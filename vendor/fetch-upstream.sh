#!/bin/sh

set -eu

here=$(dirname "$(readlink -f "$0")")
tarball=gitg-44.tar.xz
url=https://download.gnome.org/sources/gitg/44/$tarball
sha256=342a31684dab9671cd341bd3e3ce665adcee0460c2a081ddc493cdbc03132530

cd "$here"

if [ -d upstream ] && [ "${1:-}" != "--force" ]; then
	echo "vendor/upstream already present; pass --force to refetch" >&2
	exit 0
fi

if [ ! -f "$tarball" ]; then
	echo "fetching $url"
	wget -q -O "$tarball.part" "$url"
	mv "$tarball.part" "$tarball"
fi

echo "$sha256  $tarball" | sha256sum -c -

rm -rf upstream
mkdir upstream
tar xf "$tarball" -C upstream --strip-components=1
rm -f "$tarball"

echo "vendor/upstream ready (gitg 44)"
