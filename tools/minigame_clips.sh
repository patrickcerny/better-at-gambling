#!/usr/bin/env bash
# Records the looping preview clip each minigame's rules card plays (MinigameBriefing):
# assets/minigames/clips/<id>.webp, a sprite sheet of 50 frames (10 columns x 5 rows, 384x216 each,
# 10 fps = 5 s). Frames come from tools/dev/minigame_clip.tscn (real logic + bot seats for table
# games, the dev shot with walking beans for walkable ones). Needs Xvfb and ImageMagick.
# A new clip's .import needs compress/mode=1 (lossy, like the others) or it ships at ~2.5 MB.
#   tools/minigame_clips.sh [id ...]      (default: every id in data/registry/minigames.tres)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-$ROOT/tools/godot/godot}"
OUT="$ROOT/assets/minigames/clips"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$OUT"
# Seconds of real play skipped before recording, so the clip lands on the interesting part.
declare -A SKIP=(
	[quiz]=6 [lonely_number]=0 [roulette_royale]=4 [split_or_steal]=6 [bust_or_bank]=3
	[vote_race]=3 [find_the_lady]=0 [forehead_poker]=4 [spy]=5
)
if [ $# -gt 0 ]; then
	IDS=("$@")
else
	mapfile -t IDS < <(grep -o 'res://minigames/[a-z_]*/' "$ROOT/data/registry/minigames.tres" | cut -d/ -f4)
fi
for id in "${IDS[@]}"; do
	rm -rf "$TMP/$id"
	timeout 600 xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --path "$ROOT" --rendering-driver opengl3 \
		--rendering-method gl_compatibility --fixed-fps 30 --resolution 1280x720 --audio-driver Dummy \
		res://tools/dev/minigame_clip.tscn -- --game "$id" --out "$TMP/$id" --seconds 5 --every 3 \
		--skip "${SKIP[$id]:-0}" >/dev/null 2>&1 || true
	n=$(ls "$TMP/$id"/f*.png 2>/dev/null | wc -l)
	if [ "$n" -lt 50 ]; then
		echo "$id: only $n frames (the card keeps its still picture)" >&2
		continue
	fi
	montage "$TMP/$id"/f0[0-4][0-9].png -tile 10x5 -geometry 384x216+0+0 -background none "$TMP/$id.png"
	convert "$TMP/$id.png" -quality 72 -define webp:method=6 "$OUT/$id.webp"
	echo "$OUT/$id.webp $(stat -c %s "$OUT/$id.webp") bytes"
done
