#!/usr/bin/env bash
# Renders the pictures on PLAY ONLINE's cards (OnlineMenu): assets/ui/online/<name>.webp, cut to
# the cards' upright shape (720x850) around what matters in each view. The views are staged in
# the real match scene by tools/dev/tutorial_shot.tscn (--view online_<name>). Needs Xvfb and
# ImageMagick (`convert`).
#   tools/online_pictures.sh [name ...]   (default: public private browse friends)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-$ROOT/tools/godot/godot}"
OUT="$ROOT/assets/ui/online"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$OUT"
ALL=(public private browse friends)
if [ $# -gt 0 ]; then NAMES=("$@"); else NAMES=("${ALL[@]}"); fi
# Where the cut sits, as the x of its centre in the 1920 px wide render.
declare -A CENTER=([public]=1200 [private]=1150 [browse]=820 [friends]=960)
for name in "${NAMES[@]}"; do
	png="$TMP/$name.png"
	xvfb-run -a -s "-screen 0 1920x1080x24" "$GODOT" --path "$ROOT" --rendering-driver opengl3 \
		--rendering-method gl_compatibility --resolution 1920x1080 --audio-driver Dummy -s tools/screenshot.gd -- \
		--scene res://tools/dev/tutorial_shot.tscn --frames 100000 --view "online_$name" --floor grand_hall \
		--shot "$png" >"$TMP/$name.log" 2>&1 || true
	if [ ! -f "$png" ]; then
		echo "$name: no render (see the log)" >&2
		cat "$TMP/$name.log" >&2 || true
		continue
	fi
	w=915  # 1080 * 720 / 850
	x=$(( ${CENTER[$name]} - w / 2 ))
	x=$(( x < 0 ? 0 : (x > 1920 - w ? 1920 - w : x) ))
	convert "$png" -crop "${w}x1080+${x}+0" +repage -resize 720x850! -quality 82 "$OUT/$name.webp"
	echo "$OUT/$name.webp $(stat -c %s "$OUT/$name.webp") bytes"
done
