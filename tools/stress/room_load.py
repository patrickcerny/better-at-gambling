#!/usr/bin/env python3
"""Measures what one room costs: a headless room server with N scripted (autoplay) clients plays a
short match while this samples the server's CPU and memory from /proc.

    python3 tools/stress/room_load.py [--clients 4] [--minutes 2]

Prints average and peak CPU (% of one core) and peak RSS, which gives rooms per VPS:
cores * 70 / avg_cpu, and free RAM / peak RSS (the lower of the two).
"""

from __future__ import annotations

import argparse
import os
import signal
import socket
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GODOT = Path(os.environ.get("GODOT", ROOT / "tools/godot/godot"))
LOGS = ROOT / "build/test-logs/stress"


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def godot(name: str, args: list[str]) -> subprocess.Popen:
    LOGS.mkdir(parents=True, exist_ok=True)
    log = open(LOGS / f"{name}.log", "w")
    cmd = [str(GODOT), "--headless", "--path", str(ROOT), "--audio-driver", "Dummy", "--", *args]
    return subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT, cwd=ROOT, start_new_session=True)


def cpu_ticks(pid: int) -> int:
    fields = Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()
    return int(fields[11]) + int(fields[12])  # utime + stime


def rss_mb(pid: int) -> float:
    for line in Path(f"/proc/{pid}/status").read_text().splitlines():
        if line.startswith("VmRSS:"):
            return int(line.split()[1]) / 1024.0
    return 0.0


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--clients", type=int, default=4)
    ap.add_argument("--minutes", type=int, default=2)
    a = ap.parse_args()
    port = free_port()
    server = godot("server", ["--server", "--port", str(port), "--duration", str(a.minutes), "--seed", "3", "--empty-timeout", "4"])
    time.sleep(3)
    clients = [godot(f"client{i}", ["--connect", f"127.0.0.1:{port}", "--name", f"Load{i}", "--autoplay", "--quit-after-results", "--autoplay-variant", str(i % 2)]) for i in range(a.clients)]
    hz = os.sysconf("SC_CLK_TCK")
    samples: list[float] = []
    peak_rss = 0.0
    last = cpu_ticks(server.pid)
    try:
        while server.poll() is None:
            time.sleep(1.0)
            try:
                now = cpu_ticks(server.pid)
                peak_rss = max(peak_rss, rss_mb(server.pid))
            except (FileNotFoundError, ProcessLookupError):
                break
            samples.append(100.0 * (now - last) / hz)
            last = now
    finally:
        for p in [server, *clients]:
            if p.poll() is None:
                os.killpg(p.pid, signal.SIGKILL)
    busy = samples[5:] or samples  # skip boot
    print(f"clients={a.clients} seconds={len(samples)} cpu_avg={sum(busy) / max(len(busy), 1):.1f}% cpu_peak={max(busy, default=0):.1f}% rss_peak={peak_rss:.0f}MB cores_here={os.cpu_count()}")


if __name__ == "__main__":
    main()
