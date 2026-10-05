"""Rate limits (per IP and per identity), config parsing, room codes."""

from __future__ import annotations

import shlex

from orchestrator.codes import CODE_ALPHABET, new_room_code
from orchestrator.config import Config
from orchestrator.ratelimit import RateLimiter

from .conftest import BUILD, Harness


def test_rate_limit_per_ip(make_harness) -> None:
    h: Harness = make_harness(rate_limit_per_min=3)
    for i in range(3):
        assert h.join(f"user{i}", room_code="AAAAA").status_code == 404
    r = h.join("user9", room_code="AAAAA")
    assert r.status_code == 429 and r.json()["error"] == "rate_limited"
    # A different client IP (via the trusted proxy's X-Forwarded-For) is unaffected.
    r = h.client.post("/v1/rooms/join", headers={"X-Forwarded-For": "198.51.100.7"},
                      json={"ticket": "dev:other", "build": BUILD, "room_code": "AAAAA"})
    assert r.status_code == 404
    # After a minute the window resets.
    h.clock.advance(61)
    assert h.join("user9", room_code="AAAAA").status_code == 404


def test_rate_limit_per_identity(make_harness) -> None:
    h: Harness = make_harness(rate_limit_per_min=3)
    for i in range(3):
        r = h.client.post("/v1/rooms/join", headers={"X-Forwarded-For": f"198.51.100.{i}"},
                          json={"ticket": "dev:mallory", "build": BUILD, "room_code": "AAAAA"})
        assert r.status_code == 404
    r = h.client.post("/v1/rooms/join", headers={"X-Forwarded-For": "198.51.100.200"},
                      json={"ticket": "dev:mallory", "build": BUILD, "room_code": "AAAAA"})
    assert r.status_code == 429 and r.json()["error"] == "rate_limited"


def test_untrusted_peer_cannot_spoof_forwarded_ip(make_harness) -> None:
    h: Harness = make_harness(rate_limit_per_min=2, trusted_proxies=frozenset())
    for i in range(2):
        h.client.post("/v1/rooms/join", headers={"X-Forwarded-For": f"10.0.0.{i}"},
                      json={"ticket": f"dev:u{i}", "build": BUILD, "room_code": "AAAAA"})
    r = h.client.post("/v1/rooms/join", headers={"X-Forwarded-For": "10.0.0.99"},
                      json={"ticket": "dev:u9", "build": BUILD, "room_code": "AAAAA"})
    assert r.status_code == 429


def test_rate_limiter_window() -> None:
    t = [0.0]
    rl = RateLimiter(2, 60.0, clock=lambda: t[0])
    assert rl.hit("k") and rl.hit("k") and not rl.hit("k")
    assert rl.hit("other")
    t[0] = 60.5
    assert rl.hit("k")


def test_room_codes_alphabet_and_uniqueness() -> None:
    assert not set("ILO01") & set(CODE_ALPHABET)
    taken: set[str] = set()
    for _ in range(2000):
        code = new_room_code(taken)
        assert len(code) == 5 and set(code) <= set(CODE_ALPHABET)
        assert code not in taken
        taken.add(code)


def test_config_from_env() -> None:
    cfg = Config.from_env({
        "ENV": "production", "AUTH_MODE": "steam", "BUILD_ID": "1.2.3", "PUBLIC_HOST": "play.example.com",
        "PORT_RANGE": "25000-25009", "MAX_ROOMS": "5", "MAX_PLAYERS": "6",
        "GAME_SERVER_CMD": "tools/godot/godot --headless --path . --", "GAME_SERVER_CWD": "/srv/game",
        "HEARTBEAT_TIMEOUT": "15", "STARTUP_TIMEOUT": "10", "REAP_INTERVAL": "1", "RATE_LIMIT_PER_MIN": "12",
        "STEAM_WEB_API_KEY": "secret", "STEAM_APP_ID": "480", "LOG_DIR": "/var/log/bag",
    })
    cfg.validate()
    assert (cfg.port_min, cfg.port_max) == (25000, 25009)
    assert cfg.game_server_cmd == tuple(shlex.split("tools/godot/godot --headless --path . --"))
    assert cfg.max_rooms == 5 and cfg.max_players == 6 and cfg.heartbeat_timeout == 15
    assert "secret" not in repr(cfg)
    assert cfg.orchestrator_url == "http://127.0.0.1:8080"


def test_config_defaults() -> None:
    cfg = Config.from_env({})
    cfg.validate()
    assert cfg.env == "dev" and cfg.auth_mode == "dev" and cfg.build_id == "dev"
    assert cfg.game_server_cmd == ("/opt/bag/BetterAtGamblingServer.x86_64", "--headless", "--")
    assert (cfg.port_min, cfg.port_max, cfg.max_rooms, cfg.max_players) == (24700, 24799, 20, 8)
    assert (cfg.heartbeat_timeout, cfg.startup_timeout, cfg.reap_interval) == (30, 20, 2)
    assert cfg.rate_limit_per_min == 30 and cfg.log_dir == "/tmp/bag-rooms"
