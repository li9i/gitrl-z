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

private static Gtk.Application? s_app = null;

private static Gitrlz.ReflogPaned activity_for(Repo repo) throws Error
{
	var location = Gitrlz.Application.discover_repository(repo.path);
	assert_nonnull(location);

	var paned = new Gitrlz.ReflogPaned();
	paned.repository = Gitrlz.Repository.open(location);

	return paned;
}

private static Repo braided_repo() throws Error
{
	var repo = Repo.create();

	repo.commit("first");
	repo.commit("second");
	repo.branch("feature");
	repo.checkout("feature");
	repo.commit("feature work", "feature.txt");
	repo.checkout("main");
	repo.commit("main work", "main.txt");
	repo.merge("feature");

	return repo;
}

private static void test_defaults_show_everything()
{
	try
	{
		var repo = braided_repo();
		var paned = activity_for(repo);

		assert_false(paned.list.has_active_limit());
		assert_cmpint(paned.list.visible_count(), CompareOperator.EQ,
		              paned.list.entries.size);
		assert_false("(" in paned.reflog_caption);

		paned.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_count_caps_the_list()
{
	try
	{
		var repo = braided_repo();
		var paned = activity_for(repo);

		var total = paned.list.entries.size;
		assert_cmpint(total, CompareOperator.GT, 2);

		paned.set_entries_text("2");
		assert_cmpint(paned.list.visible_count(), CompareOperator.EQ, 2);

		paned.set_entries_text("abc");
		assert_cmpint(paned.list.visible_count(), CompareOperator.EQ, total);

		paned.set_entries_text("Last 10");
		assert_cmpint(paned.list.visible_count(), CompareOperator.EQ, total);

		paned.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_window_filters_by_time()
{
	try
	{
		var repo = braided_repo();
		var paned = activity_for(repo);

		var total = paned.list.entries.size;
		assert_cmpint(total, CompareOperator.GT, 0);

		paned.choose_time_window(2);
		assert_true(paned.list.has_active_limit());
		assert_cmpint(paned.list.visible_count(), CompareOperator.EQ, 0);

		paned.choose_time_window(0);
		assert_false(paned.list.has_active_limit());
		assert_cmpint(paned.list.visible_count(), CompareOperator.EQ, total);

		paned.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_caption_gains_and_loses_the_count()
{
	try
	{
		var repo = braided_repo();
		var paned = activity_for(repo);

		assert_false("(" in paned.reflog_caption);

		paned.set_entries_text("2");
		assert_true("(2 of " in paned.reflog_caption);

		paned.set_entries_text("All");
		assert_false("(" in paned.reflog_caption);

		paned.choose_time_window(2);
		assert_true("(" in paned.reflog_caption);

		paned.choose_time_window(0);
		assert_false("(" in paned.reflog_caption);

		paned.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_limit_survives_a_ref_switch()
{
	try
	{
		var repo = braided_repo();
		var paned = activity_for(repo);

		paned.set_entries_text("2");
		assert_cmpint(paned.list.visible_count(), CompareOperator.EQ, 2);

		assert_true(paned.select_ref("feature"));
		assert_true(paned.list.has_active_limit());
		assert_cmpint(paned.list.visible_count(), CompareOperator.EQ,
		              int.min(2, paned.list.entries.size));

		paned.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_limit_survives_a_reload()
{
	try
	{
		var repo = braided_repo();
		var paned = activity_for(repo);

		paned.set_entries_text("2");
		assert_cmpint(paned.list.visible_count(), CompareOperator.EQ, 2);

		repo.commit("later work", "later.txt");
		paned.reload();

		assert_cmpint(paned.list.visible_count(), CompareOperator.EQ, 2);

		paned.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_hidden_row_stays_in_the_plan()
{
	try
	{
		var repo = braided_repo();
		var paned = activity_for(repo);

		assert_true(paned.select_ref("feature"));
		assert_cmpint(paned.list.entries.size, CompareOperator.GE, 2);

		assert_true(paned.toggle_entry(1));
		assert_cmpint(paned.plan_size, CompareOperator.EQ, 1);
		var command = paned.command;

		paned.set_entries_text("1");

		assert_null(paned.list.view_path_for(1));
		assert_cmpint(paned.plan_size, CompareOperator.EQ, 1);
		assert_cmpstr(paned.command, CompareOperator.EQ, command);

		paned.destroy();
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

	s_app = new Gtk.Application(Gitrlz.Config.APPLICATION_ID + ".Tests",
	                            ApplicationFlags.NON_UNIQUE);

	try
	{
		s_app.register();
	}
	catch (Error e)
	{
		stderr.printf("could not register test application: %s\n", e.message);
		return 1;
	}

	Test.add_func("/gitrlz/limits/defaults-show-everything", test_defaults_show_everything);
	Test.add_func("/gitrlz/limits/count-caps-the-list", test_count_caps_the_list);
	Test.add_func("/gitrlz/limits/window-filters-by-time", test_window_filters_by_time);
	Test.add_func("/gitrlz/limits/caption-gains-and-loses-count", test_caption_gains_and_loses_the_count);
	Test.add_func("/gitrlz/limits/survives-ref-switch", test_limit_survives_a_ref_switch);
	Test.add_func("/gitrlz/limits/survives-reload", test_limit_survives_a_reload);
	Test.add_func("/gitrlz/limits/hidden-row-stays-in-plan", test_hidden_row_stays_in_the_plan);

	return Test.run();
}

}
