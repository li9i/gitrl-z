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

public class DiffWindow : Gtk.Window
{
	private Gtk.HeaderBar d_header;
	private Gitg.DiffView d_view;
	private Settings d_diff_settings;
	private Settings d_interface_settings;
	private Settings d_state_settings;
	private Gtk.RadioButton d_split_button;
	private Gtk.RadioButton d_unified_button;

	private const string SPLIT = "split";
	private const string UNIFIED = "unified";
	private const string SPLIT_RENDERER = "splittext";
	private const string UNIFIED_RENDERER = "text";

	private const int DEFAULT_WIDTH = 1200;
	private const int DEFAULT_HEIGHT = 700;

	private const int TITLE_SHA_LENGTH = 10;

	public Gitg.DiffView view
	{
		get { return d_view; }
	}

	static construct
	{
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

		d_view.show_parents = true;

		bind_settings();

		d_header.pack_end(renderer_switch());

		add(d_view);

		set_default_size(DEFAULT_WIDTH, DEFAULT_HEIGHT);

		maximize();

		destroy.connect(unbind_settings);

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

		d_view.repository = repository;

		d_view.commit = commit as Gitg.Commit;
	}

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

	private Gtk.Widget renderer_switch()
	{
		d_state_settings = new Settings("%s.state.diff".printf(Config.APPLICATION_ID));

		// Translators: Split stands for the noun, as in a split view. The two
		d_split_button = new Gtk.RadioButton.with_label(null, _("Split"));
		d_unified_button = new Gtk.RadioButton.with_label_from_widget(d_split_button,
		                                                             _("Unif"));

		var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
		box.get_style_context().add_class("linked");

		foreach (var button in new Gtk.RadioButton[] { d_split_button, d_unified_button })
		{
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

	private void unbind_settings()
	{
		foreach (var property in BOUND_PROPERTIES)
		{
			Settings.unbind(d_view, property);
		}
	}

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
