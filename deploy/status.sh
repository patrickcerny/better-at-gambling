#!/usr/bin/env bash
# Quick health view on the VPS: containers, orchestrator status, room processes, recent errors.
set -uo pipefail
cd "$(dirname "$0")"
envfile=$(sed -n 's/^BAG_ENV_FILE=//p' .env 2>/dev/null)
envfile=${envfile:-/etc/better-at-gambling/orchestrator.env}
port=$(sed -n 's/^BIND_PORT=//p' "$envfile" 2>/dev/null)
echo "== deployed: $(cat "$(dirname "$envfile")/deployed_rev" 2>/dev/null || echo '?')"
docker compose ps
echo "== status: $(curl -fsS "http://127.0.0.1:${port:-8080}/v1/status" || echo unreachable)"
echo "== room processes"
ps -eo pid,etime,pcpu,rss,args | grep -- '--server --port' | grep -v grep || echo "(none)"
echo "== recent orchestrator warnings"
docker compose logs --since 1h orchestrator 2>/dev/null | grep -iE '"level": ?"(warning|error|critical)"' | tail -20
