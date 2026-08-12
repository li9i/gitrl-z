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

public class CellRendererMessage : Gtk.CellRendererText
{
	private const double RADIUS = 6.0;
	private const double FONT_SCALE = 0.83;
	private const int PADDING_X = 6;
	private const int MARGIN_Y = 2;
	private const double BORDER_WIDTH = 1.0;

	private const int GAP = 6;

	public string mark { get; set; default = ""; }

	private Pango.Layout create_layout(Gtk.Widget widget)
	{
		var layout = widget.create_pango_layout(mark);

		var font = layout.get_font_description();

		if (font == null)
		{
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

		var x = (double)(cell_area.x + (int)xpad);

		var y = Math.floor(cell_area.y + (cell_area.height - pill_height) / 2.0);

		var fg = widget.get_style_context().get_color(widget.get_state_flags());

		cr.save();

		var inset = BORDER_WIDTH / 2.0;

		rounded_rectangle(cr,
		                  x + inset, y + inset,
		                  pill_width - BORDER_WIDTH, pill_height - BORDER_WIDTH,
		                  RADIUS - inset);

		cr.set_source_rgba(fg.red, fg.green, fg.blue, fg.alpha);
		cr.set_line_width(BORDER_WIDTH);
		cr.stroke();

		cr.move_to(x + PADDING_X, y + (pill_height - h) / 2.0 - 1);
		Pango.cairo_show_layout(cr, layout);

		cr.restore();

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
