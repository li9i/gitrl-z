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

public class TimelineState : Object
{
	public DateTime when { get; construct set; }

	public Gee.Map<string, Ggit.OId> positions { get; construct set; }

	public TimelineState(DateTime when, Gee.Map<string, Ggit.OId> positions)
	{
		Object(when: when, positions: positions);
	}

	public bool holds(string branch)
	{
		return positions.has_key(branch);
	}

	public Ggit.OId? position_of(string branch)
	{
		return positions.has_key(branch) ? positions[branch] : null;
	}
}

public class Timeline : Object
{
	public static ResetPlan plan_for(TimelineState state,
	                                 Gee.Map<string, Ggit.OId> tips)
	{
		var plan = new ResetPlan();

		foreach (var entry in tips.entries)
		{
			var at = state.position_of(entry.key);

			if (at == null)
			{
				plan.set_deleted(entry.key);
			}
			else if (!at.equal(entry.value))
			{
				plan.set_target(entry.key, at);
			}
		}

		return plan;
	}

	public static Gee.List<TimelineState> read(Gitg.Repository repository,
	                                           Gee.List<string> branches)
	{
		var states = new Gee.ArrayList<TimelineState>();
		var history = new Gee.HashMap<string, Gee.List<ReflogEntry>>();

		var moments = new Gee.TreeSet<int64?>((a, b) => {
			if (a == b)
			{
				return 0;
			}

			return a < b ? -1 : 1;
		});

		foreach (var branch in branches)
		{
			var ascending = new Gee.ArrayList<ReflogEntry>();
			var entries = Reflog.read(repository, branch);

			for (var i = entries.size - 1; i >= 0; i--)
			{
				var entry = entries[i];

				if (entry.date == null || entry.new_id == null)
				{
					continue;
				}

				ascending.add(entry);
				moments.add(entry.date.to_unix());
			}

			history[branch] = ascending;
		}

		var cursor = new Gee.HashMap<string, int>();
		var reached = new Gee.HashMap<string, Ggit.OId>();

		foreach (var moment in moments)
		{
			int64 at = moment;
			var positions = new Gee.HashMap<string, Ggit.OId>();

			foreach (var branch in branches)
			{
				var entries = history[branch];
				var index = cursor.has_key(branch) ? cursor[branch] : 0;

				while (index < entries.size && entries[index].date.to_unix() <= at)
				{
					reached[branch] = entries[index].new_id;
					index++;
				}

				cursor[branch] = index;

				if (reached.has_key(branch))
				{
					positions[branch] = reached[branch];
				}
			}

			states.add(new TimelineState(new DateTime.from_unix_local(at), positions));
		}

		return states;
	}
}

public class TimelineAxis : Object
{
	private const int64 SPREAD = 6;

	private double[] d_marks;

	public TimelineAxis(Gee.List<TimelineState> states)
	{
		d_marks = spread(states);
	}

	public double upper
	{
		get { return d_marks.length > 0 ? d_marks[d_marks.length - 1] : 0.0; }
	}

	public double mark(int index)
	{
		if (d_marks.length == 0)
		{
			return 0.0;
		}

		if (index < 0)
		{
			return d_marks[0];
		}

		return index < d_marks.length ? d_marks[index] : d_marks[d_marks.length - 1];
	}

	public int nearest(double value)
	{
		var nearest = -1;
		var closest = 0.0;

		for (var i = 0; i < d_marks.length; i++)
		{
			var distance = Math.fabs(d_marks[i] - value);

			if (nearest < 0 || distance < closest)
			{
				nearest = i;
				closest = distance;
			}
		}

		return nearest;
	}

	private static double[] spread(Gee.List<TimelineState> states)
	{
		double[] marks = {};

		if (states.size == 0)
		{
			return marks;
		}

		marks += 0.0;

		if (states.size == 1)
		{
			return marks;
		}

		var typical = typical_gap(states);
		var widest = typical * SPREAD;
		var narrowest = int64.max(1, typical / SPREAD);

		var at = 0.0;

		for (var i = 1; i < states.size; i++)
		{
			var gap = states[i].when.to_unix() - states[i - 1].when.to_unix();

			at += (double)int64.min(widest, int64.max(narrowest, gap));
			marks += at;
		}

		return marks;
	}

	private static int64 typical_gap(Gee.List<TimelineState> states)
	{
		var gaps = new Gee.ArrayList<int64?>();

		for (var i = 1; i < states.size; i++)
		{
			gaps.add(states[i].when.to_unix() - states[i - 1].when.to_unix());
		}

		gaps.sort((a, b) => {
			if (a == b)
			{
				return 0;
			}

			return a < b ? -1 : 1;
		});

		return gaps[(gaps.size - 1) / 2];
	}
}

}
