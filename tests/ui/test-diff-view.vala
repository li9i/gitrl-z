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
 *
 * You should have received a copy of the GNU General Public License along
 * with gitrl-z. If not, see <http://www.gnu.org/licenses/>.
 */

/*
 * What the split diff view puts on the screen.
 *
 * The unit tests hold the lines that the diff is made of; these hold what the
 * reader sees of them, which is the text of the two columns, gutter and all.
 */

namespace GitrlzTest
{

/** The text of the gutter of one side of the view. */
private static string gutter_text(Gitrlz.DiffView view, bool left)
{
	return column_text(view, left, 0);
}

/** The text of one side of the view, with no gutter in it. */
private static string side_text(Gitrlz.DiffView view, bool left)
{
	return column_text(view, left, 1);
}

/**
 * The text of one column of the view.
 *
 * A side is a box of two scrollers, the gutter first and the text second, thus
 * `index` picks which of the two to read.
 */
private static string column_text(Gitrlz.DiffView view, bool left, int index)
{
	var box = (left ? view.get_child1() : view.get_child2()) as Gtk.Box;
	assert_nonnull(box);

	var children = box.get_children();
	var scroll = children.nth_data(index) as Gtk.ScrolledWindow;
	assert_nonnull(scroll);

	var text_view = scroll.get_child() as Gtk.TextView;
	assert_nonnull(text_view);

	Gtk.TextIter start;
	Gtk.TextIter end;

	text_view.buffer.get_bounds(out start, out end);

	return text_view.buffer.get_text(start, end, true);
}

/** A view showing the diff of the commit at `sha` of `repo`. */
private static Gitrlz.DiffView view_of(Repo repo, string sha) throws Error
{
	var location = Gitrlz.Application.discover_repository(repo.path);
	assert_nonnull(location);

	var view = new Gitrlz.DiffView();
	view.show_commit(Gitrlz.Repository.open(location), new Ggit.OId.from_string(sha));

	return view;
}

private static void test_a_heading_has_no_number_and_no_sign()
{
	try
	{
		var repo = Repo.create();

		repo.commit("first", "roll.txt", "one\ntwo\n");
		var second = repo.commit("second", "roll.txt", "one\ntwo\nthree\n");

		var view = view_of(repo, second);

		// The file heading opens the diff, and it is no line of a file, thus its
		// gutter is blank and as wide as one with a number in it.
		assert_true(side_text(view, true).has_prefix("roll.txt\n"));
		assert_true(gutter_text(view, true).has_prefix("     \n"));

		view.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_each_side_shows_its_numbers_and_signs()
{
	try
	{
		var repo = Repo.create();

		repo.commit("first", "song.txt", "one\ntwo\nthree\n");
		var second = repo.commit("second", "song.txt", "one\nTWO\nthree\n");

		var view = view_of(repo, second);

		// The changed line stands at line 2 of both files, and each side carries
		// the sign of what happened to it there.
		assert_true("\n 2 - \n" in gutter_text(view, true));
		assert_true("\n 2 + \n" in gutter_text(view, false));

		// The number and the sign are the gutter's, thus the text beside them
		// holds the line and nothing else. A copy of it pastes as code.
		assert_true("\ntwo\n" in side_text(view, true));
		assert_true("\nTWO\n" in side_text(view, false));

		// A context line is on both sides, at the number it has in each file,
		// and no change happened to it, thus it carries no sign.
		assert_true("\n 1   \n" in gutter_text(view, true));
		assert_true("\n 1   \n" in gutter_text(view, false));
		assert_true("\n 3   \n" in gutter_text(view, true));
		assert_true("\n 3   \n" in gutter_text(view, false));

		view.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_the_numbers_of_a_long_file_stand_in_one_column()
{
	try
	{
		var repo = Repo.create();

		var lines = new StringBuilder();

		for (var i = 1; i <= 12; i++)
		{
			lines.append("line %d\n".printf(i));
		}

		repo.commit("first", "long.txt", lines.str);

		var second = repo.commit("second", "long.txt",
		                         lines.str.replace("line 12\n", "line twelve\n"));

		var view = view_of(repo, second);
		var left = gutter_text(view, true);

		// The widest number of the diff has two digits, thus a one digit number
		// is padded to the same width and the signs stay in one column.
		assert_true("\n  9   \n" in left);
		assert_true("\n 12 - \n" in left);

		view.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

public static int main(string[] args)
{
	Environment.set_variable("GSETTINGS_BACKEND", "memory", true);

	Test.init(ref args);

	if (!Gtk.init_check(ref args))
	{
		// No display: report as skipped rather than failed. The suite is run
		// under tests/ui/run-xvfb.sh, which provides one.
		stdout.printf("1..0 # SKIP no display available\n");
		return 0;
	}

	try
	{
		Gitg.init();
	}
	catch (Error e)
	{
		stderr.printf("Gitg.init() failed: %s\n", e.message);
		return 1;
	}

	Test.add_func("/gitrlz/ui/diff-view/numbers-and-signs", test_each_side_shows_its_numbers_and_signs);
	Test.add_func("/gitrlz/ui/diff-view/heading-gutter", test_a_heading_has_no_number_and_no_sign);
	Test.add_func("/gitrlz/ui/diff-view/number-column", test_the_numbers_of_a_long_file_stand_in_one_column);

	return Test.run();
}

}

// ex:set ts=4 noet:
