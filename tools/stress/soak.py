#!/usr/bin/env python3
"""Playroom soak: a real headless room server and N scripted clients play whole matches over ENet
on loopback, and this reads every log afterwards.

    python3 tools/stress/soak.py                       # the default scenario list
    python3 tools/stress/soak.py --scenario casino4    # one scenario by name
    python3 tools/stress/soak.py --list
    python3 tools/stress/soak.py --custom --clients 6 --mode minigames --pool spy,vote_race \
        --minigames 2 --latency 120 --loss 0.02

What counts as a failure: a client or the server that does not exit cleanly, any error line in any
log (script errors included), clients and server disagreeing on the final money and inventories
(the `NETTEST digest`), or a run that never finishes. Warnings, rejected intents, bandwidth, server
CPU and memory are reported so a run can be compared with the last one.

Logs: build/test-logs/soak/<scenario>/<process>.log
"""

from __future__ import annotations

import argparse
import collections
import dataclasses
import os
import re
import signal
import socket
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GODOT = Path(os.environ.get("GODOT", ROOT / "tools/godot/godot"))
LOGS = ROOT / "build/test-logs/soak"
# Same lines that fail the net tests (tests/net/conftest.py) and scripts/_common.sh.
ERROR_RE = re.compile(r"SCRIPT ERROR|^ERROR:|Parse Error|Failed to load script|Invalid call|\[ERROR\]", re.M)
WARN_RE = re.compile(r"^(?:WARNING: )?\[WARN\]\[([^\]]+)\] (.*)$", re.M)
REJECT_RE = re.compile(r'"error": &"([a-z_]+)"[^\n]*"type": &"intent_rejected"|intent_rejected[^\n]*"error": &"([a-z_]+)"')
ALL_MINIGAMES = [
    "quiz", "lonely_number", "roulette_royale", "split_or_steal", "bust_or_bank", "vote_race",
    "find_the_lady", "forehead_poker", "spy", "pass_the_bomb", "bat_heist", "last_seat",
    "grab_your_hand", "roulette_sumo", "dodge_the_dice", "jackpot_climb",
]


@dataclasses.dataclass
class Scenario:
    name: str
    clients: int = 4
    mode: str = "casino"
    minigames: int = 1
    gamble_seconds: int = 60
    pool: str = ""
    briefing: float = 0.0
    seed: int = 3
    latency: float = 0.0
    loss: float = 0.0
    floor: str = ""
    dummies: int = 0
    timeout: int = 900
    server_extra: tuple[str, ...] = ()
    client_extra: tuple[str, ...] = ()


def scenarios() -> dict[str, Scenario]:
    out = [
        Scenario("casino4", clients=4, minigames=1, gamble_seconds=150, pool="quiz"),
        Scenario("casino8", clients=8, minigames=1, gamble_seconds=120, pool="quiz", seed=5),
        Scenario("casino2_lag", clients=2, minigames=1, gamble_seconds=120, pool="quiz", latency=150, loss=0.02, seed=7),
        Scenario("drawn_floor4", clients=4, minigames=0, gamble_seconds=150, floor="random", seed=21),
    ]
    # Every minigame once, as its own minigames-only match with four players.
    for i, mg in enumerate(ALL_MINIGAMES):
        out.append(Scenario(f"mg_{mg}", clients=4, mode="minigames", minigames=1, pool=mg, seed=30 + i, timeout=600))
    out.append(Scenario("mg_all8", clients=8, mode="minigames", minigames=6, pool="", seed=77, timeout=1800))
    return {s.name: s for s in out}


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


class Proc:
    def __init__(self, folder: Path, name: str, args: list[str]):
        folder.mkdir(parents=True, exist_ok=True)
        self.name = name
        self.log_path = folder / f"{name}.log"
        self._log = open(self.log_path, "w")
        cmd = [str(GODOT), "--headless", "--path", str(ROOT), "--audio-driver", "Dummy", "--", *args]
        self.proc = subprocess.Popen(cmd, stdout=self._log, stderr=subprocess.STDOUT, cwd=ROOT, start_new_session=True)
        self.cpu: list[float] = []
        self.rss_peak = 0.0
        self._ticks = self._cpu_ticks()

    def _cpu_ticks(self) -> int:
        fields = Path(f"/proc/{self.proc.pid}/stat").read_text().rsplit(")", 1)[1].split()
        return int(fields[11]) + int(fields[12])  # utime + stime

    def sample(self, hz: int, seconds: float) -> None:
        if self.proc.poll() is not None:
            return
        try:
            now = self._cpu_ticks()
            for line in Path(f"/proc/{self.proc.pid}/status").read_text().splitlines():
                if line.startswith("VmRSS:"):
                    self.rss_peak = max(self.rss_peak, int(line.split()[1]) / 1024.0)
        except (FileNotFoundError, ProcessLookupError):
            return
        self.cpu.append(100.0 * (now - self._ticks) / hz / max(seconds, 1e-6))
        self._ticks = now

    def alive(self) -> bool:
        return self.proc.poll() is None

    def kill(self) -> None:
        if self.alive():
            try:
                os.killpg(self.proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            self.proc.wait(timeout=10)

    def log(self) -> str:
        self._log.flush()
        return self.log_path.read_text(errors="replace")

    def wait_for(self, pattern: str, timeout: float) -> bool:
        deadline = time.monotonic() + timeout
        rx = re.compile(pattern)
        while time.monotonic() < deadline:
            if rx.search(self.log()):
                return True
            if not self.alive():
                return False
            time.sleep(0.2)
        return False


def normalize(text: str) -> str:
    """A warning with its numbers taken out, so repeats of one warning count as one."""
    return re.sub(r"-?\d+(?:\.\d+)?", "#", text)[:110]


def run(sc: Scenario, verbose: bool = False) -> bool:
    folder = LOGS / sc.name
    port = free_port()
    server_args = ["--server", "--port", str(port), "--empty-timeout", "4", "--minigames", str(sc.minigames),
                   "--gamble-seconds", str(sc.gamble_seconds), "--seed", str(sc.seed), "--mode", sc.mode,
                   "--minigame-briefing", str(sc.briefing)]
    if sc.pool:
        server_args += ["--minigame-pool", sc.pool]
    if sc.floor:
        server_args += ["--floor", sc.floor]
    if sc.dummies:
        server_args += ["--dummies", str(sc.dummies)]
    server_args += list(sc.server_extra)
    started = time.monotonic()
    server = Proc(folder, "server", server_args)
    procs = [server]
    problems: list[str] = []
    hz = os.sysconf("SC_CLK_TCK")
    try:
        if not server.wait_for(r"server listening", 60):
            problems.append("server never listened")
        clients: list[Proc] = []
        if not problems:
            for i in range(sc.clients):
                args = ["--connect", f"127.0.0.1:{port}", "--name", f"Soak{i + 1}", "--uid", f"dev:soak{i + 1}", "--autoplay",
                        "--quit-after-results", "--autoplay-variant", str(i % 2)]
                if sc.latency > 0.0:
                    args += ["--net-latency", str(sc.latency)]
                if sc.loss > 0.0:
                    args += ["--net-loss", str(sc.loss)]
                args += list(sc.client_extra)
                clients.append(Proc(folder, f"client{i + 1}", args))
            procs += clients
        last = time.monotonic()
        while not problems and any(p.alive() for p in procs):
            time.sleep(1.0)
            now = time.monotonic()
            for p in procs:
                p.sample(hz, now - last)
            last = now
            if now - started > sc.timeout:
                stuck = [p.name for p in procs if p.alive()]
                problems.append(f"timeout after {sc.timeout} s, still running: {', '.join(stuck)}")
    finally:
        for p in procs:
            p.kill()
    seconds = time.monotonic() - started

    digests: dict[str, str] = {}
    warnings: collections.Counter[str] = collections.Counter()
    rejects: collections.Counter[str] = collections.Counter()
    downs: list[float] = []
    pings: list[int] = []
    for p in procs:
        text = p.log()
        code = p.proc.returncode
        if code != 0 and not any(x.startswith("timeout") for x in problems):
            problems.append(f"{p.name} exited with {code}")
        errors = [line for line in text.splitlines() if ERROR_RE.search(line)]
        if errors:
            problems.append(f"{p.name}: {len(errors)} error lines, first: {errors[0][:200]}")
        for tag, msg in WARN_RE.findall(text):
            warnings[f"[{tag}] {normalize(msg)}"] += 1
        if p is not server:
            for a, b in REJECT_RE.findall(text):
                rejects[a or b] += 1
            for row in re.findall(r"NETTEST bandwidth down=(\d+) B/s ping=(-?\d+) ms", text):
                downs.append(float(row[0]))
                pings.append(int(row[1]))
        found = re.findall(r"NETTEST digest (.*) hash=", text)
        if found:
            digests[p.name] = found[-1]
        elif not any(x.startswith("timeout") for x in problems):
            problems.append(f"{p.name}: no final digest")
    if len(set(digests.values())) > 1:
        problems.append("digests differ: " + "; ".join(f"{k}={v}" for k, v in sorted(digests.items())))

    busy = server.cpu[5:] or server.cpu
    load = [sum(p.cpu[i] for p in procs if i < len(p.cpu)) for i in range(len(server.cpu))]
    status = "FAIL" if problems else "ok"
    print(f"{status:4} {sc.name:22} {seconds:6.0f} s  clients={sc.clients}  server cpu avg={sum(busy) / max(len(busy), 1):5.1f}% peak={max(busy, default=0.0):5.1f}%"
          f" rss={server.rss_peak:4.0f} MB  down={sum(downs) / max(len(downs), 1):6.0f} B/s  machine peak={max(load, default=0.0):4.0f}% of one core"
          f"  warnings={sum(warnings.values())} rejected={sum(rejects.values())}")
    if digests and not problems:
        print(f"     digest {next(iter(digests.values()))[:230]}")
    for line in problems:
        print(f"     PROBLEM {line}")
    shown = warnings.most_common(None if verbose else 6)
    for text, n in shown:
        print(f"     warn x{n}: {text}")
    if rejects:
        print("     rejected intents: " + ", ".join(f"{k} x{n}" for k, n in rejects.most_common()))
    sys.stdout.flush()
    return not problems


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--scenario", action="append", default=[], help="scenario name (repeatable), 'all', or a prefix ending in *")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--verbose", action="store_true", help="print every distinct warning")
    ap.add_argument("--custom", action="store_true", help="build one scenario from the options below")
    for field in dataclasses.fields(Scenario):
        if field.name in ("name", "server_extra", "client_extra"):
            continue
        ap.add_argument(f"--{field.name.replace('_', '-')}", type=type(field.default), default=None)
    a = ap.parse_args()
    if not GODOT.exists():
        print(f"Godot not found at {GODOT}; run tools/setup_toolchain.sh", file=sys.stderr)
        return 2
    known = scenarios()
    if a.list:
        for s in known.values():
            print(s)
        return 0
    chosen: list[Scenario] = []
    if a.custom:
        sc = Scenario("custom")
        for field in dataclasses.fields(Scenario):
            v = getattr(a, field.name, None)
            if v is not None:
                setattr(sc, field.name, v)
        chosen.append(sc)
    else:
        names = a.scenario or ["casino4", "mg_quiz"]
        for n in names:
            if n == "all":
                chosen += list(known.values())
            elif n.endswith("*"):
                chosen += [s for k, s in known.items() if k.startswith(n[:-1])]
            elif n in known:
                chosen.append(known[n])
            else:
                print(f"unknown scenario {n!r}; --list shows them", file=sys.stderr)
                return 2
        for sc in chosen:  # options given next to named scenarios override them (e.g. --clients 8)
            for field in dataclasses.fields(Scenario):
                v = getattr(a, field.name, None)
                if v is not None:
                    setattr(sc, field.name, v)
    failed = [sc.name for sc in chosen if not run(sc, a.verbose)]
    print(f"{len(chosen) - len(failed)}/{len(chosen)} scenarios ok" + (f"; FAILED: {', '.join(failed)}" if failed else ""))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
