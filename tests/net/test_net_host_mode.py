"""Host mode over real ENet sockets (a party on the host's PC, docs/DECISIONS.md "Host mode over
Steam"): the room server runs as `--server --host-mode` (what `SteamParty` starts next to the
host's game), listens on loopback only, admits without an orchestrator by the hello's uid (the
Steam ID the host's bridge stamps), refuses other builds, plays a whole match with the host and a
friend in agreement, and closes once the host's game is gone. The Steam leg itself (relay,
lobby, overlay) needs a Steam client and is covered in-process with a fake Steam
(tests/integration/test_host_mode.gd, tests/unit/test_steam_transport.gd)."""

from __future__ import annotations

import re
import time
from pathlib import Path

from conftest import LOG_DIR, free_port

HOST_UID = "steam:76561190000000101"
FRIEND_UID = "steam:76561190000000102"


def _host_server(procs, name, port, *extra):
    ready = LOG_DIR / f"{name}.ready"
    ready.parent.mkdir(parents=True, exist_ok=True)
    if ready.exists():
        ready.unlink()
    server = procs(name, ["--server", "--host-mode", "--port", str(port), "--host-uid", HOST_UID,
                          "--ready-file", str(ready), "--empty-timeout", "120", *extra])
    deadline = time.monotonic() + 30
    while not ready.exists() and time.monotonic() < deadline:
        time.sleep(0.1)
    assert ready.exists(), f"no ready file (log: {server.log_path})"
    assert ready.read_text().strip() == str(port)
    return server


def _client(procs, name, port, uid, *extra):
    return procs(name, ["--connect", f"127.0.0.1:{port}", "--name", name, "--uid", uid, "--autoplay", "--quit-after-results", *extra])


def _bound_to_loopback_only(port: int) -> bool:
    """Linux: the UDP socket on `port` is bound to 127.0.0.1, not 0.0.0.0."""
    local = []
    for table in ("/proc/net/udp", "/proc/net/udp6"):
        path = Path(table)
        if not path.exists():
            continue
        for line in path.read_text().splitlines()[1:]:
            addr, hexport = line.split()[1].split(":")
            if int(hexport, 16) == port:
                local.append(addr)
    return local == ["0100007F"], local


def test_host_and_friend_play_a_hosted_match_in_agreement(procs):
    port = free_port()
    server = _host_server(procs, "host-server", port, "--minigames", "0", "--gamble-seconds", "45", "--seed", "31")
    server.wait_for(r"host mode: a party on a player's PC", 30)
    ok, local = _bound_to_loopback_only(port)
    assert ok, f"the hosted room must not listen on the network: {local}"
    host = _client(procs, "host-patrick", port, HOST_UID)
    friend = _client(procs, "host-friend", port, FRIEND_UID, "--autoplay-variant", "1")
    assert host.wait(60 + 180) == 0, host.log_path
    assert friend.wait(60) == 0, friend.log_path
    assert server.wait(60) == 0, server.log_path
    log = server.log()
    assert re.search(r"host-patrick joined as player \d", log) and re.search(r"host-friend joined as player \d", log)
    digests = {p.name: p.digest() for p in (server, host, friend)}
    assert len(set(digests.values())) == 1, digests
    for p in (server, host, friend):
        assert p.errors() == [], (p.name, p.errors()[:5])


def test_hosted_room_refuses_another_build(procs):
    port = free_port()
    server = _host_server(procs, "host-version-server", port)
    old = procs("host-old-client", ["--connect", f"127.0.0.1:{port}", "--name", "old", "--uid", FRIEND_UID, "--build", "0.0.0-old", "--quit-on-disconnect"])
    assert old.wait(60) == 4, old.log_path
    assert "version_mismatch" in old.log()
    server.wait_for(r"rejected: version", 10)
    server.kill()


def test_hosted_room_closes_when_the_host_is_gone(procs):
    port = free_port()
    server = _host_server(procs, "host-gone-server", port, "--minigames", "0", "--gamble-seconds", "600")
    host = procs("host-gone-host", ["--connect", f"127.0.0.1:{port}", "--name", "patrick", "--uid", HOST_UID, "--autoplay"])
    friend = procs("host-gone-friend", ["--connect", f"127.0.0.1:{port}", "--name", "friend", "--uid", FRIEND_UID, "--autoplay"])
    server.wait_for(r"friend joined as player \d", 60)
    server.wait_for(r"patrick joined as player \d", 60)
    friend.wait_for(r"match scene ready", 60)
    host.wait_for(r"match scene ready", 60)
    host.kill()  # the host's game crashed (or was closed)
    server.wait_for(r"closing room .*: the host left", 60)
    assert server.wait(30) == 0, server.log_path
    assert friend.wait(60) == 4, "the friend is told and leaves"
    assert server.errors() == [], server.errors()[:5]
