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
 * The plan's command, tip set and target resolution (spec FR-148 to FR-150,
 * IC 4.2). Pure: stand-in OIds, no repository.
 */

namespace GitrlzTest
{

private const string A = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
private const string B = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
private const string C = "cccccccccccccccccccccccccccccccccccccccc";

private static Ggit.OId oid(string hex) throws Error
{
	return new Ggit.OId.from_string(hex);
}

private static Gee.Map<string, Ggit.OId> tips(string[] pairs) throws Error
{
	var map = new Gee.HashMap<string, Ggit.OId>();

	for (var i = 0; i < pairs.length; i += 2)
	{
		map[pairs[i]] = oid(pairs[i + 1]);
	}

	return map;
}

private static bool contains_oid(Ggit.OId[] arr, Ggit.OId want)
{
	foreach (var o in arr)
	{
		if (o.equal(want))
		{
			return true;
		}
	}

	return false;
}

private static void test_command_non_current_branch_uses_branch_f()
{
	try
	{
		var plan = new Gitrlz.ResetPlan();
		plan.toggle("feature", oid(A));

		assert_cmpstr(Gitrlz.ResetPreview.command_for(plan, "main"),
		              CompareOperator.EQ, "git branch -f feature aaaaaaa");
	}
	catch (Error e) { Test.fail_printf("fixture failed: %s", e.message); }
}

private static void test_command_current_branch_uses_reset()
{
	try
	{
		var plan = new Gitrlz.ResetPlan();
		plan.toggle("main", oid(A));

		assert_cmpstr(Gitrlz.ResetPreview.command_for(plan, "main"),
		              CompareOperator.EQ, "git reset --hard aaaaaaa");
	}
	catch (Error e) { Test.fail_printf("fixture failed: %s", e.message); }
}

private static void test_command_reset_line_comes_last()
{
	try
	{
		var plan = new Gitrlz.ResetPlan();
		plan.toggle("feature", oid(A));
		plan.toggle("main", oid(B));

		assert_cmpstr(Gitrlz.ResetPreview.command_for(plan, "main"),
		              CompareOperator.EQ,
		              "git branch -f feature aaaaaaa; git reset --hard bbbbbbb");
	}
	catch (Error e) { Test.fail_printf("fixture failed: %s", e.message); }
}

private static void test_command_branch_f_lines_are_ordered()
{
	try
	{
		var plan = new Gitrlz.ResetPlan();
		plan.toggle("main", oid(A));
		plan.toggle("feature", oid(B));
		plan.toggle("bugfix", oid(C));

		// Detached HEAD: every move is branch -f, in branch-name order.
		assert_cmpstr(Gitrlz.ResetPreview.command_for(plan, null),
		              CompareOperator.EQ,
		              "git branch -f bugfix ccccccc; " +
		              "git branch -f feature bbbbbbb; " +
		              "git branch -f main aaaaaaa");
	}
	catch (Error e) { Test.fail_printf("fixture failed: %s", e.message); }
}

private static void test_command_empty_plan_is_empty_string()
{
	var plan = new Gitrlz.ResetPlan();
	assert_cmpstr(Gitrlz.ResetPreview.command_for(plan, "main"),
	              CompareOperator.EQ, "");
}

private static void test_tips_keep_the_tree_and_add_targets()
{
	try
	{
		var t = tips({"main", A, "feature", B});

		var plan = new Gitrlz.ResetPlan();
		plan.toggle("feature", oid(C));

		var result = Gitrlz.ResetPreview.preview_tips(t, plan);

		// The whole tree stays: both real tips are kept, and the target C is
		// added so a reset could land there without a ref reaching it.
		assert_cmpint(result.length, CompareOperator.EQ, 3);
		assert_true(contains_oid(result, oid(A)));
		assert_true(contains_oid(result, oid(B)));
		assert_true(contains_oid(result, oid(C)));
	}
	catch (Error e) { Test.fail_printf("fixture failed: %s", e.message); }
}

private static void test_tips_dedupe_a_target_that_is_already_a_tip()
{
	try
	{
		var t = tips({"main", A});

		var plan = new Gitrlz.ResetPlan();
		plan.toggle("main", oid(B));

		var result = Gitrlz.ResetPreview.preview_tips(t, plan);

		// The real tip A stays and the target B is added: two distinct commits.
		assert_cmpint(result.length, CompareOperator.EQ, 2);
		assert_true(contains_oid(result, oid(A)));
		assert_true(contains_oid(result, oid(B)));

		// A target that is already a tip is not fed to the walker twice.
		var same = new Gitrlz.ResetPlan();
		same.toggle("main", oid(A));
		var deduped = Gitrlz.ResetPreview.preview_tips(t, same);
		assert_cmpint(deduped.length, CompareOperator.EQ, 1);
		assert_true(contains_oid(deduped, oid(A)));
	}
	catch (Error e) { Test.fail_printf("fixture failed: %s", e.message); }
}

private static void test_target_branch_view_uses_the_view()
{
	try
	{
		var t = tips({"feature", A});
		assert_cmpstr(Gitrlz.ResetPreview.target_branch_for("feature", null, t),
		              CompareOperator.EQ, "feature");
	}
	catch (Error e) { Test.fail_printf("fixture failed: %s", e.message); }
}

private static void test_target_all_view_uses_the_row_branch()
{
	try
	{
		var t = tips({"feature", A});
		assert_cmpstr(Gitrlz.ResetPreview.target_branch_for("all", "feature", t),
		              CompareOperator.EQ, "feature");
	}
	catch (Error e) { Test.fail_printf("fixture failed: %s", e.message); }
}

private static void test_target_branchless_row_is_not_togglable()
{
	try
	{
		var t = tips({"feature", A});
		assert_null(Gitrlz.ResetPreview.target_branch_for("all", null, t));
	}
	catch (Error e) { Test.fail_printf("fixture failed: %s", e.message); }
}

private static void test_target_absent_branch_is_not_togglable()
{
	try
	{
		var t = tips({"feature", A});
		// A row naming a branch no longer present, in either view.
		assert_null(Gitrlz.ResetPreview.target_branch_for("all", "ghost", t));
		assert_null(Gitrlz.ResetPreview.target_branch_for("ghost", null, t));
	}
	catch (Error e) { Test.fail_printf("fixture failed: %s", e.message); }
}

public static int main(string[] args)
{
	Test.init(ref args);

	Test.add_func("/gitrlz/reset-preview/command-non-current", test_command_non_current_branch_uses_branch_f);
	Test.add_func("/gitrlz/reset-preview/command-current", test_command_current_branch_uses_reset);
	Test.add_func("/gitrlz/reset-preview/command-reset-last", test_command_reset_line_comes_last);
	Test.add_func("/gitrlz/reset-preview/command-ordered", test_command_branch_f_lines_are_ordered);
	Test.add_func("/gitrlz/reset-preview/command-empty", test_command_empty_plan_is_empty_string);
	Test.add_func("/gitrlz/reset-preview/tips-keep-tree", test_tips_keep_the_tree_and_add_targets);
	Test.add_func("/gitrlz/reset-preview/tips-dedupe-target", test_tips_dedupe_a_target_that_is_already_a_tip);
	Test.add_func("/gitrlz/reset-preview/target-branch-view", test_target_branch_view_uses_the_view);
	Test.add_func("/gitrlz/reset-preview/target-all-view", test_target_all_view_uses_the_row_branch);
	Test.add_func("/gitrlz/reset-preview/target-branchless", test_target_branchless_row_is_not_togglable);
	Test.add_func("/gitrlz/reset-preview/target-absent", test_target_absent_branch_is_not_togglable);

	return Test.run();
}

}

// ex:set ts=4 noet:
