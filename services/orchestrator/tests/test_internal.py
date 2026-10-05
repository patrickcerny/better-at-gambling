"""Internal (game-server) API: loopback check, secrets, join tokens, heartbeat, closing."""

from __future__ import annotations

from .conftest import Harness


def test_verify_returns_identity_and_adds_member(h: Harness) -> None:
    room = h.create().json()
    r = h.verify(room["room_id"], room["join_token"])
    assert r.status_code == 200
    assert r.json() == {"player_uid": "dev:alice", "steam_id": "dev:alice", "display_name": "alice"}
    assert "dev:alice" in h.manager.rooms[room["room_id"]].members


def test_join_token_single_use(h: Harness) -> None:
    room = h.create().json()
    assert h.verify(room["room_id"], room["join_token"]).status_code == 200
    r = h.verify(room["room_id"], room["join_token"])
    assert r.status_code == 403 and r.json()["error"] == "bad_token"


def test_join_token_room_bound(h: Harness) -> None:
    a = h.create("alice").json()
    b = h.create("bob").json()
    r = h.verify(b["room_id"], a["join_token"])
    assert r.status_code == 403 and r.json()["error"] == "bad_token"
    # Still valid in its own room.
    assert h.verify(a["room_id"], a["join_token"]).status_code == 200


def test_join_token_expiry(make_harness) -> None:
    h: Harness = make_harness(join_token_ttl=60)
    room = h.create().json()
    h.clock.advance(61)
    r = h.verify(room["room_id"], room["join_token"])
    assert r.status_code == 403 and r.json()["error"] == "bad_token"
    tok = h.join("bob", room_id=room["room_id"]).json()["join_token"]
    h.clock.advance(59)
    assert h.verify(room["room_id"], tok).status_code == 200


def test_newer_token_replaces_older_one(h: Harness) -> None:
    room = h.create().json()
    first = h.join("bob", room_code=room["room_code"]).json()["join_token"]
    second = h.join("bob", room_code=room["room_code"]).json()["join_token"]
    assert h.verify(room["room_id"], first).status_code == 403
    assert h.verify(room["room_id"], second).status_code == 200


def test_internal_endpoints_reject_wrong_secret(h: Harness) -> None:
    room = h.create().json()
    rid = room["room_id"]
    bad = "x" * 32
    for path, extra in (
        ("/v1/internal/verify", {"join_token": room["join_token"]}),
        ("/v1/internal/heartbeat", {"phase": "lobby", "players": 0}),
        ("/v1/internal/closing", {"reason": "empty"}),
    ):
        r = h.client.post(path, json={"room_id": rid, "room_secret": bad, **extra})
        assert r.status_code == 403 and r.json()["error"] == "forbidden", path
    assert h.manager.rooms[rid].state == "starting"
    # The token was not consumed by the rejected call.
    assert h.verify(rid, room["join_token"]).status_code == 200


def test_internal_unknown_room_404(h: Harness) -> None:
    r = h.client.post("/v1/internal/heartbeat",
                      json={"room_id": "nope", "room_secret": "x", "phase": "lobby", "players": 0})
    assert r.status_code == 404 and r.json()["error"] == "room_not_found"


def test_internal_rejects_non_loopback_host(make_harness) -> None:
    h: Harness = make_harness(loopback_hosts=frozenset({"127.0.0.1", "::1"}))  # "testclient" not allowed
    room = h.create().json()
    rid = room["room_id"]
    r = h.client.post("/v1/internal/heartbeat",
                      json={"room_id": rid, "room_secret": h.secret(rid), "phase": "lobby", "players": 0})
    assert r.status_code == 403 and r.json()["error"] == "forbidden"
    r = h.verify(rid, room["join_token"])
    assert r.status_code == 403 and r.json()["error"] == "forbidden"


def test_internal_rejects_proxied_requests(h: Harness) -> None:
    """Requests relayed by Caddy (X-Forwarded-For) must never reach the internal API."""
    room = h.create().json()
    rid = room["room_id"]
    r = h.client.post("/v1/internal/heartbeat", headers={"X-Forwarded-For": "203.0.113.9"},
                      json={"room_id": rid, "room_secret": h.secret(rid), "phase": "lobby", "players": 0})
    assert r.status_code == 403 and r.json()["error"] == "forbidden"


def test_heartbeat_moves_starting_to_running_and_records_phase(h: Harness) -> None:
    room = h.create().json()
    rid = room["room_id"]
    assert h.heartbeat(rid, phase="lobby", players=1).json() == {"ok": True}
    r = h.manager.rooms[rid]
    assert r.state == "running" and r.phase == "lobby" and r.players == 1
    h.heartbeat(rid, phase="match", players=3)
    assert r.phase == "match" and r.players == 3


def test_heartbeat_rejects_bad_phase(h: Harness) -> None:
    room = h.create().json()
    r = h.heartbeat(room["room_id"], phase="party")
    assert r.status_code == 400 and r.json()["error"] == "bad_request"
