#!/bin/sh
# Install the built .deb into a pristine noble container, exercise it, then
# remove and purge it.
#
# This is the piuparts substitute: piuparts has no candidate in noble (checked
# during feasibility analysis), so the install/remove/purge cycle is scripted
# here instead.
#
# Deliberately NOT run in the build container: that one has every build
# dependency installed, so a missing *runtime* dependency would go unnoticed.
# A stock ubuntu:24.04 has none of them, which is the point — apt must pull in
# everything gitrl-z needs from the package's own Depends.
#
# Two traps this script has already fallen into, hence the care below:
#
#   * The official Ubuntu images ship /etc/dpkg/dpkg.cfg.d/excludes, which
#     path-excludes /usr/share/man/*. The man page is in the .deb but never
#     lands on disk, which looks exactly like a packaging bug. The exclusion
#     is removed before installing.
#
#   * gsettings and strings are not installed in a stock image, so probing the
#     schema with either reports "missing" whatever the truth is. The tools
#     are installed BEFORE anything is asserted, so a missing tool is a setup
#     failure rather than a silent false negative.
#
#   tests/packaging/test-install.sh [path/to/gitrl-z_VERSION_ARCH.deb]

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

	# See the header: without this the man page is silently dropped.
	rm -f /etc/dpkg/dpkg.cfg.d/excludes

	apt-get update -qq

	# The tools the assertions depend on, installed first so that a missing
	# tool fails loudly here instead of quietly faking a passing test.
	apt-get install -y -qq libglib2.0-bin desktop-file-utils >/dev/null
	command -v gsettings >/dev/null
	command -v desktop-file-validate >/dev/null

	echo "--- install ---"
	# apt-get install on a local .deb resolves and pulls the Depends, which
	# dpkg -i alone would not.
	apt-get install -y -qq /tmp/gitrl-z.deb

	echo "--- the binary runs ---"
	# --version is the one path that works with no display (spec FR-104), so
	# it is what a headless container can check.
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
	# The dpkg file trigger owned by libglib2.0-0t64 compiles anything landing
	# in /usr/share/glib-2.0/schemas. A schema shipped but never compiled
	# aborts the application at startup, so this is not cosmetic.
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
	# dpkg, not apt: the package came from a local file, so once it is removed
	# apt can no longer resolve the name ("Unable to locate package gitrl-z").
	dpkg --purge gitrl-z
	test ! -d /usr/share/doc/gitrl-z

	# The schema must be gone from the cache too, or a purged package leaves
	# settings behind for the next thing that reads them.
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
