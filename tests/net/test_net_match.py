"""Server + scripted clients over real ENet sockets (M3 acceptance)."""

from __future__ import annotations

import math
import os
import re
import struct
import time
import wave

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
    # The scripted clients only answer quiz questions, so pin the pool to the quiz.
    server = _server(procs, "sync-server", port, "--minigames", str(SYNC_MINIGAMES), "--gamble-seconds", str(SYNC_GAMBLE_S), "--seed", "11", "--dummies", "2", "--minigame-pool", "quiz", "--minigame-briefing", "0")
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
    # The scripted brawl needs the open plaza inside the lobby doors (THROW_SPOT and the throw east
    # of it): the full floor keeps it open (a drawn floor may stand a slot island there), and no
    # guard patrols, so whether one walks past and jails the thrower is not down to timing.
    server = _server(procs, "phys-server", port, "--minigames", "0", "--gamble-seconds", "60", "--seed", "9", "--floor", "full", "--guards", "0")
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


def _read_wav(path):
    """Mono 16-bit WAV -> (rate, samples in [-1, 1])."""
    with wave.open(str(path), "rb") as w:
        assert w.getnchannels() == 1 and w.getsampwidth() == 2, path
        rate = w.getframerate()
        raw = w.readframes(w.getnframes())
    return rate, [v / 32768.0 for v in struct.unpack(f"<{len(raw) // 2}h", raw)]


def _tone_amplitude(x, hz, rate):
    """Goertzel: amplitude of the `hz` component (a sine of amplitude A reads about A)."""
    c = 2.0 * math.cos(2.0 * math.pi * hz / rate)
    s1 = s2 = 0.0
    for v in x:
        s1, s2 = v + c * s1 - s2, s1
    return math.sqrt(max(s1 * s1 + s2 * s2 - c * s1 * s2, 0.0)) * 2.0 / len(x)


def _tone_frames(x, hz, rate, frame=320):
    """The `hz` component of every 40 ms frame of `x`: (amplitudes, phase jumps). The phase is
    taken against one clock for the whole dump, so a tone played without a break keeps one phase
    from frame to frame; a frame missing in between (dropped on purpose by the jitter buffer,
    concealed, or never relayed) shows up as a jump, unless the missing stretch held whole cycles.

    A single Goertzel over the whole dump reads the level only while the tone stays in phase:
    after each drop the rest of the dump arrives in another phase and partly cancels what came
    before (0.9.13: a listener stalled twice for 0.7 s dropped 35 frames in three places, every
    played frame was the tone at 0.363-0.367, the whole dump read 0.108)."""
    amps, phases = [], []
    w = 2.0 * math.pi * hz / rate
    for k in range(len(x) // frame):
        re = im = 0.0
        for i in range(k * frame, (k + 1) * frame):
            re += x[i] * math.cos(w * i)
            im += x[i] * math.sin(w * i)
        amps.append(2.0 * math.hypot(re, im) / frame)
        phases.append(math.atan2(im, re))
    floor = max(amps, default=0.0) * 0.5
    jumps = 0
    for k in range(1, len(amps)):
        turn = (phases[k] - phases[k - 1] + math.pi) % (2.0 * math.pi) - math.pi
        if amps[k] >= floor and amps[k - 1] >= floor and abs(turn) > 0.5:
            jumps += 1
    return amps, jumps


def test_voice_from_one_client_is_relayed_by_the_dedicated_server_and_played_by_the_other(procs, tmp_path):
    """Proximity voice end to end (Patrick: "think of a way to test it if the other user received
    it"): Alice loops a 440 Hz WAV into her capture path (`--voice-test`, open mic), the headless
    dedicated server (Dummy audio driver) relays it, Bob's VoicePlayback plays it under Alice's
    avatar and `--voice-dump` writes what it played. Every hop's frame count is compared, and the
    WAV Bob played must be Alice's tone at Alice's level."""
    tone_hz, amp = 440.0, 12000 / 32768
    wav_path = tmp_path / "voice.wav"
    with wave.open(str(wav_path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(16000)
        w.writeframes(b"".join(struct.pack("<h", int(12000 * math.sin(2 * math.pi * tone_hz * i / 16000))) for i in range(16000)))
    dump = tmp_path / "bob_heard.wav"
    port = free_port()
    server = _server(procs, "voice-server", port, "--minigames", "0", "--gamble-seconds", "30", "--seed", "3")
    server.wait_for(r"server listening", 30)
    alice = _client(procs, "voice-alice", port, "--voice-test", str(wav_path))
    bob = _client(procs, "voice-bob", port, "--voice-dump", str(dump))
    assert alice.wait(240) == 0, alice.log_path
    assert bob.wait(60) == 0, bob.log_path
    assert server.wait(60) == 0, server.log_path
    stats = {}
    for p in (alice, bob):
        m = re.search(r"sent (\d+) frames \(\d+ bytes\), received (\d+) frames from (\d+) speakers, played (\d+) frames", p.log())
        assert m, (p.name, "no voice summary", p.log_path)
        stats[p.name] = [int(x) for x in m.groups()]
    sent, _, _, _ = stats["voice-alice"]
    _, received, speakers, played = stats["voice-bob"]
    assert sent > 200, stats  # 25 frames/s while she is on the casino floor
    assert received > 100 and speakers == 1, stats
    assert played > 100, stats
    a_id = int(re.search(r"welcomed as player (\d+)", alice.log()).group(1))
    b_id = int(re.search(r"welcomed as player (\d+)", bob.log()).group(1))
    # Hop by hop: Alice sent -> the server got -> the server sent Bob -> Bob got -> Bob played -> dumped.
    relay = re.search(r"voice relay: (.*)", server.log())
    assert relay, ("no relay summary", server.log_path)
    got_at_server = int(re.search(rf"player {a_id} sent (\d+)", relay.group(1)).group(1))
    to_bob = int(re.search(rf"player {b_id} got (\d+)", relay.group(1)).group(1))
    per_speaker = re.search(rf"voice from player {a_id}: received (\d+), played (\d+), late (\d+), overflowed (\d+) \((\d+) before the first frame played\), lost (\d+)", bob.log())
    assert per_speaker, ("no per-speaker line", bob.log_path)
    bob_got, bob_played, late, overflowed, backlog, lost = (int(per_speaker.group(i)) for i in range(1, 7))
    dumped = int(re.search(rf"voice dump: (\d+) frames from player {a_id}", bob.log()).group(1))
    hops = {"alice sent": sent, "server got": got_at_server, "server sent bob": to_bob, "bob got": bob_got, "bob played": bob_played, "late": late, "overflowed": overflowed, "of them before Bob played": backlog, "lost": lost, "dumped": dumped}
    print("voice hops:", hops)
    assert got_at_server >= sent * 0.98 - 2, hops  # loopback: nothing lost on the way up
    assert to_bob >= got_at_server * 0.9, hops  # Bob was in reach nearly all the time
    assert bob_got >= to_bob * 0.98 - 2, hops  # nothing lost on the way down
    # Every frame Bob got was played, or dropped on purpose by his jitter buffer (late, or the
    # oldest of a burst after a stall so latency stays bounded), or was still queued (at most its
    # 12-frame depth) when the match ended. Nothing just vanishes.
    assert bob_played + late + overflowed >= bob_got - 12, hops
    # And the drops while playing stay rare. What Alice said while Bob's match was still loading
    # queued up unheard and was trimmed to the newest 12 frames before his first frame played (on
    # a busy machine his load runs seconds behind hers: 70 frames, 0.9.13).
    assert late + overflowed - backlog <= bob_got * 0.05, hops
    # One playback under Alice's avatar all match long (a resync used to respawn her avatar,
    # dropping the buffered audio each time).
    assert bob.log().count(f"first frame played for player {a_id} ") == 1, bob.log_path
    assert dumped == bob_played, hops
    # What Bob played is Alice's tone, at Alice's level, frame by frame for as long as he got it:
    # only the frames his jitter buffer concealed may be off, and the tone runs on in one phase
    # except where a counted frame went missing on the way.
    rate, x = _read_wav(dump.with_name(f"bob_heard_p{a_id}.wav"))
    assert rate == 8000 and len(x) == dumped * 320, (rate, len(x), dumped)
    body = x[320 * 3:]
    amps, jumps = _tone_frames(body, tone_hz, rate)
    off = [round(a, 3) for a in amps if abs(a - amp) >= amp * 0.1]
    missing = late + overflowed - backlog + lost + (sent - got_at_server) + (got_at_server - to_bob) + (to_bob - bob_got)
    others = {hz: _tone_amplitude(body, hz, rate) for hz in (300.0, 700.0, 1000.0, 2000.0)}
    print(f"bob heard {len(x) / rate:.1f} s: {tone_hz:.0f} Hz at {sorted(amps)[len(amps) // 2]:.3f} (median of {len(amps)} frames, {len(off)} off level, {jumps} phase jumps for {missing} missing frames), others {others}")
    assert len(x) / rate > 5.0
    assert len(off) <= lost, (off[:20], lost)
    assert jumps <= missing, (jumps, hops)
    assert all(v < amp * 0.05 for v in others.values()), (amp, others)
    rms = math.sqrt(sum(v * v for v in body) / len(body))
    assert abs(rms - amp / math.sqrt(2)) < amp / math.sqrt(2) * 0.1, (rms, amp)
    for p in (server, alice, bob):
        assert p.errors() == [], (p.name, p.errors()[:5])
