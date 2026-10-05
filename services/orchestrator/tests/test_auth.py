"""Authentication: dev tickets, production guard, Steam verifier mapping."""

from __future__ import annotations

from typing import Any

import pytest

from orchestrator.app import create_app
from orchestrator.auth import SteamUnavailable, sanitize_display_name
from orchestrator.config import Config, ConfigError

from .conftest import BUILD, Harness, make_config

STEAM_ID = "76561197960287930"
TICKET = "14000000ABCDEF0123456789"


def steam_ok(steamid: str = STEAM_ID, **extra: Any) -> dict[str, Any]:
    return {"response": {"params": {"result": "OK", "steamid": steamid, "ownersteamid": steamid,
                                    "vacbanned": False, "publisherbanned": False, **extra}}}


def steam_error(code: int, desc: str) -> dict[str, Any]:
    return {"response": {"error": {"errorcode": code, "errordesc": desc}}}


def steam_harness(make_harness, result: Any) -> tuple[Harness, list[str]]:
    seen: list[str] = []

    async def verifier(ticket: str) -> dict[str, Any]:
        seen.append(ticket)
        if isinstance(result, Exception):
            raise result
        return result

    h = make_harness(auth_mode="steam", steam_web_api_key="SECRETKEY", steam_app_id="480",
                     steam_verifier=verifier)
    return h, seen


def post_steam(h: Harness, **extra: Any):
    return h.client.post("/v1/rooms", json={"ticket": TICKET, "build": BUILD, **extra})


@pytest.mark.parametrize("ticket", ["alice", "dev:", "dev:" + "x" * 25, "dev:bad\nname"])
def test_dev_rejects_malformed_tickets(h: Harness, ticket: str) -> None:
    r = h.client.post("/v1/rooms", json={"ticket": ticket, "build": BUILD})
    assert r.status_code == 401 and r.json()["error"] == "bad_ticket"


def test_dev_ticket_identity(h: Harness) -> None:
    room = h.create("Zoë 99").json()
    assert h.verify(room["room_id"], room["join_token"]).json()["display_name"] == "Zoë 99"


def test_dev_auth_refused_in_production() -> None:
    with pytest.raises(ConfigError):
        create_app(make_config(env="production", auth_mode="dev"))
    with pytest.raises(ConfigError):
        Config.from_env({"ENV": "production"}).validate()


def test_steam_mode_requires_key_and_app_id() -> None:
    with pytest.raises(ConfigError):
        create_app(make_config(auth_mode="steam"))


def test_production_steam_mode_starts() -> None:
    app = create_app(make_config(env="production", auth_mode="steam", steam_web_api_key="k", steam_app_id="1"))
    assert app.state.config.env == "production"


def test_steam_valid_ticket(make_harness) -> None:
    h, seen = steam_harness(make_harness, steam_ok())
    r = post_steam(h, display_name="  The\tHigh\x00 Roller  ")
    assert r.status_code == 200, r.text
    assert seen == [TICKET]
    ident = h.verify(r.json()["room_id"], r.json()["join_token"]).json()
    assert ident == {"player_uid": STEAM_ID, "steam_id": STEAM_ID, "display_name": "The High Roller"}
    logs = h.logs.getvalue()
    assert TICKET not in logs and "SECRETKEY" not in logs


def test_steam_display_name_fallback(make_harness) -> None:
    h, _ = steam_harness(make_harness, steam_ok())
    r = post_steam(h)
    assert h.verify(r.json()["room_id"], r.json()["join_token"]).json()["display_name"] == "Player"


def test_steam_invalid_ticket(make_harness) -> None:
    h, _ = steam_harness(make_harness, steam_error(101, "Invalid ticket"))
    r = post_steam(h)
    assert r.status_code == 401 and r.json()["error"] == "bad_ticket"


def test_steam_non_hex_ticket_rejected_without_calling_steam(make_harness) -> None:
    h, seen = steam_harness(make_harness, steam_ok())
    r = h.client.post("/v1/rooms", json={"ticket": "dev:alice", "build": BUILD})
    assert r.status_code == 401 and seen == []


def test_steam_wrong_app(make_harness) -> None:
    h, _ = steam_harness(make_harness, steam_error(102, "Ticket for other app"))
    r = post_steam(h)
    assert r.status_code == 401 and r.json()["error"] == "wrong_app"


def test_steam_publisher_error(make_harness) -> None:
    h, _ = steam_harness(make_harness, steam_error(3, "Invalid parameter"))
    r = post_steam(h)
    assert r.status_code == 401 and r.json()["error"] == "bad_ticket"


def test_steam_publisher_banned(make_harness) -> None:
    h, _ = steam_harness(make_harness, steam_ok(publisherbanned=True))
    r = post_steam(h)
    assert r.status_code == 403 and r.json()["error"] == "banned"


def test_steam_timeout_is_503(make_harness) -> None:
    h, _ = steam_harness(make_harness, SteamUnavailable("timeout"))
    r = post_steam(h)
    assert r.status_code == 503
    assert r.json()["error"] == "auth_unavailable"
    assert "Steam authentication is temporarily unavailable" in r.json()["message"]


def test_real_verifier_maps_timeout(monkeypatch) -> None:
    """The real httpx verifier turns a timeout into SteamUnavailable without leaking the key."""
    import asyncio

    import httpx

    from orchestrator.auth import make_steam_verifier

    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.params["identity"] == "better-at-gambling"
        raise httpx.ConnectTimeout("timed out", request=request)

    real_client = httpx.AsyncClient
    monkeypatch.setattr(httpx, "AsyncClient",
                        lambda **kw: real_client(transport=httpx.MockTransport(handler), **kw))
    verify = make_steam_verifier(make_config(auth_mode="steam", steam_web_api_key="K", steam_app_id="480"))
    with pytest.raises(SteamUnavailable) as info:
        asyncio.run(verify("ABCD"))
    assert str(info.value) == "timeout"


def test_real_verifier_parses_ok(monkeypatch) -> None:
    import asyncio

    import httpx

    from orchestrator.auth import make_steam_verifier

    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.params["appid"] == "480" and request.url.params["ticket"] == "ABCD"
        return httpx.Response(200, json=steam_ok())

    real_client = httpx.AsyncClient
    monkeypatch.setattr(httpx, "AsyncClient",
                        lambda **kw: real_client(transport=httpx.MockTransport(handler), **kw))
    verify = make_steam_verifier(make_config(auth_mode="steam", steam_web_api_key="K", steam_app_id="480"))
    assert asyncio.run(verify("ABCD"))["response"]["params"]["steamid"] == STEAM_ID


def test_sanitize_display_name() -> None:
    assert sanitize_display_name(None) == "Player"
    assert sanitize_display_name("‮\x07") == "Player"
    assert sanitize_display_name("a" * 40) == "a" * 24
