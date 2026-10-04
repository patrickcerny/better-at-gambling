#!/usr/bin/env bash
# Imports assets / rebuilds the class cache (first run, or after asset changes).
set -euo pipefail
source "$(dirname "$0")/_common.sh"
"$GODOT" --headless --path "$ROOT" --import
