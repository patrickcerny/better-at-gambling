# Deploying the servers

One orchestrator (FastAPI) starts one headless Godot server process per party. Both run in a
Docker container on the host network; Caddy sits in front of the orchestrator's public API.

## Install / update

```
curl -fsSL https://raw.githubusercontent.com/patrickcerny/better-at-gambling/main/deploy/install.sh | bash -s -- [options]
```

- **As a docker-group user (no sudo):** code in `~/better-at-gambling`, config in
  `~/.config/better-at-gambling/orchestrator.env`, auto-update via a user cron job.
- **As root:** installs Docker if missing, code in `/opt/better-at-gambling`, config in
  `/etc/better-at-gambling`, auto-update via the `bag-update.timer` systemd timer.

Options: `--http-port P` (plain HTTP on P, default 80), `--domain D` (HTTPS via Let's Encrypt,
needs 80/443), `--max-rooms N`, `--public-host H`, `--branch B`, `--firewall` (root, enables ufw),
`--no-auto-update`. The auto-updater re-runs the script with `--update` every 10 minutes and
redeploys when the branch moved, but only while no party is running (a redeploy restarts every room). A failed health check rolls back to the previous image.

Clients need TCP to the HTTP port and UDP 24700–24799 (`PORT_RANGE`). The internal API
(`/v1/internal/*`) only answers game servers on loopback and is 404 through Caddy.

## Current VPS (owner's netcup box, 152.53.33.53)

Installed as `admin` without sudo: `--http-port 4300 --max-rooms 8`. Ports 80/443 belong to the
host nginx (other sites) and 8080 to another container, so the backend lives on
`http://152.53.33.53:4300` (orchestrator on 127.0.0.1:4301). About 2 GB RAM is free and each room
uses ~180 MB, which is why rooms are capped at 8. The client default in
`data/online/online_config.tres` points there.

## Operate

- `deploy/status.sh` (in the install dir): deployed revision, containers, `/v1/status`, room
  processes, recent warnings.
- Logs: `docker compose logs -f orchestrator` in `deploy/`; per-room logs in the `room-logs` volume.
- Change settings: edit `orchestrator.env`, then re-run `deploy/install.sh`.
