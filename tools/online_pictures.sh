#!/usr/bin/env bash
# Renders the splash arts on PLAY ONLINE's cards (OnlineMenu): assets/ui/online/<name>.webp. Each is
# a staged scene in the real casino with the real bean models (tools/dev/tutorial_shot.tscn
# --view splash_<name>: outfits, emotes, a warm key light, a framed camera), cut to its card's
# shape (big cards 1.55:1, small ones 1.75:1) with a soft vignette. Needs Xvfb and ImageMagick.
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
# Cut width out of the 1920x1080 render (full height), its centre x, and the output size.
declare -A CUT=([public]=1674 [private]=1674 [browse]=1890 [friends]=1890)
declare -A CENTER=([public]=960 [private]=960 [browse]=960 [friends]=960)
declare -A SIZE=([public]=1000x645 [private]=1000x645 [browse]=900x514 [friends]=900x514)
for name in "${NAMES[@]}"; do
	png="$TMP/$name.png"
	xvfb-run -a -s "-screen 0 1920x1080x24" "$GODOT" --path "$ROOT" --rendering-driver opengl3 \
		--rendering-method gl_compatibility --resolution 1920x1080 --audio-driver Dummy -s tools/screenshot.gd -- \
		--scene res://tools/dev/tutorial_shot.tscn --frames 100000 --view "splash_$name" --floor grand_hall \
		--at 7.0 --shot "$png" >"$TMP/$name.log" 2>&1 || true
	if [ ! -f "$png" ]; then
		echo "$name: no render (see the log)" >&2
		cat "$TMP/$name.log" >&2 || true
		continue
	fi
	w=${CUT[$name]}
	x=$(( ${CENTER[$name]} - w / 2 ))
	x=$(( x < 0 ? 0 : (x > 1920 - w ? 1920 - w : x) ))
	convert "$png" -crop "${w}x1080+${x}+0" +repage -modulate 100,112 -resize "${SIZE[$name]}!" \
		-background black -vignette 0x90+10+10 -quality 86 "$OUT/$name.webp"
	echo "$OUT/$name.webp $(stat -c %s "$OUT/$name.webp") bytes"
done
