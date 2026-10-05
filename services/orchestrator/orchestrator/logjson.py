"""Structured JSON-lines logging to stdout (one object per event)."""

from __future__ import annotations

import json
import sys
import threading
from datetime import datetime, timezone
from typing import Any, TextIO

_lock = threading.Lock()
_stream: TextIO | None = None


def set_stream(stream: TextIO | None) -> None:
    """Redirect log output (``None`` restores stdout). Used by tests."""
    global _stream
    _stream = stream


def log(event: str, level: str = "info", **fields: Any) -> None:
    """Write one JSON log line: ``{"ts", "level", "event", **fields}``.

    Callers must never pass secrets (tickets, keys, room secrets, join tokens).
    """
    record: dict[str, Any] = {
        "ts": datetime.now(timezone.utc).isoformat(timespec="milliseconds"),
        "level": level,
        "event": event,
    }
    record.update(fields)
    line = json.dumps(record, default=str, separators=(",", ":"))
    with _lock:
        out = _stream or sys.stdout
        out.write(line + "\n")
        out.flush()
