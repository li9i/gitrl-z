#!/bin/sh

set -eu

root=$(dirname "$(dirname "$(readlink -f "$0")")")

output=${1:-$root/docs/screenshots/demo-one-branch.gif}
repo=${2:-$HOME/parser}

binary=$root/_build/src/gitrlz/gitrlz

if [ ! -x "$binary" ]; then
	echo "capture-demo.sh: gitrlz not built; run scripts/dev.sh build first" >&2
	exit 1
fi

for tool in xvfb-run xdotool ffmpeg convert; do
	if ! command -v "$tool" >/dev/null 2>&1; then
		echo "capture-demo.sh: $tool is not installed" >&2
		exit 1
	fi
done

built=no

if [ ! -e "$repo" ]; then
	"$root/scripts/demo-fixture.sh" "$repo"
	built=yes
fi

work=$(mktemp -d)

cleanup() {
	rm -rf "$work"

	if [ "$built" = yes ]; then
		rm -rf "$repo"
	fi
}

trap cleanup EXIT

export GTK_THEME=Adwaita
export GTK_OVERLAY_SCROLLING=0
export NO_AT_BRIDGE=1
export GTK_A11Y=none
export GSETTINGS_SCHEMA_DIR=$root/_build/data
export GSETTINGS_BACKEND=memory

xvfb-run -a --server-args="-screen 0 1210x781x24 -nolisten tcp" sh -c '
	set -eu
	video=$1
	binary=$2
	repo=$3

	glide() {
		i=1
		while [ "$i" -le 10 ]; do
			xdotool mousemove \
				$(( $1 + ($3 - $1) * i / 10 )) \
				$(( $2 + ($4 - $2) * i / 10 ))
			sleep 0.04
			i=$((i + 1))
		done
	}

	"$binary" "$repo" >/dev/null 2>&1 &
	app=$!

	sleep 6

	window=$(xdotool search --onlyvisible --name "^$(basename "$repo")$" | head -1)
	xdotool windowsize "$window" 1210 781
	xdotool windowmove "$window" 0 0

	sleep 3

	xdotool mousemove 150 705
	sleep 1

	ffmpeg -y -loglevel error -f x11grab -draw_mouse 1 \
	       -video_size 1210x781 -framerate 10 -i "$DISPLAY" -t 17 \
	       -c:v ffv1 "$video" &
	grab=$!

	sleep 1.5

	glide 150 705 700 226
	xdotool click 1
	sleep 3.0

	glide 700 226 700 361
	xdotool keydown ctrl
	xdotool click 1
	xdotool keyup ctrl
	sleep 3.0

	glide 700 361 700 145
	xdotool click 1
	sleep 3.0

	glide 700 145 700 118
	xdotool click 1
	sleep 3.0

	wait "$grab"

	kill "$app" 2>/dev/null || true
	wait "$app" 2>/dev/null || true
' sh "$work/demo.mkv" "$binary" "$repo"

mkdir -p "$work/frames" "$work/marked"

ffmpeg -y -loglevel error -i "$work/demo.mkv" -vf fps=10 "$work/frames/%04d.png"

total=$(find "$work/frames" -name '*.png' | wc -l)
index=1

for frame in "$work"/frames/*.png; do
	filled=$(( 1210 * index / total - 1 ))

	if [ "$filled" -lt 0 ]; then
		filled=0
	fi

	convert "$frame" -fill "#cc0000" -draw "rectangle 0,776 $filled,780" \
	        "$work/marked/$(basename "$frame")"

	index=$((index + 1))
done

ffmpeg -y -loglevel error -framerate 10 -i "$work/marked/%04d.png" \
       -vf "palettegen=max_colors=128:stats_mode=diff" "$work/palette.png"

ffmpeg -y -loglevel error -framerate 10 -i "$work/marked/%04d.png" -i "$work/palette.png" \
       -lavfi "paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" "$output"

echo "captured $output"
