"""Sliding-window rate limiter keyed by arbitrary strings (``ip:...``, ``uid:...``)."""

from __future__ import annotations

import time
from collections import deque
from typing import Callable


class RateLimiter:
    """Allow at most ``limit`` hits per ``window`` seconds per key."""

    def __init__(self, limit: int, window: float = 60.0, clock: Callable[[], float] | None = None) -> None:
        self.limit = limit
        self.window = window
        self._clock = clock or time.monotonic
        self._hits: dict[str, deque[float]] = {}
        self._last_sweep = self._clock()

    def hit(self, key: str) -> bool:
        """Record a hit for ``key``; return False if the key is over its limit."""
        now = self._clock()
        self._maybe_sweep(now)
        q = self._hits.setdefault(key, deque())
        cutoff = now - self.window
        while q and q[0] <= cutoff:
            q.popleft()
        if len(q) >= self.limit:
            return False
        q.append(now)
        return True

    def _maybe_sweep(self, now: float) -> None:
        """Drop idle keys periodically so memory stays bounded."""
        if now - self._last_sweep < self.window:
            return
        self._last_sweep = now
        cutoff = now - self.window
        for key in [k for k, q in self._hits.items() if not q or q[-1] <= cutoff]:
            del self._hits[key]
