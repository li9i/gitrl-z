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

public class CellRendererBranch : Gtk.CellRenderer
{
	private const double RADIUS = 4.0;
	private const double FONT_SCALE = 0.83;
	private const int PADDING_X = 6;
	private const int MARGIN_Y = 2;

	public string branch { get; set; default = ""; }

	public int colour_index { get; set; default = -1; }

	private Pango.Layout create_layout(Gtk.Widget widget)
	{
		var layout = widget.create_pango_layout(branch);

		var font = layout.get_font_description();

		if (font == null)
		{
			font = widget.get_style_context().get_font(widget.get_state_flags()).copy();
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

	public override void get_preferred_width(Gtk.Widget widget,
	                                         out int minimum,
	                                         out int natural)
	{
		if (branch == null || branch == "")
		{
			minimum = 0;
			natural = 0;
			return;
		}

		var layout = create_layout(widget);

		int w;
		int h;
		layout.get_pixel_size(out w, out h);

		minimum = w + PADDING_X * 2;
		natural = minimum;
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
		if (branch == null || branch == "" || colour_index < 0)
		{
			return;
		}

		var layout = create_layout(widget);

		int w;
		int h;
		layout.get_pixel_size(out w, out h);

		var pill_width = w + PADDING_X * 2;
		var pill_height = double.max(h + 2, cell_area.height - MARGIN_Y * 2);

		var x = (double)cell_area.x;

		var y = Math.floor(cell_area.y + (cell_area.height - pill_height) / 2.0);

		var colour = Gitg.Color.from_index(colour_index);

		cr.save();

		rounded_rectangle(cr, x, y, pill_width, pill_height, RADIUS);
		cr.set_source_rgb(colour.r, colour.g, colour.b);
		cr.fill();

		cr.set_source_rgb(1.0, 1.0, 1.0);
		cr.move_to(x + PADDING_X, y + (pill_height - h) / 2.0 - 1);
		Pango.cairo_show_layout(cr, layout);

		cr.restore();
	}
}

}
