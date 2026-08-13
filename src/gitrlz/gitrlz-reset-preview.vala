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

namespace Gitrlz
{

public class ResetPreview : Object
{
	public static string? target_branch_for(string view,
	                                        string? row_branch,
	                                        Gee.Map<string, Ggit.OId> tips)
	{
		return (view != "all" && view != "stash") ? view : row_branch;
	}

	public static Ggit.OId[] preview_tips(Gee.Map<string, Ggit.OId> tips,
	                                      ResetPlan plan,
	                                      Ggit.OId? opened_at = null)
	{
		Ggit.OId[] result = {};

		foreach (var entry in tips.entries)
		{
			if (plan.is_deleted(entry.key))
			{
				continue;
			}

			var moved = plan.target_for(entry.key);
			var id = moved != null ? moved : entry.value;

			if (!contains_oid(result, id))
			{
				result += id;
			}
		}

		foreach (var branch in plan.branches())
		{
			var target = plan.target_for(branch);

			if (target != null && !contains_oid(result, target))
			{
				result += target;
			}
		}

		if (plan.is_empty() && opened_at != null && !contains_oid(result, opened_at))
		{
			result += opened_at;
		}

		return result;
	}

	private static bool contains_oid(Ggit.OId[] ids, Ggit.OId id)
	{
		foreach (var existing in ids)
		{
			if (existing.equal(id))
			{
				return true;
			}
		}

		return false;
	}

	public static string command_for(ResetPlan plan,
	                                 string? current_branch,
	                                 Gee.Collection<string> existing)
	{
		if (plan.is_empty())
		{
			return "";
		}

		string[] lines = {};
		string? reset_line = null;

		foreach (var branch in plan.branches())
		{
			var commit = plan.target_for(branch);

			if (commit == null)
			{
				continue;
			}

			var sha = commit.to_string();
			var abbrev = sha.length > 7 ? sha.substring(0, 7) : sha;

			if (branch == current_branch)
			{
				reset_line = "git reset --hard %s".printf(abbrev);
			}
			else if (existing.contains(branch))
			{
				lines += "git branch -f %s %s".printf(branch, abbrev);
			}
			else
			{
				lines += "git branch %s %s".printf(branch, abbrev);
			}
		}

		foreach (var branch in plan.deletions())
		{
			if (branch == current_branch || !existing.contains(branch))
			{
				continue;
			}

			lines += "git branch -D %s".printf(branch);
		}

		if (reset_line != null)
		{
			lines += reset_line;
		}

		return string.joinv("\n", lines);
	}

	public static string? undeletable_branch(ResetPlan plan, string? current_branch)
	{
		if (current_branch == null)
		{
			return null;
		}

		return plan.is_deleted(current_branch) ? current_branch : null;
	}
}

}
