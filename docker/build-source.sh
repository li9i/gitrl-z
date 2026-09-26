#!/bin/sh

set -eu

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
    saflag=
    echo "reusing kept orig $orig"
    cp "$src/_build/ppa/$orig" "$work/$orig"
    tar -C "$pkgdir" -xzf "$work/$orig"
    cp -a "$src/debian" "$pkgdir/debian"
else
    saflag=-sa
    echo "generating orig $orig"
    tar --exclude=_build --exclude=.git --exclude=vendor/upstream \
        --exclude='*.AppImage' \
        -C "$src" -cf - . | tar -C "$pkgdir" -xf -
    tar --exclude=./debian -C "$pkgdir" -czf "$work/$orig" .
    cp "$work/$orig" "$src/_build/ppa/$orig"
fi

if [ -n "$series" ] || [ -n "$suffix" ]; then
    target=${series:-$(dpkg-parsechangelog -l "$pkgdir/debian/changelog" -S Distribution)}
    sed -i "1s|.*|gitrl-z ($full$suffix) $target; urgency=medium|" \
        "$pkgdir/debian/changelog"
    echo "retargeted to $full$suffix $target"
fi

cd "$pkgdir"

dpkg-buildpackage -S $saflag -us -uc

cp "$work"/gitrl-z_*.dsc \
   "$work"/gitrl-z_*.debian.tar.* \
   "$work"/gitrl-z_*_source.changes \
   "$work"/gitrl-z_*_source.buildinfo \
   "$src/_build/ppa/" 2>/dev/null || true

echo "--- source package ---"
ls -la "$src/_build/ppa/"
