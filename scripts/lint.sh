#!/usr/bin/env bash
# Static checks: Godot parses every script with untyped declarations as errors
# (project setting), plus a grep for untyped `var`/params in project code.
set -uo pipefail
source "$(dirname "$0")/_common.sh"
cd "$ROOT"
FAILED=0
echo "== lint"
FILES=$(git ls-files --cached --others --exclude-standard '*.gd' | grep -vE '^(addons|tools/godot)/')
# `var x = ...` without a type or := ; allow `for x in` loops.
BAD=$(grep -nE '^\s*(static\s+)?var\s+[a-zA-Z_][a-zA-Z0-9_]*\s*=' $FILES 2>/dev/null || true)
if [[ -n "$BAD" ]]; then
	echo "   untyped var declarations:"; echo "$BAD" | sed 's/^/   /'; FAILED=1
fi
BAD=$(grep -nE '^\s*print\(' $(echo "$FILES" | grep -vE '^(tools|tests)/' | grep -v 'services/log.gd') 2>/dev/null || true)
if [[ -n "$BAD" ]]; then
	echo "   bare print() outside Log (use Log.info):"; echo "$BAD" | sed 's/^/   /'; FAILED=1
fi
# Parse check: load every script through the engine (catches untyped declarations as errors).
LOG="$ROOT/build/test-logs/lint-parse.log"; mkdir -p "$(dirname "$LOG")"
"$GODOT" --headless --path . -s tools/check_scripts.gd >"$LOG" 2>&1
CODE=$?
if [[ $CODE -ne 0 ]] || grep -qE "$ERROR_PATTERN" "$LOG"; then
	echo "   script parse errors (log: $LOG):"; grep -E "$ERROR_PATTERN" -A2 "$LOG" | head -40; FAILED=1
fi
[[ $FAILED -eq 0 ]] && echo "   ok"
exit $FAILED
