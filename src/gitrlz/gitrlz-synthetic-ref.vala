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
 * A branch label with no live git reference (FR-166).
 *
 * The preview graph draws the pill of a branch from a Gitg.Ref. Usually that
 * is a wrapper around a real libgit2 reference. A deleted branch has no such
 * reference. To draw its pill at the position where `git branch <name> <sha>`
 * would make it again, gitrl-z needs a label object that holds only a name.
 *
 * Gitg.RefBase is a concrete Gitg.Ref, and the label renderer reads only its
 * parsed name. (Gitg.LabelRenderer takes the short name and the ref type from
 * parsed_name, and nothing else.) This class sets d_parsed_name. Thus a lookup
 * does not use get_name() on an absent native reference, and the object
 * renders as a branch pill with no reference.
 */
public class SyntheticBranchRef : Gitg.RefBase
{
	public SyntheticBranchRef(string shortname)
	{
		d_parsed_name = new Gitg.ParsedRefName("refs/heads/" + shortname);
	}
}

/**
 * A label at a commit that names no git reference at all.
 *
 * The preview draws this to mark the commit that HEAD was on when gitrl-z
 * opened the repository. It is not a branch, not a tag, and nothing in git
 * knows about it. It is a note about the current session.
 *
 * The ref type is TAG, and the cause is the pill style. Gitg.LabelRenderer
 * takes the CSS class of a pill from the ref type alone, through its private
 * class_from_ref(). The four types give the four classes that style.css
 * colours: branch, remote, tag and stash. Thus a label with no type gets no
 * class, no fill and no border, and renders as loose text beside the real
 * pills. TAG is the one remaining type that already means "a name pinned to a
 * commit that does not move", which is what this mark is. It also draws in a
 * colour that no branch uses, thus the mark cannot be misread as a branch that
 * you could check out.
 *
 * Cost: a real tag on the same commit renders in the same colour. The user
 * then reads two orange pills, one of which is not a tag. The alternative was
 * a patch to the label renderer of gitg, and the vendored closure stays
 * byte-identical instead (NFR-5).
 */
public class SyntheticMarkerRef : Gitg.RefBase
{
	public SyntheticMarkerRef(string text)
	{
		d_parsed_name = new Gitg.ParsedRefName("refs/tags/" + text);
	}
}

}

// ex:set ts=4 noet:
