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
 * A window that shows the diff of one commit.
 *
 * The window is separate rather than a third pane, so the reflog list and the
 * graph keep their height. It is transient for the main window, thus it stays
 * above it and closes with it. One window serves every commit: a second request
 * moves this one rather than opening another.
 *
 * What it holds is gitg's own diff pane, `Gitg.DiffView`: the commit's details,
 * its message, and one collapsible section per changed file. The pane reads the
 * diff itself, so this class hands it a repository and a commit and nothing
 * more. Its properties take the values gitg's own diff panel gives them, so
 * that the pane reads as the pane of the gitg installed beside it.
 *
 * The title bar keeps the short hash and the subject even though the pane
 * states both: a window in a task bar needs a name, and the pane scrolls its
 * details away.
 */
public class DiffWindow : Gtk.Window
{
	private Gtk.HeaderBar d_header;
	private Gitg.DiffView d_view;
	private Settings d_diff_settings;
	private Settings d_interface_settings;
	private Settings d_state_settings;
	private Gtk.RadioButton d_split_button;
	private Gtk.RadioButton d_unified_button;

	/** The two values of the `renderer` state key, and the stack name of each. */
	private const string SPLIT = "split";
	private const string UNIFIED = "unified";
	private const string SPLIT_RENDERER = "splittext";
	private const string UNIFIED_RENDERER = "text";

	// Wide, because a file section holds two columns beside each other.
	private const int DEFAULT_WIDTH = 1200;
	private const int DEFAULT_HEIGHT = 700;

	/** The length of the hash in the title: enough to be unambiguous. */
	private const int TITLE_SHA_LENGTH = 10;

	/** The pane, so a test can read what it built. */
	public Gitg.DiffView view
	{
		get { return d_view; }
	}

	static construct
	{
		// The renderer marks the words that changed inside a changed line, which
		// gitg does not (FR-178). It is vendored gitg code and cannot call into
		// this namespace, so the marker is left where it looks for it.
		//
		// Here rather than in Application.startup, because the marks belong to
		// the window that shows a diff: a test that constructs this window gets
		// the same pane as the application, with nothing to remember to install.
		Gitg.WordMarks.func = WordDiff.refine_flat;
	}

	public DiffWindow(Gtk.Window? parent)
	{
		Object(transient_for: parent);
	}

	construct
	{
		d_header = new Gtk.HeaderBar();
		d_header.show_close_button = true;
		d_header.title = _("Diff");
		set_titlebar(d_header);

		d_view = new Gitg.DiffView();

		// A merge has more than one parent, and the diff is against one of
		// them. The buttons say which, and let the reader have the other side.
		d_view.show_parents = true;

		bind_settings();

		d_header.pack_end(renderer_switch());

		add(d_view);

		set_default_size(DEFAULT_WIDTH, DEFAULT_HEIGHT);

		// A diff is wide and long, thus the window opens filling the screen. The
		// default size above is what it returns to when it is unmaximised.
		maximize();

		// A settings binding holds the pane, and the pane answers every change
		// of a key for as long as it does. A closed window must stop answering:
		// otherwise moving the context lines rebuilds the sections of a window
		// that is no longer on the screen, and the pane is never freed.
		destroy.connect(unbind_settings);

		// The window reads as a detail of the graph, thus Escape closes it, as
		// it closes a dialog.
		key_press_event.connect((event) => {
			if (event.keyval == Gdk.Key.Escape)
			{
				destroy();
				return true;
			}

			return false;
		});

		show_all();
	}

	public void show_commit(Gitg.Repository repository, Ggit.Commit commit)
	{
		var sha = commit.get_id().to_string();
		var subject = commit.get_subject();

		d_header.title = sha.length > TITLE_SHA_LENGTH
			? sha.substring(0, TITLE_SHA_LENGTH)
			: sha;
		d_header.subtitle = subject != null ? subject : "";

		// The repository comes first: the details grid reads it while it takes
		// the commit.
		d_view.repository = repository;

		// Every Ggit.Commit in the process is a Gitg.Commit, because Gitg.init()
		// registers that type with the Ggit factory.
		d_view.commit = commit as Gitg.Commit;
	}

	/**
	 * Ties the pane to the settings, as gitg's diff panel ties its own.
	 *
	 * The options bar at the foot of the pane writes to these same properties,
	 * so a value moved there is a value remembered.
	 */
	private void bind_settings()
	{
		d_diff_settings = new Settings("%s.preferences.diff".printf(Config.APPLICATION_ID));

		d_diff_settings.bind("ignore-whitespace", d_view, "ignore-whitespace",
		                     SettingsBindFlags.GET | SettingsBindFlags.SET);
		d_diff_settings.bind("context-lines", d_view, "context-lines",
		                     SettingsBindFlags.GET | SettingsBindFlags.SET);
		d_diff_settings.bind("tab-width", d_view, "tab-width",
		                     SettingsBindFlags.GET | SettingsBindFlags.SET);
		d_diff_settings.bind("wrap", d_view, "wrap-lines",
		                     SettingsBindFlags.GET | SettingsBindFlags.SET);

		d_interface_settings = new Settings("%s.preferences.interface".printf(Config.APPLICATION_ID));

		d_interface_settings.bind("use-gravatar", d_view, "use-gravatar",
		                          SettingsBindFlags.GET | SettingsBindFlags.SET);
		d_interface_settings.bind("enable-diff-highlighting", d_view, "highlight",
		                          SettingsBindFlags.GET | SettingsBindFlags.SET);
	}

	/**
	 * The two buttons that choose the renderer, for the title bar.
	 *
	 * gitg puts a switcher in the header of every file. gitrl-z reads one commit
	 * per window and switches the lot, thus one control serves the window and
	 * the file headers stay clear of it. The choice is remembered, so a diff
	 * opens the way the last one was left.
	 */
	private Gtk.Widget renderer_switch()
	{
		d_state_settings = new Settings("%s.state.diff".printf(Config.APPLICATION_ID));

		// Translators: Split stands for the noun, as in a split view. The two
		// labels are gitg's own, so the control reads as the switcher it stands
		// in for.
		d_split_button = new Gtk.RadioButton.with_label(null, _("Split"));
		d_unified_button = new Gtk.RadioButton.with_label_from_widget(d_split_button,
		                                                             _("Unif"));

		var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
		box.get_style_context().add_class("linked");

		foreach (var button in new Gtk.RadioButton[] { d_split_button, d_unified_button })
		{
			// A radio button draws its indicator unless it is told to behave as
			// a toggle, which is what makes the pair read as one linked control.
			button.set_mode(false);
			box.pack_start(button, false, false, 0);
		}

		unified = d_state_settings.get_string("renderer") == UNIFIED;

		d_split_button.toggled.connect(() => {
			if (d_split_button.active)
			{
				unified = false;
			}
		});

		d_unified_button.toggled.connect(() => {
			if (d_unified_button.active)
			{
				unified = true;
			}
		});

		return box;
	}

	/** Which renderer the window shows, and what it remembers. */
	private bool unified
	{
		get { return d_view.renderer_name == UNIFIED_RENDERER; }

		set
		{
			d_view.renderer_name = value ? UNIFIED_RENDERER : SPLIT_RENDERER;
			d_state_settings.set_string("renderer", value ? UNIFIED : SPLIT);

			if (value)
			{
				d_unified_button.active = true;
			}
			else
			{
				d_split_button.active = true;
			}
		}
	}

	/** Drops every binding of bind_settings(), so a closed window goes quiet. */
	private void unbind_settings()
	{
		foreach (var property in BOUND_PROPERTIES)
		{
			Settings.unbind(d_view, property);
		}
	}

	/** The properties of the pane that bind_settings() ties to a key. */
	private const string[] BOUND_PROPERTIES = {
		"ignore-whitespace",
		"context-lines",
		"tab-width",
		"wrap-lines",
		"use-gravatar",
		"highlight"
	};
}

}

// ex:set ts=4 noet:
