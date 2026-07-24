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
 * The time window the reflog list can be limited to (spec FR-156, IC-162).
 *
 * Three presets and no more: the spec offers no custom window. The `seconds`
 * accessor turns a preset into the length ReflogFilter.visible() measures
 * against, with ANY mapping to zero, which visible() reads as "no window".
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
 * Deciding which reflog rows a limit leaves visible (spec IC-160, IC-161).
 *
 * Pure logic, no widgets: the reflog list computes its visible set through
 * visible() so the combine rule of FR-158 can be tested against an injected
 * `now`, which a live fixture cannot exercise (its entries are all seconds
 * old). The reflog list owns the `Gtk.TreeModelFilter`; this only says, per
 * entry, whether it stays.
 */
public class ReflogFilter : Object
{
	/**
	 * The count a typed Entries value means (IC-161).
	 *
	 * The first run of decimal digits in `text`, when it is a positive whole
	 * number; otherwise 0, which visible() reads as "no cap". So "All" gives 0,
	 * "Last 10" gives 10, "25" gives 25, and a blank or non-numeric field gives
	 * 0. The Entries control is an editable combo, so anything at all can arrive
	 * here, and none of it is an error (spec section 5).
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
				// The first run has ended; ignore the rest.
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
	 * Which of `entries` a limit leaves visible (IC-160).
	 *
	 * `entries` is newest first, as Reflog.read returns it. The predicates are
	 * applied in order to each entry: substring search (FR-117), then the time
	 * window (FR-156), then the entry count (FR-157). `window_seconds` of 0 or
	 * less is Any time; `count` of 0 is All; `search` of "" is no search. An
	 * entry with no date always passes the window (FR-159). The returned array
	 * has one flag per entry, in the same order, true for visible.
	 */
	public static bool[] visible(Gee.List<ReflogEntry> entries,
	                             DateTime now,
	                             int64 window_seconds,
	                             uint count,
	                             string search)
	{
		var result = new bool[entries.size];

		// The oldest instant an entry may carry and still fall in the window.
		// Null when there is no window, so the window check is skipped entirely.
		DateTime? cutoff = window_seconds > 0
			? now.add_seconds(-(double)window_seconds)
			: null;

		// How many rows have been made visible so far, for the count cap. The
		// list is newest first, so the first `count` passing rows are the
		// newest `count`.
		uint shown = 0;

		for (var i = 0; i < entries.size; i++)
		{
			var entry = entries[i];
			var pass = true;

			// Search (FR-117): the message or the abbreviated id contains the
			// term. Matched against the entry, exactly as the list did before.
			if (search != "")
			{
				pass = entry.message.down().contains(search)
					|| entry.abbreviated_id.down().contains(search);
			}

			// Time window (FR-156, FR-159): an entry we cannot date always
			// passes, so the newest entry can never be hidden by the clock.
			if (pass && cutoff != null && entry.date != null)
			{
				pass = entry.date.compare(cutoff) >= 0;
			}

			// Entry count (FR-157, FR-158): keep only the newest `count` of the
			// rows that passed search and the window. `count` of 0 is no cap.
			// Only a still-passing row counts toward the cap, so a search or
			// window miss never uses up one of the newest slots.
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
