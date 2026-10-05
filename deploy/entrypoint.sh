#!/bin/sh
# BUILD_ID defaults to the game's own Protocol.BUILD_ID so clients and servers always agree.
set -e
if [ -z "${BUILD_ID:-}" ]; then
	BUILD_ID=$(sed -n 's/^const BUILD_ID: String = "\(.*\)"/\1/p' /opt/bag/game/core/net/protocol.gd)
	export BUILD_ID
fi
mkdir -p "${LOG_DIR:-/var/log/bag-rooms}"
exec /opt/bag/venv/bin/python -m orchestrator "$@"
