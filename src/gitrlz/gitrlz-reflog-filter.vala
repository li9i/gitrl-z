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
 * The time window that limits the reflog list (spec FR-156, IC-162).
 *
 * There are three presets only, because the spec has no custom window. The
 * `seconds` accessor changes a preset into the length that
 * ReflogFilter.visible() measures against. ANY gives zero, and visible()
 * reads zero as "no window".
 */
public enum TimeWindow
{
	ANY,
	LAST_10_MIN,
	LAST_HOUR;

	public int64 seconds()
	{
		switch (this)
		{
			case LAST_10_MIN: return 600;
			case LAST_HOUR: return 3600;
			default: return 0;
		}
	}
}

/**
 * Decides which reflog rows stay visible after a limit (spec IC-160, IC-161).
 *
 * This class has logic only and no widgets. The reflog list computes its
 * visible set through visible(). Thus a test can give the combine rule of
 * FR-158 an injected `now`. A live fixture cannot do this, because its
 * entries are all some seconds old. The reflog list owns the
 * `Gtk.TreeModelFilter`. This class only says, for each entry, if the entry
 * stays.
 */
public class ReflogFilter : Object
{
	/**
	 * The count that a typed Entries value gives (IC-161).
	 *
	 * The result is the first group of decimal digits in `text`, if that group
	 * is a positive whole number. If not, the result is 0, and visible() reads
	 * 0 as "no limit". Thus "All" gives 0, "Last 10" gives 10, and "25" gives
	 * 25. An empty or non-numeric field gives 0. The Entries control is an
	 * editable combo, thus any text can arrive here, and no text is an error
	 * (spec section 5).
	 */
	public static uint parse_count(string text)
	{
		var digits = new StringBuilder();

		for (var i = 0; i < text.length; i++)
		{
			var c = text[i];

			if (c >= '0' && c <= '9')
			{
				digits.append_c(c);
			}
			else if (digits.len > 0)
			{
				// The first group of digits stops here. Ignore the remainder.
				break;
			}
		}

		if (digits.len == 0)
		{
			return 0;
		}

		var value = int64.parse(digits.str);

		return value > 0 ? (uint)value : 0;
	}

	/**
	 * Gives the entries in `entries` that a limit leaves visible (IC-160).
	 *
	 * `entries` is newest first, as Reflog.read returns it. The code applies
	 * the predicates to each entry in this order: substring search (FR-117),
	 * then the time window (FR-156), then the entry count (FR-157). A
	 * `window_seconds` of 0 or less is Any time. A `count` of 0 is All. A
	 * `search` of "" is no search. An entry with no date always passes the
	 * window (FR-159). The returned array has one flag for each entry, in the
	 * same order, and true means visible.
	 */
	public static bool[] visible(Gee.List<ReflogEntry> entries,
	                             DateTime now,
	                             int64 window_seconds,
	                             uint count,
	                             string search)
	{
		var result = new bool[entries.size];

		// The oldest time that an entry can have and stay in the window. Null
		// if there is no window, and then the code does not do the window
		// check.
		DateTime? cutoff = window_seconds > 0
			? now.add_seconds(-(double)window_seconds)
			: null;

		// The number of visible rows to this point, for the count limit. The
		// list is newest first, thus the first `count` rows that pass are the
		// newest `count` rows.
		uint shown = 0;

		for (var i = 0; i < entries.size; i++)
		{
			var entry = entries[i];
			var pass = true;

			// Search (FR-117): the message or the abbreviated id contains the
			// term. The comparison is against the entry, as the list did
			// before.
			if (search != "")
			{
				pass = entry.message.down().contains(search)
					|| entry.abbreviated_id.down().contains(search);
			}

			// Time window (FR-156, FR-159): an entry with no date always
			// passes. Thus the clock cannot hide the newest entry.
			if (pass && cutoff != null && entry.date != null)
			{
				pass = entry.date.compare(cutoff) >= 0;
			}

			// Entry count (FR-157, FR-158): keep only the newest `count` rows
			// that passed the search and the window. A `count` of 0 is no
			// limit. Only a row that still passes counts against the limit.
			// Thus a search miss or a window miss does not use one of the
			// newest positions.
			if (pass && count > 0)
			{
				if (shown >= count)
				{
					pass = false;
				}
				else
				{
					shown++;
				}
			}

			result[i] = pass;
		}

		return result;
	}
}

}

// ex:set ts=4 noet:
