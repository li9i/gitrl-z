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

public class BranchColours : Object
{
	public static Gee.Map<string, int> map(Gitg.Repository repository,
	                                       Gee.Map<string, Ggit.OId> tips)
	{
		var colours = new Gee.HashMap<string, int>();

		if (tips.size == 0)
		{
			return colours;
		}

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

			var roots = new Gee.HashSet<Ggit.OId>((Gee.HashDataFunc<Ggit.OId>)Ggit.OId.hash,
			                                      (Gee.EqualDataFunc<Ggit.OId>)Ggit.OId.equal);

			foreach (var entry in tips.entries)
			{
				walker.push(entry.value);
				roots.add(entry.value);
			}

			var lanes = new Gitg.Lanes();
			lanes.reset(new Ggit.OId[0], roots);

			var retained = new Gee.ArrayList<Gitg.Commit>();

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
			warning("branch colour walk failed: %s", e.message);
		}

		return colours;
	}

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
