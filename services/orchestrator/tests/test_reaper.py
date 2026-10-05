"""Reaper: heartbeat/startup timeouts, exit detection, kill escalation, shutdown."""

from __future__ import annotations

import json

from orchestrator.spawner import FakeSpawner

from .conftest import Harness


def events(h: Harness) -> list[dict]:
    return [json.loads(line) for line in h.logs.getvalue().splitlines()]


def test_heartbeat_timeout_kills_and_reaps(make_harness) -> None:
    h: Harness = make_harness(heartbeat_timeout=30)
    room = h.create().json()
    rid = room["room_id"]
    h.heartbeat(rid)
    h.clock.advance(29)
    h.manager.reap_once()
    assert h.manager.rooms[rid].state == "running"
    h.heartbeat(rid)
    h.clock.advance(31)
    proc = h.process(rid)
    h.manager.reap_once()
    assert proc.terminated
    assert rid not in h.manager.rooms
    assert room["port"] not in h.manager.used_ports()
    assert any(e["event"] == "room_killed" and e["reason"] == "heartbeat_timeout" for e in events(h))


def test_startup_timeout_kills(make_harness) -> None:
    h: Harness = make_harness(startup_timeout=20)
    room = h.create().json()
    rid = room["room_id"]
    h.clock.advance(19)
    h.manager.reap_once()
    assert h.manager.rooms[rid].state == "starting"
    h.clock.advance(2)
    proc = h.process(rid)
    h.manager.reap_once()
    assert proc.terminated and rid not in h.manager.rooms
    assert any(e["event"] == "room_killed" and e["reason"] == "startup_timeout" for e in events(h))


def test_stubborn_process_gets_sigkill_after_grace(make_harness) -> None:
    h: Harness = make_harness(spawner=FakeSpawner(stubborn=True), startup_timeout=20, kill_grace=5)
    room = h.create().json()
    rid = room["room_id"]
    proc = h.process(rid)
    h.clock.advance(21)
    h.manager.reap_once()
    assert proc.terminated and not proc.killed
    assert h.manager.rooms[rid].state == "dead"
    assert h.join("bob", room_code=room["room_code"]).status_code == 404
    h.clock.advance(5)
    h.manager.reap_once()
    assert proc.killed and rid not in h.manager.rooms


def test_process_exit_frees_port_and_code_and_logs_crash(h: Harness) -> None:
    room = h.create().json()
    rid = room["room_id"]
    h.heartbeat(rid)
    h.process(rid).exit(139)
    h.manager.reap_once()
    assert rid not in h.manager.rooms
    assert room["port"] not in h.manager.used_ports()
    assert h.manager.by_code(room["room_code"]) is None
    crash = [e for e in events(h) if e["event"] == "room_crashed"]
    assert crash and crash[0]["room_id"] == rid and crash[0]["exit_code"] == 139
    assert h.join("bob", room_code=room["room_code"]).status_code == 404


def test_clean_exit_is_not_a_crash(h: Harness) -> None:
    room = h.create().json()
    h.process(room["room_id"]).exit(0)
    h.manager.reap_once()
    assert not [e for e in events(h) if e["event"] == "room_crashed"]


def test_reaper_drops_expired_tokens(h: Harness) -> None:
    h.create()
    assert len(h.manager.tokens) == 1
    h.clock.advance(61)
    h.manager.reap_once()
    assert h.manager.tokens == {}


def test_shutdown_kills_all_children(make_harness) -> None:
    h: Harness = make_harness(spawner=FakeSpawner(stubborn=True))
    for name in ("a", "b", "c"):
        h.create(name)
    procs = list(h.spawner.processes)
    h.manager.shutdown(wait=0.05)
    assert all(p.terminated and p.killed for p in procs)
    assert h.manager.rooms == {}


def test_lifespan_shutdown_kills_children(make_harness) -> None:
    from fastapi.testclient import TestClient

    h: Harness = make_harness()
    with TestClient(h.client.app) as c:
        c.post("/v1/rooms", json={"ticket": "dev:alice", "build": h.config.build_id})
    assert h.spawner.processes[0].terminated
    assert h.manager.rooms == {}
