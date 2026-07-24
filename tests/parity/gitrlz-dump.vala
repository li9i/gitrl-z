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
 * Dump the Vala implementation's view of a repository's reflog, in the same
 * format as tests/parity/dump-python.py, for the parity audit.
 *
 * Prints one line per reflog entry:
 *
 *     <selector>\t<sha>\t<kind>\t<position>\t<branch>\t<message>
 *
 * No GTK, no display: this is the data layer only, so the comparison runs
 * anywhere the Python one does.
 */

namespace GitrlzDump
{

private static string position_name(Gitrlz.OperationPosition position)
{
	// The Python implementation's vocabulary, so the two dumps are
	// comparable without a translation table in the middle.
	switch (position)
	{
		case Gitrlz.OperationPosition.START: return "start";
		case Gitrlz.OperationPosition.MIDDLE: return "middle";
		case Gitrlz.OperationPosition.END: return "end";
		default: return "single";
	}
}

public static int main(string[] args)
{
	if (args.length < 2)
	{
		stderr.printf("usage: gitrlz-dump <repo> [ref]\n");
		return 2;
	}

	var ref_name = args.length > 2 ? args[2] : "HEAD";

	var location = Gitrlz.Application.discover_repository(File.new_for_path(args[1]));

	if (location == null)
	{
		stderr.printf("error: not a git repository: %s\n", args[1]);
		return 1;
	}

	Gitg.Repository repository;

	try
	{
		repository = Gitrlz.Repository.open(location);
	}
	catch (Error e)
	{
		stderr.printf("error: %s\n", e.message);
		return 1;
	}

	var entries = Gitrlz.Reflog.read(repository, ref_name);
	var current = Gitrlz.Repository.current_branch(repository);

	var operations = Gitrlz.ReflogAnnotations.classify_operations(entries);
	var branches = Gitrlz.ReflogAnnotations.attribute_branches(entries, current);

	for (var i = 0; i < entries.size; i++)
	{
		var entry = entries[i];

		stdout.printf("%s\t%s\t%s\t%s\t%s\t%s\n",
		              entry.selector,
		              entry.new_id != null ? entry.new_id.to_string() : "",
		              operations[i].kind,
		              position_name(operations[i].position),
		              branches[i] != null ? branches[i] : "",
		              entry.message);
	}

	return 0;
}

}

// ex:set ts=4 noet:
