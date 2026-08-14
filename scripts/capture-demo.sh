#!/bin/sh

set -eu

root=$(dirname "$(dirname "$(readlink -f "$0")")")

scene=${1:-all}
repo=${2:-$HOME/parser}

binary=$root/_build/src/gitrlz/gitrlz

case "$scene" in
head|recover|rewind)
	scenes=$scene
	;;
all)
	scenes="head recover rewind"
	;;
*)
	echo "usage: capture-demo.sh [head|recover|rewind|all] [repository]" >&2
	exit 2
	;;
esac

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
export TZ=Europe/Berlin

record() {
	xvfb-run -a --server-args="-screen 0 1210x781x24 -nolisten tcp" sh -c '
		set -eu
		video=$1
		binary=$2
		repo=$3
		scene=$4
		seconds=$5

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
		       -video_size 1210x781 -framerate 10 -i "$DISPLAY" -t "$seconds" \
		       -c:v ffv1 "$video" &
		grab=$!

		sleep 1.5

		case "$scene" in
		head)
			glide 150 705 700 199
			xdotool click 1
			sleep 2.5

			step=1

			while [ "$step" -le 7 ]; do
				xdotool key Down
				sleep 1.5
				step=$((step + 1))
			done
			;;
		recover)
			glide 150 705 700 226
			xdotool click 1
			sleep 4.0

			glide 700 226 700 145
			xdotool click 1
			sleep 4.0

			glide 700 145 62 323
			xdotool click 1
			sleep 2.0

			glide 62 323 700 145
			xdotool click 1
			sleep 4.0
			;;
		rewind)
			glide 150 705 62 207
			xdotool click 1
			sleep 2.5

			glide 62 207 955 437
			xdotool mousedown 1
			sleep 0.4

			glide 955 437 830 437
			sleep 0.5
			glide 830 437 700 437
			sleep 0.5
			glide 700 437 570 437
			xdotool mouseup 1
			sleep 3.0

			glide 570 437 296 437
			xdotool click 1
			sleep 1.5
			xdotool click 1
			sleep 2.5

			glide 296 437 1110 389
			xdotool click 1
			sleep 5.0
			;;
		esac

		wait "$grab"

		kill "$app" 2>/dev/null || true
		wait "$app" 2>/dev/null || true
	' sh "$1" "$binary" "$repo" "$2" "$3"
}

encode() {
	video=$1
	output=$2

	rm -rf "$work/frames" "$work/marked"
	mkdir -p "$work/frames" "$work/marked"

	ffmpeg -y -loglevel error -i "$video" -vf fps=10 "$work/frames/%04d.png"

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
}

for name in $scenes; do
	case "$name" in
	head)
		seconds=17
		;;
	recover)
		seconds=19
		;;
	rewind)
		seconds=23
		;;
	esac

	output=$root/docs/screenshots/demo-$name.gif

	record "$work/$name.mkv" "$name" "$seconds"
	encode "$work/$name.mkv" "$output"

	echo "captured $output"
done
