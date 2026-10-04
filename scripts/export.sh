#!/usr/bin/env bash
# Exports a release build: scripts/export.sh linux|windows|server
set -euo pipefail
source "$(dirname "$0")/_common.sh"
case "${1:-}" in
	linux) PRESET="Linux"; OUT="build/linux/BetterAtGambling.x86_64" ;;
	windows) PRESET="Windows"; OUT="build/windows/BetterAtGambling.exe" ;;
	server) PRESET="Linux Server"; OUT="build/server/bag_server.x86_64" ;;
	*) echo "usage: $0 linux|windows|server" >&2; exit 2 ;;
esac
mkdir -p "$ROOT/$(dirname "$OUT")"
"$GODOT" --headless --path "$ROOT" --export-release "$PRESET" "$ROOT/$OUT"
ls -la "$ROOT/$OUT"
