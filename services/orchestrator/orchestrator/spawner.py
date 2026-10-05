"""Process spawning behind a small interface so tests can use :class:`FakeSpawner`."""

from __future__ import annotations

import os
import signal
import subprocess
from pathlib import Path
from typing import Protocol, Sequence


class ProcessHandle(Protocol):
    """A spawned game-server process."""

    pid: int

    def poll(self) -> int | None:
        """Return the exit code, or None while running."""

    def terminate(self) -> None:
        """Ask the process (group) to stop (SIGTERM)."""

    def kill(self) -> None:
        """Force-stop the process (group) (SIGKILL)."""


class Spawner(Protocol):
    """Starts game-server processes."""

    def spawn(self, argv: Sequence[str], cwd: str | None, log_path: Path) -> ProcessHandle:
        """Start ``argv``; raise OSError on failure."""


class PopenHandle:
    """:class:`ProcessHandle` over ``subprocess.Popen`` in its own process group."""

    def __init__(self, proc: subprocess.Popen[bytes]) -> None:
        self._proc = proc
        self.pid = proc.pid

    def poll(self) -> int | None:
        return self._proc.poll()

    def _signal(self, sig: int) -> None:
        if self._proc.poll() is not None:
            return
        try:
            os.killpg(self._proc.pid, sig)
        except (ProcessLookupError, PermissionError):
            try:
                self._proc.send_signal(sig)
            except ProcessLookupError:
                pass

    def terminate(self) -> None:
        self._signal(signal.SIGTERM)

    def kill(self) -> None:
        self._signal(signal.SIGKILL)


class PopenSpawner:
    """Real spawner: new session/process group, stdout+stderr to a per-room log file."""

    def spawn(self, argv: Sequence[str], cwd: str | None, log_path: Path) -> ProcessHandle:
        log_path.parent.mkdir(parents=True, exist_ok=True)
        with open(log_path, "ab") as out:
            proc = subprocess.Popen(
                list(argv),
                cwd=cwd,
                stdin=subprocess.DEVNULL,
                stdout=out,
                stderr=subprocess.STDOUT,
                start_new_session=True,
                close_fds=True,
            )
        return PopenHandle(proc)


class FakeProcess:
    """Test double for a process. Exits on ``terminate()`` unless ``stubborn``."""

    _next_pid = 10_000

    def __init__(self, argv: Sequence[str], stubborn: bool = False) -> None:
        FakeProcess._next_pid += 1
        self.pid = FakeProcess._next_pid
        self.argv = list(argv)
        self.returncode: int | None = None
        self.stubborn = stubborn
        self.terminated = False
        self.killed = False

    def poll(self) -> int | None:
        return self.returncode

    def exit(self, code: int = 0) -> None:
        """Simulate the process exiting by itself."""
        if self.returncode is None:
            self.returncode = code

    def terminate(self) -> None:
        self.terminated = True
        if not self.stubborn:
            self.exit(-signal.SIGTERM)

    def kill(self) -> None:
        self.killed = True
        self.exit(-signal.SIGKILL)


class FakeSpawner:
    """Records spawns and returns :class:`FakeProcess` handles."""

    def __init__(self, fail: bool = False, stubborn: bool = False) -> None:
        self.fail = fail
        self.stubborn = stubborn
        self.processes: list[FakeProcess] = []

    def spawn(self, argv: Sequence[str], cwd: str | None, log_path: Path) -> ProcessHandle:
        if self.fail:
            raise OSError("spawn failed (fake)")
        proc = FakeProcess(argv, stubborn=self.stubborn)
        self.processes.append(proc)
        return proc
