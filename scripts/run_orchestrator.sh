#!/usr/bin/env bash
# Runs the room orchestrator locally (dev auth). Implemented in M3.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/services/orchestrator"
exec python3 -m uvicorn app.main:app --host 127.0.0.1 --port "${PORT:-8080}" "$@"
