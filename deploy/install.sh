#!/usr/bin/env bash
# Installs or updates the Better at Gambling servers on a Debian/Ubuntu VPS:
#   curl -fsSL https://raw.githubusercontent.com/patrickcerny/better-at-gambling/main/deploy/install.sh | bash -s -- [options]
# As root it installs Docker if needed and lives in /opt + /etc. As a normal user in the docker
# group it needs no sudo at all: code in ~/better-at-gambling, config in ~/.config/better-at-gambling.
# Options:
#   --public-host H    address clients use for UDP (default: this machine's public IP)
#   --domain D         serve HTTPS on D (DNS must point here, needs ports 80/443 free)
#   --http-port P      plain HTTP on port P when there is no domain (default 80; e.g. 4300 next to
#                      an existing web server)
#   --max-rooms N      concurrent rooms (default 20; each room is one ~180 MB server process)
#   --branch B         git branch to deploy (default main)
#   --firewall         open 22/80/443 tcp + 24700-24799 udp in ufw and enable it
#   --no-auto-update   don't install the timer that redeploys when the branch moves
#   --update           (used by the timer) redeploy only if the branch has new commits
# Re-running is safe. A failed health check rolls back to the previous image.
set -euo pipefail

REPO_URL="https://github.com/patrickcerny/better-at-gambling.git"
if [[ $EUID -eq 0 ]]; then
	DIR=/opt/better-at-gambling
	ETC=/etc/better-at-gambling
else
	DIR="$HOME/better-at-gambling"
	ETC="$HOME/.config/better-at-gambling"
fi
BRANCH=main
HTTP_PORT=80
HTTP_PORT_SET=0
MAX_ROOMS=20
PUBLIC_HOST=""
DOMAIN=""
FIREWALL=0
AUTO_UPDATE=1
UPDATE_ONLY=0

while [[ $# -gt 0 ]]; do
	case "$1" in
		--public-host) PUBLIC_HOST="$2"; shift 2 ;;
		--domain) DOMAIN="$2"; shift 2 ;;
		--http-port) HTTP_PORT="$2"; HTTP_PORT_SET=1; shift 2 ;;
		--max-rooms) MAX_ROOMS="$2"; shift 2 ;;
		--branch) BRANCH="$2"; shift 2 ;;
		--firewall) FIREWALL=1; shift ;;
		--no-auto-update) AUTO_UPDATE=0; shift ;;
		--update) UPDATE_ONLY=1; shift ;;
		*) echo "unknown option: $1" >&2; exit 2 ;;
	esac
done

log() { echo "[bag-install] $*"; }

# 1. Packages: git, curl, Docker with the compose plugin.
if [[ $EUID -eq 0 ]]; then
	if ! command -v git >/dev/null || ! command -v curl >/dev/null; then
		apt-get update -q && apt-get install -yq git curl ca-certificates
	fi
	if ! command -v docker >/dev/null || ! docker compose version >/dev/null 2>&1; then
		log "installing Docker"
		curl -fsSL https://get.docker.com | sh
	fi
	systemctl enable --now docker >/dev/null 2>&1 || true
else
	for tool in git curl docker; do
		command -v "$tool" >/dev/null || { echo "$tool is missing; install it or run as root" >&2; exit 1; }
	done
	docker compose version >/dev/null 2>&1 && docker info >/dev/null 2>&1 \
		|| { echo "this user can't run docker compose (join the docker group or run as root)" >&2; exit 1; }
	[[ $FIREWALL -eq 0 ]] || { echo "--firewall needs root" >&2; exit 1; }
fi

# 2. Code.
if [[ -d "$DIR/.git" ]]; then
	git -C "$DIR" fetch -q origin "$BRANCH"
	if [[ $UPDATE_ONLY -eq 1 && "$(git -C "$DIR" rev-parse HEAD)" == "$(git -C "$DIR" rev-parse "origin/$BRANCH")" ]]; then
		exit 0  # nothing new
	fi
	git -C "$DIR" checkout -q -B "$BRANCH" "origin/$BRANCH"
else
	log "cloning $REPO_URL ($BRANCH)"
	git clone -q --branch "$BRANCH" "$REPO_URL" "$DIR"
fi
REV=$(git -C "$DIR" rev-parse --short HEAD)
log "deploying $REV"

# 3. Config (kept across updates; edit $ETC/orchestrator.env and re-run to change it).
mkdir -p "$ETC"
if [[ ! -f "$ETC/orchestrator.env" ]]; then
	[[ -n "$PUBLIC_HOST" ]] || PUBLIC_HOST=$(curl -fsS4 --max-time 5 https://api.ipify.org || hostname -I | awk '{print $1}')
	cat >"$ETC/orchestrator.env" <<CONF
# Better at Gambling orchestrator. Never commit this file.
ENV=dev
AUTH_MODE=dev
PUBLIC_HOST=$PUBLIC_HOST
BIND_HOST=127.0.0.1
BIND_PORT=$((HTTP_PORT == 4301 ? 4302 : 4301))
PORT_RANGE=24700-24799
MAX_ROOMS=$MAX_ROOMS
# BUILD_ID defaults to the deployed game's build; set it only to override.
# Caddy: a domain for HTTPS, or :PORT for plain HTTP on the IP (dev only).
BAG_SITE=${DOMAIN:-:$HTTP_PORT}
CONF
	chmod 600 "$ETC/orchestrator.env"
	log "wrote $ETC/orchestrator.env (public host $PUBLIC_HOST)"
elif [[ -n "$DOMAIN" ]]; then
	sed -i "s|^BAG_SITE=.*|BAG_SITE=$DOMAIN|" "$ETC/orchestrator.env"
elif [[ $HTTP_PORT_SET -eq 1 ]]; then
	sed -i "s|^BAG_SITE=.*|BAG_SITE=:$HTTP_PORT|" "$ETC/orchestrator.env"
fi
# docker compose reads deploy/.env (git-ignored) to find the config file.
echo "BAG_ENV_FILE=$ETC/orchestrator.env" >"$DIR/deploy/.env"
API="http://127.0.0.1:$(sed -n 's/^BIND_PORT=//p' "$ETC/orchestrator.env")"

# 4. Firewall (opt-in: enabling ufw on a box with other services is the owner's call).
if [[ $FIREWALL -eq 1 ]]; then
	command -v ufw >/dev/null || apt-get install -yq ufw
	ufw allow OpenSSH >/dev/null; ufw allow 22/tcp >/dev/null
	ufw allow 80/tcp >/dev/null; ufw allow 443/tcp >/dev/null
	ufw allow 24700:24799/udp >/dev/null
	ufw --force enable >/dev/null
	log "ufw enabled: 22, 80, 443/tcp and 24700-24799/udp open"
fi

# 5. Build, start, health check, roll back on failure.
cd "$DIR/deploy"
if docker image inspect better-at-gambling:current >/dev/null 2>&1; then
	docker tag better-at-gambling:current better-at-gambling:previous
fi
log "building image (first build downloads Godot, a few minutes)"
docker compose build -q orchestrator
docker compose up -d --remove-orphans
healthy=0
for _ in $(seq 1 30); do
	if curl -fsS --max-time 3 $API/healthz >/dev/null 2>&1; then healthy=1; break; fi
	sleep 2
done
if [[ $healthy -ne 1 ]]; then
	log "health check FAILED for $REV"
	docker compose logs --tail 40 orchestrator || true
	if docker image inspect better-at-gambling:previous >/dev/null 2>&1; then
		log "rolling back to the previous image"
		docker tag better-at-gambling:previous better-at-gambling:current
		docker compose up -d --no-build
	fi
	exit 1
fi
echo "$REV" >"$ETC/deployed_rev"
log "healthy: $(curl -fsS $API/v1/status)"

# 6. Auto-update: redeploy when the branch moves (milestones land on main when they're green).
if [[ $AUTO_UPDATE -eq 1 && $EUID -ne 0 ]]; then
	line="*/10 * * * * $DIR/deploy/install.sh --update --branch $BRANCH >>$ETC/update.log 2>&1"
	(crontab -l 2>/dev/null | grep -v 'better-at-gambling/deploy/install.sh'; echo "$line") | crontab -
	log "auto-update cron job active (every 10 min from $BRANCH)"
elif [[ $AUTO_UPDATE -eq 1 ]]; then
	install -m 755 "$DIR/deploy/install.sh" /usr/local/sbin/bag-install
	cat >/etc/systemd/system/bag-update.service <<UNIT
[Unit]
Description=Better at Gambling: redeploy if $BRANCH moved
After=docker.service network-online.target
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/bag-install --update --branch $BRANCH
UNIT
	cat >/etc/systemd/system/bag-update.timer <<UNIT
[Unit]
Description=Check for Better at Gambling updates every 10 minutes
[Timer]
OnBootSec=5min
OnUnitActiveSec=10min
[Install]
WantedBy=timers.target
UNIT
	systemctl daemon-reload
	systemctl enable --now bag-update.timer >/dev/null
	log "auto-update timer active (every 10 min from $BRANCH)"
fi
site=$(sed -n 's/^BAG_SITE=//p' "$ETC/orchestrator.env")
if [[ "$site" == :* ]]; then
	url="http://$(sed -n 's/^PUBLIC_HOST=//p' "$ETC/orchestrator.env")$([[ "$site" == ":80" ]] || echo "$site")"
else
	url="https://$site"
fi
log "done. Clients: --orchestrator $url"
