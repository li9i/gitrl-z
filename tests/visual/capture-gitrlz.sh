#!/bin/sh
# Capture gitrl-z with a reflog entry selected, so the preview graph is drawn.
#
# Separate from capture.sh because gitrl-z needs a click before there is a
# graph to measure: with nothing selected the preview shows the "Select an
# entry" placeholder (P-FR-23), which is correct behaviour and useless to
# measure.
#
#   tests/visual/capture-gitrlz.sh <output.png> <repo>

set -eu

output=${1:?usage: capture-gitrlz.sh <output.png> <repo>}
repo=${2:?usage: capture-gitrlz.sh <output.png> <repo>}

root=$(dirname "$(dirname "$(dirname "$(readlink -f "$0")")")")
binary=$root/_build/src/gitrlz/gitrlz

if [ ! -x "$binary" ]; then
	echo "gitrlz not built; run scripts/dev.sh build first" >&2
	exit 1
fi

export GTK_THEME=Adwaita
export GTK_OVERLAY_SCROLLING=0
export NO_AT_BRIDGE=1
export GTK_A11Y=none
export GSETTINGS_SCHEMA_DIR=${GSETTINGS_SCHEMA_DIR:-$root/_build/data}

xvfb-run -a --server-args="-screen 0 1400x900x24 -nolisten tcp" sh -c '
	set -eu
	out=$1
	binary=$2
	repo=$3

	"$binary" "$repo" >/dev/null 2>&1 &
	app=$!

	sleep 6

	# The second row of the reflog list. Any row with a resolvable commit
	# would do; this one is stable for the fixture.
	xdotool mousemove 700 110 click 1

	sleep 4

	xwd -root -silent | convert xwd:- "$out"

	kill "$app" 2>/dev/null || true
	wait "$app" 2>/dev/null || true
' sh "$output" "$binary" "$repo"

echo "captured $output"
