/*
 * This file is part of gitrl-z
 *
 * Copyright (C) 2026 alexandros filotheou
 *
 * Derived in structure from gitg's gitg-dash-view.vala,
 * Copyright (C) 2015 Ignacio Casal Quinteiro, and licensed under the same
 * terms. gitg's clone entry and its repository-creation paths are absent:
 * gitrl-z opens repositories, it does not make them (spec NFR-4).
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
 * Shown when gitrl-z is launched outside a repository, and reachable from the
 * header bar's dash button. Lists recently used repositories, filtered by a
 * search entry, with a button to open one that is not in the list.
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

		// Seeds the list from Gtk.RecentManager the first time, and from its
		// own bookmark file afterwards.
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
	 * Open a chosen directory, reporting rather than throwing when it is not
	 * a repository. Discovery is the same one the command line uses, so a
	 * directory inside a repository opens that repository (spec FR-2).
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
			// Through Gitrlz.Repository.open, not a direct construction: it is
			// the one place a repository handle is created (NFR-4), and the
			// only place Gitg.init() is guaranteed to have run first.
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
