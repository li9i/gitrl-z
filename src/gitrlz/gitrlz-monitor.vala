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
 * Follows a repository as it changes (spec FR-130, FR-131, P-FR-25).
 *
 * What is watched: the git directory itself, plus its `logs`,
 * `logs/refs/heads` and `refs/heads` subdirectories. Between them these cover
 * every way the display can go stale — HEAD and packed-refs in the git
 * directory, the reflogs, and the branch tips.
 *
 * Only the git directory is watched, never the working tree, so editing a
 * file changes nothing until git records it.
 *
 * A directory that does not exist yet, such as `logs` in a repository with no
 * commits, is simply not watched; it gets picked up at the next reload rather
 * than being missed for the life of the process.
 *
 * Debounce: one git command touches several files, and a rebase far more. A
 * change schedules the reload 400 ms ahead and each further change pushes it
 * back, so the window reloads once per operation rather than once per file.
 *
 * gitg has a Gitg.RecursiveMonitor for this, but it lives in gitg's
 * application sources rather than in libgitg and is not part of the vendored
 * closure; watching four known directories is less machinery than pulling it
 * in and recursing over an entire .git.
 */
public class Monitor : Object
{
	private const uint DEBOUNCE_MS = 400;

	private Gee.List<FileMonitor> d_monitors;
	private uint d_timeout;

	/** Emitted once per settled burst of changes. */
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
	 * Watch a repository's git directory. Replaces any previous watch.
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
			// A directory that cannot be watched degrades to manual refresh
			// rather than taking anything down: F5 and the menu entry still
			// work (FR-131).
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
