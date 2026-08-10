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
 * What one row of a rendered diff is.
 */
public enum DiffRowKind
{
	/** A file heading, which names the path and what happened to it. */
	FILE,
	/** A hunk heading, in the `@@ -a,b +c,d @@` form of git. */
	HUNK,
	/** A line that both sides have. */
	CONTEXT,
	/** A line that only the new side has. */
	ADDED,
	/** A line that only the old side has. */
	REMOVED,
	/** A statement about the diff rather than a part of it. */
	NOTE
}

/**
 * One row of a rendered diff.
 *
 * `text` carries no leading `+` or `-`: the sign belongs in the gutter that the
 * view draws, and a sign in the text as well would read as `--drop`. `spans`
 * are the parts of `text` that differ from the line this one replaced, and are
 * empty for every kind but ADDED and REMOVED.
 *
 * `lineno` is the number of this line in the file of its own side: the old file
 * on the left, the new file on the right. A heading and the blank that stands
 * where a side has no line have NO_LINE, because neither is a line of a file.
 */
public class DiffRow : Object
{
	/** The line number of a row that is not a line of either file. */
	public const int NO_LINE = 0;

	public DiffRowKind kind;
	public string text;
	public int lineno;
	public WordSpan[] spans;

	public DiffRow(DiffRowKind kind, string text, int lineno = NO_LINE)
	{
		this.kind = kind;
		this.text = text;
		this.lineno = lineno;
		this.spans = {};
	}
}

/**
 * One line of a split diff: what the old side shows, and what the new side
 * shows beside it.
 *
 * A side is null where that side has no line at all, which is how a block of
 * three removed lines sits beside a block of one added line. The view leaves
 * the blank there, so the two sides stay level all the way down.
 *
 * A heading has its text on the left and an empty row of the same kind on the
 * right, thus its band of colour crosses both sides.
 */
public class DiffPair : Object
{
	public DiffRow? left;
	public DiffRow? right;

	public DiffPair(DiffRow? left, DiffRow? right)
	{
		this.left = left;
		this.right = right;
	}
}

/**
 * The diff of one commit, as the lines of a split view.
 *
 * The diff is against the first parent, which is what `git show` does, and
 * against the empty tree for a root commit. Rename detection is on, again as
 * git has it by default.
 *
 * The class holds no GTK code, so the lines can be tested with no display.
 */
public class CommitDiff : Object
{
	private Gee.List<DiffPair> d_pairs;

	/**
	 * The removed and added lines of the current run, held back so that each
	 * pair can take its word marks and so that the two sides can be levelled.
	 *
	 * A run is the removed lines of a change and the added lines that follow
	 * them, before the next context line or hunk. The lines go into d_pairs
	 * when the run ends.
	 */
	private Gee.List<DiffRow> d_removed;
	private Gee.List<DiffRow> d_added;

	/** The context that git shows around a change, in lines. */
	private const int CONTEXT_LINES = 3;

	construct
	{
		d_pairs = new Gee.ArrayList<DiffPair>();
		d_removed = new Gee.ArrayList<DiffRow>();
		d_added = new Gee.ArrayList<DiffRow>();
	}

	/**
	 * The lines of the diff of the commit at `id`, as pairs of sides.
	 */
	public static Gee.List<DiffPair> read(Ggit.Repository repository,
	                                      Ggit.OId id) throws Error
	{
		var builder = new CommitDiff();
		builder.build(repository, id);

		return builder.d_pairs;
	}

	/** Adds a line that crosses both sides, such as a heading. */
	private void add_band(DiffRowKind kind, string text)
	{
		d_pairs.add(new DiffPair(new DiffRow(kind, text), new DiffRow(kind, "")));
	}

	/**
	 * Adds a line that the two sides share.
	 *
	 * The line stands at one number in the old file and at another in the new
	 * one, thus each side keeps its own.
	 */
	private void add_context(string text, int old_lineno, int new_lineno)
	{
		d_pairs.add(new DiffPair(new DiffRow(DiffRowKind.CONTEXT, text, old_lineno),
		                         new DiffRow(DiffRowKind.CONTEXT, text, new_lineno)));
	}

	private void build(Ggit.Repository repository, Ggit.OId id) throws Error
	{
		var commit = repository.lookup_commit(id);

		if (commit == null)
		{
			throw new Ggit.Error.NOTFOUND(_("Commit %s is not in the repository"),
			                              id.to_string());
		}

		var parents = commit.get_parents();

		Ggit.Tree? old_tree = null;

		if (parents.get_size() > 0)
		{
			var parent = parents.get(0);
			old_tree = parent != null ? parent.get_tree() : null;
		}

		if (parents.get_size() > 1)
		{
			// A merge has more than one side, and a diff has two. git shows a
			// merge against its first parent, thus so does this, and the note
			// says so rather than leaving the reader to wonder which side they
			// are reading.
			add_band(DiffRowKind.NOTE, _("Merge commit, shown against its first parent"));
		}

		var options = new Ggit.DiffOptions();
		options.n_context_lines = CONTEXT_LINES;

		var diff = new Ggit.Diff.tree_to_tree(repository, old_tree,
		                                      commit.get_tree(), options);

		// A rename is one change and not a delete beside an add. git looks for
		// them by default, and a reader of this diff expects the same.
		diff.find_similar(null);

		diff.foreach(on_file, on_binary, on_hunk, on_line);

		flush();

		if (d_pairs.size == 0)
		{
			add_band(DiffRowKind.NOTE, _("This commit changes no file"));
		}
	}

	/**
	 * Ends the current run of removed and added lines.
	 *
	 * The removed line at each position of the run sits beside the added line
	 * at the same position, and the pair takes its word marks. Where one side
	 * of the run is longer, the other side gets a blank, thus the two sides
	 * stay level and a later line is not read against the wrong one.
	 */
	private void flush()
	{
		var lines = int.max(d_removed.size, d_added.size);

		for (var i = 0; i < lines; i++)
		{
			var removed = i < d_removed.size ? d_removed[i] : null;
			var added = i < d_added.size ? d_added[i] : null;

			if (removed != null && added != null)
			{
				WordSpan[] removed_spans;
				WordSpan[] added_spans;

				if (WordDiff.refine(removed.text, added.text,
				                    out removed_spans, out added_spans))
				{
					removed.spans = removed_spans;
					added.spans = added_spans;
				}
			}

			d_pairs.add(new DiffPair(removed, added));
		}

		d_removed.clear();
		d_added.clear();
	}

	private int on_binary(Ggit.DiffDelta delta, Ggit.DiffBinary binary)
	{
		add_band(DiffRowKind.NOTE, _("Binary file"));

		return 0;
	}

	private int on_file(Ggit.DiffDelta delta, float progress)
	{
		flush();

		add_band(DiffRowKind.FILE, title_of(delta));

		return 0;
	}

	private int on_hunk(Ggit.DiffDelta delta, Ggit.DiffHunk hunk)
	{
		flush();

		add_band(DiffRowKind.HUNK, trimmed(hunk.get_header()));

		return 0;
	}

	private int on_line(Ggit.DiffDelta delta, Ggit.DiffHunk? hunk, Ggit.DiffLine line)
	{
		var text = trimmed(line.get_text());

		switch (line.get_origin())
		{
			case Ggit.DiffLineType.ADDITION:
				d_added.add(new DiffRow(DiffRowKind.ADDED, text,
				                        line.get_new_lineno()));
				break;

			case Ggit.DiffLineType.DELETION:
				d_removed.add(new DiffRow(DiffRowKind.REMOVED, text,
				                          line.get_old_lineno()));
				break;

			case Ggit.DiffLineType.CONTEXT:
				flush();
				add_context(text, line.get_old_lineno(), line.get_new_lineno());
				break;

			case Ggit.DiffLineType.CONTEXT_EOFNL:
			case Ggit.DiffLineType.ADD_EOFNL:
			case Ggit.DiffLineType.DEL_EOFNL:
				flush();
				add_band(DiffRowKind.NOTE, _("\\ No newline at end of file"));
				break;

			default:
				break;
		}

		return 0;
	}

	/** The heading of a file, which names it and says what happened to it. */
	private static string title_of(Ggit.DiffDelta delta)
	{
		var old_file = delta.get_old_file();
		var new_file = delta.get_new_file();

		var old_path = old_file != null ? old_file.get_path() : null;
		var new_path = new_file != null ? new_file.get_path() : null;

		var path = new_path != null ? new_path : old_path;

		if (path == null)
		{
			path = _("unknown path");
		}

		switch (delta.get_status())
		{
			case Ggit.DeltaType.ADDED:
				return _("%s (new file)").printf(path);

			case Ggit.DeltaType.DELETED:
				return _("%s (deleted)").printf(old_path != null ? old_path : path);

			case Ggit.DeltaType.RENAMED:
				return "%s -> %s".printf(old_path != null ? old_path : path, path);

			case Ggit.DeltaType.COPIED:
				return _("%s -> %s (copied)").printf(old_path != null ? old_path : path,
				                                     path);

			case Ggit.DeltaType.TYPECHANGE:
				return _("%s (type changed)").printf(path);

			default:
				return path;
		}
	}

	/** A line of libgit2 with its line ending removed. */
	private static string trimmed(string? text)
	{
		if (text == null)
		{
			return "";
		}

		var line = text;

		if (line.has_suffix("\n"))
		{
			line = line.substring(0, line.length - 1);
		}

		if (line.has_suffix("\r"))
		{
			line = line.substring(0, line.length - 1);
		}

		return line;
	}
}

}

// ex:set ts=4 noet:
