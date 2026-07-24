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

/**
 * The reset preview (spec FR-148 to FR-150, P-FR-18).
 *
 * Turns a reset plan into the two things the bottom pane shows: the command
 * that would produce it, and the tip set the graph is drawn over. Both are
 * pure and in memory only. No ref is moved, nothing is written, and that is
 * the whole product: gitrl-z shows the command and leaves running it to you.
 *
 * The graph itself is drawn by gitg: preview_tips() hands its set to
 * Gitg.CommitModel.set_include(), and gitg's own lane engine and cell
 * renderers do the rest (IC-106). Where a planned branch's label is drawn is
 * decided separately, by the activity's own label override, so the graph
 * shows the whole tree while a branch's pill sits where a reset would land.
 */
public class ResetPreview : Object
{
	/**
	 * The branch a clicked row would toggle into the plan, or null when the
	 * row is not togglable (FR-148).
	 *
	 * The branch is:
	 *
	 *  - in a branch view, the branch whose reflog is shown;
	 *  - in the `all` view, the branch the row itself is attributed to
	 *    (P-FR-16).
	 *
	 * A row with no attributed branch, or one naming a branch not present in
	 * the current tips, is not togglable and returns null: a branch that does
	 * not exist cannot be moved by `git branch -f` or `git reset --hard`, and
	 * gitrl-z does not create one or silently retarget the checked-out branch.
	 * The `stash` view never reaches here (it keeps FR-142's own preview).
	 */
	public static string? target_branch_for(string view,
	                                        string? row_branch,
	                                        Gee.Map<string, Ggit.OId> tips)
	{
		string? branch = (view != "all" && view != "stash") ? view : row_branch;

		if (branch == null || !tips.has_key(branch))
		{
			return null;
		}

		return branch;
	}

	/**
	 * The tip set the preview graph is drawn over (FR-150, P-FR-18).
	 *
	 * The whole current tree stays visible: every real branch tip is kept, so
	 * commits a reset would abandon are still drawn. They stay recoverable
	 * from the reflog, which is the point of gitrl-z, so hiding them would
	 * hide the very thing it exists to show. Every planned target is added
	 * too, so a commit a reset would land on is present even when no current
	 * ref reaches it any more (an abandoned commit pulled back from the
	 * reflog). The tip set only decides which commits are drawn; a planned
	 * branch's label is moved onto its target by the activity, not here.
	 *
	 * Deduplicated by commit, so two branches sharing a tip, or a target that
	 * is already a tip, do not feed the walker the same commit twice.
	 */
	public static Ggit.OId[] preview_tips(Gee.Map<string, Ggit.OId> tips,
	                                      ResetPlan plan)
	{
		Ggit.OId[] result = {};

		foreach (var entry in tips.entries)
		{
			if (!contains_oid(result, entry.value))
			{
				result += entry.value;
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

		return result;
	}

	/** Whether `ids` already holds `id`, compared by commit identity. */
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

	/**
	 * The command that would produce the whole plan (FR-149).
	 *
	 * One rule per branch: a branch that is not the checked-out one is moved
	 * with `git branch -f`, which repoints the ref without touching the working
	 * tree and leaves a reflog entry, so the move stays recoverable inside
	 * gitrl-z; the checked-out branch, if it is in the plan, is moved with
	 * `git reset --hard`, because a checked-out ref cannot be moved by
	 * `git branch -f`, and this is the one move that updates the working tree.
	 *
	 * The `git branch -f` lines come first, in the plan's branch-name order;
	 * the single `git reset --hard`, if any, comes last, so the working-tree
	 * change is the final step. Joined with `; ` on one line. An empty plan is
	 * the empty string. A null `current_branch` (detached HEAD) means no line
	 * is a reset: every move is a `git branch -f`, and nothing touches the
	 * working tree.
	 */
	public static string command_for(ResetPlan plan, string? current_branch)
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

			if (current_branch != null && branch == current_branch)
			{
				reset_line = "git reset --hard %s".printf(abbrev);
			}
			else
			{
				lines += "git branch -f %s %s".printf(branch, abbrev);
			}
		}

		if (reset_line != null)
		{
			lines += reset_line;
		}

		return string.joinv("; ", lines);
	}
}

}

// ex:set ts=4 noet:
