#!/usr/bin/env bash
# Runs a headless dedicated game server. Extra args are passed through, e.g.
#   scripts/run_server.sh --port 24680 --dummies 3 --duration 5 --min-players 1
# Without an orchestrator it trusts client names (dev only) and never closes when empty.
set -euo pipefail
source "$(dirname "$0")/_common.sh"
ARGS=("$@")
[[ ${#ARGS[@]} -eq 0 ]] && ARGS=(--port 24680 --dummies 3 --duration 5 --min-players 1)
exec "$GODOT" --headless --path "$ROOT" -- --server "${ARGS[@]}"
