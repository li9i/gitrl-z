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

namespace Gitrlz
{

public errordomain RepositoryError
{
	NOT_A_REPOSITORY,
	READ_FAILED,
}

/**
 * The read-only repository layer (spec NFR-4, IC-100 to IC-107).
 *
 * open() here makes each repository handle in gitrl-z, and each repository
 * read uses one of these functions. Thus a check of the read-only guarantee
 * occurs at one location, and not across the full codebase.
 *
 * The handle is a Gitg.Repository, which *extends* Ggit.Repository and does
 * not wrap it. There is no separate Gitrlz repository type that hides the
 * Ggit API. Such a type would re-export most of that API. This class gives
 * the set of reads that gitrl-z performs, each with the error handling that
 * the spec requires.
 *
 * Ggit is not thread safe for each handle, and each call here is synchronous.
 * Thus the main loop must call these functions.
 */
public class Repository : Object
{
	/*
	 * The status flags that `git reset --hard` would destroy.
	 *
	 * This constant is at class scope and not in uncommitted_changes(). Vala
	 * cannot read a local constant from a closure, and the status callback is
	 * a closure.
	 *
	 * It excludes WORKING_TREE_NEW (untracked) and IGNORED, which a hard reset
	 * does not change.
	 */
	private const Ggit.StatusFlags DESTRUCTIVE =
		Ggit.StatusFlags.INDEX_NEW |
		Ggit.StatusFlags.INDEX_MODIFIED |
		Ggit.StatusFlags.INDEX_DELETED |
		Ggit.StatusFlags.INDEX_RENAMED |
		Ggit.StatusFlags.INDEX_TYPECHANGE |
		Ggit.StatusFlags.WORKING_TREE_MODIFIED |
		Ggit.StatusFlags.WORKING_TREE_DELETED |
		Ggit.StatusFlags.WORKING_TREE_TYPECHANGE |
		Ggit.StatusFlags.WORKING_TREE_RENAMED |
		Ggit.StatusFlags.CONFLICTED;

	/**
	 * Opens the repository at a location that
	 * Application.discover_repository found.
	 *
	 * This is the only location that makes a repository handle (NFR-4).
	 */
	public static Gitg.Repository open(File location) throws RepositoryError
	{
		try
		{
			// Gitg.init() registers the Ggit -> Gitg object factory, and the
			// lookup_reference_dwim() of Gitg.Repository casts its result to
			// a Gitg.Ref. Without the factory, that cast gives null. Each ref
			// lookup then looks like a missing ref, and not like an
			// uninitialised library. The reflog tests showed this behaviour
			// on their first run.
			//
			// The call is here, and does not depend on callers. Thus each
			// code path that gets a repository handle is correct. The call is
			// idempotent. In the application, startup() called it before,
			// with a display present. Thus this call does not consume the
			// guard and does not skip the CSS (refer to vendor/patches).
			Gitg.init();

			return new Gitg.Repository(location, null);
		}
		catch (Error e)
		{
			throw new RepositoryError.NOT_A_REPOSITORY("%s", e.message);
		}
	}

	/**
	 * The multi-step git operation that is in progress, or null (IC-164).
	 *
	 * Ggit does not give the repository state. Thus this method reads the same
	 * filesystem markers that git_repository_state of libgit2 examines,
	 * directly in the git directory. These are rebase-merge/ or rebase-apply/
	 * for a rebase, then MERGE_HEAD, CHERRY_PICK_HEAD, REVERT_HEAD and
	 * BISECT_LOG. The method examines them in that fixed order, and the first
	 * match gives the result.
	 *
	 * This is a pure, read-only function of the filesystem (NFR-44, NFR-45).
	 * If the git directory is absent or unreadable, the method reports no
	 * operation (spec section 5).
	 */
	public static string? operation_in_progress(Gitg.Repository repository)
	{
		var git_dir = git_directory(repository);

		if (git_dir == null)
		{
			return null;
		}

		if (git_dir.get_child("rebase-merge").query_exists()
		    || git_dir.get_child("rebase-apply").query_exists())
		{
			return "rebase";
		}

		if (git_dir.get_child("MERGE_HEAD").query_exists())
		{
			return "merge";
		}

		if (git_dir.get_child("CHERRY_PICK_HEAD").query_exists())
		{
			return "cherry-pick";
		}

		if (git_dir.get_child("REVERT_HEAD").query_exists())
		{
			return "revert";
		}

		if (git_dir.get_child("BISECT_LOG").query_exists())
		{
			return "bisect";
		}

		return null;
	}

	/**
	 * The short name of a branch: "main", and not "refs/heads/main".
	 *
	 * The object factory returns a Gitg.BranchBase, and its get_name() gives
	 * the full ref name. The ParsedRefName of gitg makes the name short. It
	 * also processes the other ref prefixes, and does not assume
	 * refs/heads/.
	 */
	private static string? short_name(Ggit.Ref? branch)
	{
		if (branch == null)
		{
			return null;
		}

		var reference = branch as Gitg.Ref;

		if (reference != null)
		{
			return reference.parsed_name.shortname;
		}

		return branch.get_name();
	}

	/**
	 * Local branch names, sorted with no sensitivity to case (IC-101, P-FR-7).
	 *
	 * The order of git is bytewise, which puts each uppercase name before each
	 * lowercase name. The sidebar needs them mixed, as a reader expects.
	 */
	public static Gee.List<string> list_branches(Gitg.Repository repository)
	{
		var names = new Gee.ArrayList<string>();

		try
		{
			var enumerator = repository.enumerate_branches(Ggit.BranchType.LOCAL);

			if (enumerator != null)
			{
				foreach (var branch in enumerator)
				{
					var name = short_name(branch);

					if (name != null)
					{
						names.add(name);
					}
				}
			}
		}
		catch (Error e)
		{
			// An unreadable branch list gives an empty list, as IC-2 says.
			// There is no data to show, and this method can do nothing. The
			// caller shows an empty sidebar.
			warning("could not list branches: %s", e.message);
		}

		names.sort((a, b) => {
			return strcmp(a.casefold(), b.casefold());
		});

		return names;
	}

	/**
	 * Says if the repository has a stash (IC-102, P-FR-8).
	 */
	public static bool has_stash(Gitg.Repository repository)
	{
		try
		{
			return repository.lookup_reference("refs/stash") != null;
		}
		catch (Error e)
		{
			// A missing ref throws and does not return null. Thus each error
			// means "no stash".
			return false;
		}
	}

	/**
	 * The checked-out branch, or null if HEAD is detached (IC-105).
	 */
	public static string? current_branch(Gitg.Repository repository)
	{
		try
		{
			if (repository.is_head_detached())
			{
				return null;
			}

			var head = repository.get_head();

			return head != null ? head.get_shorthand() : null;
		}
		catch (Error e)
		{
			// An unborn HEAD throws here, and has no current branch to name.
			return null;
		}
	}

	/**
	 * Local branch tips, name to commit id (IC-104).
	 *
	 * The reset preview substitutes into this set (FR-124).
	 */
	public static Gee.Map<string, Ggit.OId> branch_tips(Gitg.Repository repository)
	{
		var tips = new Gee.HashMap<string, Ggit.OId>();

		try
		{
			var enumerator = repository.enumerate_branches(Ggit.BranchType.LOCAL);

			if (enumerator != null)
			{
				foreach (var branch in enumerator)
				{
					var name = short_name(branch);
					var target = branch.get_target();

					if (name != null && target != null)
					{
						tips.set(name, target);
					}
				}
			}
		}
		catch (Error e)
		{
			warning("could not read branch tips: %s", e.message);
		}

		return tips;
	}

	/**
	 * The data that `git reset --hard` would destroy if it ran now.
	 *
	 * The method counts files with changes that are only in the working tree
	 * or the index: modified, deleted, staged and conflicted files. It
	 * excludes untracked files, because `reset --hard` does not change them. A
	 * warning about them would be incorrect, and a repository with some unused
	 * build artefacts would always show a warning banner.
	 *
	 * This is the one condition that gitrl-z can warn about and the reflog
	 * cannot undo. A commit that a reset drops stays in the reflog.
	 * Uncommitted work that a reset destroys is permanently lost.
	 *
	 * Returns 0 for a bare repository, which has no working tree.
	 */
	public static uint uncommitted_changes(Gitg.Repository repository)
	{
		if (repository.is_bare)
		{
			return 0;
		}

		uint count = 0;

		// The code does not request untracked and ignored files. It does not
		// request them and then filter them. On a large tree, a scan of them
		// is the slow part of a status, and this method would not use the
		// result.
		var options = new Ggit.StatusOptions(Ggit.StatusOption.EXCLUDE_SUBMODULES,
		                                     Ggit.StatusShow.INDEX_AND_WORKDIR,
		                                     null);

		try
		{
			repository.file_status_foreach(options, (path, flags) => {
				if ((flags & DESTRUCTIVE) != 0)
				{
					count++;
				}

				return 0;
			});
		}
		catch (Error e)
		{
			// A status that the code cannot read must not report as "clean".
			// That result causes the deletion of the work of the user. Report
			// it as unknown, by the convention of the caller.
			warning("could not read working tree status: %s", e.message);
			return uint.MAX;
		}

		return count;
	}

	/**
	 * The git directory, for the file monitor (IC-107, FR-130).
	 *
	 * This method queries the repository, and does not add ".git" to the
	 * working directory. Thus it is correct in a linked worktree or a
	 * submodule, where .git is a file that points to a different location.
	 */
	public static File? git_directory(Gitg.Repository repository)
	{
		return repository.get_location();
	}
}

}

// ex:set ts=4 noet:
