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

public struct WordSpan
{
	int start;
	int end;
}

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

	private const int MAX_TOKENS = 400;

	private const int MIN_COMMON_PART = 3;

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

	public static bool refine_flat(string old_text,
	                               string new_text,
	                               out int[] old_spans,
	                               out int[] new_spans)
	{
		WordSpan[] old_found;
		WordSpan[] new_found;

		if (!refine(old_text, new_text, out old_found, out new_found))
		{
			old_spans = {};
			new_spans = {};

			return false;
		}

		old_spans = flattened(old_found);
		new_spans = flattened(new_found);

		return true;
	}

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

	private static int[] flattened(WordSpan[] spans)
	{
		var flat = new int[spans.length * 2];

		for (var i = 0; i < spans.length; i++)
		{
			flat[i * 2] = spans[i].start;
			flat[i * 2 + 1] = spans[i].end;
		}

		return flat;
	}

	private static TokenKind kind_of(unichar c)
	{
		if (c.isspace())
		{
			return TokenKind.SPACE;
		}

		return c.isalnum() || c == '_' ? TokenKind.WORD : TokenKind.OTHER;
	}

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

	private static string[] texts_of(string text, Token[] tokens)
	{
		var words = new string[tokens.length];

		for (var i = 0; i < tokens.length; i++)
		{
			words[i] = text.substring(tokens[i].start, tokens[i].end - tokens[i].start);
		}

		return words;
	}

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
