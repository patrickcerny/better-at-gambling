#!/usr/bin/env bash
# Renders the standard screenshot set (menu, casino, every station overlay) into build/screenshots/.
set -euo pipefail
cd "$(dirname "$0")/.."
export GODOT="${GODOT:-$PWD/tools/godot/godot}"
shot() { # name frames extra-args...
	local name="$1" frames="$2"; shift 2
	xvfb-run -a -s "-screen 0 1920x1080x24" "$GODOT" --path . --rendering-driver opengl3 \
		--rendering-method gl_compatibility --resolution 1920x1080 --audio-driver Dummy \
		-s tools/screenshot.gd -- --scene res://match/match_scene.tscn --out "build/screenshots/$name.png" --frames "$frames" "$@" >"build/test-logs/shot-$name.log" 2>&1
	echo "build/screenshots/$name.png"
}
mkdir -p build/screenshots build/test-logs
scripts/screenshot.sh res://ui/menus/main_menu.tscn main_menu 30
shot casino_first_person 120 --dummies 3 --seed 3
shot casino_third_person 120 --dummies 3 --seed 3 --third-person
shot blackjack 420 --dummies 3 --seed 3 --autosit blackjack_2
shot roulette 420 --dummies 3 --seed 3 --autosit roulette_1
shot slots 420 --dummies 3 --seed 3 --autosit slot_8
shot plinko 420 --dummies 3 --seed 3 --autosit plinko_1
shot vip_blackjack 420 --dummies 3 --seed 3 --autosit vip_blackjack_1
shot quiz_question 200 --dummies 3 --seed 3 --skip-to 100 --duration 5
shot results 240 --dummies 3 --seed 3 --skip-to 300 --duration 5
shot quiz_end 400 --dummies 3 --seed 3 --skip-to 100 --duration 5
shot pause_menu 90 --dummies 3 --seed 3 --pause-menu
shot items 760 --dummies 3 --seed 3 --third-person --autoplay --give-items lucky_clover,black_cat,banana_peel
