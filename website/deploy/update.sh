#!/usr/bin/env bash
# Pulls the newest website from GitHub. Run from anywhere; nginx serves the files directly.
set -euo pipefail
cd "$(dirname "$0")/../.."
git fetch -q origin "${1:-main}"
git checkout -q "${1:-main}"
git reset -q --hard "origin/${1:-main}"
echo "website at $(git log -1 --format='%h %s')"
