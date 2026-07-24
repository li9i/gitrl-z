#!/bin/sh
# Developer convenience wrapper.
#
# The plan's intent (spec NFR-10) is that development happens natively on the
# host, which is already the target platform, and Docker is used only to prove
# Build-Depends completeness when building the package. Both are available
# here: set GITRLZ_DOCKER=1 to run any command in the build container instead
# of natively.
#
# The container runs as the invoking user so build products are not left
# root-owned in the bind-mounted source tree.
#
#   scripts/dev.sh setup      configure the build
#   scripts/dev.sh build      build
#   scripts/dev.sh test       run the test suite
#   scripts/dev.sh run        build and run gitrlz (needs a display)
#   scripts/dev.sh clean      remove the build directory
#   scripts/dev.sh shell      interactive shell (implies GITRLZ_DOCKER=1)

set -eu

root=$(dirname "$(dirname "$(readlink -f "$0")")")
build=$root/_build
image=gitrlz-build

cd "$root"

# Run a command either natively or in the container.
sh_run() {
	if [ "${GITRLZ_DOCKER:-0}" = "1" ]; then
		docker run --rm \
			--user "$(id -u):$(id -g)" \
			-e HOME=/tmp \
			-v "$root:/src" -w /src \
			"$image" sh -c "$1"
	else
		sh -c "$1"
	fi
}

configure() {
	[ -d "$build" ] || sh_run "meson setup _build"
}

case "${1:-build}" in
setup)
	configure
	;;
build)
	configure
	sh_run "ninja -C _build"
	;;
test)
	configure
	# Build everything first: `meson test` builds only what the tests depend
	# on, which leaves the gitrlz binary unbuilt and a compile error in it
	# unnoticed by a green test run.
	sh_run "ninja -C _build && meson test -C _build --print-errorlogs ${2:+--suite $2}"
	;;
run)
	configure
	sh_run "ninja -C _build"
	# Drop the "run" subcommand before forwarding the rest, or it reaches
	# gitrlz as a path argument and the app exits 1 with
	# "not a git repository: run".
	shift
	# The binary always runs on the host, even under GITRLZ_DOCKER: it needs
	# the real display and the real theme, which is the whole point of
	# looking at it. Uninstalled runs need the schemas Meson compiled into
	# the build tree, otherwise GLib aborts on a missing schema (spec 5).
	GSETTINGS_SCHEMA_DIR="$build/data" exec "$build/src/gitrlz/gitrlz" "$@"
	;;
clean)
	# The build directory may be root-owned from an earlier container run.
	rm -rf "$build" 2>/dev/null || docker run --rm -v "$root:/src" "$image" rm -rf /src/_build
	;;
shell)
	docker run --rm -it \
		--user "$(id -u):$(id -g)" \
		-e HOME=/tmp \
		-v "$root:/src" -w /src \
		"$image" bash
	;;
*)
	echo "usage: $0 {setup|build|test|run|clean|shell}" >&2
	exit 2
	;;
esac
