#!/bin/sh
# Lintian the built package at --pedantic --info (spec NFR-11).
#
# Runs against the .changes rather than the .deb so that source-package tags
# are checked too: the binary alone misses everything about debian/control,
# debian/copyright and the source format. That distinction is not academic —
# the binary check passed cleanly while the source check was still reporting
# three warnings.
#
# One override exists, documented in debian/gitrl-z.lintian-overrides. This
# script prints overridden tags rather than hiding them, so an override can
# never quietly grow into a pile of them.

set -eu

root=$(dirname "$(dirname "$(dirname "$(readlink -f "$0")")")")
changes=${1:-$(ls "$root"/_build/deb/gitrl-z_*_amd64.changes 2>/dev/null | head -1)}

if [ ! -f "$changes" ]; then
	echo "no .changes found; run docker/build-deb.sh first" >&2
	exit 1
fi

echo "--- overridden tags (expected, and each one justified in debian/) ---"
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp \
	-v "$root:/src" -w /src gitrlz-build \
	lintian --pedantic --show-overrides "${changes#$root/}" 2>&1 | grep '^O:' || true

echo "--- unoverridden tags (must be none) ---"
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp \
	-v "$root:/src" -w /src gitrlz-build \
	lintian --pedantic --info "${changes#$root/}"

echo "lintian clean"
