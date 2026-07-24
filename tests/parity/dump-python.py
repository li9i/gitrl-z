#!/usr/bin/env python3
"""Dump the Python implementation's view of a repository's reflog.

HISTORICAL. The Python implementation was retired once the parity audit
passed, so this script no longer has modules to import and
will fail. It is kept because it is the evidence behind that decision:
`git show` the commit that retired the Python, restore src/gitrlz/*.py, and
tests/parity/compare.sh runs again.

Part of the parity audit. Prints one line per reflog entry:

    <selector>\t<sha>\t<kind>\t<position>\t<branch>\t<message>

Deliberately data, not pixels. Comparing screenshots would confirm the two
implementations look alike; comparing this confirms they *agree*, which is
the part that matters for declaring parity. Anything that differs here is a
behavioural change, whether or not it happens to be visible.

Imports only the pure and git-layer modules, never gitrlz.ui, so this runs
without PyGObject and without a display (NFR-5).

    tests/parity/dump-python.py <repo> [ref]
"""

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.realpath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "src"))

from gitrlz import gitcmd, reflog  # noqa: E402


def main():
    if len(sys.argv) < 2:
        print("usage: dump-python.py <repo> [ref]", file=sys.stderr)
        return 2

    repo = sys.argv[1]
    ref = sys.argv[2] if len(sys.argv) > 2 else "HEAD"

    entries, error = gitcmd.read_reflog(repo, ref)

    if error is not None:
        print("error: {}".format(error), file=sys.stderr)
        return 1

    # The Vala side seeds branch attribution with the current branch, so this
    # must too or the two disagree on entries older than the first checkout.
    current = gitcmd.current_branch(repo)

    operations = reflog.classify_operations(entries)
    branches = reflog.attribute_branches(entries, current)

    for index, entry in enumerate(entries):
        kind, position = operations[index]
        branch = branches[index] or ""

        print(
            "\t".join(
                [
                    entry.selector,
                    entry.sha_full,
                    kind,
                    position,
                    branch,
                    entry.message,
                ]
            )
        )

    return 0


if __name__ == "__main__":
    sys.exit(main())
