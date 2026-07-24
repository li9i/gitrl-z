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
 * Reading reflogs through Ggit (spec IC-103), and the repository layer
 * beneath it (IC-100 to IC-105).
 *
 * Ported from the Python implementation's tests/test_reflog.py and
 * tests/test_repository.py. One thing here has no Python counterpart and
 * matters more than the rest: a differential test against the git binary.
 * The spec asserts that libgit2 numbers reflog entries with 0 as the newest,
 * matching HEAD@{0}; that is documented but it is an assumption, and every
 * selector in the UI depends on it.
 */

namespace GitrlzTest
{

private static Gitg.Repository open_fixture(Repo repo) throws Error
{
	var location = Gitrlz.Application.discover_repository(repo.path);
	assert_nonnull(location);
	return Gitrlz.Repository.open(location);
}

private static void test_branch_reflog()
{
	try
	{
		var repo = Repo.create();

		var first = repo.commit("first");
		repo.branch("feature");
		repo.checkout("feature");
		var second = repo.commit("second");

		var entries = Gitrlz.Reflog.read(open_fixture(repo), "feature");

		assert_cmpint(entries.size, CompareOperator.EQ, 2);

		assert_cmpstr(entries[0].selector, CompareOperator.EQ, "feature@{0}");
		assert_cmpstr(entries[1].selector, CompareOperator.EQ, "feature@{1}");

		assert_cmpstr(entries[0].new_id.to_string(), CompareOperator.EQ, second);
		assert_cmpstr(entries[0].message, CompareOperator.EQ, "commit: second");

		assert_cmpstr(entries[1].new_id.to_string(), CompareOperator.EQ, first);
		assert_cmpstr(entries[1].message, CompareOperator.EQ, "branch: Created from main");

		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_head_reflog_across_operations()
{
	try
	{
		var repo = Repo.create();

		var first = repo.commit("first");
		var second = repo.commit("second");
		repo.branch("fix");
		repo.checkout("fix");
		repo.reset(first);
		repo.checkout("main");

		var entries = Gitrlz.Reflog.read(open_fixture(repo), "HEAD");

		assert_cmpint(entries.size, CompareOperator.EQ, 5);

		assert_cmpstr(entries[0].selector, CompareOperator.EQ, "HEAD@{0}");
		assert_cmpstr(entries[4].selector, CompareOperator.EQ, "HEAD@{4}");

		// Newest first, as git prints a reflog.
		assert_cmpstr(entries[0].message, CompareOperator.EQ,
		              "checkout: moving from fix to main");
		assert_cmpstr(entries[0].new_id.to_string(), CompareOperator.EQ, second);

		assert_cmpstr(entries[1].message, CompareOperator.EQ, "reset: moving to " + first);
		assert_cmpstr(entries[1].new_id.to_string(), CompareOperator.EQ, first);

		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_matches_git_reflog_output()
{
	// The load-bearing assumption of IC-103, checked rather than trusted:
	// that entry index 0 is the newest, so `HEAD@{n}` built from the index
	// names the same commit git names. If libgit2 ordered these the other
	// way, every selector and every row in the UI would be silently wrong,
	// and nothing else in the suite would notice.
	try
	{
		var repo = Repo.create();

		repo.commit("first");
		repo.commit("second");
		repo.branch("fix");
		repo.checkout("fix");
		repo.commit("third");
		repo.checkout("main");

		var repository = open_fixture(repo);
		var entries = Gitrlz.Reflog.read(repository, "HEAD");

		// %H is the full hash, %gs the reflog subject: the same two fields
		// the Python implementation read, from the same source of truth.
		var expected = repo.git({"reflog", "show", "HEAD", "--format=%H%x1f%gs"});
		var lines = expected.strip().split("\n");

		assert_cmpint(entries.size, CompareOperator.EQ, lines.length);

		for (var i = 0; i < lines.length; i++)
		{
			var parts = lines[i].split("\x1f");

			assert_cmpstr(entries[i].new_id.to_string(), CompareOperator.EQ, parts[0]);
			assert_cmpstr(entries[i].message, CompareOperator.EQ, parts[1]);
		}

		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_stash_reflog()
{
	try
	{
		var repo = Repo.create();

		repo.commit("first");

		FileUtils.set_contents(repo.path.get_child("file.txt").get_path(), "dirty\n");
		repo.stash("work in progress");

		var repository = open_fixture(repo);

		assert_true(Gitrlz.Repository.has_stash(repository));

		var entries = Gitrlz.Reflog.read(repository, "stash");

		assert_cmpint(entries.size, CompareOperator.EQ, 1);
		assert_cmpstr(entries[0].selector, CompareOperator.EQ, "stash@{0}");
		assert_true(entries[0].message.contains("work in progress"));

		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_no_stash_no_entries()
{
	try
	{
		var repo = Repo.create();
		repo.commit("first");

		var repository = open_fixture(repo);

		// P-FR-8: no stash, no sidebar entry.
		assert_false(Gitrlz.Repository.has_stash(repository));

		// And reading it anyway is empty rather than an error.
		var entries = Gitrlz.Reflog.read(repository, "stash");
		assert_cmpint(entries.size, CompareOperator.EQ, 0);

		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_unborn_head()
{
	// P-FR-27: a repository with no commits opens normally — empty branch
	// list, no stash, no entries, and no error anywhere.
	try
	{
		var dir = DirUtils.make_tmp("gitrlz-unborn-XXXXXX");
		var repo = new Repo(File.new_for_path(dir));

		var repository = open_fixture(repo);

		var entries = Gitrlz.Reflog.read(repository, "HEAD");
		assert_cmpint(entries.size, CompareOperator.EQ, 0);

		assert_cmpint(Gitrlz.Repository.list_branches(repository).size, CompareOperator.EQ, 0);
		assert_false(Gitrlz.Repository.has_stash(repository));

		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_missing_ref_is_empty_not_an_error()
{
	try
	{
		var repo = Repo.create();
		repo.commit("first");

		var entries = Gitrlz.Reflog.read(open_fixture(repo), "no-such-branch");

		assert_cmpint(entries.size, CompareOperator.EQ, 0);

		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_message_with_unicode_and_percent()
{
	try
	{
		var repo = Repo.create();

		repo.commit("100% café ☕");

		var entries = Gitrlz.Reflog.read(open_fixture(repo), "HEAD");

		assert_cmpint(entries.size, CompareOperator.EQ, 1);
		assert_true(entries[0].message.contains("100% café ☕"));

		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_branches_sorted_case_insensitively()
{
	// P-FR-7. git's own order is bytewise, which would put Zebra before
	// apple; the sidebar wants them mixed as a reader expects.
	try
	{
		var repo = Repo.create();
		repo.commit("first");

		repo.branch("Zebra");
		repo.branch("apple");
		repo.branch("Mango");

		var branches = Gitrlz.Repository.list_branches(open_fixture(repo));

		assert_cmpint(branches.size, CompareOperator.EQ, 4);
		assert_cmpstr(branches[0], CompareOperator.EQ, "apple");
		assert_cmpstr(branches[1], CompareOperator.EQ, "main");
		assert_cmpstr(branches[2], CompareOperator.EQ, "Mango");
		assert_cmpstr(branches[3], CompareOperator.EQ, "Zebra");

		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_current_branch_and_detached_head()
{
	try
	{
		var repo = Repo.create();
		var first = repo.commit("first");
		repo.commit("second");

		var repository = open_fixture(repo);
		assert_cmpstr(Gitrlz.Repository.current_branch(repository),
		              CompareOperator.EQ, "main");

		// IC-105: detached HEAD has no current branch.
		repo.checkout(first);

		var detached = open_fixture(repo);
		assert_null(Gitrlz.Repository.current_branch(detached));

		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_branch_tips()
{
	try
	{
		var repo = Repo.create();

		var first = repo.commit("first");
		repo.branch("feature");
		var second = repo.commit("second");

		var tips = Gitrlz.Repository.branch_tips(open_fixture(repo));

		assert_cmpint(tips.size, CompareOperator.EQ, 2);
		assert_cmpstr(tips["main"].to_string(), CompareOperator.EQ, second);
		assert_cmpstr(tips["feature"].to_string(), CompareOperator.EQ, first);

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

	Test.add_func("/gitrlz/reflog/branch-reflog", test_branch_reflog);
	Test.add_func("/gitrlz/reflog/head-across-operations", test_head_reflog_across_operations);
	Test.add_func("/gitrlz/reflog/matches-git-reflog-output", test_matches_git_reflog_output);
	Test.add_func("/gitrlz/reflog/stash-reflog", test_stash_reflog);
	Test.add_func("/gitrlz/reflog/no-stash", test_no_stash_no_entries);
	Test.add_func("/gitrlz/reflog/unborn-head", test_unborn_head);
	Test.add_func("/gitrlz/reflog/missing-ref", test_missing_ref_is_empty_not_an_error);
	Test.add_func("/gitrlz/reflog/unicode-and-percent", test_message_with_unicode_and_percent);
	Test.add_func("/gitrlz/repository/branches-sorted", test_branches_sorted_case_insensitively);
	Test.add_func("/gitrlz/repository/current-branch", test_current_branch_and_detached_head);
	Test.add_func("/gitrlz/repository/branch-tips", test_branch_tips);

	return Test.run();
}

}

// ex:set ts=4 noet:
