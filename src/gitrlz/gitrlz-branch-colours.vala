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
 * The branch-to-colour map (spec FR-153, IC 4.3).
 *
 * The colour of a branch in the reflog list must be the colour that the graph
 * of gitg gives it in the preview. If not, the two panes disagree. gitg
 * colours a lane when the lane opens during the revision walk (`Color.next()`
 * in `gitg-lane.vala`). Thus the colour of a branch is a function of the
 * *topological walk order*, and not of stable data such as the branch name.
 * To find the colour, the code must run the same walk.
 *
 * This class runs the lane engine of gitg over the branch tips of the
 * repository. It uses the sort mode and the reset that `Gitg.CommitModel`
 * uses. For each branch tip, it records the palette index of the lane that
 * receives the tip. The result is the colour that the graph draws for that
 * branch at the baseline (an empty plan). The code computes this one time for
 * each reload.
 *
 * Read-only: the walker and the lane engine traverse the history, and do not
 * write (NFR-4). This class does not modify vendored code. It uses
 * `Gitg.Lanes` and `Gitg.Color`, and does not patch them.
 */
public class BranchColours : Object
{
	/**
	 * Maps each branch in `tips` to the palette index that the graph of gitg
	 * would give it. If the walk does not place the tip of a branch, that
	 * branch stays absent.
	 *
	 * `tips` is the map of branch name to tip commit that the preview uses.
	 * The returned map has the same branch names as keys. If a branch is not
	 * in the map, callers read it as "no colour" (index -1). This is the same
	 * as the current treatment of an unknown branch (P-FR-16).
	 */
	public static Gee.Map<string, int> map(Gitg.Repository repository,
	                                       Gee.Map<string, Ggit.OId> tips)
	{
		var colours = new Gee.HashMap<string, int>();

		if (tips.size == 0)
		{
			return colours;
		}

		// A commit can be the tip of several branches. Thus the reverse lookup
		// is one id to many names. The key is the string form of the id, which
		// permits a comparison with a walked commit.
		var branches_at = new Gee.HashMap<string, Gee.List<string>>();

		foreach (var entry in tips.entries)
		{
			var key = entry.value.to_string();

			if (!branches_at.has_key(key))
			{
				branches_at[key] = new Gee.ArrayList<string>();
			}

			branches_at[key].add(entry.key);
		}

		try
		{
			var walker = new Ggit.RevisionWalker(repository);
			walker.reset();
			walker.set_sort_mode(Ggit.SortMode.TOPOLOGICAL | Ggit.SortMode.TIME);

			// The roots that the lane engine receives. They agree with the
			// `incset` that CommitModel.walk builds from the included tips.
			var roots = new Gee.HashSet<Ggit.OId>((Gee.HashDataFunc<Ggit.OId>)Ggit.OId.hash,
			                                      (Gee.EqualDataFunc<Ggit.OId>)Ggit.OId.equal);

			foreach (var entry in tips.entries)
			{
				walker.push(entry.value);
				roots.add(entry.value);
			}

			var lanes = new Gitg.Lanes();
			lanes.reset(new Ggit.OId[0], roots);

			// The lane engine of gitg keeps *weak* references to the commits
			// that it read (Lanes.d_previous). It reads them again when it
			// collapses inactive lanes on a long history. CommitModel keeps
			// each commit in an array because of this, and this code must do
			// the same. If it does not, those weak references become invalid
			// when the collapse starts, and the walk segfaults. Small
			// histories do not collapse. Thus the problem occurs only on a
			// large repository.
			var retained = new Gee.ArrayList<Gitg.Commit>();

			// Stop when each branch has a colour. The tips are near the top of
			// the history, thus the walk is usually short. This also limits
			// the cost on a large repository (spec §3).
			while (colours.size < tips.size)
			{
				var id = walker.next();

				if (id == null)
				{
					break;
				}

				var commit = repository.lookup<Gitg.Commit>(id);

				if (commit == null)
				{
					continue;
				}

				retained.add(commit);

				SList<Gitg.Lane> lns;
				int mylane;

				if (lanes.next(commit, out lns, out mylane, true))
				{
					commit.update_lanes((owned)lns, mylane);
					record(colours, branches_at, commit);
				}

				// If the parents of a commit are not yet placed, the commit
				// goes to miss_commits for a retry. CommitModel.walk does the
				// same. This code copies that behaviour, so that the lane-open
				// order, and thus the colours, agree with the graph exactly.
				while (lanes.miss_commits.size > 0)
				{
					var progressed = false;
					var iter = lanes.miss_commits.iterator();

					while (iter.next())
					{
						var missed = iter.get();

						if (lanes.next(missed, out lns, out mylane))
						{
							progressed = true;
							iter.remove();
							missed.update_lanes((owned)lns, mylane);
							record(colours, branches_at, missed);
						}
					}

					if (!progressed)
					{
						break;
					}
				}
			}
		}
		catch (Error e)
		{
			// If the walk cannot run, the map keeps the data that the walk
			// found. For a failure at construction, the map is empty. Each
			// chip then renders with no colour (spec §5). gitrl-z opens
			// correctly even when it cannot compute a colour.
			warning("branch colour walk failed: %s", e.message);
		}

		return colours;
	}

	/**
	 * If `commit` is a branch tip with no record, record the colour of its
	 * lane.
	 *
	 * The first write has priority. The walk emits a tip one time only, and
	 * the colour of its lane at that time is the graph colour for the branch.
	 */
	private static void record(Gee.Map<string, int> colours,
	                           Gee.Map<string, Gee.List<string>> branches_at,
	                           Gitg.Commit commit)
	{
		var key = commit.get_id().to_string();

		if (!branches_at.has_key(key))
		{
			return;
		}

		var lane = commit.lane;

		if (lane == null || lane.color == null)
		{
			return;
		}

		var index = (int)lane.color.idx;

		foreach (var branch in branches_at[key])
		{
			if (!colours.has_key(branch))
			{
				colours[branch] = index;
			}
		}
	}
}

}

// ex:set ts=4 noet:
