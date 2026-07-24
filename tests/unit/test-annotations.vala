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
 * Reflog list annotations: operations and branch attribution.
 *
 * A case-for-case port of the Python implementation's
 * tests/test_annotations.py, which is the specification of this behaviour.
 * Most cases are built from literal message lists; the last
 * reads a real repository so the literals stay honest about what git
 * actually writes (IC-8).
 */

namespace GitrlzTest
{

private const string[] REBASE_RUN = {
	"checkout: moving from side to main",
	"rebase (finish): returning to refs/heads/side",
	"rebase (pick): second pick",
	"rebase (pick): first pick",
	"rebase (start): checkout main",
	"checkout: moving from main to side"
};

/**
 * A ReflogEntry carrying only the field these functions read.
 */
private static Gee.List<Gitrlz.ReflogEntry> entries_for(string[] messages)
{
	var entries = new Gee.ArrayList<Gitrlz.ReflogEntry>();

	uint index = 0;

	foreach (var message in messages)
	{
		entries.add(new Gitrlz.ReflogEntry("HEAD", index++, null, null, message, null));
	}

	return entries;
}

private static void assert_kinds(Gitrlz.Operation[] ops, string[] expected)
{
	assert_cmpint(ops.length, CompareOperator.EQ, expected.length);

	for (var i = 0; i < expected.length; i++)
	{
		assert_cmpstr(ops[i].kind, CompareOperator.EQ, expected[i]);
	}
}

private static void assert_positions(Gitrlz.Operation[] ops, Gitrlz.OperationPosition[] expected)
{
	assert_cmpint(ops.length, CompareOperator.EQ, expected.length);

	for (var i = 0; i < expected.length; i++)
	{
		assert_true(ops[i].position == expected[i]);
	}
}

private static void assert_branches(string?[] got, string?[] expected)
{
	assert_cmpint(got.length, CompareOperator.EQ, expected.length);

	for (var i = 0; i < expected.length; i++)
	{
		assert_cmpstr(got[i], CompareOperator.EQ, expected[i]);
	}
}

private static void test_classify_single_entries()
{
	var ops = Gitrlz.ReflogAnnotations.classify_operations(entries_for({
		"commit: add parser",
		"commit (amend): add parser",
		"commit (initial): base",
		"checkout: moving from main to side",
		"merge topic: Merge made by the 'ort' strategy.",
		"reset: moving to HEAD~1"
	}));

	assert_kinds(ops, {"commit", "commit", "commit", "checkout", "merge", "reset"});
	assert_positions(ops, {
		Gitrlz.OperationPosition.SINGLE,
		Gitrlz.OperationPosition.SINGLE,
		Gitrlz.OperationPosition.SINGLE,
		Gitrlz.OperationPosition.SINGLE,
		Gitrlz.OperationPosition.SINGLE,
		Gitrlz.OperationPosition.SINGLE
	});
}

private static void test_classify_marks_a_rebase_run()
{
	var ops = Gitrlz.ReflogAnnotations.classify_operations(entries_for(REBASE_RUN));

	assert_kinds(ops, {"checkout", "rebase", "rebase", "rebase", "rebase", "checkout"});
	assert_positions(ops, {
		Gitrlz.OperationPosition.SINGLE,
		Gitrlz.OperationPosition.END,
		Gitrlz.OperationPosition.MIDDLE,
		Gitrlz.OperationPosition.MIDDLE,
		Gitrlz.OperationPosition.START,
		Gitrlz.OperationPosition.SINGLE
	});
}

private static void test_classify_rebase_without_a_finish()
{
	// An abandoned rebase closes at its last rebase row.
	var ops = Gitrlz.ReflogAnnotations.classify_operations(entries_for({
		"checkout: moving from side to main",
		"rebase (pick): first pick",
		"rebase (start): checkout main"
	}));

	assert_positions(ops, {
		Gitrlz.OperationPosition.SINGLE,
		Gitrlz.OperationPosition.END,
		Gitrlz.OperationPosition.START
	});
}

private static void test_classify_keeps_two_runs_separate()
{
	var ops = Gitrlz.ReflogAnnotations.classify_operations(entries_for({
		"rebase (finish): returning to refs/heads/b",
		"rebase (start): checkout main",
		"commit: unrelated",
		"rebase (finish): returning to refs/heads/a",
		"rebase (start): checkout main"
	}));

	assert_positions(ops, {
		Gitrlz.OperationPosition.END,
		Gitrlz.OperationPosition.START,
		Gitrlz.OperationPosition.SINGLE,
		Gitrlz.OperationPosition.END,
		Gitrlz.OperationPosition.START
	});
}

private static void test_classify_lone_start_stays_single()
{
	// A bracket needs at least two rows to bracket.
	var ops = Gitrlz.ReflogAnnotations.classify_operations(
		entries_for({"rebase (start): checkout main"}));

	assert_kinds(ops, {"rebase"});
	assert_positions(ops, {Gitrlz.OperationPosition.SINGLE});
}

private static void test_classify_empty()
{
	var ops = Gitrlz.ReflogAnnotations.classify_operations(
		new Gee.ArrayList<Gitrlz.ReflogEntry>());

	assert_cmpint(ops.length, CompareOperator.EQ, 0);
}

private static void test_attribute_follows_checkouts()
{
	var branches = Gitrlz.ReflogAnnotations.attribute_branches(entries_for({
		"commit: on main again",
		"checkout: moving from side to main",
		"commit: on side",
		"checkout: moving from main to side",
		"commit: on main"
	}));

	assert_branches(branches, {"main", "main", "side", "side", "main"});
}

private static void test_attribute_backfills_before_the_first_checkout()
{
	// Entries older than the first checkout take its from branch.
	var branches = Gitrlz.ReflogAnnotations.attribute_branches(entries_for({
		"checkout: moving from main to side",
		"commit: second",
		"commit (initial): first"
	}));

	assert_branches(branches, {"side", "main", "main"});
}

private static void test_attribute_uses_the_default_without_any_checkout()
{
	var entries = entries_for({"commit: second", "commit (initial): first"});

	assert_branches(Gitrlz.ReflogAnnotations.attribute_branches(entries, "trunk"),
	                {"trunk", "trunk"});
	assert_branches(Gitrlz.ReflogAnnotations.attribute_branches(entries),
	                {null, null});
}

private static void test_attribute_detached_head_gives_null()
{
	var branches = Gitrlz.ReflogAnnotations.attribute_branches(entries_for({
		"checkout: moving from a1b2c3d4e5f to main",
		"commit: while detached",
		"checkout: moving from main to a1b2c3d4e5f"
	}));

	assert_branches(branches, {"main", null, null});
}

private static void test_attribute_credits_a_rebase_run_to_its_branch()
{
	// A rebase replays with HEAD detached, so without this every row of the
	// run would read as detached rather than as work on the branch.
	var branches = Gitrlz.ReflogAnnotations.attribute_branches(entries_for(REBASE_RUN));

	assert_branches(branches, {"main", "side", "side", "side", "side", "side"});
}

private static void test_attribute_empty()
{
	var branches = Gitrlz.ReflogAnnotations.attribute_branches(
		new Gee.ArrayList<Gitrlz.ReflogEntry>());

	assert_cmpint(branches.length, CompareOperator.EQ, 0);
}

private static void test_against_a_real_reflog()
{
	// The literals above claim to be what git writes. This is what keeps
	// that claim honest, and it is now doubly worth having: the messages
	// arrive from libgit2 rather than from git's own output, so it also
	// confirms Ggit reports them unchanged (IC-103).
	try
	{
		var repo = Repo.create();

		repo.commit("base");
		repo.git({"checkout", "--quiet", "-b", "side"});
		// Distinct files so the rebase replays without a conflict.
		repo.commit("side work", "side.txt");
		repo.checkout("main");
		repo.commit("main work", "main.txt");
		repo.checkout("side");
		repo.git({"rebase", "--quiet", "main"});
		repo.checkout("main");

		var location = Gitrlz.Application.discover_repository(repo.path);
		assert_nonnull(location);

		var repository = Gitrlz.Repository.open(location);
		var entries = Gitrlz.Reflog.read(repository, "HEAD");

		assert_cmpint(entries.size, CompareOperator.GT, 0);

		var ops = Gitrlz.ReflogAnnotations.classify_operations(entries);

		var seen_rebase = false;
		var seen_checkout = false;
		var seen_commit = false;
		var seen_start = false;
		var seen_end = false;

		foreach (var op in ops)
		{
			if (op.kind == "rebase") seen_rebase = true;
			if (op.kind == "checkout") seen_checkout = true;
			if (op.kind == "commit") seen_commit = true;
			if (op.position == Gitrlz.OperationPosition.START) seen_start = true;
			if (op.position == Gitrlz.OperationPosition.END) seen_end = true;
		}

		assert_true(seen_rebase);
		assert_true(seen_checkout);
		assert_true(seen_commit);
		assert_true(seen_start);
		assert_true(seen_end);

		var branches = Gitrlz.ReflogAnnotations.attribute_branches(entries);
		assert_cmpint(branches.length, CompareOperator.EQ, entries.size);

		// The newest entry is the checkout back onto main.
		assert_cmpstr(branches[0], CompareOperator.EQ, "main");

		// Every row of the rebase run is credited to the branch it returns to.
		for (var i = 0; i < ops.length; i++)
		{
			if (ops[i].position != Gitrlz.OperationPosition.SINGLE)
			{
				assert_cmpstr(branches[i], CompareOperator.EQ, "side");
			}
		}

		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

private static void test_describe_distinguishes_branch_forms()
{
	// IC-8's kind is the first word before the colon, and two distinct
	// operations share `branch`. Describing a moved branch as "Branch
	// created" is wrong, and anything recommending `git branch -f` would
	// make that common.
	assert_cmpstr(
		Gitrlz.CellRendererOperations.describe(
			"branch", Gitrlz.OperationPosition.SINGLE, "branch: Created from main"),
		CompareOperator.EQ, "Branch created");

	assert_cmpstr(
		Gitrlz.CellRendererOperations.describe(
			"branch", Gitrlz.OperationPosition.SINGLE,
			"branch: Reset to 7c63e9f065a205331ea5522176b102fa42706a9f"),
		CompareOperator.EQ, "Branch moved");

	// The commit variants, distinguished for the same reason: an amend
	// rewrites the previous commit rather than adding one.
	assert_cmpstr(
		Gitrlz.CellRendererOperations.describe(
			"commit", Gitrlz.OperationPosition.SINGLE, "commit: add parser"),
		CompareOperator.EQ, "Commit");

	assert_cmpstr(
		Gitrlz.CellRendererOperations.describe(
			"commit", Gitrlz.OperationPosition.SINGLE, "commit (amend): add parser"),
		CompareOperator.EQ, "Commit (amended)");

	assert_cmpstr(
		Gitrlz.CellRendererOperations.describe(
			"commit", Gitrlz.OperationPosition.SINGLE, "commit (initial): base"),
		CompareOperator.EQ, "First commit");
}

private static void test_branch_force_message_form_is_real()
{
	// The literals above claim to be what git writes. Nothing in gitrl-z
	// generates a `git branch -f` today, so without this the test would be
	// asserting against my memory of git's output rather than git's output.
	try
	{
		var repo = Repo.create();

		var first = repo.commit("first");
		repo.commit("second");
		repo.branch("side");

		// Move a branch that is not checked out. `git branch -f` refuses the
		// current one, which is why `side` is used here.
		repo.git({"branch", "-f", "side", first});

		var location = Gitrlz.Application.discover_repository(repo.path);
		assert_nonnull(location);

		var repository = Gitrlz.Repository.open(location);
		var entries = Gitrlz.Reflog.read(repository, "side");

		assert_cmpint(entries.size, CompareOperator.GT, 0);

		// Newest first: the force-move is entry 0.
		var moved = entries[0];

		assert_cmpstr(Gitrlz.ReflogAnnotations.operation_kind(moved.message),
		              CompareOperator.EQ, "branch");
		assert_true(moved.message.contains("Reset to"));

		assert_cmpstr(
			Gitrlz.CellRendererOperations.describe(
				"branch", Gitrlz.OperationPosition.SINGLE, moved.message),
			CompareOperator.EQ, "Branch moved");

		// And the creation entry below it still reads as a creation.
		var created = entries[entries.size - 1];
		assert_true(created.message.contains("Created from"));

		assert_cmpstr(
			Gitrlz.CellRendererOperations.describe(
				"branch", Gitrlz.OperationPosition.SINGLE, created.message),
			CompareOperator.EQ, "Branch created");

		repo.remove();
	}
	catch (Error e)
	{
		Test.fail_printf("fixture failed: %s", e.message);
	}
}

public static int main(string[] args)
{
	Test.init(ref args);

	Test.add_func("/gitrlz/annotations/classify-single-entries", test_classify_single_entries);
	Test.add_func("/gitrlz/annotations/classify-marks-a-rebase-run", test_classify_marks_a_rebase_run);
	Test.add_func("/gitrlz/annotations/classify-rebase-without-a-finish", test_classify_rebase_without_a_finish);
	Test.add_func("/gitrlz/annotations/classify-keeps-two-runs-separate", test_classify_keeps_two_runs_separate);
	Test.add_func("/gitrlz/annotations/classify-lone-start-stays-single", test_classify_lone_start_stays_single);
	Test.add_func("/gitrlz/annotations/classify-empty", test_classify_empty);
	Test.add_func("/gitrlz/annotations/attribute-follows-checkouts", test_attribute_follows_checkouts);
	Test.add_func("/gitrlz/annotations/attribute-backfills", test_attribute_backfills_before_the_first_checkout);
	Test.add_func("/gitrlz/annotations/attribute-default-without-checkout", test_attribute_uses_the_default_without_any_checkout);
	Test.add_func("/gitrlz/annotations/attribute-detached-head", test_attribute_detached_head_gives_null);
	Test.add_func("/gitrlz/annotations/attribute-credits-a-rebase-run", test_attribute_credits_a_rebase_run_to_its_branch);
	Test.add_func("/gitrlz/annotations/attribute-empty", test_attribute_empty);
	Test.add_func("/gitrlz/annotations/against-a-real-reflog", test_against_a_real_reflog);
	Test.add_func("/gitrlz/annotations/describe-branch-forms", test_describe_distinguishes_branch_forms);
	Test.add_func("/gitrlz/annotations/branch-force-is-real", test_branch_force_message_form_is_real);

	return Test.run();
}

}

// ex:set ts=4 noet:
