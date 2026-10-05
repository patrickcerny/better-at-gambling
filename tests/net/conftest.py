"""Multi-process network tests (M3): real headless Godot servers and clients on loopback.

Every process logs to build/test-logs/net/<name>.log. Scripted clients (`--autoplay`) print
`NETTEST ...` lines that the tests parse: state digests, bandwidth, ragdoll agreement.
"""

from __future__ import annotations

import os
import re
import signal
import socket
import subprocess
import time
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
GODOT = Path(os.environ.get("GODOT", ROOT / "tools/godot/godot"))
LOG_DIR = ROOT / "build/test-logs/net"
# Lines that fail a run even with exit code 0 (same idea as scripts/_common.sh).
ERROR_RE = re.compile(r"SCRIPT ERROR|^ERROR:|Parse Error|Failed to load script|Invalid call|\[ERROR\]", re.M)


def build_id() -> str:
    text = (ROOT / "core/net/protocol.gd").read_text()
    return re.search(r'const BUILD_ID: String = "([^"]+)"', text).group(1)


def free_port(kind: int = socket.SOCK_DGRAM) -> int:
    with socket.socket(socket.AF_INET, kind) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def udp_port_free(port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        try:
            s.bind(("0.0.0.0", port))
        except OSError:
            return False
    return True


class GodotProc:
    """One headless Godot process with its log file."""

    def __init__(self, name: str, args: list[str], godot_args: list[str] | None = None):
        LOG_DIR.mkdir(parents=True, exist_ok=True)
        self.name = name
        self.log_path = LOG_DIR / f"{name}.log"
        self._log = open(self.log_path, "w")
        cmd = [str(GODOT), "--headless", *(godot_args or []), "--path", str(ROOT), "--audio-driver", "Dummy", "--", *args]
        self.proc = subprocess.Popen(cmd, stdout=self._log, stderr=subprocess.STDOUT, cwd=ROOT, start_new_session=True)

    def wait(self, timeout: float) -> int:
        try:
            return self.proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            self.kill()
            pytest.fail(f"{self.name} did not exit within {timeout:.0f} s (log: {self.log_path})")
        finally:
            self._log.flush()

    def kill(self) -> None:
        if self.proc.poll() is None:
            os.killpg(self.proc.pid, signal.SIGKILL)
            self.proc.wait(timeout=10)

    def log(self) -> str:
        self._log.flush()
        return self.log_path.read_text(errors="replace")

    def wait_for(self, pattern: str, timeout: float) -> re.Match:
        deadline = time.monotonic() + timeout
        rx = re.compile(pattern)
        while time.monotonic() < deadline:
            m = rx.search(self.log())
            if m:
                return m
            if self.proc.poll() is not None:
                break
            time.sleep(0.2)
        pytest.fail(f"{self.name}: {pattern!r} not seen (log: {self.log_path})")

    def errors(self) -> list[str]:
        return [line for line in self.log().splitlines() if ERROR_RE.search(line)]

    def nettest(self, key: str) -> list[str]:
        return re.findall(rf"NETTEST {key} (.*)", self.log())

    def digest(self) -> str:
        found = self.nettest("digest")
        assert found, f"{self.name}: no digest logged (log: {self.log_path})"
        return found[-1].split(" hash=")[0]


@pytest.fixture
def procs():
    """Collects processes and kills leftovers after the test."""
    started: list[GodotProc] = []

    def start(name: str, args: list[str], godot_args: list[str] | None = None) -> GodotProc:
        p = GodotProc(name, args, godot_args)
        started.append(p)
        return p

    yield start
    for p in started:
        p.kill()


def pytest_configure(config):
    if not GODOT.exists():
        raise pytest.UsageError(f"Godot not found at {GODOT}; run tools/setup_toolchain.sh")
