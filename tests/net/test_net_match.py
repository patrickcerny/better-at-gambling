"""Server + scripted clients over real ENet sockets (M3 acceptance)."""

from __future__ import annotations

import os
import time

from conftest import free_port

# Match length for the long sync test (M4 spec: two quizzes, 100 s of gambling before each and
# after the last). NET_SYNC_MINIGAMES shortens it.
SYNC_MINIGAMES = int(os.environ.get("NET_SYNC_MINIGAMES", "2"))
SYNC_GAMBLE_S = 100


def _server(procs, name, port, *extra):
    return procs(name, ["--server", "--port", str(port), "--empty-timeout", "4", *extra])


def _client(procs, name, port, *extra):
    return procs(name, ["--connect", f"127.0.0.1:{port}", "--name", name, "--autoplay", "--quit-after-results", *extra])


def test_two_clients_play_a_match_and_agree_on_every_balance(procs):
    port = free_port()
    server = _server(procs, "sync-server", port, "--minigames", str(SYNC_MINIGAMES), "--gamble-seconds", str(SYNC_GAMBLE_S), "--seed", "11", "--dummies", "2")
    server.wait_for(r"server listening", 30)
    alice = _client(procs, "sync-alice", port)
    bob = _client(procs, "sync-bob", port, "--autoplay-variant", "1")
    budget = SYNC_GAMBLE_S * (SYNC_MINIGAMES + 1) + 90 + 80 * SYNC_MINIGAMES  # each quiz + rewards + regroup ~80 s
    assert alice.wait(budget) == 0, alice.log_path
    assert bob.wait(60) == 0, bob.log_path
    assert server.wait(60) == 0, server.log_path  # empty room closes itself
    digests = {p.name: p.digest() for p in (server, alice, bob)}
    assert len(set(digests.values())) == 1, digests
    # The scripted players actually played (money moved).
    assert any(part.split(":")[1] != "1000" for part in digests["sync-server"].split(",")), digests
    if SYNC_MINIGAMES >= 1:
        # Quizzes ran, the rewards handed out items and the players used them online
        # (inventories in the digest may be empty again by the end).
        for p in (alice, bob):
            played = p.nettest("autoplay")[-1]
            assert "answers=0" not in played and "rewards=0" not in played, (p.name, played)
            assert "items=0" not in played, ("reward items get used online", p.name, played)
            # After each minigame everyone is back in the entrance hall (REGROUP).
            regroups = [float(x.split("dist=")[1]) for x in p.nettest("regroup")]
            assert len(regroups) == SYNC_MINIGAMES, (p.name, regroups)
            assert max(regroups) < 0.5, (p.name, regroups)
        assert server.log().count("phase regroup") == SYNC_MINIGAMES
    for p in (server, alice, bob):
        assert p.errors() == [], (p.name, p.errors()[:5])
    for p in (alice, bob):
        down = float(p.nettest("bandwidth")[-1].split()[0].split("=")[1])
        assert down < 30_000, f"{p.name} downloads {down:.0f} B/s"


def test_shoves_grab_throw_and_knockout_agree_at_150ms_and_2pct_loss(procs):
    port = free_port()
    lag = ["--net-latency", "150", "--net-loss", "0.02"]
    server = _server(procs, "phys-server", port, "--minigames", "0", "--gamble-seconds", "60", "--seed", "9")
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


def test_a_client_killed_mid_match_rejoins_with_its_state_and_the_match_finishes(procs):
    """M6 reconnect: kill a client process mid-match, start it again with the same uid; it gets its
    player back (money, items) from the snapshot and the match ends with everyone in agreement."""
    port = free_port()
    server = _server(procs, "rejoin-server", port, "--minigames", "0", "--gamble-seconds", "120", "--seed", "13")
    server.wait_for(r"server listening", 30)
    first = _client(procs, "rejoin-alice", port, "--uid", "dev:alice")
    bob = _client(procs, "rejoin-bob", port, "--autoplay-variant", "1")
    first.wait_for(r"match is on", 90)
    time.sleep(20)  # play a little, then crash
    first.kill()
    server.wait_for(r"player \d+ disconnected", 30)
    again = _client(procs, "rejoin-alice2", port, "--uid", "dev:alice")
    server.wait_for(r"rejoin-alice2 rejoined as player", 60)
    assert again.wait(2 * 60 + 240) == 0, again.log_path
    assert bob.wait(60) == 0, bob.log_path
    assert server.wait(60) == 0, server.log_path
    digests = {p.name: p.digest() for p in (server, again, bob)}
    assert len(set(digests.values())) == 1, digests
    for p in (server, again, bob):
        assert p.errors() == [], (p.name, p.errors()[:5])


def test_a_client_dropped_at_a_minigame_rejoins_through_rewards_and_regroup(procs):
    """B8 reconnect: a client dies the moment a minigame starts (its bets were just refunded and it
    was stood up), comes back with the same uid while the minigame runs, sits out the rest of it
    (away players score 0), gets its reward row, regroups in the hall and finishes the match in
    agreement with everyone."""
    port = free_port()
    server = _server(procs, "mgrejoin-server", port, "--minigames", "1", "--gamble-seconds", "45", "--seed", "17")
    server.wait_for(r"server listening", 30)
    first = _client(procs, "mgrejoin-alice", port, "--uid", "dev:alice")
    bob = _client(procs, "mgrejoin-bob", port, "--autoplay-variant", "1")
    server.wait_for(r"phase minigame", 150)
    first.kill()
    server.wait_for(r"player \d+ disconnected", 30)
    again = _client(procs, "mgrejoin-alice2", port, "--uid", "dev:alice")
    server.wait_for(r"mgrejoin-alice2 rejoined as player", 60)
    assert again.wait(45 * 2 + 240) == 0, again.log_path
    assert bob.wait(60) == 0, bob.log_path
    assert server.wait(60) == 0, server.log_path
    log = server.log()
    assert log.index("rejoined as player") < log.index("phase rewards"), "rejoined during the minigame"
    assert log.index("phase rewards") < log.index("phase regroup") < log.rindex("phase casino")
    digests = {p.name: p.digest() for p in (server, again, bob)}
    assert len(set(digests.values())) == 1, digests
    # The rejoined client learned about the regroup from the live event and went to its hall spot.
    regroup = again.nettest("regroup")
    assert regroup and float(regroup[-1].split("dist=")[1]) < 0.5, regroup
    for p in (server, again, bob):
        assert p.errors() == [], (p.name, p.errors()[:5])


def test_the_party_leader_leaves_the_lobby_and_the_next_one_starts_the_match(procs):
    """B8 host-left: the party leader's process dies in the entrance-hall lobby. Leadership passes
    to the next player, the room keeps going and the match is played to the end."""
    port = free_port()
    server = _server(procs, "hostleft-server", port, "--minigames", "0", "--gamble-seconds", "40", "--seed", "19", "--min-players", "2")
    server.wait_for(r"server listening", 30)
    leader = procs("hostleft-leader", ["--connect", f"127.0.0.1:{port}", "--name", "hostleft-leader", "--uid", "dev:leader"])
    leader.wait_for(r"welcomed as player 1", 60)
    a = _client(procs, "hostleft-a", port)
    b = _client(procs, "hostleft-b", port, "--autoplay-variant", "1")
    server.wait_for(r"hostleft-b joined as player", 60)
    leader.kill()  # the leader never readied up: the others can't start until they're gone
    server.wait_for(r"player 1 disconnected", 30)
    assert a.wait(40 + 240) == 0, a.log_path
    assert b.wait(60) == 0, b.log_path
    assert server.wait(60) == 0, server.log_path
    assert "phase casino" in server.log()
    assert "party leader is now player 2" in server.log(), "leadership passed on"
    digests = {p.name: p.digest() for p in (server, a, b)}
    assert len(set(digests.values())) == 1, digests
    for p in (server, a, b):
        assert p.errors() == [], (p.name, p.errors()[:5])
