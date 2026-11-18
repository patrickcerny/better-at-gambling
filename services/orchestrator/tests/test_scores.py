"""Server-checked leaderboards: a match counts only when 2+ Steam accounts report the same result."""

from __future__ import annotations

import asyncio
from typing import Any

import pytest

from orchestrator.scores import BEST_MATCH_MONEY, MATCHES_WON, ONLINE_WINNINGS, look_bytes

from .conftest import Harness

A, B, C = "76561190000000001", "76561190000000002", "76561190000000003"
# Fake Steam tickets: the hex ticket "a1" belongs to A, and so on.
TICKETS = {A: "a1", B: "b2", C: "c3"}


def rows(money_a: int = 3200, money_b: int = 400, players: tuple[str, ...] = (A, B)) -> list[dict[str, Any]]:
    money = {A: money_a, B: money_b, C: 1000}
    ordered = sorted(players, key=lambda s: -money[s])
    return [{"steam_id": s, "rank": ordered.index(s) + 1, "money": money[s], "profit": money[s] - 1000,
             "players": len(players), "ranked": True} for s in players]


@pytest.fixture
def sh(make_harness) -> tuple[Harness, list[tuple[str, str, int, bytes]]]:
    by_ticket = {t: s for s, t in TICKETS.items()}
    written: list[tuple[str, str, int, bytes]] = []

    async def verifier(ticket: str) -> dict[str, Any]:
        sid = by_ticket.get(ticket.lower())
        if sid is None:
            return {"response": {"error": {"errorcode": 101, "errordesc": "Invalid ticket"}}}
        return {"response": {"params": {"result": "OK", "steamid": sid, "ownersteamid": sid}}}

    async def writer(steam_id: str, board: str, score: int, details: bytes) -> bool:
        written.append((steam_id, board, score, details))
        return True

    # Rooms stay on dev auth (like the VPS today); scores always check Steam tickets.
    h = make_harness(steam_web_api_key="KEY", steam_app_id="5623410", steam_verifier=verifier,
                     score_writer=writer, score_window=120.0)
    return h, written


def report(h: Harness, who: str, body_rows: list[dict[str, Any]], match: str = "77-1", **extra: Any):
    return h.client.post("/v1/matches/report", json={"ticket": TICKETS[who], "match": match, "rows": body_rows, **extra})


def scores(written: list[tuple[str, str, int, bytes]], who: str) -> dict[str, int]:
    return {board: score for sid, board, score, _ in written if sid == who}


def test_two_matching_reports_count(sh) -> None:
    h, written = sh
    assert report(h, A, rows()).json()["state"] == "open"
    assert report(h, B, rows()).json()["state"] == "decided", "every player reported: no need to wait"
    assert h.client.app.state.scores.totals(A) == {"best_money": 3200, "wins": 1, "winnings": 2200, "matches": 1}
    assert h.client.app.state.scores.totals(B) == {"best_money": 400, "wins": 0, "winnings": 0, "matches": 1}
    assert scores(written, A) == {BEST_MATCH_MONEY: 3200, MATCHES_WON: 1, ONLINE_WINNINGS: 2200}
    assert scores(written, B) == {BEST_MATCH_MONEY: 400}, "zero wins / winnings stay off those boards"


def test_a_contradiction_voids_the_match_for_everyone(sh) -> None:
    h, written = sh
    report(h, A, rows(money_a=900_000))  # A's modified game claims a huge win
    report(h, B, rows())
    keeper = h.client.app.state.scores
    assert keeper.totals(A)["matches"] == 0 and keeper.totals(B)["matches"] == 0
    assert written == []
    assert "match_contradiction" in h.logs.getvalue()


def test_one_contradiction_beats_two_matching_reports(sh) -> None:
    h, written = sh
    three = rows(players=(A, B, C))
    report(h, A, three)
    report(h, B, three)
    liar = [dict(r, money=999_999) if r["steam_id"] == C else r for r in three]
    report(h, C, liar)
    assert h.client.app.state.scores.totals(A)["matches"] == 0, "any contradiction: nobody's match counts"
    assert written == []


def test_a_single_report_never_counts(sh) -> None:
    h, written = sh
    report(h, A, rows())
    keeper = h.client.app.state.scores
    h.clock.advance(119)
    assert keeper.decide_due() == 0, "still waiting for B"
    h.clock.advance(2)
    assert keeper.decide_due() == 1
    assert keeper.totals(A)["matches"] == 0 and written == []
    assert "match_unconfirmed" in h.logs.getvalue()


def test_two_of_three_after_the_window_count(sh) -> None:
    h, written = sh
    three = rows(players=(A, B, C))
    report(h, A, three)
    report(h, C, three)  # B left early and never reports
    h.clock.advance(121)
    keeper = h.client.app.state.scores
    keeper.decide_due()
    asyncio.run(keeper.flush())
    assert keeper.totals(B)["matches"] == 1, "B's result counts too: two others vouched for it"
    assert scores(written, A)[MATCHES_WON] == 1


def test_a_late_report_changes_nothing(sh) -> None:
    h, _ = sh
    report(h, A, rows())
    report(h, B, rows())
    assert report(h, A, rows()).json()["state"] == "late"
    assert h.client.app.state.scores.totals(A)["matches"] == 1, "no double counting"


def test_the_same_account_twice_is_not_two_witnesses(sh) -> None:
    h, written = sh
    report(h, A, rows())
    assert report(h, A, rows()).json()["state"] == "duplicate"
    h.clock.advance(121)
    h.client.app.state.scores.decide_due()
    assert h.client.app.state.scores.totals(A)["matches"] == 0 and written == []


def test_a_stranger_cannot_report_or_void_someone_elses_match(sh) -> None:
    h, _ = sh
    r = report(h, C, rows())  # C wasn't in A and B's match
    assert r.status_code == 422 and r.json()["error"] == "not_in_match"
    report(h, A, rows())
    report(h, B, rows())
    assert h.client.app.state.scores.totals(A)["matches"] == 1


def test_bad_tickets_and_bad_rows_are_refused(sh) -> None:
    h, _ = sh
    r = h.client.post("/v1/matches/report", json={"ticket": "ff", "match": "1-1", "rows": rows()})
    assert r.status_code == 401
    cases = [
        rows()[:1],  # alone: never ranked
        [dict(r, ranked=False) for r in rows()],
        [dict(r, money=2_000_000) for r in rows()],
        [dict(r, steam_id=A) for r in rows()],  # the same player twice
        [dict(r, players=5) for r in rows()],
        [dict(r, rank=3) for r in rows()],
        [dict(r, steam_id="steam:1") for r in rows()],
    ]
    for body_rows in cases:
        r = report(h, A, body_rows)
        assert r.status_code in (400, 422), body_rows
    assert h.client.app.state.scores.totals(A)["matches"] == 0


def test_totals_add_up_over_matches(sh) -> None:
    h, written = sh
    report(h, A, rows(), match="1-1")
    report(h, B, rows(), match="1-1")
    report(h, A, rows(money_a=1500, money_b=2500), match="1-2")
    report(h, B, rows(money_a=1500, money_b=2500), match="1-2")
    assert h.client.app.state.scores.totals(A) == {"best_money": 3200, "wins": 1, "winnings": 2700, "matches": 2}
    assert scores(written, A) == {BEST_MATCH_MONEY: 3200, MATCHES_WON: 1, ONLINE_WINNINGS: 2700}


def test_the_look_goes_up_with_the_scores(sh) -> None:
    h, written = sh
    report(h, A, rows(), look=[1, 5, 123, 0])
    report(h, B, rows())
    assert {d for sid, _, _, d in written if sid == A} == {look_bytes([1, 5, 123, 0])}
    written.clear()
    r = h.client.post("/v1/leaderboards/look", json={"ticket": TICKETS[A], "look": [1, 6, 0, 0]})
    assert r.json()["changed"] is True
    asyncio.run(h.client.app.state.scores.flush())
    assert {d for sid, _, _, d in written} == {look_bytes([1, 6, 0, 0])}, "a new outfit shows on the boards"
    # Someone without a counted match changes nothing on Steam.
    assert h.client.post("/v1/leaderboards/look", json={"ticket": TICKETS[C], "look": [1, 2]}).json()["changed"] is False


def test_a_failed_steam_write_is_retried(make_harness) -> None:
    calls: list[str] = []
    fail = {"on": True}

    async def verifier(ticket: str) -> dict[str, Any]:
        sid = {v: k for k, v in TICKETS.items()}[ticket]
        return {"response": {"params": {"result": "OK", "steamid": sid}}}

    async def writer(steam_id: str, board: str, score: int, details: bytes) -> bool:
        calls.append(steam_id)
        return not fail["on"]

    h = make_harness(steam_web_api_key="KEY", steam_app_id="1", steam_verifier=verifier, score_writer=writer)
    report(h, A, rows())
    report(h, B, rows())
    assert calls, "tried right away"
    fail["on"] = False
    calls.clear()
    assert asyncio.run(h.client.app.state.scores.flush()) == 2
    assert asyncio.run(h.client.app.state.scores.flush()) == 0, "written once, then clean"


def test_without_the_publisher_key_there_are_no_server_leaderboards(h: Harness) -> None:
    r = h.client.post("/v1/matches/report", json={"ticket": "a1", "match": "1-1", "rows": rows()})
    assert r.status_code == 503 and r.json()["error"] == "scores_unavailable"


def test_reports_survive_a_restart(make_harness, tmp_path) -> None:
    db = str(tmp_path / "scores.db")

    async def verifier(ticket: str) -> dict[str, Any]:
        sid = {v: k for k, v in TICKETS.items()}[ticket]
        return {"response": {"params": {"result": "OK", "steamid": sid}}}

    async def writer(*_: Any) -> bool:
        return True

    h1 = make_harness(steam_web_api_key="KEY", steam_app_id="1", steam_verifier=verifier, score_writer=writer, scores_db=db)
    report(h1, A, rows())
    h2 = make_harness(steam_web_api_key="KEY", steam_app_id="1", steam_verifier=verifier, score_writer=writer, scores_db=db)
    report(h2, B, rows())
    assert h2.client.app.state.scores.totals(A)["matches"] == 1, "the VPS updating mid-match loses nothing"
