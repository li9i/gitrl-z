#!/bin/sh

set -eu

series=${1:-}
suffix=${2:-}

src=/src

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
stamp=$(dpkg-parsechangelog -l "$src/debian/changelog" -S Timestamp)
work=/tmp/gitrlz-build-deb
pkgdir="$work/gitrl-z-$version"

rm -rf "$work"
mkdir -p "$pkgdir"

git -C "$src" ls-files -z | tar -C "$src" --null -T - -cf - | tar -C "$pkgdir" -xf -
find "$pkgdir" -type d -exec touch -d "@$stamp" {} +

if [ -n "$series" ] || [ -n "$suffix" ]; then
    sed -i "1s|.*|gitrl-z ($full$suffix) $target_series; urgency=medium|" \
        "$pkgdir/debian/changelog"
fi

tar --exclude=./debian -C "$pkgdir" -czf "$work/gitrl-z_$version.orig.tar.gz" .

cd "$pkgdir"

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
