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
 *
 * You should have received a copy of the GNU General Public License along
 * with gitrl-z. If not, see <http://www.gnu.org/licenses/>.
 */

namespace Gitrlz
{

/**
 * Preferences (spec FR-115).
 *
 * Each control here binds to a key in the gitrl-z schema, and gitrl-z reads
 * each key in that schema. The commit, clone, diff and gravatar pages of gitg
 * have no equivalent, because the settings for them do not exist.
 *
 * Settings.bind makes the bindings. Thus the dialog has no save step and no
 * apply button. A change becomes effective immediately, and the schema holds
 * the only copy of the data.
 */
public class PreferencesDialog : Gtk.Dialog
{
	private Settings d_interface_settings;
	private Settings d_reflog_settings;

	public PreferencesDialog(Gtk.Window? parent)
	{
		Object(title: _("Preferences"),
		       transient_for: parent,
		       use_header_bar: 1,
		       destroy_with_parent: true);
	}

	construct
	{
		d_interface_settings = new Settings("%s.preferences.interface".printf(Config.APPLICATION_ID));
		d_reflog_settings = new Settings("%s.preferences.reflog".printf(Config.APPLICATION_ID));

		set_default_size(500, -1);

		var notebook = new Gtk.Notebook();
		notebook.margin = 12;

		notebook.append_page(build_interface_page(), new Gtk.Label(_("Interface")));
		notebook.append_page(build_reflog_page(), new Gtk.Label(_("Reflog")));

		get_content_area().add(notebook);

		show_all();
	}

	private Gtk.Widget build_interface_page()
	{
		var grid = new_page_grid();
		var row = 0;

		var orientation = new Gtk.ComboBoxText();
		orientation.append("horizontal", _("Horizontal"));
		orientation.append("vertical", _("Vertical"));
		// The key is an enum, and the active-id of ComboBoxText is a string.
		// Thus the mapping uses the nick. bind_with_mapping is the general
		// solution. For two values the nicks are already the strings.
		orientation.active_id = d_interface_settings.get_string("orientation");
		orientation.changed.connect(() => {
			if (orientation.active_id != null)
			{
				d_interface_settings.set_string("orientation", orientation.active_id);
			}
		});
		add_row(grid, ref row, _("_Layout:"), orientation);

		var use_default_font = new Gtk.CheckButton.with_mnemonic(_("Use the system fixed width font"));
		d_interface_settings.bind("use-default-font", use_default_font, "active",
		                          SettingsBindFlags.DEFAULT);
		add_wide_row(grid, ref row, use_default_font);

		var font_button = new Gtk.FontButton();
		d_interface_settings.bind("monospace-font-name", font_button, "font",
		                          SettingsBindFlags.DEFAULT);
		// A font selection has no effect while the system font is in use.
		// Thus the control follows the checkbox.
		d_interface_settings.bind("use-default-font", font_button, "sensitive",
		                          SettingsBindFlags.GET | SettingsBindFlags.INVERT_BOOLEAN);
		add_row(grid, ref row, _("_Font:"), font_button);

		var monitoring = new Gtk.CheckButton.with_mnemonic(
			_("Reload automatically when the repository changes"));
		d_interface_settings.bind("enable-monitoring", monitoring, "active",
		                          SettingsBindFlags.DEFAULT);
		add_wide_row(grid, ref row, monitoring);

		return grid;
	}

	private Gtk.Widget build_reflog_page()
	{
		var grid = new_page_grid();
		var row = 0;

		var limit = new Gtk.SpinButton.with_range(100, 100000, 100);
		d_reflog_settings.bind("commit-limit", limit, "value", SettingsBindFlags.DEFAULT);
		add_row(grid, ref row, _("_Maximum commits drawn:"), limit);

		return grid;
	}

	private Gtk.Grid new_page_grid()
	{
		var grid = new Gtk.Grid();
		grid.margin = 12;
		grid.row_spacing = 6;
		grid.column_spacing = 12;
		return grid;
	}

	private void add_row(Gtk.Grid grid, ref int row, string label_text, Gtk.Widget control)
	{
		var label = new Gtk.Label.with_mnemonic(label_text);
		label.xalign = 0;
		label.mnemonic_widget = control;

		control.hexpand = true;

		grid.attach(label, 0, row, 1, 1);
		grid.attach(control, 1, row, 1, 1);

		row++;
	}

	private void add_wide_row(Gtk.Grid grid, ref int row, Gtk.Widget control)
	{
		grid.attach(control, 0, row, 2, 1);
		row++;
	}
}

}

// ex:set ts=4 noet:
