#!/bin/sh

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
