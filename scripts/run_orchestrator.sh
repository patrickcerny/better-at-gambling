#!/usr/bin/env bash
# Runs the room orchestrator locally (dev auth) spawning game servers from this checkout.
# Clients then use: --orchestrator http://127.0.0.1:8080 --create-room | --join-code ABCDE
set -euo pipefail
source "$(dirname "$0")/_common.sh"
BUILD=$(sed -n 's/^const BUILD_ID: String = "\(.*\)"/\1/p' "$ROOT/core/net/protocol.gd")
export BUILD_ID="${BUILD_ID:-$BUILD}"
export GAME_SERVER_CMD="${GAME_SERVER_CMD:-$GODOT --headless --path $ROOT --audio-driver Dummy --}"
export GAME_SERVER_CWD="${GAME_SERVER_CWD:-$ROOT}"
export LOG_DIR="${LOG_DIR:-$ROOT/build/rooms}"
cd "$ROOT/services/orchestrator"
exec python3 -m orchestrator "$@"
