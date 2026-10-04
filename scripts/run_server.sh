#!/usr/bin/env bash
# Runs a headless dedicated game server. Extra args are passed through, e.g.
#   scripts/run_server.sh --port 24680 --bots 3 --duration 5 --timescale 4 --autostart
set -euo pipefail
source "$(dirname "$0")/_common.sh"
ARGS=("$@")
[[ ${#ARGS[@]} -eq 0 ]] && ARGS=(--port 24680 --bots 3 --duration 5 --timescale 4 --autostart)
exec "$GODOT" --headless --path "$ROOT" -- --server "${ARGS[@]}"
