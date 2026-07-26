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
 * A branch label with no live git reference behind it (FR-166).
 *
 * The preview graph draws a branch's pill from a Gitg.Ref, which is normally a
 * wrapper over a real libgit2 reference. A branch that has been deleted has no
 * such reference, so to draw its pill where a `git branch <name> <sha>` would
 * recreate it, gitrl-z needs a label object that carries only a name.
 *
 * Gitg.RefBase is a concrete Gitg.Ref, and its parsed name is the only thing
 * the label renderer reads (Gitg.LabelRenderer takes the short name and the
 * ref type off parsed_name and nothing else). Setting d_parsed_name here means
 * that lookup never falls back to get_name() on an absent native reference, so
 * the object renders as a branch pill without one.
 */
public class SyntheticBranchRef : Gitg.RefBase
{
	public SyntheticBranchRef(string shortname)
	{
		d_parsed_name = new Gitg.ParsedRefName("refs/heads/" + shortname);
	}
}

}

// ex:set ts=4 noet:
