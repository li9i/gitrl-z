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
 */
public class DiffWindow : Gtk.Window
{
	private Gtk.HeaderBar d_header;
	private DiffView d_view;

	// Wide, because the view is two columns beside each other.
	private const int DEFAULT_WIDTH = 1200;
	private const int DEFAULT_HEIGHT = 700;

	/** The length of the hash in the title: enough to be unambiguous. */
	private const int TITLE_SHA_LENGTH = 10;

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

		d_view = new DiffView();
		add(d_view);

		set_default_size(DEFAULT_WIDTH, DEFAULT_HEIGHT);

		// A diff is wide and long, thus the window opens filling the screen. The
		// default size above is what it returns to when it is unmaximised.
		maximize();

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

	public void show_commit(Ggit.Repository repository, Ggit.Commit commit)
	{
		var sha = commit.get_id().to_string();
		var subject = commit.get_subject();

		d_header.title = sha.length > TITLE_SHA_LENGTH
			? sha.substring(0, TITLE_SHA_LENGTH)
			: sha;
		d_header.subtitle = subject != null ? subject : "";

		d_view.show_commit(repository, commit.get_id());
	}
}

}

// ex:set ts=4 noet:
