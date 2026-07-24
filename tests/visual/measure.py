#!/usr/bin/env python3
"""Extract lane geometry from a screenshot of a commit graph.

Plan step 21, spec 6.3.1. The visual suite compares gitg and gitrl-z on
*geometry*, not pixels: the two show different commit sets, so a pixel diff
would compare nothing meaningful, but lane spacing, dot radius, row height and
lane colours are readable from two different graphs.

What this measures, and why each one:

    lane_spacing   centre-to-centre distance between adjacent lane columns
    dot_radius     radius of a commit dot
    row_height     vertical distance between adjacent commit rows
    lane_colours   the RGB the renderer actually used, per lane

These are the properties FR-102 delegates to vendored code. If the vendored
renderers really are gitg's, every one of them matches exactly; if a patch or
a CSS divergence perturbs the look, they do not.

The technique is the one the Python implementation used to derive gitg's
constants by hand (P-FR-21): scan a row for runs of saturated colour, profile
a dot's edge. Those recorded values — 14 px lane spacing, 4 px dot radius —
are what tests/visual/test-parity.sh checks this code against before trusting
it to judge anything.

    measure.py <image.png> [--json]
"""

import json
import sys
from collections import Counter

try:
    from PIL import Image
except ImportError:  # pragma: no cover
    print("python3-pil is required", file=sys.stderr)
    raise SystemExit(2)


# gitg's lane palette, copied from src/vendor-gitg/libgitg/gitg-color.vala.
#
# Matching against the palette rather than against "looks saturated" is what
# makes this measurement trustworthy. The earlier heuristic could not tell a
# lane dot from Adwaita's selection blue or from a blue ref pill, and reported
# eight lanes of #3584e4 on a graph whose lanes are plainly yellow and green.
# The palette is not a guess about what a lane looks like — it is the
# definition of one.
PALETTE = [
    (196, 160, 0),
    (78, 154, 6),
    (206, 92, 0),
    (32, 74, 135),
    (108, 53, 102),
    (164, 0, 0),
    (138, 226, 52),
    (252, 175, 62),
    (114, 159, 207),
    (252, 233, 79),
    (136, 138, 133),
    (173, 127, 168),
    (233, 185, 110),
    (239, 41, 41),
]

# Antialiasing and the dot's darker outline shift a pixel a little off the
# nominal colour, so an exact match would find only the dot's core.
TOLERANCE = 24


def palette_index(pixel):
    """The palette slot a pixel belongs to, or None."""
    r, g, b = pixel[:3]

    best = None
    best_distance = None

    for index, (pr, pg, pb) in enumerate(PALETTE):
        distance = abs(r - pr) + abs(g - pg) + abs(b - pb)

        if distance <= TOLERANCE * 3 and (best_distance is None or distance < best_distance):
            best = index
            best_distance = distance

    return best


def is_saturated(pixel):
    """Whether a pixel is part of a lane, i.e. drawn in a palette colour."""
    return palette_index(pixel) is not None


def load(path):
    return Image.open(path).convert("RGB")


# A commit dot is a small filled circle. Anything much wider than this on a
# scanline is not a dot: a selection highlight spans the whole list, and a
# header bar spans the window. Without an upper bound those swamp the
# measurement completely — the first run of this code reported a "dot radius"
# of 224 px and 28 "lanes", all of them Adwaita's selection blue.
DOT_MIN_WIDTH = 5
DOT_MAX_WIDTH = 16


def saturated_runs(image, y):
    """Horizontal runs of saturated pixels on row y, as (start, end, colour)."""
    width = image.width
    runs = []
    start = None
    pixels = [image.getpixel((x, y)) for x in range(width)]

    for x in range(width):
        if is_saturated(pixels[x]):
            if start is None:
                start = x
        elif start is not None:
            runs.append((start, x - 1, pixels[(start + x - 1) // 2]))
            start = None

    if start is not None:
        runs.append((start, width - 1, pixels[(start + width - 1) // 2]))

    return runs


def find_dot_rows(image):
    """Rows that look like the vertical centre of a commit dot.

    A dot's widest scanline is its centre. Scanning every row and keeping the
    local maxima of run width finds them without knowing the row height in
    advance.
    """
    widths = []

    for y in range(image.height):
        runs = saturated_runs(image, y)
        candidates = [e - s + 1 for s, e, _ in runs if e - s + 1 <= DOT_MAX_WIDTH]
        widest = max(candidates, default=0)
        widths.append(widest)

    centres = []

    for y in range(1, image.height - 1):
        # A local maximum that is wide enough to be a dot rather than a lane
        # line (lanes are ~2 px, dots ~7-9 px across).
        if (DOT_MIN_WIDTH <= widths[y] <= DOT_MAX_WIDTH
                and widths[y] >= widths[y - 1] and widths[y] > widths[y + 1]):
            centres.append(y)

    # Collapse centres that are adjacent (a dot can plateau over two rows).
    collapsed = []

    for y in centres:
        if not collapsed or y - collapsed[-1] > 3:
            collapsed.append(y)

    return collapsed


def measure(path):
    image = load(path)

    dot_rows = find_dot_rows(image)

    if len(dot_rows) < 2:
        raise SystemExit("found fewer than two commit dots; is this a graph?")

    # Row height: the most common gap between consecutive dot rows. The mode
    # rather than the mean, because a graph with a merge has rows whose dots
    # sit in different lanes and occasional gaps of two rows.
    gaps = [b - a for a, b in zip(dot_rows, dot_rows[1:])]
    row_height = Counter(gaps).most_common(1)[0][0]

    # Lane centres and colours, gathered across every dot row so that lanes
    # which only appear partway down are still seen.
    centres = []
    colours = {}

    for y in dot_rows:
        for start, end, colour in saturated_runs(image, y):
            width = end - start + 1

            if width < DOT_MIN_WIDTH or width > DOT_MAX_WIDTH:
                # A lane line (too narrow) or UI chrome (too wide).
                continue

            centre = (start + end) // 2
            centres.append(centre)
            colours.setdefault(centre, []).append(colour)

    # A lane is vertical: its dots sit at the same x on several rows. A ref
    # pill sits at one x on one row, and gitg's pill blue is itself a palette
    # colour (#204a87), so colour alone cannot separate them — recurrence can.
    seen_rows = {}

    for y in dot_rows:
        for start, end, _ in saturated_runs(image, y):
            width = end - start + 1

            if DOT_MIN_WIDTH <= width <= DOT_MAX_WIDTH:
                seen_rows.setdefault((start + end) // 2, set()).add(y)

    recurring = sorted(c for c, rows in seen_rows.items() if len(rows) >= 2)

    unique = []

    for c in recurring:
        if not unique or c - unique[-1] > 4:
            unique.append(c)

    lane_spacing = None

    if len(unique) >= 2:
        spacings = [b - a for a, b in zip(unique, unique[1:])]
        lane_spacing = Counter(spacings).most_common(1)[0][0]

    # Dot radius: half the widest run on a dot row, which is the dot's
    # diameter at its centre.
    # Measured only on lanes, for the same reason: a pill would otherwise set
    # the "dot" diameter. The mode rather than the maximum, since a dot that
    # overlaps a connector reads wider than it is.
    diameters = []

    for y in dot_rows:
        for start, end, _ in saturated_runs(image, y):
            width = end - start + 1
            centre = (start + end) // 2

            if DOT_MIN_WIDTH <= width <= DOT_MAX_WIDTH and any(
                abs(centre - u) <= 4 for u in unique
            ):
                diameters.append(width)

    dot_radius = round(Counter(diameters).most_common(1)[0][0] / 2.0, 1) if diameters else None

    lane_colours = []

    for c in unique:
        samples = colours.get(c, [])

        if samples:
            lane_colours.append(Counter(samples).most_common(1)[0][0])

    return {
        "dots": len(dot_rows),
        "row_height": row_height,
        "lane_spacing": lane_spacing,
        "lane_count": len(unique),
        "dot_radius": dot_radius,
        "lane_colours": ["#%02x%02x%02x" % c for c in lane_colours],
    }


def main():
    if len(sys.argv) < 2:
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        return 2

    result = measure(sys.argv[1])

    if "--json" in sys.argv:
        print(json.dumps(result, indent=2, sort_keys=True))
    else:
        for key in sorted(result):
            print("{}: {}".format(key, result[key]))

    return 0


if __name__ == "__main__":
    sys.exit(main())
