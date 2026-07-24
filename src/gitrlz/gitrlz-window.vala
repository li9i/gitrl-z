/*
 * This file is part of gitrl-z
 *
 * Copyright (C) 2026 alexandros filotheou
 *
 * Derived in structure from gitg's gitg-window.vala,
 * Copyright (C) 2012 Jesse van den Kieboom, and licensed under the same
 * terms.
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

[GtkTemplate (ui = "/io/github/li9i/gitrlz/ui/gitrlz-window.ui")]
public class Window : Gtk.ApplicationWindow
{
	[GtkChild]
	private unowned Gtk.HeaderBar d_header_bar;
	[GtkChild]
	private unowned Gtk.Button d_dash_button;
	[GtkChild]
	private unowned Gtk.StackSwitcher d_activities_switcher;
	[GtkChild]
	private unowned Gtk.ToggleButton d_search_button;
	[GtkChild]
	private unowned Gtk.MenuButton d_gear_menu;
	[GtkChild]
	private unowned Gtk.Stack d_main_stack;
	[GtkChild]
	private unowned Gtk.Stack d_stack_activities;
	[GtkChild]
	private unowned Gtk.InfoBar d_infobar;
	[GtkChild]
	private unowned Gtk.Label d_infobar_primary_label;
	[GtkChild]
	private unowned Gtk.Label d_infobar_secondary_label;

	private Settings d_state_settings;
	private Gitg.Repository? d_repository;
	private Gitrlz.DashView d_dash_view;
	private Gitrlz.ReflogPaned d_reflog;

	public Gitg.Repository? repository
	{
		get { return d_repository; }
	}

	private const ActionEntry[] s_action_entries = {
		{"dash", on_dash_activated},
		{"reload", on_reload_activated},
		{"preferences", on_preferences_activated},
	};

	public Window(Gtk.Application application)
	{
		Object(application: application);
	}

	construct
	{
		d_state_settings = new Settings("%s.state.window".printf(Config.APPLICATION_ID));

		add_action_entries(s_action_entries, this);

		var builder = new Gtk.Builder.from_resource("/io/github/li9i/gitrlz/ui/gitrlz-menus.ui");
		d_gear_menu.menu_model = builder.get_object("gear-menu") as MenuModel;

		d_infobar.response.connect((id) => {
			d_infobar.hide();
		});

		d_dash_view = new Gitrlz.DashView();
		d_dash_view.repository_activated.connect(on_repository_activated);
		d_dash_view.show_error.connect((primary, secondary) => {
			show_infobar(primary, secondary, Gtk.MessageType.ERROR);
		});
		d_main_stack.add_named(d_dash_view, "dash");

		// The one activity gitrl-z has (FR-120). Compiled in rather than
		// loaded: gitg's own History activity is listed directly in its
		// sources too, so dropping libpeas costs nothing here.
		d_reflog = new Gitrlz.ReflogPaned();
		d_stack_activities.add_titled(d_reflog, "reflog", _("Reflog"));

		reload.connect(() => {
			d_reflog.reload();
		});

		// FR-117: the header bar's search toggle drives the activity's search
		// bar. Binding active <-> search_mode_enabled keeps the button and the
		// bar's own close control in step.
		d_search_button.toggled.connect(() => {
			d_reflog.set_search_visible(d_search_button.active);
		});

		restore_state();

		// The dash is what a window without a repository shows (FR-100), so
		// it is also the sensible state to start in: open_repository() moves
		// off it when there is something to open.
		show_dash();
	}

	/**
	 * Restore and follow window geometry (FR-116).
	 */
	private void restore_state()
	{
		var size = d_state_settings.get_value("size");

		int width;
		int height;
		size.get("(ii)", out width, out height);

		if (width > 0 && height > 0)
		{
			set_default_size(width, height);
		}

		if ((d_state_settings.get_int("state") & Gdk.WindowState.MAXIMIZED) != 0)
		{
			maximize();
		}
	}

	protected override bool window_state_event(Gdk.EventWindowState event)
	{
		d_state_settings.set_int("state", event.new_window_state);
		return base.window_state_event(event);
	}

	protected override bool configure_event(Gdk.EventConfigure event)
	{
		// Only an unmaximised size is worth remembering; storing the
		// maximised one would restore a window that fills the screen but is
		// not actually maximised.
		if ((d_state_settings.get_int("state") & Gdk.WindowState.MAXIMIZED) == 0)
		{
			int width;
			int height;
			get_size(out width, out height);

			d_state_settings.set_value("size", new Variant("(ii)", width, height));
		}

		return base.configure_event(event);
	}

	/**
	 * Open a repository, or report why it cannot be opened.
	 *
	 * `location` is a repository location as returned by
	 * Application.discover_repository, not an arbitrary path.
	 */
	public void open_repository(File location)
	{
		try
		{
			d_repository = Gitrlz.Repository.open(location);
		}
		catch (Error e)
		{
			// An unopenable repository is reported in the window rather than
			// on the command line: by this point a window exists, and taking
			// the whole application down over one bad path would be worse
			// than showing the dash with an explanation (spec section 5).
			show_infobar(_("Failed to open repository"), e.message, Gtk.MessageType.ERROR);
			d_repository = null;
			show_dash();
			return;
		}

		update_title();
		d_reflog.repository = d_repository;
		show_activities();
	}

	private void update_title()
	{
		if (d_repository == null)
		{
			d_header_bar.title = "gitrl-z";
			d_header_bar.subtitle = null;
			return;
		}

		d_header_bar.title = d_repository.name;

		var workdir = d_repository.get_workdir();
		var location = workdir != null ? workdir : d_repository.get_location();

		if (location != null)
		{
			d_header_bar.subtitle = Gitg.Utils.replace_home_dir_with_tilde(location);
		}
	}

	public void show_infobar(string primary, string secondary, Gtk.MessageType type)
	{
		d_infobar_primary_label.label = primary;
		d_infobar_secondary_label.label = secondary;
		d_infobar.message_type = type;
		d_infobar.show();
	}

	/**
	 * Show the repository chooser (FR-100, FR-111).
	 */
	public void show_dash()
	{
		d_main_stack.visible_child_name = "dash";

		d_dash_button.visible = false;
		d_activities_switcher.visible = false;
		d_search_button.visible = false;

		update_title();
	}

	public void show_activities()
	{
		d_main_stack.visible_child_name = "activities";

		d_dash_button.visible = true;
		d_activities_switcher.visible = d_stack_activities.get_children().length() > 1;
		d_search_button.visible = true;
	}

	private void on_dash_activated(SimpleAction action, Variant? parameter)
	{
		show_dash();
	}

	private void on_repository_activated(Gitg.Repository repository)
	{
		d_repository = repository;
		update_title();
		d_reflog.repository = d_repository;
		show_activities();
	}

	private void on_reload_activated(SimpleAction action, Variant? parameter)
	{
		// The reflog activity does the actual reloading (FR-130); this is the
		// F5 and menu entry point that will drive it.
		reload();
	}

	public signal void reload();

	private void on_preferences_activated(SimpleAction action, Variant? parameter)
	{
		var dialog = new Gitrlz.PreferencesDialog(this);
		dialog.present();
	}
}

}

// ex:set ts=4 noet:
