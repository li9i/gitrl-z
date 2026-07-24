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
 * The reflog visibility rule (spec IC-160, IC-161), as pure logic.
 *
 * Time is injected as `now`, so the "older than the window" branch is
 * exercised here rather than in the UI suite, where a fixture's entries are
 * all seconds old. This file is the authority on the combine rule of FR-158
 * and its edge cases.
 */

namespace GitrlzTest
{

/** A fixed reference instant every case measures against. */
private static DateTime now()
{
	return new DateTime.local(2026, 7, 20, 12, 0, 0);
}

/** An entry `minutes` before now(), or undated when `dated` is false. */
private static Gitrlz.ReflogEntry aged(string message, int minutes, bool dated = true)
{
	DateTime? when = dated ? now().add_minutes(-minutes) : null;
	return new Gitrlz.ReflogEntry("HEAD", 0, null, null, message, when);
}

/**
 * Five entries, newest first: now, 5 min, 30 min, 2 h, and one undated.
 * The messages let a search pick out "commit", which matches the last two.
 */
private static Gee.List<Gitrlz.ReflogEntry> sample()
{
	var list = new Gee.ArrayList<Gitrlz.ReflogEntry>();
	list.add(aged("reset moving to HEAD", 0));
	list.add(aged("checkout main", 5));
	list.add(aged("rebase pick", 30));
	list.add(aged("commit main work", 120));
	list.add(aged("commit feature", 0, false));
	return list;
}

private static int shown(bool[] flags)
{
	var n = 0;
	foreach (var f in flags)
	{
		if (f) n++;
	}
	return n;
}

private static void test_any_time_shows_all()
{
	var flags = Gitrlz.ReflogFilter.visible(sample(), now(), 0, 0, "");
	assert_cmpint(shown(flags), CompareOperator.EQ, 5);
}

private static void test_ten_minute_window()
{
	// Cutoff is now - 10 min: the entries at 0 and 5 min pass, 30 min and 2 h
	// do not, and the undated one always does (FR-159).
	var flags = Gitrlz.ReflogFilter.visible(sample(), now(), 600, 0, "");
	assert_true(flags[0]);
	assert_true(flags[1]);
	assert_false(flags[2]);
	assert_false(flags[3]);
	assert_true(flags[4]);
	assert_cmpint(shown(flags), CompareOperator.EQ, 3);
}

private static void test_one_hour_window()
{
	// Cutoff is now - 60 min: 0, 5 and 30 min pass; 2 h does not; undated does.
	var flags = Gitrlz.ReflogFilter.visible(sample(), now(), 3600, 0, "");
	assert_false(flags[3]);
	assert_true(flags[4]);
	assert_cmpint(shown(flags), CompareOperator.EQ, 4);
}

private static void test_count_keeps_newest()
{
	var flags = Gitrlz.ReflogFilter.visible(sample(), now(), 0, 2, "");
	assert_true(flags[0]);
	assert_true(flags[1]);
	assert_false(flags[2]);
	assert_cmpint(shown(flags), CompareOperator.EQ, 2);
}

private static void test_count_over_size_keeps_all()
{
	var flags = Gitrlz.ReflogFilter.visible(sample(), now(), 0, 99, "");
	assert_cmpint(shown(flags), CompareOperator.EQ, 5);
}

private static void test_count_zero_keeps_all()
{
	var flags = Gitrlz.ReflogFilter.visible(sample(), now(), 0, 0, "");
	assert_cmpint(shown(flags), CompareOperator.EQ, 5);
}

private static void test_window_then_count()
{
	// One hour keeps four (0, 5, 30 min, undated); the cap of 2 then keeps the
	// newest two of those, at 0 and 5 min (FR-158).
	var flags = Gitrlz.ReflogFilter.visible(sample(), now(), 3600, 2, "");
	assert_true(flags[0]);
	assert_true(flags[1]);
	assert_false(flags[2]);
	assert_false(flags[4]);
	assert_cmpint(shown(flags), CompareOperator.EQ, 2);
}

private static void test_search_then_count()
{
	// "commit" matches the 2 h entry and the undated one; the cap of 1 keeps
	// the newer of the two matches, the 2 h entry.
	var one = Gitrlz.ReflogFilter.visible(sample(), now(), 0, 0, "commit");
	assert_cmpint(shown(one), CompareOperator.EQ, 2);

	var capped = Gitrlz.ReflogFilter.visible(sample(), now(), 0, 1, "commit");
	assert_true(capped[3]);
	assert_false(capped[4]);
	assert_cmpint(shown(capped), CompareOperator.EQ, 1);
}

private static void test_parse_count()
{
	assert_cmpuint(Gitrlz.ReflogFilter.parse_count("All"), CompareOperator.EQ, 0);
	assert_cmpuint(Gitrlz.ReflogFilter.parse_count("Last 10"), CompareOperator.EQ, 10);
	assert_cmpuint(Gitrlz.ReflogFilter.parse_count("25"), CompareOperator.EQ, 25);
	assert_cmpuint(Gitrlz.ReflogFilter.parse_count(""), CompareOperator.EQ, 0);
	assert_cmpuint(Gitrlz.ReflogFilter.parse_count("0"), CompareOperator.EQ, 0);
	assert_cmpuint(Gitrlz.ReflogFilter.parse_count("abc"), CompareOperator.EQ, 0);
	assert_cmpuint(Gitrlz.ReflogFilter.parse_count("  7 entries"), CompareOperator.EQ, 7);
}

public static int main(string[] args)
{
	Test.init(ref args);

	Test.add_func("/reflog-filter/any-time-shows-all", test_any_time_shows_all);
	Test.add_func("/reflog-filter/ten-minute-window", test_ten_minute_window);
	Test.add_func("/reflog-filter/one-hour-window", test_one_hour_window);
	Test.add_func("/reflog-filter/count-keeps-newest", test_count_keeps_newest);
	Test.add_func("/reflog-filter/count-over-size-keeps-all", test_count_over_size_keeps_all);
	Test.add_func("/reflog-filter/count-zero-keeps-all", test_count_zero_keeps_all);
	Test.add_func("/reflog-filter/window-then-count", test_window_then_count);
	Test.add_func("/reflog-filter/search-then-count", test_search_then_count);
	Test.add_func("/reflog-filter/parse-count", test_parse_count);

	return Test.run();
}

}

// ex:set ts=4 noet:
