#!/bin/sh

set -eu

root=$(dirname "$(dirname "$(dirname "$(readlink -f "$0")")")")
repo=${1:-$root}
ref=${2:-HEAD}

dump_vala=$root/_build/tests/gitrlz-dump

if [ ! -x "$dump_vala" ]; then
	echo "gitrlz-dump not built; run scripts/dev.sh build first" >&2
	exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "comparing implementations on $repo ($ref)"

python3 "$root/tests/parity/dump-python.py" "$repo" "$ref" > "$tmp/python.txt"

if [ "${GITRLZ_DOCKER:-0}" = "1" ]; then
	docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp \
		-v "$root:/src" -v "$repo:$repo:ro" -w /src gitrlz-build \
		./_build/tests/gitrlz-dump "$repo" "$ref" > "$tmp/vala.txt"
else
	"$dump_vala" "$repo" "$ref" > "$tmp/vala.txt"
fi

python_lines=$(wc -l < "$tmp/python.txt")
vala_lines=$(wc -l < "$tmp/vala.txt")

echo "python: $python_lines entries"
echo "vala:   $vala_lines entries"

if diff -u "$tmp/python.txt" "$tmp/vala.txt" > "$tmp/diff.txt"; then
	echo "IDENTICAL: the two implementations agree on every field of every entry"
	exit 0
fi

echo "DIFFERENCES:"
cat "$tmp/diff.txt"
exit 1
