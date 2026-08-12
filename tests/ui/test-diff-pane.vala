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

namespace GitrlzTest
{

private delegate bool DiffCondition();

private static Gee.List<Gtk.Widget> descendants(Gtk.Widget root)
{
	var found = new Gee.ArrayList<Gtk.Widget>();

	found.add(root);

	var container = root as Gtk.Container;

	if (container != null)
	{
		foreach (var child in container.get_children())
		{
			found.add_all(descendants(child));
		}
	}

	return found;
}

private static Gee.List<Gtk.Widget> file_sections(Gitg.DiffView view)
{
	var sections = new Gee.ArrayList<Gtk.Widget>();

	foreach (var widget in descendants(view))
	{
		if (widget.get_type().name() == "GitgDiffViewFile")
		{
			sections.add(widget);
		}
	}

	sections.sort((a, b) => section_row(a) - section_row(b));

	return sections;
}

private static int section_row(Gtk.Widget section)
{
	var grid = section.get_parent() as Gtk.Grid;

	if (grid == null)
	{
		return 0;
	}

	var row = Value(typeof(int));
	grid.child_get_property(section, "top-attach", ref row);

	return row.get_int();
}

private static Gtk.Widget? commit_details(Gitg.DiffView view)
{
	foreach (var widget in descendants(view))
	{
		if (widget.get_type().name() == "GitgDiffViewCommitDetails")
		{
			return widget;
		}
	}

	return null;
}

private static string section_path(Gtk.Widget section)
{
	foreach (var widget in descendants(section))
	{
		var label = widget as Gtk.Label;

		if (label != null)
		{
			return label.label;
		}
	}

	return "";
}

private static Gitg.DiffStat? section_stat(Gtk.Widget section)
{
	foreach (var widget in descendants(section))
	{
		var stat = widget as Gitg.DiffStat;

		if (stat != null)
		{
			return stat;
		}
	}

	return null;
}

private static Gee.List<string> section_renderers(Gtk.Widget section)
{
	var names = new Gee.ArrayList<string>();

	foreach (var widget in descendants(section))
	{
		var stack = widget as Gtk.Stack;

		if (stack == null)
		{
			continue;
		}

		foreach (var child in stack.get_children())
		{
			string name;
			stack.child_get(child, "name", out name);
			names.add(name);
		}

		break;
	}

	return names;
}

private static void expand_all(Gitg.DiffView view)
{
	var details = commit_details(view);
	assert_nonnull(details);

	details.set_property("expanded", true);
}

private static bool section_expanded(Gtk.Widget section)
{
	var expanded = Value(typeof(bool));
	section.get_property("expanded", ref expanded);

	return expanded.get_boolean();
}

private static int section_line_count(Gtk.Widget section)
{
	foreach (var widget in descendants(section))
	{
		var source = widget as Gtk.SourceView;

		if (source != null && source.buffer.get_line_count() > 1)
		{
			return source.buffer.get_line_count();
		}
	}

	return 0;
}

private static Gtk.Widget visible_renderer_widget(Gtk.Widget section)
{
	foreach (var widget in descendants(section))
	{
		var stack = widget as Gtk.Stack;

		if (stack != null && stack.visible_child != null)
		{
			return stack.visible_child;
		}
	}

	return section;
}

private static string visible_renderer(Gtk.Widget section)
{
	foreach (var widget in descendants(section))
	{
		var stack = widget as Gtk.Stack;

		if (stack != null)
		{
			return stack.visible_child_name;
		}
	}

	return "";
}

private static string tagged_text(Gtk.Widget section, string tag)
{
	var found = "";

	foreach (var widget in descendants(visible_renderer_widget(section)))
	{
		var source = widget as Gtk.SourceView;

		if (source == null)
		{
			continue;
		}

		var mark = source.buffer.tag_table.lookup(tag);

		if (mark == null)
		{
			continue;
		}

		Gtk.TextIter iter;
		source.buffer.get_start_iter(out iter);

		if (!iter.starts_tag(mark))
		{
			if (!iter.forward_to_tag_toggle(mark))
			{
				continue;
			}
		}

		while (true)
		{
			var start = iter;

			if (!iter.forward_to_tag_toggle(mark))
			{
				break;
			}

			found += source.buffer.get_text(start, iter, true) + "|";

			if (!iter.forward_to_tag_toggle(mark))
			{
				break;
			}
		}
	}

	return found;
}

private static Gtk.RadioButton? switch_button(Gitrlz.DiffWindow window, string label)
{
	var header = window.get_titlebar();
	assert_nonnull(header);

	foreach (var widget in descendants(header))
	{
		var button = widget as Gtk.RadioButton;

		if (button != null && button.label == label)
		{
			return button;
		}
	}

	return null;
}

private static string all_label_text(Gtk.Widget root)
{
	var text = "";

	foreach (var widget in descendants(root))
	{
		var label = widget as Gtk.Label;

		if (label != null)
		{
			text += label.label + "\n";
		}
	}

	return text;
}

private static Gee.List<Gtk.RadioButton> parent_buttons(Gitg.DiffView view)
{
	var buttons = new Gee.ArrayList<Gtk.RadioButton>();
	var details = commit_details(view);

	assert_nonnull(details);

	foreach (var widget in descendants(details))
	{
		var button = widget as Gtk.RadioButton;

		if (button != null)
		{
			buttons.add(button);
		}
	}

	buttons.sort((a, b) => section_row(a) - section_row(b));

	return buttons;
}

private static void wait_for(DiffCondition cond, uint timeout_ms = 5000)
{
	var loop = new MainLoop();
	var elapsed = 0;
	var step = 50;

	Timeout.add(step, () => {
		if (cond() || elapsed >= timeout_ms)
		{
			loop.quit();
			return Source.REMOVE;
		}

		elapsed += step;
		return Source.CONTINUE;
	});

	loop.run();
}

private static Gitrlz.DiffWindow window_for(Repo repo, string sha, int expected) throws Error
{
	var location = Gitrlz.Application.discover_repository(repo.path);
	assert_nonnull(location);

	var repository = Gitrlz.Repository.open(location);
	var window = new Gitrlz.DiffWindow(null);

	window.show_commit(repository, repository.lookup_commit(new Ggit.OId.from_string(sha)));

	if (expected > 0)
	{
		wait_for(() => file_sections(window.view).size >= expected);
	}
	else
	{
		wait_for(() => false, 500);
	}

	return window;
}

private static void test_a_section_per_changed_file()
{
	try
	{
		var repo = Repo.create();
		repo.commit("first", "a.txt", "one\n");
		repo.commit("second", "b.txt", "two\n");

		var sha = repo.commit("both", "a.txt", "one changed\n");
		repo.git({"rm", "--quiet", "b.txt"});
		sha = repo.commit("touch two files", "a.txt", "one changed again\n");

		var window = window_for(repo, sha, 2);
		var sections = file_sections(window.view);

		assert_cmpint(sections.size, CompareOperator.EQ, 2);
		assert_cmpstr(section_path(sections[0]), CompareOperator.EQ, "a.txt");
		assert_cmpstr(section_path(sections[1]), CompareOperator.EQ, "b.txt");

		window.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_the_stat_badge_counts_the_changed_lines()
{
	try
	{
		var repo = Repo.create();
		repo.commit("first", "a.txt", "one\ntwo\nthree\n");

		var sha = repo.commit("grow", "a.txt", "one\ntwo\nthree\nfour\nfive\n");

		var window = window_for(repo, sha, 1);
		var stat = section_stat(file_sections(window.view)[0]);

		assert_nonnull(stat);
		assert_cmpuint(stat.added, CompareOperator.EQ, 2);
		assert_cmpuint(stat.removed, CompareOperator.EQ, 0);

		window.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_sections_start_folded_and_expand_all_unfolds_them()
{
	try
	{
		var repo = Repo.create();
		repo.commit("first", "a.txt", "one\n");
		repo.commit("second", "b.txt", "two\n");

		repo.git({"rm", "--quiet", "b.txt"});
		var sha = repo.commit("change both", "a.txt", "one changed\n");

		var window = window_for(repo, sha, 2);
		var sections = file_sections(window.view);

		foreach (var section in sections)
		{
			assert_false(section_expanded(section));
		}

		expand_all(window.view);

		wait_for(() => section_expanded(sections[0]));

		foreach (var section in sections)
		{
			assert_true(section_expanded(section));
		}

		window.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_the_details_grid_states_the_commit()
{
	try
	{
		var repo = Repo.create();
		var sha = repo.commit("a subject worth reading", "a.txt", "one\n");

		var window = window_for(repo, sha, 1);
		var text = all_label_text(window.view);

		assert_true(sha in text);
		assert_true("a subject worth reading" in text);
		assert_true("Test Author" in text);

		window.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_a_merge_offers_both_parents()
{
	try
	{
		var repo = Repo.create();
		repo.commit("first", "shared.txt", "one\n");
		repo.branch("side");
		repo.checkout("side");
		repo.commit("on the side", "side.txt", "side\n");
		repo.checkout("main");
		repo.commit("on the trunk", "trunk.txt", "trunk\n");
		repo.merge("side");

		var sha = repo.git({"rev-parse", "HEAD"}).strip();

		var window = window_for(repo, sha, 1);
		var buttons = parent_buttons(window.view);

		assert_cmpint(buttons.size, CompareOperator.EQ, 2);

		assert_cmpstr(section_path(file_sections(window.view)[0]),
		              CompareOperator.EQ, "side.txt");

		buttons[1].active = true;

		wait_for(() => file_sections(window.view).size == 1
		               && section_path(file_sections(window.view)[0]) == "trunk.txt");

		assert_cmpstr(section_path(file_sections(window.view)[0]),
		              CompareOperator.EQ, "trunk.txt");

		window.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_a_rename_reads_from_and_to()
{
	try
	{
		var repo = Repo.create();
		repo.commit("first", "before.txt", "one\ntwo\nthree\nfour\n");

		repo.git({"mv", "before.txt", "after.txt"});
		var sha = repo.commit("rename it", "after.txt", "one\ntwo\nthree\nfour\n");

		var window = window_for(repo, sha, 1);
		var path = section_path(file_sections(window.view)[0]);

		assert_true("before.txt" in path);
		assert_true("after.txt" in path);

		window.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_a_commit_that_changes_nothing_shows_no_section()
{
	try
	{
		var repo = Repo.create();
		repo.commit("first", "a.txt", "one\n");
		repo.git({"commit", "--quiet", "--allow-empty", "-m", "nothing at all"});

		var sha = repo.git({"rev-parse", "HEAD"}).strip();

		var window = window_for(repo, sha, 0);

		assert_cmpint(file_sections(window.view).size, CompareOperator.EQ, 0);
		assert_true("nothing at all" in all_label_text(window.view));

		window.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_an_image_gets_the_image_renderer()
{
	try
	{
		var repo = Repo.create();

		uint8[] first = {
			0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d,
			0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
			0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xde, 0x00, 0x00, 0x00,
			0x0c, 0x49, 0x44, 0x41, 0x54, 0x78, 0xda, 0x63, 0xf8, 0xcf, 0xc0, 0x00,
			0x00, 0x03, 0x01, 0x01, 0x00, 0xf7, 0x03, 0x41, 0x43, 0x00, 0x00, 0x00,
			0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82
		};

		uint8[] second = {
			0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d,
			0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
			0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xde, 0x00, 0x00, 0x00,
			0x0c, 0x49, 0x44, 0x41, 0x54, 0x78, 0xda, 0x63, 0x60, 0x60, 0xf8, 0x0f,
			0x00, 0x01, 0x03, 0x01, 0x00, 0x36, 0x74, 0x11, 0x40, 0x00, 0x00, 0x00,
			0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82
		};

		repo.commit_bytes("add an image", "pixel.png", first);
		var sha = repo.commit_bytes("change the image", "pixel.png", second);

		var window = window_for(repo, sha, 1);
		var renderers = section_renderers(file_sections(window.view)[0]);

		assert_true("image" in renderers);
		assert_false("text" in renderers);

		window.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_a_binary_file_gets_the_binary_notice()
{
	try
	{
		var repo = Repo.create();

		uint8[] first = { 0x00, 0x01, 0x02, 0x03 };
		uint8[] second = { 0x00, 0x04, 0x05, 0x06 };

		repo.commit_bytes("add a blob", "blob.bin", first);
		var sha = repo.commit_bytes("change the blob", "blob.bin", second);

		var window = window_for(repo, sha, 1);
		var renderers = section_renderers(file_sections(window.view)[0]);

		assert_true("binary" in renderers);
		assert_false("text" in renderers);

		window.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_the_context_lines_change_what_a_section_holds()
{
	try
	{
		var repo = Repo.create();
		repo.commit("first", "a.txt", "1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n11\n12\n");

		var sha = repo.commit("change the middle",
		                      "a.txt", "1\n2\n3\n4\n5\n6\nsix and a half\n7\n8\n9\n10\n11\n12\n");

		var window = window_for(repo, sha, 1);

		expand_all(window.view);

		wait_for(() => section_line_count(file_sections(window.view)[0]) > 0);

		var with_three = section_line_count(file_sections(window.view)[0]);
		assert_cmpint(with_three, CompareOperator.GT, 0);

		window.view.context_lines = 6;

		wait_for(() => file_sections(window.view).size == 1
		               && section_line_count(file_sections(window.view)[0]) > with_three);

		assert_cmpint(section_line_count(file_sections(window.view)[0]),
		              CompareOperator.GT, with_three);

		window.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_the_switch_moves_every_section()
{
	try
	{
		var repo = Repo.create();
		repo.commit("first", "a.txt", "one\n");
		repo.commit("second", "b.txt", "two\n");

		repo.git({"rm", "--quiet", "b.txt"});
		var sha = repo.commit("change both", "a.txt", "one changed\n");

		var window = window_for(repo, sha, 2);
		var sections = file_sections(window.view);

		foreach (var section in sections)
		{
			assert_cmpstr(visible_renderer(section), CompareOperator.EQ, "splittext");
		}

		var unif = switch_button(window, "Unif");
		assert_nonnull(unif);
		unif.active = true;

		foreach (var section in file_sections(window.view))
		{
			assert_cmpstr(visible_renderer(section), CompareOperator.EQ, "text");
		}

		var split = switch_button(window, "Split");
		assert_nonnull(split);
		split.active = true;

		foreach (var section in file_sections(window.view))
		{
			assert_cmpstr(visible_renderer(section), CompareOperator.EQ, "splittext");
		}

		window.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_the_switch_is_remembered()
{
	try
	{
		var repo = Repo.create();
		repo.commit("first", "a.txt", "one\n");

		var sha = repo.commit("change it", "a.txt", "one changed\n");

		var state = new Settings("%s.state.diff".printf(Gitrlz.Config.APPLICATION_ID));

		var first = window_for(repo, sha, 1);
		assert_cmpstr(state.get_string("renderer"), CompareOperator.EQ, "split");

		switch_button(first, "Unif").active = true;
		assert_cmpstr(state.get_string("renderer"), CompareOperator.EQ, "unified");

		first.destroy();

		var second = window_for(repo, sha, 1);

		assert_cmpstr(visible_renderer(file_sections(second.view)[0]),
		              CompareOperator.EQ, "text");

		switch_button(second, "Split").active = true;

		second.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_an_image_keeps_its_renderer_through_the_switch()
{
	try
	{
		var repo = Repo.create();

		uint8[] first = {
			0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d,
			0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
			0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xde, 0x00, 0x00, 0x00,
			0x0c, 0x49, 0x44, 0x41, 0x54, 0x78, 0xda, 0x63, 0xf8, 0xcf, 0xc0, 0x00,
			0x00, 0x03, 0x01, 0x01, 0x00, 0xf7, 0x03, 0x41, 0x43, 0x00, 0x00, 0x00,
			0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82
		};

		uint8[] second = {
			0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d,
			0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
			0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xde, 0x00, 0x00, 0x00,
			0x0c, 0x49, 0x44, 0x41, 0x54, 0x78, 0xda, 0x63, 0x60, 0x60, 0xf8, 0x0f,
			0x00, 0x01, 0x03, 0x01, 0x00, 0x36, 0x74, 0x11, 0x40, 0x00, 0x00, 0x00,
			0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82
		};

		repo.commit_bytes("add an image", "pixel.png", first);
		var sha = repo.commit_bytes("change the image", "pixel.png", second);

		var window = window_for(repo, sha, 1);
		var section = file_sections(window.view)[0];

		assert_cmpstr(visible_renderer(section), CompareOperator.EQ, "image");

		switch_button(window, "Unif").active = true;

		assert_cmpstr(visible_renderer(file_sections(window.view)[0]),
		              CompareOperator.EQ, "image");

		switch_button(window, "Split").active = true;

		window.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_the_changed_words_are_marked()
{
	try
	{
		var repo = Repo.create();
		repo.commit("first", "a.txt",
		            "the quick brown fox jumps over the lazy dog\nsecond line\n");

		var sha = repo.commit("one word", "a.txt",
		                      "the quick brown cat jumps over the lazy dog\nsecond line\n");

		var window = window_for(repo, sha, 1);

		expand_all(window.view);

		wait_for(() => tagged_text(file_sections(window.view)[0], "word-added") != "");

		var section = file_sections(window.view)[0];

		assert_cmpstr(tagged_text(section, "word-added"), CompareOperator.EQ, "cat|");
		assert_cmpstr(tagged_text(section, "word-removed"), CompareOperator.EQ, "fox|");

		switch_button(window, "Unif").active = true;

		wait_for(() => tagged_text(file_sections(window.view)[0], "word-added") != "");

		section = file_sections(window.view)[0];

		assert_cmpstr(tagged_text(section, "word-added"), CompareOperator.EQ, "cat|");
		assert_cmpstr(tagged_text(section, "word-removed"), CompareOperator.EQ, "fox|");

		switch_button(window, "Split").active = true;

		window.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_a_line_with_no_counterpart_takes_no_marks()
{
	try
	{
		var repo = Repo.create();
		repo.commit("first", "a.txt", "one\ntwo\nthree\n");

		var sha = repo.commit("append", "a.txt", "one\ntwo\nthree\nfour\n");

		var window = window_for(repo, sha, 1);

		expand_all(window.view);

		wait_for(() => section_line_count(file_sections(window.view)[0]) > 0);

		var section = file_sections(window.view)[0];

		assert_cmpstr(tagged_text(section, "word-added"), CompareOperator.EQ, "");
		assert_cmpstr(tagged_text(section, "word-removed"), CompareOperator.EQ, "");

		window.destroy();
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

	Test.add_func("/gitrlz/diff-pane/a-section-per-changed-file",
	              test_a_section_per_changed_file);
	Test.add_func("/gitrlz/diff-pane/stat-badge-counts",
	              test_the_stat_badge_counts_the_changed_lines);
	Test.add_func("/gitrlz/diff-pane/sections-start-folded",
	              test_sections_start_folded_and_expand_all_unfolds_them);
	Test.add_func("/gitrlz/diff-pane/details-grid-states-the-commit",
	              test_the_details_grid_states_the_commit);
	Test.add_func("/gitrlz/diff-pane/a-merge-offers-both-parents",
	              test_a_merge_offers_both_parents);
	Test.add_func("/gitrlz/diff-pane/a-rename-reads-from-and-to",
	              test_a_rename_reads_from_and_to);
	Test.add_func("/gitrlz/diff-pane/no-change-no-section",
	              test_a_commit_that_changes_nothing_shows_no_section);
	Test.add_func("/gitrlz/diff-pane/an-image-gets-the-image-renderer",
	              test_an_image_gets_the_image_renderer);
	Test.add_func("/gitrlz/diff-pane/a-binary-file-gets-the-notice",
	              test_a_binary_file_gets_the_binary_notice);
	Test.add_func("/gitrlz/diff-pane/context-lines-change-the-section",
	              test_the_context_lines_change_what_a_section_holds);
	Test.add_func("/gitrlz/diff-pane/the-switch-moves-every-section",
	              test_the_switch_moves_every_section);
	Test.add_func("/gitrlz/diff-pane/the-switch-is-remembered",
	              test_the_switch_is_remembered);
	Test.add_func("/gitrlz/diff-pane/an-image-keeps-its-renderer",
	              test_an_image_keeps_its_renderer_through_the_switch);
	Test.add_func("/gitrlz/diff-pane/the-changed-words-are-marked",
	              test_the_changed_words_are_marked);
	Test.add_func("/gitrlz/diff-pane/no-counterpart-no-marks",
	              test_a_line_with_no_counterpart_takes_no_marks);

	return Test.run();
}

}
