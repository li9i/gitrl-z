#!/bin/sh

set -eu

root=$(dirname "$(dirname "$(readlink -f "$0")")")
build=$root/_build
image=gitrlz-build

cd "$root"

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
	sh_run "ninja -C _build && meson test -C _build --print-errorlogs ${2:+--suite $2}"
	;;
run)
	configure
	sh_run "ninja -C _build"
	shift
	GSETTINGS_SCHEMA_DIR="$build/data" exec "$build/src/gitrlz/gitrlz" "$@"
	;;
clean)
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
