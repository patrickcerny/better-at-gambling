#!/usr/bin/env bash
# Renders a scene under Xvfb with the Compatibility renderer and saves a PNG.
#   scripts/screenshot.sh [res://scene.tscn] [name] [frames]
set -euo pipefail
source "$(dirname "$0")/_common.sh"
SCENE="${1:-res://ui/menus/main_menu.tscn}"
NAME="${2:-$(basename "${SCENE%.tscn}")}"
FRAMES="${3:-30}"
OUT="$ROOT/build/screenshots"
mkdir -p "$OUT"
xvfb-run -a -s "-screen 0 1920x1080x24" "$GODOT" --path "$ROOT" --rendering-driver opengl3 \
	--rendering-method gl_compatibility --resolution 1920x1080 -s tools/screenshot.gd -- \
	--scene "$SCENE" --out "$OUT/$NAME.png" --frames "$FRAMES"
echo "$OUT/$NAME.png"
