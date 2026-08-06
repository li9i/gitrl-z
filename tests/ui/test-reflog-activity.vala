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

/*
 * The reflog activity's wiring (spec FR-147 to FR-153, P-FR-7 to P-FR-18).
 *
 * Model and widget state, not pixels. What these catch is everything between
 * the tested-in-isolation pieces: that a click toggles a branch into the plan,
 * that the plan reaches gitg's commit model as a substituted tip set, that
 * planned rows are marked and columns fit, and that the placeholders appear
 * where section 5 says they should.
 */

namespace GitrlzTest
{

private static Gtk.Application? s_app = null;

/**
 * A repository with branches, a merge and a stash, plus the activity showing
 * it. The caller owns both.
 */
private static Gitrlz.ReflogPaned activity_for(Repo repo) throws Error
{
	var location = Gitrlz.Application.discover_repository(repo.path);
	assert_nonnull(location);

	var paned = new Gitrlz.ReflogPaned();
	paned.repository = Gitrlz.Repository.open(location);

	return paned;
}

/** Whether `ids` holds the commit whose hex is `hex`. */
private static bool includes_oid(Ggit.OId[] ids, string hex)
{
	foreach (var id in ids)
	{
		if (id.to_string() == hex)
		{
			return true;
		}
	}

	return false;
}

/** Whether `names` holds `name`. */
private static bool has_label(string[] names, string name)
{
	foreach (var n in names)
	{
		if (n == name)
		{
			return true;
		}
	}

	return false;
}

private static Repo braided_repo() throws Error
{
	var repo = Repo.create();

	repo.commit("first");
	repo.commit("second");
	repo.branch("feature");
	repo.checkout("feature");
	repo.commit("feature work", "feature.txt");
	repo.checkout("main");
	repo.commit("main work", "main.txt");
	repo.merge("feature");

	return repo;
}

private static void test_refs_panel_contents()
{
	// P-FR-7, P-FR-8: `all`, the local branches sorted, and `stash` only
	// when there is one.
	try
	{
		var repo = braided_repo();
		var paned = activity_for(repo);

		var ids = paned.ref_ids();

		assert_cmpstr(ids[0], CompareOperator.EQ, "all");
		assert_true(ids.contains("feature"));
		assert_true(ids.contains("main"));
		assert_false(ids.contains("stash"));

		// feature sorts before main, case-insensitively.
		assert_true(ids.index_of("feature") < ids.index_of("main"));

		// At startup `all` is selected (P-FR-9).
		assert_cmpstr(paned.view, CompareOperator.EQ, "all");

		paned.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_checked_out_branch_is_marked()
{
	// The sidebar marks the branch HEAD is on, and nothing when detached.
	try
	{
		var repo = braided_repo();          // ends on main
		var paned = activity_for(repo);

		assert_true("checked out" in paned.ref_label("main"));
		assert_false("checked out" in paned.ref_label("feature"));

		paned.destroy();

		// Detached: no branch carries the mark.
		repo.checkout("HEAD~1");
		var detached = activity_for(repo);

		assert_false("checked out" in detached.ref_label("main"));
		assert_false("checked out" in detached.ref_label("feature"));

		detached.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_stash_entry_appears_only_with_a_stash()
{
	try
	{
		var repo = braided_repo();

		FileUtils.set_contents(repo.path.get_child("main.txt").get_path(), "dirty\n");
		repo.stash("wip");

		var paned = activity_for(repo);

		assert_true(paned.ref_ids().contains("stash"));

		paned.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_selecting_a_ref_reloads_the_list()
{
	// P-FR-10: `all` shows HEAD's reflog, a branch shows its own.
	try
	{
		var repo = braided_repo();
		var paned = activity_for(repo);

		var head_count = paned.list.entries.size;
		assert_cmpint(head_count, CompareOperator.GT, 0);

		assert_true(paned.select_ref("feature"));
		assert_cmpstr(paned.view, CompareOperator.EQ, "feature");

		// feature's own reflog is shorter than HEAD's, which also records
		// every checkout between branches.
		assert_cmpint(paned.list.entries.size, CompareOperator.GT, 0);
		assert_cmpint(paned.list.entries.size, CompareOperator.LT, head_count);

		foreach (var entry in paned.list.entries)
		{
			assert_true(entry.selector.has_prefix("feature@{"));
		}

		paned.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_empty_plan_shows_the_repository_tree()
{
	// With nothing planned, the lower pane shows the repository as it stands:
	// the graph over the real tips, no command, a caption marking it as the
	// present state.
	try
	{
		var repo = braided_repo();
		var paned = activity_for(repo);

		assert_cmpint(paned.plan_size, CompareOperator.EQ, 0);
		assert_cmpstr(paned.preview_state, CompareOperator.EQ, "graph");
		assert_cmpstr(paned.command, CompareOperator.EQ, "");

		// The real tips, unsubstituted: one per local branch.
		assert_cmpint(paned.included_tips.length, CompareOperator.EQ, 2);

		// A caption, and not the preview one.
		assert_true(paned.graph_caption != "");
		assert_false("after the command" in paned.graph_caption);

		paned.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_toggling_an_entry_builds_the_preview()
{
	// FR-148, FR-150: a click adds the row's branch to the plan, and the
	// substituted tip set reaches gitg's own commit model.
	try
	{
		var repo = braided_repo();
		var paned = activity_for(repo);

		assert_true(paned.toggle_entry(0));

		assert_cmpint(paned.plan_size, CompareOperator.EQ, 1);
		assert_cmpstr(paned.preview_state, CompareOperator.EQ, "graph");

		// One tip per local branch: the substitution replaces a tip, it does
		// not add one.
		assert_cmpint(paned.included_tips.length, CompareOperator.EQ, 2);

		// FR-149: the newest HEAD row belongs to main, the checked-out branch,
		// so its command is a hard reset rather than a branch -f.
		assert_true(paned.command.has_prefix("git reset --hard "));

		paned.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_toggling_the_same_row_clears_the_plan()
{
	// FR-148: clicking a planned row again removes it; an empty plan returns
	// to the placeholder.
	try
	{
		var repo = braided_repo();
		var paned = activity_for(repo);

		assert_true(paned.toggle_entry(0));
		assert_cmpint(paned.plan_size, CompareOperator.EQ, 1);

		assert_true(paned.toggle_entry(0));
		assert_cmpint(paned.plan_size, CompareOperator.EQ, 0);

		// An emptied plan falls back to the repository tree: a graph, no command.
		assert_cmpstr(paned.preview_state, CompareOperator.EQ, "graph");
		assert_cmpstr(paned.command, CompareOperator.EQ, "");

		paned.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_two_branch_plan()
{
	// FR-149, FR-150: a plan across two branches shows both moves, and both
	// substitutions reach the graph.
	try
	{
		var repo = braided_repo();
		var paned = activity_for(repo);

		// main, the checked-out branch, from the `all` view.
		assert_true(paned.toggle_entry(0));

		// feature, a non-current branch, from its own view.
		assert_true(paned.select_ref("feature"));
		assert_true(paned.toggle_entry(0));

		assert_cmpint(paned.plan_size, CompareOperator.EQ, 2);

		// A branch -f for the non-current branch, a reset --hard for the
		// current one.
		assert_true(paned.command.contains("git branch -f feature "));
		assert_true(paned.command.contains("git reset --hard "));

		// One tip per local branch, both substituted.
		assert_cmpint(paned.included_tips.length, CompareOperator.EQ, 2);

		paned.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_second_row_in_a_branch_moves_the_target()
{
	// FR-148: a different row in a branch already planned moves that branch's
	// target, it does not add a second entry.
	try
	{
		var repo = braided_repo();
		var paned = activity_for(repo);

		assert_true(paned.select_ref("feature"));
		assert_cmpint(paned.list.entries.size, CompareOperator.GE, 2);

		var second_sha = paned.list.entries[1].abbreviated_id;

		assert_true(paned.toggle_entry(0));
		assert_true(paned.toggle_entry(1));

		assert_cmpint(paned.plan_size, CompareOperator.EQ, 1);
		assert_true(paned.command.contains(second_sha));

		paned.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_preview_keeps_the_tree_and_moves_the_branch()
{
	// P-FR-18, FR-150: resetting a branch back keeps the whole tree on screen
	// (the abandoned commits stay, recoverable) and moves the branch's label
	// onto the commit it would reset to.
	try
	{
		var repo = Repo.create();

		var first = repo.commit("first");
		repo.commit("second");
		var third = repo.commit("third");

		var paned = activity_for(repo);

		// HEAD@{2} is the "first" commit; resetting main there.
		var entries = paned.list.entries;
		var index = -1;

		for (var i = 0; i < entries.size; i++)
		{
			if (entries[i].new_id.to_string() == first)
			{
				index = i;
				break;
			}
		}

		assert_cmpint(index, CompareOperator.GE, 0);
		assert_true(paned.toggle_entry(index));

		// The tree is whole: both the target `first` and the real tip `third`
		// are drawn, so nothing the reset would abandon disappears.
		assert_cmpint(paned.included_tips.length, CompareOperator.EQ, 2);
		assert_true(includes_oid(paned.included_tips, first));
		assert_true(includes_oid(paned.included_tips, third));
		assert_true(paned.command.contains(first.substring(0, 7)));

		// The label has moved: main is drawn at `first`, not at its real tip.
		var first_oid = new Ggit.OId.from_string(first);
		var third_oid = new Ggit.OId.from_string(third);
		assert_true(has_label(paned.preview_labels_for(first_oid), "main"));
		assert_false(has_label(paned.preview_labels_for(third_oid), "main"));

		// And the real repository is untouched: `third` is still main's tip.
		var tips = Gitrlz.Repository.branch_tips(paned.repository);
		assert_cmpstr(tips["main"].to_string(), CompareOperator.EQ, third);

		paned.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_graph_keeps_the_commit_the_session_started_on()
{
	// FR-169. A hard reset in a terminal beside the window leaves the opening
	// commit with no ref reaching it. The graph carries no label for it, and
	// it must still draw the commit: the position you came from is the one you
	// are most likely to want back.
	try
	{
		var repo = Repo.create();

		var first = repo.commit("first");
		repo.commit("second");
		var third = repo.commit("third");

		var paned = activity_for(repo);

		repo.reset(first);
		paned.reload();

		// main is back at `first`, and nothing reaches `third` any more. It is
		// in the tip set regardless, so the row stays on screen.
		assert_true(includes_oid(paned.included_tips, first));
		assert_true(includes_oid(paned.included_tips, third));

		paned.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_graph_pills_follow_a_ref_change_outside_the_window()
{
	// Gitg.Repository caches the ref-to-commit map on first use, so a reload
	// that does not clear it draws every branch pill where the branch was when
	// the window opened. The reflog list updates and the graph does not, which
	// reads as gitrl-z reporting a reset it can see in the list.
	try
	{
		var repo = Repo.create();

		var first = repo.commit("first");
		repo.commit("second");
		var third = repo.commit("third");

		var paned = activity_for(repo);

		var first_oid = new Ggit.OId.from_string(first);
		var third_oid = new Ggit.OId.from_string(third);

		assert_true(has_label(paned.preview_labels_for(third_oid), "main"));

		// A hard reset in a terminal beside the window.
		repo.reset(first);
		paned.reload();

		// main is drawn where it is now, and not where it was at open.
		assert_true(has_label(paned.preview_labels_for(first_oid), "main"));
		assert_false(has_label(paned.preview_labels_for(third_oid), "main"));

		paned.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_head_view_marks_the_row_the_session_opened_on()
{
	// FR-170. The mark answers "which row was I on when I opened this". With
	// no mark on the HEAD view there is nothing to measure the log against,
	// and the user has to remember the position instead of reading it.
	try
	{
		var repo = braided_repo();
		var paned = activity_for(repo);

		assert_cmpstr(paned.view, CompareOperator.EQ, "all");
		assert_cmpint(paned.list.entries.size, CompareOperator.GT, 1);

		// Nothing has happened since the window opened, so the newest row is
		// the row the session began at.
		assert_true(paned.list.row_is_start_mark(0));

		// One row and no more. Two marks would say the session began twice.
		for (var i = 1; i < paned.list.entries.size; i++)
		{
			assert_false(paned.list.row_is_start_mark(i));
		}

		paned.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_start_mark_drifts_down_as_the_log_grows()
{
	// FR-170. A commit made in a terminal beside the window pushes every row
	// down one. A mark pinned to the top row would follow the log forward and
	// point at the newest entry for ever, which is the one position the user
	// already has and never needs to be told about.
	try
	{
		var repo = Repo.create();

		repo.commit("first");
		var second = repo.commit("second");

		var paned = activity_for(repo);

		assert_true(paned.list.row_is_start_mark(0));

		// Work done outside the window: one new entry at the top.
		repo.commit("third");
		paned.reload();

		assert_false(paned.list.row_is_start_mark(0));
		assert_true(paned.list.row_is_start_mark(1));

		// And the marked row holds the entry that was newest at open, not
		// merely the row under the top one.
		assert_cmpstr(paned.list.entries[1].new_id.to_string(),
		              CompareOperator.EQ, second);

		paned.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_branch_view_marks_its_own_starting_row()
{
	// FR-170. Each ref keeps its own starting entry. Marking a branch view
	// from HEAD's entry would mark nothing here, because the merge HEAD stood
	// on at open is in no branch's own log, and a branch view with no mark
	// reads as a branch the session never touched.
	try
	{
		var repo = braided_repo();
		var paned = activity_for(repo);

		assert_true(paned.select_ref("feature"));
		assert_true(paned.list.row_is_start_mark(0));

		var opened_on = paned.list.entries[0].new_id.to_string();

		// Work on feature from a terminal beside the window.
		repo.checkout("feature");
		repo.commit("later feature work", "feature.txt", "later\n");
		paned.reload();

		assert_cmpstr(paned.view, CompareOperator.EQ, "feature");
		assert_false(paned.list.row_is_start_mark(0));
		assert_true(paned.list.row_is_start_mark(1));
		assert_cmpstr(paned.list.entries[1].new_id.to_string(),
		              CompareOperator.EQ, opened_on);

		paned.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_stash_view_marks_its_own_starting_row()
{
	// FR-170. A stash pushed from a terminal beside the window buries the one
	// that was on top at open. The stash the user came here to find is the one
	// they left behind, so the mark has to stay on it rather than move to the
	// newcomer.
	try
	{
		var repo = braided_repo();

		FileUtils.set_contents(repo.path.get_child("main.txt").get_path(), "dirty\n");
		repo.stash("work in progress");

		var paned = activity_for(repo);

		assert_true(paned.select_ref("stash"));
		assert_true(paned.list.row_is_start_mark(0));

		var opened_on = paned.list.entries[0].new_id.to_string();

		// A second stash, pushed outside the window.
		FileUtils.set_contents(repo.path.get_child("main.txt").get_path(), "dirtier\n");
		repo.stash("more work in progress");
		paned.reload();

		assert_cmpstr(paned.view, CompareOperator.EQ, "stash");
		assert_cmpint(paned.list.entries.size, CompareOperator.EQ, 2);
		assert_false(paned.list.row_is_start_mark(0));
		assert_true(paned.list.row_is_start_mark(1));
		assert_cmpstr(paned.list.entries[1].new_id.to_string(),
		              CompareOperator.EQ, opened_on);

		paned.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_branch_made_after_open_carries_no_mark()
{
	// FR-170. A branch that did not exist at open has no position the session
	// started from. A mark on its newest row would invent one, and tell the
	// user they had been somewhere they had never been.
	try
	{
		var repo = braided_repo();
		var paned = activity_for(repo);

		// A branch created in a terminal beside the window.
		repo.branch("later");
		paned.reload();

		assert_true(paned.select_ref("later"));
		assert_cmpint(paned.list.entries.size, CompareOperator.GT, 0);

		for (var i = 0; i < paned.list.entries.size; i++)
		{
			assert_false(paned.list.row_is_start_mark(i));
		}

		paned.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_search_takes_the_mark_off_screen_with_its_row()
{
	// FR-170. The filters decide what is on screen and a decoration does not
	// overrule them. A mark held back from a search would sit on some row the
	// search did match, and name the wrong entry as the one the session began
	// at.
	try
	{
		var repo = Repo.create();

		repo.commit("alpha");
		repo.commit("beta");
		repo.commit("omega");

		var paned = activity_for(repo);

		var all = paned.list.visible_count();
		assert_cmpint(all, CompareOperator.EQ, 3);
		assert_true(paned.list.row_is_start_mark(0));

		// "alpha" matches the older row only, so the marked row is filtered
		// out while the list still shows something.
		paned.search("alpha");

		var visible = paned.list.visible_count();
		assert_cmpint(visible, CompareOperator.GT, 0);
		assert_cmpint(visible, CompareOperator.LT, all);

		// The row keeps the mark in the model. What must not happen is the
		// filter letting it through, so every marked row has no view path.
		var marked = 0;

		for (var i = 0; i < paned.list.entries.size; i++)
		{
			if (paned.list.row_is_start_mark(i))
			{
				marked++;
				assert_null(paned.list.view_path_for(i));
			}
		}

		assert_cmpint(marked, CompareOperator.EQ, 1);

		paned.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_preview_writes_nothing()
{
	// NFR-4, the guarantee the whole product rests on. Building previews for
	// every entry must leave every ref exactly where it was.
	try
	{
		var repo = braided_repo();
		var before = repo.git({"for-each-ref", "--format=%(refname) %(objectname)"});

		var paned = activity_for(repo);

		// Every entry, not just one: a write would most likely happen on a
		// particular kind of row rather than on all of them.
		for (var i = 0; i < paned.list.entries.size; i++)
		{
			paned.toggle_entry(i);
		}

		var after = repo.git({"for-each-ref", "--format=%(refname) %(objectname)"});

		assert_cmpstr(after, CompareOperator.EQ, before);

		paned.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_empty_reflog_shows_placeholder()
{
	// P-FR-14, P-FR-27: an unborn HEAD opens normally and shows the
	// placeholder rather than an empty table.
	try
	{
		var dir = DirUtils.make_tmp("gitrlz-unborn-ui-XXXXXX");
		var repo = new Repo(File.new_for_path(dir));

		var paned = activity_for(repo);

		assert_cmpint(paned.list.entries.size, CompareOperator.EQ, 0);
		assert_cmpstr(paned.list_state, CompareOperator.EQ, "placeholder");

		paned.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_reload_preserves_the_plan()
{
	// FR-152: the plan survives a reload, matched on branch and commit rather
	// than on a row position, so a new entry at the top does not disturb it.
	try
	{
		var repo = braided_repo();
		var paned = activity_for(repo);

		assert_true(paned.toggle_entry(0));

		var planned_command = paned.command;
		assert_true(planned_command != "");

		// A new entry at the top shifts every row down by one.
		repo.commit("later work", "later.txt");
		paned.reload();

		assert_cmpint(paned.plan_size, CompareOperator.EQ, 1);
		assert_cmpstr(paned.command, CompareOperator.EQ, planned_command);
		assert_cmpstr(paned.preview_state, CompareOperator.EQ, "graph");

		paned.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_reload_drops_a_stale_plan_entry()
{
	// FR-152: an entry whose branch is deleted underneath is dropped on
	// reload, and the rest of the plan survives.
	try
	{
		var repo = braided_repo();
		var paned = activity_for(repo);

		// Plan main (all view) and feature (its own view).
		assert_true(paned.toggle_entry(0));
		assert_true(paned.select_ref("feature"));
		assert_true(paned.toggle_entry(0));
		assert_cmpint(paned.plan_size, CompareOperator.EQ, 2);

		// Delete feature from under the window. Its view falls back to `all`
		// (P-FR-9) and its plan entry is pruned; main stays.
		repo.git({"checkout", "--quiet", "main"});
		repo.git({"branch", "-D", "feature"});
		paned.reload();

		assert_cmpint(paned.plan_size, CompareOperator.EQ, 1);
		assert_true(paned.command.contains("git reset --hard "));
		assert_false(paned.command.contains("feature"));

		paned.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_reload_falls_back_when_ref_disappears()
{
	// P-FR-9: if the selected ref has gone, selection falls back to `all`.
	try
	{
		var repo = braided_repo();
		var paned = activity_for(repo);

		assert_true(paned.select_ref("feature"));
		assert_cmpstr(paned.view, CompareOperator.EQ, "feature");

		repo.git({"checkout", "--quiet", "main"});
		repo.git({"branch", "-D", "feature"});
		paned.reload();

		assert_cmpstr(paned.view, CompareOperator.EQ, "all");
		assert_false(paned.ref_ids().contains("feature"));

		paned.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_monitor_reloads_on_change()
{
	// FR-130: the window follows the repository. A commit made behind its
	// back must reach the list without anyone pressing F5.
	//
	// This waits on a real 400 ms debounce and a real file monitor, so it
	// runs a main loop rather than asserting immediately.
	try
	{
		var repo = braided_repo();
		var paned = activity_for(repo);

		var before = paned.list.entries.size;

		repo.commit("made behind its back", "behind.txt");

		var loop = new MainLoop();
		var reloaded = false;

		// Generous relative to the 400 ms debounce: this asserts that a
		// reload happens, not how quickly.
		var timeout = Timeout.add(5000, () => {
			loop.quit();
			return Source.REMOVE;
		});

		Timeout.add(100, () => {
			if (paned.list.entries.size > before)
			{
				reloaded = true;
				Source.remove(timeout);
				loop.quit();
				return Source.REMOVE;
			}

			return Source.CONTINUE;
		});

		loop.run();

		assert_true(reloaded);

		paned.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_working_tree_edits_are_ignored()
{
	// P-FR-25: only the git directory is watched, never the working tree,
	// so editing a file changes nothing until git records it.
	try
	{
		var repo = braided_repo();
		var paned = activity_for(repo);

		var before = paned.list.entries.size;

		FileUtils.set_contents(repo.path.get_child("main.txt").get_path(),
		                       "edited but not committed\n");

		var loop = new MainLoop();

		Timeout.add(1500, () => {
			loop.quit();
			return Source.REMOVE;
		});

		loop.run();

		assert_cmpint(paned.list.entries.size, CompareOperator.EQ, before);

		paned.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_search_filters_the_list()
{
	// FR-117: search filters by substring against the message and the SHA.
	try
	{
		var repo = braided_repo();
		var paned = activity_for(repo);

		var all = paned.list.visible_count();
		assert_cmpint(all, CompareOperator.GT, 1);

		// "merge" matches the merge commit's reflog message and little else.
		paned.search("merge");
		var filtered = paned.list.visible_count();

		assert_cmpint(filtered, CompareOperator.GT, 0);
		assert_cmpint(filtered, CompareOperator.LT, all);

		// Every visible row actually matches.
		var iter = Gtk.TreeIter();
		var model = paned.list.filtered_model;

		for (var ok = model.get_iter_first(out iter); ok; ok = model.iter_next(ref iter))
		{
			Value message;
			Value sha;
			model.get_value(iter, Gitrlz.ReflogColumn.MESSAGE, out message);
			model.get_value(iter, Gitrlz.ReflogColumn.SHA, out sha);

			assert_true(((string)message).down().contains("merge")
				|| ((string)sha).down().contains("merge"));
		}

		// Clearing the filter restores every row.
		paned.search("");
		assert_cmpint(paned.list.visible_count(), CompareOperator.EQ, all);

		paned.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_copied_state_follows_the_clipboard()
{
	// FR-143. The banner goes green when its command is copied, and green
	// means "this is what you would paste right now" rather than "a button
	// was pressed at some point". So it must follow the command as the plan
	// changes, and clear when a different command is copied.
	try
	{
		var repo = braided_repo();
		var paned = activity_for(repo);

		assert_true(paned.toggle_entry(0));
		var one_branch = paned.command;
		assert_false(paned.copied);

		paned.copy_command();
		assert_true(paned.copied);

		// Add a second branch: a different command, not the one on the
		// clipboard.
		assert_true(paned.select_ref("feature"));
		assert_cmpstr(paned.command, CompareOperator.EQ, one_branch);
		assert_true(paned.toggle_entry(0));

		var two_branch = paned.command;
		assert_cmpstr(two_branch, CompareOperator.NE, one_branch);
		assert_false(paned.copied);

		// Remove it again: back to the copied command, so green again.
		assert_true(paned.toggle_entry(0));
		assert_cmpstr(paned.command, CompareOperator.EQ, one_branch);
		assert_true(paned.copied);

		// Copying the two-branch command takes the green away from the one.
		assert_true(paned.toggle_entry(0));
		assert_cmpstr(paned.command, CompareOperator.EQ, two_branch);
		paned.copy_command();
		assert_true(paned.copied);

		assert_true(paned.toggle_entry(0));
		assert_cmpstr(paned.command, CompareOperator.EQ, one_branch);
		assert_false(paned.copied);

		paned.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

/**
 * The copied command must stay after gitrl-z closes.
 *
 * X11 holds a selection in the process that owns it. A command that gitrl-z
 * only puts on the clipboard goes away with the window, and the paste in the
 * terminal that follows gives nothing. The clipboard manager of the session
 * is the way to keep it: the application says that the content is storable,
 * and asks the manager to take a copy.
 *
 * This test is the manager. It holds the CLIPBOARD_MANAGER selection, and it
 * sees the SAVE_TARGETS request that the copy must send.
 */
private static void test_copy_offers_the_command_to_the_clipboard_manager()
{
	try
	{
		var repo = braided_repo();
		var paned = activity_for(repo);

		assert_true(paned.toggle_entry(0));
		assert_cmpstr(paned.command, CompareOperator.NE, "");

		// An empty window that holds CLIPBOARD_MANAGER is a clipboard manager,
		// as much as GTK needs. Without an owner of that selection, GTK finds
		// no manager on the display and keeps nothing.
		var manager = new Gtk.Window(Gtk.WindowType.TOPLEVEL);
		manager.realize();

		var selection = Gdk.Atom.intern("CLIPBOARD_MANAGER", false);
		var save_targets = Gdk.Atom.intern("SAVE_TARGETS", false);
		var asked = false;

		Gtk.selection_add_target(manager, selection, save_targets, 0);
		assert_true(Gtk.selection_owner_set(manager, selection, Gdk.CURRENT_TIME));

		manager.selection_request_event.connect((widget, ev) => {
			if (ev.selection == selection && ev.target == save_targets)
			{
				asked = true;
			}

			return false;
		});

		paned.copy_command();

		assert_true(asked);

		Gtk.selection_owner_set(null, selection, Gdk.CURRENT_TIME);

		manager.destroy();
		paned.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_uncommitted_warning()
{
	// FR-140. A hard reset destroys uncommitted work, and that is the one
	// thing gitrl-z shows you that the reflog cannot undo. It warns exactly
	// when the plan includes the checked-out branch, whose command is the
	// reset --hard.
	try
	{
		var repo = braided_repo();
		var paned = activity_for(repo);

		// Clean tree: no warning.
		assert_true(paned.toggle_entry(0));
		assert_true(paned.command.contains("reset --hard"));
		assert_cmpuint(paned.uncommitted_changes, CompareOperator.EQ, 0);
		assert_false(paned.warning_visible);

		// Modify a tracked file without committing it.
		FileUtils.set_contents(repo.path.get_child("main.txt").get_path(),
		                       "edited but not committed\n");

		// Toggling off and on rebuilds the preview, which re-reads the status.
		paned.toggle_entry(0);
		paned.toggle_entry(0);

		assert_cmpuint(paned.uncommitted_changes, CompareOperator.EQ, 1);
		assert_true(paned.warning_visible);

		paned.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_untracked_files_do_not_warn()
{
	// A hard reset leaves untracked files alone, so warning about them would
	// be crying wolf — and a repository with stray build output would show a
	// permanent red banner that people learn to ignore.
	try
	{
		var repo = braided_repo();

		FileUtils.set_contents(repo.path.get_child("untracked.txt").get_path(),
		                       "not tracked\n");

		var paned = activity_for(repo);

		assert_true(paned.toggle_entry(0));

		assert_cmpuint(paned.uncommitted_changes, CompareOperator.EQ, 0);
		assert_false(paned.warning_visible);

		paned.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_mid_operation_offers_the_abort()
{
	// FR-165, IC-164: while a git operation is in progress there is nothing to
	// reset until it is finished or aborted, so the preview offers the abort
	// command and plans nothing, even where a reset would otherwise appear.
	try
	{
		var repo = braided_repo();
		repo.begin_operation("MERGE_HEAD");

		var paned = activity_for(repo);

		// On open, mid-merge: the abort command and a note that names it.
		assert_cmpstr(paned.command, CompareOperator.EQ, "git merge --abort");
		assert_cmpstr(paned.preview_state, CompareOperator.EQ, "placeholder");
		assert_true("merge" in paned.preview_placeholder);

		// Clicking a row plans nothing and keeps offering the abort, not a reset.
		assert_true(paned.toggle_entry(0));
		assert_cmpint(paned.plan_size, CompareOperator.EQ, 0);
		assert_cmpstr(paned.command, CompareOperator.EQ, "git merge --abort");
		assert_false(paned.command.contains("reset --hard"));

		paned.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_mid_rebase_offers_abort_not_checkout()
{
	// The bug this fixes: a rebase detaches HEAD, so without giving the
	// operation precedence over the detached-HEAD case the preview offered
	// `git checkout -` in the middle of a rebase. It must offer the abort.
	try
	{
		var repo = braided_repo();
		repo.checkout("HEAD~1");          // detach, as a rebase does
		repo.begin_operation("rebase");   // and mark a rebase in progress

		var paned = activity_for(repo);

		assert_cmpstr(paned.command, CompareOperator.EQ, "git rebase --abort");
		assert_false(paned.command.contains("checkout -"));
		assert_true("rebase" in paned.preview_placeholder);

		paned.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_reflog_caption_names_the_log()
{
	// The refs panel says which row is selected; it does not say that the
	// list on the right is that ref's reflog. The caption does.
	try
	{
		var repo = braided_repo();
		var paned = activity_for(repo);

		// The `all` view reads logs/HEAD, which is a different log from any
		// branch's — so the caption says HEAD, not "all branches".
		assert_cmpstr(paned.view, CompareOperator.EQ, "all");
		assert_true("HEAD" in paned.reflog_caption);

		assert_true(paned.select_ref("feature"));
		assert_true("feature" in paned.reflog_caption);
		assert_false("HEAD" in paned.reflog_caption);

		paned.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_graph_caption_names_a_single_moved_branch()
{
	// FR-146: with one branch planned, the caption names it. Derived from the
	// plan, so it names the branch the command moves — here feature, from a
	// branch -f line rather than the sidebar.
	try
	{
		var repo = braided_repo();
		var paned = activity_for(repo);

		assert_true(paned.select_ref("feature"));
		assert_true(paned.toggle_entry(0));

		assert_true(paned.command.has_prefix("git branch -f feature "));
		assert_true("feature" in paned.graph_caption);
		assert_true("moved" in paned.graph_caption);

		paned.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_graph_caption_drops_the_name_for_many_branches()
{
	// FR-146 revisited: with two or more branches planned there is no single
	// branch to name, so the caption drops the clause.
	try
	{
		var repo = braided_repo();
		var paned = activity_for(repo);

		assert_true(paned.toggle_entry(0));
		assert_true(paned.select_ref("feature"));
		assert_true(paned.toggle_entry(0));

		assert_cmpint(paned.plan_size, CompareOperator.EQ, 2);
		assert_false("moved" in paned.graph_caption);
		assert_true("after execution of the command above" in paned.graph_caption);

		paned.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_graph_caption_hidden_without_a_graph()
{
	// A caption describing a graph that is not on screen is worse than no
	// caption. A stash row draws no graph (FR-142), so its caption is hidden.
	try
	{
		var repo = braided_repo();

		FileUtils.set_contents(repo.path.get_child("main.txt").get_path(), "dirty\n");
		repo.stash("work in progress");

		var paned = activity_for(repo);

		assert_true(paned.select_ref("stash"));
		assert_true(paned.toggle_entry(0));

		assert_cmpstr(paned.preview_state, CompareOperator.EQ, "placeholder");
		assert_cmpstr(paned.graph_caption, CompareOperator.EQ, "");

		paned.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_stash_offers_apply_not_reset()
{
	// FR-142. A stash entry is a commit, so the reset machinery would happily
	// offer to move a branch to it — which would put the stashed content on
	// the branch as committed history. A stash stays out of the plan.
	try
	{
		var repo = braided_repo();

		FileUtils.set_contents(repo.path.get_child("main.txt").get_path(), "dirty\n");
		repo.stash("work in progress");

		var paned = activity_for(repo);

		assert_true(paned.select_ref("stash"));
		assert_true(paned.toggle_entry(0));

		// The command restores files; it does not move a branch, and the plan
		// stays empty.
		assert_cmpint(paned.plan_size, CompareOperator.EQ, 0);
		assert_true(paned.command.has_prefix("git stash apply "));
		assert_true(paned.command.contains("stash@{0}"));
		assert_false(paned.command.contains("reset"));

		// And no graph, because applying a stash moves no ref.
		assert_cmpstr(paned.preview_state, CompareOperator.EQ, "placeholder");
		assert_false(paned.warning_visible);

		paned.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_branchless_row_is_not_togglable()
{
	// FR-148: a row from a detached-HEAD stretch belongs to no branch, so it
	// cannot be planned; clicking it shows a note and leaves the plan alone.
	try
	{
		var repo = Repo.create();
		repo.commit("first");
		var second = repo.commit("second");
		repo.git({"checkout", "--quiet", second});
		repo.commit("detached work", "detached.txt");
		repo.checkout("main");

		var paned = activity_for(repo);

		// Find a row the walk attributes to no branch.
		var branchless = -1;

		for (var i = 0; i < paned.list.entries.size; i++)
		{
			if (paned.list.branch_for_index(i) == null)
			{
				branchless = i;
				break;
			}
		}

		assert_cmpint(branchless, CompareOperator.GE, 0);

		assert_true(paned.toggle_entry(branchless));

		assert_cmpint(paned.plan_size, CompareOperator.EQ, 0);
		assert_cmpstr(paned.preview_state, CompareOperator.EQ, "placeholder");
		assert_cmpstr(paned.preview_placeholder, CompareOperator.EQ,
		              "No branch to move for this entry");

		paned.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_deleted_branch_offers_recreate()
{
	// FR-166, IC-165, IC-166: an entry attributed to a branch that no longer
	// exists offers to recreate it with `git branch <name> <sha>` (no -f),
	// draws the target commit with the branch's pill so it can be confirmed,
	// and raises no warning, because a recreate moves no ref and touches no
	// working tree.
	try
	{
		var repo = Repo.create();
		repo.commit("first");
		repo.branch("recover");
		repo.checkout("recover");
		var lost = repo.commit("work to recover", "recover.txt");
		repo.checkout("main");
		repo.delete_branch("recover");

		var paned = activity_for(repo);

		// HEAD's reflog is where the deleted branch's entry is attributed to it
		// (P-FR-16); the `all` view reads that log.
		assert_cmpstr(paned.view, CompareOperator.EQ, "all");

		var index = -1;

		for (var i = 0; i < paned.list.entries.size; i++)
		{
			if (paned.list.branch_for_index(i) == "recover")
			{
				index = i;
				break;
			}
		}

		assert_cmpint(index, CompareOperator.GE, 0);
		assert_true(paned.toggle_entry(index));

		// The recreate command, not a move: plain `git branch recover <sha>`
		// with no -f, because the branch no longer exists.
		assert_true(paned.command.contains("git branch recover "));
		assert_false(paned.command.contains("git branch -f recover "));

		// The target commit is drawn, so the operator can confirm the branch
		// would come back at the right place.
		assert_true(includes_oid(paned.included_tips, lost));

		// The recreated branch's pill is drawn at that commit, even though no
		// live ref reaches it (a synthesised label).
		assert_true(has_label(paned.preview_labels_for(new Ggit.OId.from_string(lost)), "recover"));

		// A recreate is not a move: nothing warns, and the caption does not say
		// the branch was moved.
		assert_false(paned.warning_visible);
		assert_false("moved" in paned.graph_caption);

		paned.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_deleted_branch_row_is_tinted()
{
	// FR-151, FR-166: the row of a deleted branch enters the plan like any
	// other row, thus it carries the tint that says it is planned. The branch
	// has no lane in the graph of the repository as it stands, and so no
	// colour of its own, but the tint does not depend on that: a planned row
	// with no mark reads as a click that did nothing.
	try
	{
		var repo = Repo.create();
		repo.commit("first");
		repo.branch("recover");
		repo.checkout("recover");
		repo.commit("work to recover", "recover.txt");
		repo.checkout("main");
		repo.delete_branch("recover");

		var paned = activity_for(repo);

		var index = -1;

		for (var i = 0; i < paned.list.entries.size; i++)
		{
			if (paned.list.branch_for_index(i) == "recover")
			{
				index = i;
				break;
			}
		}

		assert_cmpint(index, CompareOperator.GE, 0);
		assert_false(paned.list.row_is_tinted(index));

		assert_true(paned.toggle_entry(index));
		assert_true(paned.list.row_is_tinted(index));

		// And out again, so the tint follows the plan and is not a one-way
		// mark.
		assert_true(paned.toggle_entry(index));
		assert_false(paned.list.row_is_tinted(index));

		paned.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_planned_row_is_tinted_and_survives_a_ref_switch()
{
	// FR-151: a planned row carries a tint, keyed by branch and commit, so it
	// is marked again when its branch's reflog is shown after switching away.
	try
	{
		var repo = braided_repo();
		var paned = activity_for(repo);

		assert_true(paned.select_ref("feature"));
		assert_true(paned.toggle_entry(0));
		assert_true(paned.list.row_is_tinted(0));

		// Away to main, then back to feature: the row is tinted again.
		assert_true(paned.select_ref("main"));
		assert_true(paned.select_ref("feature"));
		assert_true(paned.list.row_is_tinted(0));

		paned.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_refs_panel_bolds_a_planned_branch()
{
	// A branch's name in the refs panel goes bold when it is in the plan, so
	// the left side shows which branches a reset is planned for. It follows the
	// plan, not the open view: it stays bold after switching away, and clears
	// when the branch is toggled back out.
	try
	{
		var repo = braided_repo();
		var paned = activity_for(repo);

		assert_true(paned.select_ref("feature"));
		assert_false(paned.ref_row_bold("feature"));

		assert_true(paned.toggle_entry(0));
		assert_true(paned.ref_row_bold("feature"));

		// Switching to another ref does not rebuild the panel, so the bold
		// stays: the plan still holds feature.
		assert_true(paned.select_ref("main"));
		assert_true(paned.ref_row_bold("feature"));

		// Toggle feature back out: no longer bold.
		assert_true(paned.select_ref("feature"));
		assert_true(paned.toggle_entry(0));
		assert_false(paned.ref_row_bold("feature"));

		paned.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private delegate bool Condition();

/** Run a main loop until `cond` holds or `timeout_ms` elapses. */
private static void wait_until(Condition cond, uint timeout_ms)
{
	var loop = new MainLoop();
	var elapsed = 0;
	var step = 50;

	Timeout.add(step, () => {
		if (cond() || elapsed >= timeout_ms)
		{
			loop.quit();
			return Source.REMOVE;
		}

		elapsed += step;
		return Source.CONTINUE;
	});

	loop.run();
}

private static void test_graph_keeps_its_scroll_across_a_toggle()
{
	// Toggling a row reloads the graph, which used to jerk it back to the top.
	// A repository tall enough to scroll: resetting main to its own tip leaves
	// the graph unchanged but still reloads it, so any jump is the bug, not a
	// content change.
	try
	{
		var repo = Repo.create();

		for (var i = 0; i < 60; i++)
		{
			repo.commit("c%d".printf(i), "f.txt", "%d\n".printf(i));
		}

		var paned = activity_for(repo);

		// Tall enough that the bottom preview pane has real height to scroll
		// in, past the vertical paned's resting position.
		var win = new Gtk.Window();
		win.set_default_size(700, 950);
		win.add(paned);
		win.show_all();

		// The graph loads asynchronously, after the model's initial wait.
		wait_until(() => paned.graph_row_count() >= 60, 8000);
		assert_cmpuint(paned.graph_row_count(), CompareOperator.GE, 60);

		// Scroll well down and let the tree view apply it.
		paned.scroll_graph_to_row(30);
		wait_until(() => paned.graph_top_row() >= 25, 3000);

		var before = paned.graph_top_row();
		assert_cmpint(before, CompareOperator.GT, 10);

		// Toggle the newest row: main resets to its own tip, an unchanged graph
		// that still reloads. The view must come back to where it was, not jump
		// to the top; a row of slack absorbs alignment rounding.
		assert_true(paned.toggle_entry(0));

		wait_until(() => {
			var t = paned.graph_top_row();
			return t >= before - 2 && t <= before + 2;
		}, 8000);

		var after = paned.graph_top_row();
		assert_cmpint(after, CompareOperator.GE, before - 2);
		assert_cmpint(after, CompareOperator.LE, before + 2);

		win.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_graph_columns_fit_on_open()
{
	// The graph's columns size to content once it loads (FR-147-like). The SHA
	// column shows the abbreviated hash, so it is narrow (well under the full
	// hash, and under the old fixed 120), while author and date are sized to
	// their own content.
	try
	{
		var repo = braided_repo();

		var paned = activity_for(repo);

		var win = new Gtk.Window();
		win.set_default_size(700, 700);
		win.add(paned);
		win.show_all();

		wait_until(() => paned.graph_column_width("author") > 50, 8000);

		// Abbreviated: a 7-character hash, far short of a full 40-character one.
		assert_cmpint(paned.graph_column_width("sha1"), CompareOperator.GT, 20);
		assert_cmpint(paned.graph_column_width("sha1"), CompareOperator.LT, 150);
		assert_cmpint(paned.graph_column_width("author"), CompareOperator.GT, 50);
		assert_cmpint(paned.graph_column_width("date"), CompareOperator.GT, 50);

		win.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_columns_fit_their_content()
{
	// FR-147: the Branch column fits the branch names shown, and grows for a
	// long name; the data columns are user-resizable.
	try
	{
		var short_repo = braided_repo();
		var short_paned = activity_for(short_repo);

		assert_true(short_paned.list.columns_resizable);
		var short_width = short_paned.list.branch_column_width;

		var long_repo = Repo.create();
		long_repo.commit("first");
		long_repo.branch("a-very-long-descriptive-feature-branch-name");
		long_repo.checkout("a-very-long-descriptive-feature-branch-name");
		long_repo.commit("work", "work.txt");

		var long_paned = activity_for(long_repo);
		var long_width = long_paned.list.branch_column_width;

		assert_cmpint(long_width, CompareOperator.GT, short_width);

		short_paned.destroy();
		long_paned.destroy();
		short_repo.remove();
		long_repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_keyboard_select_keeps_other_branches()
{
	// FR-148: keyboard arrow travel selects the landed row for the current
	// view's branch, exactly as a mouse click on that row would, and leaves
	// branches selected in other views alone. It must not wipe them.
	try
	{
		var repo = braided_repo();
		var paned = activity_for(repo);

		// A two-branch plan, built the way clicks do: main from the `all` view,
		// feature from its own.
		assert_true(paned.toggle_entry(0));
		assert_true(paned.select_ref("feature"));
		assert_true(paned.toggle_entry(0));
		assert_cmpint(paned.plan_size, CompareOperator.EQ, 2);

		// A keyboard select on feature keeps main: both branches stay planned.
		assert_true(paned.select_entry(0));
		assert_cmpint(paned.plan_size, CompareOperator.EQ, 2);
		assert_true(paned.command.contains("git branch -f feature "));
		assert_true(paned.command.contains("git reset --hard "));

		paned.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_keyboard_select_never_deselects()
{
	// FR-148: selecting the row already selected keeps it, where a second
	// click would toggle it off. Arrow travel tracks the cursor, it does not
	// deselect, so landing back on the planned row leaves the plan as it was.
	try
	{
		var repo = braided_repo();
		var paned = activity_for(repo);

		assert_true(paned.select_entry(0));
		assert_cmpint(paned.plan_size, CompareOperator.EQ, 1);

		assert_true(paned.select_entry(0));
		assert_cmpint(paned.plan_size, CompareOperator.EQ, 1);

		paned.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_head_view_plain_select_replaces_the_plan()
{
	// FR-148: in the HEAD view the top pane is a single selection. A plain
	// click or arrow travel (select_entry here) drops branches chosen
	// elsewhere and keeps only the landed row, while a Ctrl-click, which
	// toggles (toggle_entry here), is how several branches are gathered.
	try
	{
		var repo = braided_repo();
		var paned = activity_for(repo);

		// Gather two branches the Ctrl-click way: main from the HEAD view,
		// feature from its own.
		assert_true(paned.toggle_entry(0));
		assert_true(paned.select_ref("feature"));
		assert_true(paned.toggle_entry(0));
		assert_cmpint(paned.plan_size, CompareOperator.EQ, 2);

		// Back in the HEAD view, a plain selection replaces the plan with the
		// one landed row: feature is dropped, only main's reset remains.
		assert_true(paned.select_ref("all"));
		assert_true(paned.select_entry(0));

		assert_cmpint(paned.plan_size, CompareOperator.EQ, 1);
		assert_true(paned.command.contains("git reset --hard "));
		assert_false(paned.command.contains("git branch -f feature "));

		paned.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_head_view_click_deselects_the_same_row()
{
	// FR-148: in the HEAD view a plain click makes a row the sole selection,
	// and clicking that same row again clears it. This is what a mouse click
	// does (click_entry), unlike arrow travel, which tracks the cursor and
	// never deselects.
	try
	{
		var repo = braided_repo();
		var paned = activity_for(repo);

		// First click selects the row: its branch enters the plan.
		assert_true(paned.click_entry(0));
		assert_cmpint(paned.plan_size, CompareOperator.EQ, 1);

		// A second click on the same row deselects it: the plan empties and the
		// command clears with it.
		assert_true(paned.click_entry(0));
		assert_cmpint(paned.plan_size, CompareOperator.EQ, 0);
		assert_cmpstr(paned.command, CompareOperator.EQ, "");

		paned.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_head_view_arrow_travel_never_deselects()
{
	// FR-148: arrow travel (select_entry) is not a click. Landing on the same
	// row twice keeps it selected, where a second click would clear it.
	try
	{
		var repo = braided_repo();
		var paned = activity_for(repo);

		assert_true(paned.select_entry(0));
		assert_cmpint(paned.plan_size, CompareOperator.EQ, 1);

		assert_true(paned.select_entry(0));
		assert_cmpint(paned.plan_size, CompareOperator.EQ, 1);

		paned.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_detached_head_offers_the_way_back()
{
	// FR-148 / Option 3: with HEAD detached there is no branch to reset, so the
	// preview offers the way back on to a branch and plans nothing.
	try
	{
		var repo = braided_repo();
		repo.checkout("HEAD~1");   // detach HEAD onto an earlier commit

		var paned = activity_for(repo);

		// On open: the command is the reattach, the preview is the note (not a
		// graph), and it says why.
		assert_cmpstr(paned.command, CompareOperator.EQ, "git checkout -");
		assert_cmpstr(paned.preview_state, CompareOperator.EQ, "placeholder");
		assert_true("detached" in paned.preview_placeholder);

		// Clicking an entry plans nothing: reset is off until you are back on a
		// branch, and the reattach command stays put.
		assert_true(paned.click_entry(0));
		assert_cmpint(paned.plan_size, CompareOperator.EQ, 0);
		assert_cmpstr(paned.command, CompareOperator.EQ, "git checkout -");

		paned.destroy();
		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

public static int main(string[] args)
{
	Environment.set_variable("GSETTINGS_BACKEND", "memory", true);

	Test.init(ref args);

	if (!Gtk.init_check(ref args))
	{
		stdout.printf("1..0 # SKIP no display available\n");
		return 0;
	}

	try
	{
		Gitg.init();
	}
	catch (Error e)
	{
		stderr.printf("Gitg.init() failed: %s\n", e.message);
		return 1;
	}

	s_app = new Gtk.Application(Gitrlz.Config.APPLICATION_ID + ".Tests",
	                            ApplicationFlags.NON_UNIQUE);

	try
	{
		s_app.register();
	}
	catch (Error e)
	{
		stderr.printf("could not register test application: %s\n", e.message);
		return 1;
	}

	Test.add_func("/gitrlz/activity/refs-panel-contents", test_refs_panel_contents);
	Test.add_func("/gitrlz/activity/checked-out-branch-marked", test_checked_out_branch_is_marked);
	Test.add_func("/gitrlz/activity/stash-entry", test_stash_entry_appears_only_with_a_stash);
	Test.add_func("/gitrlz/activity/selecting-a-ref-reloads", test_selecting_a_ref_reloads_the_list);
	Test.add_func("/gitrlz/activity/empty-plan-shows-tree", test_empty_plan_shows_the_repository_tree);
	Test.add_func("/gitrlz/activity/toggling-builds-preview", test_toggling_an_entry_builds_the_preview);
	Test.add_func("/gitrlz/activity/toggling-clears-plan", test_toggling_the_same_row_clears_the_plan);
	Test.add_func("/gitrlz/activity/two-branch-plan", test_two_branch_plan);
	Test.add_func("/gitrlz/activity/second-row-moves-target", test_second_row_in_a_branch_moves_the_target);
	Test.add_func("/gitrlz/activity/keyboard-select-keeps-others", test_keyboard_select_keeps_other_branches);
	Test.add_func("/gitrlz/activity/keyboard-select-never-deselects", test_keyboard_select_never_deselects);
	Test.add_func("/gitrlz/activity/head-view-plain-select-replaces", test_head_view_plain_select_replaces_the_plan);
	Test.add_func("/gitrlz/activity/head-view-click-deselects", test_head_view_click_deselects_the_same_row);
	Test.add_func("/gitrlz/activity/head-view-arrow-never-deselects", test_head_view_arrow_travel_never_deselects);
	Test.add_func("/gitrlz/activity/detached-head-offers-way-back", test_detached_head_offers_the_way_back);
	Test.add_func("/gitrlz/activity/preview-keeps-tree-moves-branch", test_preview_keeps_the_tree_and_moves_the_branch);
	Test.add_func("/gitrlz/activity/preview-writes-nothing", test_preview_writes_nothing);
	Test.add_func("/gitrlz/activity/graph-pills-follow-ref-change", test_graph_pills_follow_a_ref_change_outside_the_window);
	Test.add_func("/gitrlz/activity/graph-keeps-start-commit", test_graph_keeps_the_commit_the_session_started_on);
	Test.add_func("/gitrlz/activity/start-mark-head-view", test_head_view_marks_the_row_the_session_opened_on);
	Test.add_func("/gitrlz/activity/start-mark-drifts-down", test_start_mark_drifts_down_as_the_log_grows);
	Test.add_func("/gitrlz/activity/start-mark-branch-view", test_branch_view_marks_its_own_starting_row);
	Test.add_func("/gitrlz/activity/start-mark-stash-view", test_stash_view_marks_its_own_starting_row);
	Test.add_func("/gitrlz/activity/start-mark-new-branch", test_branch_made_after_open_carries_no_mark);
	Test.add_func("/gitrlz/activity/start-mark-hidden-by-search", test_search_takes_the_mark_off_screen_with_its_row);
	Test.add_func("/gitrlz/activity/empty-reflog-placeholder", test_empty_reflog_shows_placeholder);
	Test.add_func("/gitrlz/activity/reload-preserves-plan", test_reload_preserves_the_plan);
	Test.add_func("/gitrlz/activity/reload-drops-stale", test_reload_drops_a_stale_plan_entry);
	Test.add_func("/gitrlz/activity/reload-ref-disappears", test_reload_falls_back_when_ref_disappears);
	Test.add_func("/gitrlz/activity/monitor-reloads", test_monitor_reloads_on_change);
	Test.add_func("/gitrlz/activity/working-tree-ignored", test_working_tree_edits_are_ignored);
	Test.add_func("/gitrlz/activity/search-filters", test_search_filters_the_list);
	Test.add_func("/gitrlz/activity/copied-state", test_copied_state_follows_the_clipboard);
	Test.add_func("/gitrlz/activity/copy-reaches-clipboard-manager", test_copy_offers_the_command_to_the_clipboard_manager);
	Test.add_func("/gitrlz/activity/uncommitted-warning", test_uncommitted_warning);
	Test.add_func("/gitrlz/activity/untracked-no-warning", test_untracked_files_do_not_warn);
	Test.add_func("/gitrlz/activity/mid-operation-abort", test_mid_operation_offers_the_abort);
	Test.add_func("/gitrlz/activity/mid-rebase-abort-not-checkout", test_mid_rebase_offers_abort_not_checkout);
	Test.add_func("/gitrlz/activity/reflog-caption", test_reflog_caption_names_the_log);
	Test.add_func("/gitrlz/activity/graph-caption-single", test_graph_caption_names_a_single_moved_branch);
	Test.add_func("/gitrlz/activity/graph-caption-many", test_graph_caption_drops_the_name_for_many_branches);
	Test.add_func("/gitrlz/activity/graph-caption-hidden", test_graph_caption_hidden_without_a_graph);
	Test.add_func("/gitrlz/activity/stash-offers-apply", test_stash_offers_apply_not_reset);
	Test.add_func("/gitrlz/activity/branchless-not-togglable", test_branchless_row_is_not_togglable);
	Test.add_func("/gitrlz/activity/deleted-branch-recreate", test_deleted_branch_offers_recreate);
	Test.add_func("/gitrlz/activity/deleted-branch-tinted", test_deleted_branch_row_is_tinted);
	Test.add_func("/gitrlz/activity/planned-row-tinted", test_planned_row_is_tinted_and_survives_a_ref_switch);
	Test.add_func("/gitrlz/activity/refs-bold-planned", test_refs_panel_bolds_a_planned_branch);
	Test.add_func("/gitrlz/activity/graph-keeps-scroll", test_graph_keeps_its_scroll_across_a_toggle);
	Test.add_func("/gitrlz/activity/graph-columns-fit", test_graph_columns_fit_on_open);
	Test.add_func("/gitrlz/activity/columns-fit", test_columns_fit_their_content);

	return Test.run();
}

}

// ex:set ts=4 noet:
