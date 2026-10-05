"""Server + scripted clients over real ENet sockets (M3 acceptance)."""

from __future__ import annotations

import os

from conftest import free_port

# Match length in minutes for the long sync test (M4 spec: a 5-minute match with two quizzes).
SYNC_MINUTES = int(os.environ.get("NET_SYNC_MINUTES", "5"))


def _server(procs, name, port, *extra):
    return procs(name, ["--server", "--port", str(port), "--empty-timeout", "4", *extra])


def _client(procs, name, port, *extra):
    return procs(name, ["--connect", f"127.0.0.1:{port}", "--name", name, "--autoplay", "--quit-after-results", *extra])


def test_two_clients_play_a_match_and_agree_on_every_balance(procs):
    port = free_port()
    server = _server(procs, "sync-server", port, "--duration", str(SYNC_MINUTES), "--seed", "11", "--bots", "2")
    server.wait_for(r"server listening", 30)
    alice = _client(procs, "sync-alice", port)
    bob = _client(procs, "sync-bob", port, "--autoplay-variant", "1")
    budget = SYNC_MINUTES * 60 + 90 + 75 * max(SYNC_MINUTES // 2, 0)  # each quiz + draft adds ~1 min
    assert alice.wait(budget) == 0, alice.log_path
    assert bob.wait(60) == 0, bob.log_path
    assert server.wait(60) == 0, server.log_path  # empty room closes itself
    digests = {p.name: p.digest() for p in (server, alice, bob)}
    assert len(set(digests.values())) == 1, digests
    # The scripted players actually played (money moved).
    assert any(part.split(":")[1] != "1000" for part in digests["sync-server"].split(",")), digests
    if SYNC_MINUTES >= 2:
        # Quizzes ran and the rewards draft handed out items (identical on every process).
        assert any(part.split(":")[2] for part in digests["sync-server"].split(",")), digests
        for p in (alice, bob):
            played = p.nettest("autoplay")[-1]
            assert "answers=0" not in played and "drafts=0" not in played, (p.name, played)
    for p in (server, alice, bob):
        assert p.errors() == [], (p.name, p.errors()[:5])
    for p in (alice, bob):
        down = float(p.nettest("bandwidth")[-1].split()[0].split("=")[1])
        assert down < 30_000, f"{p.name} downloads {down:.0f} B/s"


def test_shoves_grab_throw_and_knockout_agree_at_150ms_and_2pct_loss(procs):
    port = free_port()
    lag = ["--net-latency", "150", "--net-loss", "0.02"]
    server = _server(procs, "phys-server", port, "--duration", "1", "--seed", "9")
    server.wait_for(r"server listening", 30)
    thrower = _client(procs, "phys-thrower", port, "--autoplay-script", "thrower", *lag)
    victim = _client(procs, "phys-victim", port, "--autoplay-script", "victim", *lag)
    assert thrower.wait(200) == 0, thrower.log_path
    assert victim.wait(60) == 0, victim.log_path
    assert server.wait(60) == 0, server.log_path
    log = thrower.log()
    # A shove exchange: both players shoved the other.
    assert '"attacker": 1, "target": 2' in log and '"attacker": 2, "target": 1' in log and "player_shoved" in log
    assert '"type": &"player_thrown"' in log
    assert '"cause": &"shoves", "type": &"player_knocked_out"' in log
    for p in (thrower, victim):
        agreements = [float(x.split("agreement=")[1]) for x in p.nettest("got_up")]
        assert len(agreements) >= 2, (p.name, agreements)  # after the throw and after the knockout
        assert max(agreements) <= 0.3, (p.name, agreements)
    authority = victim.nettest("authority")
    assert authority, "victim never checked its body"
    assert "state=0" in authority[0] and float(authority[0].split("drift=")[1]) < 0.5, authority
    digests = {p.name: p.digest() for p in (server, thrower, victim)}
    assert len(set(digests.values())) == 1, digests
    for p in (server, thrower, victim):
        assert p.errors() == [], (p.name, p.errors()[:5])
    assert "moved implausibly" not in server.log()


def test_version_mismatch_is_refused_with_a_reason(procs):
    port = free_port()
    server = _server(procs, "ver-server", port)
    server.wait_for(r"server listening", 30)
    client = procs("ver-client", ["--connect", f"127.0.0.1:{port}", "--name", "Old", "--build", "0.0.1-old", "--quit-on-disconnect"])
    assert client.wait(60) == 4, client.log_path
    assert "could not join" in client.log() and "update" in client.log().lower()
    assert "rejected: version" in server.log()
    server.kill()
