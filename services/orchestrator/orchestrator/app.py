"""FastAPI application: public room API, loopback-only internal API, reaper task."""

from __future__ import annotations

import asyncio
import contextlib
from typing import AsyncIterator, Callable, Literal

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
from starlette.exceptions import HTTPException as StarletteHTTPException

from .auth import Authenticator, Identity, SteamVerifier
from .config import Config
from .errors import ApiError
from .logjson import log
from .ratelimit import RateLimiter
from .rooms import Room, RoomManager
from .spawner import PopenSpawner, Spawner

# ---------------------------------------------------------------------- request models


class CreateRoomBody(BaseModel):
    ticket: str = Field(max_length=8192)
    build: str = Field(max_length=128)
    display_name: str | None = Field(default=None, max_length=128)


class JoinRoomBody(CreateRoomBody):
    room_code: str | None = Field(default=None, max_length=16)
    room_id: str | None = Field(default=None, max_length=64)


class InternalBody(BaseModel):
    room_id: str = Field(max_length=64)
    room_secret: str = Field(max_length=256)


class VerifyBody(InternalBody):
    join_token: str = Field(max_length=256)


class HeartbeatBody(InternalBody):
    phase: Literal["lobby", "match", "results"]
    players: int = Field(ge=0, le=1000)
    player_uids: list[str] | None = Field(default=None, max_length=1000)


class ClosingBody(InternalBody):
    reason: str = Field(default="", max_length=500)


# ---------------------------------------------------------------------- app factory


def create_app(
    config: Config | None = None,
    *,
    spawner: Spawner | None = None,
    clock: Callable[[], float] | None = None,
    steam_verifier: SteamVerifier | None = None,
) -> FastAPI:
    """Build the orchestrator app. Raises ConfigError for unsafe configs (e.g. prod + dev auth)."""
    cfg = config or Config.from_env()
    cfg.validate()
    manager = RoomManager(cfg, spawner or PopenSpawner(), clock)
    authenticator = Authenticator(cfg, steam_verifier)
    limiter = RateLimiter(cfg.rate_limit_per_min, 60.0, clock)

    @contextlib.asynccontextmanager
    async def lifespan(_: FastAPI) -> AsyncIterator[None]:
        task: asyncio.Task[None] | None = None
        if cfg.reap_interval > 0:
            task = asyncio.create_task(_reaper(manager, cfg.reap_interval))
        log("orchestrator_started", build=cfg.build_id, env=cfg.env, auth_mode=cfg.auth_mode,
            bind=f"{cfg.bind_host}:{cfg.bind_port}", ports=f"{cfg.port_min}-{cfg.port_max}",
            max_rooms=cfg.max_rooms)
        try:
            yield
        finally:
            if task:
                task.cancel()
                with contextlib.suppress(asyncio.CancelledError):
                    await task
            await asyncio.to_thread(manager.shutdown)

    app = FastAPI(title="Better at Gambling Room Orchestrator", lifespan=lifespan,
                  docs_url=None, redoc_url=None, openapi_url=None)
    app.state.config = cfg
    app.state.manager = manager
    app.state.limiter = limiter

    # ------------------------------------------------------------------ errors
    @app.exception_handler(ApiError)
    async def _api_error(_: Request, exc: ApiError) -> JSONResponse:
        return JSONResponse(exc.body(), status_code=exc.status)

    @app.exception_handler(RequestValidationError)
    async def _validation_error(_: Request, exc: RequestValidationError) -> JSONResponse:
        fields = sorted({".".join(str(p) for p in e.get("loc", ())[1:]) for e in exc.errors()})
        return JSONResponse({"error": "bad_request", "message": f"Invalid or missing fields: {', '.join(fields)}"},
                            status_code=400)

    @app.exception_handler(StarletteHTTPException)
    async def _http_error(_: Request, exc: StarletteHTTPException) -> JSONResponse:
        code = {404: "not_found", 405: "method_not_allowed"}.get(exc.status_code, "http_error")
        return JSONResponse({"error": code, "message": str(exc.detail)}, status_code=exc.status_code)

    # ------------------------------------------------------------------ helpers
    def client_ip(request: Request) -> str:
        """Peer address, or the proxy-reported client when the peer is a trusted proxy (Caddy)."""
        peer = request.client.host if request.client else "unknown"
        fwd = request.headers.get("x-forwarded-for")
        if fwd and peer in cfg.trusted_proxies:
            return fwd.split(",")[-1].strip() or peer
        return peer

    def limit(key: str) -> None:
        if not limiter.hit(key):
            raise ApiError(429, "rate_limited", "Too many requests. Slow down and try again in a minute.")

    async def admit(request: Request, body: CreateRoomBody) -> Identity:
        """Rate-limit by IP, check build, authenticate, rate-limit by identity."""
        limit(f"ip:{client_ip(request)}")
        if body.build != cfg.build_id:
            raise ApiError(426, "version_mismatch", "Update required — restart Steam to update.",
                           server_build=cfg.build_id)
        ident = await authenticator.authenticate(body.ticket, body.display_name)
        limit(f"uid:{ident.player_uid}")
        return ident

    def room_reply(room: Room, token: str) -> dict[str, object]:
        return {"room_id": room.room_id, "room_code": room.code, "host": cfg.public_host,
                "port": room.port, "join_token": token}

    def internal(request: Request, body: InternalBody) -> Room:
        """Allow only direct loopback peers (no proxy headers) holding the room secret."""
        peer = request.client.host if request.client else ""
        proxied = "x-forwarded-for" in request.headers or "forwarded" in request.headers
        if peer not in cfg.loopback_hosts or proxied:
            log("internal_forbidden", level="warning", peer=peer, proxied=proxied)
            raise ApiError(403, "forbidden", "Internal endpoint.")
        return manager.authorize_room(body.room_id, body.room_secret)

    # ------------------------------------------------------------------ public routes
    @app.get("/healthz")
    async def healthz() -> dict[str, bool]:
        return {"ok": True}

    @app.get("/v1/status")
    async def status() -> dict[str, object]:
        return {"build": cfg.build_id, "rooms": len(manager.rooms), "max_rooms": cfg.max_rooms,
                "auth_mode": cfg.auth_mode}

    @app.post("/v1/rooms")
    async def create_room(body: CreateRoomBody, request: Request) -> dict[str, object]:
        ident = await admit(request, body)
        room, token = manager.create_room(ident)
        return room_reply(room, token)

    @app.post("/v1/rooms/join")
    async def join_room(body: JoinRoomBody, request: Request) -> dict[str, object]:
        ident = await admit(request, body)
        room, token = manager.join_room(ident, body.room_code, body.room_id)
        return room_reply(room, token)

    # ------------------------------------------------------------------ internal routes
    @app.post("/v1/internal/verify")
    async def verify(body: VerifyBody, request: Request) -> dict[str, str]:
        room = internal(request, body)
        ident = manager.verify_token(room, body.join_token)
        return {"player_uid": ident.player_uid, "steam_id": ident.player_uid, "display_name": ident.display_name}

    @app.post("/v1/internal/heartbeat")
    async def heartbeat(body: HeartbeatBody, request: Request) -> dict[str, bool]:
        room = internal(request, body)
        manager.heartbeat(room, body.phase, body.players, body.player_uids)
        return {"ok": True}

    @app.post("/v1/internal/closing")
    async def closing(body: ClosingBody, request: Request) -> dict[str, bool]:
        room = internal(request, body)
        manager.closing(room, body.reason)
        return {"ok": True}

    return app


async def _reaper(manager: RoomManager, interval: float) -> None:
    """Background loop calling :meth:`RoomManager.reap_once` every ``interval`` seconds."""
    while True:
        try:
            manager.reap_once()
        except Exception as exc:  # keep reaping no matter what
            log("reaper_error", level="error", error=repr(exc))
        await asyncio.sleep(interval)
