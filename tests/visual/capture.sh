#!/bin/sh
# Screenshot an application's window under a fixed, private X server.
#
# Everything environmental is pinned — screen size, theme, font, scrollbar
# behaviour — so that a measurement difference between two captures is a
# difference in the applications, not in the conditions they ran under.
#
#   tests/visual/capture.sh <output.png> <command> [args...]

set -eu

output=${1:?usage: capture.sh <output.png> <command> [args...]}
shift

export GTK_THEME=Adwaita
export GTK_OVERLAY_SCROLLING=0
export NO_AT_BRIDGE=1
export GTK_A11Y=none
# A missing font would silently change every text metric, and with it the row
# height, so the family is named rather than left to fontconfig's preference.
export FONTCONFIG_FILE=${FONTCONFIG_FILE:-/etc/fonts/fonts.conf}

xvfb-run -a --server-args="-screen 0 1400x900x24 -nolisten tcp" sh -c '
	set -eu
	out=$1
	shift

	"$@" >/dev/null 2>&1 &
	app=$!

	# Long enough for the window to map, the repository to load and the graph
	# to be walked and drawn. The suite is not timing-sensitive beyond this.
	sleep 7

	xwd -root -silent | convert xwd:- "$out"

	kill "$app" 2>/dev/null || true
	wait "$app" 2>/dev/null || true
' sh "$output" "$@"

echo "captured $output"
