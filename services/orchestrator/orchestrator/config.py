"""Orchestrator configuration, read from environment variables."""

from __future__ import annotations

import os
import shlex
from dataclasses import dataclass, field
from typing import Mapping

DEFAULT_GAME_SERVER_CMD = "/opt/bag/BetterAtGamblingServer.x86_64 --headless --"


class ConfigError(ValueError):
    """Raised when the configuration is invalid or unsafe to run with."""


def _int(env: Mapping[str, str], key: str, default: int) -> int:
    raw = env.get(key, "").strip()
    if not raw:
        return default
    try:
        return int(raw)
    except ValueError as exc:
        raise ConfigError(f"{key} must be an integer, got {raw!r}") from exc


def _float(env: Mapping[str, str], key: str, default: float) -> float:
    raw = env.get(key, "").strip()
    if not raw:
        return default
    try:
        return float(raw)
    except ValueError as exc:
        raise ConfigError(f"{key} must be a number, got {raw!r}") from exc


def _csv(env: Mapping[str, str], key: str, default: str) -> frozenset[str]:
    raw = env.get(key, default)
    return frozenset(part.strip() for part in raw.split(",") if part.strip())


def _port_range(raw: str) -> tuple[int, int]:
    try:
        lo_s, hi_s = raw.split("-", 1)
        lo, hi = int(lo_s), int(hi_s)
    except ValueError as exc:
        raise ConfigError(f"PORT_RANGE must look like 24700-24799, got {raw!r}") from exc
    if not (1 <= lo <= hi <= 65535):
        raise ConfigError(f"PORT_RANGE out of bounds: {raw!r}")
    return lo, hi


@dataclass(frozen=True)
class Config:
    """All tunables of the orchestrator. Build with :meth:`from_env`, override in tests."""

    env: str = "dev"
    auth_mode: str = "dev"
    build_id: str = "dev"
    public_host: str = "127.0.0.1"
    bind_host: str = "127.0.0.1"
    bind_port: int = 8080
    port_min: int = 24700
    port_max: int = 24799
    max_rooms: int = 20
    max_players: int = 8
    game_server_cmd: tuple[str, ...] = tuple(shlex.split(DEFAULT_GAME_SERVER_CMD))
    game_server_cwd: str | None = None
    heartbeat_timeout: float = 30.0
    startup_timeout: float = 20.0
    reap_interval: float = 2.0
    kill_grace: float = 5.0
    join_token_ttl: float = 60.0
    steam_web_api_key: str = field(default="", repr=False)
    steam_app_id: str = ""
    steam_timeout: float = 5.0
    rate_limit_per_min: int = 30
    log_dir: str = "/tmp/bag-rooms"
    loopback_hosts: frozenset[str] = frozenset({"127.0.0.1", "::1"})
    trusted_proxies: frozenset[str] = frozenset({"127.0.0.1", "::1"})

    @classmethod
    def from_env(cls, env: Mapping[str, str] | None = None) -> "Config":
        """Build a config from ``env`` (defaults to ``os.environ``)."""
        e: Mapping[str, str] = os.environ if env is None else env
        lo, hi = _port_range(e.get("PORT_RANGE", "24700-24799"))
        cmd = tuple(shlex.split(e.get("GAME_SERVER_CMD", DEFAULT_GAME_SERVER_CMD)))
        if not cmd:
            raise ConfigError("GAME_SERVER_CMD must not be empty")
        return cls(
            env=e.get("ENV", "dev").strip().lower() or "dev",
            auth_mode=e.get("AUTH_MODE", "dev").strip().lower() or "dev",
            build_id=e.get("BUILD_ID", "dev").strip() or "dev",
            public_host=e.get("PUBLIC_HOST", "127.0.0.1").strip(),
            bind_host=e.get("BIND_HOST", "127.0.0.1").strip(),
            bind_port=_int(e, "BIND_PORT", 8080),
            port_min=lo,
            port_max=hi,
            max_rooms=_int(e, "MAX_ROOMS", 20),
            max_players=_int(e, "MAX_PLAYERS", 8),
            game_server_cmd=cmd,
            game_server_cwd=e.get("GAME_SERVER_CWD") or None,
            heartbeat_timeout=_float(e, "HEARTBEAT_TIMEOUT", 30.0),
            startup_timeout=_float(e, "STARTUP_TIMEOUT", 20.0),
            reap_interval=_float(e, "REAP_INTERVAL", 2.0),
            kill_grace=_float(e, "KILL_GRACE", 5.0),
            join_token_ttl=_float(e, "JOIN_TOKEN_TTL", 60.0),
            steam_web_api_key=e.get("STEAM_WEB_API_KEY", ""),
            steam_app_id=e.get("STEAM_APP_ID", "").strip(),
            steam_timeout=_float(e, "STEAM_TIMEOUT", 5.0),
            rate_limit_per_min=_int(e, "RATE_LIMIT_PER_MIN", 30),
            log_dir=e.get("LOG_DIR", "/tmp/bag-rooms"),
            loopback_hosts=_csv(e, "LOOPBACK_HOSTS", "127.0.0.1,::1"),
            trusted_proxies=_csv(e, "TRUSTED_PROXIES", "127.0.0.1,::1"),
        )

    def validate(self) -> None:
        """Raise :class:`ConfigError` if the config is unsafe or inconsistent."""
        if self.env not in ("dev", "production"):
            raise ConfigError(f"ENV must be dev or production, got {self.env!r}")
        if self.auth_mode not in ("dev", "steam"):
            raise ConfigError(f"AUTH_MODE must be dev or steam, got {self.auth_mode!r}")
        if self.env == "production" and self.auth_mode == "dev":
            raise ConfigError("Refusing to start: AUTH_MODE=dev is not allowed when ENV=production")
        if self.auth_mode == "steam" and (not self.steam_web_api_key or not self.steam_app_id):
            raise ConfigError("AUTH_MODE=steam requires STEAM_WEB_API_KEY and STEAM_APP_ID")
        if self.max_rooms < 1 or self.max_players < 1:
            raise ConfigError("MAX_ROOMS and MAX_PLAYERS must be >= 1")
        if self.rate_limit_per_min < 1:
            raise ConfigError("RATE_LIMIT_PER_MIN must be >= 1")

    @property
    def orchestrator_url(self) -> str:
        """URL game servers use to reach the internal API (always loopback-ish)."""
        host = self.bind_host
        if host in ("", "0.0.0.0"):
            host = "127.0.0.1"
        elif host == "::":
            host = "::1"
        if ":" in host:
            host = f"[{host}]"
        return f"http://{host}:{self.bind_port}"
