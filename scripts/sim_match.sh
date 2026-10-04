#!/usr/bin/env bash
# Headless bots-only match simulation at accelerated time; prints a JSON summary.
#   scripts/sim_match.sh [--bots 4] [--duration 5] [--timescale 20] [--seed 1]
set -euo pipefail
source "$(dirname "$0")/_common.sh"
exec "$GODOT" --headless --path "$ROOT" -- --sim-match --bots 4 --duration 5 --timescale 20 "$@"
