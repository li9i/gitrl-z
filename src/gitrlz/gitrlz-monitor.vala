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
 * Follows a repository while it changes (spec FR-130, FR-131, P-FR-25).
 *
 * This class monitors the git directory, and also its `logs`,
 * `logs/refs/heads` and `refs/heads` subdirectories. Together these cover
 * each condition that can make the display stale: HEAD and packed-refs in the
 * git directory, the reflogs, and the branch tips.
 *
 * It monitors only the git directory, and never the working tree. Thus a
 * change to a file has no effect until git records it.
 *
 * A directory that does not exist, such as `logs` in a repository with no
 * commits, has no monitor. The next reload finds it. It is not lost for the
 * full life of the process.
 *
 * Debounce: one git command changes several files, and a rebase changes many
 * more. A change schedules the reload 400 ms later, and each subsequent
 * change delays it again. Thus the window reloads one time for each
 * operation, and not one time for each file.
 *
 * gitg has a Gitg.RecursiveMonitor for this. But it is in the application
 * sources of gitg and not in libgitg, thus it is not in the vendored closure.
 * Four known directories need less code than that class and a recursion
 * through a full .git.
 */
public class Monitor : Object
{
	private const uint DEBOUNCE_MS = 400;

	private Gee.List<FileMonitor> d_monitors;
	private uint d_timeout;

	/** Emitted one time for each group of changes, after the changes stop. */
	public signal void changed();

	public bool enabled { get; set; default = true; }

	construct
	{
		d_monitors = new Gee.ArrayList<FileMonitor>();
	}

	~Monitor()
	{
		stop();
	}

	public void stop()
	{
		if (d_timeout != 0)
		{
			Source.remove(d_timeout);
			d_timeout = 0;
		}

		foreach (var monitor in d_monitors)
		{
			monitor.cancel();
		}

		d_monitors.clear();
	}

	/**
	 * Monitors the git directory of a repository. Replaces any previous
	 * monitor.
	 */
	public void watch(File? git_dir)
	{
		stop();

		if (git_dir == null)
		{
			return;
		}

		watch_directory(git_dir);
		watch_directory(git_dir.get_child("logs"));
		watch_directory(git_dir.get_child("logs").get_child("refs").get_child("heads"));
		watch_directory(git_dir.get_child("refs").get_child("heads"));
	}

	private void watch_directory(File directory)
	{
		if (!directory.query_exists())
		{
			return;
		}

		try
		{
			var monitor = directory.monitor_directory(FileMonitorFlags.NONE, null);
			monitor.changed.connect(on_changed);
			d_monitors.add(monitor);
		}
		catch (Error e)
		{
			// If a directory cannot have a monitor, the user reloads
			// manually. Nothing stops. F5 and the menu entry continue to
			// operate (FR-131).
			warning("could not watch %s: %s", directory.get_path(), e.message);
		}
	}

	private void on_changed(File file, File? other, FileMonitorEvent event)
	{
		if (!enabled)
		{
			return;
		}

		if (d_timeout != 0)
		{
			Source.remove(d_timeout);
		}

		d_timeout = Timeout.add(DEBOUNCE_MS, () => {
			d_timeout = 0;
			changed();
			return Source.REMOVE;
		});
	}
}

}

// ex:set ts=4 noet:
