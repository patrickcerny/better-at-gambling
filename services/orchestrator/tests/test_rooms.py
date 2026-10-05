"""Public room API: create, join, full, closed, in-progress, reconnect, caps, ports."""

from __future__ import annotations

from orchestrator.codes import CODE_ALPHABET

from .conftest import BUILD, Harness


def test_healthz_and_status(h: Harness) -> None:
    assert h.client.get("/healthz").json() == {"ok": True}
    h.create()
    assert h.client.get("/v1/status").json() == {"build": BUILD, "rooms": 1, "max_rooms": 20, "auth_mode": "dev"}


def test_create_room_spawns_process_with_contract_args(h: Harness) -> None:
    r = h.create()
    assert r.status_code == 200, r.text
    body = r.json()
    assert set(body) == {"room_id", "room_code", "host", "port", "join_token"}
    assert "room_secret" not in r.text
    assert body["host"] == "127.0.0.1" and body["port"] == 24700
    assert len(body["room_code"]) == 5 and all(c in CODE_ALPHABET for c in body["room_code"])
    room = h.manager.rooms[body["room_id"]]
    assert room.state == "starting"
    assert h.spawner.processes[0].argv == [
        "godot", "--headless", "--", "--server", "--port", "24700", "--room-id", body["room_id"],
        "--room-code", body["room_code"], "--room-secret", room.secret,
        "--orchestrator", "http://127.0.0.1:8080", "--build", BUILD,
    ]
    assert room.secret not in h.logs.getvalue()


def test_join_by_code_case_insensitive_and_by_id(h: Harness) -> None:
    room = h.create().json()
    r = h.join("bob", room_code=room["room_code"].lower())
    assert r.status_code == 200, r.text
    assert r.json()["room_id"] == room["room_id"] and r.json()["port"] == room["port"]
    assert r.json()["join_token"] != room["join_token"]
    r2 = h.join("carol", room_id=room["room_id"])
    assert r2.status_code == 200


def test_join_starting_room_allowed(h: Harness) -> None:
    room = h.create().json()
    assert h.manager.rooms[room["room_id"]].state == "starting"
    assert h.join("bob", room_code=room["room_code"]).status_code == 200


def test_join_unknown_room_404_and_missing_target_400(h: Harness) -> None:
    r = h.join("bob", room_code="ZZZZZ")
    assert r.status_code == 404 and r.json()["error"] == "room_not_found"
    r = h.join("bob")
    assert r.status_code == 400 and r.json()["error"] == "bad_request"


def test_room_full_counts_heartbeat_players_and_pending_tokens(make_harness) -> None:
    h: Harness = make_harness(max_players=3)
    room = h.create().json()  # owner token pending -> 1
    h.heartbeat(room["room_id"], players=1, player_uids=["dev:alice"])  # alice connected; token not double counted
    assert h.join("bob", room_code=room["room_code"]).status_code == 200  # 2
    assert h.join("carol", room_code=room["room_code"]).status_code == 200  # 3
    r = h.join("dave", room_code=room["room_code"])
    assert r.status_code == 409 and r.json()["error"] == "room_full"
    # A player asking again replaces their own token instead of taking a new slot.
    assert h.join("bob", room_code=room["room_code"]).status_code == 200
    # Pending tokens expire -> slots free up.
    h.clock.advance(61)
    assert h.join("dave", room_code=room["room_code"]).status_code == 200


def test_room_in_progress_rejects_new_but_admits_reconnecting_member(h: Harness) -> None:
    room = h.create().json()
    rid = room["room_id"]
    bob = h.join("bob", room_code=room["room_code"]).json()
    assert h.verify(rid, bob["join_token"]).status_code == 200  # bob becomes a member
    h.heartbeat(rid, phase="match", players=2)
    r = h.join("carol", room_code=room["room_code"])
    assert r.status_code == 409 and r.json()["error"] == "room_in_progress"
    r = h.join("bob", room_code=room["room_code"])
    assert r.status_code == 200, r.text
    # Members from heartbeat player_uids also count as reconnecting members.
    h.heartbeat(rid, phase="results", players=2, player_uids=["dev:alice", "dev:zed"])
    assert h.join("zed", room_id=rid).status_code == 200


def test_reconnecting_member_admitted_even_when_full(make_harness) -> None:
    h: Harness = make_harness(max_players=1)
    room = h.create().json()
    h.verify(room["room_id"], room["join_token"])
    h.heartbeat(room["room_id"], phase="match", players=1, player_uids=["dev:alice"])
    assert h.join("alice", room_code=room["room_code"]).status_code == 200
    assert h.join("bob", room_code=room["room_code"]).json()["error"] == "room_in_progress"


def test_closing_room_not_joinable_even_for_members(h: Harness) -> None:
    room = h.create().json()
    rid = room["room_id"]
    h.verify(rid, room["join_token"])
    h.heartbeat(rid)
    r = h.client.post("/v1/internal/closing", json={"room_id": rid, "room_secret": h.secret(rid), "reason": "empty"})
    assert r.json() == {"ok": True}
    assert h.manager.rooms[rid].state == "closing"
    for name in ("bob", "alice"):
        r = h.join(name, room_code=room["room_code"])
        assert r.status_code == 404 and r.json()["error"] == "room_not_found"
    # Still counted (process alive) until it exits, then reaped.
    h.manager.reap_once()
    assert rid in h.manager.rooms
    h.process(rid).exit(0)
    h.manager.reap_once()
    assert rid not in h.manager.rooms
    assert room["port"] not in h.manager.used_ports()


def test_one_room_per_owner(h: Harness) -> None:
    first = h.create().json()
    r = h.create()
    assert r.status_code == 409
    assert r.json()["error"] == "already_owns_room"
    assert r.json()["room_code"] == first["room_code"] and r.json()["room_id"] == first["room_id"]
    assert h.create("bob").status_code == 200
    # Once the first room is closing, the owner may create a new one.
    rid = first["room_id"]
    h.client.post("/v1/internal/closing", json={"room_id": rid, "room_secret": h.secret(rid), "reason": "empty"})
    assert h.create().status_code == 200


def test_global_room_cap(make_harness) -> None:
    h: Harness = make_harness(max_rooms=2)
    assert h.create("a").status_code == 200
    assert h.create("b").status_code == 200
    r = h.create("c")
    assert r.status_code == 503 and r.json()["error"] == "capacity"


def test_port_allocation_fill_free_reuse(make_harness) -> None:
    h: Harness = make_harness(port_min=24700, port_max=24702, max_rooms=10)
    rooms = [h.create(f"p{i}").json() for i in range(3)]
    assert sorted(r["port"] for r in rooms) == [24700, 24701, 24702]
    r = h.create("p3")
    assert r.status_code == 503 and r.json()["error"] == "no_ports"
    h.process(rooms[1]["room_id"]).exit(0)
    h.manager.reap_once()
    r = h.create("p3")
    assert r.status_code == 200 and r.json()["port"] == 24701


def test_room_codes_unique(h: Harness) -> None:
    codes = {h.create(f"u{i}").json()["room_code"] for i in range(20)}
    assert len(codes) == 20


def test_version_mismatch_426(h: Harness) -> None:
    r = h.client.post("/v1/rooms", json={"ticket": "dev:alice", "build": "old-build"})
    assert r.status_code == 426
    assert r.json()["error"] == "version_mismatch"
    assert "Update required" in r.json()["message"]
    r = h.client.post("/v1/rooms/join", json={"ticket": "dev:alice", "build": "old", "room_code": "AAAAA"})
    assert r.status_code == 426


def test_spawn_failure_500_frees_port(make_harness) -> None:
    from orchestrator.spawner import FakeSpawner

    h: Harness = make_harness(spawner=FakeSpawner(fail=True))
    r = h.create()
    assert r.status_code == 500 and r.json()["error"] == "spawn_failed"
    assert h.manager.rooms == {}


def test_bad_body_is_400_json(h: Harness) -> None:
    r = h.client.post("/v1/rooms", json={"build": BUILD})
    assert r.status_code == 400 and r.json()["error"] == "bad_request"
