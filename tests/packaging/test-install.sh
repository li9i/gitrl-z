#!/bin/sh

set -eu

root=$(dirname "$(dirname "$(dirname "$(readlink -f "$0")")")")
deb=${1:-$(ls "$root"/_build/deb/gitrl-z_*_amd64.deb 2>/dev/null | head -1)}

if [ ! -f "$deb" ]; then
	echo "no .deb found; run docker/build-deb.sh first" >&2
	exit 1
fi

echo "testing $(basename "$deb")"

docker run --rm -v "$deb:/tmp/gitrl-z.deb:ro" ubuntu:24.04 sh -eu -c '
	export DEBIAN_FRONTEND=noninteractive

	rm -f /etc/dpkg/dpkg.cfg.d/excludes

	apt-get update -qq

	apt-get install -y -qq libglib2.0-bin desktop-file-utils >/dev/null
	command -v gsettings >/dev/null
	command -v desktop-file-validate >/dev/null

	echo "--- install ---"
	apt-get install -y -qq /tmp/gitrl-z.deb

	echo "--- the binary runs ---"
	test "$(gitrlz --version)" = "gitrlz 0.1.0"

	echo "--- files are where the package said ---"
	test -x /usr/bin/gitrlz
	test -f /usr/share/applications/io.github.li9i.gitrlz.desktop
	test -f /usr/share/metainfo/io.github.li9i.gitrlz.metainfo.xml
	test -f /usr/share/man/man1/gitrlz.1.gz
	for size in 128 64 48; do
		test -f "/usr/share/icons/hicolor/${size}x${size}/apps/io.github.li9i.gitrlz.png"
	done
	test -f /usr/share/icons/hicolor/symbolic/apps/io.github.li9i.gitrlz-symbolic.svg

	echo "--- the schema was compiled on install ---"
	gsettings list-schemas | grep -qx "io.github.li9i.gitrlz.preferences.interface"
	gsettings list-schemas | grep -qx "io.github.li9i.gitrlz.preferences.reflog"
	gsettings list-schemas | grep -qx "io.github.li9i.gitrlz.state.window"
	gsettings list-schemas | grep -qx "io.github.li9i.gitrlz.state.reflog"

	echo "--- the desktop entry is valid as installed ---"
	desktop-file-validate /usr/share/applications/io.github.li9i.gitrlz.desktop

	echo "--- remove ---"
	apt-get remove -y -qq gitrl-z >/dev/null
	test ! -e /usr/bin/gitrlz

	echo "--- purge ---"
	dpkg --purge gitrl-z
	test ! -d /usr/share/doc/gitrl-z

	if gsettings list-schemas | grep -qx "io.github.li9i.gitrlz.preferences.reflog"; then
		echo "schema still registered after purge" >&2
		exit 1
	fi

	echo "--- dpkg has no record left ---"
	if dpkg -l gitrl-z 2>/dev/null | grep -q "^ii"; then
		echo "gitrl-z still installed after purge" >&2
		exit 1
	fi
'

echo "install/remove/purge clean"
