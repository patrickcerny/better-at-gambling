"""Host mode over real ENet sockets (a party on the host's PC, docs/DECISIONS.md "Host mode over
Steam"): the room server runs as `--server --host-mode` (what `SteamParty` starts next to the
host's game), listens on loopback only, admits without an orchestrator by the hello's uid (the
Steam ID the host's bridge stamps), refuses other builds, plays a whole match with the host and a
friend in agreement, and closes once the host's game is gone. The Steam leg itself (relay,
lobby, overlay) needs a Steam client and is covered in-process with a fake Steam
(tests/integration/test_host_mode.gd, tests/unit/test_steam_transport.gd)."""

from __future__ import annotations

import math
import re
import struct
import time
import wave
from pathlib import Path

import pytest
from conftest import LOG_DIR, free_port
from test_net_match import _read_wav, _tone_amplitude, _tone_frames

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


def _tone_wav(path, hz, amp=12000, rate=16000):
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(b"".join(struct.pack("<h", int(amp * math.sin(2 * math.pi * hz * i / rate))) for i in range(rate)))


@pytest.mark.parametrize("via", ["loopback", "bridge"])
def test_voice_goes_both_ways_between_the_host_and_a_friend_in_a_hosted_room(procs, tmp_path, via):
    """Voice in a party hosted on the host's PC (Patrick, 0.9.10: "other people online dont hear
    me"): the room is the `--server --host-mode` process `SteamParty` starts (loopback only,
    admitted by uid, no orchestrator) and the host's own game talks to it as player `HOST_UID`.
    The friend, a separate process, joins either straight to the room (`loopback`) or the way a
    Steam friend does, through the host game's `HostBridge` (`bridge`: `--bridge-port`, the same
    bridge with ENet in place of Steam's relay, one loopback link per friend to the room). Both
    loop a tone into their real capture path (`--voice-test`, a different tone each) and dump what
    they played (`--voice-dump`). Every hop is counted both ways, and each side must have played
    the other's tone, not its own. Steam itself is covered in-process with a fake Steam
    (tests/integration/test_voice_over_steam.gd, tests/unit/test_steam_transport.gd)."""
    tones = {"host-voice-patrick": 440.0, "host-voice-friend": 1000.0}
    amp = 12000 / 32768
    port = free_port()
    bridge_port = free_port()
    server = _host_server(procs, f"host-voice-{via}-server", port, "--minigames", "0", "--gamble-seconds", "30", "--seed", "3")
    clients = {}
    for name, uid, extra in (("host-voice-patrick", HOST_UID, ["--bridge-port", str(bridge_port)] if via == "bridge" else []), ("host-voice-friend", FRIEND_UID, ["--autoplay-variant", "1"])):
        _tone_wav(tmp_path / f"{name}.wav", tones[name])
        args = ["--voice-test", str(tmp_path / f"{name}.wav"), "--voice-dump", str(tmp_path / f"{name}_heard.wav"), *extra]
        if name == "host-voice-friend" and via == "bridge":
            clients["host-voice-patrick"].wait_for(r"dev bridge: friends over ENet", 60)
            clients[name] = procs(f"{name}-{via}", ["--connect", f"127.0.0.1:{bridge_port}", "--name", name, "--uid", uid, "--autoplay", "--quit-after-results", *args])
        else:
            clients[name] = procs(f"{name}-{via}", ["--connect", f"127.0.0.1:{port}", "--name", name, "--uid", uid, "--autoplay", "--quit-after-results", *args])
    host, friend = clients["host-voice-patrick"], clients["host-voice-friend"]
    assert host.wait(240) == 0, host.log_path
    assert friend.wait(60) == 0, friend.log_path
    assert server.wait(60) == 0, server.log_path
    log = server.log()
    assert "host mode: a party on a player's PC" in log
    ids = {name: int(re.search(rf"{name} joined as player (\d+)", log).group(1)) for name in clients}
    if via == "bridge":
        assert "voice: first packet from friend peer" in host.log() and "voice: first packet from the room to friend peer" in host.log(), host.log_path
    relay = re.search(r"voice relay: (.*)", log)
    assert relay, ("no relay summary", server.log_path)
    for speaker, listener in ((host, friend), (friend, host)):
        s_id, l_id = ids[_base(speaker)], ids[_base(listener)]
        assert int(re.search(r"welcomed as player (\d+)", speaker.log()).group(1)) == s_id
        sent = int(re.search(r"sent (\d+) frames \(\d+ bytes\)", speaker.log()).group(1))
        got_at_server, unheard, alone = (int(x) for x in re.search(rf"player {s_id} sent (\d+) \((\d+) reached nobody, (\d+) of them with nobody else in the room", relay.group(1)).groups())
        to_listener = int(re.search(rf"player {l_id} got (\d+)", relay.group(1)).group(1))
        line = re.search(rf"voice from player {s_id}: received (\d+), played (\d+), late (\d+), overflowed (\d+) \((\d+) before the first frame played\), lost (\d+)", listener.log())
        assert line, (listener.name, "never heard", speaker.name, listener.log_path)
        got, played, late, overflowed, backlog, lost = (int(line.group(i)) for i in range(1, 7))
        hops = {"sent": sent, "server got": got_at_server, "before the other joined": unheard, "server sent": to_listener, "got": got, "played": played, "late": late, "overflowed": overflowed, "of them before the first frame played": backlog}
        print(f"{speaker.name} -> {listener.name}:", hops)
        assert sent > 200, hops  # 25 frames/s on the casino floor
        assert got_at_server >= sent * 0.98 - 2, hops
        # What reached nobody was said with nobody else in the room: before the other one joined
        # (the host's game may start talking seconds before the friend's has joined, more on a
        # busy machine: 237 frames, 0.9.13) or after they left (the last frame or two, 0.9.15).
        # Out of reach while the other was present would be a relay bug: the server counts both
        # kinds when it first relays to them, and the totals must not grow apart afterwards.
        before = re.search(rf"relaying player {s_id}'s voice to player\(s\) \[{l_id}\] \([^,]*, after (\d+) that reached nobody, (\d+) of them with nobody else in the room\)", log)
        assert before, (hops, log[-2000:])
        before_unheard, before_alone = int(before.group(1)), int(before.group(2))
        assert before_unheard == before_alone, (hops, before.group(0))
        assert unheard == alone, (hops, before.group(0))
        assert to_listener >= (got_at_server - unheard) * 0.98 - 2, hops  # in reach all along
        assert got >= to_listener * 0.98 - 2, hops
        assert played + late + overflowed >= got - 12, hops
        # The drops while playing stay rare. What queued up while the listener's match was still
        # loading is trimmed to the newest 12 frames before their first frame plays: the bridged
        # friend joins seconds after the host started talking, and their 3-4% "burst" drops on
        # that leg were all this backlog (0-1 frames dropped while playing, 0.9.13).
        assert late + overflowed - backlog <= got * 0.05, hops
        rate, x = _read_wav(tmp_path / f"{_base(listener)}_heard_p{s_id}.wav")
        assert rate == 8000 and len(x) == played * 320, (rate, len(x), played)
        # Every frame played is the speaker's tone at their level (only concealed frames may be
        # off), in one phase except where a counted frame went missing on the way.
        body = x[320 * 3:]
        amps, jumps = _tone_frames(body, tones[_base(speaker)], rate)
        off = [round(a, 3) for a in amps if abs(a - amp) >= amp * 0.1]
        missing = late + overflowed - backlog + lost + (sent - got_at_server) + max(got_at_server - unheard - to_listener, 0) + (to_listener - got)
        own = _tone_amplitude(body, tones[_base(listener)], rate)
        print(f"{listener.name} heard {len(x) / rate:.1f} s of {speaker.name}: {sorted(amps)[len(amps) // 2]:.3f} at {tones[_base(speaker)]:.0f} Hz (median of {len(amps)} frames, {len(off)} off level, {jumps} phase jumps for {missing} missing frames), {own:.3f} at its own tone")
        assert len(off) <= lost, (off[:20], lost)
        assert jumps <= missing, (jumps, hops)
        assert own < amp * 0.05, (own, amp)
        # Nobody plays their own voice back.
        assert not (tmp_path / f"{_base(listener)}_heard_p{l_id}.wav").exists()
    for p in (server, host, friend):
        assert p.errors() == [], (p.name, p.errors()[:5])


def _base(p):
    """The player name behind a process name ("host-voice-friend-bridge" -> "host-voice-friend")."""
    return p.name.rsplit("-", 1)[0]
