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
 * The diff of one commit, in two columns.
 *
 * The old side is on the left and the new side on the right, level line by
 * line: where one side of a change has more lines than the other, the shorter
 * side keeps a blank, as the split view of gitg does. The two columns share one
 * vertical scroll position, thus they cannot drift apart, and the divider
 * between them can be dragged.
 *
 * Each side opens with a gutter that holds the number of the line in the file
 * of that side, the old file on the left and the new one on the right, and then
 * the sign of the change: `-` on the left of a removed line, `+` on the right of
 * an added one, and a blank elsewhere. The gutter is a column of its own and not
 * part of the text, so that a selection of the text takes the lines alone and
 * what is copied out of it can be pasted as code. It takes the colour of its
 * line, thus the band of a change still runs from the number to the end.
 *
 * The colours are gitg's own, taken from its diff renderer, and change with the
 * theme as gitg's do. Its added and removed shades hold whole lines. The word
 * marks are a stronger shade of the same hue, and are the one thing here that
 * gitg has no colour for: gitg tints the full line and leaves the reader to
 * find the word that changed.
 */
public class DiffView : Gtk.Paned
{
	private Gtk.TextView d_left;
	private Gtk.TextView d_right;
	private Gtk.TextView d_left_gutter;
	private Gtk.TextView d_right_gutter;
	private Gtk.TextBuffer d_left_buffer;
	private Gtk.TextBuffer d_right_buffer;
	private Gtk.TextBuffer d_left_gutter_buffer;
	private Gtk.TextBuffer d_right_gutter_buffer;
	private Gtk.ScrolledWindow d_left_scroll;
	private Gtk.ScrolledWindow d_right_scroll;

	// The colours of gitg's diff renderer, for a light and for a dark theme.
	private const string ADDED_LIGHT = "#dcffdc";
	private const string REMOVED_LIGHT = "#ffdcdc";
	private const string HEADER_LIGHT = "#f4f7fb";
	private const string ADDED_DARK = "#204415";
	private const string REMOVED_DARK = "#823735";
	private const string HEADER_DARK = "#585858";

	// A stronger shade of each, for the words inside a changed line.
	private const string ADDED_WORD_LIGHT = "#a8f0a8";
	private const string REMOVED_WORD_LIGHT = "#ffb0b0";
	private const string ADDED_WORD_DARK = "#3a7a26";
	private const string REMOVED_WORD_DARK = "#b04e4a";

	construct
	{
		orientation = Gtk.Orientation.HORIZONTAL;

		d_left_buffer = new Gtk.TextBuffer(null);
		d_right_buffer = new Gtk.TextBuffer(null);
		d_left_gutter_buffer = new Gtk.TextBuffer(null);
		d_right_gutter_buffer = new Gtk.TextBuffer(null);

		foreach (var buffer in buffers())
		{
			add_tags(buffer);
		}

		d_left = text_view(d_left_buffer);
		d_right = text_view(d_right_buffer);
		d_left_gutter = gutter_view(d_left_gutter_buffer);
		d_right_gutter = gutter_view(d_right_gutter_buffer);

		// One adjustment for every column, the gutters included. Thus the scroll
		// of any of them moves all, and no code has to keep positions in
		// agreement. The left side shows no vertical scrollbar, because the one
		// on the right drives the set.
		var vadjustment = new Gtk.Adjustment(0, 0, 0, 0, 0, 0);

		d_left_scroll = new Gtk.ScrolledWindow(null, vadjustment);
		d_left_scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.EXTERNAL);
		d_left_scroll.add(d_left);

		d_right_scroll = new Gtk.ScrolledWindow(null, vadjustment);
		d_right_scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
		d_right_scroll.add(d_right);

		pack1(side(gutter_scroll(d_left_gutter, vadjustment), d_left_scroll),
		      true, false);
		pack2(side(gutter_scroll(d_right_gutter, vadjustment), d_right_scroll),
		      true, false);

		// Open with the two columns of equal width, computed from the first
		// real allocation. A literal here would be wrong at any other window
		// width.
		ulong handler = 0;
		handler = size_allocate.connect((alloc) => {
			if (alloc.width <= 1)
				return;

			disconnect(handler);
			position = alloc.width / 2;
		});

		var settings = Gtk.Settings.get_default();

		if (settings != null)
		{
			settings.notify["gtk-application-prefer-dark-theme"].connect(update_theme);
		}

		update_theme();

		show_all();
	}

	/** Shows the diff of the commit at `id`, or the reason it cannot. */
	public void show_commit(Ggit.Repository repository, Ggit.OId id)
	{
		try
		{
			render(CommitDiff.read(repository, id));
		}
		catch (Error e)
		{
			var pairs = new Gee.ArrayList<DiffPair>();
			pairs.add(new DiffPair(
				new DiffRow(DiffRowKind.NOTE,
				            _("Cannot read the diff: %s").printf(e.message)),
				new DiffRow(DiffRowKind.NOTE, "")));

			render(pairs);
		}
	}

	/** Writes one line of one side, and marks it. */
	private void append(Gtk.TextBuffer buffer, DiffRow? row)
	{
		Gtk.TextIter iter;
		buffer.get_end_iter(out iter);

		if (row == null)
		{
			// The side that this line is missing from. It keeps the blank, so
			// the other side stays level with it.
			buffer.insert(ref iter, "\n", -1);
			return;
		}

		var start = iter.get_offset();
		buffer.insert(ref iter, row.text + "\n", -1);

		var tag = tag_of(row.kind);

		if (tag != null)
		{
			// The line tag covers the newline as well as the text. An empty
			// line, which is what the right side of a heading is, has nothing
			// but its newline to carry the colour.
			apply(buffer, tag, start, start + row.text.char_count() + 1);
		}

		foreach (var span in row.spans)
		{
			apply(buffer,
			      row.kind == DiffRowKind.ADDED ? "added-word" : "removed-word",
			      start + char_offset(row.text, span.start),
			      start + char_offset(row.text, span.end));
		}
	}

	/** Writes the gutter of one line: its number, then the sign of its kind. */
	private static void append_gutter(Gtk.TextBuffer buffer, DiffRow? row, int width)
	{
		Gtk.TextIter iter;
		buffer.get_end_iter(out iter);

		if (row == null)
		{
			// The blank that stands where this side has no line belongs to no
			// file, thus it has no number and no sign either.
			buffer.insert(ref iter, "\n", -1);
			return;
		}

		var start = iter.get_offset();
		var text = gutter_of(row, width);

		buffer.insert(ref iter, text + "\n", -1);

		var tag = tag_of(row.kind);

		if (tag != null)
		{
			apply(buffer, tag, start, start + text.char_count() + 1);
		}
	}

	/** Every buffer of the view: the text of the two sides, and the gutters. */
	private Gtk.TextBuffer[] buffers()
	{
		return { d_left_buffer, d_right_buffer,
		         d_left_gutter_buffer, d_right_gutter_buffer };
	}

	private static void apply(Gtk.TextBuffer buffer, string tag,
	                          int start_offset, int end_offset)
	{
		Gtk.TextIter start;
		Gtk.TextIter end;

		buffer.get_iter_at_offset(out start, start_offset);
		buffer.get_iter_at_offset(out end, end_offset);

		buffer.apply_tag_by_name(tag, start, end);
	}

	/**
	 * Creates the tags of a side, with no colour yet.
	 *
	 * update_theme() puts the colours on, and puts them on again whenever the
	 * theme changes.
	 */
	private static void add_tags(Gtk.TextBuffer buffer)
	{
		buffer.create_tag("file", "weight", (int)Pango.Weight.BOLD);
		buffer.create_tag("hunk");
		buffer.create_tag("added");
		buffer.create_tag("removed");
		buffer.create_tag("added-word");
		buffer.create_tag("removed-word");
		buffer.create_tag("note", "style", (int)Pango.Style.ITALIC);
	}

	/**
	 * The character offset of a byte offset into `text`.
	 *
	 * The spans of WordDiff are byte offsets, because they index a string. A
	 * text buffer counts characters. The two agree until a line holds anything
	 * outside ASCII, and then a byte offset would put the mark in the wrong
	 * place.
	 */
	private static int char_offset(string text, int bytes)
	{
		return text.substring(0, bytes).char_count();
	}

	/**
	 * The gutter of a row: its line number, then the sign of its kind.
	 *
	 * `width` is the room the widest number of the diff needs, thus the numbers
	 * stand in one column and the text of every row starts at the same place.
	 */
	private static string gutter_of(DiffRow row, int width)
	{
		var number = row.lineno != DiffRow.NO_LINE
			? "%d".printf(row.lineno)
			: "";

		// The space on either side is part of the text rather than a margin,
		// because the colour of a line covers its text and not its margins.
		return " %s%s %s ".printf(string.nfill(width - number.length, ' '),
		                          number, sign_of(row.kind));
	}

	/**
	 * Puts a gutter in a scroller that follows the text beside it.
	 *
	 * The gutter takes the width its widest line needs and no more, thus the
	 * text keeps the rest of the side. It carries no scrollbar of its own: the
	 * shared adjustment moves it, and it is too narrow to scroll sideways.
	 */
	private static Gtk.ScrolledWindow gutter_scroll(Gtk.TextView gutter,
	                                                Gtk.Adjustment vadjustment)
	{
		var scroll = new Gtk.ScrolledWindow(null, vadjustment);

		scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.EXTERNAL);
		scroll.add(gutter);

		return scroll;
	}

	/**
	 * The column that holds the numbers and the signs of one side.
	 *
	 * It takes no click, thus nothing in it can be selected and a selection of
	 * the text beside it stays a selection of code.
	 */
	private static Gtk.TextView gutter_view(Gtk.TextBuffer buffer)
	{
		var view = text_view(buffer);

		view.can_focus = false;
		view.right_margin = 0;
		view.button_press_event.connect(() => true);

		return view;
	}

	/**
	 * The room that the line numbers of a diff need, in characters.
	 *
	 * One width serves both sides, so that the two columns read alike and the
	 * two halves of a pair start at the same place.
	 */
	private static int number_width(Gee.List<DiffPair> pairs)
	{
		var most = 0;

		foreach (var pair in pairs)
		{
			if (pair.left != null)
			{
				most = int.max(most, pair.left.lineno);
			}

			if (pair.right != null)
			{
				most = int.max(most, pair.right.lineno);
			}
		}

		return "%d".printf(most).length;
	}

	private void render(Gee.List<DiffPair> pairs)
	{
		foreach (var buffer in buffers())
		{
			buffer.set_text("", 0);
		}

		var width = number_width(pairs);

		foreach (var pair in pairs)
		{
			append(d_left_buffer, pair.left);
			append(d_right_buffer, pair.right);

			append_gutter(d_left_gutter_buffer, pair.left, width);
			append_gutter(d_right_gutter_buffer, pair.right, width);
		}

		scroll_to_start();
	}

	private void scroll_to_start()
	{
		Gtk.TextIter start;
		d_left_buffer.get_start_iter(out start);

		d_left.scroll_to_iter(start, 0.0, true, 0.0, 0.0);

		d_left_scroll.get_hadjustment().value = 0;
		d_right_scroll.get_hadjustment().value = 0;
	}

	/** Puts a background colour on a tag of every column. */
	private void set_background(string tag, string colour, bool paragraph)
	{
		foreach (var buffer in buffers())
		{
			var it = buffer.tag_table.lookup(tag);

			if (paragraph)
			{
				it.paragraph_background = colour;
			}
			else
			{
				it.background = colour;
			}
		}
	}

	/** Puts a foreground colour on a tag of every column. */
	private void set_foreground(string tag, string colour)
	{
		foreach (var buffer in buffers())
		{
			buffer.tag_table.lookup(tag).foreground = colour;
		}
	}

	/** A side of the view: its gutter, and its text beside it. */
	private static Gtk.Box side(Gtk.Widget gutter, Gtk.Widget text)
	{
		var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);

		box.pack_start(gutter, false, false, 0);
		box.pack_start(text, true, true, 0);

		return box;
	}

	/** The sign that a row of this kind carries in its gutter. */
	private static string sign_of(DiffRowKind kind)
	{
		switch (kind)
		{
			case DiffRowKind.ADDED: return "+";
			case DiffRowKind.REMOVED: return "-";
			default: return " ";
		}
	}

	/** The tag that draws a row of this kind, or null for the plain text. */
	private static string? tag_of(DiffRowKind kind)
	{
		switch (kind)
		{
			case DiffRowKind.ADDED: return "added";
			case DiffRowKind.REMOVED: return "removed";
			case DiffRowKind.FILE: return "file";
			case DiffRowKind.HUNK: return "hunk";
			case DiffRowKind.NOTE: return "note";
			default: return null;
		}
	}

	private static Gtk.TextView text_view(Gtk.TextBuffer buffer)
	{
		var view = new Gtk.TextView.with_buffer(buffer);

		view.editable = false;
		view.cursor_visible = false;
		view.monospace = true;

		// A diff is a set of lines, and a wrapped line stops the two columns
		// from staying level. gitg does not wrap in its split view either.
		view.wrap_mode = Gtk.WrapMode.NONE;

		// No margin on the left: the gutter stands there, and a margin between
		// the two would break the band of colour that crosses them.
		view.left_margin = 0;
		view.right_margin = 6;

		return view;
	}

	/**
	 * Takes the colours for the theme in force.
	 *
	 * gitg reads the theme the same way and holds two sets of colours, one for
	 * a light theme and one for a dark one. Thus this follows it rather than
	 * one translucent set over both.
	 */
	private void update_theme()
	{
		var dark = Gitg.Theme.instance().is_theme_dark();

		set_background("added", dark ? ADDED_DARK : ADDED_LIGHT, true);
		set_background("removed", dark ? REMOVED_DARK : REMOVED_LIGHT, true);
		set_background("file", dark ? HEADER_DARK : HEADER_LIGHT, true);
		set_background("hunk", dark ? HEADER_DARK : HEADER_LIGHT, true);

		set_background("added-word",
		               dark ? ADDED_WORD_DARK : ADDED_WORD_LIGHT, false);
		set_background("removed-word",
		               dark ? REMOVED_WORD_DARK : REMOVED_WORD_LIGHT, false);

		set_foreground("hunk", dark ? "#c0c0c0" : "#4c4c4c");
		set_foreground("note", dark ? "#c0c0c0" : "#4c4c4c");
	}
}

}

// ex:set ts=4 noet:
