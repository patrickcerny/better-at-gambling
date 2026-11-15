#!/usr/bin/env bash
# Pulls the newest website from GitHub (default: the branch this clone is on) and restarts the
# container. A restart, not an nginx reload: site.conf is bind-mounted as a single file, and git
# replaces that file, so a running container keeps the old copy.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
cd "$here/../.."
branch="${1:-$(git rev-parse --abbrev-ref HEAD)}"
git fetch -q origin "$branch"
git reset -q --hard "origin/$branch"
cd "$here" && docker compose up -d && docker compose restart web >/dev/null
echo "website at $(git log -1 --format='%h %s')"
