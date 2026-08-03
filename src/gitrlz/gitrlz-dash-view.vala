/*
 * This file is part of gitrl-z
 *
 * Copyright (C) 2026 alexandros filotheou
 *
 * The structure comes from gitg-dash-view.vala of gitg,
 * Copyright (C) 2015 Ignacio Casal Quinteiro, and licensed under the same
 * terms. The clone entry of gitg and its repository-creation paths are
 * absent. gitrl-z opens repositories and does not make them (spec NFR-4).
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
 *
 * You should have received a copy of the GNU General Public License along
 * with gitrl-z. If not, see <http://www.gnu.org/licenses/>.
 */

namespace Gitrlz
{

/**
 * The repository chooser (spec FR-100, FR-111).
 *
 * gitrl-z shows this view when it starts external to a repository. The dash
 * button in the header bar also opens it. It shows the repositories used most
 * recently, a search entry that filters them, and a button that opens a
 * repository which is not in the list.
 */
public class DashView : Gtk.Box
{
	private Gitg.RepositoryListBox d_repository_list;
	private Gtk.SearchEntry d_search_entry;

	public signal void repository_activated(Gitg.Repository repository);
	public signal void show_error(string primary, string secondary);

	construct
	{
		orientation = Gtk.Orientation.VERTICAL;

		var header = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
		header.margin = 12;

		d_search_entry = new Gtk.SearchEntry();
		d_search_entry.placeholder_text = _("Search repositories");
		d_search_entry.hexpand = true;
		d_search_entry.search_changed.connect(on_search_changed);
		header.add(d_search_entry);

		var open_button = new Gtk.Button.with_mnemonic(_("_Open Repository…"));
		open_button.clicked.connect(on_open_clicked);
		header.add(open_button);

		add(header);

		d_repository_list = new Gitg.RepositoryListBox();
		d_repository_list.repository_activated.connect((repository) => {
			repository_activated(repository);
		});
		d_repository_list.show_error.connect((primary, secondary) => {
			show_error(primary, secondary);
		});

		var scrolled = new Gtk.ScrolledWindow(null, null);
		scrolled.hexpand = true;
		scrolled.vexpand = true;
		scrolled.add(d_repository_list);

		add(scrolled);

		// Fills the list from Gtk.RecentManager the first time, then from
		// its own bookmark file.
		d_repository_list.populate_bookmarks();

		show_all();
	}

	private void on_search_changed()
	{
		d_repository_list.filter_text(d_search_entry.text);
	}

	private void on_open_clicked()
	{
		var chooser = new Gtk.FileChooserNative(_("Open Repository"),
		                                        get_toplevel() as Gtk.Window,
		                                        Gtk.FileChooserAction.SELECT_FOLDER,
		                                        _("_Open"),
		                                        _("_Cancel"));

		if (chooser.run() == Gtk.ResponseType.ACCEPT)
		{
			var file = chooser.get_file();

			if (file != null)
			{
				open_location(file);
			}
		}

		chooser.destroy();
	}

	/**
	 * Opens a selected directory. If the directory is not a repository, this
	 * method reports the error and does not throw. It uses the same discovery
	 * as the command line. Thus a directory in a repository opens that
	 * repository (spec FR-2).
	 */
	private void open_location(File file)
	{
		var location = Gitrlz.Application.discover_repository(file);

		if (location == null)
		{
			show_error(_("Not a git repository"),
			           _("%s is not inside a git repository.").printf(file.get_path()));
			return;
		}

		try
		{
			// Through Gitrlz.Repository.open, and not a direct construction.
			// That method is the one location that makes a repository handle
			// (NFR-4), and the only location where Gitg.init() ran first.
			repository_activated(Gitrlz.Repository.open(location));
		}
		catch (Error e)
		{
			show_error(_("Failed to open repository"), e.message);
		}
	}
}

}

// ex:set ts=4 noet:
