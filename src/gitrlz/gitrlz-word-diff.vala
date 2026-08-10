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
 * A range of bytes inside one line of a diff.
 *
 * The offsets are byte offsets into the line text, which is what
 * string.substring and the rest of the GLib string calls take. `end` is one
 * past the last byte of the range.
 */
public struct WordSpan
{
	int start;
	int end;
}

/**
 * The parts of a changed line that actually changed.
 *
 * A unified diff works in whole lines. One corrected word in a long sentence
 * marks the full sentence, and the reader is left to find the word. meld marks
 * the word as well as the line, and this class computes those marks for the
 * diff view of gitrl-z.
 *
 * refine() pairs a removed line with the added line that replaced it, cuts
 * both into words, and reports the words that are not common to the two. The
 * match is a longest common subsequence over the words, which is what the
 * line-level diff of git does over lines.
 */
public class WordDiff : Object
{
	private enum TokenKind
	{
		WORD,
		SPACE,
		OTHER
	}

	private struct Token
	{
		int start;
		int end;
		TokenKind kind;
	}

	/**
	 * The longest pair of lines that takes a refinement.
	 *
	 * The word match costs the product of the two token counts. A minified
	 * script or a data file holds lines of thousands of tokens, where that
	 * product is large and the marks are of no use anyway. Such a line keeps
	 * its line tint and gets no word marks.
	 */
	private const int MAX_TOKENS = 400;

	/**
	 * The part of the shorter line that must be common for a refinement.
	 *
	 * Two lines that share almost nothing are a rewrite and not an edit. There
	 * the marks would cover the whole line, which the line tint already says,
	 * and a pairing of unrelated lines would mark words at random. Thus a
	 * refinement needs at least this part of the words of the shorter line to
	 * be common. The value is a divisor: 3 is a third.
	 */
	private const int MIN_COMMON_PART = 3;

	/**
	 * The words of `old_text` and `new_text` that are not common to the two.
	 *
	 * Returns false when the two lines take no refinement, either because they
	 * are too long to match or because they have too little in common to be
	 * one edit. The caller then shows the line tint alone. The spans are empty
	 * in that case.
	 */
	public static bool refine(string old_text,
	                          string new_text,
	                          out WordSpan[] old_spans,
	                          out WordSpan[] new_spans)
	{
		old_spans = {};
		new_spans = {};

		var old_tokens = tokenise(old_text);
		var new_tokens = tokenise(new_text);

		if (old_tokens.length == 0 || new_tokens.length == 0
		    || old_tokens.length > MAX_TOKENS || new_tokens.length > MAX_TOKENS)
		{
			return false;
		}

		var old_words = texts_of(old_text, old_tokens);
		var new_words = texts_of(new_text, new_tokens);

		var old_common = new bool[old_tokens.length];
		var new_common = new bool[new_tokens.length];

		match(old_words, new_words, old_common, new_common);

		var common = common_count(old_tokens, old_common);
		var shorter = int.min(word_count(old_tokens), word_count(new_tokens));

		if (common == 0 || common * MIN_COMMON_PART < shorter)
		{
			return false;
		}

		old_spans = spans_of(old_tokens, old_common);
		new_spans = spans_of(new_tokens, new_common);

		return old_spans.length > 0 || new_spans.length > 0;
	}

	/** The number of tokens that carry text and are common to both lines. */
	private static int common_count(Token[] tokens, bool[] common)
	{
		var count = 0;

		for (var i = 0; i < tokens.length; i++)
		{
			if (common[i] && tokens[i].kind != TokenKind.SPACE)
			{
				count++;
			}
		}

		return count;
	}

	private static TokenKind kind_of(unichar c)
	{
		if (c.isspace())
		{
			return TokenKind.SPACE;
		}

		return c.isalnum() || c == '_' ? TokenKind.WORD : TokenKind.OTHER;
	}

	/**
	 * Marks the tokens that the two lines have in common.
	 *
	 * This is the standard longest common subsequence: a table of the match
	 * length from each pair of positions to the end of the two lines, then one
	 * walk forward through the table that takes the matches.
	 */
	private static void match(string[] old_words,
	                          string[] new_words,
	                          bool[] old_common,
	                          bool[] new_common)
	{
		var n = old_words.length;
		var m = new_words.length;

		var lcs = new int[n + 1, m + 1];

		for (var i = n - 1; i >= 0; i--)
		{
			for (var j = m - 1; j >= 0; j--)
			{
				lcs[i, j] = old_words[i] == new_words[j]
					? lcs[i + 1, j + 1] + 1
					: int.max(lcs[i + 1, j], lcs[i, j + 1]);
			}
		}

		var i = 0;
		var j = 0;

		while (i < n && j < m)
		{
			if (old_words[i] == new_words[j])
			{
				old_common[i] = true;
				new_common[j] = true;
				i++;
				j++;
			}
			else if (lcs[i + 1, j] >= lcs[i, j + 1])
			{
				i++;
			}
			else
			{
				j++;
			}
		}
	}

	/**
	 * The spans that cover the tokens which are not common.
	 *
	 * Tokens beside each other join into one span, so that a changed phrase
	 * takes one mark and not one for each word. A span does not begin or end
	 * on whitespace: a mark that reaches into the gap before the next word
	 * reads as a change to that gap.
	 *
	 * Whitespace never holds a span open or closed. Every gap of one space is
	 * the same text, thus the match calls them all common, and a phrase of two
	 * changed words would break into one mark for each word.
	 */
	private static WordSpan[] spans_of(Token[] tokens, bool[] common)
	{
		var spans = new WordSpan[] {};

		var first = -1;
		var last = -1;

		for (var i = 0; i <= tokens.length; i++)
		{
			var changed = i < tokens.length
				&& (!common[i] || tokens[i].kind == TokenKind.SPACE);

			if (changed)
			{
				if (tokens[i].kind == TokenKind.SPACE && first < 0)
				{
					// Whitespace cannot open a span. It joins one that is
					// already open, and then only if a further token follows.
					continue;
				}

				if (first < 0)
				{
					first = i;
				}

				if (tokens[i].kind != TokenKind.SPACE)
				{
					last = i;
				}

				continue;
			}

			if (first >= 0 && last >= first)
			{
				spans += WordSpan() { start = tokens[first].start, end = tokens[last].end };
			}

			first = -1;
			last = -1;
		}

		return spans;
	}

	/** The text of each token, for the match. */
	private static string[] texts_of(string text, Token[] tokens)
	{
		var words = new string[tokens.length];

		for (var i = 0; i < tokens.length; i++)
		{
			words[i] = text.substring(tokens[i].start, tokens[i].end - tokens[i].start);
		}

		return words;
	}

	/**
	 * Cuts a line into words, runs of whitespace, and single other characters.
	 *
	 * A punctuation character is its own token, so that a change from `foo()`
	 * to `foo(bar)` marks `bar` and not the whole call. Whitespace stays in
	 * the token list, because the spans are byte ranges of the original line
	 * and the tokens must cover it with no gap.
	 */
	private static Token[] tokenise(string text)
	{
		var tokens = new Token[] {};

		var index = 0;
		unichar c;

		while (true)
		{
			var start = index;

			if (!text.get_next_char(ref index, out c))
			{
				break;
			}

			var kind = kind_of(c);

			if (kind == TokenKind.OTHER)
			{
				tokens += Token() { start = start, end = index, kind = kind };
				continue;
			}

			var end = index;
			var probe = index;
			unichar next;

			while (text.get_next_char(ref probe, out next) && kind_of(next) == kind)
			{
				end = probe;
			}

			index = end;
			tokens += Token() { start = start, end = end, kind = kind };
		}

		return tokens;
	}

	/** The number of tokens that carry text rather than whitespace. */
	private static int word_count(Token[] tokens)
	{
		var count = 0;

		foreach (var token in tokens)
		{
			if (token.kind != TokenKind.SPACE)
			{
				count++;
			}
		}

		return count;
	}
}

}

// ex:set ts=4 noet:
