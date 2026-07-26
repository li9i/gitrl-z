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
 * Every repository handle in gitrl-z is created by open() here, and every
 * repository read goes through one of these functions, so the read-only
 * guarantee can be checked at one place rather than argued about across the
 * codebase.
 *
 * Note that the handle is a Gitg.Repository, which *extends*
 * Ggit.Repository rather than wrapping it. There is no separate Gitrlz
 * repository type to hide the Ggit API behind: hiding it would mean
 * re-exporting most of it. What this class provides instead is the set of
 * reads gitrl-z actually performs, each with the error handling the spec
 * asks for.
 *
 * Ggit is not thread safe per handle and every call here is synchronous, so
 * these must be called from the main loop.
 */
public class Repository : Object
{
	/*
	 * The status flags that `git reset --hard` would destroy.
	 *
	 * At class scope rather than inside uncommitted_changes(): Vala cannot
	 * reach a local constant from inside a closure, and the status callback
	 * is one.
	 *
	 * Deliberately excludes WORKING_TREE_NEW (untracked) and IGNORED, which
	 * a hard reset leaves alone.
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
	 * Open the repository at a location discovered by
	 * Application.discover_repository.
	 *
	 * This is the only place a repository handle is created (NFR-4).
	 */
	public static Gitg.Repository open(File location) throws RepositoryError
	{
		try
		{
			// Gitg.init() registers the Ggit -> Gitg object factory, and
			// Gitg.Repository's own lookup_reference_dwim() casts its result
			// to a Gitg.Ref. Without the factory that cast yields null, and
			// every ref lookup then looks like a missing ref rather than an
			// uninitialised library — which is exactly how it presented when
			// the reflog tests first ran.
			//
			// Doing it here rather than trusting callers means any code that
			// gets as far as a repository handle is correctly set up. It is
			// idempotent, and in the application startup() has already called
			// it with a display present, so this never becomes the call that
			// consumes the guard and skips the CSS (see vendor/patches).
			Gitg.init();

			return new Gitg.Repository(location, null);
		}
		catch (Error e)
		{
			throw new RepositoryError.NOT_A_REPOSITORY("%s", e.message);
		}
	}

	/**
	 * Which multi-step git operation is in progress, or null (IC-164).
	 *
	 * Ggit does not expose repository state, so the same filesystem markers
	 * libgit2's git_repository_state inspects are read directly under the git
	 * directory: rebase-merge/ or rebase-apply/ for a rebase, then MERGE_HEAD,
	 * CHERRY_PICK_HEAD, REVERT_HEAD and BISECT_LOG. Checked in that fixed
	 * precedence, the first match wins.
	 *
	 * A pure, read-only function of the filesystem (NFR-44, NFR-45). An
	 * unreadable or absent git directory reports no operation rather than
	 * inventing one (spec section 5).
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
	 * A branch's short name: "main", not "refs/heads/main".
	 *
	 * The object factory hands back a Gitg.BranchBase, whose get_name()
	 * reports the full ref name. gitg's own ParsedRefName is what knows how
	 * to shorten it, and it handles the other ref prefixes too rather than
	 * assuming refs/heads/.
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
	 * Local branch names, sorted case-insensitively (IC-101, P-FR-7).
	 *
	 * git's own order is bytewise, which puts every uppercase name before
	 * every lowercase one; the sidebar wants them mixed as a reader would
	 * expect.
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
			// An unreadable branch list yields an empty one, as IC-2 had it.
			// There is nothing useful to show and nothing to be done about
			// it here; the caller shows an empty sidebar.
			warning("could not list branches: %s", e.message);
		}

		names.sort((a, b) => {
			return strcmp(a.casefold(), b.casefold());
		});

		return names;
	}

	/**
	 * Whether the repository has a stash (IC-102, P-FR-8).
	 */
	public static bool has_stash(Gitg.Repository repository)
	{
		try
		{
			return repository.lookup_reference("refs/stash") != null;
		}
		catch (Error e)
		{
			// A missing ref throws rather than returning null, so any error
			// reads as "no stash".
			return false;
		}
	}

	/**
	 * The checked-out branch, or null when HEAD is detached (IC-105).
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
	 * This is the set the reset preview substitutes into (FR-124).
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
	 * What `git reset --hard` would destroy if it ran now.
	 *
	 * Counts files with changes that exist only in the working tree or the
	 * index — modified, deleted, staged, conflicted. Untracked files are
	 * deliberately excluded: `reset --hard` leaves them alone, so warning
	 * about them would be crying wolf, and a repository with a few stray
	 * build artefacts would permanently show a scary banner.
	 *
	 * This is the one thing gitrl-z can warn about that the reflog cannot
	 * undo. A commit dropped by a reset is still in the reflog; uncommitted
	 * work destroyed by one is gone for good.
	 *
	 * Returns 0 for a bare repository, which has no working tree to dirty.
	 */
	public static uint uncommitted_changes(Gitg.Repository repository)
	{
		if (repository.is_bare)
		{
			return 0;
		}

		uint count = 0;

		// Untracked and ignored files are not requested at all, rather than
		// requested and filtered: on a large tree, scanning them is the
		// expensive part of a status and nothing here would use the result.
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
			// A status that cannot be read must not be reported as "clean":
			// that is the reading that gets someone's work deleted. Report it
			// as unknown by the caller's convention instead.
			warning("could not read working tree status: %s", e.message);
			return uint.MAX;
		}

		return count;
	}

	/**
	 * The git directory, for the file monitor (IC-107, FR-130).
	 *
	 * Asking the repository rather than joining ".git" onto the working
	 * directory is what makes this correct in a linked worktree or a
	 * submodule, where .git is a file pointing elsewhere.
	 */
	public static File? git_directory(Gitg.Repository repository)
	{
		return repository.get_location();
	}
}

}

// ex:set ts=4 noet:
