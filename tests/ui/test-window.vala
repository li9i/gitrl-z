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

private static Gtk.Application? s_app = null;

private static Gitrlz.Window new_window()
{
	return new Gitrlz.Window(s_app);
}

private static void test_template_loads()
{
	var window = new_window();
	assert_nonnull(window);
	window.destroy();
}

private static void test_window_without_repository_shows_dash()
{
	var window = new_window();

	assert_null(window.repository);

	window.destroy();
}

private static void test_open_repository_sets_title()
{
	try
	{
		var repo = Repo.create();
		repo.commit("first");

		var window = new_window();
		var location = Gitrlz.Application.discover_repository(repo.path);

		assert_nonnull(location);

		window.open_repository(location);

		assert_nonnull(window.repository);

		var name = repo.path.get_basename();
		assert_cmpstr(window.repository.name, CompareOperator.EQ, name);

		window.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_open_bare_repository()
{
	try
	{
		var dir = DirUtils.make_tmp("gitrlz-bare-XXXXXX");
		var bare = File.new_for_path(dir);

		string err;
		int status;
		Process.spawn_sync(dir,
		                   {"git", "init", "--quiet", "--bare", null},
		                   null,
		                   SpawnFlags.SEARCH_PATH | SpawnFlags.STDOUT_TO_DEV_NULL,
		                   null,
		                   null,
		                   out err,
		                   out status);

		var location = Gitrlz.Application.discover_repository(bare);
		assert_nonnull(location);

		var window = new_window();
		window.open_repository(location);

		assert_nonnull(window.repository);

		window.destroy();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_preferences_dialog_constructs()
{
	var window = new_window();
	var dialog = new Gitrlz.PreferencesDialog(window);

	assert_nonnull(dialog);

	dialog.destroy();
	window.destroy();
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

	Test.add_func("/gitrlz/ui/template-loads", test_template_loads);
	Test.add_func("/gitrlz/ui/window-without-repository-shows-dash", test_window_without_repository_shows_dash);
	Test.add_func("/gitrlz/ui/open-repository-sets-title", test_open_repository_sets_title);
	Test.add_func("/gitrlz/ui/open-bare-repository", test_open_bare_repository);
	Test.add_func("/gitrlz/ui/preferences-dialog-constructs", test_preferences_dialog_constructs);

	return Test.run();
}

}
