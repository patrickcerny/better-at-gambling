"""Room-code and secret generation."""

from __future__ import annotations

import secrets
import uuid
from typing import Container

#: No ambiguous characters (no I, L, O, 0, 1).
CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
CODE_LENGTH = 5


def new_room_code(taken: Container[str], attempts: int = 1000) -> str:
    """Return a random 5-char room code not contained in ``taken``."""
    for _ in range(attempts):
        code = "".join(secrets.choice(CODE_ALPHABET) for _ in range(CODE_LENGTH))
        if code not in taken:
            return code
    raise RuntimeError("could not allocate a unique room code")


def normalize_room_code(code: str) -> str:
    """Normalize user input for code lookups (case-insensitive, trimmed)."""
    return code.strip().upper()


def new_room_id() -> str:
    """Return a new room id (uuid4 hex)."""
    return uuid.uuid4().hex


def new_room_secret() -> str:
    """Return a new per-room secret shared only with the game-server process."""
    return secrets.token_urlsafe(24)


def new_join_token() -> str:
    """Return a new single-use join token."""
    return secrets.token_urlsafe(16)
