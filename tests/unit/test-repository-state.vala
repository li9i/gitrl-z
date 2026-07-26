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
 * The repository's mid-operation state (spec FR-165, IC-164).
 *
 * A pure read over the git directory: each marker libgit2's
 * git_repository_state inspects maps to its operation token, and a clean
 * repository reports none.
 */

namespace GitrlzTest
{

private static Gitg.Repository open_fixture(Repo repo) throws Error
{
	var location = Gitrlz.Application.discover_repository(repo.path);
	assert_nonnull(location);
	return Gitrlz.Repository.open(location);
}

private static void test_clean_repository_has_no_operation()
{
	// None of the markers present: no operation in progress.
	try
	{
		var repo = Repo.create();
		repo.commit("first");

		assert_null(Gitrlz.Repository.operation_in_progress(open_fixture(repo)));

		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_each_marker_maps_to_its_token()
{
	// IC-164, checked marker by marker: the table the detection mirrors.
	string[] markers = {
		"rebase", "MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "BISECT_LOG"
	};
	string[] tokens = {
		"rebase", "merge", "cherry-pick", "revert", "bisect"
	};

	for (var i = 0; i < markers.length; i++)
	{
		try
		{
			var repo = Repo.create();
			repo.commit("first");

			repo.begin_operation(markers[i]);

			assert_cmpstr(Gitrlz.Repository.operation_in_progress(open_fixture(repo)),
			              CompareOperator.EQ, tokens[i]);

			repo.remove();
		}
		catch (Error e)
		{
			Test.fail_printf("fixture failed: %s", e.message);
		}
	}
}

public static int main(string[] args)
{
	Test.init(ref args);

	Test.add_func("/gitrlz/repository-state/clean", test_clean_repository_has_no_operation);
	Test.add_func("/gitrlz/repository-state/each-marker", test_each_marker_maps_to_its_token);

	return Test.run();
}

}

// ex:set ts=4 noet:
