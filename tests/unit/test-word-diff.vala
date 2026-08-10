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
 * The word marks inside a changed line.
 *
 * Pure logic: two strings in, byte ranges out. The tests read the marked text
 * back out of the line rather than asserting on offsets, because the offsets
 * are a means and the marked words are the behaviour.
 */

namespace GitrlzTest
{

/** The text that each span covers, joined by `|` so one assert can read it. */
private static string marked(string line, Gitrlz.WordSpan[] spans)
{
	var parts = new string[spans.length];

	for (var i = 0; i < spans.length; i++)
	{
		parts[i] = line.substring(spans[i].start, spans[i].end - spans[i].start);
	}

	return string.joinv("|", parts);
}

private static void test_a_changed_word_in_a_long_line()
{
	Gitrlz.WordSpan[] old_spans;
	Gitrlz.WordSpan[] new_spans;

	var old_line = "The quick brown fox jumps over the lazy dog";
	var new_line = "The quick brown cat jumps over the lazy dog";

	assert_true(Gitrlz.WordDiff.refine(old_line, new_line,
	                                   out old_spans, out new_spans));

	assert_cmpstr(marked(old_line, old_spans), CompareOperator.EQ, "fox");
	assert_cmpstr(marked(new_line, new_spans), CompareOperator.EQ, "cat");
}

private static void test_an_added_word_marks_only_that_word()
{
	Gitrlz.WordSpan[] old_spans;
	Gitrlz.WordSpan[] new_spans;

	var old_line = "call(first, third)";
	var new_line = "call(first, second, third)";

	assert_true(Gitrlz.WordDiff.refine(old_line, new_line,
	                                   out old_spans, out new_spans));

	assert_cmpint(old_spans.length, CompareOperator.EQ, 0);
	assert_cmpstr(marked(new_line, new_spans), CompareOperator.EQ, "second,");
}

private static void test_a_mark_does_not_end_on_whitespace()
{
	Gitrlz.WordSpan[] old_spans;
	Gitrlz.WordSpan[] new_spans;

	var old_line = "alpha beta gamma delta";
	var new_line = "alpha one two gamma delta";

	assert_true(Gitrlz.WordDiff.refine(old_line, new_line,
	                                   out old_spans, out new_spans));

	// One mark over the changed phrase, and not one for each word of it.
	assert_cmpstr(marked(new_line, new_spans), CompareOperator.EQ, "one two");
	assert_cmpstr(marked(old_line, old_spans), CompareOperator.EQ, "beta");
}

private static void test_punctuation_is_its_own_word()
{
	Gitrlz.WordSpan[] old_spans;
	Gitrlz.WordSpan[] new_spans;

	var old_line = "value = compute(a, b);";
	var new_line = "value = compute(a, c);";

	assert_true(Gitrlz.WordDiff.refine(old_line, new_line,
	                                   out old_spans, out new_spans));

	assert_cmpstr(marked(old_line, old_spans), CompareOperator.EQ, "b");
	assert_cmpstr(marked(new_line, new_spans), CompareOperator.EQ, "c");
}

private static void test_two_unrelated_lines_take_no_marks()
{
	Gitrlz.WordSpan[] old_spans;
	Gitrlz.WordSpan[] new_spans;

	// A rewrite, not an edit. Marks over the whole line would say no more
	// than the line tint already says.
	assert_false(Gitrlz.WordDiff.refine("import os", "def main(argv):",
	                                    out old_spans, out new_spans));

	assert_cmpint(old_spans.length, CompareOperator.EQ, 0);
	assert_cmpint(new_spans.length, CompareOperator.EQ, 0);
}

private static void test_marks_land_on_the_right_bytes_past_a_wide_character()
{
	Gitrlz.WordSpan[] old_spans;
	Gitrlz.WordSpan[] new_spans;

	// The offsets are byte offsets, thus a character outside ASCII before the
	// change must not move the mark.
	var old_line = "καλημέρα alpha beta";
	var new_line = "καλημέρα alpha gamma";

	assert_true(Gitrlz.WordDiff.refine(old_line, new_line,
	                                   out old_spans, out new_spans));

	assert_cmpstr(marked(old_line, old_spans), CompareOperator.EQ, "beta");
	assert_cmpstr(marked(new_line, new_spans), CompareOperator.EQ, "gamma");
}

private static void test_the_flat_form_carries_the_same_offsets()
{
	// The diff renderer is vendored gitg code and cannot name Gitrlz.WordSpan,
	// so it asks for the spans as a flat array of start and end offsets. The two
	// forms have to agree, or the marks land on the wrong bytes.
	Gitrlz.WordSpan[] old_spans;
	Gitrlz.WordSpan[] new_spans;
	int[] old_flat;
	int[] new_flat;

	var old_line = "one two three four";
	var new_line = "one six three four";

	assert_true(Gitrlz.WordDiff.refine(old_line, new_line,
	                                   out old_spans, out new_spans));
	assert_true(Gitrlz.WordDiff.refine_flat(old_line, new_line,
	                                        out old_flat, out new_flat));

	assert_cmpint(old_flat.length, CompareOperator.EQ, old_spans.length * 2);
	assert_cmpint(new_flat.length, CompareOperator.EQ, new_spans.length * 2);

	for (var i = 0; i < old_spans.length; i++)
	{
		assert_cmpint(old_flat[i * 2], CompareOperator.EQ, old_spans[i].start);
		assert_cmpint(old_flat[i * 2 + 1], CompareOperator.EQ, old_spans[i].end);
	}

	for (var i = 0; i < new_spans.length; i++)
	{
		assert_cmpint(new_flat[i * 2], CompareOperator.EQ, new_spans[i].start);
		assert_cmpint(new_flat[i * 2 + 1], CompareOperator.EQ, new_spans[i].end);
	}
}

private static void test_the_flat_form_declines_where_refine_declines()
{
	// A pair with nothing in common takes no marks in either form, and the
	// renderer then leaves the line with its tint.
	int[] old_flat;
	int[] new_flat;

	assert_false(Gitrlz.WordDiff.refine_flat("alpha beta gamma", "nothing alike here",
	                                         out old_flat, out new_flat));

	assert_cmpint(old_flat.length, CompareOperator.EQ, 0);
	assert_cmpint(new_flat.length, CompareOperator.EQ, 0);
}

private static void test_an_identical_line_takes_no_marks()
{
	Gitrlz.WordSpan[] old_spans;
	Gitrlz.WordSpan[] new_spans;

	assert_false(Gitrlz.WordDiff.refine("same line", "same line",
	                                    out old_spans, out new_spans));
}

private static void test_an_empty_line_takes_no_marks()
{
	Gitrlz.WordSpan[] old_spans;
	Gitrlz.WordSpan[] new_spans;

	assert_false(Gitrlz.WordDiff.refine("", "something",
	                                    out old_spans, out new_spans));
}

public static int main(string[] args)
{
	Test.init(ref args);

	Test.add_func("/gitrlz/word-diff/changed-word", test_a_changed_word_in_a_long_line);
	Test.add_func("/gitrlz/word-diff/added-word", test_an_added_word_marks_only_that_word);
	Test.add_func("/gitrlz/word-diff/phrase-is-one-mark", test_a_mark_does_not_end_on_whitespace);
	Test.add_func("/gitrlz/word-diff/punctuation", test_punctuation_is_its_own_word);
	Test.add_func("/gitrlz/word-diff/unrelated-lines", test_two_unrelated_lines_take_no_marks);
	Test.add_func("/gitrlz/word-diff/wide-characters", test_marks_land_on_the_right_bytes_past_a_wide_character);
	Test.add_func("/gitrlz/word-diff/flat-form-agrees", test_the_flat_form_carries_the_same_offsets);
	Test.add_func("/gitrlz/word-diff/flat-form-declines", test_the_flat_form_declines_where_refine_declines);
	Test.add_func("/gitrlz/word-diff/identical-lines", test_an_identical_line_takes_no_marks);
	Test.add_func("/gitrlz/word-diff/empty-line", test_an_empty_line_takes_no_marks);

	return Test.run();
}

}

// ex:set ts=4 noet:
