"""Player authentication: ``dev:<name>`` tickets or Steam Web API tickets.

Tickets and the publisher Web API key are never logged.
"""

from __future__ import annotations

import logging
import re
import unicodedata
from dataclasses import dataclass
from typing import Any, Awaitable, Callable

import httpx

from .config import Config
from .errors import ApiError
from .logjson import log

STEAM_AUTH_URL = "https://partner.steam-api.com/ISteamUserAuth/AuthenticateUserTicket/v1/"
STEAM_IDENTITY = "better-at-gambling"
MAX_NAME_LEN = 24

# httpx logs full request URLs (which would contain the key) at INFO level.
logging.getLogger("httpx").setLevel(logging.WARNING)
logging.getLogger("httpcore").setLevel(logging.WARNING)


class SteamUnavailable(Exception):
    """Steam could not be reached, timed out, or rejected our publisher key."""


#: ``async (ticket) -> parsed JSON`` of AuthenticateUserTicket. Raises SteamUnavailable.
SteamVerifier = Callable[[str], Awaitable[dict[str, Any]]]


@dataclass(frozen=True)
class Identity:
    """A verified player."""

    player_uid: str
    display_name: str


def sanitize_display_name(raw: str | None, fallback: str = "Player") -> str:
    """Strip control/format characters, collapse whitespace, cap at 24 chars."""
    if not raw:
        return fallback
    spaced = re.sub(r"\s+", " ", raw)
    cleaned = "".join(ch for ch in spaced if unicodedata.category(ch)[0] != "C")
    cleaned = re.sub(r" +", " ", cleaned).strip()[:MAX_NAME_LEN].strip()
    return cleaned or fallback


def make_steam_verifier(config: Config) -> SteamVerifier:
    """Build the real verifier that calls the Steam partner Web API."""

    async def verify(ticket: str) -> dict[str, Any]:
        params = {
            "key": config.steam_web_api_key,
            "appid": config.steam_app_id,
            "ticket": ticket,
            "identity": STEAM_IDENTITY,
        }
        try:
            async with httpx.AsyncClient(timeout=config.steam_timeout) as client:
                resp = await client.get(STEAM_AUTH_URL, params=params)
        except httpx.TimeoutException:
            raise SteamUnavailable("timeout") from None
        except httpx.HTTPError:
            # Never include str(exc): it may contain the URL with the key.
            raise SteamUnavailable(type(exc).__name__) from None
        if resp.status_code in (401, 403):
            raise SteamUnavailable(f"publisher_key_rejected_http_{resp.status_code}")
        if resp.status_code >= 500:
            raise SteamUnavailable(f"http_{resp.status_code}")
        try:
            data = resp.json()
        except ValueError:
            raise SteamUnavailable("bad_json") from None
        if not isinstance(data, dict):
            raise SteamUnavailable("bad_json")
        return data

    return verify


class Authenticator:
    """Turns a client ticket into an :class:`Identity` or raises :class:`ApiError`."""

    def __init__(self, config: Config, steam_verifier: SteamVerifier | None = None) -> None:
        self.config = config
        self._steam = steam_verifier or (make_steam_verifier(config) if config.auth_mode == "steam" else None)

    async def authenticate(self, ticket: str, display_name: str | None = None) -> Identity:
        """Verify ``ticket`` according to ``AUTH_MODE``."""
        if self.config.auth_mode == "dev":
            return self._dev(ticket)
        return await self._steam_auth(ticket, display_name)

    @staticmethod
    def _dev(ticket: str) -> Identity:
        if not ticket.startswith("dev:"):
            raise ApiError(401, "bad_ticket", "Dev auth expects a ticket of the form dev:<name>.")
        name = ticket[4:]
        if not (1 <= len(name) <= MAX_NAME_LEN) or sanitize_display_name(name, "") != name:
            raise ApiError(401, "bad_ticket", "Dev name must be 1-24 printable characters.")
        return Identity(player_uid=f"dev:{name}", display_name=name)

    async def _steam_auth(self, ticket: str, display_name: str | None) -> Identity:
        if not ticket or len(ticket) > 4096 or not re.fullmatch(r"[0-9A-Fa-f]+", ticket):
            raise ApiError(401, "bad_ticket", "Invalid Steam auth ticket.")
        assert self._steam is not None
        try:
            data = await self._steam(ticket)
        except SteamUnavailable as exc:
            log("steam_auth_unavailable", level="error", reason=str(exc))
            raise ApiError(
                503, "auth_unavailable",
                "Steam authentication is temporarily unavailable. Please try again in a minute.",
            ) from None
        response = data.get("response") if isinstance(data.get("response"), dict) else {}
        params = response.get("params") if isinstance(response.get("params"), dict) else None
        error = response.get("error") if isinstance(response.get("error"), dict) else None
        if params and params.get("result") == "OK" and str(params.get("steamid", "")).isdigit():
            if params.get("publisherbanned"):
                raise ApiError(403, "banned", "This account is banned from online play.")
            return Identity(player_uid=str(params["steamid"]), display_name=sanitize_display_name(display_name))
        code = error.get("errorcode") if error else None
        log("steam_auth_rejected", level="warning", errorcode=code)
        if code == 102:
            raise ApiError(401, "wrong_app", "Steam ticket was issued for a different app.")
        raise ApiError(401, "bad_ticket", "Steam rejected the auth ticket. Restart Steam and try again.")
