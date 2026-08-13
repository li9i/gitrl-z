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

private static Gee.Collection<string> existing(string[] names)
{
	var set = new Gee.HashSet<string>();

	foreach (var n in names)
	{
		set.add(n);
	}

	return set;
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

		assert_cmpstr(Gitrlz.ResetPreview.command_for(plan, "main", existing({"main", "feature"})),
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

		assert_cmpstr(Gitrlz.ResetPreview.command_for(plan, "main", existing({"main"})),
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

		assert_cmpstr(Gitrlz.ResetPreview.command_for(plan, "main", existing({"main", "feature"})),
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

		assert_cmpstr(Gitrlz.ResetPreview.command_for(plan, null, existing({"main", "feature", "bugfix"})),
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
	assert_cmpstr(Gitrlz.ResetPreview.command_for(plan, "main", existing({"main"})),
	              CompareOperator.EQ, "");
}

private static void test_command_absent_branch_is_recreated()
{
	try
	{
		var plan = new Gitrlz.ResetPlan();
		plan.toggle("main", oid(A));
		plan.toggle("feature", oid(B));
		plan.toggle("ghost", oid(C));

		assert_cmpstr(
			Gitrlz.ResetPreview.command_for(plan, "main", existing({"main", "feature"})),
			CompareOperator.EQ,
			"git branch -f feature bbbbbbb; " +
			"git branch ghost ccccccc; " +
			"git reset --hard aaaaaaa");
	}
	catch (Error e) { Test.fail_printf("fixture failed: %s", e.message); }
}

private static void test_tips_move_a_planned_branch_off_its_old_commit()
{
	try
	{
		var t = tips({"main", A, "feature", B});

		var plan = new Gitrlz.ResetPlan();
		plan.toggle("feature", oid(C));

		var result = Gitrlz.ResetPreview.preview_tips(t, plan);

		assert_cmpint(result.length, CompareOperator.EQ, 2);
		assert_true(contains_oid(result, oid(A)));
		assert_true(contains_oid(result, oid(C)));
		assert_false(contains_oid(result, oid(B)));
	}
	catch (Error e) { Test.fail_printf("fixture failed: %s", e.message); }
}

private static void test_tips_keep_a_branch_that_is_not_planned()
{
	try
	{
		var t = tips({"main", A, "feature", B});

		var plan = new Gitrlz.ResetPlan();
		plan.toggle("main", oid(C));

		var result = Gitrlz.ResetPreview.preview_tips(t, plan);

		assert_cmpint(result.length, CompareOperator.EQ, 2);
		assert_true(contains_oid(result, oid(B)));
		assert_true(contains_oid(result, oid(C)));
	}
	catch (Error e) { Test.fail_printf("fixture failed: %s", e.message); }
}

private static void test_tips_recreate_a_branch_that_is_gone()
{
	try
	{
		var t = tips({"main", A});

		var plan = new Gitrlz.ResetPlan();
		plan.toggle("ghost", oid(B));

		var result = Gitrlz.ResetPreview.preview_tips(t, plan);

		assert_cmpint(result.length, CompareOperator.EQ, 2);
		assert_true(contains_oid(result, oid(A)));
		assert_true(contains_oid(result, oid(B)));
	}
	catch (Error e) { Test.fail_printf("fixture failed: %s", e.message); }
}

private static void test_tips_dedupe_a_target_that_is_already_a_tip()
{
	try
	{
		var t = tips({"main", A, "feature", B});

		var plan = new Gitrlz.ResetPlan();
		plan.toggle("main", oid(B));

		var result = Gitrlz.ResetPreview.preview_tips(t, plan);

		assert_cmpint(result.length, CompareOperator.EQ, 1);
		assert_true(contains_oid(result, oid(B)));

		var same = new Gitrlz.ResetPlan();
		same.toggle("main", oid(A));
		var unmoved = Gitrlz.ResetPreview.preview_tips(t, same);
		assert_cmpint(unmoved.length, CompareOperator.EQ, 2);
		assert_true(contains_oid(unmoved, oid(A)));
		assert_true(contains_oid(unmoved, oid(B)));
	}
	catch (Error e) { Test.fail_printf("fixture failed: %s", e.message); }
}

private static void test_tips_keep_the_commit_the_session_started_on()
{
	try
	{
		var t = tips({"main", A});
		var plan = new Gitrlz.ResetPlan();

		var result = Gitrlz.ResetPreview.preview_tips(t, plan, oid(B));

		assert_cmpint(result.length, CompareOperator.EQ, 2);
		assert_true(contains_oid(result, oid(A)));
		assert_true(contains_oid(result, oid(B)));

		var untouched = Gitrlz.ResetPreview.preview_tips(t, plan, oid(A));
		assert_cmpint(untouched.length, CompareOperator.EQ, 1);
		assert_true(contains_oid(untouched, oid(A)));
	}
	catch (Error e) { Test.fail_printf("fixture failed: %s", e.message); }
}

private static void test_tips_drop_the_session_start_once_a_plan_exists()
{
	try
	{
		var t = tips({"main", A});

		var plan = new Gitrlz.ResetPlan();
		plan.toggle("main", oid(C));

		var result = Gitrlz.ResetPreview.preview_tips(t, plan, oid(A));

		assert_cmpint(result.length, CompareOperator.EQ, 1);
		assert_true(contains_oid(result, oid(C)));
		assert_false(contains_oid(result, oid(A)));
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

private static void test_target_absent_branch_is_recoverable()
{
	try
	{
		var t = tips({"feature", A});

		assert_cmpstr(Gitrlz.ResetPreview.target_branch_for("all", "ghost", t),
		              CompareOperator.EQ, "ghost");
		assert_cmpstr(Gitrlz.ResetPreview.target_branch_for("ghost", null, t),
		              CompareOperator.EQ, "ghost");

		assert_null(Gitrlz.ResetPreview.target_branch_for("all", null, t));
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
	Test.add_func("/gitrlz/reset-preview/command-absent-recreated", test_command_absent_branch_is_recreated);
	Test.add_func("/gitrlz/reset-preview/tips-move-planned", test_tips_move_a_planned_branch_off_its_old_commit);
	Test.add_func("/gitrlz/reset-preview/tips-keep-unplanned", test_tips_keep_a_branch_that_is_not_planned);
	Test.add_func("/gitrlz/reset-preview/tips-recreate-gone", test_tips_recreate_a_branch_that_is_gone);
	Test.add_func("/gitrlz/reset-preview/tips-dedupe-target", test_tips_dedupe_a_target_that_is_already_a_tip);
	Test.add_func("/gitrlz/reset-preview/tips-keep-start", test_tips_keep_the_commit_the_session_started_on);
	Test.add_func("/gitrlz/reset-preview/tips-drop-start-with-plan", test_tips_drop_the_session_start_once_a_plan_exists);
	Test.add_func("/gitrlz/reset-preview/target-branch-view", test_target_branch_view_uses_the_view);
	Test.add_func("/gitrlz/reset-preview/target-all-view", test_target_all_view_uses_the_row_branch);
	Test.add_func("/gitrlz/reset-preview/target-branchless", test_target_branchless_row_is_not_togglable);
	Test.add_func("/gitrlz/reset-preview/target-absent", test_target_absent_branch_is_recoverable);

	return Test.run();
}

}
