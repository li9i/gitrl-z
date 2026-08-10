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
	private Gtk.TextBuffer d_left_buffer;
	private Gtk.TextBuffer d_right_buffer;
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

		add_tags(d_left_buffer);
		add_tags(d_right_buffer);

		d_left = text_view(d_left_buffer);
		d_right = text_view(d_right_buffer);

		// One adjustment for the two columns. Thus the scroll of either moves
		// both, and no code has to keep two positions in agreement. The left
		// column shows no vertical scrollbar, because the one on the right
		// drives the pair.
		var vadjustment = new Gtk.Adjustment(0, 0, 0, 0, 0, 0);

		d_left_scroll = new Gtk.ScrolledWindow(null, vadjustment);
		d_left_scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.EXTERNAL);
		d_left_scroll.add(d_left);

		d_right_scroll = new Gtk.ScrolledWindow(null, vadjustment);
		d_right_scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
		d_right_scroll.add(d_right);

		pack1(d_left_scroll, true, false);
		pack2(d_right_scroll, true, false);

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

	private void render(Gee.List<DiffPair> pairs)
	{
		d_left_buffer.set_text("", 0);
		d_right_buffer.set_text("", 0);

		foreach (var pair in pairs)
		{
			append(d_left_buffer, pair.left);
			append(d_right_buffer, pair.right);
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

	/** Puts a background colour on a tag of both sides. */
	private void set_background(string tag, string colour, bool paragraph)
	{
		foreach (var buffer in new Gtk.TextBuffer[] { d_left_buffer, d_right_buffer })
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

	/** Puts a foreground colour on a tag of both sides. */
	private void set_foreground(string tag, string colour)
	{
		foreach (var buffer in new Gtk.TextBuffer[] { d_left_buffer, d_right_buffer })
		{
			buffer.tag_table.lookup(tag).foreground = colour;
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
		view.left_margin = 6;
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
