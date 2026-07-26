#!/bin/sh
# Build the gitrl-z source package for a Launchpad PPA, in the clean container.
#
# Run from the repository root, inside the build container:
#
#   docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp \
#       -v "$PWD:/src" -w /src gitrlz-build ./docker/build-source.sh
#
# A PPA accepts source only: Launchpad's own build farm compiles the binary.
# So this produces a source-only .changes, unlike build-deb.sh which also
# builds the .deb. Signing is left out here (-us -uc) and done on the host with
# the maintainer's key, which does not live in the container. The finished
# source package lands in _build/ppa/, ready for debsign and dput.
#
# One orig tarball per upstream version. Launchpad stores it as immutable, so
# every Debian revision of that version (-1, -2, ...) must reference the exact
# same bytes, and plain tar|gzip is not reproducible. So the orig is kept in
# _build/ppa and never regenerated once made:
#
#   first revision  (-1): generate the orig from the tree, keep it, ship it.
#   later revisions (-2+): reuse the kept orig as the upstream source and lay
#                          the current debian/ on top, so only debian/ differs.
#                          Do not delete _build/ppa between revisions, or the
#                          orig is lost and has to be refetched from Launchpad.
#
# gitrl-z is packaged non-native (3.0 quilt) and is its own upstream: the orig
# is simply this tree without the debian/ directory.

set -eu

# Optionally target another Ubuntu series from the same tree. A PPA builds each
# series separately, so a second series is a second source upload differing only
# in the changelog's version suffix and target. When given, the changelog is
# retargeted in the build copy alone; the tracked changelog stays the primary
# (noble) entry.
#
#   ./docker/build-source.sh                            # noble, as tracked
#   ./docker/build-source.sh resolute '~ubuntu26.04.1'  # 26.04 LTS
series=${1:-}
suffix=${2:-}

src=/src
full=$(dpkg-parsechangelog -l "$src/debian/changelog" -S Version)
upstream=${full%-*}
orig="gitrl-z_$upstream.orig.tar.gz"
work=/tmp/gitrlz-build-source
pkgdir="$work/gitrl-z-$upstream"

rm -rf "$work"
mkdir -p "$pkgdir" "$src/_build/ppa"

if [ -f "$src/_build/ppa/$orig" ]; then
    # Reuse: the upstream source is the kept orig; only debian/ may change.
    # The orig shipped on its first upload, so reference it, do not resend.
    saflag=
    echo "reusing kept orig $orig"
    cp "$src/_build/ppa/$orig" "$work/$orig"
    tar -C "$pkgdir" -xzf "$work/$orig"
    cp -a "$src/debian" "$pkgdir/debian"
else
    # First revision: the tree is the upstream source; generate and keep orig.
    # Exclude build dirs, VCS metadata and the vendored upstream working copy
    # (reproducible from vendor/PROVENANCE).
    # First time this orig exists, so ship it in the upload (-sa). Later
    # revisions and other series reference this same stored copy.
    saflag=-sa
    echo "generating orig $orig"
    tar --exclude=_build --exclude=.git --exclude=vendor/upstream \
        -C "$src" -cf - . | tar -C "$pkgdir" -xf -
    tar --exclude=./debian -C "$pkgdir" -czf "$work/$orig" .
    cp "$work/$orig" "$src/_build/ppa/$orig"
fi

if [ -n "$series" ] || [ -n "$suffix" ]; then
    # Retarget the top entry only: version suffix and target series. Upstream
    # (hence the orig) is untouched; the suffix rides the Debian revision.
    target=${series:-$(dpkg-parsechangelog -l "$pkgdir/debian/changelog" -S Distribution)}
    sed -i "1s|.*|gitrl-z ($full$suffix) $target; urgency=medium|" \
        "$pkgdir/debian/changelog"
    echo "retargeted to $full$suffix $target"
fi

cd "$pkgdir"

# -S source only, the one kind of upload a PPA takes. $saflag is -sa the first
# time the orig is made, so it ships once, then empty so later revisions and
# other series reference the stored copy. -us -uc: unsigned here; debsign on the
# host adds the signature.
dpkg-buildpackage -S $saflag -us -uc

cp "$work"/gitrl-z_*.dsc \
   "$work"/gitrl-z_*.debian.tar.* \
   "$work"/gitrl-z_*_source.changes \
   "$work"/gitrl-z_*_source.buildinfo \
   "$src/_build/ppa/" 2>/dev/null || true

echo "--- source package ---"
ls -la "$src/_build/ppa/"
