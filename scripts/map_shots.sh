#!/usr/bin/env bash
# Renders map/atmosphere shots of the Lucky Lounge from fixed free-camera positions.
#   scripts/map_shots.sh [out-dir]   (default build/screenshots/map)
set -uo pipefail
cd "$(dirname "$0")/.."
export GODOT="${GODOT:-$PWD/tools/godot/godot}"
OUT="${1:-build/screenshots/map}"
mkdir -p "$OUT" build/test-logs
shot() { # name cam look [fov] [extra args...]
	local name="$1" cam="$2" look="$3" fov="${4:-70}"; shift 3; [[ $# -gt 0 ]] && shift
	xvfb-run -a -s "-screen 0 1920x1080x24" "$GODOT" --path . --rendering-driver opengl3 \
		--rendering-method gl_compatibility --resolution 1920x1080 --audio-driver Dummy \
		-s tools/screenshot.gd -- --scene res://match/match_scene.tscn --out "$OUT/$name.png" --frames 100 \
		--dummies 3 --seed 3 --cam "$cam" --look "$look" --fov "$fov" "$@" >"build/test-logs/shot-map-$name.log" 2>&1
	echo "$OUT/$name.png ($?)"
}
shot entrance "0,2.4,5.5" "0,2.8,16" 75
shot lobby_wide "-16,4.5,14.5" "0,1.5,5" 75
shot stairs "17,3.2,11.5" "12,2.6,3"
shot bar "13.6,2.0,0.5" "18,1.2,5.5"
shot vip_gate "12.6,5.4,-2.6" "7,5.0,-4" 75
shot vip_from_stairs "13,5.6,0.5" "3,4.6,-5"
shot vip_wide "0,6.4,-0.2" "0,4.2,-6.5" 80
shot vip_table "-2,5.4,-0.5" "-4.5,4.6,-4"
shot vip_back "2,5.6,-2" "0,5.2,-15" 75
shot wide "20,6.5,14" "-4,1.5,-4" 85
shot slots "-4,2.8,-4" "-14,1.3,-11"
shot blackjack_floor "-9,2.4,10" "-9,1.0,4"
