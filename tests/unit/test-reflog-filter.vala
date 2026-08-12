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

namespace GitrlzTest
{

private static DateTime now()
{
	return new DateTime.local(2026, 7, 20, 12, 0, 0);
}

private static Gitrlz.ReflogEntry aged(string message, int minutes, bool dated = true)
{
	DateTime? when = dated ? now().add_minutes(-minutes) : null;
	return new Gitrlz.ReflogEntry("HEAD", 0, null, null, message, when);
}

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
	var flags = Gitrlz.ReflogFilter.visible(sample(), now(), 3600, 2, "");
	assert_true(flags[0]);
	assert_true(flags[1]);
	assert_false(flags[2]);
	assert_false(flags[4]);
	assert_cmpint(shown(flags), CompareOperator.EQ, 2);
}

private static void test_search_then_count()
{
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
