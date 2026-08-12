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

private static Ggit.OId oid(string hex) throws Error
{
	return new Ggit.OId.from_string(hex);
}

private const string A = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
private const string B = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
private const string C = "cccccccccccccccccccccccccccccccccccccccc";

private static DateTime at(int minutes)
{
	return new DateTime.local(2026, 7, 20, 12, 0, 0).add_minutes(minutes);
}

private static Gitrlz.ReflogEntry entry(string message,
                                        Ggit.OId? new_id,
                                        Ggit.OId? old_id,
                                        DateTime? date)
{
	return new Gitrlz.ReflogEntry("HEAD", 0, new_id, old_id, message, date);
}

private static Gee.List<Gitrlz.ReflogEntry> sample() throws Error
{
	var list = new Gee.ArrayList<Gitrlz.ReflogEntry>();
	list.add(entry("commit: fourth", oid(C), oid(B), at(0)));
	list.add(entry("commit: third", oid(B), oid(A), at(-10)));
	list.add(entry("checkout: moving from main to feature", oid(A), oid(A), at(-20)));
	list.add(entry("commit: second", oid(A), null, at(-30)));
	return list;
}

private static Gitrlz.ReflogEntry top() throws Error
{
	return entry("commit: fourth", oid(C), oid(B), at(0));
}

private static Gitrlz.ReflogEntry middle() throws Error
{
	return entry("checkout: moving from main to feature", oid(A), oid(A), at(-20));
}

private static Gitg.Repository open_fixture(Repo repo) throws Error
{
	var location = Gitrlz.Application.discover_repository(repo.path);
	assert_nonnull(location);
	return Gitrlz.Repository.open(location);
}

private static void test_no_stored_entry_marks_no_row()
{
	try
	{
		assert_cmpint(Gitrlz.SessionStart.index_of(null, sample()),
		              CompareOperator.EQ, -1);
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_empty_list_marks_no_row()
{
	try
	{
		var entries = new Gee.ArrayList<Gitrlz.ReflogEntry>();

		assert_cmpint(Gitrlz.SessionStart.index_of(top(), entries),
		              CompareOperator.EQ, -1);
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_untouched_log_marks_the_top_row()
{
	try
	{
		assert_cmpint(Gitrlz.SessionStart.index_of(top(), sample()),
		              CompareOperator.EQ, 0);
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_new_entries_push_the_row_down()
{
	try
	{
		var entries = sample();
		entries.insert(0, entry("commit: sixth", oid(B), oid(A), at(20)));
		entries.insert(0, entry("commit: fifth", oid(A), oid(B), at(30)));

		assert_cmpint(Gitrlz.SessionStart.index_of(top(), entries),
		              CompareOperator.EQ, 2);
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_an_expired_tail_leaves_the_row_correct()
{
	try
	{
		var entries = sample();

		assert_cmpint(Gitrlz.SessionStart.index_of(middle(), entries),
		              CompareOperator.EQ, 2);

		entries.remove_at(3);

		assert_cmpint(Gitrlz.SessionStart.index_of(middle(), entries),
		              CompareOperator.EQ, 2);
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_any_differing_field_prevents_the_match()
{
	try
	{
		var entries = sample();

		assert_cmpint(Gitrlz.SessionStart.index_of(middle(), entries),
		              CompareOperator.EQ, 2);

		assert_cmpint(Gitrlz.SessionStart.index_of(
		                  entry("checkout: moving from main to feature",
		                        oid(C), oid(A), at(-20)),
		                  entries),
		              CompareOperator.EQ, -1);

		assert_cmpint(Gitrlz.SessionStart.index_of(
		                  entry("checkout: moving from main to feature",
		                        oid(A), oid(C), at(-20)),
		                  entries),
		              CompareOperator.EQ, -1);

		assert_cmpint(Gitrlz.SessionStart.index_of(
		                  entry("checkout: moving from feature to main",
		                        oid(A), oid(A), at(-20)),
		                  entries),
		              CompareOperator.EQ, -1);

		assert_cmpint(Gitrlz.SessionStart.index_of(
		                  entry("checkout: moving from main to feature",
		                        oid(A), oid(A), at(-21)),
		                  entries),
		              CompareOperator.EQ, -1);

		assert_cmpint(Gitrlz.SessionStart.index_of(
		                  entry("commit: second", oid(A), oid(B), at(-30)),
		                  entries),
		              CompareOperator.EQ, -1);

		assert_cmpint(Gitrlz.SessionStart.index_of(
		                  entry("commit: second", oid(A), null, at(-30)),
		                  entries),
		              CompareOperator.EQ, 3);
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_two_matching_rows_give_the_topmost()
{
	try
	{
		var entries = sample();
		entries.insert(2, middle());

		assert_cmpint(Gitrlz.SessionStart.index_of(middle(), entries),
		              CompareOperator.EQ, 2);
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_read_stores_the_newest_entry_of_each_ref()
{
	try
	{
		var repo = Repo.create();

		repo.commit("first");
		repo.branch("feature");
		repo.checkout("feature");
		var second = repo.commit("second");
		repo.checkout("main");

		FileUtils.set_contents(repo.path.get_child("file.txt").get_path(), "dirty\n");
		repo.stash("work in progress");

		var repository = open_fixture(repo);

		var start = Gitrlz.SessionStart.read(
			repository,
			Gitrlz.Repository.list_branches(repository),
			Gitrlz.Repository.has_stash(repository));

		assert_nonnull(start.entry_for("feature"));
		assert_cmpstr(start.entry_for("feature").new_id.to_string(),
		              CompareOperator.EQ, second);
		assert_cmpstr(start.entry_for("feature").message,
		              CompareOperator.EQ, "commit: second");

		assert_nonnull(start.entry_for("stash"));
		assert_true(start.entry_for("stash").message.contains("work in progress"));

		var head_log = Gitrlz.Reflog.read(repository, "HEAD");

		assert_nonnull(start.entry_for("HEAD"));
		assert_cmpstr(start.entry_for("HEAD").message,
		              CompareOperator.EQ, head_log[0].message);

		assert_cmpint(start.index_in("HEAD", head_log), CompareOperator.EQ, 0);
		assert_cmpint(start.index_in("feature",
		                             Gitrlz.Reflog.read(repository, "feature")),
		              CompareOperator.EQ, 0);
		assert_cmpint(start.index_in("stash",
		                             Gitrlz.Reflog.read(repository, "stash")),
		              CompareOperator.EQ, 0);

		assert_null(start.entry_for("later"));
		assert_cmpint(start.index_in("later", head_log), CompareOperator.EQ, -1);

		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_read_stores_nothing_for_an_absent_stash()
{
	try
	{
		var repo = Repo.create();
		repo.commit("first");

		var repository = open_fixture(repo);

		assert_false(Gitrlz.Repository.has_stash(repository));

		var start = Gitrlz.SessionStart.read(
			repository,
			Gitrlz.Repository.list_branches(repository),
			Gitrlz.Repository.has_stash(repository));

		assert_null(start.entry_for("stash"));
		assert_nonnull(start.entry_for("HEAD"));

		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_read_of_an_unborn_head_stores_nothing()
{
	try
	{
		var dir = DirUtils.make_tmp("gitrlz-unborn-XXXXXX");
		var repo = new Repo(File.new_for_path(dir));

		var repository = open_fixture(repo);

		var start = Gitrlz.SessionStart.read(
			repository,
			Gitrlz.Repository.list_branches(repository),
			Gitrlz.Repository.has_stash(repository));

		assert_null(start.entry_for("HEAD"));
		assert_cmpint(start.index_in("HEAD", Gitrlz.Reflog.read(repository, "HEAD")),
		              CompareOperator.EQ, -1);

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

	Test.add_func("/gitrlz/session-start/no-stored-entry", test_no_stored_entry_marks_no_row);
	Test.add_func("/gitrlz/session-start/empty-list", test_empty_list_marks_no_row);
	Test.add_func("/gitrlz/session-start/untouched-log", test_untouched_log_marks_the_top_row);
	Test.add_func("/gitrlz/session-start/new-entries-push-down", test_new_entries_push_the_row_down);
	Test.add_func("/gitrlz/session-start/expired-tail", test_an_expired_tail_leaves_the_row_correct);
	Test.add_func("/gitrlz/session-start/differing-field", test_any_differing_field_prevents_the_match);
	Test.add_func("/gitrlz/session-start/duplicate-rows", test_two_matching_rows_give_the_topmost);
	Test.add_func("/gitrlz/session-start/read-each-ref", test_read_stores_the_newest_entry_of_each_ref);
	Test.add_func("/gitrlz/session-start/read-no-stash", test_read_stores_nothing_for_an_absent_stash);
	Test.add_func("/gitrlz/session-start/read-unborn-head", test_read_of_an_unborn_head_stores_nothing);

	return Test.run();
}

}
