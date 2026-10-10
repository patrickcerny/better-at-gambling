"""Server browser: GET /v1/rooms?public=1 lists running rooms whose leader switched PUBLIC on."""

from __future__ import annotations

from .conftest import BUILD, Harness


def _list(h: Harness, **params):
    return h.client.get("/v1/rooms", params={"public": 1, **params})


def test_only_public_running_rooms_are_listed(h: Harness) -> None:
    a = h.create("alice").json()
    b = h.create("bob").json()
    h.create("carol")  # still starting: never heartbeated, not listed
    assert _list(h).json() == {"rooms": [], "max_players": 8}
    h.heartbeat(a["room_id"], players=2, public=True, name="alice's party", mode="casino")
    h.heartbeat(b["room_id"], players=1, public=False, name="bob's party")
    rows = _list(h).json()["rooms"]
    assert rows == [{
        "room_id": a["room_id"], "room_code": a["room_code"], "name": "alice's party", "players": 2,
        "max_players": 8, "phase": "lobby", "mode": "casino", "joinable": True,
    }]
    assert "room_secret" not in _list(h).text and h.secret(a["room_id"]) not in _list(h).text
    # Switching PUBLIC off removes it again.
    h.heartbeat(a["room_id"], players=2, public=False)
    assert _list(h).json()["rooms"] == []


def test_listing_shows_phase_mode_and_joinability(make_harness) -> None:
    h: Harness = make_harness(max_players=4)
    lobby = h.create("a").json()
    match = h.create("b").json()
    results = h.create("c").json()
    full = h.create("d").json()
    h.heartbeat(lobby["room_id"], players=1, public=True, name="A's party", mode="minigames")
    h.heartbeat(match["room_id"], phase="match", players=2, public=True, name="B's party")
    h.heartbeat(results["room_id"], phase="results", players=2, public=True, name="C's party")
    h.heartbeat(full["room_id"], players=4, public=True, name="D's party")
    rows = {r["name"]: r for r in _list(h).json()["rooms"]}
    assert rows["A's party"]["mode"] == "minigames" and rows["A's party"]["joinable"]
    assert rows["B's party"]["phase"] == "match" and rows["B's party"]["joinable"], "late join into a running match"
    assert rows["C's party"]["phase"] == "results" and not rows["C's party"]["joinable"]
    assert not rows["D's party"]["joinable"], "full"
    names = [r["name"] for r in _list(h).json()["rooms"]]
    assert names[:2] == ["B's party", "A's party"], "joinable first, fuller first"
    # Joining a listed running party works like joining by code.
    r = h.join("eve", room_id=match["room_id"])
    assert r.status_code == 200 and r.json()["room_code"] == match["room_code"]


def test_names_are_cleaned_and_closing_rooms_drop_out(h: Harness) -> None:
    room = h.create().json()
    rid = room["room_id"]
    h.heartbeat(rid, public=True, name="  Bad\nName\x00" + "x" * 80)
    row = _list(h).json()["rooms"][0]
    assert row["name"] == ("BadName" + "x" * 80)[:40]
    h.client.post("/v1/internal/closing", json={"room_id": rid, "room_secret": h.secret(rid), "reason": "empty"})
    assert _list(h).json()["rooms"] == []


def test_listing_requires_public_and_the_current_build(h: Harness) -> None:
    r = h.client.get("/v1/rooms")
    assert r.status_code == 400 and r.json()["error"] == "bad_request"
    r = _list(h, build="old-build")
    assert r.status_code == 426 and r.json()["error"] == "version_mismatch"
    assert _list(h, build=BUILD).status_code == 200


def test_listing_is_rate_limited_per_ip(make_harness) -> None:
    h: Harness = make_harness(rate_limit_per_min=3)
    for _ in range(3):
        assert _list(h).status_code == 200
    r = _list(h)
    assert r.status_code == 429 and r.json()["error"] == "rate_limited"


def test_bad_heartbeat_mode_is_rejected(h: Harness) -> None:
    room = h.create().json()
    r = h.heartbeat(room["room_id"], public=True, mode="poker")
    assert r.status_code == 400
