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

public class CellRendererOperations : Gtk.CellRenderer
{
	private const int WIDTH = 18;
	private const double LANE_WIDTH = 2.0;
	private const double NODE_RADIUS = 3.5;

	public string kind { get; set; default = ""; }

	public OperationPosition position { get; set; default = OperationPosition.SINGLE; }

	public int colour_index { get; set; default = -1; }

	public override void get_preferred_width(Gtk.Widget widget,
	                                         out int minimum,
	                                         out int natural)
	{
		minimum = WIDTH;
		natural = WIDTH;
	}

	private void set_lane_colour(Cairo.Context cr, bool darker)
	{
		if (colour_index < 0)
		{
			return;
		}

		var colour = Gitg.Color.from_index(colour_index);

		if (darker)
		{
			cr.set_source_rgb(colour.r * 0.6, colour.g * 0.6, colour.b * 0.6);
		}
		else
		{
			cr.set_source_rgb(colour.r, colour.g, colour.b);
		}
	}

	public override void render(Cairo.Context cr,
	                            Gtk.Widget widget,
	                            Gdk.Rectangle background_area,
	                            Gdk.Rectangle cell_area,
	                            Gtk.CellRendererState flags)
	{
		var centre_x = background_area.x + background_area.width / 2.0;
		var centre_y = background_area.y + background_area.height / 2.0;

		cr.save();

		if (position != OperationPosition.SINGLE)
		{
			double top = background_area.y;
			double bottom = background_area.y + background_area.height;

			if (position == OperationPosition.END)
			{
				top = centre_y;
			}
			else if (position == OperationPosition.START)
			{
				bottom = centre_y;
			}

			set_lane_colour(cr, false);
			cr.set_line_width(LANE_WIDTH);
			cr.move_to(centre_x, top);
			cr.line_to(centre_x, bottom);
			cr.stroke();

			cr.arc(centre_x, centre_y, NODE_RADIUS, 0, 2 * Math.PI);
			set_lane_colour(cr, false);
			cr.fill_preserve();
			set_lane_colour(cr, true);
			cr.set_line_width(1.0);
			cr.stroke();
		}
		else if (is_operation(kind))
		{
			cr.arc(centre_x, centre_y, NODE_RADIUS, 0, 2 * Math.PI);

			if (colour_index >= 0)
			{
				set_lane_colour(cr, false);
				cr.fill_preserve();
				set_lane_colour(cr, true);
			}
			else
			{
				var context = widget.get_style_context();
				var fg = context.get_color(widget.get_state_flags());
				cr.set_source_rgba(fg.red, fg.green, fg.blue, 0.7);
				cr.fill_preserve();
				cr.set_source_rgba(fg.red, fg.green, fg.blue, 1.0);
			}

			cr.set_line_width(1.0);
			cr.stroke();
		}

		cr.restore();
	}

	public static bool is_operation(string kind)
	{
		switch (kind)
		{
			case "commit":
			case "unknown":
				return false;
			default:
				return true;
		}
	}

	public static string describe(string kind, OperationPosition position, string message)
	{
		if (position != OperationPosition.SINGLE)
		{
			return _("Part of a %s").printf(kind);
		}

		switch (kind)
		{
			case "commit":
				if ("(amend)" in message) return _("Commit (amended)");
				if ("(initial)" in message) return _("First commit");
				return _("Commit");
			case "checkout": return _("Checkout");
			case "merge": return _("Merge");
			case "reset": return _("Reset");
			case "rebase": return _("Rebase");
			case "branch":
				return "Reset to" in message ? _("Branch moved") : _("Branch created");
			case "pull": return _("Pull");
			case "clone": return _("Clone");
			case "revert": return _("Revert");
			case "am": return _("Applied patch");
			default: return kind;
		}
	}
}

}
