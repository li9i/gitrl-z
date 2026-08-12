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

public class Monitor : Object
{
	private const uint DEBOUNCE_MS = 400;

	private Gee.List<FileMonitor> d_monitors;
	private uint d_timeout;

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
