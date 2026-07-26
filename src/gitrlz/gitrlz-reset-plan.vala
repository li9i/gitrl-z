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
 * A multi-branch reset plan (spec FR-148, IC 4.1).
 *
 * Holds at most one target commit per local branch: the commit that branch
 * would be reset to. The plan is what the bottom pane draws and what the
 * banner's command is built from, so a plan of one behaves exactly like a
 * single selected entry used to, and a plan of many is the same idea repeated.
 *
 * Keyed by branch, not by list position. A reflog row is a position and every
 * entry shifts down as new ones arrive; a branch and a commit are an identity
 * that survives a reload. That is why the mark on a planned row (FR-151) and
 * the plan's survival across a reload (FR-152) are both expressed here in
 * terms of branch and commit rather than of which row was clicked.
 *
 * Pure: no widget, no repository. It can be exercised in full without a GTK
 * main loop, which is where spec §6.1 puts its tests.
 */
public class ResetPlan : Object
{
	private Gee.HashMap<string, Ggit.OId> d_targets;

	construct
	{
		d_targets = new Gee.HashMap<string, Ggit.OId>();
	}

	/** How many branches the plan moves. */
	public int size
	{
		get { return d_targets.size; }
	}

	/** Whether the plan moves nothing. */
	public bool is_empty()
	{
		return d_targets.size == 0;
	}

	/**
	 * The planned branches, in ascending name order.
	 *
	 * Ordered so the command they build (FR-149) is a stable, diffable string
	 * rather than one that reshuffles with the hash map's iteration order.
	 */
	public Gee.List<string> branches()
	{
		var names = new Gee.ArrayList<string>();
		names.add_all(d_targets.keys);
		names.sort();

		return names;
	}

	/** The commit a branch is planned to move to, or null when it is absent. */
	public Ggit.OId? target_for(string branch)
	{
		return d_targets.has_key(branch) ? d_targets[branch] : null;
	}

	/**
	 * Whether the plan holds `branch` at exactly `commit` (FR-151, FR-148).
	 *
	 * This is the question a reflog row asks to know whether it is the row that
	 * put its branch in the plan: same branch at a different commit is not a
	 * match, because only one row per branch is the planned one.
	 */
	public bool contains(string branch, Ggit.OId commit)
	{
		return d_targets.has_key(branch) && d_targets[branch].equal(commit);
	}

	/**
	 * Toggle a branch's place in the plan (FR-148).
	 *
	 * The three-way rule that drives the whole interaction. Given a branch and
	 * the commit of the clicked row:
	 *
	 *  - the branch is not in the plan  -> add it, targeting `commit`;
	 *  - the branch is in the plan at a *different* commit -> move its target
	 *    to `commit` (a branch has one position, so a second choice replaces
	 *    the first, it does not add a second entry);
	 *  - the branch is in the plan at *this* commit -> remove it (clicking the
	 *    same row again deselects it).
	 *
	 * The map is `d_targets`, from branch name to `Ggit.OId`. `contains(branch,
	 * commit)` above already answers the third case; `Gee.HashMap` has
	 * `has_key`, `set(key, value)` and `unset(key)`; two ids compare with
	 * `a.equal(b)`.
	 */
	public void toggle(string branch, Ggit.OId commit)
	{
		if (contains(branch, commit))
		{
			d_targets.unset(branch);
		}
		else
		{
			d_targets[branch] = commit;
		}
	}

	/**
	 * Set a branch's target, replacing its own previous one and keeping others.
	 *
	 * The keyboard select uses this (FR-148): arrow travel updates the focused
	 * view's branch to the landed row, exactly as a mouse click on that row
	 * would, while branches chosen in other views stay in the plan. Unlike
	 * toggle it never removes, so landing again on a branch's own planned row
	 * leaves it planned rather than deselecting it.
	 */
	public void set_target(string branch, Ggit.OId commit)
	{
		d_targets[branch] = commit;
	}

	/**
	 * Replace the whole plan with a single branch at `commit` (FR-148).
	 *
	 * The HEAD view's single selection uses this: there a row is one branch, so
	 * choosing it drops every other branch and keeps only the chosen one. It is
	 * the counterpart to set_target, which keeps the others; arrow travel picks
	 * this (it never deselects), a plain click picks set_only_or_clear (a second
	 * click deselects), and a Ctrl-click toggles to build a multi-branch plan.
	 */
	public void set_only(string branch, Ggit.OId commit)
	{
		d_targets.clear();
		d_targets[branch] = commit;
	}

	/**
	 * Make `branch` at `commit` the whole plan, or clear it when it already is
	 * (FR-148).
	 *
	 * The HEAD view's plain click uses this: the first click selects the row as
	 * the sole target (set_only), and clicking that same row again removes it,
	 * so the plan empties. It is set_only with a deselect, the single-selection
	 * counterpart of toggle.
	 */
	public void set_only_or_clear(string branch, Ggit.OId commit)
	{
		if (contains(branch, commit))
		{
			d_targets.unset(branch);
		}
		else
		{
			set_only(branch, commit);
		}
	}

	/**
	 * Remove a branch from the plan outright.
	 *
	 * Used by the reload pruning when a target commit has been pruned from the
	 * object database (FR-152), a condition the plan cannot see for itself
	 * because it holds no repository.
	 */
	public void remove(string branch)
	{
		d_targets.unset(branch);
	}

	/**
	 * Drop entries whose branch is not among `present` (FR-152).
	 *
	 * Called on a reload with the branches the repository still has. A branch
	 * that has been deleted cannot be moved, so it leaves the plan; the rest
	 * stay. Commit-level pruning (a target that has been pruned from the object
	 * database) is the caller's job, because it holds the repository to look
	 * the commit up in.
	 */
	public void prune(Gee.List<string> present)
	{
		var doomed = new Gee.ArrayList<string>();

		foreach (var branch in d_targets.keys)
		{
			if (!(branch in present))
			{
				doomed.add(branch);
			}
		}

		foreach (var branch in doomed)
		{
			d_targets.unset(branch);
		}
	}
}

}

// ex:set ts=4 noet:
