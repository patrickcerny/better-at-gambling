#!/usr/bin/env bash
# Renders the pictures on the tutorial pages (HowToPlayPanel): assets/tutorial/<name>.webp
# (960x540). The match views come from tools/dev/tutorial_shot.tscn (--view <name>), the minigame
# page from a minigame's dev shot. Needs Xvfb and ImageMagick (`convert`).
#   tools/tutorial_pictures.sh [name ...]   (default: all of them)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-$ROOT/tools/godot/godot}"
OUT="$ROOT/assets/tutorial"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$OUT"
ALL=(leaderboard hall table shop oddjobs minigame rough jail lobby)
if [ $# -gt 0 ]; then NAMES=("$@"); else NAMES=("${ALL[@]}"); fi
render() { # out scene extra-args...
	local out="$1" scene="$2"; shift 2
	xvfb-run -a -s "-screen 0 1920x1080x24" "$GODOT" --path "$ROOT" --rendering-driver opengl3 \
		--rendering-method gl_compatibility --resolution 1920x1080 --audio-driver Dummy -s tools/screenshot.gd -- \
		--scene "$scene" "$@" >"$TMP/$(basename "$out").log" 2>&1 || true
}
for name in "${NAMES[@]}"; do
	png="$TMP/$name.png"
	case "$name" in
		minigame) render "$png" res://tools/dev/roulette_sumo_shot.tscn --out "$png" --frames 60 ;;
		rough) render "$png" res://tools/dev/tutorial_shot.tscn --frames 100000 --view rough --seconds 60 --shot "$png" ;;
		*) render "$png" res://tools/dev/tutorial_shot.tscn --frames 100000 --view "$name" --autobet 50 --shot "$png" ;;
	esac
	if [ ! -f "$png" ]; then
		echo "$name: no render (see the log)" >&2
		cat "$TMP/$name.png.log" >&2 || true
		continue
	fi
	convert "$png" -resize 960x540! -quality 80 "$OUT/$name.webp"
	echo "$OUT/$name.webp $(stat -c %s "$OUT/$name.webp") bytes"
done
