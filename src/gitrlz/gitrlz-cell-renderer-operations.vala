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
 * A column at the left of the reflog list that makes a multi-step operation
 * read as one unit. Drawn to match gitg's lanes rather than invented:
 *
 *  - A rebase, which git records as an explicit start-to-finish run, is drawn
 *    the way the graph draws a lane — a two pixel line in the lane colour
 *    running the height of the run, carrying a filled node ringed in a darker
 *    shade on every row it passes through. The run's extent is what marks its
 *    start and finish, the oldest row sitting lowest since the list runs
 *    newest first.
 *
 *  - A single-step entry that moved the ref by some means other than
 *    committing — a merge, a reset, a checkout, a branch creation — takes a
 *    node of its own with no lane. It is an operation, but not part of a run.
 *    This is what makes the gutter carry meaning in a branch view, where a
 *    rebase can never appear: a branch reflog holds no rebase start or pick,
 *    because those move HEAD rather than the branch.
 *
 *  - Plain commits draw nothing. They are the ordinary traffic of a reflog,
 *    and a mark on every row would be a column of decoration rather than a
 *    signal. The blank rows are what make the operations stand out.
 *
 *    This diverges from P-FR-15, which gave plain commits a quiet tick. The
 *    tick was there for the same reason — to make operations stand out — but
 *    in practice it competed with them instead.
 *
 * Colours come from Gitg.Color, the same source the graph's lanes and the
 * list's branch chips read, so a branch looks the same everywhere (FR-102).
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
	 * The lane colour index for this row's run, or -1 for no lane.
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
			// Part of a run. The line spans the full row height except at the
			// ends, where it stops at the node so the run reads as bounded
			// rather than running off into the neighbouring rows.
			//
			// The list is newest first, so END is the newest row and sits at
			// the top: it draws downward. START is the oldest and sits at the
			// bottom, drawing upward.
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

			// A filled node ringed in a darker shade, on every row the run
			// passes through, exactly as the graph draws a commit.
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
		// A plain commit draws nothing at all. It is the ordinary traffic of
		// a reflog, and marking every row of it filled the gutter with dots
		// that carried no information — leaving those rows blank is what
		// makes the operations legible as marks rather than as one more
		// column of decoration.

		cr.restore();
	}

	/**
	 * Whether a kind moved the ref by some means other than committing.
	 *
	 * "commit" is the ordinary traffic; everything else named here is an
	 * operation worth a node of its own.
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
	 * A human name for the operation, for the gutter's tooltip (P-FR-15).
	 *
	 * Takes the whole message, not just the kind, because IC-8's kind is the
	 * first word before the colon and two distinct operations share one:
	 *
	 *     branch: Created from main            a branch was created
	 *     branch: Reset to 7c63e9f...          a branch was moved (git branch -f)
	 *
	 * Both classify as `branch`, and calling the second one "Branch created"
	 * is simply wrong. Nothing in gitrl-z produces the second form today, but
	 * anything that recommends `git branch -f` would make it common.
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
				// The parenthesised variants are worth distinguishing: an
				// amend rewrites the previous commit rather than adding one,
				// which changes what resetting past it means.
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
