#!/bin/sh

set -eu

root=$(dirname "$(dirname "$(dirname "$(readlink -f "$0")")")")
out=${GITRLZ_VISUAL_OUT:-$root/_build/visual}
fixture=${GITRLZ_VISUAL_FIXTURE:-/tmp/gitrlz-visual-fixture}

mkdir -p "$out"

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

COMPARED = ["lane_spacing", "dot_radius", "row_height"]

failures = []

for key in COMPARED:
    a, b = gitg.get(key), gitrlz.get(key)

    if a != b:
        failures.append("{}: gitg {!r}, gitrl-z {!r}".format(key, a, b))
    else:
        print("  {}: {} (match)".format(key, a))

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

echo "--- self-check: the comparison must reject a perturbed capture ---"

convert "$out/gitrlz-graph.png" -scale 130% "$out/perturbed.png"
python3 "$root/tests/visual/measure.py" "$out/perturbed.png" --json > "$out/perturbed.json"
python3 "$root/tests/visual/selfcheck.py" "$out/gitg.json" "$out/perturbed.json"

echo "visual parity suite passed"
