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
 * Holds a maximum of one target commit for each local branch. That commit is
 * the commit that a reset would move the branch to. The bottom pane draws the
 * plan, and the command of the banner comes from it. Thus a plan of one branch
 * operates as a single selected entry did before, and a plan of many branches
 * repeats that behaviour.
 *
 * The key is the branch, and not the list position. A reflog row is a
 * position, and each entry moves down when new entries arrive. A branch and a
 * commit are an identity that stays after a reload. Thus the mark on a planned
 * row (FR-151) and the plan after a reload (FR-152) both use the branch and
 * the commit, and not the row that the user clicked.
 *
 * This class is pure: it has no widget and no repository. A test can use all
 * of it with no GTK main loop, which is where spec §6.1 puts its tests.
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

	/** Says if the plan moves no branch. */
	public bool is_empty()
	{
		return d_targets.size == 0;
	}

	/**
	 * The planned branches, in increasing name order.
	 *
	 * The order is fixed, thus the command that they build (FR-149) is a
	 * stable string. Without the order, the string would change with the
	 * iteration order of the hash map.
	 */
	public Gee.List<string> branches()
	{
		var names = new Gee.ArrayList<string>();
		names.add_all(d_targets.keys);
		names.sort();

		return names;
	}

	/** The commit that the plan moves a branch to, or null if it is absent. */
	public Ggit.OId? target_for(string branch)
	{
		return d_targets.has_key(branch) ? d_targets[branch] : null;
	}

	/**
	 * Says if the plan holds `branch` at `commit` (FR-151, FR-148).
	 *
	 * A reflog row uses this method to know if it is the row that put its
	 * branch in the plan. The same branch at a different commit is not a
	 * match, because only one row for each branch is the planned row.
	 */
	public bool contains(string branch, Ggit.OId commit)
	{
		return d_targets.has_key(branch) && d_targets[branch].equal(commit);
	}

	/**
	 * Toggles the position of a branch in the plan (FR-148).
	 *
	 * This is the three-way rule for the full interaction. For a branch and
	 * the commit of the clicked row:
	 *
	 *  - if the branch is not in the plan, add it with the target `commit`.
	 *  - if the branch is in the plan at a *different* commit, move its target
	 *    to `commit`. A branch has one position, thus a second choice replaces
	 *    the first and does not add a second entry.
	 *  - if the branch is in the plan at *this* commit, remove it. A second
	 *    click on the same row deselects it.
	 *
	 * The map is `d_targets`, from branch name to `Ggit.OId`.
	 * `contains(branch, commit)` above gives the third condition.
	 * `Gee.HashMap` has `has_key`, `set(key, value)` and `unset(key)`. Two ids
	 * compare with `a.equal(b)`.
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
	 * Sets the target of a branch. Replaces the previous target of that branch,
	 * and keeps the other branches.
	 *
	 * The keyboard selection uses this method (FR-148). Arrow movement changes
	 * the branch of the focused view to the new row, as a mouse click on that
	 * row does. Branches selected in other views stay in the plan. This method
	 * does not remove a branch, and toggle does. Thus a second arrival on the
	 * planned row of a branch keeps it planned, and does not deselect it.
	 */
	public void set_target(string branch, Ggit.OId commit)
	{
		d_targets[branch] = commit;
	}

	/**
	 * Replaces the full plan with one branch at `commit` (FR-148).
	 *
	 * The single selection of the HEAD view uses this method. There a row is
	 * one branch, thus a selection removes each other branch and keeps only
	 * the selected one. set_target is the equivalent method that keeps the
	 * others. Arrow movement uses this method, which does not deselect. A
	 * plain click uses set_only_or_clear, where a second click deselects. A
	 * Ctrl-click toggles, to build a multi-branch plan.
	 */
	public void set_only(string branch, Ggit.OId commit)
	{
		d_targets.clear();
		d_targets[branch] = commit;
	}

	/**
	 * Makes `branch` at `commit` the full plan, or clears the plan if it is
	 * already that (FR-148).
	 *
	 * The plain click of the HEAD view uses this method. The first click
	 * selects the row as the only target (set_only). A second click on the
	 * same row removes it, and the plan becomes empty. This is set_only with a
	 * deselect, and it is the single-selection equivalent of toggle.
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
	 * Removes a branch from the plan.
	 *
	 * The reload pruning uses this method when the object database no longer
	 * holds a target commit (FR-152). The plan cannot find this condition
	 * itself, because it holds no repository.
	 */
	public void remove(string branch)
	{
		d_targets.unset(branch);
	}

	/**
	 * Removes entries whose branch is not in `present` (FR-152).
	 *
	 * A reload calls this method with the branches that the repository still
	 * has. A deleted branch cannot move, thus it leaves the plan. The other
	 * branches stay. The caller does the commit-level pruning, for a target
	 * that the object database no longer holds. The caller holds the
	 * repository, and can look up the commit.
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
