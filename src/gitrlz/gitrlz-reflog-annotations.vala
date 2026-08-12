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

public enum OperationPosition
{
	SINGLE,
	START,
	MIDDLE,
	END
}

public struct Operation
{
	public string kind;
	public OperationPosition position;
}

public class ReflogAnnotations : Object
{
	private static string message_head(string message)
	{
		var colon = message.index_of(":");

		return colon < 0 ? message : message.substring(0, colon);
	}

	public static string operation_kind(string message)
	{
		var head = message_head(message).strip();
		var space = head.index_of(" ");

		if (space >= 0)
		{
			head = head.substring(0, space);
		}

		head = head.strip().down();

		return head == "" ? "unknown" : head;
	}

	private static bool is_hash(string text)
	{
		if (text.length < 7 || text.length > 40)
		{
			return false;
		}

		for (var i = 0; i < text.length; i++)
		{
			if (!text[i].isxdigit() || text[i].isupper())
			{
				return false;
			}
		}

		return true;
	}

	private static bool checkout_move(string message, out string from, out string to)
	{
		from = "";
		to = "";

		var colon = message.index_of(":");

		if (colon < 0)
		{
			return false;
		}

		if (message.substring(0, colon).strip().down() != "checkout")
		{
			return false;
		}

		var rest = message.substring(colon + 1);
		const string MARKER = "moving from ";

		var at = rest.index_of(MARKER);

		if (at < 0)
		{
			return false;
		}

		var body = rest.substring(at + MARKER.length);
		var sep = body.last_index_of(" to ");

		if (sep < 0)
		{
			return false;
		}

		from = body.substring(0, sep).strip();
		to = body.substring(sep + 4).strip();

		return true;
	}

	private static string? rebase_return(string message)
	{
		const string MARKER = "returning to refs/heads/";

		var at = message.index_of(MARKER);

		if (at < 0)
		{
			return null;
		}

		return message.substring(at + MARKER.length).strip();
	}

	public static Operation[] classify_operations(Gee.List<ReflogEntry> entries)
	{
		var count = entries.size;
		var result = new Operation[count];

		for (var i = 0; i < count; i++)
		{
			result[i] = Operation() {
				kind = operation_kind(entries[i].message),
				position = OperationPosition.SINGLE
			};
		}

		var cursor = count - 1;

		while (cursor >= 0)
		{
			if (result[cursor].kind == "rebase" &&
			    "(start)" in message_head(entries[cursor].message))
			{
				var run = new Gee.ArrayList<int>();
				run.add(cursor);

				var step = cursor - 1;

				while (step >= 0 && result[step].kind == "rebase")
				{
					run.add(step);

					var head = message_head(entries[step].message);
					step--;

					if ("(finish)" in head || "(abort)" in head)
					{
						break;
					}
				}

				if (run.size > 1)
				{
					result[run[0]].position = OperationPosition.START;
					result[run[run.size - 1]].position = OperationPosition.END;

					for (var i = 1; i < run.size - 1; i++)
					{
						result[run[i]].position = OperationPosition.MIDDLE;
					}
				}

				cursor = step;
				continue;
			}

			cursor--;
		}

		return result;
	}

	public static string?[] attribute_branches(Gee.List<ReflogEntry> entries,
	                                           string? default_branch = null)
	{
		var count = entries.size;
		var result = new string?[count];

		if (count == 0)
		{
			return result;
		}

		string? current = default_branch;

		for (var i = count - 1; i >= 0; i--)
		{
			string from;
			string to;

			if (checkout_move(entries[i].message, out from, out to))
			{
				current = is_hash(from) ? null : from;
				break;
			}
		}

		for (var i = count - 1; i >= 0; i--)
		{
			var message = entries[i].message;

			string from;
			string to;

			if (checkout_move(message, out from, out to))
			{
				current = is_hash(to) ? null : to;
			}

			var returned = rebase_return(message);

			if (returned != null)
			{
				current = returned;
			}

			result[i] = current;
		}

		var operations = classify_operations(entries);
		var run = new Gee.ArrayList<int>();

		for (var i = count - 1; i >= 0; i--)
		{
			var position = operations[i].position;

			if (position == OperationPosition.START)
			{
				run.clear();
				run.add(i);
			}
			else if ((position == OperationPosition.MIDDLE ||
			          position == OperationPosition.END) && run.size > 0)
			{
				run.add(i);

				if (position == OperationPosition.END)
				{
					var branch = rebase_return(entries[i].message);

					if (branch != null)
					{
						foreach (var member in run)
						{
							result[member] = branch;
						}
					}

					run.clear();
				}
			}
		}

		return result;
	}
}

}
