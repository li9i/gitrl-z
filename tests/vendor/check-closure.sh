#!/bin/sh
# Guard against drift in the vendored closure.
#
# src/vendor-gitg/ is code we carry, and src/vendor-gitg/meson.build is the
# list the build actually uses. If someone copies another gitg file in, or
# adds one to meson.build without copying it, this catches it.

set -eu

root=$(dirname "$(dirname "$(dirname "$(readlink -f "$0")")")")
cd "$root"

status=0

# Every .vala file present must be listed in meson.build, and vice versa.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

find src/vendor-gitg -name '*.vala' | sed 's|^src/vendor-gitg/||' | sort > "$tmp/present"
grep -oE "'(libgitg|libgitg-ext)/[a-z0-9-]+\.vala'" src/vendor-gitg/meson.build \
	| tr -d "'" | sort > "$tmp/listed"

present=$(cat "$tmp/present")
unlisted=$(comm -23 "$tmp/present" "$tmp/listed")
missing=$(comm -13 "$tmp/present" "$tmp/listed")

if [ -n "$unlisted" ]; then
	echo "FAIL: vendored files present but not in meson.build:" >&2
	echo "$unlisted" | sed 's/^/  /' >&2
	status=1
fi

if [ -n "$missing" ]; then
	echo "FAIL: files in meson.build but not present:" >&2
	echo "$missing" | sed 's/^/  /' >&2
	status=1
fi

# Every patched file must have a patch recorded (spec NFR-5).
if [ -d vendor/upstream ]; then
	for f in $present; do
		if ! diff -q "vendor/upstream/$f" "src/vendor-gitg/$f" >/dev/null 2>&1; then
			base=$(basename "$f" .vala)
			if [ ! -f "vendor/patches/$base.patch" ]; then
				echo "FAIL: $f differs from upstream but vendor/patches/$base.patch is missing" >&2
				status=1
			fi
		fi
	done
else
	echo "note: vendor/upstream absent, skipping patch check (run vendor/fetch-upstream.sh)"
fi

[ $status -eq 0 ] && echo "closure consistent: $(echo "$present" | wc -l) vendored files"
exit $status
