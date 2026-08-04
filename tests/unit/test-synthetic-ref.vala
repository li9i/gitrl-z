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

private static void test_synthetic_branch_ref_has_no_native()
{
	// It must construct without a live git reference and render as a branch
	// pill: the label renderer reads only the short name and the ref type.
	var r = new Gitrlz.SyntheticBranchRef("gone-feature");

	assert_cmpstr(r.parsed_name.shortname, CompareOperator.EQ, "gone-feature");
	assert_true(r.parsed_name.rtype == Gitg.RefType.BRANCH);
}

public static int main(string[] args)
{
	Test.init(ref args);

	Test.add_func("/gitrlz/synthetic-ref/no-native", test_synthetic_branch_ref_has_no_native);

	return Test.run();
}

}

// ex:set ts=4 noet:
