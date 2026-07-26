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
 * The one activity gitrl-z has: refs panel, reflog list, reset preview and
 * the command banner, wired together.
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
	 * The preview graph's ref labels, keyed by commit (FR-150).
	 *
	 * gitg draws a branch's pill at the commit its ref really points to. The
	 * preview needs it drawn where a reset would move it, so this map overrides
	 * gitg's lookup for the commits a plan moves a branch off or onto: an entry
	 * here wins, any other commit falls back to the repository's real refs. It
	 * is rebuilt whenever the plan changes.
	 *
	 * Owned here because the lanes cell holds its label list unowned, so the
	 * list must outlive the draw that reads it. This mirrors how gitg's own
	 * Repository owns the ref lists it hands out.
	 */
	private HashTable<Ggit.OId, GLib.SList<Gitg.Ref>> d_preview_labels;

	/**
	 * The graph's top visible row to restore after a reload, or -1 when none.
	 *
	 * Reloading the commit model clears and repopulates it, which sends the
	 * graph back to the top. Remembering which row was at the top before a
	 * reload and scrolling back to it when the model finishes keeps the view
	 * where it was, so toggling a row does not jerk the tree to its newest
	 * commits. A row index rather than a pixel offset, because scroll_to_cell
	 * survives the tree view's post-populate relayout where poking the
	 * adjustment does not.
	 */
	private int d_saved_top_row = -1;

	/** Whether the graph's columns have been fitted to content (FR-147-like). */
	private bool d_graph_fitted = false;

	/** A pending idle to select the row a keyboard move settled on, or 0. */
	private uint d_cursor_select_id = 0;

	/** The command the banner currently shows, for the copy button. */
	private string d_command = "";

	/**
	 * The command last put on the clipboard, or "" if none this session.
	 *
	 * Tracked as the command rather than as a boolean on the widget, so the
	 * green state follows what the clipboard actually holds: navigate away
	 * from a copied row and back, and it is green again, because it is still
	 * the thing you would paste. It clears only when a different command is
	 * copied.
	 */
	private string d_copied_command = "";

	/** Whether the banner is currently showing green. */
	private bool d_copied = false;

	/**
	 * Files a hard reset would destroy, or uint.MAX when unknown.
	 *
	 * Read when the preview is built rather than watched continuously: the
	 * monitor deliberately watches only the git directory, never the working
	 * tree (P-FR-25), and re-reading status on every keystroke in an editor
	 * would be both wasteful and pointless. What matters is that the number
	 * is current at the moment someone is about to copy a command.
	 */
	private uint d_uncommitted = 0;

	/**
	 * The command banner's resting top margin, matching the template.
	 *
	 * Held here because set_warning_visible() has to restore it, and a literal
	 * in two places is a literal that will drift out of step with the .ui.
	 */
	private const int BANNER_MARGIN = 8;

	/** Slack added to a fitted graph column, matching the reflog list's. */
	private const int GRAPH_COLUMN_PAD = 12;

	static construct
	{
		// GtkBuilder instantiates template children by GType name, and a
		// type that has never been referenced from C is not registered yet —
		// the template then fails with "Invalid object type
		// 'GitgCommitListView'" and every [GtkChild] comes back null.
		//
		// gitg does not hit this because its own .ui files are built by code
		// that already touches these types. Ensuring them at class-init time
		// is the standard fix, and it must happen here rather than in
		// construct: the template is parsed during instance construction.
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

		// FR-130: follow the repository. FR-131: honour the preference, so
		// turning monitoring off leaves only F5 and the refresh entry.
		d_monitor = new Monitor();
		d_interface_settings.bind("enable-monitoring", d_monitor, "enabled",
		                          SettingsBindFlags.GET);
		d_monitor.changed.connect(reload);

		d_state_settings.bind("paned-sidebar-position", this, "position",
		                      SettingsBindFlags.DEFAULT);

		// Open the reflog list and the graph at the same height. The divider is
		// deliberately not remembered across sessions: it was stored as an
		// absolute pixel offset, and a value chosen for one window height leaves
		// the panes lopsided at another (a divider from a tall window buried the
		// bottom pane in a short one). So the panels open halfway every time
		// instead, computed from the first real allocation.
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

		// FR-148: how a reflog row folds into the plan depends on the view. In
		// the HEAD view (d_view == "all") the top pane is a single selection: a
		// plain click or arrow travel replaces the plan with the landed row, and
		// only a Ctrl-click toggles a branch so several branches can be gathered.
		// In a branch view a click toggles that one branch and arrow travel
		// keeps branches chosen in other views. Space and Enter toggle the
		// focused row in either view, the keyboard way to add to the plan.
		d_reflog_list.button_press_event.connect(on_button_press);
		d_reflog_list.key_press_event.connect(on_key_press);

		// The plan is the selection here, shown as the row tint (FR-151).
		// The tree view's own selection would paint a second, blue highlight on
		// top of that tint and confuse the two states, so it is turned off; the
		// cursor still moves for the keyboard handlers above.
		d_reflog_list.get_selection().set_mode(Gtk.SelectionMode.NONE);

		// P-FR-15: the gutter carries a tooltip naming the operation kind.
		d_reflog_list.has_tooltip = true;
		d_reflog_list.query_tooltip.connect(on_query_tooltip);

		// FR-117: filter the list by substring against message and SHA. The
		// caption count follows, so it stays truthful when a search narrows a
		// view that a limit is already capping (FR-161).
		d_search_entry.search_changed.connect(() => {
			d_list.filter_text(d_search_entry.text);
			update_reflog_caption();
		});

		// FR-155/156/157: the two reflog limits, above the refs list. The
		// defaults are set here rather than in the .ui (see the template
		// comment) and before the handlers are connected, so this initial
		// selection does not fire them.
		d_time_combo.active = 0;
		d_entries_combo.active = 0;

		d_time_combo.changed.connect(on_time_window_changed);
		d_entries_combo.changed.connect(on_entries_count_changed);

		// The graph shows absolute timestamps, where the reflog list above
		// shows "2 days ago". Deliberately different: the list is for
		// scanning ("roughly when?"), the graph for pinning something down
		// ("exactly when?"), and gitg's model only offers the relative
		// wording. Formatting here rather than patching the vendored model
		// keeps the divergence in gitrl-z's own code.
		column_date.set_cell_data_func(renderer_date, (layout, cell, model, iter) => {
			var renderer = cell as Gtk.CellRendererText;

			Value value;
			model.get_value(iter, Gitg.CommitModelColumns.COMMIT, out value);

			var commit = value.get_object() as Gitg.Commit;

			renderer.text = commit != null ? iso_date(commit) : "";
		});

		// The graph shows the abbreviated hash, matching the reflog list above:
		// the model's column 0 is the full 40-character id, so it is shortened
		// here rather than bound directly.
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

			// A new repository starts with an empty plan; the old one's
			// branches mean nothing here. Its graph columns want fitting afresh.
			d_plan = new ResetPlan();
			d_graph_fitted = false;

			d_commit_model = d_repository != null
				? new Gitg.CommitModel(d_repository)
				: null;

			if (d_commit_model != null)
			{
				d_commit_list_view.model = d_commit_model;

				// Once a reload has repopulated the graph: restore its scroll
				// offset, and fit its columns to content the first time.
				d_commit_model.finished.connect(restore_scroll);
				d_commit_model.finished.connect(fit_graph_columns);
			}

			d_monitor.watch(d_repository != null
				? Repository.git_directory(d_repository)
				: null);

			reload();
		}
	}

	/** Exposed for the UI tests, which assert on what the list holds. */
	public ReflogList list
	{
		get { return d_list; }
	}

	/** How many branches the plan currently moves, for the tests. */
	public int plan_size
	{
		get { return d_plan.size; }
	}

	/** How many commits the graph holds, for the scroll tests. */
	public uint graph_row_count()
	{
		return d_commit_model != null ? d_commit_model.size() : 0;
	}

	/** The graph's top visible row, or -1, for the scroll tests. */
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

	/** Scroll the graph so `row` sits at the top, for the scroll tests. */
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

	/** Whether a refs-panel row's name is shown bold, for the tests. */
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

	/** Exposed for the UI tests: the tip set handed to gitg's model. */
	public Ggit.OId[] included_tips { get; private set; }

	/** The command the banner shows, or "" when it is hidden (FR-125). */
	public string command
	{
		get { return d_command; }
	}

	/** Whether the banner is showing the copied (green) state. */
	public bool copied
	{
		get { return d_copied; }
	}

	/**
	 * Put the shown command on the clipboard, as the copy button does.
	 *
	 * Exposed so the tests can exercise the copied state without synthesising
	 * a click on the button.
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

	/** Which page the preview shows: "graph" or "placeholder". */
	public string preview_state
	{
		owned get { return d_stack_preview.visible_child_name; }
	}

	/** The text of the preview placeholder, for the section 5 cases. */
	public string preview_placeholder
	{
		owned get { return d_preview_placeholder.label; }
	}

	/** Which page the reflog list shows: "list" or "placeholder". */
	public string list_state
	{
		owned get { return d_stack_reflog.visible_child_name; }
	}

	/** The currently selected sidebar entry. */
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

	/** The visible label of the sidebar row with id `id`, or "" — for the tests. */
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
	 * Select a sidebar entry by id. Returns false when it is not present.
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
	 * Set the search filter (FR-117). Empty text clears it.
	 */
	public void search(string? text)
	{
		d_list.filter_text(text);
	}

	/**
	 * Show or hide the search bar (FR-117), driven by the header bar's search
	 * toggle. Hiding it clears the filter, so a hidden search never silently
	 * keeps rows filtered out.
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
	 * Apply the chosen time window to the list (FR-156).
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
	 * Apply the chosen or typed entry count to the list (FR-157).
	 *
	 * The Entries combo has an entry, so `changed` fires for a preset pick and
	 * for typing alike; get_active_text() returns the entry's current text in
	 * both cases, which parse_count turns into a cap, 0 meaning All.
	 */
	private void on_entries_count_changed()
	{
		var text = d_entries_combo.get_active_text();

		d_list.set_count(ReflogFilter.parse_count(text != null ? text : ""));
		update_reflog_caption();
	}

	/** Choose a time window by its combo index (test-facing, FR-156). */
	public void choose_time_window(int index)
	{
		d_time_combo.active = index;
	}

	/**
	 * Set the Entries field's text, as typing or picking a preset would
	 * (test-facing, FR-157).
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
	 * Reload everything from the repository (FR-130).
	 *
	 * The selected ref is preserved when it still exists, otherwise it falls
	 * back to `all` (P-FR-9). The plan persists across a reload by identity
	 * (FR-152): entries whose branch and target commit still exist are kept,
	 * the rest dropped. The colour map is recomputed once for the new tips
	 * (FR-153).
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
	 * Drop plan entries that no longer make sense (FR-152).
	 *
	 * A branch that has been deleted cannot be moved, and a target commit that
	 * has been pruned cannot be drawn; both leave the plan. Everything still
	 * valid stays, so a plan built before a reload survives it.
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
	 * Fill the refs panel: `all`, a Branches heading, the local branches, and
	 * `stash` when the repository has one (P-FR-7, P-FR-8).
	 */
	private void build_refs_list(string preferred)
	{
		foreach (var child in d_refs_list.get_children())
		{
			child.destroy();
		}

		// Labelled HEAD, not "all": this row reads logs/HEAD, a different log
		// from any branch's, and the caption over the list says HEAD too. "all"
		// read as "all branches", which is not what it shows. The internal id
		// stays "all"; only the visible name changes.
		add_ref_row("all", _("HEAD"), false);
		add_ref_row("", _("Branches"), true);

		foreach (var branch in d_branches)
		{
			// Mark the branch HEAD is on, so the sidebar says where you are
			// sitting. Nothing is marked when HEAD is detached (d_current_branch
			// is null then). The id stays the bare branch name; only the visible
			// label gains the note.
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

		// A selection mode of BROWSE keeps exactly one row selected, so an
		// empty selection cannot arise (P-FR-9). If the previously selected
		// ref has gone, fall back to `all`.
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
	 * Bold a branch's name in the refs panel when it is in the plan.
	 *
	 * The left side then says at a glance which branches a reset is planned
	 * for, not just which reflog is open. Rebuilt state is restored from the
	 * plan here, and a toggle updates it through the same path.
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

			// `all` and `stash` are not branches; only a real branch can be in
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
				// Bound the bold to the branch name only. The checked-out
				// branch's label carries a " (checked out)" note, and that note
				// stays normal weight: id.length is the byte offset where the
				// name ends, and Pango attribute indices are byte offsets. For a
				// branch without the note the label is just the name, so the same
				// bound covers all of it.
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
	 * Load the reflog of the selected ref (P-FR-10).
	 */
	private void load_reflog()
	{
		if (d_repository == null)
		{
			return;
		}

		var ref_name = d_view == "all" ? "HEAD" : d_view;
		var entries = Reflog.read(d_repository, ref_name);

		// The Branch column exists only in the `all` view, where entries can
		// belong to different branches (P-FR-16). populate re-tints from the
		// plan, so a planned row is marked again when its branch is shown. In a
		// branch view every row belongs to that branch, which the tint needs.
		var view_branch = (d_view != "all" && d_view != "stash") ? d_view : null;
		d_list.populate(entries, d_current_branch, d_view == "all", d_colours, d_plan, view_branch);

		// After populate, so the "N of M" count reflects the rows just loaded
		// under the current limits (FR-161).
		update_reflog_caption();

		// P-FR-14: a dimmed placeholder rather than an empty table.
		d_stack_reflog.visible_child_name = entries.size > 0 ? "list" : "placeholder";

		// The preview follows the whole plan, which spans branches, so it
		// persists when the shown reflog changes.
		update_preview();
	}

	/**
	 * Say which reflog the list is showing.
	 *
	 * Named for what is actually read, not for the sidebar row: the `all`
	 * view reads `logs/HEAD`, which is a different log from any branch's and
	 * is the whole reason that view exists (P-FR-16). Calling it "HEAD" here
	 * costs nothing with an audience that knows git, and saying "all
	 * branches" would be a plain lie about which file was opened.
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

		// FR-161: when a limit is active and the reflog is not empty, show how
		// many of its entries are visible. The parentheses set the count off
		// from the name without a separator; search, if any, is already
		// reflected in the visible count.
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

	/** How a reflog row folds into the plan. */
	private enum PlanFold
	{
		/** Flip the branch into or out of the plan (click and Space in a branch
		 * view, Ctrl-click and Space in the HEAD view). */
		TOGGLE,
		/** Set this branch's target, keeping branches chosen in other views
		 * (arrow travel in a branch view). */
		SET_TARGET,
		/** Replace the whole plan with this one row (arrow travel in the HEAD
		 * view, which tracks a single selection and never clears it). */
		SELECT_ONLY,
		/** Make this row the only selection, or clear it when it already is
		 * (a plain click in the HEAD view, so clicking the selected row again
		 * deselects it). */
		SELECT_OR_DESELECT
	}

	/**
	 * How a plain or Ctrl-click folds a row in, given the current view.
	 *
	 * The HEAD view is a single selection: a plain click makes the row the sole
	 * selection, or clears it when it already is, so clicking it again
	 * deselects. A Ctrl-click toggles so several branches can be gathered. A
	 * branch view holds one branch, so its click has always toggled that branch
	 * in or out and Ctrl adds nothing there.
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
	 * How arrow travel folds the landed row in, given the current view.
	 *
	 * The HEAD view tracks a single selection, so arrow travel replaces the
	 * plan with the landed row. A branch view keeps branches chosen in other
	 * views and only moves its own.
	 */
	private PlanFold arrow_fold()
	{
		return d_view == "all" ? PlanFold.SELECT_ONLY : PlanFold.SET_TARGET;
	}

	/**
	 * Fold the row at a view path into the plan (FR-148).
	 *
	 * A togglable row's branch enters the plan, the marks are refreshed and the
	 * preview rebuilt from the whole plan. A stash row shows its own apply
	 * preview instead (FR-142); a row with no branch to move shows a note and
	 * leaves the plan alone.
	 *
	 * `fold` is how the row is folded in. TOGGLE flips the branch into or out of
	 * the plan and a run of them builds a plan across branches. SET_TARGET sets
	 * the landed row's branch while keeping branches chosen in other views, and
	 * landing on an already-planned row keeps it rather than removing it.
	 * SELECT_ONLY replaces the whole plan with this one row, the single
	 * selection the HEAD view's plain click and arrow travel make. Which of
	 * these an input maps to is decided by click_fold and arrow_fold.
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

		// Mid-operation takes precedence over everything: nothing here can be
		// planned until the rebase, merge, cherry-pick, revert or bisect is
		// finished or aborted, so a click shows the way out instead.
		var operation = Repository.operation_in_progress(d_repository);

		if (operation != null)
		{
			show_operation_preview(operation);
			return;
		}

		// A stash is not a branch position (FR-142): show how to apply it, and
		// never fold it into a branch plan. What someone wants from a stash is
		// their files back.
		if (d_view == "stash")
		{
			show_stash_preview(entry);
			return;
		}

		// A detached HEAD has no branch to reset, so clicking an entry plans
		// nothing; update_preview owns showing the way back instead (Option 3).
		// Applying a stash is unaffected, which is why this comes after the
		// stash case.
		if (d_current_branch == null)
		{
			update_preview();
			return;
		}

		var branch = ResetPreview.target_branch_for(d_view, d_list.branch_at(path), d_tips);

		if (branch == null)
		{
			// A branchless row: a detached-HEAD stretch attributed to no
			// branch, so there is nothing to move or recreate (FR-148). A row
			// naming a deleted branch is not branchless and folds in below, to
			// be recreated (FR-166).
			show_preview_placeholder(_("No branch to move for this entry"));
			return;
		}

		// P-FR-24: a commit whose object has been pruned cannot be drawn, so it
		// cannot be planned either.
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
				// Clicking the row that is already the sole selection clears it;
				// any other row becomes the new sole selection.
				d_plan.set_only_or_clear(branch, entry.new_id);
				break;
		}

		d_list.refresh_plan_marks();
		refresh_ref_weights();
		update_preview();
	}

	/**
	 * Toggle the entry at a store index (FR-148).
	 *
	 * Exposed for the tests, matching what a toggle does: a click in a branch
	 * view, or a Ctrl-click in the HEAD view. Returns false when the index is
	 * out of range or the search filter hides it.
	 */
	public bool toggle_entry(int index)
	{
		return fold_entry(index, PlanFold.TOGGLE);
	}

	/**
	 * Select the entry at a store index (FR-148).
	 *
	 * Exposed for the tests, matching what keyboard arrow travel does: a single
	 * selection that replaces the plan in the HEAD view, or the landed row's
	 * branch kept alongside the others in a branch view. Returns false when the
	 * index is out of range or the search filter hides it.
	 */
	public bool select_entry(int index)
	{
		return fold_entry(index, arrow_fold());
	}

	/**
	 * Click the entry at a store index (FR-148).
	 *
	 * Exposed for the tests, matching a plain primary click: in the HEAD view it
	 * makes the row the sole selection, or clears it when it already is; in a
	 * branch view it toggles that branch. Returns false when the index is out of
	 * range or the search filter hides it.
	 */
	public bool click_entry(int index)
	{
		return fold_entry(index, click_fold(false));
	}

	/**
	 * Fold the entry at a store index into the plan, for the three test hooks.
	 *
	 * Returns false when the index is out of range or the search filter hides
	 * it, so a test can tell an ignored input from an acted-on one.
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

		// A tree-row button event arrives on the bin window, so its coordinates
		// are already bin-window relative and get_path_at_pos takes them as-is.
		// Converting from widget coordinates here (as the tooltip handler must,
		// since query-tooltip gives widget coordinates) would subtract the
		// header height a second time and land a row too high.
		Gtk.TreePath? path;

		if (!d_reflog_list.get_path_at_pos((int)event.x, (int)event.y, out path, null, null, null))
		{
			return false;
		}

		var ctrl = (event.state & Gdk.ModifierType.CONTROL_MASK) != 0;
		plan_path(path, click_fold(ctrl));

		// Let the row still take the keyboard cursor.
		return false;
	}

	private bool on_key_press(Gdk.EventKey event)
	{
		if (event.keyval == Gdk.Key.space
		    || event.keyval == Gdk.Key.Return
		    || event.keyval == Gdk.Key.KP_Enter)
		{
			// The cursor, not the selection: selection is off (see construct),
			// but the focus cursor still moves with the arrow keys.
			Gtk.TreePath? path;
			d_reflog_list.get_cursor(out path, null);

			if (path == null)
			{
				return false;
			}

			plan_path(path, PlanFold.TOGGLE);

			// Consume, so Space does not also scroll the list.
			return true;
		}

		if (is_vertical_nav_key(event.keyval))
		{
			// Arrow travel selects the row it lands on, the way a click does,
			// so the preview follows the cursor. The tree view moves its own
			// cursor for these keys, so let that happen (return false) and read
			// where it landed on the next idle, once the move has completed.
			schedule_cursor_select();
			return false;
		}

		return false;
	}

	/** Whether `keyval` is a key that moves the tree view's cursor up or down. */
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
	 * Select whatever row the cursor lands on after a keyboard move.
	 *
	 * Deferred to an idle because the tree view moves its cursor in its own
	 * key handler, which runs after this one; the idle reads the settled
	 * cursor. Coalesced through `d_cursor_select_id` so a held-down arrow key,
	 * which repeats, schedules the work once per settled position rather than
	 * stacking an idle per repeat.
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
	 * Take over the graph's lane cell so its labels come from the preview.
	 *
	 * gitg's own data func fills the lane cell from the repository's real refs.
	 * Re-setting it here keeps everything gitg does (the lanes, the commit and
	 * its successor) and changes only where the labels come from, so a planned
	 * branch's pill can sit at the commit a reset would move it to. Called once:
	 * the column and its cell live for the widget's lifetime.
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
	 * Fill the lane cell for a row, with the preview's labels (FR-150).
	 *
	 * A copy of gitg's own lanes data func in all but the label source: the
	 * commit and its successor set the lanes exactly as gitg would, and the
	 * labels come from labels_for_preview() so a moved branch shows where a
	 * reset would put it.
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
	 * The labels to draw at a commit: the plan's override, else the real refs.
	 *
	 * An id the plan touches (a branch moved off it or onto it) has an entry in
	 * d_preview_labels and that wins, even when the entry is the empty list (a
	 * commit a branch was the only ref on, now moved away). Every other commit
	 * falls back to gitg's real-ref lookup, so tags, remotes and unmoved
	 * branches are unaffected.
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
	 * Rebuild the label override from the current plan (FR-150).
	 *
	 * For each planned branch that visibly moves, its pill is taken off the
	 * commit it really sits on and put on the commit it would reset to. Other
	 * refs on those commits are kept. Built before every reload so the graph's
	 * first draw already has the labels in their planned places.
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

			// A branch not among the current tips is being recreated (FR-166):
			// it has no live pill to move, so draw a synthetic one at the commit
			// `git branch <name> <sha>` would put it on.
			if (from == null)
			{
				add_label(target, new SyntheticBranchRef(branch));
				continue;
			}

			// A move to where the branch already is relocates nothing.
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

	/** The branch's own ref object where it really sits, or null. */
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

	/** Override `id`'s labels with its current ones minus `exclude`. */
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

	/** Override `id`'s labels with its current ones plus `add`. */
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

	/** `id`'s labels so far: the override if one exists, else the real refs. */
	private unowned GLib.SList<Gitg.Ref> current_preview_labels(Ggit.OId id)
	{
		if (d_preview_labels.contains(id))
		{
			return d_preview_labels.lookup(id);
		}

		return d_repository.refs_for_id(id);
	}

	/**
	 * The ref shortnames the preview draws at a commit (test-facing, FR-150).
	 *
	 * The names of the pills gitg would paint on the row for `id` given the
	 * current plan, so a test can assert a moved branch shows at its target and
	 * not at its old tip without reading pixels.
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
	 * Draw the graph the plan would produce, or the repository as it stands.
	 *
	 * The tip set keeps the whole current tree and adds every planned target
	 * (FR-150), so nothing a reset would abandon disappears; with an empty plan
	 * that is just the real tips, the current repository tree. A planned
	 * branch's label is moved onto its target by rebuild_preview_labels(). With
	 * an empty plan there is no command to run, so no banner and no warning, and
	 * the caption says it is the present state rather than a preview. Once
	 * entries are toggled into the plan the command (FR-149) and its caption
	 * appear.
	 */
	private void update_preview()
	{
		if (d_repository == null || d_commit_model == null)
		{
			return;
		}

		// A repository mid-operation comes first: a rebase, merge, cherry-pick,
		// revert or bisect must be finished or aborted before a reset or a
		// checkout means anything. A rebase and a bisect detach HEAD, so this
		// has to be tested before the detached case below, or it would offer
		// `git checkout -` in the middle of a rebase.
		var operation = Repository.operation_in_progress(d_repository);

		if (operation != null)
		{
			show_operation_preview(operation);
			return;
		}

		// A detached HEAD shows the way back on to a branch rather than a tree
		// to reset (Option 3). The stash view is exempt: applying a stash works
		// whether or not HEAD is on a branch.
		if (d_current_branch == null && d_view != "stash")
		{
			show_detached_preview();
			return;
		}

		var tips = ResetPreview.preview_tips(d_tips, d_plan);

		// No tips to draw at all (an unborn HEAD, say): nothing to show.
		if (tips.length == 0)
		{
			show_preview_placeholder(_("Select an entry"));
			return;
		}

		included_tips = tips;

		// Move each planned branch's label onto its target before the reload,
		// so the graph's first draw already shows the pills where a reset would
		// put them (FR-150).
		rebuild_preview_labels();

		// Keep the graph where it was scrolled to across the reload (see
		// d_saved_top_row). Captured only when nothing is already pending, so a
		// burst of clicks preserves the row from before the first one rather
		// than the post-clear top of the ones between.
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
			// The repository as it is now: the graph over the real tips, no
			// reset planned. Nothing to run, so the banner and warning stay
			// down; the caption marks this as the present state.
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
	 * The caption over the graph (FR-146, revisited for the plan).
	 *
	 * One planned branch that still exists keeps the wording that names it as
	 * moved; two or more drop the clause, because there is no single branch to
	 * name. A single recreated branch (one no longer among the tips) is not
	 * moved either, so it takes the plain caption too (FR-166). Derived from
	 * the same plan the command is, so caption and command cannot disagree.
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
	 * Scroll the graph back to its saved top row after a reload.
	 *
	 * scroll_to_cell stores the request and applies it once the tree view has
	 * validated the freshly inserted rows, which is why it works where setting
	 * the adjustment directly does not. A row that no longer exists (a shorter
	 * graph) falls back to the last row. This relies on the graph's headers
	 * being hidden; with them shown, scroll_to_cell does not move a
	 * fixed-height tree view, which is one reason the headers stay off.
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
	 * Fit the graph's columns to their content once, when it first loads.
	 *
	 * The reflog list above fits its columns on open (FR-147); this does the
	 * same for the graph, where the columns are not otherwise sized to content.
	 * Author, SHA and date size to what they hold; the subject column keeps
	 * expanding to fill, and the graph is not measured for it. Done once per
	 * repository rather than on every reload, so building a plan does not make
	 * the columns twitch.
	 *
	 * The columns are not user-resizable: the graph's headers are hidden (to
	 * keep the gitg look and the scroll_to_cell restore working), and without
	 * headers GTK offers no resize handles.
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

		// A bounded sample: enough to catch the range of author-name widths
		// without measuring thousands of rows. SHA and date are fixed formats,
		// so any row settles them.
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

			// Just the name: the column binds to AUTHOR_NAME (model column 4),
			// not "name <email>". Measuring the longer form fitted the column
			// far wider than its content, leaving a gap between the name and the
			// SHA and stealing width from the message.
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
	 * A commit's hash abbreviated to seven characters, as the reflog list
	 * shows it (ReflogEntry.abbreviated_id) and as git's --abbrev-commit does.
	 */
	private static string abbreviated_sha(Gitg.Commit commit)
	{
		var sha = commit.get_id().to_string();

		return sha.length > 7 ? sha.substring(0, 7) : sha;
	}

	/**
	 * A commit's author date in git's --date=iso form.
	 *
	 * "2026-07-20 10:00:00 +0200" — the local time with its offset, as git
	 * prints it, rather than a normalised UTC that would not match what the
	 * user sees from git itself.
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
	 * What to do with a stashed change (item 6).
	 *
	 * A stash entry is a commit, so the reset machinery will happily offer to
	 * move a branch to it — and that is almost never what anyone wants. It
	 * would put the stashed content on the branch as committed history,
	 * which is a strange thing to do by accident while trying to get some
	 * edits back.
	 *
	 * `apply` rather than `pop`: apply leaves the stash in place, so if the
	 * result is not what they expected the stash is still there to try again.
	 * `pop` removes it on success, and for someone who is already lost that
	 * is a worse default.
	 *
	 * There is no graph, because applying a stash moves no ref: the graph
	 * would be identical to the current one, and showing an unchanged graph
	 * beside a command implies the command does nothing.
	 */
	private void show_stash_preview(ReflogEntry entry)
	{
		show_command_note("git stash apply %s".printf(entry.selector),
			_("Applying a stash changes your files, not your branches, so there is no new history to show."));
	}

	/**
	 * What to do when HEAD is detached.
	 *
	 * With a detached HEAD there is no branch to reset, so reset planning is
	 * switched off until you are back on one: a `git branch -f` would move a ref
	 * while leaving HEAD detached, which looks like it did nothing, and moving
	 * the branch you are notionally on is not possible because there is none.
	 * So the preview offers only the way back, `git checkout -`, and explains
	 * why.
	 */
	private void show_detached_preview()
	{
		show_command_note("git checkout -",
			_("HEAD is detached, so you are not on a branch and there is nothing to reset. Run the command above to return to the branch you were on, then plan a reset from there."));
	}

	/** The command that ends an in-progress operation (IC-164 tokens). */
	private static string operation_command(string operation)
	{
		// Every operation but bisect ends with `--abort`; bisect ends with
		// `git bisect reset`.
		return operation == "bisect" ? "git bisect reset"
		                             : "git %s --abort".printf(operation);
	}

	/**
	 * What to do when a git operation is in progress (FR-165).
	 *
	 * A rebase, merge, cherry-pick, revert or bisect has to be finished or
	 * aborted before a reset or a checkout means anything, so reset planning is
	 * off and the preview offers the one command that undoes the operation. A
	 * rebase and a bisect leave HEAD detached, which is why this is reached
	 * before the detached-HEAD case, so it does not offer `git checkout -` in
	 * the middle of a rebase.
	 */
	private void show_operation_preview(string operation)
	{
		show_command_note(operation_command(operation),
			_("A %s is in progress. Finish it, or run the command above to abort and undo it. Reset planning is off until you do.").printf(operation));
	}

	/**
	 * Show a copyable command and a note, with no graph.
	 *
	 * The shape both the stash and the detached-HEAD previews want: a command
	 * that moves no ref, so there is nothing for the graph to show, and a note
	 * saying why. The banner carries the command; the warning and the graph
	 * caption come down (and any stale tips and labels are cleared) so the pane
	 * does not keep showing the last reset's graph beside it.
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
	 * Warn when the shown command would destroy uncommitted work.
	 *
	 * This is the only thing gitrl-z warns about, because it is the only thing
	 * it shows you that the reflog cannot undo. A commit dropped by a reset
	 * is still in the reflog and gitrl-z will happily bring it back; a file
	 * you had edited and not committed is simply gone.
	 */
	private void update_uncommitted_warning()
	{
		if (d_repository == null || d_command == "")
		{
			set_warning_visible(false);
			return;
		}

		// Only a hard reset destroys the working tree. A command that merely
		// repoints a ref leaves it alone, and warning about those would teach
		// people to ignore the warning.
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

	/** Files a hard reset would destroy, for the tests. */
	public uint uncommitted_changes
	{
		get { return d_uncommitted; }
	}

	/** The caption over the reflog list, for the tests. */
	public string reflog_caption
	{
		get { return d_reflog_caption.label; }
	}

	/** The caption over the preview graph, or "" when hidden, for the tests. */
	public string graph_caption
	{
		get { return d_graph_caption.visible ? d_graph_caption.label : ""; }
	}

	/** Whether the uncommitted-changes warning is showing. */
	public bool warning_visible
	{
		get { return d_warning.visible; }
	}

	/**
	 * Show or hide the warning, keeping it flush against the command banner.
	 *
	 * The two are one statement — what would be destroyed, and the command
	 * that would destroy it — so when both are up they touch and read as a
	 * single block. The warning's own bottom margin is zero in the template;
	 * it is the banner's top margin that has to go, and only while the
	 * warning is there. Without the warning the banner needs it back, or it
	 * sits flush against the top of the preview pane instead.
	 */
	private void set_warning_visible(bool visible)
	{
		d_warning.visible = visible;
		d_banner.margin_top = visible ? 0 : BANNER_MARGIN;
	}

	/**
	 * Colour the banner green exactly when it shows the copied command.
	 *
	 * Green means "this is what you would paste right now" — a claim about
	 * the clipboard, so it is derived from the clipboard's contents rather
	 * than latched when the button is pressed. Select another entry and it
	 * goes amber; come back and it is green again; copy something else and
	 * the old one stops being green anywhere.
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

		// Only the gutter, which is the first column, carries a tooltip.
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
