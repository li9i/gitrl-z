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

public class Repository : Object
{
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

	public static bool any_reaches(Gitg.Repository repository,
	                               Gee.Collection<Ggit.OId> tips,
	                               Ggit.OId commit)
	{
		foreach (var tip in tips)
		{
			try
			{
				if (tip.equal(commit) || repository.get_descendant_of(tip, commit))
				{
					return true;
				}
			}
			catch (Error e)
			{
				warning("could not test whether %s reaches %s: %s",
				        tip.to_string(), commit.to_string(), e.message);
			}
		}

		return false;
	}

	public static Gitg.Repository open(File location) throws RepositoryError
	{
		try
		{
			Gitg.init();

			return new Gitg.Repository(location, null);
		}
		catch (Error e)
		{
			throw new RepositoryError.NOT_A_REPOSITORY("%s", e.message);
		}
	}

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
			warning("could not list branches: %s", e.message);
		}

		names.sort((a, b) => {
			return strcmp(a.casefold(), b.casefold());
		});

		return names;
	}

	public static bool has_stash(Gitg.Repository repository)
	{
		try
		{
			return repository.lookup_reference("refs/stash") != null;
		}
		catch (Error e)
		{
			return false;
		}
	}

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
			return null;
		}
	}

	public static Ggit.OId? head_commit(Gitg.Repository repository)
	{
		try
		{
			var head = repository.get_head();

			return head != null ? head.get_target() : null;
		}
		catch (Error e)
		{
			return null;
		}
	}

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

	public static uint uncommitted_changes(Gitg.Repository repository)
	{
		if (repository.is_bare)
		{
			return 0;
		}

		uint count = 0;

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
			warning("could not read working tree status: %s", e.message);
			return uint.MAX;
		}

		return count;
	}

	public static File? git_directory(Gitg.Repository repository)
	{
		return repository.get_location();
	}
}

}
