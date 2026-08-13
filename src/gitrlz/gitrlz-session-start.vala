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

public class SessionStart : Object
{
	private Gee.HashMap<string, ReflogEntry> d_entries;

	construct
	{
		d_entries = new Gee.HashMap<string, ReflogEntry>();
	}

	public static SessionStart read(Gitg.Repository repository,
	                                Gee.List<string> branches,
	                                bool has_stash)
	{
		var start = new SessionStart();

		start.store(repository, "HEAD");

		foreach (var branch in branches)
		{
			start.store(repository, branch);
		}

		if (has_stash)
		{
			start.store(repository, "stash");
		}

		return start;
	}

	public ReflogEntry? entry_for(string ref_name)
	{
		return d_entries.has_key(ref_name) ? d_entries[ref_name] : null;
	}

	public int boundary_in(Gee.List<ReflogEntry> entries)
	{
		var when = latest_date();

		if (when == null)
		{
			return -1;
		}

		for (var i = 0; i < entries.size; i++)
		{
			if (entries[i].date != null && entries[i].date.compare(when) <= 0)
			{
				return i;
			}
		}

		return -1;
	}

	public DateTime? latest_date()
	{
		DateTime? newest = null;

		foreach (var entry in d_entries.values)
		{
			if (entry.date == null)
			{
				continue;
			}

			if (newest == null || entry.date.compare(newest) > 0)
			{
				newest = entry.date;
			}
		}

		return newest;
	}

	public int index_in(string ref_name, Gee.List<ReflogEntry> entries)
	{
		return index_of(entry_for(ref_name), entries);
	}

	public static int index_of(ReflogEntry? start, Gee.List<ReflogEntry> entries)
	{
		if (start == null)
		{
			return -1;
		}

		for (var i = 0; i < entries.size; i++)
		{
			var entry = entries[i];

			if (same_id(start.new_id, entry.new_id)
			    && same_id(start.old_id, entry.old_id)
			    && start.message == entry.message
			    && same_date(start.date, entry.date))
			{
				return i;
			}
		}

		return -1;
	}

	private static bool same_id(Ggit.OId? a, Ggit.OId? b)
	{
		if (a == null || b == null)
		{
			return a == b;
		}

		return a.equal(b);
	}

	private static bool same_date(DateTime? a, DateTime? b)
	{
		if (a == null || b == null)
		{
			return a == b;
		}

		return a.to_unix() == b.to_unix();
	}

	private void store(Gitg.Repository repository, string ref_name)
	{
		var entries = Reflog.read(repository, ref_name, 1);

		if (entries.size > 0)
		{
			d_entries[ref_name] = entries[0];
		}
	}
}

}
