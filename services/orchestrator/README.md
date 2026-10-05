# Room Orchestrator

Small Python (3.11+, deployed on 3.12) FastAPI service that runs on the VPS behind Caddy
(see `docs/MASTER_PROMPT.md` §4.0 / §4.0.1). It authenticates players, spawns **one headless
Godot game-server process per room**, hands out single-use join tokens, tracks rooms through
heartbeats and reaps dead/finished processes, freeing their UDP port and room code.

**State is in memory only.** Restarting the orchestrator forgets every room; game servers that
are still running get `404 room_not_found` on their next heartbeat and must shut down. This is
an accepted V1 trade-off (no database).

## Layout

```
orchestrator/
  config.py     Config dataclass built from env vars (ConfigError on unsafe config)
  app.py        create_app(): routes, error handlers, reaper task in lifespan
  rooms.py      RoomManager: rooms, ports, codes, join tokens, heartbeats, reap_once()
  auth.py       dev:<name> tickets and Steam AuthenticateUserTicket (injectable verifier)
  spawner.py    Spawner interface, PopenSpawner (real) and FakeSpawner (tests)
  ratelimit.py  sliding-window limiter (per IP, per identity)
  codes.py      room codes / ids / secrets / join tokens
  errors.py     ApiError -> {"error": code, "message": text}
  logjson.py    JSON-lines logging to stdout
  __main__.py   python -m orchestrator
tests/          pytest suite (FakeSpawner + fake clock) and a real-process test
```

## Running

```sh
cd services/orchestrator
pip install -r requirements.txt
# local dev against the Godot editor binary:
GAME_SERVER_CMD="$(pwd)/../../tools/godot/godot --headless --path ../.. --" \
GAME_SERVER_CWD="$(pwd)/../.." BUILD_ID=dev python -m orchestrator
```

Production values live in `/etc/better-at-gambling/orchestrator.env` (never in the repo).
The process refuses to start (exit code 2, `config_error` log line) when `ENV=production` and
`AUTH_MODE=dev`, or when `AUTH_MODE=steam` lacks the key or app id.

## Testing

```sh
cd services/orchestrator
pip install -r requirements-dev.txt
python3 -m pytest -q        # ~3 s
```

## Environment variables

| Variable | Default | Meaning |
|---|---|---|
| `ENV` | `dev` | `dev` or `production` |
| `AUTH_MODE` | `dev` | `dev` (`dev:<name>` tickets) or `steam` |
| `BUILD_ID` | `dev` | Build string clients must send exactly (`build` field) |
| `PUBLIC_HOST` | `127.0.0.1` | Host returned to clients for the UDP connection |
| `BIND_HOST` / `BIND_PORT` | `127.0.0.1` / `8080` | HTTP listen address (keep loopback; Caddy proxies) |
| `PORT_RANGE` | `24700-24799` | UDP ports handed to game servers |
| `MAX_ROOMS` | `20` | Global room cap |
| `MAX_PLAYERS` | `8` | Players per room |
| `GAME_SERVER_CMD` | `/opt/bag/BetterAtGamblingServer.x86_64 --headless --` | Command prefix (shell-style, `shlex`-split) |
| `GAME_SERVER_CWD` | unset | Working directory for game servers |
| `LOG_DIR` | `/tmp/bag-rooms` | Per-room stdout/stderr log `room-<room_id>.log` (kept after exit for crash analysis) |
| `HEARTBEAT_TIMEOUT` | `30` | Seconds without heartbeat before a room is killed |
| `STARTUP_TIMEOUT` | `20` | Seconds allowed until the first heartbeat |
| `REAP_INTERVAL` | `2` | Reaper period in seconds (`0` disables the background task) |
| `KILL_GRACE` | `5` | SIGTERM → SIGKILL delay |
| `JOIN_TOKEN_TTL` | `60` | Join-token lifetime in seconds |
| `RATE_LIMIT_PER_MIN` | `30` | Public room calls per minute, per IP and per identity |
| `STEAM_WEB_API_KEY` | – | Publisher Web API key (steam mode; never logged) |
| `STEAM_APP_ID` | – | Steam app id (steam mode) |
| `STEAM_TIMEOUT` | `5` | Steam Web API timeout in seconds |
| `LOOPBACK_HOSTS` | `127.0.0.1,::1` | Peers allowed on `/v1/internal/*` |
| `TRUSTED_PROXIES` | `127.0.0.1,::1` | Peers whose `X-Forwarded-For` (last entry) is used as client IP for rate limits |

## Public API

All errors: `{"error": "<code>", "message": "<human text>", ...extra}`. Malformed bodies → `400 bad_request`.
Every room call is rate-limited per IP (before auth) and per identity (after auth) → `429 rate_limited`.

### `POST /v1/rooms`
Body `{"ticket": str, "build": str, "display_name"?: str}` →
`200 {"room_id", "room_code", "host", "port", "join_token"}`.

| Status | `error` | When |
|---|---|---|
| 401 | `bad_ticket` / `wrong_app` | ticket rejected (Steam error 102 = `wrong_app`) |
| 403 | `banned` | Steam reports `publisherbanned` |
| 409 | `already_owns_room` | caller owns a live room; body also has `room_code`, `room_id` |
| 426 | `version_mismatch` | `build != BUILD_ID` ("Update required — restart Steam to update"); body has `server_build` |
| 500 | `spawn_failed` | process could not be started |
| 503 | `capacity` / `no_ports` / `auth_unavailable` | room cap / port pool exhausted / Steam unreachable, timed out or rejected our key |

### `POST /v1/rooms/join`
Body `{"ticket", "build", "display_name"?, "room_code"? | "room_id"?}` (code is case-insensitive) →
`200 {"room_id", "room_code", "host", "port", "join_token"}`.
Errors: `404 room_not_found` (unknown, closing or dying), `409 room_full`, `409 room_in_progress`,
plus the auth/version/rate errors above. A room still `starting` is joinable (the client retries the UDP connect).
A **reconnecting member** (uid previously verified in this room, or listed in a heartbeat's `player_uids`)
is always admitted while the room is `starting`/`running`, regardless of phase or fullness.
Fullness = heartbeat `players` + unexpired join tokens of players not in `player_uids`.

### `GET /v1/status` → `{"build", "rooms", "max_rooms", "auth_mode"}` · `GET /healthz` → `{"ok": true}`

### Auth
* `AUTH_MODE=dev`: ticket `dev:<name>` (1–24 printable chars) → `player_uid = "dev:<name>"`, `display_name = <name>`.
* `AUTH_MODE=steam`: ticket = hex string from GodotSteam `getAuthTicketForWebApi("better-at-gambling")`.
  The orchestrator calls `ISteamUserAuth/AuthenticateUserTicket/v1` with `identity=better-at-gambling`;
  `player_uid` = SteamID64 string, `display_name` = sanitized body `display_name` or `"Player"`.

## Contract with the game server

### Launch
```
<GAME_SERVER_CMD...> --server --port <udp_port> --room-id <room_id> --room-code <ROOMC>
    --room-secret <secret> --orchestrator http://127.0.0.1:8080 --build <BUILD_ID>
```
e.g. `BetterAtGamblingServer.x86_64 --headless -- --server --port 24700 --room-id 3f2c… --room-code KX7PQ --room-secret … --orchestrator http://127.0.0.1:8080 --build 1.0.3`
(in Godot read them with `OS.get_cmdline_user_args()`). The process runs in its own process group with
stdout/stderr redirected to `LOG_DIR/room-<room_id>.log`. It is stopped with SIGTERM, then SIGKILL after `KILL_GRACE`.

### Internal endpoints (loopback only, no proxy headers; `room_secret` must match)
Common failures: `403 forbidden` (not loopback or wrong secret), `404 room_not_found` (orchestrator does not
know the room, e.g. it restarted — **the game server must shut down**), `400 bad_request`.

| Call | Body | Response |
|---|---|---|
| `POST /v1/internal/verify` — on **every** client connect (from `hello`) | `{"room_id", "room_secret", "join_token"}` | `200 {"player_uid", "steam_id", "display_name"}` (`steam_id` == `player_uid`); `403 bad_token` if unknown, used, expired or for another room. Tokens are single-use; success records the uid as a room member (for reconnects). |
| `POST /v1/internal/heartbeat` — **every 5 s**, first one as soon as the ENet port is listening | `{"room_id", "room_secret", "phase": "lobby"\|"match"\|"results", "players": int, "player_uids"?: [str]}` | `200 {"ok": true}`. First heartbeat: `starting → running`. `phase != "lobby"` blocks new (non-member) joins. |
| `POST /v1/internal/closing` — before exiting on its own (e.g. empty for 120 s) | `{"room_id", "room_secret", "reason": str}` | `200 {"ok": true}`; room becomes `closing` (not joinable) and is reaped when the process exits. |

Timeouts: no first heartbeat within `STARTUP_TIMEOUT` (20 s) or no heartbeat for `HEARTBEAT_TIMEOUT`
(30 s) → the room is killed. A non-zero exit that was not preceded by `closing` is logged as `room_crashed`.

## Security notes
* Caddy must proxy only `/v1/rooms*`, `/v1/status`, `/healthz`; requests carrying `X-Forwarded-For`/`Forwarded`
  are refused on `/v1/internal/*` anyway, and every internal call also needs the room secret.
* Tickets, the Web API key, room secrets and join tokens are never logged. The room secret is visible in the
  game server's argv (`ps`) to local users; the VPS runs the service under a dedicated user.
