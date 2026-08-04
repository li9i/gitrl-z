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
 * Columns of the model of the reflog list.
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
	START,
	N_COLUMNS
}

/**
 * The reflog list (spec FR-123, FR-147, FR-151, FR-153, P-FR-11 to P-FR-16).
 *
 * The columns, from left to right: the operation gutter, a Branch chip that
 * only the `all` view shows, then SHA, Message, Date and Selector. The hash is
 * first, because the user looks for it. The selector is last, because it is
 * position data and not content. There is no author and no email.
 *
 * The columns fit their content at open (FR-147), and the user can resize
 * them. A row in the reset plan has a light background tint in the colour of
 * its branch (FR-151). The colour of each branch comes from the map that the
 * lane walk of the graph made (FR-153).
 *
 * One row can carry the session mark, a pill before its message that says this
 * entry was the newest of this reflog when the window opened (FR-170).
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
	private CellRendererMessage d_message_renderer;
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
	 * The branch of all rows in a branch view, or null in the `all` and
	 * `stash` views.
	 *
	 * The reflog of a branch has no checkout entries. Thus attribution by
	 * checkout tracking would give the rows to the default branch, and not to
	 * the branch of this log. There the plan targets the branch of the view,
	 * as ResetPreview.target_branch_for does. The tint must do the same. If
	 * not, a planned row in a branch view has no mark.
	 */
	private string? d_view_branch;

	/** The reset plan, so a planned row can be tinted (FR-151), or null. */
	private ResetPlan? d_plan;

	/** The search text, lowercased, or "" for no filtering (FR-117). */
	private string d_filter_text = "";

	/** The time window that limits the list (FR-156). ANY is no window. */
	private TimeWindow d_window = TimeWindow.ANY;

	/** The entry-count limit (FR-157). 0 is no limit. */
	private uint d_count = 0;

	/**
	 * The store rows that a limit leaves visible, one flag for each entry
	 * (IC-160).
	 *
	 * The code computes this again when the entries or a limit change. Thus
	 * the callback of the filter for each row is a lookup and not a walk. The
	 * count limit must know how many earlier rows passed, and a predicate for
	 * one row cannot know this. Thus the code decides the full list at one
	 * time, here.
	 */
	private bool[] d_visible = {};

	/** The strength of the plan tint: a light wash, and not a solid block. */
	private const double TINT_ALPHA = 0.28;

	/** Extra width for a fitted column, and for a header measured for its title. */
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
		                            typeof(string),   // PLAN_BG
		                            typeof(string));  // START

		// A filter model is between the store and the view. Thus a search can
		// hide rows and does not change the data (FR-117). The view then
		// returns a filtered path. The accessors below change that path to a
		// store row before they index d_entries.
		d_filter = new Gtk.TreeModelFilter(d_store, null);
		d_filter.set_visible_func(row_matches_filter);

		d_view.model = d_filter;

		build_columns();
	}

	/**
	 * Says if a row passes the current limits (FR-117, FR-156, FR-157).
	 *
	 * recompute_visible() made the decision and put it in d_visible, indexed
	 * by store row. This method only reads it. If the index of a row is out of
	 * range, which can occur during a rebuild, the row is visible.
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
	 * Sets the search text (FR-117). An empty string clears the predicate.
	 */
	public void filter_text(string? text)
	{
		d_filter_text = text != null ? text.strip().down() : "";
		recompute_visible();
		d_filter.refilter();
	}

	/** Limits the list to a time window (FR-156). ANY is no window. */
	public void set_window(TimeWindow window)
	{
		d_window = window;
		recompute_visible();
		d_filter.refilter();
	}

	/** Limits the list to the newest `count` entries (FR-157). 0 is no limit. */
	public void set_count(uint count)
	{
		d_count = count;
		recompute_visible();
		d_filter.refilter();
	}

	/** Says if a time window or an entry limit is active (FR-161). */
	public bool has_active_limit()
	{
		return d_window != TimeWindow.ANY || d_count != 0;
	}

	/**
	 * Computes again which rows are visible with the current limits (IC-160).
	 *
	 * Each call measures the window against the present time (FR-163). There
	 * is no timer, thus this is the only location that reads "now".
	 */
	private void recompute_visible()
	{
		d_visible = ReflogFilter.visible(d_entries,
		                                 new DateTime.now_local(),
		                                 d_window.seconds(),
		                                 d_count,
		                                 d_filter_text);
	}

	/** The filtered model that the view shows, for the search tests. */
	public Gtk.TreeModel filtered_model
	{
		get { return d_filter; }
	}

	/** The number of rows visible now, after the filter. */
	public int visible_count()
	{
		return d_filter.iter_n_children(null);
	}

	/**
	 * The store row that a filtered path points at, or -1.
	 *
	 * The view uses filtered paths. d_entries and the annotation arrays use
	 * the store row as the index. Each method that takes a path from the view
	 * calls this method first.
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
		// The gutter. It has a fixed width and no title, because it is a
		// margin with data, and not a data column.
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
		// The plan tint covers the full row, and this cell (FR-151).
		gutter_column.add_attribute(d_gutter, "cell-background", ReflogColumn.PLAN_BG);

		d_view.append_column(gutter_column);

		// The Branch chip, in the `all` view only (P-FR-16). It is a filled
		// round pill that agrees with the ref pills of the graph. It is not a
		// text cell with a background. The labels of gitg are pills, and a
		// full-cell colour block looks like a table highlight and not like a
		// label.
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

		// SHA renders in monospace, because a hash is easiest to read in a
		// fixed width. Message, Date and Selector use the default font, as the
		// remainder of the UI does. Message expands and adds an ellipsis. The
		// others fit their content (FR-147, P-FR-13).
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

		// The session mark shares the Message column with the message itself
		// (FR-170), and one renderer draws the two. A column of its own would
		// hold the width of the pill on every row for a mark that one row
		// carries, and a second renderer in this column cannot take its width
		// from the row (refer to CellRendererMessage).
		d_message_renderer = new CellRendererMessage();
		d_message_renderer.ellipsize = Pango.EllipsizeMode.END;

		d_message_column = new Gtk.TreeViewColumn.with_attributes(
			_("Message"), d_message_renderer,
			"text", ReflogColumn.MESSAGE,
			"mark", ReflogColumn.START,
			"cell-background", ReflogColumn.PLAN_BG);
		d_message_column.sizing = Gtk.TreeViewColumnSizing.FIXED;
		d_message_column.resizable = true;
		// Message continues to expand and fills the remaining width. Its
		// fixed_width is only the minimum width, thus it is not fitted.
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
	 * Fills the list from the reflog of a ref.
	 *
	 * `show_branches` is true only in the `all` view, where entries can come
	 * from different branches. In a branch view or a stash view, each entry
	 * belongs to the same ref, and the column would give the same text on each
	 * row.
	 *
	 * `colours` maps a branch to the palette index that the graph gives it
	 * (FR-153). `plan` is the current reset plan, thus the code tints the rows
	 * that are already in it (FR-151). The two can be null before the code
	 * sets a repository. `view_branch` is the branch of the rows of a branch
	 * view, or null in the `all` and `stash` views.
	 *
	 * `start_index` is the row that was the newest entry of this reflog when
	 * gitrl-z opened the repository, and -1 when this view has none (FR-170).
	 * That row gets the session mark.
	 */
	public void populate(Gee.List<ReflogEntry> entries,
	                     string? current_branch,
	                     bool show_branches,
	                     Gee.Map<string, int>? colours,
	                     ResetPlan? plan,
	                     string? view_branch,
	                     int start_index)
	{
		d_entries = entries;
		d_operations = ReflogAnnotations.classify_operations(entries);
		d_branches = ReflogAnnotations.attribute_branches(entries, current_branch);
		d_colours = colours;
		d_plan = plan;
		d_view_branch = view_branch;

		// Decide the visibility before the rows go in. Thus the callback of
		// the filter for each row reads a d_visible that includes them. The
		// current limits stay after a populate (FR-161), thus a reload keeps
		// them.
		recompute_visible();

		d_branch_column.visible = show_branches;

		d_store.clear();

		// The words of the mark live with the column titles above, which are
		// the other visible strings of this file.
		var start_text = _("session start");

		for (var i = 0; i < entries.size; i++)
		{
			var entry = entries[i];

			// The colour is the position of the branch in the lane walk of
			// the graph. Thus a branch looks the same in the list and in the
			// graph (FR-153).
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
			            ReflogColumn.PLAN_BG, plan_tint(i),
			            ReflogColumn.START, i == start_index ? start_text : "");
		}

		fit_columns(show_branches);
	}

	/**
	 * Tints the rows again from the current plan, with no repopulate (FR-151).
	 *
	 * The code calls this method when the plan changes under a shown reflog.
	 * The key of the plan is the branch and the commit. Thus the tint follows
	 * the identity of the planned row, and not a position.
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
	 * The tint for the store row at `index`, or null if the row is not planned.
	 *
	 * It is a wash of the colour of the branch at a low alpha. GTK parses it
	 * from an `rgba()` string. Null leaves the cell-background unset, thus an
	 * unplanned row has the background of the theme.
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

		// All rows of a branch view belong to that branch. Only the `all` view
		// attributes them for each row (FR-148, and refer to d_view_branch).
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
	 * Sets each data column to fit its content, one time, on a populate
	 * (FR-147).
	 *
	 * The list runs in fixed-height mode, which needs FIXED sizing for the
	 * columns. Thus the fit is a measurement and not AUTOSIZE. The code
	 * measures the widest cell of each column through the renderer that draws
	 * it, and sets fixed_width to that value. The user can then drag the
	 * column, because it is resizable. The Message column continues to expand.
	 * The gutter is a fixed margin.
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
	 * The width that a column header needs for its title.
	 *
	 * Thus a fitted column is never more narrow than its own heading. The code
	 * measures it with the font of the view, and adds extra width for the
	 * padding of the header button.
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

	/** Says if the user can resize the data columns, for the FR-147 tests. */
	public bool columns_resizable
	{
		get { return d_branch_column.resizable && d_sha_column.resizable; }
	}

	/** Says if the store row at `index` has the plan tint, for the tests. */
	public bool row_is_tinted(int index)
	{
		return plan_tint(index) != null;
	}

	/** Says if the store row at `index` carries the session mark, for the tests. */
	public bool row_is_start_mark(int index)
	{
		Gtk.TreeIter iter;

		if (!d_store.get_iter(out iter, new Gtk.TreePath.from_indices(index)))
		{
			return false;
		}

		Value text;
		d_store.get_value(iter, ReflogColumn.START, out text);

		return (string)text != null && (string)text != "";
	}

	/** The branch attributed to the store row at `index`, for the tests. */
	public string? branch_for_index(int index)
	{
		return d_branches != null && index >= 0 && index < d_branches.length
			? d_branches[index] : null;
	}

	/**
	 * The time since an entry occurred, in the words of gitg (P-FR-11).
	 *
	 * This method uses Gitg.Date.for_display(), and not the words that the
	 * Python implementation computed. gitg gives "Half an hour ago" and "A
	 * minute ago" where the Python gave "30 minutes ago" and "1 minute ago".
	 * The purpose of the rewrite is to look like gitg, thus the words of gitg
	 * have priority.
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
	 * The view path for a store row, or null if the filter hides it.
	 *
	 * The activity selects rows by store index. A reload finds an entry by
	 * hash, then selects it again. With an active filter, the code must map
	 * that index forward to a filtered path, and the row can be invisible.
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
	 * A tooltip that names the operation kind of a row (P-FR-15).
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
