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
 *
 * You should have received a copy of the GNU General Public License along
 * with gitrl-z. If not, see <http://www.gnu.org/licenses/>.
 */

namespace Gitrlz
{

public class ReflogEntry : Object
{
	public string ref_name { get; construct set; }

	public uint index { get; construct set; }

	public Ggit.OId? new_id { get; construct set; }

	public Ggit.OId? old_id { get; construct set; }

	public string message { get; construct set; }

	public DateTime? date { get; construct set; }

	public ReflogEntry(string ref_name,
	                   uint index,
	                   Ggit.OId? new_id,
	                   Ggit.OId? old_id,
	                   string message,
	                   DateTime? date)
	{
		Object(ref_name: ref_name,
		       index: index,
		       new_id: new_id,
		       old_id: old_id,
		       message: message,
		       date: date);
	}

	public string selector
	{
		owned get { return "%s@{%u}".printf(ref_name, index); }
	}

	public string abbreviated_id
	{
		owned get
		{
			if (new_id == null)
			{
				return "";
			}

			var full = new_id.to_string();

			return full.length > 7 ? full.substring(0, 7) : full;
		}
	}
}

public class Reflog : Object
{
	public static Gee.List<ReflogEntry> read(Gitg.Repository repository,
	                                         string ref_name,
	                                         uint limit = 0)
	{
		var entries = new Gee.ArrayList<ReflogEntry>();

		Ggit.Ref? reference = null;

		try
		{
			if (ref_name == "HEAD")
			{
				reference = repository.lookup_reference("HEAD");
			}
			else
			{
				reference = repository.lookup_reference_dwim(ref_name);
			}
		}
		catch (Error e)
		{
			return entries;
		}

		if (reference == null)
		{
			warning("reflog lookup for '%s' returned no reference; " +
			        "is Gitg.init() called before opening a repository?", ref_name);
			return entries;
		}

		try
		{
			if (!reference.has_log())
			{
				return entries;
			}

			var log = reference.get_log();

			if (log == null)
			{
				return entries;
			}

			var count = log.get_entry_count();

			if (limit != 0 && limit < count)
			{
				count = limit;
			}

			for (uint i = 0; i < count; i++)
			{
				var entry = log.get_entry_from_index(i);

				if (entry == null)
				{
					continue;
				}

				DateTime? when = null;
				var committer = entry.get_committer();

				if (committer != null)
				{
					when = committer.get_time();
				}

				var message = entry.get_message();

				entries.add(new ReflogEntry(ref_name,
				                            i,
				                            entry.get_new_id(),
				                            entry.get_old_id(),
				                            message != null ? message : "",
				                            when));
			}
		}
		catch (Error e)
		{
			warning("could not read reflog for %s: %s", ref_name, e.message);
		}

		return entries;
	}
}

}
