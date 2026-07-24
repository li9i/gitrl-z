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
 * Columns of the reflog list's model.
 */
public enum ReflogColumn
{
	KIND,
	POSITION,
	COLOUR,
	BRANCH,
	SHA,
	MESSAGE,
	DATE,
	SELECTOR,
	PLAN_BG,
	N_COLUMNS
}

/**
 * The reflog list (spec FR-123, FR-147, FR-151, FR-153, P-FR-11 to P-FR-16).
 *
 * Columns, left to right: the operation gutter, a Branch chip shown only in
 * the `all` view, then SHA, Message, Date and Selector. The hash leads
 * because it is what the eye looks for; the selector trails because it is
 * positional bookkeeping rather than content. No author, no email.
 *
 * Columns size to their content on open (FR-147) and stay resizable. A row
 * that is part of the reset plan carries a faint background tint in its
 * branch's colour (FR-151), and every branch's colour comes from the map the
 * graph's own lane walk produced (FR-153).
 */
public class ReflogList : Object
{
	private unowned Gtk.TreeView d_view;
	private Gtk.ListStore d_store;
	private Gtk.TreeModelFilter d_filter;
	private CellRendererOperations d_gutter;

	private Gtk.TreeViewColumn d_branch_column;
	private CellRendererBranch d_branch_renderer;
	private Gtk.TreeViewColumn d_sha_column;
	private Gtk.CellRendererText d_sha_renderer;
	private Gtk.TreeViewColumn d_message_column;
	private Gtk.CellRendererText d_message_renderer;
	private Gtk.TreeViewColumn d_date_column;
	private Gtk.CellRendererText d_date_renderer;
	private Gtk.TreeViewColumn d_selector_column;
	private Gtk.CellRendererText d_selector_renderer;

	private Gee.List<ReflogEntry> d_entries;
	private Operation[] d_operations;
	private string?[] d_branches;

	/** The branch-to-colour map for the shown reflog (FR-153), or null. */
	private Gee.Map<string, int>? d_colours;

	/**
	 * The branch a branch-view's rows all belong to, or null in the `all` and
	 * `stash` views.
	 *
	 * A branch's own reflog has no checkout entries, so attributing rows by
	 * checkout tracking would credit them to the default branch, not the one
	 * whose log this is. The plan targets the view's branch there (as
	 * ResetPreview.target_branch_for does), so the tint has to as well, or a
	 * planned row in a branch view is never marked.
	 */
	private string? d_view_branch;

	/** The reset plan, so a planned row can be tinted (FR-151), or null. */
	private ResetPlan? d_plan;

	/** The search text, lowercased, or "" for no filtering (FR-117). */
	private string d_filter_text = "";

	/** The time window the list is limited to (FR-156), ANY for no window. */
	private TimeWindow d_window = TimeWindow.ANY;

	/** The entry-count cap (FR-157), 0 for no cap. */
	private uint d_count = 0;

	/**
	 * Which store rows a limit leaves visible, one flag per entry (IC-160).
	 *
	 * Recomputed whenever the entries or any limit change, so the filter's
	 * per-row callback is a lookup rather than a walk. The count cap has to
	 * know how many earlier rows passed, which a per-row predicate cannot see,
	 * so the whole list is judged at once, here.
	 */
	private bool[] d_visible = {};

	/** How faint the plan tint is: a wash of the branch colour, not a block. */
	private const double TINT_ALPHA = 0.28;

	/** Slack added to a fitted column, and to a header measured for its title. */
	private const int COLUMN_PAD = 10;
	private const int HEADER_PAD = 28;

	public ReflogList(Gtk.TreeView view)
	{
		d_view = view;
		d_entries = new Gee.ArrayList<ReflogEntry>();

		d_store = new Gtk.ListStore(ReflogColumn.N_COLUMNS,
		                            typeof(string),   // KIND
		                            typeof(int),      // POSITION
		                            typeof(int),      // COLOUR
		                            typeof(string),   // BRANCH
		                            typeof(string),   // SHA
		                            typeof(string),   // MESSAGE
		                            typeof(string),   // DATE
		                            typeof(string),   // SELECTOR
		                            typeof(string));  // PLAN_BG

		// A filter model sits between the store and the view so search can
		// hide rows without touching the underlying data (FR-117). The path
		// the view hands back is then a filtered path, which the accessors
		// below convert to a store row before indexing d_entries.
		d_filter = new Gtk.TreeModelFilter(d_store, null);
		d_filter.set_visible_func(row_matches_filter);

		d_view.model = d_filter;

		build_columns();
	}

	/**
	 * Whether a row passes the current limits (FR-117, FR-156, FR-157).
	 *
	 * The decision was made in recompute_visible() and cached in d_visible,
	 * indexed by store row; here it is only read back. A row whose index is out
	 * of range, which can happen mid-rebuild, defaults to visible.
	 */
	private bool row_matches_filter(Gtk.TreeModel model, Gtk.TreeIter iter)
	{
		var indices = model.get_path(iter).get_indices();

		if (indices.length == 0)
		{
			return true;
		}

		var index = indices[0];

		return index >= 0 && index < d_visible.length ? d_visible[index] : true;
	}

	/**
	 * Set the search text (FR-117). Empty clears the search predicate.
	 */
	public void filter_text(string? text)
	{
		d_filter_text = text != null ? text.strip().down() : "";
		recompute_visible();
		d_filter.refilter();
	}

	/** Limit the list to a time window (FR-156); ANY is no window. */
	public void set_window(TimeWindow window)
	{
		d_window = window;
		recompute_visible();
		d_filter.refilter();
	}

	/** Cap the list to the newest `count` entries (FR-157); 0 is no cap. */
	public void set_count(uint count)
	{
		d_count = count;
		recompute_visible();
		d_filter.refilter();
	}

	/** Whether a time window or an entry cap is in force (FR-161). */
	public bool has_active_limit()
	{
		return d_window != TimeWindow.ANY || d_count != 0;
	}

	/**
	 * Recompute which rows are visible under the current limits (IC-160).
	 *
	 * The window is measured against the present time on each call (FR-163);
	 * there is no timer, so this is the only place "now" is read.
	 */
	private void recompute_visible()
	{
		d_visible = ReflogFilter.visible(d_entries,
		                                 new DateTime.now_local(),
		                                 d_window.seconds(),
		                                 d_count,
		                                 d_filter_text);
	}

	/** The filtered model the view shows, for the search tests. */
	public Gtk.TreeModel filtered_model
	{
		get { return d_filter; }
	}

	/** The number of rows currently visible after filtering. */
	public int visible_count()
	{
		return d_filter.iter_n_children(null);
	}

	/**
	 * The store row a filtered path points at, or -1.
	 *
	 * The view works in filtered paths; d_entries and the annotation arrays
	 * are indexed by store row. Everything that takes a path from the view
	 * goes through here first.
	 */
	private int store_index(Gtk.TreePath path)
	{
		Gtk.TreeIter filter_iter;

		if (!d_filter.get_iter(out filter_iter, path))
		{
			return -1;
		}

		Gtk.TreeIter child_iter;
		d_filter.convert_iter_to_child_iter(out child_iter, filter_iter);

		var child_path = d_store.get_path(child_iter);
		var indices = child_path.get_indices();

		return indices.length > 0 ? indices[0] : -1;
	}

	public Gee.List<ReflogEntry> entries
	{
		get { return d_entries; }
	}

	private void build_columns()
	{
		// The gutter. Fixed width, no title: it is a margin that means
		// something, not a data column.
		d_gutter = new CellRendererOperations();

		var gutter_column = new Gtk.TreeViewColumn();
		gutter_column.title = "";
		gutter_column.sizing = Gtk.TreeViewColumnSizing.FIXED;
		gutter_column.fixed_width = 22;
		gutter_column.pack_start(d_gutter, false);
		gutter_column.set_cell_data_func(d_gutter, (layout, cell, model, iter) => {
			var renderer = cell as CellRendererOperations;

			Value kind;
			Value position;
			Value colour;

			model.get_value(iter, ReflogColumn.KIND, out kind);
			model.get_value(iter, ReflogColumn.POSITION, out position);
			model.get_value(iter, ReflogColumn.COLOUR, out colour);

			renderer.kind = (string)kind;
			renderer.position = (OperationPosition)((int)position);
			renderer.colour_index = (int)colour;
		});
		// The plan tint runs the whole row, this cell included (FR-151).
		gutter_column.add_attribute(d_gutter, "cell-background", ReflogColumn.PLAN_BG);

		d_view.append_column(gutter_column);

		// The Branch chip, `all` view only (P-FR-16). A filled rounded pill
		// matching the graph's ref pills, rather than a text cell with a
		// background: gitg's labels are pills, and a full-cell colour block
		// reads as a table highlight instead of as a label.
		d_branch_renderer = new CellRendererBranch();

		d_branch_column = new Gtk.TreeViewColumn();
		d_branch_column.title = _("Branch");
		d_branch_column.sizing = Gtk.TreeViewColumnSizing.FIXED;
		d_branch_column.resizable = true;
		d_branch_column.fixed_width = 110;
		d_branch_column.pack_start(d_branch_renderer, true);
		d_branch_column.set_cell_data_func(d_branch_renderer, (layout, cell, model, iter) => {
			var renderer = cell as CellRendererBranch;

			Value branch;
			Value colour;

			model.get_value(iter, ReflogColumn.BRANCH, out branch);
			model.get_value(iter, ReflogColumn.COLOUR, out colour);

			renderer.branch = (string)branch;
			renderer.colour_index = (int)colour;
		});
		d_branch_column.add_attribute(d_branch_renderer, "cell-background", ReflogColumn.PLAN_BG);

		d_view.append_column(d_branch_column);

		// SHA renders in monospace, since a hash reads best fixed-width; Message,
		// Date and Selector use the default font like the rest of the UI.
		// Message expands and ellipsises; the others size to content (FR-147,
		// P-FR-13).
		d_sha_renderer = new Gtk.CellRendererText();
		d_sha_renderer.family = "monospace";

		d_sha_column = new Gtk.TreeViewColumn.with_attributes(
			_("SHA"), d_sha_renderer,
			"text", ReflogColumn.SHA,
			"cell-background", ReflogColumn.PLAN_BG);
		d_sha_column.sizing = Gtk.TreeViewColumnSizing.FIXED;
		d_sha_column.resizable = true;
		d_sha_column.fixed_width = 90;
		d_view.append_column(d_sha_column);

		d_message_renderer = new Gtk.CellRendererText();
		d_message_renderer.ellipsize = Pango.EllipsizeMode.END;

		d_message_column = new Gtk.TreeViewColumn.with_attributes(
			_("Message"), d_message_renderer,
			"text", ReflogColumn.MESSAGE,
			"cell-background", ReflogColumn.PLAN_BG);
		d_message_column.sizing = Gtk.TreeViewColumnSizing.FIXED;
		d_message_column.resizable = true;
		// Message keeps expanding to fill the width left over; its fixed_width
		// is only the floor it will not shrink below, so it is not fitted.
		d_message_column.expand = true;
		d_message_column.fixed_width = 400;
		d_view.append_column(d_message_column);

		d_date_renderer = new Gtk.CellRendererText();

		d_date_column = new Gtk.TreeViewColumn.with_attributes(
			_("Date"), d_date_renderer,
			"text", ReflogColumn.DATE,
			"cell-background", ReflogColumn.PLAN_BG);
		d_date_column.sizing = Gtk.TreeViewColumnSizing.FIXED;
		d_date_column.resizable = true;
		d_date_column.fixed_width = 130;
		d_view.append_column(d_date_column);

		d_selector_renderer = new Gtk.CellRendererText();

		d_selector_column = new Gtk.TreeViewColumn.with_attributes(
			_("Selector"), d_selector_renderer,
			"text", ReflogColumn.SELECTOR,
			"cell-background", ReflogColumn.PLAN_BG);
		d_selector_column.sizing = Gtk.TreeViewColumnSizing.FIXED;
		d_selector_column.resizable = true;
		d_selector_column.fixed_width = 110;
		d_view.append_column(d_selector_column);
	}

	/**
	 * Fill the list from a ref's reflog.
	 *
	 * `show_branches` is true only in the `all` view, where entries can come
	 * from different branches; in a branch or stash view every entry belongs
	 * to the same ref and the column would say the same thing on every row.
	 *
	 * `colours` maps a branch to the palette index the graph gives it (FR-153).
	 * `plan` is the current reset plan, so rows already in it are tinted
	 * (FR-151); both may be null before a repository is set. `view_branch` is
	 * the branch a branch-view's rows belong to, or null in the `all` and
	 * `stash` views.
	 */
	public void populate(Gee.List<ReflogEntry> entries,
	                     string? current_branch,
	                     bool show_branches,
	                     Gee.Map<string, int>? colours,
	                     ResetPlan? plan,
	                     string? view_branch)
	{
		d_entries = entries;
		d_operations = ReflogAnnotations.classify_operations(entries);
		d_branches = ReflogAnnotations.attribute_branches(entries, current_branch);
		d_colours = colours;
		d_plan = plan;
		d_view_branch = view_branch;

		// Judge visibility before the rows go in, so the filter's per-row
		// callback reads a d_visible that already covers them. The current
		// limits persist across a populate (FR-161), so a reload keeps them.
		recompute_visible();

		d_branch_column.visible = show_branches;

		d_store.clear();

		for (var i = 0; i < entries.size; i++)
		{
			var entry = entries[i];

			// The colour is the branch's slot in the graph's lane walk, so a
			// branch looks the same in the list and the graph (FR-153).
			var branch = d_branches[i];
			var colour = branch != null && colours != null && colours.has_key(branch)
				? colours[branch] : -1;

			Gtk.TreeIter iter;
			d_store.append(out iter);

			d_store.set(iter,
			            ReflogColumn.KIND, d_operations[i].kind,
			            ReflogColumn.POSITION, (int)d_operations[i].position,
			            ReflogColumn.COLOUR, colour,
			            ReflogColumn.BRANCH, branch != null ? branch : "",
			            ReflogColumn.SHA, entry.abbreviated_id,
			            ReflogColumn.MESSAGE, entry.message,
			            ReflogColumn.DATE, format_date(entry.date),
			            ReflogColumn.SELECTOR, entry.selector,
			            ReflogColumn.PLAN_BG, plan_tint(i));
		}

		fit_columns(show_branches);
	}

	/**
	 * Re-tint the rows from the current plan, without repopulating (FR-151).
	 *
	 * Called when the plan changes under a shown reflog. The plan is keyed by
	 * branch and commit, so the tint follows the identity of the planned row,
	 * not a position.
	 */
	public void refresh_plan_marks()
	{
		Gtk.TreeIter iter;

		if (!d_store.get_iter_first(out iter))
		{
			return;
		}

		var i = 0;

		do
		{
			d_store.set(iter, ReflogColumn.PLAN_BG, plan_tint(i));
			i++;
		}
		while (d_store.iter_next(ref iter));
	}

	/**
	 * The tint for the store row at `index`, or null when it is not planned.
	 *
	 * A wash of the branch's colour at low alpha, parsed by GTK from an
	 * `rgba()` string. Null leaves the cell-background unset, so an unplanned
	 * row carries the theme's own background.
	 */
	private string? plan_tint(int index)
	{
		if (d_plan == null || d_branches == null)
		{
			return null;
		}

		if (index < 0 || index >= d_entries.size || index >= d_branches.length)
		{
			return null;
		}

		// A branch view's rows all belong to that branch; only the `all` view
		// attributes them per row (FR-148, and see d_view_branch).
		var branch = d_view_branch != null ? d_view_branch : d_branches[index];
		var commit = d_entries[index].new_id;

		if (branch == null || commit == null || !d_plan.contains(branch, commit))
		{
			return null;
		}

		var colour = d_colours != null && d_colours.has_key(branch)
			? d_colours[branch] : -1;

		if (colour < 0)
		{
			return null;
		}

		var c = Gitg.Color.from_index(colour);

		return "rgba(%u,%u,%u,%.3f)".printf(
			(uint)(c.r * 255 + 0.5),
			(uint)(c.g * 255 + 0.5),
			(uint)(c.b * 255 + 0.5),
			TINT_ALPHA);
	}

	/**
	 * Size each data column to fit its content, once, on populate (FR-147).
	 *
	 * The list runs in fixed-height mode, which requires columns to be FIXED
	 * sizing, so the fit is a measurement rather than AUTOSIZE: each column's
	 * widest cell is measured through the renderer that draws it, and its
	 * fixed_width set to that. The user can drag from there (resizable). The
	 * Message column is left expanding; the gutter is a fixed margin.
	 */
	private void fit_columns(bool show_branches)
	{
		if (show_branches)
		{
			fit_branch_column();
		}

		fit_text_column(d_sha_column, d_sha_renderer, ReflogColumn.SHA);
		fit_text_column(d_date_column, d_date_renderer, ReflogColumn.DATE);
		fit_text_column(d_selector_column, d_selector_renderer, ReflogColumn.SELECTOR);
	}

	private void fit_branch_column()
	{
		var widest = header_width(d_branch_column.title);

		Gtk.TreeIter iter;

		if (d_store.get_iter_first(out iter))
		{
			do
			{
				Value branch;
				d_store.get_value(iter, ReflogColumn.BRANCH, out branch);

				var name = (string)branch;

				if (name == null || name == "")
				{
					continue;
				}

				d_branch_renderer.branch = name;

				int min;
				int nat;
				d_branch_renderer.get_preferred_width(d_view, out min, out nat);

				if (nat > widest)
				{
					widest = nat;
				}
			}
			while (d_store.iter_next(ref iter));
		}

		d_branch_column.fixed_width = widest + COLUMN_PAD;
	}

	private void fit_text_column(Gtk.TreeViewColumn column,
	                             Gtk.CellRendererText renderer,
	                             ReflogColumn col)
	{
		var widest = header_width(column.title);

		Gtk.TreeIter iter;

		if (d_store.get_iter_first(out iter))
		{
			do
			{
				Value text;
				d_store.get_value(iter, col, out text);

				renderer.text = (string)text != null ? (string)text : "";

				int min;
				int nat;
				renderer.get_preferred_width(d_view, out min, out nat);

				if (nat > widest)
				{
					widest = nat;
				}
			}
			while (d_store.iter_next(ref iter));
		}

		column.fixed_width = widest + COLUMN_PAD;
	}

	/**
	 * The width a column header needs for its title.
	 *
	 * So a fitted column is never narrower than its own heading. Measured off
	 * the view's font, with slack for the header button's padding.
	 */
	private int header_width(string title)
	{
		if (title == "")
		{
			return 0;
		}

		var layout = d_view.create_pango_layout(title);

		int w;
		int h;
		layout.get_pixel_size(out w, out h);

		return w + HEADER_PAD;
	}

	/**
	 * The current width of the Branch column, for the FR-147 tests.
	 */
	public int branch_column_width
	{
		get { return d_branch_column.fixed_width; }
	}

	/** Whether the data columns are user-resizable, for the FR-147 tests. */
	public bool columns_resizable
	{
		get { return d_branch_column.resizable && d_sha_column.resizable; }
	}

	/** Whether the store row at `index` carries the plan tint, for the tests. */
	public bool row_is_tinted(int index)
	{
		return plan_tint(index) != null;
	}

	/** The branch attributed to the store row at `index`, for the tests. */
	public string? branch_for_index(int index)
	{
		return d_branches != null && index >= 0 && index < d_branches.length
			? d_branches[index] : null;
	}

	/**
	 * How long ago an entry happened, worded as gitg words it (P-FR-11).
	 *
	 * This uses Gitg.Date.for_display() rather than the wording the Python
	 * implementation computed. gitg says "Half an hour ago" and "A minute
	 * ago" where the Python said "30 minutes ago" and "1 minute ago"; since
	 * the point of the rewrite is to look like gitg, gitg's own wording wins.
	 */
	private string format_date(DateTime? when)
	{
		if (when == null)
		{
			return "";
		}

		return new Gitg.Date.for_date_time(when).for_display();
	}

	/**
	 * The view path for a store row, or null when the filter hides it.
	 *
	 * The activity selects rows by store index (a reload matches an entry by
	 * hash, then wants to reselect it); with a filter active that index has
	 * to be mapped forward to a filtered path, and the row may not be visible
	 * at all.
	 */
	public Gtk.TreePath? view_path_for(int store_row)
	{
		Gtk.TreeIter child_iter;

		if (!d_store.get_iter(out child_iter, new Gtk.TreePath.from_indices(store_row)))
		{
			return null;
		}

		Gtk.TreeIter filter_iter;

		if (!d_filter.convert_child_iter_to_iter(out filter_iter, child_iter))
		{
			return null;
		}

		return d_filter.get_path(filter_iter);
	}

	/**
	 * The entry at a view path, or null.
	 */
	public ReflogEntry? entry_at(Gtk.TreePath path)
	{
		var index = store_index(path);

		return index >= 0 && index < d_entries.size ? d_entries[index] : null;
	}

	/**
	 * The branch attributed to the entry at a view path (P-FR-16).
	 */
	public string? branch_at(Gtk.TreePath path)
	{
		if (d_branches == null)
		{
			return null;
		}

		var index = store_index(path);

		return index >= 0 && index < d_branches.length ? d_branches[index] : null;
	}

	/**
	 * A tooltip naming the operation kind of a row (P-FR-15).
	 */
	public string? tooltip_at(Gtk.TreePath path)
	{
		if (d_operations == null)
		{
			return null;
		}

		var index = store_index(path);

		if (index < 0 || index >= d_operations.length)
		{
			return null;
		}

		return CellRendererOperations.describe(d_operations[index].kind,
		                                       d_operations[index].position,
		                                       d_entries[index].message);
	}
}

}

// ex:set ts=4 noet:
