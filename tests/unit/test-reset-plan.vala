/*
 * This file is part of gitrl-z
 *
 * Copyright (C) 2026 alexandros filotheou
 *
 * gitrl-z is free software: you can redistribute it and/or modify it under the
 * terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 2 of the License, or (at your option) any later
 * version.
 *
 * gitrl-z is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
 * details.
 */

/*
 * The multi-branch reset plan (spec FR-148, FR-152, IC 4.1).
 *
 * Pure logic: no repository, no widget. Commits are stand-in OIds built from
 * hex strings, because the plan cares only about branch names and commit
 * identity, not about anything the objects actually contain.
 */

namespace GitrlzTest
{

private static Ggit.OId oid(string hex) throws Error
{
	return new Ggit.OId.from_string(hex);
}

// Four distinct, valid 40-hex ids to move branches between.
private const string A = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
private const string B = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
private const string C = "cccccccccccccccccccccccccccccccccccccccc";
private const string D = "dddddddddddddddddddddddddddddddddddddddd";

private static void test_toggle_adds_a_new_branch()
{
	try
	{
		var plan = new Gitrlz.ResetPlan();

		assert_true(plan.is_empty());

		plan.toggle("feature", oid(A));

		assert_cmpint(plan.size, CompareOperator.EQ, 1);
		assert_false(plan.is_empty());
		assert_true(plan.contains("feature", oid(A)));
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_toggle_same_row_removes_the_branch()
{
	try
	{
		var plan = new Gitrlz.ResetPlan();

		plan.toggle("feature", oid(A));
		plan.toggle("feature", oid(A));

		assert_true(plan.is_empty());
		assert_false(plan.contains("feature", oid(A)));
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_toggle_moves_the_target_within_a_branch()
{
	try
	{
		var plan = new Gitrlz.ResetPlan();

		plan.toggle("feature", oid(A));
		// A different row in the same branch moves the target, it does not add
		// a second entry: a branch has one position.
		plan.toggle("feature", oid(B));

		assert_cmpint(plan.size, CompareOperator.EQ, 1);
		assert_false(plan.contains("feature", oid(A)));
		assert_true(plan.contains("feature", oid(B)));
		assert_cmpstr(plan.target_for("feature").to_string(), CompareOperator.EQ, B);
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_branches_are_independent()
{
	try
	{
		var plan = new Gitrlz.ResetPlan();

		plan.toggle("feature", oid(A));
		plan.toggle("main", oid(B));

		assert_cmpint(plan.size, CompareOperator.EQ, 2);

		// Toggling one branch off leaves the other untouched.
		plan.toggle("feature", oid(A));

		assert_cmpint(plan.size, CompareOperator.EQ, 1);
		assert_false(plan.contains("feature", oid(A)));
		assert_true(plan.contains("main", oid(B)));
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_contains_distinguishes_the_commit()
{
	try
	{
		var plan = new Gitrlz.ResetPlan();

		plan.toggle("feature", oid(A));

		// Present, but at a different commit: not a match. Only the row that
		// put the branch in the plan is the planned one.
		assert_true(plan.contains("feature", oid(A)));
		assert_false(plan.contains("feature", oid(B)));
		assert_false(plan.contains("main", oid(A)));
		assert_null(plan.target_for("main"));
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_branches_come_back_sorted()
{
	try
	{
		var plan = new Gitrlz.ResetPlan();

		plan.toggle("main", oid(A));
		plan.toggle("feature", oid(B));
		plan.toggle("bugfix", oid(C));

		var names = plan.branches();

		assert_cmpint(names.size, CompareOperator.EQ, 3);
		assert_cmpstr(names[0], CompareOperator.EQ, "bugfix");
		assert_cmpstr(names[1], CompareOperator.EQ, "feature");
		assert_cmpstr(names[2], CompareOperator.EQ, "main");
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_prune_drops_absent_keeps_present()
{
	try
	{
		var plan = new Gitrlz.ResetPlan();

		plan.toggle("feature", oid(A));
		plan.toggle("main", oid(B));
		plan.toggle("gone", oid(C));

		var present = new Gee.ArrayList<string>();
		present.add("feature");
		present.add("main");

		plan.prune(present);

		assert_cmpint(plan.size, CompareOperator.EQ, 2);
		assert_true(plan.contains("feature", oid(A)));
		assert_true(plan.contains("main", oid(B)));
		assert_false(plan.contains("gone", oid(C)));
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_set_target_keeps_other_branches()
{
	try
	{
		var plan = new Gitrlz.ResetPlan();

		plan.toggle("feature", oid(A));
		plan.toggle("main", oid(B));
		assert_cmpint(plan.size, CompareOperator.EQ, 2);

		// A keyboard select sets the landed row's branch, leaving the others in
		// the plan: arrow travel is like a click on that row, not a wipe.
		plan.set_target("feature", oid(C));

		assert_cmpint(plan.size, CompareOperator.EQ, 2);
		assert_true(plan.contains("feature", oid(C)));
		assert_true(plan.contains("main", oid(B)));
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_set_target_same_row_keeps_it()
{
	try
	{
		var plan = new Gitrlz.ResetPlan();

		// Unlike a toggle, selecting the same branch and commit twice keeps it
		// in the plan rather than removing it: keyboard travel selects, it
		// never deselects.
		plan.set_target("feature", oid(A));
		plan.set_target("feature", oid(A));

		assert_cmpint(plan.size, CompareOperator.EQ, 1);
		assert_true(plan.contains("feature", oid(A)));
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_set_only_replaces_the_whole_plan()
{
	try
	{
		var plan = new Gitrlz.ResetPlan();

		plan.toggle("feature", oid(A));
		plan.toggle("main", oid(B));
		assert_cmpint(plan.size, CompareOperator.EQ, 2);

		// The HEAD view's plain selection: one row drops every other branch and
		// keeps only the chosen one, unlike set_target which keeps the others.
		plan.set_only("main", oid(C));

		assert_cmpint(plan.size, CompareOperator.EQ, 1);
		assert_true(plan.contains("main", oid(C)));
		assert_false(plan.contains("feature", oid(A)));
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

public static int main(string[] args)
{
	Test.init(ref args);

	Test.add_func("/gitrlz/reset-plan/toggle-adds", test_toggle_adds_a_new_branch);
	Test.add_func("/gitrlz/reset-plan/toggle-same-removes", test_toggle_same_row_removes_the_branch);
	Test.add_func("/gitrlz/reset-plan/toggle-moves", test_toggle_moves_the_target_within_a_branch);
	Test.add_func("/gitrlz/reset-plan/branches-independent", test_branches_are_independent);
	Test.add_func("/gitrlz/reset-plan/contains-distinguishes-commit", test_contains_distinguishes_the_commit);
	Test.add_func("/gitrlz/reset-plan/branches-sorted", test_branches_come_back_sorted);
	Test.add_func("/gitrlz/reset-plan/prune", test_prune_drops_absent_keeps_present);
	Test.add_func("/gitrlz/reset-plan/set-target-keeps-others", test_set_target_keeps_other_branches);
	Test.add_func("/gitrlz/reset-plan/set-target-same-keeps", test_set_target_same_row_keeps_it);
	Test.add_func("/gitrlz/reset-plan/set-only-replaces-all", test_set_only_replaces_the_whole_plan);

	return Test.run();
}

}

// ex:set ts=4 noet:
