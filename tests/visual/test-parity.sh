#!/bin/sh
# Geometry parity against the installed gitg (spec 6.3.1).
#
# Captures gitg and gitrl-z over the same fixture, measures both graphs, and
# compares the properties FR-102 delegates to vendored code: lane spacing,
# dot radius and row height. If the vendored renderers really are gitg's,
# these match exactly; if a patch or a CSS divergence perturbs the drawing,
# they do not.
#
# What is deliberately NOT compared: the number of dots and the number of
# lanes. gitg shows all refs, gitrl-z's preview shows local branches with one
# tip substituted, so the two draw different commit sets by design. That is
# why this measures geometry rather than diffing pixels (spec 6.3).
#
# Run in the visual container, which has gitg 44-1build2 pinned:
#
#   docker build -f Dockerfile.visual -t gitrlz-visual .
#   docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp \
#       -v "$PWD:/src" -w /src gitrlz-visual ./tests/visual/test-parity.sh

set -eu

root=$(dirname "$(dirname "$(dirname "$(readlink -f "$0")")")")
out=${GITRLZ_VISUAL_OUT:-$root/_build/visual}
fixture=${GITRLZ_VISUAL_FIXTURE:-/tmp/gitrlz-visual-fixture}

mkdir -p "$out"

# The crop windows.
#
# Both are a strip of the lane column, at a fixed window size and fixed
# fixture, so the graph lands in the same place every run. They are constants
# of this fixture and this geometry rather than of the applications: change
# either and these must be re-derived, which is what the reference images in
# tests/visual/reference/ are for.
#
# The strip is narrow on purpose. Measured over a whole window, ref pills,
# selection highlights and header-bar chrome all produce palette-coloured
# runs, and the measurement reports nonsense with total confidence.
GITG_CROP=${GITG_CROP:-90x180+200+50}
GITRLZ_CROP=${GITRLZ_CROP:-90x180+205+535}

echo "--- fixture ---"
"$root/tests/visual/fixture.sh" "$fixture" >/dev/null

echo "--- capture gitg ---"
"$root/tests/visual/capture.sh" "$out/gitg-full.png" gitg "$fixture"
convert "$out/gitg-full.png" -crop "$GITG_CROP" +repage "$out/gitg-graph.png"

echo "--- capture gitrl-z ---"
GSETTINGS_SCHEMA_DIR=$root/_build/data \
	"$root/tests/visual/capture-gitrlz.sh" "$out/gitrlz-full.png" "$fixture"
convert "$out/gitrlz-full.png" -crop "$GITRLZ_CROP" +repage "$out/gitrlz-graph.png"

echo "--- measure ---"
python3 "$root/tests/visual/measure.py" "$out/gitg-graph.png" --json > "$out/gitg.json"
python3 "$root/tests/visual/measure.py" "$out/gitrlz-graph.png" --json > "$out/gitrlz.json"

echo "gitg:"
sed 's/^/  /' "$out/gitg.json"
echo "gitrl-z:"
sed 's/^/  /' "$out/gitrlz.json"

echo "--- compare ---"
python3 - "$out/gitg.json" "$out/gitrlz.json" <<'PY'
import json
import sys

gitg = json.load(open(sys.argv[1]))
gitrlz = json.load(open(sys.argv[2]))

# The properties that must match: everything the vendored renderer decides.
# A failure names the property and both values, which is the whole advantage
# of measuring over diffing — "the images differ by 4213 pixels" tells you
# nothing about what to go and look at.
COMPARED = ["lane_spacing", "dot_radius", "row_height"]

failures = []

for key in COMPARED:
    a, b = gitg.get(key), gitrlz.get(key)

    if a != b:
        failures.append("{}: gitg {!r}, gitrl-z {!r}".format(key, a, b))
    else:
        print("  {}: {} (match)".format(key, a))

# Both must draw in gitg's palette; the specific lanes differ because the
# commit sets differ, but the first lane is lane 0 in both.
if gitg["lane_colours"] and gitrlz["lane_colours"]:
    if gitg["lane_colours"][0] != gitrlz["lane_colours"][0]:
        failures.append("first lane colour: gitg {}, gitrl-z {}".format(
            gitg["lane_colours"][0], gitrlz["lane_colours"][0]))
    else:
        print("  first lane colour: {} (match)".format(gitg["lane_colours"][0]))
else:
    failures.append("no lane colours detected in one of the captures")

if failures:
    print("\nGEOMETRY DIFFERS:")
    for f in failures:
        print("  " + f)
    sys.exit(1)

print("\ngeometry matches gitg")
PY

# A test suite that cannot fail is not a test suite. See selfcheck.py.
echo "--- self-check: the comparison must reject a perturbed capture ---"

convert "$out/gitrlz-graph.png" -scale 130% "$out/perturbed.png"
python3 "$root/tests/visual/measure.py" "$out/perturbed.png" --json > "$out/perturbed.json"
python3 "$root/tests/visual/selfcheck.py" "$out/gitg.json" "$out/perturbed.json"

echo "visual parity suite passed"
