"""The single error type every endpoint raises; rendered as ``{"error", "message"}``."""

from __future__ import annotations

from typing import Any


class ApiError(Exception):
    """An HTTP error with a stable machine-readable ``code`` and a human ``message``."""

    def __init__(self, status: int, code: str, message: str, **extra: Any) -> None:
        super().__init__(f"{status} {code}: {message}")
        self.status = status
        self.code = code
        self.message = message
        self.extra = extra

    def body(self) -> dict[str, Any]:
        """JSON body for the response."""
        return {"error": self.code, "message": self.message, **self.extra}
