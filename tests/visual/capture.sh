#!/bin/sh

set -eu

output=${1:?usage: capture.sh <output.png> <command> [args...]}
shift

export GTK_THEME=Adwaita
export GTK_OVERLAY_SCROLLING=0
export NO_AT_BRIDGE=1
export GTK_A11Y=none
export FONTCONFIG_FILE=${FONTCONFIG_FILE:-/etc/fonts/fonts.conf}

xvfb-run -a --server-args="-screen 0 1400x900x24 -nolisten tcp" sh -c '
	set -eu
	out=$1
	shift

	"$@" >/dev/null 2>&1 &
	app=$!

	sleep 7

	xwd -root -silent | convert xwd:- "$out"

	kill "$app" 2>/dev/null || true
	wait "$app" 2>/dev/null || true
' sh "$output" "$@"

echo "captured $output"
