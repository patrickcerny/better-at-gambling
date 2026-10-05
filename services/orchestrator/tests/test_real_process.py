"""End-to-end: real uvicorn server + real subprocess speaking the internal API."""

from __future__ import annotations

import socket
import sys
import threading
import time
from pathlib import Path

import httpx
import uvicorn

from orchestrator.app import create_app
from orchestrator.config import Config

FAKE_SERVER = Path(__file__).with_name("fake_game_server.py")


def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def free_udp_range(n: int = 3) -> tuple[int, int]:
    base = 40000 + (free_port() % 20000)
    return base, base + n - 1


def test_real_game_server_lifecycle(tmp_path: Path) -> None:
    port = free_port()
    lo, hi = free_udp_range()
    cfg = Config(
        build_id="e2e", bind_host="127.0.0.1", bind_port=port, port_min=lo, port_max=hi,
        game_server_cmd=(sys.executable, str(FAKE_SERVER)), reap_interval=0.05,
        heartbeat_timeout=10, startup_timeout=10, kill_grace=1, log_dir=str(tmp_path),
    )
    app = create_app(cfg)
    manager = app.state.manager
    server = uvicorn.Server(uvicorn.Config(app, host="127.0.0.1", port=port, log_level="warning",
                                           access_log=False, proxy_headers=False))
    thread = threading.Thread(target=server.run, daemon=True)
    thread.start()
    try:
        deadline = time.monotonic() + 10
        while not server.started:
            assert time.monotonic() < deadline, "uvicorn did not start"
            time.sleep(0.02)
        base = f"http://127.0.0.1:{port}"
        r = httpx.post(f"{base}/v1/rooms", json={"ticket": "dev:alice", "build": "e2e"})
        assert r.status_code == 200, r.text
        room = r.json()
        rid = room["room_id"]
        assert room["port"] == lo

        seen: list[str] = []
        deadline = time.monotonic() + 15
        while rid in manager.rooms:
            state = manager.rooms.get(rid)
            if state is not None and (not seen or seen[-1] != state.state):
                seen.append(state.state)
            assert time.monotonic() < deadline, f"room never reaped; states={seen}"
            time.sleep(0.01)

        assert "running" in seen and "closing" in seen, seen
        assert seen.index("running") < seen.index("closing")
        assert lo not in manager.used_ports()
        assert httpx.get(f"{base}/v1/status").json()["rooms"] == 0
        log_text = (tmp_path / f"room-{rid}.log").read_text()
        assert f"code={room['room_code']}" in log_text and f"port={lo}" in log_text
    finally:
        server.should_exit = True
        thread.join(timeout=10)
