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

private static Gitg.Repository open_repo(Repo repo) throws Error
{
	var location = Gitrlz.Application.discover_repository(repo.path);
	assert_nonnull(location);
	return Gitrlz.Repository.open(location);
}

private static void test_single_branch_is_the_first_colour()
{
	try
	{
		var repo = Repo.create();
		repo.commit("first");
		repo.commit("second");

		var repository = open_repo(repo);
		var tips = Gitrlz.Repository.branch_tips(repository);
		var colours = Gitrlz.BranchColours.map(repository, tips);

		assert_true(colours.has_key("main"));
		assert_cmpint(colours["main"], CompareOperator.EQ, 0);

		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_diverged_branches_get_distinct_colours()
{
	try
	{
		var repo = Repo.create();
		repo.commit("base");
		repo.branch("feature");
		repo.checkout("feature");
		repo.commit("feature work", "feature.txt");
		repo.checkout("main");
		repo.commit("main work", "main.txt");

		var repository = open_repo(repo);
		var tips = Gitrlz.Repository.branch_tips(repository);
		var colours = Gitrlz.BranchColours.map(repository, tips);

		assert_true(colours.has_key("main"));
		assert_true(colours.has_key("feature"));

		assert_cmpint(colours["main"], CompareOperator.NE, colours["feature"]);

		assert_cmpint(colours["main"], CompareOperator.GE, 0);
		assert_cmpint(colours["feature"], CompareOperator.GE, 0);

		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_index_equals_the_walks_own_lane_colour()
{
	try
	{
		var repo = Repo.create();
		repo.commit("base");
		repo.branch("feature");
		repo.checkout("feature");
		repo.commit("feature work", "feature.txt");
		repo.checkout("main");
		repo.commit("main work", "main.txt");

		var repository = open_repo(repo);
		var tips = Gitrlz.Repository.branch_tips(repository);
		var colours = Gitrlz.BranchColours.map(repository, tips);

		var walker = new Ggit.RevisionWalker(repository);
		walker.reset();
		walker.set_sort_mode(Ggit.SortMode.TOPOLOGICAL | Ggit.SortMode.TIME);

		var roots = new Gee.HashSet<Ggit.OId>((Gee.HashDataFunc<Ggit.OId>)Ggit.OId.hash,
		                                      (Gee.EqualDataFunc<Ggit.OId>)Ggit.OId.equal);

		foreach (var entry in tips.entries)
		{
			walker.push(entry.value);
			roots.add(entry.value);
		}

		var lanes = new Gitg.Lanes();
		lanes.reset(new Ggit.OId[0], roots);

		var seen = new Gee.HashMap<string, int>();

		while (true)
		{
			var id = walker.next();
			if (id == null)
			{
				break;
			}

			var commit = repository.lookup<Gitg.Commit>(id);

			SList<Gitg.Lane> lns;
			int mylane;

			if (lanes.next(commit, out lns, out mylane, true))
			{
				commit.update_lanes((owned)lns, mylane);
				seen[commit.get_id().to_string()] = (int)commit.lane.color.idx;
			}
		}

		foreach (var branch in colours.keys)
		{
			var tip = tips[branch].to_string();
			assert_true(seen.has_key(tip));
			assert_cmpint(colours[branch], CompareOperator.EQ, seen[tip]);
		}

		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_long_history_with_collapse_does_not_crash()
{
	try
	{
		var repo = Repo.create();

		var root = repo.commit_at(1, "base");
		repo.commit_at(2, "m1", "main.txt");
		repo.git({"branch", "behind"});

		for (var i = 2; i <= 61; i++)
		{
			repo.commit_at(i + 1, "main %d".printf(i), "main.txt");
		}

		repo.git({"branch", "feature", root});
		repo.checkout("feature");
		repo.commit_at(63, "feature work", "feature.txt");

		var repository = open_repo(repo);
		var tips = Gitrlz.Repository.branch_tips(repository);
		var colours = Gitrlz.BranchColours.map(repository, tips);

		assert_true(colours.has_key("main"));
		assert_true(colours.has_key("feature"));
		assert_true(colours.has_key("behind"));

		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

public static int main(string[] args)
{
	Test.init(ref args);

	Test.add_func("/gitrlz/branch-colours/single-is-first", test_single_branch_is_the_first_colour);
	Test.add_func("/gitrlz/branch-colours/diverged-distinct", test_diverged_branches_get_distinct_colours);
	Test.add_func("/gitrlz/branch-colours/index-equals-lane-colour", test_index_equals_the_walks_own_lane_colour);
	Test.add_func("/gitrlz/branch-colours/long-history-no-crash", test_long_history_with_collapse_does_not_crash);

	return Test.run();
}

}
