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

/**
 * One reflog entry (spec IC-103).
 *
 * Ggit.ReflogEntry gives the message, the committer signature, and the old and
 * new ids. It gives nothing else. It has no selector string and no author.
 * This class builds the displayed `<ref>@{n}` from the index, and takes the
 * date from the committer signature. The Python implementation parsed the two
 * from the output of git. That code has no equivalent now.
 */
public class ReflogEntry : Object
{
	/** The ref whose reflog this entry came from: "HEAD", a branch, "stash". */
	public string ref_name { get; construct set; }

	/** Position in the reflog. 0 is the newest entry. */
	public uint index { get; construct set; }

	/** The commit the ref pointed at after this entry. */
	public Ggit.OId? new_id { get; construct set; }

	/** The commit the ref pointed at before it. */
	public Ggit.OId? old_id { get; construct set; }

	/** The reflog message of git, unchanged, as IC-8 describes it. */
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

	/**
	 * The selector as git writes it: `HEAD@{0}`, `feature@{3}`, `stash@{1}`.
	 */
	public string selector
	{
		owned get { return "%s@{%u}".printf(ref_name, index); }
	}

	/**
	 * The abbreviated hash, as --abbrev-commit of git shows it.
	 */
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

/**
 * Reads reflogs (spec IC-103).
 */
public class Reflog : Object
{
	/**
	 * Reads the reflog of a ref, newest entry first.
	 *
	 * `ref_name` is "HEAD", a local branch name, or "stash".
	 *
	 * `limit` is the number of entries to return, and 0 is the whole log. A
	 * caller that wants only the position a ref is at, and not its history,
	 * asks for one entry and does not pay for a long log (IC-169). The `index`
	 * of each entry stays its true position in the log, thus a limited read
	 * still gives `HEAD@{0}` and not a renumbered entry.
	 *
	 * If a ref does not resolve, the result is an empty list and no error.
	 * Examples are an unborn HEAD, a branch deleted a short time before, and a
	 * repository with no stash. IC-4 specifies this, and the placeholder in
	 * P-FR-14 needs it.
	 */
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
				// This code does not use dwim for HEAD.
				//
				// dwim resolves HEAD to the branch that it points at. The
				// reflog that you then read is the reflog of that branch
				// (.git/logs/refs/heads/main), and not the reflog of HEAD
				// (.git/logs/HEAD). These are different logs. The log of
				// HEAD records checkouts and resets that did not change the
				// branch, and the `all` view shows mostly those. A direct
				// lookup of the name keeps the symbolic ref, and thus the
				// correct log.
				reference = repository.lookup_reference("HEAD");
			}
			else
			{
				// dwim resolves a bare branch name and "stash" in the same
				// way. This covers the other items in the sidebar.
				reference = repository.lookup_reference_dwim(ref_name);
			}
		}
		catch (Error e)
		{
			// A ref that does not resolve is not an error here. An unborn
			// HEAD, a deleted branch and an absent stash all come here, and
			// the three mean "nothing to show" (IC-4).
			return entries;
		}

		if (reference == null)
		{
			// This is different from the condition above, and it needs a
			// message. lookup_reference_dwim() returns null if its cast to
			// Gitg.Ref fails. That means that the Ggit -> Gitg object
			// factory has no registration. A quiet result of "no entries"
			// would show a library initialisation bug as an empty reflog.
			warning("reflog lookup for '%s' returned no reference; " +
			        "is Gitg.init() called before opening a repository?", ref_name);
			return entries;
		}

		try
		{
			// The name is Ggit.Ref.get_log(), and not get_reflog(). has_log()
			// separates "no reflog file" from "reflog read failed".
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

// ex:set ts=4 noet:
