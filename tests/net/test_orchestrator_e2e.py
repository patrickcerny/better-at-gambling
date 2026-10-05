"""Orchestrator → real game-server process → two clients joining by room code (M3 acceptance).

Client A creates the party through the orchestrator, client B joins with A's room code, both
play a 1-minute match, leave, and the empty room shuts itself down, freeing its UDP port.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
import urllib.request

from conftest import GODOT, LOG_DIR, ROOT, build_id, free_port, udp_port_free


def _get(url: str) -> dict:
    with urllib.request.urlopen(url, timeout=5) as r:
        return json.loads(r.read())


def test_create_join_by_code_play_and_room_closes_when_empty(procs):
    http_port = free_port(kind=1)  # SOCK_STREAM
    udp = free_port()
    url = f"http://127.0.0.1:{http_port}"
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ)
    env.update({
        "BUILD_ID": build_id(),
        "BIND_PORT": str(http_port),
        "PORT_RANGE": f"{udp}-{udp}",
        "GAME_SERVER_CMD": f"{GODOT} --headless --path {ROOT} --audio-driver Dummy -- --duration 1 --empty-timeout 3",
        "GAME_SERVER_CWD": str(ROOT),
        "LOG_DIR": str(LOG_DIR / "rooms"),
        "REAP_INTERVAL": "1",
        "STARTUP_TIMEOUT": "60",
    })
    orch_log = open(LOG_DIR / "orchestrator.log", "w")
    orch = subprocess.Popen([sys.executable, "-m", "orchestrator"], cwd=ROOT / "services/orchestrator",
                            env=env, stdout=orch_log, stderr=subprocess.STDOUT)
    try:
        deadline = time.monotonic() + 20
        while True:
            try:
                assert _get(f"{url}/healthz")["ok"]
                break
            except OSError:
                assert time.monotonic() < deadline, "orchestrator did not start"
                time.sleep(0.2)
        common = ["--orchestrator", url, "--autoplay", "--quit-after-results"]
        ann = procs("orch-ann", ["--create-room", "--name", "Ann", *common])
        code = ann.wait_for(r"room ([A-Z0-9]{5}) at 127\.0\.0\.1:(\d+)", 60)
        assert int(code.group(2)) == udp
        assert _get(f"{url}/v1/status")["rooms"] == 1
        ben = procs("orch-ben", ["--join-code", code.group(1).lower(), "--name", "Ben", "--autoplay-variant", "1", *common])
        assert ann.wait(200) == 0, ann.log_path
        assert ben.wait(60) == 0, ben.log_path
        assert ann.digest() == ben.digest()
        for p in (ann, ben):
            assert p.errors() == [], (p.name, p.errors()[:5])
        # Both left: the room closes itself, the orchestrator forgets it and the port is free.
        deadline = time.monotonic() + 40
        while _get(f"{url}/v1/status")["rooms"] != 0:
            assert time.monotonic() < deadline, "room was not closed after everyone left"
            time.sleep(0.5)
        deadline = time.monotonic() + 10
        while not udp_port_free(udp):
            assert time.monotonic() < deadline, f"UDP port {udp} still bound"
            time.sleep(0.5)
    finally:
        orch.terminate()
        try:
            orch.wait(timeout=10)
        except subprocess.TimeoutExpired:
            orch.kill()
        orch_log.close()
