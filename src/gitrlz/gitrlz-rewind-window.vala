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

public class RewindWindow : Gtk.Dialog
{
	private string d_command;

	public RewindWindow(Gtk.Window parent,
	                    string moment,
	                    Gee.List<string> branches,
	                    Gee.Map<string, Ggit.OId> tips,
	                    ResetPlan plan,
	                    string? current_branch,
	                    string command)
	{
		Object(title: _("Rewind to %s").printf(moment),
		       transient_for: parent,
		       use_header_bar: 1,
		       destroy_with_parent: true);

		d_command = command;

		get_style_context().add_class("gitrlz-dialog");

		var bar = get_header_bar() as Gtk.HeaderBar;

		if (bar != null)
		{
			bar.show_close_button = true;
		}

		response.connect(() => { destroy(); });

		var content = get_content_area();
		content.orientation = Gtk.Orientation.VERTICAL;
		content.spacing = 8;
		content.margin = 12;

		content.add(build_command_view(command));
		content.add(build_table(branches, tips, plan, current_branch));

		resizable = true;
		set_default_size(760, 560);
		show_all();
	}

	public static string after_text(string branch,
	                                Gee.Map<string, Ggit.OId> tips,
	                                ResetPlan plan,
	                                string? current_branch)
	{
		var target = plan.target_for(branch);

		if (target != null)
		{
			return abbreviate(target);
		}

		if (plan.is_deleted(branch))
		{
			return branch == current_branch
				? _("kept, it is checked out")
				: _("removed");
		}

		return _("stays");
	}

	private static string abbreviate(Ggit.OId id)
	{
		var full = id.to_string();

		return full.length > 7 ? full.substring(0, 7) : full;
	}

	private Gtk.Widget build_command_view(string command)
	{
		var label = new Gtk.Label(command);
		label.xalign = 0;
		label.yalign = 0;
		label.hexpand = true;
		label.selectable = true;
		label.get_style_context().add_class("gitrlz-command-text");

		var copy = new Gtk.Button.from_icon_name("edit-copy-symbolic",
		                                         Gtk.IconSize.MENU);
		copy.valign = Gtk.Align.START;
		copy.relief = Gtk.ReliefStyle.NONE;
		copy.tooltip_text = _("Copy the command");
		copy.clicked.connect(copy_command);

		var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
		box.margin = 8;
		box.add(label);
		box.add(copy);

		var frame = new Gtk.Frame(null);
		frame.get_style_context().add_class("gitrlz-command-banner");
		frame.add(box);

		return frame;
	}

	private Gtk.Widget build_table(Gee.List<string> branches,
	                               Gee.Map<string, Ggit.OId> tips,
	                               ResetPlan plan,
	                               string? current_branch)
	{
		var grid = new Gtk.Grid();
		grid.column_spacing = 16;
		grid.row_spacing = 4;
		grid.margin = 8;

		grid.attach(heading(_("Branch")), 0, 0, 1, 1);
		grid.attach(heading(_("Now")), 1, 0, 1, 1);
		grid.attach(heading(_("After")), 2, 0, 1, 1);

		var row = 1;

		foreach (var branch in branches)
		{
			grid.attach(cell(branch, false), 0, row, 1, 1);
			grid.attach(cell(tips.has_key(branch) ? abbreviate(tips[branch]) : "", true),
			            1, row, 1, 1);

			var after = after_text(branch, tips, plan, current_branch);
			var widget = cell(after, plan.target_for(branch) != null);

			if (plan.is_deleted(branch) && branch != current_branch)
			{
				widget.get_style_context().add_class("gitrlz-removal");
			}

			grid.attach(widget, 2, row, 1, 1);

			row++;
		}

		var scrolled = new Gtk.ScrolledWindow(null, null);
		scrolled.hexpand = true;
		scrolled.vexpand = true;
		scrolled.shadow_type = Gtk.ShadowType.IN;
		scrolled.add(grid);

		return scrolled;
	}

	private Gtk.Label cell(string text, bool monospace)
	{
		var label = new Gtk.Label(text);
		label.xalign = 0;

		if (monospace)
		{
			label.get_style_context().add_class("gitrlz-command-text");
		}

		return label;
	}

	private Gtk.Label heading(string text)
	{
		var label = new Gtk.Label(text);
		label.xalign = 0;
		label.get_style_context().add_class("gitrlz-caption");

		return label;
	}

	private void copy_command()
	{
		var clipboard = Gtk.Clipboard.get_default(get_display());

		if (clipboard == null)
		{
			return;
		}

		clipboard.set_text(d_command, -1);
		clipboard.set_can_store(null);
		clipboard.store();
	}
}

}
