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
 * Harness smoke tests.
 *
 * These prove the test infrastructure itself works before any behaviour
 * depends on it: that GLib.Test runs under meson, that the vendored gitg
 * library links into a test binary, and that the fixture factory produces
 * deterministic repositories.
 */

namespace GitrlzTest
{

private static void test_vendored_library_links()
{
	// Gitg.init() registering the Ggit -> Gitg type factory is the thing
	// every repository test depends on. If the vendored library did not
	// link, this would not compile; if it linked but was broken, this
	// would throw.
	try
	{
		Gitg.init();
	}
	catch (Error e)
	{
		Test.fail_printf("Gitg.init() failed: %s", e.message);
	}
}

private static void test_fixture_is_deterministic()
{
	// The visual regression suite (spec 6.3) needs byte-identical fixture
	// repositories across runs, and this is what guarantees it. Two
	// repositories built from the same commands must produce the same
	// commit hash.
	try
	{
		var a = Repo.create();
		var b = Repo.create();

		var sha_a = a.commit("first");
		var sha_b = b.commit("first");

		assert_cmpstr(sha_a, CompareOperator.EQ, sha_b);

		a.remove();
		b.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_fixture_builds_history()
{
	// Exercises the factory's whole surface, so a later test that uses
	// branches, merges or stashes fails for its own reasons rather than
	// because the helper is broken.
	try
	{
		var repo = Repo.create();

		repo.commit("first");
		repo.branch("feature");
		repo.checkout("feature");
		// Distinct files per branch, so the merge is clean. Both branches
		// writing commit()'s default file.txt would conflict, and a
		// conflicted merge is a different fixture than the one wanted here.
		repo.commit("on feature", "feature.txt");
		repo.checkout("main");
		repo.commit("on main", "main.txt");
		repo.merge("feature");

		var branches = repo.git({"for-each-ref", "--format=%(refname:short)", "refs/heads"});
		assert_true("feature" in branches);
		assert_true("main" in branches);

		// A stash needs a dirty tree first.
		FileUtils.set_contents(repo.path.get_child("file.txt").get_path(), "dirty\n");
		repo.stash("wip");

		var stash = repo.git({"stash", "list"});
		assert_true("wip" in stash);

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

	Test.add_func("/gitrlz/smoke/vendored-library-links", test_vendored_library_links);
	Test.add_func("/gitrlz/smoke/fixture-is-deterministic", test_fixture_is_deterministic);
	Test.add_func("/gitrlz/smoke/fixture-builds-history", test_fixture_builds_history);

	return Test.run();
}

}

// ex:set ts=4 noet:
