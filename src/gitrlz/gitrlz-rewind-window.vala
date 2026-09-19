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

private class RewindMove
{
	public string branch;
	public string now;
	public string after;

	public RewindMove(string branch, string now, string after)
	{
		this.branch = branch;
		this.now = now;
		this.after = after;
	}
}

public class RewindWindow : Gtk.Dialog
{
	private Gtk.Frame d_banner;
	private string d_command;
	private Gee.Map<string, RewindMove> d_moves;
	private Gtk.Menu? d_menu;
	private Gtk.SizeGroup d_branch_group;
	private Gtk.SizeGroup d_now_group;
	private Gtk.SizeGroup d_after_group;

	public signal void show_change(string branch, string now, string after);
	public signal void show_landing(string after);

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
		d_moves = new Gee.HashMap<string, RewindMove>();

		d_branch_group = new Gtk.SizeGroup(Gtk.SizeGroupMode.HORIZONTAL);
		d_now_group = new Gtk.SizeGroup(Gtk.SizeGroupMode.HORIZONTAL);
		d_after_group = new Gtk.SizeGroup(Gtk.SizeGroupMode.HORIZONTAL);

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

	public bool open_change(string branch)
	{
		if (!d_moves.has_key(branch))
		{
			return false;
		}

		var move = d_moves[branch];

		show_change(move.branch, move.now, move.after);

		return true;
	}

	public bool open_landing(string branch)
	{
		if (!d_moves.has_key(branch))
		{
			return false;
		}

		show_landing(d_moves[branch].after);

		return true;
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
		label.hexpand = true;
		label.selectable = true;
		label.get_style_context().add_class("gitrlz-command-text");

		var copy = new Gtk.Button.from_icon_name("edit-copy-symbolic",
		                                         Gtk.IconSize.MENU);
		copy.valign = Gtk.Align.CENTER;
		copy.relief = Gtk.ReliefStyle.NONE;
		copy.tooltip_text = _("Copy the command");
		copy.clicked.connect(copy_command);

		var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
		box.margin = 8;
		box.add(label);
		box.add(copy);

		d_banner = new Gtk.Frame(null);
		d_banner.get_style_context().add_class("gitrlz-command-banner");
		d_banner.add(box);

		return d_banner;
	}

	private Gtk.Widget build_table(Gee.List<string> branches,
	                               Gee.Map<string, Ggit.OId> tips,
	                               ResetPlan plan,
	                               string? current_branch)
	{
		var rows = new Gtk.Box(Gtk.Orientation.VERTICAL, 4);
		rows.margin = 8;

		rows.add(row_box(heading(_("Branch")), heading(_("Now")), heading(_("After"))));

		foreach (var branch in branches)
		{
			var now = tips.has_key(branch) ? abbreviate(tips[branch]) : "";
			var target = plan.target_for(branch);

			var after = cell(after_text(branch, tips, plan, current_branch),
			                 target != null);

			if (plan.is_deleted(branch) && branch != current_branch)
			{
				after.get_style_context().add_class("gitrlz-removal");
			}

			var row = row_box(cell(branch, false), cell(now, true), after);

			var moves = target != null
			            && tips.has_key(branch)
			            && !tips[branch].equal(target);

			rows.add(moves ? movable_row(branch, tips[branch], target, row) : row);
		}

		var scrolled = new Gtk.ScrolledWindow(null, null);
		scrolled.hexpand = true;
		scrolled.vexpand = true;
		scrolled.shadow_type = Gtk.ShadowType.IN;
		scrolled.add(rows);

		var title = new Gtk.Label(_("Where the branches move"));
		title.xalign = 0;

		var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 4);
		box.add(title);
		box.pack_start(scrolled, true, true, 0);

		return box;
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

	private Gtk.Widget movable_row(string branch,
	                               Ggit.OId now,
	                               Ggit.OId after,
	                               Gtk.Widget row)
	{
		var move = new RewindMove(branch, now.to_string(), after.to_string());

		d_moves[branch] = move;

		var box = new Gtk.EventBox();
		box.visible_window = false;
		box.tooltip_text = _("Double click to see the commit this branch lands on");
		box.add(row);

		box.button_press_event.connect((widget, event) => {
			if (event.type == Gdk.EventType.@2BUTTON_PRESS
			    && event.button == Gdk.BUTTON_PRIMARY)
			{
				return open_landing(move.branch);
			}

			if (event.type == Gdk.EventType.BUTTON_PRESS
			    && event.button == Gdk.BUTTON_SECONDARY)
			{
				popup_row_menu(widget, move, event);

				return true;
			}

			return false;
		});

		return box;
	}

	private void popup_row_menu(Gtk.Widget parent,
	                            RewindMove move,
	                            Gdk.EventButton event)
	{
		if (d_menu != null)
		{
			d_menu.destroy();
		}

		var menu = new Gtk.Menu();
		menu.attach_to_widget(parent, null);

		d_menu = menu;

		var landing = new Gtk.MenuItem.with_mnemonic(_("_Show the commit it lands on"));

		landing.activate.connect(() => {
			open_landing(move.branch);
		});

		menu.append(landing);

		var change = new Gtk.MenuItem.with_mnemonic(_("Show _every change the rewind makes"));

		change.activate.connect(() => {
			open_change(move.branch);
		});

		menu.append(change);

		menu.show_all();
		menu.popup_at_pointer(event);
	}

	private Gtk.Widget row_box(Gtk.Label branch, Gtk.Label now, Gtk.Label after)
	{
		d_branch_group.add_widget(branch);
		d_now_group.add_widget(now);
		d_after_group.add_widget(after);

		var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 16);
		box.add(branch);
		box.add(now);
		box.add(after);

		return box;
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

		d_banner.get_style_context().add_class("copied");
	}
}

}
