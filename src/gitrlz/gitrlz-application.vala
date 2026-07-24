/*
 * This file is part of gitrl-z
 *
 * Copyright (C) 2026 alexandros filotheou
 *
 * Derived in structure from gitg's gitg-application.vala,
 * Copyright (C) 2012 Jesse van den Kieboom, and licensed under the same
 * terms. Everything gitg does there for cloning, remotes, author details and
 * the commit activity is absent: gitrl-z is read only (spec NFR-4).
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

public class Application : Gtk.Application
{
	private static bool s_show_version = false;
	private static bool s_no_wd = false;
	private static bool s_new_window = false;

	private const OptionEntry[] s_entries = {
		{"version", 'v', 0, OptionArg.NONE, ref s_show_version,
		 N_("Show the application's version"), null},
		{"no-wd", 0, 0, OptionArg.NONE, ref s_no_wd,
		 N_("Do not try to load a repository from the current working directory"), null},
		{"new-window", 0, 0, OptionArg.NONE, ref s_new_window,
		 N_("Open a new window rather than reusing an existing one"), null},
		{null}
	};

	public Application()
	{
		Object(application_id: Gitg.Config.APPLICATION_ID,
		       flags: ApplicationFlags.HANDLES_OPEN |
		              ApplicationFlags.HANDLES_COMMAND_LINE |
		              ApplicationFlags.NON_UNIQUE);
	}

	/**
	 * Everything that has to work without a display happens here.
	 *
	 * local_command_line runs before GApplication connects to the session
	 * bus or opens a display, so this is the only place --version and the
	 * not-a-repository error (spec FR-104) can be handled while still
	 * meeting their requirement to work on a machine with no display.
	 * Deferring either to command_line() or activate() would make them
	 * depend on a display they must not need.
	 */
	protected override bool local_command_line([CCode (array_length = false, array_null_terminated = true)] ref unowned string[] arguments, out int exit_status)
	{
		string[] copy = arguments;
		unowned string[] argv = copy;

		var context = new OptionContext(_("- Git reflog browser and reset preview"));
		context.add_main_entries(s_entries, Config.GETTEXT_PACKAGE);
		context.set_help_enabled(true);

		try
		{
			context.parse(ref argv);
		}
		catch (OptionError e)
		{
			stderr.printf("gitrlz: %s\n", e.message);
			stderr.printf(_("Run '%s --help' to see a full list of available options.\n"),
			              "gitrlz");
			// Exit 2 for a usage error, as spec section 4.1 requires and as
			// convention expects; GApplication's own default would be 1.
			exit_status = 2;
			return true;
		}

		if (s_show_version)
		{
			stdout.printf("%s %s\n", "gitrlz", Config.PACKAGE_VERSION);
			exit_status = 0;
			return true;
		}

		// An explicit path that is not in a repository is an error, reported
		// on stderr with no window (FR-104). This is deliberately not the
		// same as running with no arguments outside a repository, which
		// opens the chooser instead (FR-100).
		for (var i = 1; i < argv.length; i++)
		{
			var file = File.new_for_commandline_arg(argv[i]);

			if (discover_repository(file) == null)
			{
				stderr.printf(_("gitrlz: not a git repository: %s\n"), argv[i]);
				exit_status = 1;
				return true;
			}
		}

		return base.local_command_line(ref arguments, out exit_status);
	}

	/**
	 * Find the repository containing a path, as git itself would.
	 *
	 * Returns the repository location, or null when the path is not inside
	 * one. A file is replaced by its parent directory first (spec FR-2), and
	 * a path that does not exist at all simply is not in a repository.
	 *
	 * Unlike the Python implementation, which asked git for
	 * --show-toplevel, this succeeds for a bare repository: it has refs and
	 * reflogs, so gitrl-z has something to show (spec section 5).
	 */
	public static File? discover_repository(File location)
	{
		// Discovery needs libgit2 initialised, and this can run from
		// local_command_line, before startup() has called Gitg.init().
		//
		// Deliberately Ggit.init() and not Gitg.init(): Gitg.init() is
		// guarded so it runs its body once, and its body also installs the
		// CSS provider — which our headless patch skips when there is no
		// screen. Calling it here would mark it done while there is no
		// display, and startup() would then return early and never style
		// anything. Ggit.init() is itself idempotent.
		Ggit.init();

		var start = location;

		try
		{
			if (start.query_file_type(FileQueryInfoFlags.NONE) == FileType.REGULAR)
			{
				var parent = start.get_parent();

				if (parent != null)
				{
					start = parent;
				}
			}
		}
		catch (Error e)
		{
			// Not stat-able; let discovery decide.
		}

		try
		{
			return Ggit.Repository.discover(start);
		}
		catch (Error e)
		{
			return null;
		}
	}

	protected override void startup()
	{
		base.startup();

		try
		{
			// Registers the Ggit -> Gitg type factory. Nothing that touches a
			// repository works before this runs.
			Gitg.init();
		}
		catch (Error e)
		{
			critical("failed to initialise: %s", e.message);
		}

		Hdy.init();

		// gitrl-z's own stylesheet. Gitg.init() loads the vendored
		// libgitg-style.css, but nothing loads ours, and without it the
		// command banner renders in the theme's ordinary background instead
		// of the fixed amber that marks it as a command that has not been
		// run (FR-125).
		var screen = Gdk.Screen.get_default();

		if (screen != null)
		{
			var provider = new Gtk.CssProvider();

			try
			{
				provider.load_from_resource("/io/github/li9i/gitrlz/ui/style.css");
				Gtk.StyleContext.add_provider_for_screen(
					screen, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
			}
			catch (Error e)
			{
				warning("could not load stylesheet: %s", e.message);
			}
		}

		add_action_entries(s_action_entries, this);

		set_accels_for_action("app.quit", {"<Primary>q"});
		set_accels_for_action("win.reload", {"F5"});
	}

	private const ActionEntry[] s_action_entries = {
		{"new-window", on_new_window_activated},
		{"about", on_about_activated},
		{"quit", on_quit_activated},
	};

	private static void on_new_window_activated(SimpleAction action, Variant? parameter)
	{
		var app = GLib.Application.get_default() as Gitrlz.Application;
		app.create_window(null);
	}

	private static void on_quit_activated(SimpleAction action, Variant? parameter)
	{
		var app = GLib.Application.get_default() as Gitrlz.Application;

		foreach (var window in app.get_windows())
		{
			window.close();
		}
	}

	private static void on_about_activated(SimpleAction action, Variant? parameter)
	{
		var app = GLib.Application.get_default() as Gitrlz.Application;

		string[] authors = {"alexandros filotheou"};

		// The application icon incorporates the Git logo, which is CC BY 3.0
		// and so requires attribution wherever the work is distributed. Left
		// untranslated: it names a person and a licence, neither of which
		// should vary by locale.
		string[] artists = {
			"alexandros filotheou",
			"Git logo by Jason Long — CC BY 3.0",
		};

		Gtk.show_about_dialog(app.get_active_window(),
		                      "program-name", "gitrl-z",
		                      "version", Config.PACKAGE_VERSION,
		                      "comments", _("Git reflog browser and reset preview"),
		                      "copyright", "Copyright \xc2\xa9 2026 alexandros filotheou",
		                      "license-type", Gtk.License.GPL_2_0,
		                      "logo-icon-name", Config.APPLICATION_ID,
		                      "authors", authors,
		                      "artists", artists,
		                      "website", Config.PACKAGE_URL,
		                      null);
	}

	protected override int command_line(ApplicationCommandLine cmd)
	{
		var arguments = cmd.get_arguments();
		unowned string[] argv = arguments;

		if (argv.length > 1)
		{
			File[] files = {};

			for (var i = 1; i < argv.length; i++)
			{
				files += File.new_for_commandline_arg(argv[i]);
			}

			open(files, "");
		}
		else
		{
			activate();
		}

		return 0;
	}

	protected override void activate()
	{
		// With no argument, open the repository containing the working
		// directory (FR-112). Outside one, or with --no-wd, the window opens
		// on the chooser instead (FR-100, FR-111).
		File? location = null;

		if (!s_no_wd)
		{
			location = discover_repository(File.new_for_path(Environment.get_current_dir()));
		}

		create_window(location);

		base.activate();
	}

	protected override void open(File[] files, string hint)
	{
		foreach (var file in files)
		{
			create_window(discover_repository(file));
		}
	}

	/**
	 * Open a window on a repository, or on the chooser when location is null.
	 */
	public void create_window(File? location)
	{
		var window = new Gitrlz.Window(this);

		if (location != null)
		{
			window.open_repository(location);
		}

		window.present();
	}
}

}

// ex:set ts=4 noet:
