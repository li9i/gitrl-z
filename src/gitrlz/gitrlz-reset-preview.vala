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
 * Changes a reset plan into the two items that the bottom pane shows: the
 * command that would give that plan, and the tip set for the graph. The two
 * are pure and in memory only. The code moves no ref and writes nothing.
 * gitrl-z shows the command, and you run it.
 *
 * gitg draws the graph. preview_tips() gives its set to
 * Gitg.CommitModel.set_include(), and the lane engine and cell renderers of
 * gitg do the remainder (IC-106). The label override of the activity decides
 * the position of the label of a planned branch. Thus the graph shows the full
 * tree, and the pill of a branch is at the position where a reset would put
 * it.
 */
public class ResetPreview : Object
{
	/**
	 * The branch that a clicked row would toggle into the plan, or null if the
	 * row does not toggle (FR-148).
	 *
	 * The branch is:
	 *
	 *  - in a branch view, the branch of the reflog that is shown.
	 *  - in the `all` view, the branch of the row itself (P-FR-16).
	 *
	 * A row with no branch returns null. A detached-HEAD position has no
	 * branch to move, and the `stash` view does not come here, because it
	 * keeps the preview of FR-142. The attribution is already null for a
	 * detached position or a bare-hash position, and is never a hash. Thus it
	 * is null or a real branch name.
	 *
	 * The method returns a real branch name that is not in the current tips
	 * (IC-166). That name is a deleted branch, and the plan can make it again
	 * at the commit of the row with `git branch <name> <sha>`. The `tips` map
	 * stays in the signature, so that callers do not change. But membership no
	 * longer controls the result.
	 */
	public static string? target_branch_for(string view,
	                                        string? row_branch,
	                                        Gee.Map<string, Ggit.OId> tips)
	{
		return (view != "all" && view != "stash") ? view : row_branch;
	}

	/**
	 * The tip set for the preview graph (FR-150, P-FR-18).
	 *
	 * The full current tree stays visible. The method keeps each real branch
	 * tip, thus the graph still draws the commits that a reset would abandon.
	 * The reflog can recover those commits, which is the purpose of gitrl-z.
	 * If the graph hid them, it would hide its own subject. The method also
	 * adds each planned target. Thus a commit that a reset would move to is
	 * present, also when no current ref reaches it. An example is an abandoned
	 * commit that comes back from the reflog. The tip set decides only which
	 * commits the graph draws. The activity moves the label of a planned
	 * branch onto its target, and this method does not.
	 *
	 * `opened_at` is the commit that HEAD was on when gitrl-z opened the
	 * repository, and it joins the set for the same cause as a planned target.
	 * A reset that ran in a terminal beside the window can leave that commit
	 * with no ref that reaches it. The graph would then stop drawing the
	 * position that the session started from, which is the one position the
	 * user is most likely to want again. In an untouched session it is already
	 * a branch tip, thus it adds nothing and the graph is unchanged.
	 *
	 * The method removes duplicates by commit. Thus two branches with the same
	 * tip, or a target that is already a tip, do not give the walker the same
	 * commit two times.
	 */
	public static Ggit.OId[] preview_tips(Gee.Map<string, Ggit.OId> tips,
	                                      ResetPlan plan,
	                                      Ggit.OId? opened_at = null)
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

		if (opened_at != null && !contains_oid(result, opened_at))
		{
			result += opened_at;
		}

		return result;
	}

	/** Says if `ids` already holds `id`, compared by commit identity. */
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
	 * The command that would give the full plan (FR-149, IC-165).
	 *
	 * There is one rule for each branch. The rule depends on the current state
	 * of the branch, and uses the set of branches that exist now (`existing`,
	 * the key set of the tips):
	 *
	 *  - `git reset --hard` moves the checked-out branch. `git branch -f`
	 *    cannot move a checked-out ref, and this is the one move that updates
	 *    the working tree.
	 *  - `git branch -f` moves a branch that exists and is not the checked-out
	 *    branch. It points the ref to a different commit, does not change the
	 *    working tree, and writes a reflog entry. Thus gitrl-z can recover the
	 *    move.
	 *  - plain `git branch` (with no `-f`) makes a branch that no longer
	 *    exists. This returns a deleted branch at the commit of the row
	 *    (FR-166).
	 *
	 * The branch lines come first, in the branch-name order of the plan. The
	 * one `git reset --hard`, if there is one, comes last. Thus the change to
	 * the working tree is the last step. The method joins the lines with `; `
	 * on one line. An empty plan gives an empty string. A null
	 * `current_branch` (detached HEAD) means that no line is a reset. Each
	 * move is then a `git branch -f` or a branch creation, and nothing changes
	 * the working tree. In practice the activity does not come here with a
	 * detached HEAD, because it offers a way back to a branch. But the rule is
	 * still correct.
	 */
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

		if (reset_line != null)
		{
			lines += reset_line;
		}

		return string.joinv("; ", lines);
	}
}

}

// ex:set ts=4 noet:
