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
 * Where each ref stood when the window opened (spec FR-170, IC-168).
 *
 * The matching rule is exercised over lists built by hand, because the cases
 * that matter are a log that has grown at the front and a log that has lost
 * its tail to an expiry, and neither is convenient to drive through git. The
 * snapshot itself is taken from a fixture repository, where the only question
 * is that each ref keeps its own entry.
 */

namespace GitrlzTest
{

private static Ggit.OId oid(string hex) throws Error
{
	return new Ggit.OId.from_string(hex);
}

// Three distinct, valid 40-hex ids to build entries from.
private const string A = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
private const string B = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
private const string C = "cccccccccccccccccccccccccccccccccccccccc";

/** An instant `minutes` from a fixed reference point. */
private static DateTime at(int minutes)
{
	return new DateTime.local(2026, 7, 20, 12, 0, 0).add_minutes(minutes);
}

/**
 * An entry carrying the four fields that the match reads.
 *
 * The ref name and the index are the same for every entry here on purpose.
 * They take no part in the match, and a case that passed because of one of
 * them would be a case that fails against a real log.
 */
private static Gitrlz.ReflogEntry entry(string message,
                                        Ggit.OId? new_id,
                                        Ggit.OId? old_id,
                                        DateTime? date)
{
	return new Gitrlz.ReflogEntry("HEAD", 0, new_id, old_id, message, date);
}

/** Four entries, newest first, as Reflog.read returns them. */
private static Gee.List<Gitrlz.ReflogEntry> sample() throws Error
{
	var list = new Gee.ArrayList<Gitrlz.ReflogEntry>();
	list.add(entry("commit: fourth", oid(C), oid(B), at(0)));
	list.add(entry("commit: third", oid(B), oid(A), at(-10)));
	list.add(entry("checkout: moving from main to feature", oid(A), oid(A), at(-20)));
	list.add(entry("commit: second", oid(A), null, at(-30)));
	return list;
}

/** A separately built entry of the same content as the top row of sample(). */
private static Gitrlz.ReflogEntry top() throws Error
{
	return entry("commit: fourth", oid(C), oid(B), at(0));
}

/** The same, for the row at index 2 of sample(). */
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
		// A ref that had no log at open, and a branch made after the window
		// opened, both arrive here. Neither is an error.
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
		// The window has just opened and nothing has happened since. The row
		// the session started on is the row at the top.
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
		// Two commits made in a terminal beside the window. The mark stays on
		// the entry it started on, which is now two rows lower.
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
		// `git gc` drops old entries from the end of the log. An offset counted
		// back from the size of the list would move; a content match does not.
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

		// The unchanged entry, so the four cases below differ in one field
		// each and in nothing else.
		assert_cmpint(Gitrlz.SessionStart.index_of(middle(), entries),
		              CompareOperator.EQ, 2);

		// New commit.
		assert_cmpint(Gitrlz.SessionStart.index_of(
		                  entry("checkout: moving from main to feature",
		                        oid(C), oid(A), at(-20)),
		                  entries),
		              CompareOperator.EQ, -1);

		// Old commit.
		assert_cmpint(Gitrlz.SessionStart.index_of(
		                  entry("checkout: moving from main to feature",
		                        oid(A), oid(C), at(-20)),
		                  entries),
		              CompareOperator.EQ, -1);

		// Message.
		assert_cmpint(Gitrlz.SessionStart.index_of(
		                  entry("checkout: moving from feature to main",
		                        oid(A), oid(A), at(-20)),
		                  entries),
		              CompareOperator.EQ, -1);

		// Date.
		assert_cmpint(Gitrlz.SessionStart.index_of(
		                  entry("checkout: moving from main to feature",
		                        oid(A), oid(A), at(-21)),
		                  entries),
		              CompareOperator.EQ, -1);

		// A set field against a missing one is a difference as well, and two
		// missing ones are a match. The last row of sample() has no old commit.
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
		// The same operation run twice in one second. The rows agree on all
		// four fields, and the topmost takes the mark.
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

		// Each ref keeps its own newest entry, and not the newest entry of
		// HEAD. The branch was left behind two operations ago, so a shared
		// reading would give it the checkout back to main.
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

		// And the stored entry is found again in the log it came from.
		assert_cmpint(start.index_in("HEAD", head_log), CompareOperator.EQ, 0);
		assert_cmpint(start.index_in("feature",
		                             Gitrlz.Reflog.read(repository, "feature")),
		              CompareOperator.EQ, 0);
		assert_cmpint(start.index_in("stash",
		                             Gitrlz.Reflog.read(repository, "stash")),
		              CompareOperator.EQ, 0);

		// A branch made after the reading has nothing stored, and its view
		// carries no mark.
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
		// A repository with no commits. Every reflog is empty, and the reading
		// gives an empty snapshot rather than an error.
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

// ex:set ts=4 noet:
