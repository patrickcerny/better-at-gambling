"""In-memory room registry: create/join, join tokens, heartbeats, reaping.

All state lives in this process; an orchestrator restart forgets every room
(running game servers then fail their next heartbeat with 404 and exit).
Methods are synchronous and are called from the single asyncio event loop,
so no locking is needed.
"""

from __future__ import annotations

import hmac
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

from . import codes
from .auth import Identity
from .config import Config
from .errors import ApiError
from .logjson import log
from .spawner import ProcessHandle, Spawner

PHASES = ("lobby", "match", "results")

# Room states.
STARTING = "starting"  # process spawned, no heartbeat yet (joinable; clients retry connecting)
RUNNING = "running"  # heartbeating
CLOSING = "closing"  # game server announced shutdown; not joinable, reaped on exit
DEAD = "dead"  # orchestrator is killing it; not joinable, reaped on exit


@dataclass
class JoinToken:
    """A single-use, room-bound, short-lived permission to connect."""

    token: str
    room_id: str
    identity: Identity
    expires_at: float


@dataclass
class Room:
    """One game-server process and its bookkeeping."""

    room_id: str
    code: str
    secret: str
    port: int
    owner_uid: str
    created_at: float
    process: ProcessHandle
    state: str = STARTING
    phase: str = "lobby"
    players: int = 0
    player_uids: list[str] = field(default_factory=list)
    members: set[str] = field(default_factory=set)
    last_heartbeat: float | None = None
    kill_requested_at: float | None = None

    @property
    def joinable(self) -> bool:
        return self.state in (STARTING, RUNNING)


class RoomManager:
    """Owns all rooms, ports, codes and join tokens."""

    def __init__(self, config: Config, spawner: Spawner, clock: Callable[[], float] | None = None) -> None:
        self.config = config
        self.spawner = spawner
        self.clock = clock or time.monotonic
        self.rooms: dict[str, Room] = {}
        self.tokens: dict[str, JoinToken] = {}

    # ------------------------------------------------------------------ lookups
    def by_code(self, code: str) -> Room | None:
        norm = codes.normalize_room_code(code)
        return next((r for r in self.rooms.values() if r.code == norm), None)

    def used_ports(self) -> set[int]:
        return {r.port for r in self.rooms.values()}

    def free_port(self) -> int | None:
        used = self.used_ports()
        return next((p for p in range(self.config.port_min, self.config.port_max + 1) if p not in used), None)

    def owned_room(self, uid: str) -> Room | None:
        return next((r for r in self.rooms.values() if r.owner_uid == uid and r.joinable), None)

    def occupancy(self, room: Room, now: float, exclude_uid: str | None = None) -> int:
        """Players reported by heartbeat plus unexpired tokens of players not yet connected.

        ``exclude_uid``'s own pending token is ignored (re-requesting replaces it).
        """
        present = set(room.player_uids) | ({exclude_uid} if exclude_uid else set())
        pending = {
            t.identity.player_uid
            for t in self.tokens.values()
            if t.room_id == room.room_id and t.expires_at > now and t.identity.player_uid not in present
        }
        return room.players + len(pending)

    # ------------------------------------------------------------------ public API
    def create_room(self, ident: Identity) -> tuple[Room, str]:
        """Spawn a new room owned by ``ident``; return it and the owner's join token."""
        now = self.clock()
        existing = self.owned_room(ident.player_uid)
        if existing:
            raise ApiError(
                409, "already_owns_room", "You already have a room running; rejoin it instead.",
                room_code=existing.code, room_id=existing.room_id,
            )
        if len(self.rooms) >= self.config.max_rooms:
            raise ApiError(503, "capacity", "All servers are busy. Please try again in a few minutes.")
        port = self.free_port()
        if port is None:
            raise ApiError(503, "no_ports", "No free server ports. Please try again in a few minutes.")
        room_id = codes.new_room_id()
        code = codes.new_room_code({r.code for r in self.rooms.values()})
        secret = codes.new_room_secret()
        argv = [
            *self.config.game_server_cmd,
            "--server", "--port", str(port), "--room-id", room_id, "--room-code", code,
            "--room-secret", secret, "--orchestrator", self.config.orchestrator_url,
            "--build", self.config.build_id,
        ]
        log_path = Path(self.config.log_dir) / f"room-{room_id}.log"
        try:
            process = self.spawner.spawn(argv, self.config.game_server_cwd, log_path)
        except OSError as exc:
            log("room_spawn_failed", level="error", room_id=room_id, port=port, error=type(exc).__name__)
            raise ApiError(500, "spawn_failed", "Could not start a game server. Please try again.") from None
        room = Room(
            room_id=room_id, code=code, secret=secret, port=port, owner_uid=ident.player_uid,
            created_at=now, process=process,
        )
        self.rooms[room_id] = room
        log("room_created", room_id=room_id, room_code=code, port=port, pid=process.pid,
            owner=ident.player_uid, log_file=str(log_path))
        return room, self._issue_token(room, ident, now)

    def join_room(self, ident: Identity, room_code: str | None, room_id: str | None) -> tuple[Room, str]:
        """Admit ``ident`` to a room and return a join token, or raise ApiError."""
        now = self.clock()
        room = self.rooms.get(room_id) if room_id else (self.by_code(room_code) if room_code else None)
        if not room_id and not room_code:
            raise ApiError(400, "bad_request", "Provide room_code or room_id.")
        if room is None or not room.joinable:
            raise ApiError(404, "room_not_found", "That room does not exist or has closed.")
        if ident.player_uid not in room.members:
            if room.phase != "lobby":
                raise ApiError(409, "room_in_progress", "That match is already in progress.")
            if self.occupancy(room, now, ident.player_uid) >= self.config.max_players:
                raise ApiError(409, "room_full", "That room is full.")
        token = self._issue_token(room, ident, now)
        log("room_join_issued", room_id=room.room_id, player=ident.player_uid,
            reconnect=ident.player_uid in room.members)
        return room, token

    def _issue_token(self, room: Room, ident: Identity, now: float) -> str:
        # One outstanding token per (room, player): drop older ones so they don't inflate occupancy.
        for key in [k for k, t in self.tokens.items()
                    if t.room_id == room.room_id and t.identity.player_uid == ident.player_uid]:
            del self.tokens[key]
        token = codes.new_join_token()
        self.tokens[token] = JoinToken(token, room.room_id, ident, now + self.config.join_token_ttl)
        return token

    # ------------------------------------------------------------------ internal API
    def authorize_room(self, room_id: str, secret: str) -> Room:
        """Return the room if ``secret`` matches, else raise 404/403."""
        room = self.rooms.get(room_id)
        if room is None:
            raise ApiError(404, "room_not_found", "Unknown room; shut down.")
        if not hmac.compare_digest(room.secret.encode(), secret.encode()):
            log("internal_bad_secret", level="warning", room_id=room_id)
            raise ApiError(403, "forbidden", "Bad room secret.")
        return room

    def verify_token(self, room: Room, token: str) -> Identity:
        """Consume a join token for ``room``; return the player identity."""
        now = self.clock()
        jt = self.tokens.get(token)
        if jt is None or jt.room_id != room.room_id:
            raise ApiError(403, "bad_token", "Join token is invalid, used, or for another room.")
        del self.tokens[token]
        if jt.expires_at <= now:
            raise ApiError(403, "bad_token", "Join token expired.")
        room.members.add(jt.identity.player_uid)
        log("player_verified", room_id=room.room_id, player=jt.identity.player_uid)
        return jt.identity

    def heartbeat(self, room: Room, phase: str, players: int, player_uids: list[str] | None) -> None:
        """Record a heartbeat; the first one moves the room to ``running``."""
        now = self.clock()
        room.last_heartbeat = now
        room.phase = phase
        room.players = players
        if player_uids is not None:
            room.player_uids = list(player_uids)
            room.members.update(player_uids)
        if room.state == STARTING:
            room.state = RUNNING
            log("room_running", room_id=room.room_id, startup_s=round(now - room.created_at, 3))

    def closing(self, room: Room, reason: str) -> None:
        """The game server announced it is shutting down."""
        if room.state in (STARTING, RUNNING):
            room.state = CLOSING
            log("room_closing", room_id=room.room_id, reason=reason[:200])

    # ------------------------------------------------------------------ reaping
    def _kill(self, room: Room, now: float, reason: str) -> None:
        log("room_killed", level="warning", room_id=room.room_id, reason=reason, pid=room.process.pid)
        room.state = DEAD
        room.kill_requested_at = now
        room.process.terminate()

    def reap_once(self, now: float | None = None) -> None:
        """One reaper pass: time out rooms, escalate kills, remove exited processes."""
        now = self.clock() if now is None else now
        for key in [k for k, t in self.tokens.items() if t.expires_at <= now]:
            del self.tokens[key]
        for room in list(self.rooms.values()):
            rc = room.process.poll()
            if rc is None:
                if room.state == STARTING and now - room.created_at > self.config.startup_timeout:
                    self._kill(room, now, "startup_timeout")
                elif room.state in (RUNNING, CLOSING) and room.last_heartbeat is not None \
                        and now - room.last_heartbeat > self.config.heartbeat_timeout:
                    self._kill(room, now, "heartbeat_timeout")
                elif room.state == DEAD and room.kill_requested_at is not None \
                        and now - room.kill_requested_at >= self.config.kill_grace:
                    log("room_sigkill", level="warning", room_id=room.room_id, pid=room.process.pid)
                    room.process.kill()
                rc = room.process.poll()
            if rc is not None:
                self._remove(room, rc)

    def _remove(self, room: Room, rc: int) -> None:
        del self.rooms[room.room_id]
        for key in [k for k, t in self.tokens.items() if t.room_id == room.room_id]:
            del self.tokens[key]
        expected = room.state in (CLOSING, DEAD)
        if rc != 0 and not expected:
            log("room_crashed", level="error", room_id=room.room_id, exit_code=rc, state=room.state,
                log_file=str(Path(self.config.log_dir) / f"room-{room.room_id}.log"))
        log("room_reaped", room_id=room.room_id, exit_code=rc, state=room.state, port=room.port)

    def shutdown(self, wait: float | None = None) -> None:
        """Terminate every child, wait up to ``wait`` s (default kill_grace), then SIGKILL."""
        wait = self.config.kill_grace if wait is None else wait
        for room in self.rooms.values():
            if room.process.poll() is None:
                room.process.terminate()
        deadline = time.monotonic() + wait
        while time.monotonic() < deadline and any(r.process.poll() is None for r in self.rooms.values()):
            time.sleep(0.05)
        for room in list(self.rooms.values()):
            if room.process.poll() is None:
                room.process.kill()
        end = time.monotonic() + 1.0
        while time.monotonic() < end and any(r.process.poll() is None for r in self.rooms.values()):
            time.sleep(0.02)
        for room in list(self.rooms.values()):
            room.state = DEAD
            self._remove(room, room.process.poll() if room.process.poll() is not None else -9)
        log("orchestrator_shutdown")
