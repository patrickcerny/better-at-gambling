"""Server-checked leaderboards (Patrick 2026-11-18: "mach das mit den 2").

Every player who is still in an online match when it ends sends the match's result to
``POST /v1/matches/report`` with a Steam Web API ticket (so the reporter's Steam ID is vouched for
by Steam, not claimed). The :class:`ScoreKeeper` collects the reports of one match for
``score_window`` seconds (or until every player of the match reported) and then decides:

* at least two different Steam accounts sent the very same result and nobody sent another one:
  the match counts, each player's totals (best match money, matches won, total winnings) grow;
* anything else (only one report, or any report that contradicts another): the match counts for
  nobody and the contradiction is logged.

Only this server writes the Steam leaderboards (``ISteamLeaderboards/SetLeaderboardScore`` with
the publisher key), so with the boards set to "trusted" in Steamworks a modified game can no
longer put a made-up score there: it would need a second real Steam account in the same match
telling the same lie.

The publisher key is never logged.
"""

from __future__ import annotations

import hashlib
import json
import os
import sqlite3
import struct
import threading
from dataclasses import dataclass
from typing import Any, Awaitable, Callable, Iterable

import httpx

from .config import Config
from .logjson import log

#: Steam board names (the game's ``LeaderboardRules``).
BEST_MATCH_MONEY = "BEST_MATCH_MONEY"
MATCHES_WON = "MATCHES_WON"
ONLINE_WINNINGS = "ONLINE_WINNINGS"
BOARDS = (BEST_MATCH_MONEY, MATCHES_WON, ONLINE_WINNINGS)

#: Same limits as the game's ``LeaderboardRules``.
MAX_MATCH_MONEY = 1_000_000
MAX_TOTAL = 2_000_000_000
MAX_PLAYERS = 8
#: Steam leaderboard details: at most 64 int32 (256 bytes); the game sends 16 at most.
MAX_LOOK = 16

STEAM_API = "https://partner.steam-api.com/ISteamLeaderboards"

#: ``async (steam_id, board, score, details) -> ok``.
ScoreWriter = Callable[[str, str, int, bytes], Awaitable[bool]]


class ReportError(ValueError):
    """A report that can never count (bad shape, reporter not in the match, not ranked)."""

    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


@dataclass(frozen=True)
class Row:
    """One player's line of a match result."""

    steam_id: str
    rank: int
    money: int
    profit: int


def parse_rows(raw: Iterable[dict[str, Any]]) -> list[Row]:
    """Checks a match's rows: 2..8 distinct Steam IDs, ranks 1..n, money and profit in range,
    every row ranked by the host. Returns them sorted by Steam ID (the canonical order)."""
    rows: list[Row] = []
    raw = list(raw)
    if not 2 <= len(raw) <= MAX_PLAYERS:
        raise ReportError("not_ranked", "Only online matches with 2 to 8 players go on the leaderboards.")
    for r in raw:
        if not r.get("ranked", False):
            raise ReportError("not_ranked", "The host did not rank this match.")
        sid = str(r.get("steam_id", ""))
        if not (sid.isdigit() and 1 <= len(sid) <= 20):
            raise ReportError("bad_rows", "Every row needs a Steam ID.")
        if int(r.get("players", 0)) != len(raw):
            raise ReportError("bad_rows", "The rows disagree on the number of players.")
        rank, money, profit = int(r.get("rank", 0)), int(r.get("money", -1)), int(r.get("profit", 0))
        if not (1 <= rank <= len(raw)) or not (0 <= money <= MAX_MATCH_MONEY) or abs(profit) > MAX_MATCH_MONEY:
            raise ReportError("bad_rows", "A row's numbers are out of range.")
        rows.append(Row(sid, rank, money, profit))
    if len({r.steam_id for r in rows}) != len(rows):
        raise ReportError("bad_rows", "A player appears twice.")
    return sorted(rows, key=lambda r: r.steam_id)


def digest(rows: list[Row]) -> str:
    """The fingerprint two honest reports of the same match share."""
    canon = json.dumps([[r.steam_id, r.rank, r.money, r.profit] for r in rows], separators=(",", ":"))
    return hashlib.sha256(canon.encode()).hexdigest()


def match_key(match: str, rows: list[Row]) -> str:
    """A match is its server's match id plus who played: a stranger can't report into it."""
    return f"{match}|{','.join(r.steam_id for r in rows)}"


def look_bytes(look: Iterable[int]) -> bytes:
    """The game's look ints (``LeaderboardRules.skin_details``) as Steam's int32 details."""
    vals = [int(v) for v in list(look)[:MAX_LOOK]]
    return b"".join(struct.pack("<i", max(-(2**31), min(2**31 - 1, v))) for v in vals)


SCHEMA = """
CREATE TABLE IF NOT EXISTS matches (key TEXT PRIMARY KEY, first_at REAL NOT NULL, players INTEGER NOT NULL,
    state TEXT NOT NULL DEFAULT 'open', rows TEXT NOT NULL DEFAULT '');
CREATE TABLE IF NOT EXISTS reports (key TEXT NOT NULL, steam_id TEXT NOT NULL, digest TEXT NOT NULL,
    rows TEXT NOT NULL, at REAL NOT NULL, PRIMARY KEY (key, steam_id));
CREATE TABLE IF NOT EXISTS totals (steam_id TEXT PRIMARY KEY, best_money INTEGER NOT NULL DEFAULT 0,
    wins INTEGER NOT NULL DEFAULT 0, winnings INTEGER NOT NULL DEFAULT 0, matches INTEGER NOT NULL DEFAULT 0,
    look BLOB NOT NULL DEFAULT x'', dirty INTEGER NOT NULL DEFAULT 0);
"""


class ScoreKeeper:
    """Collects match reports, decides them, and keeps each player's server totals."""

    def __init__(self, config: Config, writer: ScoreWriter | None, clock: Callable[[], float]) -> None:
        self.config = config
        self.writer = writer
        self.clock = clock
        self.window = config.score_window
        self._lock = threading.Lock()
        if config.scores_db != ":memory:":
            os.makedirs(os.path.dirname(config.scores_db) or ".", exist_ok=True)
        self.db = sqlite3.connect(config.scores_db, check_same_thread=False, isolation_level=None)
        self.db.executescript(SCHEMA)

    # ------------------------------------------------------------------ reports
    def report(self, reporter: str, match: str, raw_rows: list[dict[str, Any]], look: list[int] | None) -> str:
        """Takes one player's report. Returns ``open`` (waiting for more), ``late`` (already decided)
        or ``duplicate``. Raises :class:`ReportError` for a report that can never count."""
        rows = parse_rows(raw_rows)
        if reporter not in {r.steam_id for r in rows}:
            raise ReportError("not_in_match", "You can only report matches you played in.")
        key, dg = match_key(match, rows), digest(rows)
        now = self.clock()
        with self._lock:
            if look is not None:
                self._set_look(reporter, look_bytes(look))
            m = self.db.execute("SELECT state FROM matches WHERE key=?", (key,)).fetchone()
            if m is None:
                self.db.execute("INSERT INTO matches (key, first_at, players) VALUES (?, ?, ?)", (key, now, len(rows)))
            elif m[0] != "open":
                old = self.db.execute("SELECT rows FROM matches WHERE key=?", (key,)).fetchone()[0]
                if m[0] == "accepted" and old and digest([Row(*r) for r in json.loads(old)]) != dg:
                    log("match_late_contradiction", level="warning", key=key, reporter=reporter)
                return "late"
            seen = self.db.execute("SELECT 1 FROM reports WHERE key=? AND steam_id=?", (key, reporter)).fetchone()
            if seen:
                return "duplicate"
            self.db.execute("INSERT INTO reports VALUES (?, ?, ?, ?, ?)",
                            (key, reporter, dg, json.dumps([[r.steam_id, r.rank, r.money, r.profit] for r in rows]), now))
            got = self.db.execute("SELECT COUNT(*) FROM reports WHERE key=?", (key,)).fetchone()[0]
            if got >= len(rows):
                self._decide(key)
            return "open" if got < len(rows) else "decided"

    def decide_due(self) -> int:
        """Decides every match whose window ran out. Returns how many were decided."""
        cutoff = self.clock() - self.window
        with self._lock:
            keys = [k for (k,) in self.db.execute("SELECT key FROM matches WHERE state='open' AND first_at<=?", (cutoff,))]
            for k in keys:
                self._decide(k)
        return len(keys)

    def _decide(self, key: str) -> None:
        reps = self.db.execute("SELECT steam_id, digest, rows FROM reports WHERE key=?", (key,)).fetchall()
        digests = {d for _, d, _ in reps}
        reporters = sorted({s for s, _, _ in reps})
        if len(digests) == 1 and len(reporters) >= 2:
            rows = [Row(*r) for r in json.loads(reps[0][2])]
            for r in rows:
                self._add_match(r)
            self.db.execute("UPDATE matches SET state='accepted', rows=? WHERE key=?", (reps[0][2], key))
            log("match_accepted", key=key, reporters=len(reporters), players=len(rows))
        elif len(digests) > 1:
            self.db.execute("UPDATE matches SET state='rejected' WHERE key=?", (key,))
            # Who sent which version, so a cheater shows up in the logs.
            log("match_contradiction", level="warning", key=key,
                versions={d[:12]: sorted(s for s, dd, _ in reps if dd == d) for d in digests})
        else:
            self.db.execute("UPDATE matches SET state='rejected' WHERE key=?", (key,))
            log("match_unconfirmed", key=key, reporters=reporters)
        self.db.execute("DELETE FROM reports WHERE key=?", (key,))

    def _add_match(self, r: Row) -> None:
        self.db.execute("INSERT OR IGNORE INTO totals (steam_id) VALUES (?)", (r.steam_id,))
        self.db.execute(
            "UPDATE totals SET best_money=MAX(best_money, ?), wins=MIN(wins+?, ?), winnings=MIN(winnings+?, ?),"
            " matches=matches+1, dirty=1 WHERE steam_id=?",
            (r.money, 1 if r.rank == 1 else 0, MAX_TOTAL, max(r.profit, 0), MAX_TOTAL, r.steam_id))

    # ------------------------------------------------------------------ looks
    def set_look(self, steam_id: str, look: list[int]) -> bool:
        """A new outfit: re-sent with the player's scores (only players already on the boards)."""
        with self._lock:
            return self._set_look(steam_id, look_bytes(look))

    def _set_look(self, steam_id: str, look: bytes) -> bool:
        cur = self.db.execute("SELECT look, matches FROM totals WHERE steam_id=?", (steam_id,)).fetchone()
        if cur is None:
            self.db.execute("INSERT INTO totals (steam_id, look) VALUES (?, ?)", (steam_id, look))
            return False
        if bytes(cur[0]) == look:
            return False
        self.db.execute("UPDATE totals SET look=?, dirty=CASE WHEN matches>0 THEN 1 ELSE dirty END WHERE steam_id=?",
                        (look, steam_id))
        return cur[1] > 0

    def totals(self, steam_id: str) -> dict[str, int]:
        row = self.db.execute("SELECT best_money, wins, winnings, matches FROM totals WHERE steam_id=?", (steam_id,)).fetchone()
        best, wins, won, matches = row if row else (0, 0, 0, 0)
        return {"best_money": best, "wins": wins, "winnings": won, "matches": matches}

    # ------------------------------------------------------------------ Steam
    async def flush(self, limit: int = 20) -> int:
        """Writes changed totals to Steam. Returns how many players were written."""
        if self.writer is None:
            return 0
        with self._lock:
            dirty = self.db.execute("SELECT steam_id, best_money, wins, winnings, look FROM totals WHERE dirty=1 LIMIT ?",
                                    (limit,)).fetchall()
        done = 0
        for sid, best, wins, won, look in dirty:
            scores = {BEST_MATCH_MONEY: best, MATCHES_WON: wins, ONLINE_WINNINGS: won}
            ok = True
            for board, score in scores.items():
                if score > 0 or board == BEST_MATCH_MONEY:
                    ok = await self.writer(sid, board, int(score), bytes(look)) and ok
            if ok:
                with self._lock:
                    self.db.execute("UPDATE totals SET dirty=0 WHERE steam_id=? AND best_money=? AND wins=? AND winnings=? AND look=?",
                                    (sid, best, wins, won, look))
                done += 1
        return done

    def prune(self, keep_seconds: float = 7 * 24 * 3600) -> None:
        """Forgets decided matches after a week (a late report of one is then simply unconfirmed)."""
        with self._lock:
            self.db.execute("DELETE FROM matches WHERE state!='open' AND first_at<?", (self.clock() - keep_seconds,))


def make_steam_writer(config: Config) -> ScoreWriter:
    """The real writer: ``SetLeaderboardScore`` with ForceUpdate (the server's totals are the truth).
    Board ids come from ``GetLeaderboardsForGame`` once."""
    board_ids: dict[str, int] = {}

    async def find_boards(client: httpx.AsyncClient) -> None:
        resp = await client.get(f"{STEAM_API}/GetLeaderboardsForGame/v2/",
                                params={"key": config.steam_web_api_key, "appid": config.steam_app_id})
        data = resp.json() if resp.status_code == 200 else {}
        for b in (data.get("response") or {}).get("leaderboards") or []:
            if isinstance(b, dict) and b.get("name") in BOARDS:
                board_ids[str(b["name"])] = int(b["id"])

    async def write(steam_id: str, board: str, score: int, details: bytes) -> bool:
        try:
            async with httpx.AsyncClient(timeout=config.steam_timeout) as client:
                if board not in board_ids:
                    await find_boards(client)
                if board not in board_ids:
                    log("leaderboard_unknown", level="error", board=board)
                    return False
                form = {"key": config.steam_web_api_key, "appid": config.steam_app_id, "leaderboardid": board_ids[board],
                        "steamid": steam_id, "score": score, "scoremethod": "ForceUpdate"}
                resp = await client.post(f"{STEAM_API}/SetLeaderboardScore/v1/", data={**form, "details": details.hex()})
                if resp.status_code != 200 and details:
                    # The look is a nice-to-have; the score must arrive.
                    resp = await client.post(f"{STEAM_API}/SetLeaderboardScore/v1/", data=form)
        except httpx.HTTPError as exc:
            # Never str(exc): it may hold the URL with the key.
            log("leaderboard_write_failed", level="error", board=board, reason=type(exc).__name__)
            return False
        except ValueError:
            log("leaderboard_write_failed", level="error", board=board, reason="bad_json")
            return False
        if resp.status_code != 200:
            log("leaderboard_write_failed", level="error", board=board, reason=f"http_{resp.status_code}")
            return False
        return True

    return write
