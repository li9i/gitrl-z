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
 * The reflog activity (spec FR-120, FR-121).
 *
 * The one activity that gitrl-z has. It connects the refs panel, the reflog
 * list, the reset preview and the command banner.
 */
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

	/** The selected sidebar entry: "all", "stash", or a branch name. */
	private string d_view = "all";

	private Gee.List<string> d_branches;
	private Gee.Map<string, Ggit.OId> d_tips;
	private string? d_current_branch;

	/** The branch-to-colour map for the current tips (FR-153). */
	private Gee.Map<string, int> d_colours;

	/** The multi-branch reset plan the panes render (FR-148). */
	private ResetPlan d_plan;

	/**
	 * The ref labels of the preview graph, with the commit as the key (FR-150).
	 *
	 * gitg draws the pill of a branch at the commit that its ref points to. The
	 * preview must draw it at the position where a reset would move it. Thus
	 * this map replaces the lookup of gitg for the commits that a plan moves a
	 * branch from or to. An entry here has priority. Each other commit uses the
	 * real refs of the repository. The code builds this map again when the plan
	 * changes.
	 *
	 * This class owns the map, because the lanes cell holds its label list
	 * unowned. Thus the list must stay after the draw that reads it. The
	 * Repository of gitg owns the ref lists that it gives out in the same way.
	 */
	private HashTable<Ggit.OId, GLib.SList<Gitg.Ref>> d_preview_labels;

	/**
	 * The top visible row of the graph, to restore after a reload, or -1.
	 *
	 * A reload clears the commit model and fills it again, which moves the
	 * graph back to the top. The code keeps the row that was at the top before
	 * the reload, and scrolls back to it when the model is complete. Thus the
	 * view stays at its position, and a toggle of a row does not move the tree
	 * to its newest commits. This is a row index and not a pixel offset,
	 * because scroll_to_cell stays correct after the relayout that the tree
	 * view does at the end of a populate. A change to the adjustment does not.
	 */
	private int d_saved_top_row = -1;

	/** Says if the graph columns fit their content (FR-147-like). */
	private bool d_graph_fitted = false;

	/** A pending idle to select the row a keyboard move settled on, or 0. */
	private uint d_cursor_select_id = 0;

	/** The command that the banner shows now, for the copy button. */
	private string d_command = "";

	/**
	 * The last command on the clipboard, or "" if there is none this session.
	 *
	 * This is the command itself, and not a boolean on the widget. Thus the
	 * green state follows the content of the clipboard. If you move away from
	 * a copied row and come back, the state is green again, because that
	 * command is still the command that you would paste. The state clears only
	 * when the code copies a different command.
	 */
	private string d_copied_command = "";

	/** Says if the banner shows green now. */
	private bool d_copied = false;

	/**
	 * The files that a hard reset would destroy, or uint.MAX if unknown.
	 *
	 * The code reads this when it builds the preview, and does not monitor it
	 * continuously. The monitor reads only the git directory, and never the
	 * working tree (P-FR-25). A new status read at each keystroke in an editor
	 * would be slow and would give no benefit. The number must be correct at
	 * the time that a user copies a command.
	 */
	private uint d_uncommitted = 0;

	/**
	 * The default top margin of the command banner, which agrees with the
	 * template.
	 *
	 * The value is here because set_warning_visible() must restore it. A
	 * literal in two locations becomes different from the .ui with time.
	 */
	private const int BANNER_MARGIN = 8;

	/** Extra width for a fitted graph column, as the reflog list uses. */
	private const int GRAPH_COLUMN_PAD = 12;

	static construct
	{
		// GtkBuilder instantiates template children by GType name. A type
		// with no reference from C has no registration yet. The template then
		// fails with "Invalid object type 'GitgCommitListView'", and each
		// [GtkChild] returns null.
		//
		// gitg does not get this problem, because code that already uses
		// these types builds its .ui files. The standard correction is to
		// ensure the types at class-init time. This must occur here and not
		// in construct, because the template parse occurs during the instance
		// construction.
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

		// FR-130: follow the repository. FR-131: obey the preference. Thus if
		// the user disables the monitor, only F5 and the refresh entry stay.
		d_monitor = new Monitor();
		d_interface_settings.bind("enable-monitoring", d_monitor, "enabled",
		                          SettingsBindFlags.GET);
		d_monitor.changed.connect(reload);

		d_state_settings.bind("paned-sidebar-position", this, "position",
		                      SettingsBindFlags.DEFAULT);

		// Open the reflog list and the graph at the same height. The code does
		// not keep the divider position between sessions. The stored value was
		// an absolute pixel offset, and a value for one window height gives
		// unequal panes at a different height. A divider from a tall window
		// hid the bottom pane in a short window. Thus the panels open at the
		// half position each time, computed from the first real allocation.
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

		// FR-148: the method that puts a reflog row into the plan depends on
		// the view. In the HEAD view (d_view == "all") the top pane is a
		// single selection. A plain click or an arrow movement replaces the
		// plan with the new row. Only a Ctrl-click toggles a branch, to
		// collect several branches. In a branch view, a click toggles that one
		// branch, and an arrow movement keeps branches selected in other
		// views. Space and Enter toggle the focused row in the two views, and
		// are the keyboard method to add to the plan.
		d_reflog_list.button_press_event.connect(on_button_press);
		d_reflog_list.key_press_event.connect(on_key_press);

		// The plan is the selection here, and the row tint shows it (FR-151).
		// The selection of the tree view would draw a second, blue highlight
		// on that tint, and the two states would be unclear. Thus the code
		// disables it. The cursor still moves for the keyboard handlers above.
		d_reflog_list.get_selection().set_mode(Gtk.SelectionMode.NONE);

		// P-FR-15: the gutter carries a tooltip naming the operation kind.
		d_reflog_list.has_tooltip = true;
		d_reflog_list.query_tooltip.connect(on_query_tooltip);

		// FR-117: filter the list by substring, against the message and the
		// SHA. The caption count follows. Thus it stays correct when a search
		// decreases a view that a limit already decreased (FR-161).
		d_search_entry.search_changed.connect(() => {
			d_list.filter_text(d_search_entry.text);
			update_reflog_caption();
		});

		// FR-155/156/157: the two reflog limits, above the refs list. The code
		// sets the defaults here and not in the .ui (refer to the template
		// comment). It sets them before it connects the handlers, thus this
		// initial selection does not start them.
		d_time_combo.active = 0;
		d_entries_combo.active = 0;

		d_time_combo.changed.connect(on_time_window_changed);
		d_entries_combo.changed.connect(on_entries_count_changed);

		// The graph shows absolute timestamps, and the reflog list above shows
		// "2 days ago". The difference is intentional. The list is for a quick
		// look at the approximate time. The graph gives the exact time. The
		// model of gitg has the relative words only. The format occurs here,
		// and the code does not patch the vendored model. Thus the difference
		// stays in the code of gitrl-z.
		column_date.set_cell_data_func(renderer_date, (layout, cell, model, iter) => {
			var renderer = cell as Gtk.CellRendererText;

			Value value;
			model.get_value(iter, Gitg.CommitModelColumns.COMMIT, out value);

			var commit = value.get_object() as Gitg.Commit;

			renderer.text = commit != null ? iso_date(commit) : "";
		});

		// The graph shows the abbreviated hash, which agrees with the reflog
		// list above. Column 0 of the model is the full 40-character id, thus
		// the code makes it short here and does not bind it directly.
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

			// A new repository starts with an empty plan. The branches of the
			// previous repository have no meaning here. The graph columns
			// need a new fit.
			d_plan = new ResetPlan();
			d_graph_fitted = false;

			d_commit_model = d_repository != null
				? new Gitg.CommitModel(d_repository)
				: null;

			if (d_commit_model != null)
			{
				d_commit_list_view.model = d_commit_model;

				// After a reload fills the graph again: restore its scroll
				// offset, and fit its columns to the content the first time.
				d_commit_model.finished.connect(restore_scroll);
				d_commit_model.finished.connect(fit_graph_columns);
			}

			d_monitor.watch(d_repository != null
				? Repository.git_directory(d_repository)
				: null);

			reload();
		}
	}

	/** For the UI tests, which assert on the content of the list. */
	public ReflogList list
	{
		get { return d_list; }
	}

	/** The number of branches that the plan moves now, for the tests. */
	public int plan_size
	{
		get { return d_plan.size; }
	}

	/** The number of commits in the graph, for the scroll tests. */
	public uint graph_row_count()
	{
		return d_commit_model != null ? d_commit_model.size() : 0;
	}

	/** The top visible row of the graph, or -1, for the scroll tests. */
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

	/** Scrolls the graph to put `row` at the top, for the scroll tests. */
	public void scroll_graph_to_row(int row)
	{
		d_commit_list_view.scroll_to_cell(
			new Gtk.TreePath.from_indices(row), null, true, 0.0f, 0.0f);
	}

	/** The fitted width of a graph column, for the fit tests. */
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

	/** Says if the name of a refs-panel row is bold, for the tests. */
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

	/** For the UI tests: the tip set that the code gives to the gitg model. */
	public Ggit.OId[] included_tips { get; private set; }

	/** The command that the banner shows, or "" if it is hidden (FR-125). */
	public string command
	{
		get { return d_command; }
	}

	/** Says if the banner shows the copied (green) state. */
	public bool copied
	{
		get { return d_copied; }
	}

	/**
	 * Puts the shown command on the clipboard, as the copy button does.
	 *
	 * This is available so that the tests can use the copied state, and do not
	 * make an artificial click on the button.
	 */
	public void copy_command()
	{
		if (d_command == "")
		{
			return;
		}

		var clipboard = Gtk.Clipboard.get_default(get_display());

		if (clipboard != null)
		{
			clipboard.set_text(d_command, -1);
		}

		d_copied_command = d_command;
		refresh_copied();
	}

	/** The page that the preview shows: "graph" or "placeholder". */
	public string preview_state
	{
		owned get { return d_stack_preview.visible_child_name; }
	}

	/** The text of the preview placeholder, for the section 5 cases. */
	public string preview_placeholder
	{
		owned get { return d_preview_placeholder.label; }
	}

	/** The page that the reflog list shows: "list" or "placeholder". */
	public string list_state
	{
		owned get { return d_stack_reflog.visible_child_name; }
	}

	/** The selected sidebar entry. */
	public string view
	{
		get { return d_view; }
	}

	/**
	 * The selectable ref ids in the panel, in order (P-FR-7).
	 */
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

	/** The visible label of the sidebar row with id `id`, or "". For the tests. */
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

	/**
	 * Selects a sidebar entry by id. Returns false if the entry is absent.
	 */
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

	/**
	 * Sets the search filter (FR-117). Empty text clears it.
	 */
	public void search(string? text)
	{
		d_list.filter_text(text);
	}

	/**
	 * Shows or hides the search bar (FR-117). The search toggle in the header
	 * bar drives this method. When it hides the bar, it clears the filter.
	 * Thus a hidden search does not keep rows out of the list.
	 */
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

	/**
	 * Applies the selected time window to the list (FR-156).
	 */
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

	/**
	 * Applies the selected or typed entry count to the list (FR-157).
	 *
	 * The Entries combo has an entry. Thus `changed` occurs for a preset
	 * selection and for typed text. In the two conditions, get_active_text()
	 * returns the current text of the entry. parse_count changes that text
	 * into a limit, and 0 means All.
	 */
	private void on_entries_count_changed()
	{
		var text = d_entries_combo.get_active_text();

		d_list.set_count(ReflogFilter.parse_count(text != null ? text : ""));
		update_reflog_caption();
	}

	/** Selects a time window by its combo index (for the tests, FR-156). */
	public void choose_time_window(int index)
	{
		d_time_combo.active = index;
	}

	/**
	 * Sets the text of the Entries field, as typed text or a preset selection
	 * does (for the tests, FR-157).
	 */
	public void set_entries_text(string text)
	{
		var entry = d_entries_combo.get_child() as Gtk.Entry;

		if (entry != null)
		{
			entry.text = text;
		}
	}

	/**
	 * Reloads all data from the repository (FR-130).
	 *
	 * The selected ref stays if it still exists. If not, the code selects
	 * `all` (P-FR-9). The plan stays after a reload, by identity (FR-152). The
	 * code keeps entries whose branch and target commit still exist, and
	 * removes the others. It computes the colour map again, one time, for the
	 * new tips (FR-153).
	 */
	public void reload()
	{
		if (d_repository == null)
		{
			return;
		}

		d_branches = Repository.list_branches(d_repository);
		d_tips = Repository.branch_tips(d_repository);
		d_current_branch = Repository.current_branch(d_repository);
		d_colours = BranchColours.map(d_repository, d_tips);

		prune_plan();

		build_refs_list(d_view);
		load_reflog();
	}

	/**
	 * Removes plan entries that are no longer correct (FR-152).
	 *
	 * A deleted branch cannot move, and the graph cannot draw a target commit
	 * that the object database no longer holds. The two leave the plan. Each
	 * valid entry stays. Thus a plan from before a reload stays after it.
	 */
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

	/**
	 * Fills the refs panel: `all`, a Branches heading, the local branches, and
	 * `stash` if the repository has one (P-FR-7, P-FR-8).
	 */
	private void build_refs_list(string preferred)
	{
		foreach (var child in d_refs_list.get_children())
		{
			child.destroy();
		}

		// The label is HEAD, and not "all". This row reads logs/HEAD, which is
		// a different log from the log of a branch. The caption above the list
		// also says HEAD. Users read "all" as "all branches", and the row does
		// not show that. The internal id stays "all". Only the visible name
		// changes.
		add_ref_row("all", _("HEAD"), false);
		add_ref_row("", _("Branches"), true);

		foreach (var branch in d_branches)
		{
			// Mark the branch that HEAD is on. Thus the sidebar shows your
			// position. If HEAD is detached, the code marks no branch, because
			// d_current_branch is then null. The id stays the bare branch
			// name. Only the visible label gets the note.
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

		// A selection mode of BROWSE keeps one row selected. Thus an empty
		// selection cannot occur (P-FR-9). If the ref that was selected before
		// is absent, select `all`.
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

	/**
	 * Makes the name of a branch bold in the refs panel if it is in the plan.
	 *
	 * The left side then shows which branches a reset moves, and not only
	 * which reflog is open. This method restores the state from the plan after
	 * a rebuild, and a toggle updates it through the same path.
	 */
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

			// `all` and `stash` are not branches. Only a real branch can be in
			// the plan.
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
				// Limit the bold to the branch name. The label of the
				// checked-out branch has a " (checked out)" note, and that
				// note stays at normal weight. id.length is the byte offset of
				// the end of the name, and Pango attribute indices are byte
				// offsets. For a branch with no note, the label is the name
				// only, thus the same limit covers all of it.
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

	/**
	 * Loads the reflog of the selected ref (P-FR-10).
	 */
	private void load_reflog()
	{
		if (d_repository == null)
		{
			return;
		}

		var ref_name = d_view == "all" ? "HEAD" : d_view;
		var entries = Reflog.read(d_repository, ref_name);

		// The Branch column is in the `all` view only, where entries can
		// belong to different branches (P-FR-16). populate tints again from
		// the plan. Thus a planned row gets its mark again when the code shows
		// its branch. In a branch view, each row belongs to that branch, which
		// the tint needs.
		var view_branch = (d_view != "all" && d_view != "stash") ? d_view : null;
		d_list.populate(entries, d_current_branch, d_view == "all", d_colours, d_plan, view_branch);

		// This is after populate. Thus the "N of M" count agrees with the rows
		// that the code loaded with the current limits (FR-161).
		update_reflog_caption();

		// P-FR-14: a dim placeholder, and not an empty table.
		d_stack_reflog.visible_child_name = entries.size > 0 ? "list" : "placeholder";

		// The preview follows the full plan, which covers several branches.
		// Thus it stays when the shown reflog changes.
		update_preview();
	}

	/**
	 * Says which reflog the list shows.
	 *
	 * The name comes from the file that the code reads, and not from the
	 * sidebar row. The `all` view reads `logs/HEAD`, which is a different log
	 * from the log of a branch, and that difference is the purpose of the view
	 * (P-FR-16). The name "HEAD" is clear to a reader who knows git. The name
	 * "all branches" would be incorrect about the file that the code opened.
	 */
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

		// FR-161: if a limit is active and the reflog is not empty, show the
		// number of visible entries. The parentheses divide the count from the
		// name with no separator. The visible count already includes the
		// effect of a search.
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

	/** The method that puts a reflog row into the plan. */
	private enum PlanFold
	{
		/** Moves the branch into the plan or out of it (a click and Space in a
		 * branch view, a Ctrl-click and Space in the HEAD view). */
		TOGGLE,
		/** Sets the target of this branch, and keeps branches selected in other
		 * views (an arrow movement in a branch view). */
		SET_TARGET,
		/** Replaces the full plan with this one row (an arrow movement in the
		 * HEAD view, which keeps one selection and does not clear it). */
		SELECT_ONLY,
		/** Makes this row the only selection, or clears it if it is already
		 * that (a plain click in the HEAD view, thus a second click on the
		 * selected row deselects it). */
		SELECT_OR_DESELECT
	}

	/**
	 * The method that a plain click or a Ctrl-click uses, for the current view.
	 *
	 * The HEAD view keeps one selection. A plain click makes the row the only
	 * selection, or clears it if it is already that. Thus a second click
	 * deselects it. A Ctrl-click toggles, to collect several branches. A
	 * branch view holds one branch, thus its click always toggles that branch,
	 * and Ctrl gives nothing more there.
	 */
	private PlanFold click_fold(bool ctrl)
	{
		if (d_view != "all")
		{
			return PlanFold.TOGGLE;
		}

		return ctrl ? PlanFold.TOGGLE : PlanFold.SELECT_OR_DESELECT;
	}

	/**
	 * The method that an arrow movement uses for the new row, for the current
	 * view.
	 *
	 * The HEAD view keeps one selection, thus an arrow movement replaces the
	 * plan with the new row. A branch view keeps branches selected in other
	 * views, and moves only its own branch.
	 */
	private PlanFold arrow_fold()
	{
		return d_view == "all" ? PlanFold.SELECT_ONLY : PlanFold.SET_TARGET;
	}

	/**
	 * Puts the row at a view path into the plan (FR-148).
	 *
	 * The branch of a row that toggles goes into the plan. The code refreshes
	 * the marks and builds the preview again from the full plan. A stash row
	 * shows its own apply preview (FR-142). A row with no branch to move shows
	 * a note and does not change the plan.
	 *
	 * `fold` is the method. TOGGLE moves the branch into the plan or out of
	 * it, and a sequence of these builds a plan across branches. SET_TARGET
	 * sets the branch of the new row and keeps branches selected in other
	 * views. An arrival on a planned row keeps it and does not remove it.
	 * SELECT_ONLY replaces the full plan with this one row, which is the
	 * single selection that a plain click and an arrow movement make in the
	 * HEAD view. click_fold and arrow_fold decide which of these an input
	 * uses.
	 */
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

		// An operation in progress has priority. The code can plan nothing
		// until the rebase, merge, cherry-pick, revert or bisect stops or
		// aborts. Thus a click shows the way out.
		var operation = Repository.operation_in_progress(d_repository);

		if (operation != null)
		{
			show_operation_preview(operation);
			return;
		}

		// A stash is not a branch position (FR-142). Show the method to apply
		// it, and do not put it into a branch plan. A user wants their files
		// again from a stash.
		if (d_view == "stash")
		{
			show_stash_preview(entry);
			return;
		}

		// A detached HEAD has no branch to reset, thus a click on an entry
		// plans nothing. update_preview shows the way back (Option 3). This
		// does not change the apply of a stash, thus this test comes after the
		// stash test.
		if (d_current_branch == null)
		{
			update_preview();
			return;
		}

		var branch = ResetPreview.target_branch_for(d_view, d_list.branch_at(path), d_tips);

		if (branch == null)
		{
			// A row with no branch: a detached-HEAD period with no branch,
			// thus there is nothing to move and nothing to make again
			// (FR-148). A row that names a deleted branch has a branch. It
			// goes into the plan below, and the command makes it again
			// (FR-166).
			show_preview_placeholder(_("No branch to move for this entry"));
			return;
		}

		// P-FR-24: the graph cannot draw a commit whose object is no longer in
		// the database. Thus the code cannot plan it.
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
				// A click on the row that is already the only selection clears
				// it. Each other row becomes the new only selection.
				d_plan.set_only_or_clear(branch, entry.new_id);
				break;
		}

		d_list.refresh_plan_marks();
		refresh_ref_weights();
		update_preview();
	}

	/**
	 * Toggles the entry at a store index (FR-148).
	 *
	 * This is for the tests. It does what a toggle does: a click in a branch
	 * view, or a Ctrl-click in the HEAD view. Returns false if the index is
	 * out of range, or if the search filter hides the entry.
	 */
	public bool toggle_entry(int index)
	{
		return fold_entry(index, PlanFold.TOGGLE);
	}

	/**
	 * Selects the entry at a store index (FR-148).
	 *
	 * This is for the tests. It does what a keyboard arrow movement does. In
	 * the HEAD view, it is one selection that replaces the plan. In a branch
	 * view, the branch of the new row stays with the other branches. Returns
	 * false if the index is out of range, or if the search filter hides the
	 * entry.
	 */
	public bool select_entry(int index)
	{
		return fold_entry(index, arrow_fold());
	}

	/**
	 * Clicks the entry at a store index (FR-148).
	 *
	 * This is for the tests. It does what a plain primary click does. In the
	 * HEAD view it makes the row the only selection, or clears it if it is
	 * already that. In a branch view it toggles that branch. Returns false if
	 * the index is out of range, or if the search filter hides the entry.
	 */
	public bool click_entry(int index)
	{
		return fold_entry(index, click_fold(false));
	}

	/**
	 * Puts the entry at a store index into the plan, for the three test hooks.
	 *
	 * Returns false if the index is out of range, or if the search filter
	 * hides the entry. Thus a test can separate an ignored input from an input
	 * that the code processed.
	 */
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
		    || event.button != Gdk.BUTTON_PRIMARY)
		{
			return false;
		}

		// A tree-row button event comes on the bin window. Thus its
		// coordinates are already relative to the bin window, and
		// get_path_at_pos takes them with no change. A conversion from widget
		// coordinates here would subtract the header height a second time, and
		// would give a row that is too high. The tooltip handler must do that
		// conversion, because query-tooltip gives widget coordinates.
		Gtk.TreePath? path;

		if (!d_reflog_list.get_path_at_pos((int)event.x, (int)event.y, out path, null, null, null))
		{
			return false;
		}

		var ctrl = (event.state & Gdk.ModifierType.CONTROL_MASK) != 0;
		plan_path(path, click_fold(ctrl));

		// The row still takes the keyboard cursor.
		return false;
	}

	private bool on_key_press(Gdk.EventKey event)
	{
		if (event.keyval == Gdk.Key.space
		    || event.keyval == Gdk.Key.Return
		    || event.keyval == Gdk.Key.KP_Enter)
		{
			// This is the cursor, and not the selection. The selection is off
			// (refer to construct), but the focus cursor still moves with the
			// arrow keys.
			Gtk.TreePath? path;
			d_reflog_list.get_cursor(out path, null);

			if (path == null)
			{
				return false;
			}

			plan_path(path, PlanFold.TOGGLE);

			// Consume the event, thus Space does not also scroll the list.
			return true;
		}

		if (is_vertical_nav_key(event.keyval))
		{
			// An arrow movement selects the new row, as a click does. Thus the
			// preview follows the cursor. The tree view moves its own cursor
			// for these keys. Permit that (return false), then read the new
			// position on the next idle, after the move is complete.
			schedule_cursor_select();
			return false;
		}

		return false;
	}

	/** Says if `keyval` is a key that moves the cursor of the tree view. */
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

	/**
	 * Selects the row that the cursor moves to after a keyboard move.
	 *
	 * This work is in an idle, because the tree view moves its cursor in its
	 * own key handler, which runs after this one. The idle reads the final
	 * cursor position. `d_cursor_select_id` groups the calls. Thus a held
	 * arrow key, which repeats, schedules the work one time for each final
	 * position, and does not add one idle for each repeat.
	 */
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

	/**
	 * Takes control of the lane cell of the graph, so that its labels come from
	 * the preview.
	 *
	 * The data func of gitg fills the lane cell from the real refs of the
	 * repository. A new data func here keeps each operation of gitg (the
	 * lanes, the commit and its successor) and changes only the source of the
	 * labels. Thus the pill of a planned branch can be at the commit that a
	 * reset would move it to. The code calls this one time, because the column
	 * and its cell stay for the full life of the widget.
	 */
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

	/**
	 * Fills the lane cell for a row, with the labels of the preview (FR-150).
	 *
	 * This is a copy of the lanes data func of gitg, with one difference: the
	 * source of the labels. The commit and its successor set the lanes as gitg
	 * sets them. The labels come from labels_for_preview(). Thus a moved
	 * branch is at the position where a reset would put it.
	 */
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

	/**
	 * The labels for a commit: the override of the plan, or the real refs.
	 *
	 * An id that the plan changes, because a branch moves from it or to it,
	 * has an entry in d_preview_labels. That entry has priority, also when it
	 * is the empty list. The empty list occurs for a commit where a branch was
	 * the only ref, and that branch moved away. Each other commit uses the
	 * real-ref lookup of gitg. Thus tags, remotes and branches that do not
	 * move do not change.
	 */
	private unowned GLib.SList<Gitg.Ref> labels_for_preview(Ggit.OId id)
	{
		if (d_preview_labels != null && d_preview_labels.contains(id))
		{
			return d_preview_labels.lookup(id);
		}

		return d_repository != null ? d_repository.refs_for_id(id) : null;
	}

	/**
	 * Builds the label override again from the current plan (FR-150).
	 *
	 * For each planned branch that moves visibly, the code takes its pill from
	 * the commit that it is on, and puts it on the commit that a reset would
	 * move it to. The other refs on those commits stay. The code does this
	 * before each reload. Thus the first draw of the graph already has the
	 * labels at their planned positions.
	 */
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

			// The command makes a branch again if that branch is not in the
			// current tips (FR-166). It has no live pill to move, thus the
			// code draws a synthetic pill at the commit that
			// `git branch <name> <sha>` would use.
			if (from == null)
			{
				add_label(target, new SyntheticBranchRef(branch));
				continue;
			}

			// A move to the current position of the branch changes nothing.
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

	/** The ref object of the branch at its current position, or null. */
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

	/** Replaces the labels of `id` with its current labels, less `exclude`. */
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

	/** Replaces the labels of `id` with its current labels, plus `add`. */
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

	/** The labels of `id` now: the override if there is one, or the real refs. */
	private unowned GLib.SList<Gitg.Ref> current_preview_labels(Ggit.OId id)
	{
		if (d_preview_labels.contains(id))
		{
			return d_preview_labels.lookup(id);
		}

		return d_repository.refs_for_id(id);
	}

	/**
	 * The ref short names that the preview draws at a commit (for the tests,
	 * FR-150).
	 *
	 * These are the names of the pills that gitg would draw on the row for
	 * `id` with the current plan. Thus a test can assert that a moved branch
	 * is at its target and not at its previous tip, and does not read pixels.
	 */
	public string[] preview_labels_for(Ggit.OId id)
	{
		string[] names = {};

		foreach (unowned Gitg.Ref r in labels_for_preview(id))
		{
			names += r.parsed_name.shortname;
		}

		return names;
	}

	/**
	 * Draws the graph that the plan would give, or the current repository.
	 *
	 * The tip set keeps the full current tree and adds each planned target
	 * (FR-150). Thus the commits that a reset would abandon stay visible. With
	 * an empty plan, the tip set is the real tips, which is the current
	 * repository tree. rebuild_preview_labels() moves the label of a planned
	 * branch onto its target. With an empty plan there is no command to run,
	 * thus there is no banner and no warning, and the caption says that this
	 * is the present state and not a preview. After the user toggles entries
	 * into the plan, the command (FR-149) and its caption appear.
	 */
	private void update_preview()
	{
		if (d_repository == null || d_commit_model == null)
		{
			return;
		}

		// A repository with an operation in progress is first. A rebase,
		// merge, cherry-pick, revert or bisect must stop or abort before a
		// reset or a checkout has any meaning. A rebase and a bisect detach
		// HEAD. Thus this test must come before the detached test below. If
		// not, the code would offer `git checkout -` during a rebase.
		var operation = Repository.operation_in_progress(d_repository);

		if (operation != null)
		{
			show_operation_preview(operation);
			return;
		}

		// A detached HEAD shows the way back to a branch, and not a tree to
		// reset (Option 3). The stash view is an exception, because an apply
		// of a stash operates with HEAD on a branch and with HEAD detached.
		if (d_current_branch == null && d_view != "stash")
		{
			show_detached_preview();
			return;
		}

		var tips = ResetPreview.preview_tips(d_tips, d_plan);

		// There are no tips to draw, for example with an unborn HEAD. There is
		// nothing to show.
		if (tips.length == 0)
		{
			show_preview_placeholder(_("Select an entry"));
			return;
		}

		included_tips = tips;

		// Move the label of each planned branch onto its target before the
		// reload. Thus the first draw of the graph already shows the pills at
		// the positions where a reset would put them (FR-150).
		rebuild_preview_labels();

		// Keep the scroll position of the graph across the reload (refer to
		// d_saved_top_row). The code saves it only when no save is already
		// pending. Thus a group of clicks keeps the row from before the first
		// click, and not the post-clear top row of the clicks between.
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
			// The current repository: the graph over the real tips, with no
			// planned reset. There is no command to run, thus the banner and
			// the warning stay hidden. The caption says that this is the
			// present state.
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

	/**
	 * The caption above the graph (FR-146, changed for the plan).
	 *
	 * One planned branch that still exists keeps the words that name it as
	 * moved. With two or more branches, the code removes that clause, because
	 * there is no single branch to name. A single branch that the command
	 * makes again, and that is not in the tips, does not move. Thus it also
	 * takes the plain caption (FR-166). The caption comes from the same plan
	 * as the command, thus the caption and the command always agree.
	 */
	private string graph_caption_text()
	{
		var branches = d_plan.branches();

		if (branches.size == 1 && d_tips.has_key(branches[0]))
		{
			return _("Repository state after execution of the command above, with %s moved").printf(branches[0]);
		}

		return _("Repository state after execution of the command above");
	}

	/**
	 * Scrolls the graph back to its saved top row after a reload.
	 *
	 * scroll_to_cell keeps the request and applies it after the tree view
	 * validates the new rows. This is why it operates correctly where a direct
	 * change to the adjustment does not. If the row no longer exists, because
	 * the graph is shorter, the code uses the last row. This needs hidden
	 * headers on the graph. With visible headers, scroll_to_cell does not move
	 * a fixed-height tree view, which is one cause for the hidden headers.
	 */
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

	/**
	 * Fits the graph columns to their content one time, at the first load.
	 *
	 * The reflog list above fits its columns at open (FR-147). This method
	 * does the same for the graph, where nothing else fits the columns to the
	 * content. Author, SHA and date fit their content. The subject column
	 * continues to expand and fill, and the code does not measure the graph
	 * for it. This occurs one time for each repository, and not at each
	 * reload. Thus the columns do not move while the user builds a plan.
	 *
	 * The user cannot resize the columns. The headers of the graph are hidden,
	 * to keep the appearance of gitg and to keep the scroll_to_cell restore
	 * correct. With no headers, GTK gives no resize handles.
	 */
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

		// A limited sample. It is sufficient for the range of author-name
		// widths, and it does not measure thousands of rows. SHA and date have
		// fixed formats, thus any row gives their width.
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

			// The name only. The column binds to AUTHOR_NAME (model column 4),
			// and not to "name <email>". A measurement of the longer form made
			// the column much wider than its content. That left a space
			// between the name and the SHA, and decreased the width of the
			// message.
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

	/**
	 * The hash of a commit, abbreviated to seven characters. The reflog list
	 * shows it in this form (ReflogEntry.abbreviated_id), and --abbrev-commit
	 * of git gives the same form.
	 */
	private static string abbreviated_sha(Gitg.Commit commit)
	{
		var sha = commit.get_id().to_string();

		return sha.length > 7 ? sha.substring(0, 7) : sha;
	}

	/**
	 * The author date of a commit, in the --date=iso form of git.
	 *
	 * "2026-07-20 10:00:00 +0200" is the local time with its offset, as git
	 * prints it. A normalised UTC time would not agree with the time that the
	 * user sees from git.
	 */
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

	/**
	 * The action for a stashed change (item 6).
	 *
	 * A stash entry is a commit. Thus the reset code would offer to move a
	 * branch to it, and a user almost never wants that. It would put the
	 * stashed content on the branch as committed history. That is an unusual
	 * result for a user who wants some edits again.
	 *
	 * The command is `apply` and not `pop`. apply keeps the stash. Thus if the
	 * result is not correct, the stash is still available for a second
	 * attempt. `pop` removes the stash after a success, which is a worse
	 * default for a user who is already lost.
	 *
	 * There is no graph, because an apply of a stash moves no ref. The graph
	 * would be the same as the current graph, and an unchanged graph beside a
	 * command means that the command does nothing.
	 */
	private void show_stash_preview(ReflogEntry entry)
	{
		show_command_note("git stash apply %s".printf(entry.selector),
			_("Applying a stash changes your files, not your branches, so there is no new history to show."));
	}

	/**
	 * The action when HEAD is detached.
	 *
	 * With a detached HEAD there is no branch to reset. Thus reset planning is
	 * off until you return to a branch. A `git branch -f` would move a ref and
	 * would leave HEAD detached, which looks like no change. A move of the
	 * branch that you are on is not possible, because there is no such branch.
	 * Thus the preview offers only the way back, `git checkout -`, and gives
	 * the cause.
	 */
	private void show_detached_preview()
	{
		show_command_note("git checkout -",
			_("HEAD is detached, so you are not on a branch and there is nothing to reset. Run the command above to return to the branch you were on, then plan a reset from there."));
	}

	/** The command that ends an in-progress operation (IC-164 tokens). */
	private static string operation_command(string operation)
	{
		// Each operation stops with `--abort`, except bisect. Bisect stops
		// with `git bisect reset`.
		return operation == "bisect" ? "git bisect reset"
		                             : "git %s --abort".printf(operation);
	}

	/**
	 * The action when a git operation is in progress (FR-165).
	 *
	 * A rebase, merge, cherry-pick, revert or bisect must stop or abort before
	 * a reset or a checkout has any meaning. Thus reset planning is off, and
	 * the preview offers the one command that undoes the operation. A rebase
	 * and a bisect leave HEAD detached. This is why the code comes here before
	 * the detached-HEAD condition, and does not offer `git checkout -` during
	 * a rebase.
	 */
	private void show_operation_preview(string operation)
	{
		show_command_note(operation_command(operation),
			_("A %s is in progress. Finish it, or run the command above to abort and undo it. Reset planning is off until you do.").printf(operation));
	}

	/**
	 * Shows a command that the user can copy, and a note, with no graph.
	 *
	 * The stash preview and the detached-HEAD preview both need this form: a
	 * command that moves no ref, thus the graph has nothing to show, and a
	 * note that gives the cause. The banner holds the command. The warning and
	 * the graph caption become hidden, and the code clears any old tips and
	 * labels. Thus the pane does not continue to show the graph of the
	 * previous reset beside the command.
	 */
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

	/**
	 * Warns when the shown command would destroy uncommitted work.
	 *
	 * This is the one condition that gitrl-z warns about, because it is the
	 * one result that the reflog cannot undo. A commit that a reset drops
	 * stays in the reflog, and gitrl-z can return it. A file that you edited
	 * and did not commit is permanently lost.
	 */
	private void update_uncommitted_warning()
	{
		if (d_repository == null || d_command == "")
		{
			set_warning_visible(false);
			return;
		}

		// Only a hard reset destroys the working tree. A command that points a
		// ref to a different commit does not change the working tree. A
		// warning for those commands would teach users to ignore the warning.
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

	/** The files that a hard reset would destroy, for the tests. */
	public uint uncommitted_changes
	{
		get { return d_uncommitted; }
	}

	/** The caption above the reflog list, for the tests. */
	public string reflog_caption
	{
		get { return d_reflog_caption.label; }
	}

	/** The caption above the preview graph, or "" if hidden, for the tests. */
	public string graph_caption
	{
		get { return d_graph_caption.visible ? d_graph_caption.label : ""; }
	}

	/** Says if the uncommitted-changes warning is visible. */
	public bool warning_visible
	{
		get { return d_warning.visible; }
	}

	/**
	 * Shows or hides the warning, and keeps it against the command banner.
	 *
	 * The two are one statement: the data that the command would destroy, and
	 * the command itself. Thus when the two are visible, they touch and read
	 * as one block. The bottom margin of the warning is zero in the template.
	 * The top margin of the banner must become zero, and only while the
	 * warning is visible. With no warning, the banner needs that margin again.
	 * If not, the banner touches the top of the preview pane.
	 */
	private void set_warning_visible(bool visible)
	{
		d_warning.visible = visible;
		d_banner.margin_top = visible ? 0 : BANNER_MARGIN;
	}

	/**
	 * Makes the banner green only when it shows the copied command.
	 *
	 * Green means "this is the command that you would paste now". That is a
	 * statement about the clipboard. Thus the code takes the state from the
	 * content of the clipboard, and does not set it when the user presses the
	 * button. If you select a different entry, the banner becomes amber. If
	 * you return, it is green again. If you copy a different command, the
	 * previous command is no longer green in any location.
	 */
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

		// Only the gutter, which is the first column, has a tooltip.
		if (column != d_reflog_list.get_column(0))
		{
			return false;
		}

		var text = d_list.tooltip_at(path);

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

// ex:set ts=4 noet:
