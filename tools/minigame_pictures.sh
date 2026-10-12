#!/usr/bin/env bash
# Renders one picture per registered minigame for the lobby's minigame selector:
# assets/minigames/<id>.webp (480x270). Uses the game's dev shot (tools/dev/<id>_shot.tscn), or
# tools/dev/minigame_stage_shot.tscn for the 2D stages without one (quiz, lonely_number,
# bust_or_bank). Needs Xvfb and ImageMagick (`convert`).
#   tools/minigame_pictures.sh [id ...]      (default: every id in data/registry/minigames.tres)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-$ROOT/tools/godot/godot}"
OUT="$ROOT/assets/minigames"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$OUT"
if [ $# -gt 0 ]; then
	IDS=("$@")
else
	mapfile -t IDS < <(grep -o 'res://minigames/[a-z_]*/' "$ROOT/data/registry/minigames.tres" | cut -d/ -f4)
fi
for id in "${IDS[@]}"; do
	scene="res://tools/dev/${id}_shot.tscn"
	extra=()
	if [ ! -f "$ROOT/tools/dev/${id}_shot.tscn" ]; then
		scene="res://tools/dev/minigame_stage_shot.tscn"
		extra=(--game "$id")
	fi
	xvfb-run -a -s "-screen 0 1920x1080x24" "$GODOT" --path "$ROOT" --rendering-driver opengl3 \
		--rendering-method gl_compatibility --resolution 1920x1080 --audio-driver Dummy -s tools/screenshot.gd -- \
		--scene "$scene" --out "$TMP/$id.png" --frames 60 --pixel 1 "${extra[@]}" >/dev/null 2>&1 || true
	if [ ! -f "$TMP/$id.png" ]; then
		echo "$id: no render (the selector draws a placeholder card)" >&2
		continue
	fi
	convert "$TMP/$id.png" -resize 480x270! -quality 82 "$OUT/$id.webp"
	echo "$OUT/$id.webp $(stat -c %s "$OUT/$id.webp") bytes"
done
