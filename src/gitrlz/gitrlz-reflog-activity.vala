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

[GtkTemplate (ui = "/io/github/li9i/gitrlz/ui/gitrlz-reflog-paned.ui")]
public class ReflogPaned : Gtk.Paned
{
	[GtkChild]
	private unowned Gtk.ListBox d_refs_list;
	[GtkChild]
	private unowned Gtk.Paned d_paned_panels;
	[GtkChild]
	private unowned Gtk.Stack d_stack_reflog;
	[GtkChild]
	private unowned Gtk.TreeView d_reflog_list;
	[GtkChild]
	private unowned Gtk.Stack d_stack_preview;
	[GtkChild]
	private unowned Gtk.Label d_preview_placeholder;
	[GtkChild]
	private unowned Gitg.CommitListView d_commit_list_view;
	[GtkChild]
	private unowned Gtk.TreeViewColumn column_author;
	[GtkChild]
	private unowned Gtk.TreeViewColumn column_sha1;
	[GtkChild]
	private unowned Gtk.CellRendererText renderer_sha1;
	[GtkChild]
	private unowned Gtk.TreeViewColumn column_date;
	[GtkChild]
	private unowned Gtk.CellRendererText renderer_date;
	[GtkChild]
	private unowned Gtk.Label d_reflog_caption;
	[GtkChild]
	private unowned Gtk.Label d_graph_caption;
	[GtkChild]
	private unowned Gtk.SearchBar d_search_bar;
	[GtkChild]
	private unowned Gtk.SearchEntry d_search_entry;
	[GtkChild]
	private unowned Gtk.ComboBoxText d_time_combo;
	[GtkChild]
	private unowned Gtk.ComboBoxText d_entries_combo;
	[GtkChild]
	private unowned Gtk.Box d_warning;
	[GtkChild]
	private unowned Gtk.Label d_warning_label;
	[GtkChild]
	private unowned Gtk.Box d_banner;
	[GtkChild]
	private unowned Gtk.Label d_banner_label;
	[GtkChild]
	private unowned Gtk.Button d_banner_copy;

	private Gitg.Repository? d_repository;
	private ReflogList d_list;
	private Gitg.CommitModel? d_commit_model;
	private Settings d_state_settings;
	private Settings d_reflog_settings;
	private Settings d_interface_settings;
	private Monitor d_monitor;

	private string d_view = "all";

	private Gee.List<string> d_branches;
	private Gee.Map<string, Ggit.OId> d_tips;
	private string? d_current_branch;

	private Ggit.OId? d_opened_at;

	private SessionStart? d_session_start;

	private Gee.Map<string, int> d_colours;

	private ResetPlan d_plan;

	private HashTable<Ggit.OId, GLib.SList<Gitg.Ref>> d_preview_labels;

	private int d_saved_top_row = -1;

	private bool d_graph_fitted = false;

	private uint d_cursor_select_id = 0;

	private DiffWindow? d_diff_window;

	private string d_command = "";

	private string d_copied_command = "";

	private bool d_copied = false;

	private uint d_uncommitted = 0;

	private const int BANNER_MARGIN = 8;

	private const int GRAPH_COLUMN_PAD = 12;

	static construct
	{
		typeof(Gitg.CommitListView).ensure();
		typeof(Gitg.CellRendererLanes).ensure();
	}

	construct
	{
		d_branches = new Gee.ArrayList<string>();
		d_tips = new Gee.HashMap<string, Ggit.OId>();

		d_state_settings = new Settings("%s.state.reflog".printf(Config.APPLICATION_ID));
		d_reflog_settings = new Settings("%s.preferences.reflog".printf(Config.APPLICATION_ID));
		d_interface_settings = new Settings("%s.preferences.interface".printf(Config.APPLICATION_ID));

		d_monitor = new Monitor();
		d_interface_settings.bind("enable-monitoring", d_monitor, "enabled",
		                          SettingsBindFlags.GET);
		d_monitor.changed.connect(reload);

		d_state_settings.bind("paned-sidebar-position", this, "position",
		                      SettingsBindFlags.DEFAULT);

		ulong handler = 0;
		handler = d_paned_panels.size_allocate.connect((alloc) => {
			if (alloc.height <= 1)
				return;

			d_paned_panels.disconnect(handler);
			d_paned_panels.position = alloc.height / 2;
		});

		d_list = new ReflogList(d_reflog_list);
		d_plan = new ResetPlan();
		d_colours = new Gee.HashMap<string, int>();

		d_refs_list.row_selected.connect(on_ref_selected);

		d_reflog_list.button_press_event.connect(on_button_press);
		d_reflog_list.key_press_event.connect(on_key_press);

		d_commit_list_view.button_press_event.connect(on_graph_button_press);

		d_reflog_list.get_selection().set_mode(Gtk.SelectionMode.NONE);

		d_reflog_list.has_tooltip = true;
		d_reflog_list.query_tooltip.connect(on_query_tooltip);

		d_search_entry.search_changed.connect(() => {
			d_list.filter_text(d_search_entry.text);
			update_reflog_caption();
		});

		d_time_combo.active = 0;
		d_entries_combo.active = 0;

		d_time_combo.changed.connect(on_time_window_changed);
		d_entries_combo.changed.connect(on_entries_count_changed);

		column_date.set_cell_data_func(renderer_date, (layout, cell, model, iter) => {
			var renderer = cell as Gtk.CellRendererText;

			Value value;
			model.get_value(iter, Gitg.CommitModelColumns.COMMIT, out value);

			var commit = value.get_object() as Gitg.Commit;

			renderer.text = commit != null ? iso_date(commit) : "";
		});

		column_sha1.set_cell_data_func(renderer_sha1, (layout, cell, model, iter) => {
			var renderer = cell as Gtk.CellRendererText;

			Value value;
			model.get_value(iter, Gitg.CommitModelColumns.COMMIT, out value);

			var commit = value.get_object() as Gitg.Commit;

			renderer.text = commit != null ? abbreviated_sha(commit) : "";
		});

		d_banner_copy.clicked.connect(copy_command);

		d_preview_labels = new HashTable<Ggit.OId, GLib.SList<Gitg.Ref>>(
			Ggit.OId.hash, Ggit.OId.equal);
		install_preview_labels();

		show_all();
	}

	public Gitg.Repository? repository
	{
		get { return d_repository; }
		set
		{
			d_repository = value;

			if (d_diff_window != null)
			{
				d_diff_window.destroy();
			}

			d_opened_at = d_repository != null
				? Repository.head_commit(d_repository)
				: null;

			d_session_start = d_repository != null
				? SessionStart.read(d_repository,
				                    Repository.list_branches(d_repository),
				                    Repository.has_stash(d_repository))
				: null;

			d_plan = new ResetPlan();
			d_graph_fitted = false;

			d_commit_model = d_repository != null
				? new Gitg.CommitModel(d_repository)
				: null;

			if (d_commit_model != null)
			{
				d_commit_list_view.model = d_commit_model;

				d_commit_model.finished.connect(restore_scroll);
				d_commit_model.finished.connect(fit_graph_columns);
			}

			d_monitor.watch(d_repository != null
				? Repository.git_directory(d_repository)
				: null);

			reload();
		}
	}

	public ReflogList list
	{
		get { return d_list; }
	}

	public int plan_size
	{
		get { return d_plan.size; }
	}

	public uint graph_row_count()
	{
		return d_commit_model != null ? d_commit_model.size() : 0;
	}

	public int graph_top_row()
	{
		Gtk.TreePath? top;

		if (d_commit_list_view.get_visible_range(out top, null) && top != null)
		{
			var indices = top.get_indices();
			return indices.length > 0 ? indices[0] : -1;
		}

		return -1;
	}

	public void scroll_graph_to_row(int row)
	{
		d_commit_list_view.scroll_to_cell(
			new Gtk.TreePath.from_indices(row), null, true, 0.0f, 0.0f);
	}

	public int graph_column_width(string which)
	{
		switch (which)
		{
			case "author": return column_author.fixed_width;
			case "sha1": return column_sha1.fixed_width;
			case "date": return column_date.fixed_width;
			default: return -1;
		}
	}

	public bool ref_row_bold(string id)
	{
		foreach (var child in d_refs_list.get_children())
		{
			var row = child as Gtk.ListBoxRow;

			if (row == null || row.get_data<string>("ref") != id)
			{
				continue;
			}

			var label = row.get_child() as Gtk.Label;
			var attrs = label != null ? label.get_attributes() : null;

			if (attrs == null)
			{
				return false;
			}

			var it = attrs.get_iterator();

			do
			{
				unowned Pango.Attribute? a = it.get(Pango.AttrType.WEIGHT);

				if (a != null && ((Pango.AttrInt)a).value >= Pango.Weight.BOLD)
				{
					return true;
				}
			}
			while (it.next());

			return false;
		}

		return false;
	}

	public Ggit.OId[] included_tips { get; private set; }

	public string command
	{
		get { return d_command; }
	}

	public bool copied
	{
		get { return d_copied; }
	}

	public void copy_command()
	{
		if (d_command == "")
		{
			return;
		}

		copy_to_clipboard(d_command);

		d_copied_command = d_command;
		refresh_copied();
	}

	private void copy_to_clipboard(string text)
	{
		var clipboard = Gtk.Clipboard.get_default(get_display());

		if (clipboard == null)
		{
			return;
		}

		clipboard.set_text(text, -1);

		clipboard.set_can_store(null);
		clipboard.store();
	}

	private void popup_commit_menu(Gtk.Widget parent, Ggit.OId id, Gdk.EventButton event)
	{
		var menu = new Gtk.Menu();
		var commit = commit_at(id);

		if (commit != null)
		{
			var diff = new Gtk.MenuItem.with_mnemonic(_("_Show diff"));

			diff.activate.connect(() => {
				show_diff(commit);
			});

			menu.append(diff);
		}

		var copy = new Gtk.MenuItem.with_mnemonic(_("_Copy SHA"));

		copy.activate.connect(() => {
			copy_to_clipboard(id.to_string());
		});

		menu.append(copy);

		menu.attach_to_widget(parent, null);
		menu.show_all();
		menu.popup_at_pointer(event);
	}

	public string preview_state
	{
		owned get { return d_stack_preview.visible_child_name; }
	}

	public string preview_placeholder
	{
		owned get { return d_preview_placeholder.label; }
	}

	public string list_state
	{
		owned get { return d_stack_reflog.visible_child_name; }
	}

	public string view
	{
		get { return d_view; }
	}

	public Gee.List<string> ref_ids()
	{
		var ids = new Gee.ArrayList<string>();

		foreach (var child in d_refs_list.get_children())
		{
			var row = child as Gtk.ListBoxRow;

			if (row != null && row.selectable)
			{
				ids.add(row.get_data<string>("ref"));
			}
		}

		return ids;
	}

	public string ref_label(string id)
	{
		foreach (var child in d_refs_list.get_children())
		{
			var row = child as Gtk.ListBoxRow;

			if (row != null && row.get_data<string>("ref") == id)
			{
				var label = row.get_child() as Gtk.Label;
				return label != null ? label.label : "";
			}
		}

		return "";
	}

	public bool select_ref(string id)
	{
		foreach (var child in d_refs_list.get_children())
		{
			var row = child as Gtk.ListBoxRow;

			if (row != null && row.selectable && row.get_data<string>("ref") == id)
			{
				d_refs_list.select_row(row);
				return true;
			}
		}

		return false;
	}

	public void search(string? text)
	{
		d_list.filter_text(text);
	}

	public void set_search_visible(bool visible)
	{
		d_search_bar.search_mode_enabled = visible;

		if (visible)
		{
			d_search_entry.grab_focus();
		}
		else
		{
			d_search_entry.text = "";
		}
	}

	private void on_time_window_changed()
	{
		TimeWindow window;

		switch (d_time_combo.active)
		{
			case 1: window = TimeWindow.LAST_10_MIN; break;
			case 2: window = TimeWindow.LAST_HOUR; break;
			default: window = TimeWindow.ANY; break;
		}

		d_list.set_window(window);
		update_reflog_caption();
	}

	private void on_entries_count_changed()
	{
		var text = d_entries_combo.get_active_text();

		d_list.set_count(ReflogFilter.parse_count(text != null ? text : ""));
		update_reflog_caption();
	}

	public void choose_time_window(int index)
	{
		d_time_combo.active = index;
	}

	public void set_entries_text(string text)
	{
		var entry = d_entries_combo.get_child() as Gtk.Entry;

		if (entry != null)
		{
			entry.text = text;
		}
	}

	public void reload()
	{
		if (d_repository == null)
		{
			return;
		}

		d_repository.clear_refs_cache();

		d_branches = Repository.list_branches(d_repository);
		d_tips = Repository.branch_tips(d_repository);
		d_current_branch = Repository.current_branch(d_repository);
		d_colours = BranchColours.map(d_repository, d_tips);

		prune_plan();

		build_refs_list(d_view);
		load_reflog();
	}

	private void prune_plan()
	{
		d_plan.prune(d_branches);

		var doomed = new Gee.ArrayList<string>();

		foreach (var branch in d_plan.branches())
		{
			var commit = d_plan.target_for(branch);

			if (commit == null)
			{
				continue;
			}

			try
			{
				d_repository.lookup<Ggit.Commit>(commit);
			}
			catch (Error e)
			{
				doomed.add(branch);
			}
		}

		foreach (var branch in doomed)
		{
			d_plan.remove(branch);
		}
	}

	private void build_refs_list(string preferred)
	{
		foreach (var child in d_refs_list.get_children())
		{
			child.destroy();
		}

		add_ref_row("all", _("HEAD"), false);
		add_ref_row("", _("Branches"), true);

		foreach (var branch in d_branches)
		{
			var label = branch == d_current_branch
				? _("%s (checked out)").printf(branch)
				: branch;
			add_ref_row(branch, label, false);
		}

		if (Repository.has_stash(d_repository))
		{
			add_ref_row("stash", _("stash"), false);
		}

		d_refs_list.show_all();

		var wanted = preferred;

		if (wanted != "all" && wanted != "stash" && !(wanted in d_branches))
		{
			wanted = "all";
		}

		if (wanted == "stash" && !Repository.has_stash(d_repository))
		{
			wanted = "all";
		}

		select_ref_row(wanted);
		refresh_ref_weights();
	}

	private void refresh_ref_weights()
	{
		foreach (var child in d_refs_list.get_children())
		{
			var row = child as Gtk.ListBoxRow;

			if (row == null || !row.selectable)
			{
				continue;
			}

			var id = row.get_data<string>("ref");

			if (id == null || id == "" || id == "all" || id == "stash")
			{
				continue;
			}

			var label = row.get_child() as Gtk.Label;

			if (label == null)
			{
				continue;
			}

			var attrs = new Pango.AttrList();

			if (d_plan.target_for(id) != null)
			{
				var bold = Pango.attr_weight_new(Pango.Weight.BOLD);
				bold.start_index = 0;
				bold.end_index = id.length;
				attrs.insert((owned) bold);
			}

			label.set_attributes(attrs);
		}
	}

	private void add_ref_row(string id, string label_text, bool is_header)
	{
		var row = new Gtk.ListBoxRow();
		row.set_data<string>("ref", id);
		row.selectable = !is_header;
		row.activatable = !is_header;

		var label = new Gtk.Label(label_text);
		label.xalign = 0;
		label.margin_start = is_header ? 6 : 18;
		label.margin_end = 6;
		label.margin_top = 3;
		label.margin_bottom = 3;

		if (is_header)
		{
			label.get_style_context().add_class("dim-label");
			var attrs = new Pango.AttrList();
			attrs.insert(Pango.attr_weight_new(Pango.Weight.BOLD));
			label.set_attributes(attrs);
		}

		row.add(label);
		d_refs_list.add(row);
	}

	private void select_ref_row(string id)
	{
		foreach (var child in d_refs_list.get_children())
		{
			var row = child as Gtk.ListBoxRow;

			if (row != null && row.selectable && row.get_data<string>("ref") == id)
			{
				d_refs_list.select_row(row);
				d_view = id;
				return;
			}
		}
	}

	private void on_ref_selected(Gtk.ListBoxRow? row)
	{
		if (row == null)
		{
			return;
		}

		var id = row.get_data<string>("ref");

		if (id == null || id == "" || id == d_view)
		{
			return;
		}

		d_view = id;
		load_reflog();
	}

	private void load_reflog()
	{
		if (d_repository == null)
		{
			return;
		}

		var ref_name = d_view == "all" ? "HEAD" : d_view;
		var entries = Reflog.read(d_repository, ref_name);

		var view_branch = (d_view != "all" && d_view != "stash") ? d_view : null;

		var start_index = d_session_start != null
			? d_session_start.index_in(ref_name, entries)
			: -1;

		d_list.populate(entries, d_current_branch, d_view == "all", d_colours, d_plan,
		                view_branch, start_index);

		update_reflog_caption();

		d_stack_reflog.visible_child_name = entries.size > 0 ? "list" : "placeholder";

		update_preview();
	}

	private void update_reflog_caption()
	{
		string base_text;

		if (d_view == "stash")
		{
			base_text = _("Stashed changes");
		}
		else if (d_view == "all")
		{
			base_text = _("Reflog for HEAD");
		}
		else
		{
			base_text = _("Reflog for branch %s").printf(d_view);
		}

		if (d_list.has_active_limit() && d_list.entries.size > 0)
		{
			d_reflog_caption.label = _("%s (%d of %d)").printf(
				base_text, d_list.visible_count(), d_list.entries.size);
		}
		else
		{
			d_reflog_caption.label = base_text;
		}
	}

	private enum PlanFold
	{
		TOGGLE,
		SET_TARGET,
		SELECT_ONLY,
		SELECT_OR_DESELECT
	}

	private PlanFold click_fold(bool ctrl)
	{
		if (d_view != "all")
		{
			return PlanFold.TOGGLE;
		}

		return ctrl ? PlanFold.TOGGLE : PlanFold.SELECT_OR_DESELECT;
	}

	private PlanFold arrow_fold()
	{
		return d_view == "all" ? PlanFold.SELECT_ONLY : PlanFold.SET_TARGET;
	}

	private void plan_path(Gtk.TreePath path, PlanFold fold)
	{
		if (d_repository == null)
		{
			return;
		}

		var entry = d_list.entry_at(path);

		if (entry == null || entry.new_id == null)
		{
			return;
		}

		var operation = Repository.operation_in_progress(d_repository);

		if (operation != null)
		{
			show_operation_preview(operation);
			return;
		}

		if (d_view == "stash")
		{
			show_stash_preview(entry);
			return;
		}

		if (d_current_branch == null)
		{
			update_preview();
			return;
		}

		var branch = ResetPreview.target_branch_for(d_view, d_list.branch_at(path), d_tips);

		if (branch == null)
		{
			show_preview_placeholder(_("No branch to move for this entry"));
			return;
		}

		try
		{
			d_repository.lookup<Ggit.Commit>(entry.new_id);
		}
		catch (Error e)
		{
			show_preview_placeholder(
				_("Commit %s is not available").printf(entry.abbreviated_id));
			return;
		}

		switch (fold)
		{
			case PlanFold.TOGGLE:
				d_plan.toggle(branch, entry.new_id);
				break;
			case PlanFold.SET_TARGET:
				d_plan.set_target(branch, entry.new_id);
				break;
			case PlanFold.SELECT_ONLY:
				d_plan.set_only(branch, entry.new_id);
				break;
			case PlanFold.SELECT_OR_DESELECT:
				d_plan.set_only_or_clear(branch, entry.new_id);
				break;
		}

		d_list.refresh_plan_marks();
		refresh_ref_weights();
		update_preview();
	}

	public bool toggle_entry(int index)
	{
		return fold_entry(index, PlanFold.TOGGLE);
	}

	public bool select_entry(int index)
	{
		return fold_entry(index, arrow_fold());
	}

	public bool click_entry(int index)
	{
		return fold_entry(index, click_fold(false));
	}

	private bool fold_entry(int index, PlanFold fold)
	{
		var path = d_list.view_path_for(index);

		if (path == null)
		{
			return false;
		}

		plan_path(path, fold);
		return true;
	}

	private bool on_button_press(Gdk.EventButton event)
	{
		if (event.type != Gdk.EventType.BUTTON_PRESS
		    || (event.button != Gdk.BUTTON_PRIMARY
		        && event.button != Gdk.BUTTON_SECONDARY))
		{
			return false;
		}

		Gtk.TreePath? path;

		if (!d_reflog_list.get_path_at_pos((int)event.x, (int)event.y, out path, null, null, null))
		{
			return false;
		}

		if (event.button == Gdk.BUTTON_SECONDARY)
		{
			var entry = d_list.entry_at(path);

			if (entry == null || entry.new_id == null)
			{
				return false;
			}

			popup_commit_menu(d_reflog_list, entry.new_id, event);

			return true;
		}

		var ctrl = (event.state & Gdk.ModifierType.CONTROL_MASK) != 0;
		plan_path(path, click_fold(ctrl));

		return false;
	}

	private bool on_graph_button_press(Gdk.EventButton event)
	{
		if (event.type != Gdk.EventType.BUTTON_PRESS
		    || event.button != Gdk.BUTTON_SECONDARY)
		{
			return false;
		}

		Gtk.TreePath? path;

		if (!d_commit_list_view.get_path_at_pos((int)event.x, (int)event.y,
		                                        out path, null, null, null))
		{
			return false;
		}

		var commit = graph_commit_at(path);

		if (commit == null)
		{
			return false;
		}

		popup_commit_menu(d_commit_list_view, commit.get_id(), event);

		return true;
	}

	private Ggit.Commit? commit_at(Ggit.OId id)
	{
		if (d_repository == null)
		{
			return null;
		}

		try
		{
			return d_repository.lookup_commit(id);
		}
		catch (Error e)
		{
			return null;
		}
	}

	private Gitg.Commit? graph_commit_at(Gtk.TreePath path)
	{
		if (d_commit_model == null)
		{
			return null;
		}

		Gtk.TreeIter iter;

		if (!d_commit_model.get_iter(out iter, path))
		{
			return null;
		}

		Value value;
		d_commit_model.get_value(iter, Gitg.CommitModelColumns.COMMIT, out value);

		return value.get_object() as Gitg.Commit;
	}

	private void show_diff(Ggit.Commit commit)
	{
		if (d_repository == null)
		{
			return;
		}

		if (d_diff_window == null)
		{
			d_diff_window = new DiffWindow(get_toplevel() as Gtk.Window);
			d_diff_window.destroy.connect(() => {
				d_diff_window = null;
			});
		}

		d_diff_window.show_commit(d_repository, commit);
		d_diff_window.present();
	}

	private bool on_key_press(Gdk.EventKey event)
	{
		if (event.keyval == Gdk.Key.space
		    || event.keyval == Gdk.Key.Return
		    || event.keyval == Gdk.Key.KP_Enter)
		{
			Gtk.TreePath? path;
			d_reflog_list.get_cursor(out path, null);

			if (path == null)
			{
				return false;
			}

			plan_path(path, PlanFold.TOGGLE);

			return true;
		}

		if (is_vertical_nav_key(event.keyval))
		{
			schedule_cursor_select();
			return false;
		}

		return false;
	}

	private static bool is_vertical_nav_key(uint keyval)
	{
		switch (keyval)
		{
			case Gdk.Key.Up:
			case Gdk.Key.Down:
			case Gdk.Key.Page_Up:
			case Gdk.Key.Page_Down:
			case Gdk.Key.Home:
			case Gdk.Key.End:
			case Gdk.Key.KP_Up:
			case Gdk.Key.KP_Down:
			case Gdk.Key.KP_Page_Up:
			case Gdk.Key.KP_Page_Down:
			case Gdk.Key.KP_Home:
			case Gdk.Key.KP_End:
				return true;
			default:
				return false;
		}
	}

	private void schedule_cursor_select()
	{
		if (d_cursor_select_id != 0)
		{
			return;
		}

		d_cursor_select_id = Idle.add(() => {
			d_cursor_select_id = 0;

			Gtk.TreePath? path;
			d_reflog_list.get_cursor(out path, null);

			if (path != null)
			{
				plan_path(path, arrow_fold());
			}

			return Source.REMOVE;
		});
	}

	private void install_preview_labels()
	{
		foreach (var column in d_commit_list_view.get_columns())
		{
			foreach (var cell in column.get_cells())
			{
				if (cell is Gitg.CellRendererLanes)
				{
					column.set_cell_data_func(cell, preview_lanes_data_func);
				}
			}
		}
	}

	private void preview_lanes_data_func(Gtk.CellLayout   layout,
	                                     Gtk.CellRenderer cell,
	                                     Gtk.TreeModel    model,
	                                     Gtk.TreeIter     iter)
	{
		var m = model as Gitg.CommitModel;
		var lanes = cell as Gitg.CellRendererLanes;

		if (m == null || lanes == null)
		{
			return;
		}

		var commit = m.commit_from_iter(iter);

		if (commit == null)
		{
			return;
		}

		var cp = iter;
		Gitg.Commit? next_commit = null;

		if (m.iter_next(ref cp))
		{
			next_commit = m.commit_from_iter(cp);
		}

		lanes.commit = commit;
		lanes.next_commit = next_commit;
		lanes.labels = labels_for_preview(commit.get_id());
	}

	private unowned GLib.SList<Gitg.Ref> labels_for_preview(Ggit.OId id)
	{
		if (d_preview_labels != null && d_preview_labels.contains(id))
		{
			return d_preview_labels.lookup(id);
		}

		return d_repository != null ? d_repository.refs_for_id(id) : null;
	}

	private void rebuild_preview_labels()
	{
		d_preview_labels = new HashTable<Ggit.OId, GLib.SList<Gitg.Ref>>(
			Ggit.OId.hash, Ggit.OId.equal);

		if (d_repository == null)
		{
			return;
		}

		foreach (var branch in d_plan.branches())
		{
			var target = d_plan.target_for(branch);

			if (target == null)
			{
				continue;
			}

			var from = d_tips.has_key(branch) ? d_tips[branch] : null;

			if (from == null)
			{
				add_label(target, new SyntheticBranchRef(branch));
				continue;
			}

			if (from.equal(target))
			{
				continue;
			}

			var branch_ref = branch_ref_at(branch, from);

			if (branch_ref == null)
			{
				continue;
			}

			set_labels_without(from, branch_ref);
			add_label(target, branch_ref);
		}
	}

	private Gitg.Ref? branch_ref_at(string branch, Ggit.OId id)
	{
		foreach (unowned Gitg.Ref r in d_repository.refs_for_id(id))
		{
			if (r.parsed_name.rtype == Gitg.RefType.BRANCH
			    && r.parsed_name.shortname == branch)
			{
				return r;
			}
		}

		return null;
	}

	private void set_labels_without(Ggit.OId id, Gitg.Ref exclude)
	{
		var nlist = new GLib.SList<Gitg.Ref>();

		foreach (unowned Gitg.Ref r in current_preview_labels(id))
		{
			if (r.get_name() != exclude.get_name())
			{
				nlist.append(r);
			}
		}

		d_preview_labels.insert(id, (owned)nlist);
	}

	private void add_label(Ggit.OId id, Gitg.Ref add)
	{
		var nlist = new GLib.SList<Gitg.Ref>();

		foreach (unowned Gitg.Ref r in current_preview_labels(id))
		{
			nlist.append(r);
		}

		nlist.append(add);

		d_preview_labels.insert(id, (owned)nlist);
	}

	private unowned GLib.SList<Gitg.Ref> current_preview_labels(Ggit.OId id)
	{
		if (d_preview_labels.contains(id))
		{
			return d_preview_labels.lookup(id);
		}

		return d_repository.refs_for_id(id);
	}

	public string[] preview_labels_for(Ggit.OId id)
	{
		string[] names = {};

		foreach (unowned Gitg.Ref r in labels_for_preview(id))
		{
			names += r.parsed_name.shortname;
		}

		return names;
	}

	private void update_preview()
	{
		if (d_repository == null || d_commit_model == null)
		{
			return;
		}

		var operation = Repository.operation_in_progress(d_repository);

		if (operation != null)
		{
			show_operation_preview(operation);
			return;
		}

		if (d_current_branch == null && d_view != "stash")
		{
			show_detached_preview();
			return;
		}

		var tips = ResetPreview.preview_tips(d_tips, d_plan, d_opened_at);

		if (tips.length == 0)
		{
			show_preview_placeholder(_("Select an entry"));
			return;
		}

		included_tips = tips;

		rebuild_preview_labels();

		if (d_saved_top_row < 0)
		{
			Gtk.TreePath? top;

			if (d_commit_list_view.get_visible_range(out top, null) && top != null)
			{
				var indices = top.get_indices();

				if (indices.length > 0)
				{
					d_saved_top_row = indices[0];
				}
			}
		}

		d_commit_model.set_include(tips);
		d_commit_model.reload();

		if (d_plan.is_empty())
		{
			d_command = "";
			refresh_copied();
			d_banner.hide();
			set_warning_visible(false);
			d_graph_caption.label = _("Repository current state");
			d_graph_caption.show();
			d_stack_preview.visible_child_name = "graph";
			return;
		}

		d_command = ResetPreview.command_for(d_plan, d_current_branch, d_tips.keys);
		d_banner_label.label = d_command;
		refresh_copied();
		d_banner.show();

		update_uncommitted_warning();

		d_graph_caption.label = graph_caption_text();
		d_graph_caption.show();

		d_stack_preview.visible_child_name = "graph";
	}

	private string graph_caption_text()
	{
		var branches = d_plan.branches();

		if (branches.size == 1 && d_tips.has_key(branches[0]))
		{
			return _("Repository state after execution of the command above, with %s moved").printf(branches[0]);
		}

		return _("Repository state after execution of the command above");
	}

	private void restore_scroll()
	{
		if (d_saved_top_row < 0 || d_commit_model == null)
		{
			return;
		}

		var target = d_saved_top_row;
		d_saved_top_row = -1;

		var count = (int)d_commit_model.size();

		if (count <= 0)
		{
			return;
		}

		var row = target < count ? target : count - 1;

		d_commit_list_view.scroll_to_cell(
			new Gtk.TreePath.from_indices(row), null, true, 0.0f, 0.0f);
	}

	private void fit_graph_columns()
	{
		if (d_graph_fitted || d_commit_model == null)
		{
			return;
		}

		var count = (int)d_commit_model.size();

		if (count == 0)
		{
			return;
		}

		var limit = int.min(count, 500);

		var author_width = 0;
		var sha_width = 0;
		var date_width = 0;

		for (var i = 0; i < limit; i++)
		{
			var commit = d_commit_model.get(i);

			if (commit == null)
			{
				continue;
			}

			var author = commit.get_author();

			if (author != null)
			{
				author_width = int.max(author_width, text_width(author.get_name()));
			}

			sha_width = int.max(sha_width, text_width(abbreviated_sha(commit)));
			date_width = int.max(date_width, text_width(iso_date(commit)));
		}

		column_author.fixed_width = author_width + GRAPH_COLUMN_PAD;
		column_sha1.fixed_width = sha_width + GRAPH_COLUMN_PAD;
		column_date.fixed_width = date_width + GRAPH_COLUMN_PAD;

		d_graph_fitted = true;
	}

	private int text_width(string text)
	{
		var layout = d_commit_list_view.create_pango_layout(text);

		int w;
		int h;
		layout.get_pixel_size(out w, out h);

		return w;
	}

	private void show_preview_placeholder(string text)
	{
		d_preview_placeholder.label = text;
		d_stack_preview.visible_child_name = "placeholder";
		d_banner.hide();
		set_warning_visible(false);
		d_graph_caption.hide();
		d_command = "";
		refresh_copied();
	}

	private static string abbreviated_sha(Gitg.Commit commit)
	{
		var sha = commit.get_id().to_string();

		return sha.length > 7 ? sha.substring(0, 7) : sha;
	}

	private static string iso_date(Gitg.Commit commit)
	{
		var signature = commit.get_author();

		if (signature == null)
		{
			return "";
		}

		var when = signature.get_time();

		return when != null ? when.format("%Y-%m-%d %H:%M:%S %z") : "";
	}

	private void show_stash_preview(ReflogEntry entry)
	{
		show_command_note("git stash apply %s".printf(entry.selector),
			_("Applying a stash changes your files, not your branches, so there is no new history to show."));
	}

	private void show_detached_preview()
	{
		show_command_note("git checkout -",
			_("HEAD is detached, so you are not on a branch and there is nothing to reset. Run the command above to return to the branch you were on, then plan a reset from there."));
	}

	private static string operation_command(string operation)
	{
		return operation == "bisect" ? "git bisect reset"
		                             : "git %s --abort".printf(operation);
	}

	private void show_operation_preview(string operation)
	{
		show_command_note(operation_command(operation),
			_("A %s is in progress. Finish it, or run the command above to abort and undo it. Reset planning is off until you do.").printf(operation));
	}

	private void show_command_note(string command, string note)
	{
		d_command = command;
		d_banner_label.label = d_command;
		refresh_copied();
		d_banner.show();

		set_warning_visible(false);
		d_graph_caption.hide();

		included_tips = {};
		d_preview_labels = new HashTable<Ggit.OId, GLib.SList<Gitg.Ref>>(
			Ggit.OId.hash, Ggit.OId.equal);

		d_preview_placeholder.label = note;
		d_stack_preview.visible_child_name = "placeholder";
	}

	private void update_uncommitted_warning()
	{
		if (d_repository == null || d_command == "")
		{
			set_warning_visible(false);
			return;
		}

		if (!d_command.contains("reset --hard"))
		{
			set_warning_visible(false);
			return;
		}

		d_uncommitted = Repository.uncommitted_changes(d_repository);

		if (d_uncommitted == 0)
		{
			set_warning_visible(false);
			return;
		}

		if (d_uncommitted == uint.MAX)
		{
			d_warning_label.label =
				_("Your uncommitted changes could not be checked. If you have edited files without committing them, the command below will delete those edits permanently.");
		}
		else
		{
			d_warning_label.label = ngettext(
				"You have %u file with changes you have not committed. The command below will delete those changes permanently.",
				"You have %u files with changes you have not committed. The command below will delete those changes permanently.",
				d_uncommitted).printf(d_uncommitted);
		}

		set_warning_visible(true);
	}

	public uint uncommitted_changes
	{
		get { return d_uncommitted; }
	}

	public string reflog_caption
	{
		get { return d_reflog_caption.label; }
	}

	public string graph_caption
	{
		get { return d_graph_caption.visible ? d_graph_caption.label : ""; }
	}

	public bool warning_visible
	{
		get { return d_warning.visible; }
	}

	private void set_warning_visible(bool visible)
	{
		d_warning.visible = visible;
		d_banner.margin_top = visible ? 0 : BANNER_MARGIN;
	}

	private void refresh_copied()
	{
		var copied = d_command != "" && d_command == d_copied_command;

		if (d_copied == copied)
		{
			return;
		}

		d_copied = copied;

		var context = d_banner.get_style_context();

		if (copied)
		{
			context.add_class("copied");
		}
		else
		{
			context.remove_class("copied");
		}
	}

	private bool on_query_tooltip(int x, int y, bool keyboard, Gtk.Tooltip tooltip)
	{
		if (keyboard)
		{
			return false;
		}

		int bin_x;
		int bin_y;
		d_reflog_list.convert_widget_to_bin_window_coords(x, y, out bin_x, out bin_y);

		Gtk.TreePath? path;
		Gtk.TreeViewColumn? column;

		if (!d_reflog_list.get_path_at_pos(bin_x, bin_y, out path, out column, null, null))
		{
			return false;
		}

		string? text = null;

		if (column == d_reflog_list.get_column(0))
		{
			text = d_list.tooltip_at(path);
		}
		else if (column == d_list.date_column)
		{
			text = d_list.date_tooltip_at(path);
		}

		if (text == null)
		{
			return false;
		}

		tooltip.set_text(text);
		d_reflog_list.set_tooltip_cell(tooltip, path, column, null);

		return true;
	}
}

}
