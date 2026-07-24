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
 * A branch's colour in the reflog list has to be the colour gitg's graph
 * gives it in the preview, or the two panes disagree. gitg colours a lane the
 * moment it opens during the revision walk (`Color.next()` in
 * `gitg-lane.vala`), so a branch's colour is a function of the *topological
 * walk order*, not of anything stable like the branch's name. The only way to
 * learn it is to run the same walk.
 *
 * That is what this does: it runs gitg's own lane engine over the repository's
 * actual branch tips, with the sort mode and reset that `Gitg.CommitModel`
 * uses, and records for each branch tip the palette index of the lane it lands
 * on. The result is the colour the graph draws that branch at the baseline
 * (an empty plan), computed once per reload.
 *
 * Read-only: the walker and the lane engine traverse, they do not write
 * (NFR-4). No vendored code is modified; this uses `Gitg.Lanes` and
 * `Gitg.Color`, it does not patch them.
 */
public class BranchColours : Object
{
	/**
	 * Map each branch in `tips` to the palette index gitg's graph would give
	 * it, or leave it absent when the walk never places its tip.
	 *
	 * `tips` is the branch-name to tip-commit map the preview is drawn over.
	 * The returned map is keyed by the same branch names; a branch missing
	 * from it is read by callers as "no colour" (index -1), exactly as an
	 * unknown branch is treated today (P-FR-16).
	 */
	public static Gee.Map<string, int> map(Gitg.Repository repository,
	                                       Gee.Map<string, Ggit.OId> tips)
	{
		var colours = new Gee.HashMap<string, int>();

		if (tips.size == 0)
		{
			return colours;
		}

		// A commit can be several branches' tip at once, so the reverse lookup
		// is one id to many names. Keyed by the id's string form, which is what
		// a walked commit can be compared by.
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

			// The roots the lane engine is told about, matching the `incset`
			// CommitModel.walk builds from the included tips.
			var roots = new Gee.HashSet<Ggit.OId>((Gee.HashDataFunc<Ggit.OId>)Ggit.OId.hash,
			                                      (Gee.EqualDataFunc<Ggit.OId>)Ggit.OId.equal);

			foreach (var entry in tips.entries)
			{
				walker.push(entry.value);
				roots.add(entry.value);
			}

			var lanes = new Gitg.Lanes();
			lanes.reset(new Ggit.OId[0], roots);

			// gitg's lane engine keeps *weak* references to the commits it has
			// seen (Lanes.d_previous), and reaches back into them when it
			// collapses inactive lanes on a long history. CommitModel keeps
			// every commit alive in an array for exactly this reason, and so
			// must this: without it those weak references dangle the moment
			// collapsing begins, and the walk segfaults. Small histories never
			// collapse, which is why this only bites on a real repository.
			var retained = new Gee.ArrayList<Gitg.Commit>();

			// Stop once every branch has a colour. The tips sit near the top of
			// the history, so this is usually a short walk, and it bounds the
			// cost on a large repository (spec §3).
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

				// A commit whose parents are not placed yet is parked in
				// miss_commits and retried, exactly as CommitModel.walk does.
				// Replicated so the lane-open order, and thus the colours, match
				// the graph rather than merely approximating it.
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
			// A walk that cannot run leaves the map as far as it got, which for
			// a failure at construction is empty. Every chip then renders
			// uncoloured (spec §5); gitrl-z does not fail to open over a colour
			// it could not compute.
			warning("branch colour walk failed: %s", e.message);
		}

		return colours;
	}

	/**
	 * If `commit` is a branch tip not yet recorded, note its lane's colour.
	 *
	 * First writing wins: a tip is emitted once, and its lane's colour at that
	 * moment is the graph's colour for the branch.
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
