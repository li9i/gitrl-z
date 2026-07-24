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
 * Command-line contract (spec section 4.1, FR-104).
 *
 * These spawn the real binary with DISPLAY unset, because the requirement is
 * not merely that the exit codes are right but that these paths work on a
 * machine with no display at all. That is easy to lose in a GTK application
 * and hard to notice: everything still behaves correctly on a developer's
 * desktop. It is the direct descendant of the Python implementation's
 * headless-import test.
 */

namespace GitrlzTest
{

private struct Result
{
	public string stdout_text;
	public string stderr_text;
	public int status;
}

private static Result run_gitrlz(string[] args)
{
	var binary = Environment.get_variable("GITRLZ_BINARY");
	assert_nonnull(binary);

	string[] argv = {};
	argv += binary;

	foreach (var arg in args)
	{
		argv += arg;
	}

	argv += null;

	// DISPLAY removed rather than blanked: this must hold where no display
	// exists, not merely where one is misconfigured.
	var env = Environ.get();
	env = Environ.unset_variable(env, "DISPLAY");
	env = Environ.unset_variable(env, "WAYLAND_DISPLAY");

	var result = Result();

	try
	{
		int status;

		Process.spawn_sync(null,
		                   argv,
		                   env,
		                   SpawnFlags.SEARCH_PATH,
		                   null,
		                   out result.stdout_text,
		                   out result.stderr_text,
		                   out status);

		result.status = Process.exit_status(status);
	}
	catch (Error e)
	{
		Test.fail_printf("could not run gitrlz: %s", e.message);
	}

	return result;
}

private static void test_version()
{
	var r = run_gitrlz({"--version"});

	assert_cmpint(r.status, CompareOperator.EQ, 0);
	assert_true(r.stdout_text.has_prefix("gitrlz "));
}

private static void test_help()
{
	var r = run_gitrlz({"--help"});

	assert_cmpint(r.status, CompareOperator.EQ, 0);
}

private static void test_usage_error()
{
	// Spec section 4.1: a usage error is 2, distinct from a startup error.
	var r = run_gitrlz({"--this-is-not-an-option"});

	assert_cmpint(r.status, CompareOperator.EQ, 2);
}

private static void test_path_not_a_repository()
{
	// FR-104: the message goes to stderr, the exit code is 1, and no window
	// appears. A directory that certainly exists and certainly is not a
	// repository.
	try
	{
		var dir = DirUtils.make_tmp("gitrlz-notrepo-XXXXXX");

		var r = run_gitrlz({dir});

		assert_cmpint(r.status, CompareOperator.EQ, 1);
		assert_true(r.stderr_text.contains("not a git repository"));
		assert_true(r.stderr_text.contains(dir));
		assert_cmpstr(r.stdout_text, CompareOperator.EQ, "");

		DirUtils.remove(dir);
	}
	catch (Error e)
	{
		Test.fail_printf("could not create temporary directory: %s", e.message);
	}
}

private static void test_path_in_a_repository_is_accepted()
{
	// The complement of the test above, and the one that catches the real
	// bug: if discovery is broken, every path looks like "not a repository"
	// and the test above passes for the wrong reason.
	//
	// With no display the run still cannot finish, but it must fail on the
	// display rather than on the repository, so what is asserted is the
	// absence of the discovery error.
	try
	{
		var repo = Repo.create();
		repo.commit("first");

		var r = run_gitrlz({repo.path.get_path()});

		assert_false(r.stderr_text.contains("not a git repository"));

		// A path nested inside the repository resolves to the same one
		// (spec FR-2).
		var nested = repo.path.get_child("nested");
		nested.make_directory();

		var r2 = run_gitrlz({nested.get_path()});
		assert_false(r2.stderr_text.contains("not a git repository"));

		// So does a file inside it.
		var r3 = run_gitrlz({repo.path.get_child("file.txt").get_path()});
		assert_false(r3.stderr_text.contains("not a git repository"));

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

	Test.add_func("/gitrlz/cli/version", test_version);
	Test.add_func("/gitrlz/cli/help", test_help);
	Test.add_func("/gitrlz/cli/usage-error", test_usage_error);
	Test.add_func("/gitrlz/cli/path-not-a-repository", test_path_not_a_repository);
	Test.add_func("/gitrlz/cli/path-in-a-repository", test_path_in_a_repository_is_accepted);

	return Test.run();
}

}

// ex:set ts=4 noet:
