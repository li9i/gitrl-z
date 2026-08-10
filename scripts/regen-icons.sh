#!/bin/sh
# Regenerate the installed application icons from the SVG master.
#
# Run from anywhere:
#
#   ./scripts/regen-icons.sh
#   -> data/icons/io.github.li9i.gitrlz-{128,64,48}.png
#
# hicolor gets one PNG per size rather than a single scalable/ entry, because
# a panel that picks the nearest size and scales it produces a softer icon than
# one drawn at the size it needs. The PNGs are committed, so building the
# package needs no image tooling; only this script does.
#
# Each size is rendered from the SVG rather than downscaled from the largest,
# so the thin parts of the loop stay crisp at 48.

set -eu

cd "$(dirname "$0")/.."

src=data/icons/io.github.li9i.gitrlz.svg
test -f "$src" || { echo "regen-icons: $src not found" >&2; exit 1; }

command -v rsvg-convert >/dev/null 2>&1 || {
	echo "regen-icons: rsvg-convert not found (Debian: librsvg2-bin)" >&2
	exit 1
}

for size in 128 64 48; do
	out="data/icons/io.github.li9i.gitrlz-$size.png"
	rsvg-convert -w "$size" -h "$size" "$src" -o "$out"
	echo "wrote $out"
done
