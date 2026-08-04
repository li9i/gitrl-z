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
 * Where each ref stood when the window opened (spec FR-170, IC-168).
 *
 * The activity reads this once, at the point that it takes the repository, and
 * a reload never reads it again. The reflog grows under an open window
 * whenever the user runs git in a terminal beside it, and what the mark
 * reports is the state at open.
 *
 * A stored entry is found again by its content, and not by its position. A
 * reflog entry has no identity of its own, and the two positional alternatives
 * both fail. An index of 0 follows the log forward instead of staying where
 * the session began, and an offset counted back from the number of entries
 * breaks when `git gc` expires old entries from the tail.
 *
 * Only read() touches a repository. index_of() is static and takes none, thus
 * the matching rule is testable over lists that a test builds by hand.
 */
public class SessionStart : Object
{
	// Keyed by the ref name that Reflog.read takes: "HEAD", a branch name, or
	// "stash". A ref whose log was empty at open has no key here, and its view
	// carries no mark.
	private Gee.HashMap<string, ReflogEntry> d_entries;

	construct
	{
		d_entries = new Gee.HashMap<string, ReflogEntry>();
	}

	/**
	 * Reads the newest entry of the reflog of HEAD, of each branch, and of the
	 * stash when there is one.
	 *
	 * Each read asks for one entry (IC-169). A repository with a hundred
	 * branches then reads a hundred single entries, and not a hundred whole
	 * logs. A ref that does not resolve gives an empty list and no error, thus
	 * an unborn HEAD stores nothing and does not fail.
	 */
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

	/** The entry that was newest for `ref_name` at open, or null. */
	public ReflogEntry? entry_for(string ref_name)
	{
		return d_entries.has_key(ref_name) ? d_entries[ref_name] : null;
	}

	/**
	 * The index in `entries` of the entry that `ref_name` started at, or -1.
	 *
	 * A ref with no stored entry gives -1, and so the caller marks no row. A
	 * branch created after the window opened is the common case of that.
	 */
	public int index_in(string ref_name, Gee.List<ReflogEntry> entries)
	{
		return index_of(entry_for(ref_name), entries);
	}

	/**
	 * The same match against one stored entry, with no repository.
	 *
	 * The topmost entry whose new commit, old commit, message and date all
	 * equal the stored one, and -1 when there is none. The walk runs from the
	 * top, thus two rows of the same content give the topmost. The same
	 * operation run twice in one second writes two entries that agree on all
	 * four fields, and the user cannot tell those two apart either.
	 */
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

	/**
	 * Two commits, with null equal to null.
	 *
	 * Ggit.OId.equal needs an instance to call it on, and both ids of an entry
	 * can be null. Thus the null pair is answered here and never reaches it.
	 */
	private static bool same_id(Ggit.OId? a, Ggit.OId? b)
	{
		if (a == null || b == null)
		{
			return a == b;
		}

		return a.equal(b);
	}

	/**
	 * Two dates, with null equal to null.
	 *
	 * An entry whose committer signature was missing has no date, for the same
	 * reason that same_id handles the null pair here. The measure is Unix time,
	 * so the zone that git recorded does not decide the answer.
	 */
	private static bool same_date(DateTime? a, DateTime? b)
	{
		if (a == null || b == null)
		{
			return a == b;
		}

		return a.to_unix() == b.to_unix();
	}

	/** Reads one entry for `ref_name` and keeps it when there is one. */
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

// ex:set ts=4 noet:
