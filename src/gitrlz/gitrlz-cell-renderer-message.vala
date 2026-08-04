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
 * The Message cell of the reflog list, with the session mark (spec FR-170,
 * FR-171, IC-171).
 *
 * The message of a reflog entry, and on one row of the list a pill before it
 * that says this entry was the newest of this log when gitrl-z opened the
 * repository. The pill takes the width it needs on that row alone, and the
 * message of every other row starts at the edge of the column.
 *
 * The pill is drawn here, and not by a second cell renderer packed into the
 * same column, although that was the first attempt. A cell area gives each of
 * its cells one width for the whole column, measured once. In the fixed height
 * mode that FR-147 needs, that measurement happens before the list has rows,
 * thus a cell whose width comes from the row data is measured empty and keeps
 * a width of zero for ever. The pill then never appeared. Widening it for
 * every row instead would indent every message by the width of a mark that one
 * row carries. Drawing both in one renderer takes the per row decision away
 * from GTK, and it is the only method here that gives it.
 *
 * The appearance is deliberately not the appearance of a ref. Every ref pill in
 * the application is filled with a palette colour, in the list and in the
 * graph, and its text is light. This one has no fill at all: an edge and its
 * words, in the text colour, with the row showing through. Thus it cannot be
 * read as a branch, a remote, a tag or a stash, and it sits in its row rather
 * than on top of it.
 *
 * A fill was the first attempt, white under a light theme and near black under
 * a dark one, chosen as the opposite of the text. It failed on the rows that
 * matter. A tinted row (FR-151) showed the mark as a hole punched through the
 * tint, and no fixed value can follow a row whose colour comes from the plan,
 * from the theme or from the selection. An unfilled pill follows all three
 * without being told.
 *
 * The geometry is the geometry of the branch chip, so that the two look like
 * members of one family rather than two accidents. The corner is the one
 * departure: 6 px, which is the radius that the stylesheet gives the pills of
 * the graph, against the 4 px that a measurement of gitg gave the chip.
 *
 * The constants are declared again here and not shared with
 * CellRendererBranch. A shared constant would tie the appearance of the branch
 * chip to the appearance of a mark that is deliberately not a branch.
 */
public class CellRendererMessage : Gtk.CellRendererText
{
	private const double RADIUS = 6.0;
	private const double FONT_SCALE = 0.83;
	private const int PADDING_X = 6;
	private const int MARGIN_Y = 2;
	private const double BORDER_WIDTH = 1.0;

	/** The space between the pill and the message that follows it. */
	private const int GAP = 6;

	/** The words in the pill. The empty string draws no pill. */
	public string mark { get; set; default = ""; }

	private Pango.Layout create_layout(Gtk.Widget widget)
	{
		var layout = widget.create_pango_layout(mark);

		var font = layout.get_font_description();

		if (font == null)
		{
			// The body font, taken from the Pango context of the widget. The
			// style context holds the same font, but its getter for it is
			// deprecated in GTK 3 and warns at build time.
			font = layout.get_context().get_font_description().copy();
		}
		else
		{
			font = font.copy();
		}

		font.set_size((int)(font.get_size() * FONT_SCALE));
		font.set_weight(Pango.Weight.NORMAL);
		layout.set_font_description(font);

		return layout;
	}

	private static void rounded_rectangle(Cairo.Context cr,
	                                      double x, double y,
	                                      double width, double height,
	                                      double radius)
	{
		cr.new_sub_path();
		cr.arc(x + width - radius, y + radius, radius, -Math.PI / 2, 0);
		cr.arc(x + width - radius, y + height - radius, radius, 0, Math.PI / 2);
		cr.arc(x + radius, y + height - radius, radius, Math.PI / 2, Math.PI);
		cr.arc(x + radius, y + radius, radius, Math.PI, 3 * Math.PI / 2);
		cr.close_path();
	}

	public override void render(Cairo.Context cr,
	                            Gtk.Widget widget,
	                            Gdk.Rectangle background_area,
	                            Gdk.Rectangle cell_area,
	                            Gtk.CellRendererState flags)
	{
		// Only the row that the session started at carries a mark. Every other
		// row is the message alone, at the edge of its column.
		if (mark == null || mark == "")
		{
			base.render(cr, widget, background_area, cell_area, flags);
			return;
		}

		var layout = create_layout(widget);

		int w;
		int h;
		layout.get_pixel_size(out w, out h);

		var pill_width = w + PADDING_X * 2;
		var pill_height = double.max(h + 2, cell_area.height - MARGIN_Y * 2);

		// Left justified against the leading edge of the cell, as the branch
		// chip is, past the horizontal padding that the text renderer keeps
		// for itself. Thus the pill starts where the message of an unmarked
		// row starts, and the left edges make a straight column.
		var x = (double)(cell_area.x + (int)xpad);

		// Rounded down to a whole pixel. The border below is one pixel wide,
		// and a fractional origin would spread it over two rows of pixels and
		// leave it grey and blurred.
		var y = Math.floor(cell_area.y + (cell_area.height - pill_height) / 2.0);

		// The text colour, which draws both the edge and the words.
		var fg = widget.get_style_context().get_color(widget.get_state_flags());

		cr.save();

		// Cairo puts half of a stroke on each side of the path, thus the path
		// is inset by half the border and the ink stays inside the pill. The
		// pill then covers the same box as the branch chip would with the same
		// words, and the inset lands the border on the pixel grid, as the
		// labels of gitg do. The radius is inset with it, so that the outer
		// edge of the border keeps the radius of the chip.
		var inset = BORDER_WIDTH / 2.0;

		rounded_rectangle(cr,
		                  x + inset, y + inset,
		                  pill_width - BORDER_WIDTH, pill_height - BORDER_WIDTH,
		                  RADIUS - inset);

		// The edge alone, with no fill under it. Without the edge the mark
		// would be its words on the row and would read as part of the message.
		cr.set_source_rgba(fg.red, fg.green, fg.blue, fg.alpha);
		cr.set_line_width(BORDER_WIDTH);
		cr.stroke();

		// The words of the mark take the foreground colour, which is already
		// the source, and read against the row as the message does.
		//
		// One pixel above the centre, which is where gitg puts the text of a
		// label. Words sit low in their line box, thus a true centre reads as
		// too low, and the lift corrects it.
		cr.move_to(x + PADDING_X, y + (pill_height - h) / 2.0 - 1);
		Pango.cairo_show_layout(cr, layout);

		cr.restore();

		// The message takes what is left. The base renderer ellipsizes against
		// the area it is given, thus a long message on this row ends earlier
		// than it would on an unmarked row, and does not run under the pill.
		var rest = cell_area;
		rest.x += pill_width + GAP;
		rest.width -= pill_width + GAP;

		if (rest.width > 0)
		{
			base.render(cr, widget, background_area, rest, flags);
		}
	}
}

}

// ex:set ts=4 noet:
