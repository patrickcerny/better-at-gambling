#!/usr/bin/env bash
# Records the looping preview clip each minigame's rules card plays (MinigameBriefing):
# assets/minigames/clips/<id>.ogv, an Ogg Theora video (Godot plays it natively), 960x540 at
# 30 fps, 6 s. Patrick 2026-11-16: "Dont use GIFs use videos gifs are bad quality" (until 0.9.84
# these were 384x216 10 fps sprite sheets). Frames come from tools/dev/minigame_clip.tscn (real
# logic + bot seats for table games, the dev shot with walking beans for walkable ones, or the
# game's own scripted tools/dev/<id>_clip.tscn). Needs Xvfb and ffmpeg with libtheora.
#   tools/minigame_clips.sh [id ...]      (default: every id in data/registry/minigames.tres)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-$ROOT/tools/godot/godot}"
OUT="$ROOT/assets/minigames/clips"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$OUT"
SECONDS_LONG="${CLIP_SECONDS:-6}"
QUALITY="${CLIP_QUALITY:-5}"
# Seconds of real play skipped before recording, so the clip lands on the interesting part.
declare -A SKIP=(
	[quiz]=6 [lonely_number]=0 [roulette_royale]=4 [split_or_steal]=7 [bust_or_bank]=3
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
		res://tools/dev/minigame_clip.tscn -- --game "$id" --out "$TMP/$id" --seconds "$SECONDS_LONG" --every 1 \
		--skip "${SKIP[$id]:-0}" >/dev/null 2>&1 || true
	n=$(ls "$TMP/$id"/f*.png 2>/dev/null | wc -l)
	if [ "$n" -lt 150 ]; then
		echo "$id: only $n frames (the card keeps its still picture)" >&2
		continue
	fi
	ffmpeg -loglevel error -y -framerate 30 -i "$TMP/$id/f%03d.png" -c:v libtheora -q:v "$QUALITY" \
		-pix_fmt yuv420p -g 30 "$OUT/$id.ogv"
	rm -f "$OUT/$id.webp" "$OUT/$id.webp.import"
	echo "$OUT/$id.ogv $(stat -c %s "$OUT/$id.ogv") bytes"
done
