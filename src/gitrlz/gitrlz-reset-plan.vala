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

public class ResetPlan : Object
{
	private Gee.HashMap<string, Ggit.OId> d_targets;
	private Gee.HashSet<string> d_deletions;

	construct
	{
		d_targets = new Gee.HashMap<string, Ggit.OId>();
		d_deletions = new Gee.HashSet<string>();
	}

	public void adopt(ResetPlan other)
	{
		d_targets.clear();
		d_deletions.clear();

		foreach (var branch in other.branches())
		{
			d_targets[branch] = other.target_for(branch);
		}

		foreach (var branch in other.deletions())
		{
			d_deletions.add(branch);
		}
	}

	public void clear()
	{
		d_targets.clear();
		d_deletions.clear();
	}

	public int size
	{
		get { return d_targets.size + d_deletions.size; }
	}

	public bool is_empty()
	{
		return d_targets.size == 0 && d_deletions.size == 0;
	}

	public Gee.List<string> branches()
	{
		var names = new Gee.ArrayList<string>();
		names.add_all(d_targets.keys);
		names.sort();

		return names;
	}

	public Gee.List<string> deletions()
	{
		var names = new Gee.ArrayList<string>();
		names.add_all(d_deletions);
		names.sort();

		return names;
	}

	public bool is_deleted(string branch)
	{
		return d_deletions.contains(branch);
	}

	public void set_deleted(string branch)
	{
		d_targets.unset(branch);
		d_deletions.add(branch);
	}

	public Ggit.OId? target_for(string branch)
	{
		return d_targets.has_key(branch) ? d_targets[branch] : null;
	}

	public bool contains(string branch, Ggit.OId commit)
	{
		return d_targets.has_key(branch) && d_targets[branch].equal(commit);
	}

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

	public void set_target(string branch, Ggit.OId commit)
	{
		d_deletions.remove(branch);
		d_targets[branch] = commit;
	}

	public void set_only(string branch, Ggit.OId commit)
	{
		d_targets.clear();
		d_deletions.clear();
		d_targets[branch] = commit;
	}

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

	public void remove(string branch)
	{
		d_targets.unset(branch);
		d_deletions.remove(branch);
	}

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

		foreach (var branch in d_deletions)
		{
			if (!(branch in present))
			{
				doomed.add(branch);
			}
		}

		foreach (var branch in doomed)
		{
			d_targets.unset(branch);
			d_deletions.remove(branch);
		}
	}
}

}
