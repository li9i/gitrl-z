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

private static Gitg.Repository open_fixture(Repo repo) throws Error
{
	var location = Gitrlz.Application.discover_repository(repo.path);
	assert_nonnull(location);
	return Gitrlz.Repository.open(location);
}

private static Gee.List<Gitrlz.TimelineState> states_of(Repo repo) throws Error
{
	var repository = open_fixture(repo);

	return Gitrlz.Timeline.read(repository, Gitrlz.Repository.list_branches(repository));
}

private static void test_states_run_oldest_first()
{
	try
	{
		var repo = Repo.create();
		var first = repo.commit_at(1, "first");
		var second = repo.commit_at(2, "second");

		var states = states_of(repo);

		assert_cmpint(states.size, CompareOperator.EQ, 2);
		assert_cmpstr(states[0].position_of("main").to_string(), CompareOperator.EQ, first);
		assert_cmpstr(states[1].position_of("main").to_string(), CompareOperator.EQ, second);
		assert_true(states[0].when.compare(states[1].when) < 0);

		repo.remove();
	}
	catch (Error e) { Test.fail_printf("fixture failed: %s", e.message); }
}

private static void test_a_branch_is_absent_before_it_was_made()
{
	try
	{
		var repo = Repo.create();
		repo.commit_at(1, "first");
		repo.commit_at(2, "second");
		repo.branch("feature");

		var states = states_of(repo);

		assert_cmpint(states.size, CompareOperator.EQ, 3);
		assert_false(states[0].holds("feature"));
		assert_false(states[1].holds("feature"));
		assert_true(states[2].holds("feature"));

		repo.remove();
	}
	catch (Error e) { Test.fail_printf("fixture failed: %s", e.message); }
}

private static void test_a_branch_keeps_its_place_until_it_moves()
{
	try
	{
		var repo = Repo.create();
		var first = repo.commit_at(1, "first");
		repo.branch("feature");
		repo.commit_at(2, "second");

		var states = states_of(repo);
		var last = states[states.size - 1];

		assert_cmpstr(last.position_of("feature").to_string(), CompareOperator.EQ, first);

		repo.remove();
	}
	catch (Error e) { Test.fail_printf("fixture failed: %s", e.message); }
}

private static void test_entries_sharing_an_instant_fold_into_one_state()
{
	try
	{
		var repo = Repo.create();
		repo.commit_at(1, "first");
		repo.branch("feature");
		repo.checkout("feature");
		repo.commit_at(2, "on feature");
		repo.checkout("main");
		repo.commit_at(2, "on main");

		var states = states_of(repo);
		var instants = new Gee.HashSet<int64?>();

		foreach (var state in states)
		{
			assert_false(instants.contains(state.when.to_unix()));
			instants.add(state.when.to_unix());
		}

		repo.remove();
	}
	catch (Error e) { Test.fail_printf("fixture failed: %s", e.message); }
}

private static void test_plan_moves_a_branch_that_stood_elsewhere()
{
	try
	{
		var repo = Repo.create();
		var first = repo.commit_at(1, "first");
		repo.commit_at(2, "second");

		var repository = open_fixture(repo);
		var states = states_of(repo);
		var plan = Gitrlz.Timeline.plan_for(states[0], Gitrlz.Repository.branch_tips(repository));

		assert_cmpstr(plan.target_for("main").to_string(), CompareOperator.EQ, first);

		repo.remove();
	}
	catch (Error e) { Test.fail_printf("fixture failed: %s", e.message); }
}

private static void test_plan_deletes_a_branch_that_did_not_exist()
{
	try
	{
		var repo = Repo.create();
		repo.commit_at(1, "first");
		repo.commit_at(2, "second");
		repo.branch("feature");

		var repository = open_fixture(repo);
		var states = states_of(repo);
		var plan = Gitrlz.Timeline.plan_for(states[0], Gitrlz.Repository.branch_tips(repository));

		assert_true(plan.is_deleted("feature"));
		assert_null(plan.target_for("feature"));

		repo.remove();
	}
	catch (Error e) { Test.fail_printf("fixture failed: %s", e.message); }
}

private static void test_plan_leaves_out_a_branch_already_in_place()
{
	try
	{
		var repo = Repo.create();
		repo.commit_at(1, "first");
		repo.commit_at(2, "second");

		var repository = open_fixture(repo);
		var states = states_of(repo);
		var plan = Gitrlz.Timeline.plan_for(states[states.size - 1],
		                                    Gitrlz.Repository.branch_tips(repository));

		assert_true(plan.is_empty());

		repo.remove();
	}
	catch (Error e) { Test.fail_printf("fixture failed: %s", e.message); }
}

private static void test_marks_keep_the_time_between_states()
{
	try
	{
		var repo = Repo.create();
		repo.commit_at(1, "first");
		repo.commit_at(2, "second");
		repo.commit_at(4, "third");

		var axis = new Gitrlz.TimelineAxis(states_of(repo));

		assert_cmpint((int)(axis.mark(1) - axis.mark(0)), CompareOperator.EQ, 86400);
		assert_cmpint((int)(axis.mark(2) - axis.mark(1)), CompareOperator.EQ, 172800);

		repo.remove();
	}
	catch (Error e) { Test.fail_printf("fixture failed: %s", e.message); }
}

private static void test_marks_squash_a_long_idle_gap()
{
	try
	{
		var repo = Repo.create();
		repo.commit_at(1, "first");
		repo.commit_at(2, "second");
		repo.commit_at(100, "third");

		var axis = new Gitrlz.TimelineAxis(states_of(repo));

		assert_cmpint((int)(axis.mark(1) - axis.mark(0)), CompareOperator.EQ, 86400);
		assert_cmpint((int)(axis.mark(2) - axis.mark(1)), CompareOperator.EQ, 6 * 86400);

		repo.remove();
	}
	catch (Error e) { Test.fail_printf("fixture failed: %s", e.message); }
}

public static int main(string[] args)
{
	Test.init(ref args);

	Test.add_func("/gitrlz/timeline/oldest-first", test_states_run_oldest_first);
	Test.add_func("/gitrlz/timeline/absent-before-made", test_a_branch_is_absent_before_it_was_made);
	Test.add_func("/gitrlz/timeline/keeps-its-place", test_a_branch_keeps_its_place_until_it_moves);
	Test.add_func("/gitrlz/timeline/instants-fold", test_entries_sharing_an_instant_fold_into_one_state);
	Test.add_func("/gitrlz/timeline/plan-moves", test_plan_moves_a_branch_that_stood_elsewhere);
	Test.add_func("/gitrlz/timeline/plan-deletes", test_plan_deletes_a_branch_that_did_not_exist);
	Test.add_func("/gitrlz/timeline/plan-empty-at-now", test_plan_leaves_out_a_branch_already_in_place);
	Test.add_func("/gitrlz/timeline/marks-follow-time", test_marks_keep_the_time_between_states);
	Test.add_func("/gitrlz/timeline/marks-squash-idle", test_marks_squash_a_long_idle_gap);

	return Test.run();
}

}
