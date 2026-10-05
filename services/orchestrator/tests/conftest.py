"""Shared fixtures: FakeSpawner + fake clock + TestClient (no lifespan, no background reaper)."""

from __future__ import annotations

import dataclasses
import io
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable

import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from orchestrator import logjson  # noqa: E402
from orchestrator.app import create_app  # noqa: E402
from orchestrator.config import Config  # noqa: E402
from orchestrator.rooms import RoomManager  # noqa: E402
from orchestrator.spawner import FakeSpawner  # noqa: E402

BUILD = "test-build-1"


class FakeClock:
    """Manually advanced monotonic clock."""

    def __init__(self, start: float = 1000.0) -> None:
        self.now = start

    def __call__(self) -> float:
        return self.now

    def advance(self, seconds: float) -> None:
        self.now += seconds


@dataclass
class Harness:
    client: TestClient
    manager: RoomManager
    spawner: FakeSpawner
    clock: FakeClock
    config: Config
    logs: io.StringIO

    def create(self, name: str = "alice", **extra: Any):
        return self.client.post("/v1/rooms", json={"ticket": f"dev:{name}", "build": BUILD, **extra})

    def join(self, name: str, **extra: Any):
        return self.client.post("/v1/rooms/join", json={"ticket": f"dev:{name}", "build": BUILD, **extra})

    def secret(self, room_id: str) -> str:
        return self.manager.rooms[room_id].secret

    def heartbeat(self, room_id: str, phase: str = "lobby", players: int = 0, **extra: Any):
        return self.client.post("/v1/internal/heartbeat", json={
            "room_id": room_id, "room_secret": self.secret(room_id), "phase": phase, "players": players, **extra})

    def verify(self, room_id: str, token: str, secret: str | None = None):
        return self.client.post("/v1/internal/verify", json={
            "room_id": room_id, "room_secret": secret or self.secret(room_id), "join_token": token})

    def process(self, room_id: str):
        return self.manager.rooms[room_id].process


def make_config(**overrides: Any) -> Config:
    base = Config(
        build_id=BUILD, rate_limit_per_min=1000, reap_interval=0, log_dir="/tmp/bag-rooms-test",
        loopback_hosts=frozenset({"testclient", "127.0.0.1", "::1"}),
        trusted_proxies=frozenset({"testclient"}),
        game_server_cmd=("godot", "--headless", "--"),
    )
    return dataclasses.replace(base, **overrides)


@pytest.fixture
def make_harness() -> Callable[..., Harness]:
    """Factory: ``make_harness(max_rooms=2, steam_verifier=..., spawner=...)``."""
    created: list[io.StringIO] = []

    def factory(*, steam_verifier: Any = None, spawner: FakeSpawner | None = None, **overrides: Any) -> Harness:
        logs = io.StringIO()
        created.append(logs)
        logjson.set_stream(logs)
        cfg = make_config(**overrides)
        clock = FakeClock()
        sp = spawner or FakeSpawner()
        app = create_app(cfg, spawner=sp, clock=clock, steam_verifier=steam_verifier)
        return Harness(TestClient(app), app.state.manager, sp, clock, cfg, logs)

    yield factory
    logjson.set_stream(None)


@pytest.fixture
def h(make_harness: Callable[..., Harness]) -> Harness:
    return make_harness()
