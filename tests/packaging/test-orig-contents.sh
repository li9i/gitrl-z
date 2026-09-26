#!/bin/sh

set -eu

root=$(dirname "$(dirname "$(dirname "$(readlink -f "$0")")")")
orig=${1:-$(ls -t "$root"/_build/ppa/gitrl-z_*.orig.tar.gz 2>/dev/null | head -1)}

if [ ! -f "$orig" ]; then
	echo "no orig tarball found; run docker/build-source.sh first" >&2
	exit 1
fi

echo "checking $(basename "$orig")"

packed=$(mktemp)
tracked=$(mktemp)
trap 'rm -f "$packed" "$tracked"' EXIT

tar -tzf "$orig" | grep -v '/$' | sed 's|^\./||' | sort >"$packed"
git -C "$root" -c core.quotePath=false ls-files | grep -v '^debian/' | sort >"$tracked"

if ! diff -u "$tracked" "$packed"; then
	echo "the orig tarball does not hold exactly the tracked files outside debian/" >&2
	exit 1
fi

echo "orig tarball holds the tracked files only"
