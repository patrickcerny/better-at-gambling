#!/usr/bin/env bash
# Runs the test suites headless. Exits non-zero on any failure.
# Usage: scripts/test.sh [unit|sim|integration|physics|ui|smoke|session|lint|orchestrator|net|all]   (default: unit)
# `net` runs real server/client processes (~7 min; NET_SYNC_MINUTES shortens the long match).
set -uo pipefail
source "$(dirname "$0")/_common.sh"
cd "$ROOT"

SUITE="${1:-unit}"
FAILED=0
LOG_DIR="$ROOT/build/test-logs"
mkdir -p "$LOG_DIR"

run_gut() { # suite-name dir
	local name="$1" dir="$2" log="$LOG_DIR/$1.log"
	if [[ -z "$(find "$ROOT/${dir#res://}" -name 'test_*.gd' 2>/dev/null)" ]]; then
		echo "== $name: no tests yet, skipped"
		return 0
	fi
	echo "== $name"
	"$GODOT" --headless --path . -s addons/gut/gut_cmdln.gd -gdir="$dir" -ginclude_subdirs -gexit -glog=1 >"$log" 2>&1
	local code=$?
	grep -E 'Scripts|Tests|Passing|Failing|Pending|Asserts|Time' "$log" | sed 's/^/   /'
	if [[ $code -ne 0 ]]; then
		echo "   FAILED (exit $code), log: $log"; grep -E 'FAILED|\[Failed\]' -A3 "$log" | head -40; FAILED=1
	elif grep -qE "$ERROR_PATTERN" "$log"; then
		echo "   FAILED: errors in output, log: $log"; grep -E "$ERROR_PATTERN" -A2 "$log" | head -40; FAILED=1
	fi
}

run_boot_smoke() {
	local log="$LOG_DIR/boot.log"
	echo "== boot (main scene, 60 frames)"
	"$GODOT" --headless --path . -- --smoke-test --frames 60 >"$log" 2>&1
	local code=$?
	if [[ $code -ne 0 ]] || grep -qE "$ERROR_PATTERN" "$log"; then
		echo "   FAILED (exit $code), log: $log"; grep -E "$ERROR_PATTERN" -A2 "$log" | head -40; FAILED=1
	else
		echo "   ok"
	fi
}

run_session() { # scripted 3-minute Practice session must log no errors (M2 acceptance)
	local log="$LOG_DIR/session.log"
	echo "== session (autoplay, 185 s game time)"
	"$GODOT" --headless --path . --audio-driver Dummy -- --autoplay --smoke-test --seconds 185 --bots 3 --seed 7 >"$log" 2>&1
	local code=$?
	if [[ $code -ne 0 ]] || grep -qE "$ERROR_PATTERN" "$log"; then
		echo "   FAILED (exit $code), log: $log"; grep -E "$ERROR_PATTERN" -A2 "$log" | head -40; FAILED=1
	else
		echo "   ok ($(grep -c 'autoplay\]' "$log") scripted steps, $(grep -c WARN "$log") warnings)"
	fi
}

run_pytest() { # suite-name dir
	local name="$1" dir="$2" log="$LOG_DIR/$1.log"
	echo "== $name"
	(cd "$ROOT/$dir" && python3 -m pytest -q -p no:cacheprovider) >"$log" 2>&1
	local code=$?
	tail -n 1 "$log" | sed 's/^/   /'
	if [[ $code -ne 0 ]]; then
		echo "   FAILED (exit $code), log: $log"; grep -E '^(FAILED|ERROR|E )' "$log" | head -30; FAILED=1
	fi
}

ensure_import() {
	# Refreshes the class_name cache (new scripts) and imports changed assets.
	"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
}

ensure_import
case "$SUITE" in
	unit) run_gut unit res://tests/unit ;;
	sim) run_gut sim res://tests/sim ;;
	integration) run_gut integration res://tests/integration ;;
	physics) run_gut physics res://tests/physics ;;
	ui) run_gut ui res://tests/ui ;;
	smoke) run_gut smoke res://tests/smoke; run_boot_smoke ;;
	session) run_session ;;
	lint) "$ROOT/scripts/lint.sh" || FAILED=1 ;;
	orchestrator) run_pytest orchestrator services/orchestrator ;;
	net) run_pytest net tests/net ;;
	all)
		"$ROOT/scripts/lint.sh" || FAILED=1
		run_gut unit res://tests/unit
		run_gut sim res://tests/sim
		run_gut integration res://tests/integration
		run_gut physics res://tests/physics
		run_gut ui res://tests/ui
		run_gut smoke res://tests/smoke
		run_boot_smoke
		run_session
		run_pytest orchestrator services/orchestrator
		run_pytest net tests/net
		;;
	*) echo "unknown suite: $SUITE" >&2; exit 2 ;;
esac

if [[ $FAILED -ne 0 ]]; then
	echo "TESTS FAILED"; exit 1
fi
echo "ALL GREEN ($SUITE)"
