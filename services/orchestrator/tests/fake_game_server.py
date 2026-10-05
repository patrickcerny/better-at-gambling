"""Stand-in for the headless Godot game server, used by test_real_process.py.

Parses exactly the args the orchestrator appends, then follows the contract:
heartbeat (lobby) a few times, announce ``closing``, keep heartbeating briefly, exit 0.
Uses only the standard library.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.request


def post(base: str, path: str, body: dict) -> dict:
    req = urllib.request.Request(base + path, data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(req, timeout=5) as resp:
        return json.loads(resp.read())


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--server", action="store_true", required=True)
    p.add_argument("--port", type=int, required=True)
    p.add_argument("--room-id", required=True)
    p.add_argument("--room-code", required=True)
    p.add_argument("--room-secret", required=True)
    p.add_argument("--orchestrator", required=True)
    p.add_argument("--build", required=True)
    p.add_argument("--interval", type=float, default=0.15)
    a = p.parse_args()
    auth = {"room_id": a.room_id, "room_secret": a.room_secret}
    print(f"fake server room={a.room_id} code={a.room_code} port={a.port} build={a.build}", flush=True)
    for _ in range(4):
        assert post(a.orchestrator, "/v1/internal/heartbeat",
                    {**auth, "phase": "lobby", "players": 0, "player_uids": []}) == {"ok": True}
        time.sleep(a.interval)
    assert post(a.orchestrator, "/v1/internal/closing", {**auth, "reason": "empty_timeout"}) == {"ok": True}
    for _ in range(3):
        post(a.orchestrator, "/v1/internal/heartbeat", {**auth, "phase": "lobby", "players": 0})
        time.sleep(a.interval)
    return 0


if __name__ == "__main__":
    sys.exit(main())
