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
 * Where a row sits within a multi-step operation (spec P-FR-15).
 *
 * Everything is SINGLE except inside a rebase, which git records as an
 * explicit run: the oldest row is START, the newest END, any rows between
 * are MIDDLE. A run of one row stays SINGLE, because a bracket needs at
 * least two rows to bracket.
 */
public enum OperationPosition
{
	SINGLE,
	START,
	MIDDLE,
	END
}

public struct Operation
{
	/** First word before the first colon, lowercased: "commit", "rebase". */
	public string kind;
	public OperationPosition position;
}

/**
 * Analysis of reflog messages: which operation, and which branch.
 *
 * Everything here is pure. It reads the message strings git writes,
 * described by IC-8, and calls neither Ggit nor GTK, which is what makes the
 * reflog list's annotations straightforward to test.
 *
 * Ported from the Python implementation's gitrlz/reflog.py, which — together
 * with tests/test_annotations.py — is the specification of this behaviour.
 * The message forms are unchanged by the move to libgit2:
 * Ggit.ReflogEntry.get_message() returns exactly what %gs produced.
 */
public class ReflogAnnotations : Object
{
	/**
	 * Return the part of a reflog message before the first colon.
	 */
	private static string message_head(string message)
	{
		var colon = message.index_of(":");

		return colon < 0 ? message : message.substring(0, colon);
	}

	/**
	 * The operation kind of a reflog message (IC-8).
	 *
	 * The first word before the first colon, lowercased, so `rebase (pick)`
	 * and `rebase -i (start)` both give `rebase`, and `merge topic` gives
	 * `merge`.
	 */
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

	/**
	 * True when text looks like an abbreviated or full hash.
	 */
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

	/**
	 * (from, to) for a checkout reflog message, else false (IC-8).
	 *
	 * A ref name cannot contain a space, so the last " to " in the body
	 * separates the two names.
	 */
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

	/**
	 * The branch a rebase finish or abort returns to, else null.
	 */
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

	/**
	 * Classify every entry as (kind, position) (IC-8, P-FR-15).
	 *
	 * `entries` arrives newest first, as git prints a reflog.
	 */
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

		// Walk oldest to newest, which is how a run reads: a rebase starts
		// at the oldest of its rows.
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

	/**
	 * The branch HEAD was on for each entry, or null (IC-8, P-FR-16).
	 *
	 * `entries` arrives newest first. Walking oldest to newest, a checkout
	 * moves HEAD to its target and a rebase finish returns it to the named
	 * branch. A target that is a bare hash means a detached HEAD and gives
	 * null. Entries before the first checkout take that checkout's from
	 * branch, or `default_branch` when the reflog holds no checkout at all.
	 *
	 * A rebase replays with HEAD detached, so every entry of a rebase run is
	 * attributed to the branch the run returns to.
	 */
	public static string?[] attribute_branches(Gee.List<ReflogEntry> entries,
	                                           string? default_branch = null)
	{
		var count = entries.size;
		var result = new string?[count];

		if (count == 0)
		{
			return result;
		}

		// Seed from the oldest checkout's "from" branch: entries older than
		// the first checkout belong to whatever HEAD was on before it.
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

		// A rebase replays detached, so its rows would otherwise be
		// attributed to nothing. Give the whole run the branch it returns to.
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

// ex:set ts=4 noet:
