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
 * The lines of a commit diff, as the split view takes them.
 *
 * These run against fixture repositories rather than stand-in objects: the
 * lines come out of libgit2, and a test with no real trees would only assert
 * that this file calls the functions it calls.
 */

namespace GitrlzTest
{

private static Gitg.Repository open_diff_fixture(Repo repo) throws Error
{
	var location = Gitrlz.Application.discover_repository(repo.path);
	assert_nonnull(location);

	return Gitrlz.Repository.open(location);
}

/** The text of the rows of one kind on the left side, in order. */
private static string[] left_rows_of(Gee.List<Gitrlz.DiffPair> pairs,
                                     Gitrlz.DiffRowKind kind)
{
	var texts = new string[] {};

	foreach (var pair in pairs)
	{
		if (pair.left != null && pair.left.kind == kind)
		{
			texts += pair.left.text;
		}
	}

	return texts;
}

/** The text that the marks of a row cover, joined by `|`. */
private static string marked_text(Gitrlz.DiffRow row)
{
	var parts = new string[row.spans.length];

	for (var i = 0; i < row.spans.length; i++)
	{
		parts[i] = row.text.substring(row.spans[i].start,
		                              row.spans[i].end - row.spans[i].start);
	}

	return string.joinv("|", parts);
}

/** The text of the rows of one kind on the right side, in order. */
private static string[] right_rows_of(Gee.List<Gitrlz.DiffPair> pairs,
                                      Gitrlz.DiffRowKind kind)
{
	var texts = new string[] {};

	foreach (var pair in pairs)
	{
		if (pair.right != null && pair.right.kind == kind)
		{
			texts += pair.right.text;
		}
	}

	return texts;
}

private static void test_a_changed_line_carries_word_marks()
{
	try
	{
		var repo = Repo.create();

		repo.commit("first", "poem.txt", "the quick brown fox jumps over it\n");
		var second = repo.commit("second", "poem.txt",
		                         "the quick brown cat jumps over it\n");

		var repository = open_diff_fixture(repo);
		var pairs = Gitrlz.CommitDiff.read(repository, new Ggit.OId.from_string(second));

		var marked = 0;

		foreach (var pair in pairs)
		{
			if (pair.left == null || pair.left.kind != Gitrlz.DiffRowKind.REMOVED)
			{
				continue;
			}

			// The changed line and its replacement sit beside each other, and
			// each carries the mark of the word that differs.
			assert_nonnull(pair.right);
			assert_cmpint(pair.left.spans.length, CompareOperator.EQ, 1);
			assert_cmpint(pair.right.spans.length, CompareOperator.EQ, 1);

			assert_cmpstr(marked_text(pair.left), CompareOperator.EQ, "fox");
			assert_cmpstr(marked_text(pair.right), CompareOperator.EQ, "cat");

			marked++;
		}

		assert_cmpint(marked, CompareOperator.EQ, 1);

		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_a_root_commit_shows_its_whole_content()
{
	try
	{
		var repo = Repo.create();
		var first = repo.commit("first", "notes.txt", "one\ntwo\n");

		var repository = open_diff_fixture(repo);
		var pairs = Gitrlz.CommitDiff.read(repository, new Ggit.OId.from_string(first));

		var files = left_rows_of(pairs, Gitrlz.DiffRowKind.FILE);
		assert_cmpint(files.length, CompareOperator.EQ, 1);
		assert_true(files[0].has_prefix("notes.txt"));

		// A new file is all additions, thus every line of it is on the right
		// side and the left side of each of those lines is blank.
		var added = right_rows_of(pairs, Gitrlz.DiffRowKind.ADDED);
		assert_cmpint(added.length, CompareOperator.EQ, 2);
		assert_cmpstr(added[0], CompareOperator.EQ, "one");
		assert_cmpstr(added[1], CompareOperator.EQ, "two");

		var blanks = 0;

		foreach (var pair in pairs)
		{
			if (pair.left == null)
			{
				blanks++;
			}
		}

		assert_cmpint(blanks, CompareOperator.EQ, 2);

		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_a_row_carries_no_sign_in_its_text()
{
	try
	{
		var repo = Repo.create();

		repo.commit("first", "list.txt", "keep\ndrop\n");
		var second = repo.commit("second", "list.txt", "keep\n");

		var repository = open_diff_fixture(repo);
		var pairs = Gitrlz.CommitDiff.read(repository, new Ggit.OId.from_string(second));

		// The side says which it is, thus the text carries no sign. A sign here
		// as well would read as "--drop".
		var removed = left_rows_of(pairs, Gitrlz.DiffRowKind.REMOVED);
		assert_cmpint(removed.length, CompareOperator.EQ, 1);
		assert_cmpstr(removed[0], CompareOperator.EQ, "drop");

		// A removed line with nothing to replace it leaves the new side blank.
		foreach (var pair in pairs)
		{
			if (pair.left != null && pair.left.kind == Gitrlz.DiffRowKind.REMOVED)
			{
				assert_null(pair.right);
			}
		}

		// A context line stands on both sides.
		var context = left_rows_of(pairs, Gitrlz.DiffRowKind.CONTEXT);
		assert_cmpint(context.length, CompareOperator.EQ, 1);
		assert_cmpstr(context[0], CompareOperator.EQ, "keep");

		var right_context = right_rows_of(pairs, Gitrlz.DiffRowKind.CONTEXT);
		assert_cmpint(right_context.length, CompareOperator.EQ, 1);
		assert_cmpstr(right_context[0], CompareOperator.EQ, "keep");

		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_an_unequal_change_keeps_the_sides_level()
{
	try
	{
		var repo = Repo.create();

		repo.commit("first", "body.txt", "head\nmiddle\ntail\n");
		var second = repo.commit("second", "body.txt",
		                         "head\nmiddle one\nmiddle two\ntail\n");

		var repository = open_diff_fixture(repo);
		var pairs = Gitrlz.CommitDiff.read(repository, new Ggit.OId.from_string(second));

		var changed = new Gee.ArrayList<Gitrlz.DiffPair>();

		foreach (var pair in pairs)
		{
			var kind = pair.left != null ? pair.left.kind : pair.right.kind;

			if (kind == Gitrlz.DiffRowKind.REMOVED || kind == Gitrlz.DiffRowKind.ADDED)
			{
				changed.add(pair);
			}
		}

		// One line became two. The first added line stands beside the line it
		// replaced, and the second has a blank beside it, thus the tail line
		// that follows stays level on the two sides.
		assert_cmpint(changed.size, CompareOperator.EQ, 2);

		assert_nonnull(changed[0].left);
		assert_cmpstr(changed[0].left.text, CompareOperator.EQ, "middle");
		assert_nonnull(changed[0].right);
		assert_cmpstr(changed[0].right.text, CompareOperator.EQ, "middle one");

		assert_null(changed[1].left);
		assert_nonnull(changed[1].right);
		assert_cmpstr(changed[1].right.text, CompareOperator.EQ, "middle two");

		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_each_changed_file_gets_a_heading()
{
	try
	{
		var repo = Repo.create();

		repo.commit("first", "a.txt", "a\n");
		repo.commit("second", "b.txt", "b\n");

		FileUtils.set_contents(repo.path.get_child("a.txt").get_path(), "a2\n");
		FileUtils.set_contents(repo.path.get_child("b.txt").get_path(), "b2\n");

		repo.git({"add", "--all"});
		repo.git({"commit", "--quiet", "-m", "both"});
		var third = repo.git({"rev-parse", "HEAD"}).strip();

		var repository = open_diff_fixture(repo);
		var pairs = Gitrlz.CommitDiff.read(repository, new Ggit.OId.from_string(third));

		var files = left_rows_of(pairs, Gitrlz.DiffRowKind.FILE);
		assert_cmpint(files.length, CompareOperator.EQ, 2);
		assert_cmpstr(files[0], CompareOperator.EQ, "a.txt");
		assert_cmpstr(files[1], CompareOperator.EQ, "b.txt");

		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_a_merge_reads_against_its_first_parent()
{
	try
	{
		var repo = Repo.create();

		repo.commit("first", "shared.txt", "one\n");
		repo.branch("side");
		repo.checkout("side");
		repo.commit("side change", "side.txt", "side\n");
		repo.checkout("main");
		repo.commit("main change", "main.txt", "main\n");
		repo.merge("side");

		var head = repo.git({"rev-parse", "HEAD"}).strip();

		var repository = open_diff_fixture(repo);
		var pairs = Gitrlz.CommitDiff.read(repository, new Ggit.OId.from_string(head));

		var notes = left_rows_of(pairs, Gitrlz.DiffRowKind.NOTE);
		assert_cmpint(notes.length, CompareOperator.GE, 1);
		assert_cmpstr(notes[0], CompareOperator.EQ,
		              "Merge commit, shown against its first parent");

		// Against the first parent, which is main, the merge brings in the file
		// that the side branch added.
		var files = left_rows_of(pairs, Gitrlz.DiffRowKind.FILE);
		assert_cmpint(files.length, CompareOperator.EQ, 1);
		assert_true(files[0].has_prefix("side.txt"));

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

	Test.add_func("/gitrlz/commit-diff/word-marks", test_a_changed_line_carries_word_marks);
	Test.add_func("/gitrlz/commit-diff/root-commit", test_a_root_commit_shows_its_whole_content);
	Test.add_func("/gitrlz/commit-diff/no-sign-in-text", test_a_row_carries_no_sign_in_its_text);
	Test.add_func("/gitrlz/commit-diff/sides-stay-level", test_an_unequal_change_keeps_the_sides_level);
	Test.add_func("/gitrlz/commit-diff/file-headings", test_each_changed_file_gets_a_heading);
	Test.add_func("/gitrlz/commit-diff/merge-first-parent", test_a_merge_reads_against_its_first_parent);

	return Test.run();
}

}

// ex:set ts=4 noet:
