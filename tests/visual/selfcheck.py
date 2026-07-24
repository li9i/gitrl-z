#!/usr/bin/env python3
"""Assert that the geometry comparison rejects a deliberately wrong capture.

A test suite that cannot fail is not a test suite. tests/visual/test-parity.sh
rescales a real capture by 130% — which changes lane spacing, dot size and row
height exactly as a renderer regression would — and runs this. If the
comparison passes the real capture but this does not fail, the measurement is
not measuring anything, and every green run since it was written has been
meaningless.

Worth having concretely, not just in principle: the measurement code went
through four revisions before it worked, and two of them reported confident,
entirely wrong numbers. This is the guard against the fifth.

    selfcheck.py <reference.json> <perturbed.json>
"""

import json
import sys

COMPARED = ("lane_spacing", "dot_radius", "row_height")


def main():
    if len(sys.argv) < 3:
        print("usage: selfcheck.py <reference.json> <perturbed.json>", file=sys.stderr)
        return 2

    reference = json.load(open(sys.argv[1]))
    perturbed = json.load(open(sys.argv[2]))

    differing = [k for k in COMPARED if reference.get(k) != perturbed.get(k)]

    if not differing:
        print("  SELF-CHECK FAILED: a 130% rescale went undetected")
        print("  the measurement is not measuring anything; treat every pass as void")
        return 1

    print("  perturbation detected in: {} (good)".format(", ".join(differing)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
