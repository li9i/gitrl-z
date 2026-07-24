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
 * Ggit.ReflogEntry exposes the message, the committer signature and the old
 * and new ids, and nothing else. In particular it has no selector string and
 * no author: the displayed `<ref>@{n}` is built from the index here, and the
 * date comes from the committer signature. The Python implementation parsed
 * both out of git's own output; that parsing has no counterpart now.
 */
public class ReflogEntry : Object
{
	/** The ref whose reflog this entry came from: "HEAD", a branch, "stash". */
	public string ref_name { get; construct set; }

	/** Position in the reflog, 0 being the newest entry. */
	public uint index { get; construct set; }

	/** The commit the ref pointed at after this entry. */
	public Ggit.OId? new_id { get; construct set; }

	/** The commit the ref pointed at before it. */
	public Ggit.OId? old_id { get; construct set; }

	/** git's own reflog message, unchanged, as IC-8 describes it. */
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
	 * The abbreviated hash, as git's --abbrev-commit shows it.
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
 * Reading reflogs (spec IC-103).
 */
public class Reflog : Object
{
	/**
	 * Read the reflog of a ref, newest entry first.
	 *
	 * `ref_name` is "HEAD", a local branch name, or "stash".
	 *
	 * A ref that does not resolve — an unborn HEAD, a branch that has just
	 * been deleted, a repository with no stash — yields an empty list and no
	 * error, which is what IC-4 specified and what the placeholder in
	 * P-FR-14 expects.
	 */
	public static Gee.List<ReflogEntry> read(Gitg.Repository repository, string ref_name)
	{
		var entries = new Gee.ArrayList<ReflogEntry>();

		Ggit.Ref? reference = null;

		try
		{
			if (ref_name == "HEAD")
			{
				// Deliberately not dwim for HEAD.
				//
				// dwim resolves HEAD through to the branch it points at, and
				// the reflog you then read is that branch's (.git/logs/refs/
				// heads/main) rather than HEAD's own (.git/logs/HEAD). Those
				// are different logs: HEAD's records checkouts and resets
				// that never touched the branch, which is most of what the
				// `all` view exists to show. Looking the name up directly
				// keeps the symbolic ref, and with it the right log.
				reference = repository.lookup_reference("HEAD");
			}
			else
			{
				// dwim resolves a bare branch name and "stash" alike, which
				// covers the rest of what the sidebar offers.
				reference = repository.lookup_reference_dwim(ref_name);
			}
		}
		catch (Error e)
		{
			// A ref that does not resolve is not an error condition here: an
			// unborn HEAD, a deleted branch and an absent stash all land
			// exactly here, and all three mean "nothing to show" (IC-4).
			return entries;
		}

		if (reference == null)
		{
			// Distinct from the case above, and worth saying out loud.
			// lookup_reference_dwim() returns null when its cast to Gitg.Ref
			// fails, which means the Ggit -> Gitg object factory was never
			// registered. Silently returning "no entries" for that would
			// present a library initialisation bug as an empty reflog.
			warning("reflog lookup for '%s' returned no reference; " +
			        "is Gitg.init() called before opening a repository?", ref_name);
			return entries;
		}

		try
		{
			// Note the name: Ggit.Ref.get_log(), not get_reflog(). has_log()
			// distinguishes "no reflog file" from "reflog read failed".
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
