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

public class ReflogFilter : Object
{
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

	public static bool[] visible(Gee.List<ReflogEntry> entries,
	                             DateTime now,
	                             int64 window_seconds,
	                             uint count,
	                             string search)
	{
		var result = new bool[entries.size];

		DateTime? cutoff = window_seconds > 0
			? now.add_seconds(-(double)window_seconds)
			: null;

		uint shown = 0;

		for (var i = 0; i < entries.size; i++)
		{
			var entry = entries[i];
			var pass = true;

			if (search != "")
			{
				pass = entry.message.down().contains(search)
					|| entry.abbreviated_id.down().contains(search);
			}

			if (pass && cutoff != null && entry.date != null)
			{
				pass = entry.date.compare(cutoff) >= 0;
			}

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
