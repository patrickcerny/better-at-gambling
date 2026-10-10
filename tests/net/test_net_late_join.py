"""Late join over real ENet (Patrick: "Let players join running rounds"): a third client connects
after the match started, is admitted (not refused as in progress), loads in, plays on and ends the
match in agreement with everyone else."""

from __future__ import annotations

from conftest import free_port


def test_a_client_joins_a_running_match_and_finishes_in_agreement(procs):
    port = free_port()
    server = procs("late-server", ["--server", "--port", str(port), "--empty-timeout", "4",
                                   "--minigames", "0", "--gamble-seconds", "60", "--seed", "23"])
    server.wait_for(r"server listening", 30)
    common = ["--autoplay", "--quit-after-results"]
    alice = procs("late-alice", ["--connect", f"127.0.0.1:{port}", "--name", "late-alice", *common])
    bob = procs("late-bob", ["--connect", f"127.0.0.1:{port}", "--name", "late-bob", "--autoplay-variant", "1", *common])
    alice.wait_for(r"match is on", 120)
    carol = procs("late-carol", ["--connect", f"127.0.0.1:{port}", "--name", "late-carol", *common])
    server.wait_for(r"late-carol joined the running match", 60)
    carol.wait_for(r"welcomed as player 3", 30)
    assert alice.wait(60 + 180) == 0, alice.log_path
    assert bob.wait(60) == 0, bob.log_path
    assert carol.wait(60) == 0, carol.log_path
    assert server.wait(60) == 0, server.log_path
    assert "room_in_progress" not in carol.log()
    digests = {p.name: p.digest() for p in (server, alice, bob, carol)}
    assert len(set(digests.values())) == 1, digests
    assert len(digests["late-server"].split(",")) == 3, digests  # three players in the standings
    for p in (server, alice, bob, carol):
        assert p.errors() == [], (p.name, p.errors()[:5])
