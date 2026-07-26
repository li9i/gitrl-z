#!/bin/sh
# Build the gitrl-z .deb in the clean container.
#
# Run from the repository root, inside the build container:
#
#   docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp \
#       -v "$PWD:/src" -w /src gitrlz-build ./docker/build-deb.sh
#
# The build happens in a copy under /tmp so the bind-mounted source tree is
# not littered with debian/ build products. The finished artefacts are copied
# back to _build/deb/.
#
# The point of doing this in the container rather than natively is that the
# container installs only the declared Build-Depends: if the build needs
# something not in debian/control, it fails here, which is exactly the check a
# Launchpad buildd performs. See docker/README.md.
#
# gitrl-z is packaged non-native (3.0 quilt), so an orig tarball is generated
# from the tree first. gitrl-z is nonetheless its own upstream: the "orig"
# tarball is just this repository minus the debian/ directory.

set -eu

# Optional: build another series' .deb. Empty means the default noble build.
# The series MUST match the container the build runs in, because a .deb links
# whatever libraries are present at build time.
#
#   docker build --build-arg UBUNTU=26.04 -t gitrlz-build:26.04 .
#   docker run ... gitrlz-build:26.04 ./docker/build-deb.sh resolute '~ubuntu26.04.1'
series=${1:-}
suffix=${2:-}

src=/src

# Refuse a series that is not this container's own, rather than emit a
# mislabelled package built against the wrong libraries.
container_series=$(. /etc/os-release; echo "${VERSION_CODENAME:-}")
target_series=${series:-noble}
if [ "$container_series" != "$target_series" ]; then
    echo "build-deb.sh: asked to build for '$target_series' but this container is '$container_series'." >&2
    echo "A .deb links this container's libraries, so the series must match." >&2
    echo "Build the image on that series first: docker build --build-arg UBUNTU=<ver> -t gitrlz-build:<ver> ." >&2
    exit 1
fi

full=$(dpkg-parsechangelog -l "$src/debian/changelog" -S Version)
version=${full%-*}
work=/tmp/gitrlz-build-deb
pkgdir="$work/gitrl-z-$version"

rm -rf "$work"
mkdir -p "$pkgdir"

# The package tree: everything except build dirs, VCS metadata and the
# vendored upstream working copy (reproducible from vendor/PROVENANCE).
tar --exclude=_build --exclude=.git --exclude=vendor/upstream \
    -C "$src" -cf - . | tar -C "$pkgdir" -xf -

if [ -n "$series" ] || [ -n "$suffix" ]; then
    # Retarget the top changelog entry (version suffix and series) in the build
    # copy only, so the .deb is named and versioned for this series. Upstream
    # (hence the orig) is untouched.
    sed -i "1s|.*|gitrl-z ($full$suffix) $target_series; urgency=medium|" \
        "$pkgdir/debian/changelog"
fi

# The orig tarball is the tree without debian/.
tar --exclude=./debian -C "$pkgdir" -czf "$work/gitrl-z_$version.orig.tar.gz" .

cd "$pkgdir"

# -b binary, plus the source package for lintian and the PPA. -us -uc: unsigned
# here; signing happens at upload time with the maintainer's key.
dpkg-buildpackage -us -uc

mkdir -p "$src/_build/deb"
cp "$work"/gitrl-z*.deb \
   "$work"/gitrl-z*.ddeb \
   "$work"/gitrl-z_*.dsc \
   "$work"/gitrl-z_*.orig.tar.gz \
   "$work"/gitrl-z_*.debian.tar.* \
   "$work"/gitrl-z_*.changes \
   "$work"/gitrl-z_*.buildinfo \
   "$src/_build/deb/" 2>/dev/null || true

echo "--- built artefacts ---"
ls -la "$src/_build/deb/"
