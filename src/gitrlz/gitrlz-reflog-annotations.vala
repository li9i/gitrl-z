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
 * The position of a row in a multi-step operation (spec P-FR-15).
 *
 * Each row is SINGLE, except the rows in a rebase, which git records as an
 * explicit run. In a run, the oldest row is START, the newest row is END, and
 * the rows between them are MIDDLE. A run of one row stays SINGLE, because a
 * bracket needs a minimum of two rows.
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
 * All code here is pure. It reads the message strings that git writes, which
 * IC-8 describes. It calls neither Ggit nor GTK. Thus the annotations of the
 * reflog list are easy to test.
 *
 * This code comes from gitrlz/reflog.py of the Python implementation. That
 * file and tests/test_annotations.py are the specification of this behaviour.
 * The move to libgit2 does not change the message forms.
 * Ggit.ReflogEntry.get_message() returns the same text as %gs.
 */
public class ReflogAnnotations : Object
{
	/**
	 * Returns the part of a reflog message before the first colon.
	 */
	private static string message_head(string message)
	{
		var colon = message.index_of(":");

		return colon < 0 ? message : message.substring(0, colon);
	}

	/**
	 * The operation kind of a reflog message (IC-8).
	 *
	 * The result is the first word before the first colon, in lower case. Thus
	 * `rebase (pick)` and `rebase -i (start)` both give `rebase`, and `merge
	 * topic` gives `merge`.
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
	 * True if the text has the form of an abbreviated hash or a full hash.
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
	 * Gives (from, to) for a checkout reflog message, or false (IC-8).
	 *
	 * A ref name cannot contain a space. Thus the last " to " in the body
	 * divides the two names.
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
	 * The branch that a rebase finish or abort returns to, or null.
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
	 * Classifies each entry as (kind, position) (IC-8, P-FR-15).
	 *
	 * `entries` is newest first, as git prints a reflog.
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

		// Walk from the oldest to the newest, which is the order of a run.
		// A rebase starts at its oldest row.
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
	 * The branch of HEAD for each entry, or null (IC-8, P-FR-16).
	 *
	 * `entries` is newest first. In a walk from the oldest to the newest, a
	 * checkout moves HEAD to its target, and a rebase finish returns HEAD to
	 * the named branch. If the target is a bare hash, HEAD is detached and the
	 * result is null. Entries before the first checkout take the from branch
	 * of that checkout. If the reflog has no checkout, they take
	 * `default_branch`.
	 *
	 * A rebase replays with a detached HEAD. Thus each entry of a rebase run
	 * gets the branch that the run returns to.
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

		// Start from the "from" branch of the oldest checkout. Entries older
		// than the first checkout belong to the branch that HEAD was on
		// before that checkout.
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

		// A rebase replays with a detached HEAD. Thus its rows would get no
		// branch. Give the full run the branch that it returns to.
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
