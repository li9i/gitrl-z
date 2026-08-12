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

	private Gee.Map<string, int>? d_colours;

	private string? d_view_branch;

	private ResetPlan? d_plan;

	private string d_filter_text = "";

	private TimeWindow d_window = TimeWindow.ANY;

	private uint d_count = 0;

	private bool[] d_visible = {};

	private const double TINT_ALPHA = 0.28;

	private const uint TINT_NEUTRAL = 128;

	private const int COLUMN_PAD = 10;
	private const int HEADER_PAD = 28;

	public ReflogList(Gtk.TreeView view)
	{
		d_view = view;
		d_entries = new Gee.ArrayList<ReflogEntry>();

		d_store = new Gtk.ListStore(ReflogColumn.N_COLUMNS,
		                            typeof(string),
		                            typeof(int),
		                            typeof(int),
		                            typeof(string),
		                            typeof(string),
		                            typeof(string),
		                            typeof(string),
		                            typeof(string),
		                            typeof(string),
		                            typeof(string));

		d_filter = new Gtk.TreeModelFilter(d_store, null);
		d_filter.set_visible_func(row_matches_filter);

		d_view.model = d_filter;

		build_columns();
	}

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

	public void filter_text(string? text)
	{
		d_filter_text = text != null ? text.strip().down() : "";
		recompute_visible();
		d_filter.refilter();
	}

	public void set_window(TimeWindow window)
	{
		d_window = window;
		recompute_visible();
		d_filter.refilter();
	}

	public void set_count(uint count)
	{
		d_count = count;
		recompute_visible();
		d_filter.refilter();
	}

	public bool has_active_limit()
	{
		return d_window != TimeWindow.ANY || d_count != 0;
	}

	private void recompute_visible()
	{
		d_visible = ReflogFilter.visible(d_entries,
		                                 new DateTime.now_local(),
		                                 d_window.seconds(),
		                                 d_count,
		                                 d_filter_text);
	}

	public Gtk.TreeModel filtered_model
	{
		get { return d_filter; }
	}

	public int visible_count()
	{
		return d_filter.iter_n_children(null);
	}

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

	public Gtk.TreeViewColumn date_column
	{
		get { return d_date_column; }
	}

	public string? date_tooltip_at(Gtk.TreePath path)
	{
		var entry = entry_at(path);

		if (entry == null || entry.date == null)
		{
			return null;
		}

		return entry.date.format("%Y-%m-%d %H:%M:%S %z");
	}

	public Gee.List<ReflogEntry> entries
	{
		get { return d_entries; }
	}

	private void build_columns()
	{
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
		gutter_column.add_attribute(d_gutter, "cell-background", ReflogColumn.PLAN_BG);

		d_view.append_column(gutter_column);

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

		d_message_renderer = new CellRendererMessage();
		d_message_renderer.ellipsize = Pango.EllipsizeMode.END;

		d_message_column = new Gtk.TreeViewColumn.with_attributes(
			_("Message"), d_message_renderer,
			"text", ReflogColumn.MESSAGE,
			"mark", ReflogColumn.START,
			"cell-background", ReflogColumn.PLAN_BG);
		d_message_column.sizing = Gtk.TreeViewColumnSizing.FIXED;
		d_message_column.resizable = true;
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

		recompute_visible();

		d_branch_column.visible = show_branches;

		d_store.clear();

		var start_text = _("session start");

		for (var i = 0; i < entries.size; i++)
		{
			var entry = entries[i];

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
			return "rgba(%u,%u,%u,%.3f)".printf(
				TINT_NEUTRAL, TINT_NEUTRAL, TINT_NEUTRAL, TINT_ALPHA);
		}

		var c = Gitg.Color.from_index(colour);

		return "rgba(%u,%u,%u,%.3f)".printf(
			(uint)(c.r * 255 + 0.5),
			(uint)(c.g * 255 + 0.5),
			(uint)(c.b * 255 + 0.5),
			TINT_ALPHA);
	}

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

	public int branch_column_width
	{
		get { return d_branch_column.fixed_width; }
	}

	public bool columns_resizable
	{
		get { return d_branch_column.resizable && d_sha_column.resizable; }
	}

	public bool row_is_tinted(int index)
	{
		return plan_tint(index) != null;
	}

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

	public string? branch_for_index(int index)
	{
		return d_branches != null && index >= 0 && index < d_branches.length
			? d_branches[index] : null;
	}

	private string format_date(DateTime? when)
	{
		if (when == null)
		{
			return "";
		}

		return new Gitg.Date.for_date_time(when).for_display();
	}

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

	public ReflogEntry? entry_at(Gtk.TreePath path)
	{
		var index = store_index(path);

		return index >= 0 && index < d_entries.size ? d_entries[index] : null;
	}

	public string? branch_at(Gtk.TreePath path)
	{
		if (d_branches == null)
		{
			return null;
		}

		var index = store_index(path);

		return index >= 0 && index < d_branches.length ? d_branches[index] : null;
	}

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
