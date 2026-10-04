#!/usr/bin/env bash
# Runs a windowed client connecting to a server. Extra args are passed through, e.g.
#   scripts/run_client.sh --connect 127.0.0.1:24680 --name P2
set -euo pipefail
source "$(dirname "$0")/_common.sh"
ARGS=("$@")
[[ ${#ARGS[@]} -eq 0 ]] && ARGS=(--connect 127.0.0.1:24680 --name P2)
exec "$GODOT" --path "$ROOT" -- "${ARGS[@]}"
