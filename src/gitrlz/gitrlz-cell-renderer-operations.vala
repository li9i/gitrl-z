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
 * The operation gutter (spec P-FR-15).
 *
 * A column at the left of the reflog list. It shows a multi-step operation as
 * one unit. It agrees with the lanes of gitg:
 *
 *  - git records a rebase as an explicit start-to-finish run. The gutter
 *    draws it as the graph draws a lane: a two pixel line in the lane colour,
 *    for the full height of the run. On each row of the run there is a filled
 *    node with a ring in a darker shade. The length of the run shows its start
 *    and its finish. The oldest row is at the bottom, because the list is
 *    newest first.
 *
 *  - A single-step entry that moved the ref, and did not commit, gets its own
 *    node with no lane. Examples are a merge, a reset, a checkout and a branch
 *    creation. It is an operation, but not part of a run. Thus the gutter
 *    still gives data in a branch view, where a rebase cannot occur. A branch
 *    reflog holds no rebase start and no pick, because those move HEAD and not
 *    the branch.
 *
 *  - Plain commits draw nothing. They are the usual content of a reflog. A
 *    mark on each row would be decoration and not data. The empty rows make
 *    the operations easy to see.
 *
 *    This is different from P-FR-15, which gave plain commits a small tick.
 *    The tick had the same purpose, to make the operations easy to see. But in
 *    practice the tick decreased their visibility.
 *
 * The colours come from Gitg.Color. The lanes of the graph and the branch
 * chips of the list read the same source. Thus a branch looks the same in all
 * locations (FR-102).
 */
public class CellRendererOperations : Gtk.CellRenderer
{
	private const int WIDTH = 18;
	private const double LANE_WIDTH = 2.0;
	private const double NODE_RADIUS = 3.5;

	/** The operation kind, for the tooltip and the drawing style. */
	public string kind { get; set; default = ""; }

	public OperationPosition position { get; set; default = OperationPosition.SINGLE; }

	/**
	 * The lane colour index for the run of this row, or -1 for no lane.
	 */
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
			// Part of a run. The line covers the full row height, but at the
			// ends it stops at the node. Thus the run has clear limits and
			// does not continue into the adjacent rows.
			//
			// The list is newest first. Thus END is the newest row and is at
			// the top, and it draws in the downward direction. START is the
			// oldest row and is at the bottom, and it draws in the upward
			// direction.
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

			// A filled node with a ring in a darker shade, on each row of the
			// run, as the graph draws a commit.
			cr.arc(centre_x, centre_y, NODE_RADIUS, 0, 2 * Math.PI);
			set_lane_colour(cr, false);
			cr.fill_preserve();
			set_lane_colour(cr, true);
			cr.set_line_width(1.0);
			cr.stroke();
		}
		else if (is_operation(kind))
		{
			// A lone operation: a node, no lane.
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
		// A plain commit draws nothing. It is the usual content of a reflog.
		// A mark on each row filled the gutter with dots that gave no data.
		// Empty rows make the operations easy to read as marks, and not as
		// one more column of decoration.

		cr.restore();
	}

	/**
	 * Says if a kind moved the ref and did not commit.
	 *
	 * "commit" is the usual content. Each other kind here is an operation that
	 * gets its own node.
	 */
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

	/**
	 * A name for the operation, for the tooltip of the gutter (P-FR-15).
	 *
	 * This method takes the full message and not only the kind. The kind in
	 * IC-8 is the first word before the colon, and two different operations
	 * have the same kind:
	 *
	 *     branch: Created from main            a branch was created
	 *     branch: Reset to 7c63e9f...          a branch was moved (git branch -f)
	 *
	 * The two classify as `branch`. The name "Branch created" is wrong for the
	 * second one. No part of gitrl-z makes the second form now, but code that
	 * recommends `git branch -f` would make it frequent.
	 */
	public static string describe(string kind, OperationPosition position, string message)
	{
		if (position != OperationPosition.SINGLE)
		{
			return _("Part of a %s").printf(kind);
		}

		switch (kind)
		{
			case "commit":
				// The variants in parentheses are different. An amend
				// rewrites the previous commit and does not add one. Thus a
				// reset past it has a different result.
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

// ex:set ts=4 noet:
