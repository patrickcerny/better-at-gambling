class_name LeaderboardRules
extends RefCounted
## The global leaderboards (Patrick 2026-11-16: "globale leaderboards ... Most money made in a single
## lobby. Einfach lobby übergreifend") and what may go on them. The boards live on Steam
## (`SteamLeaderboards`, created by the game itself with FindOrCreateLeaderboard); this file only
## holds the rules, so the server, the profile and the tests share them.
##
## Who decides: the match server (the lobby host's PC) builds every player's row from its own
## economy and stats and marks it `ranked` (`MatchServer.progress_rows`): an online room, at least
## two players, no developer tool used in this server's life, and every number plausible. Each
## client then only uploads its own row's numbers (Steam lets a player write only their own score)
## and checks the row once more on its side. Practice never reaches a leaderboard.

## Board API names on Steam (FindOrCreateLeaderboard creates them on first use).
const BEST_MATCH_MONEY: StringName = &"BEST_MATCH_MONEY"
const BIGGEST_WIN: StringName = &"BIGGEST_WIN"
const MATCHES_WON: StringName = &"MATCHES_WON"
const ONLINE_WINNINGS: StringName = &"ONLINE_WINNINGS"

## The boards in menu order: {id, title, hint, money (shown as $)}.
const BOARDS: Array[Dictionary] = [
	{"id": BEST_MATCH_MONEY, "title": "Most money in one match", "hint": "Your money when an online match ends. Your best match counts.", "money": true},
	{"id": BIGGEST_WIN, "title": "Biggest single win", "hint": "The most you won on one hand, spin or round in an online match.", "money": true},
	{"id": MATCHES_WON, "title": "Matches won", "hint": "Online matches you finished in 1st place.", "money": false},
	{"id": ONLINE_WINNINGS, "title": "Total winnings", "hint": "Everything you won across all your online matches (only the matches you ended in profit).", "money": true},
]

## A match's money and biggest win above this are not believed (a normal match ends at a few
## thousand $, the start is $1,000): such a row is never ranked.
const MAX_MATCH_MONEY: int = 1_000_000
## Lifetime totals never pass this (one profile can't have won more than this many matches...).
const MAX_TOTAL: int = 2_000_000_000
## Steam's sort/display enums (ELeaderboardSortMethod / ELeaderboardDisplayType).
const SORT_DESCENDING: int = 2
const DISPLAY_NUMERIC: int = 1
## ELeaderboardDataRequest.
const SCOPE_GLOBAL: int = 0
const SCOPE_AROUND_ME: int = 1
const SCOPE_FRIENDS: int = 2


static func board(id: StringName) -> Dictionary:
	for b: Dictionary in BOARDS:
		if b["id"] == id:
			return b
	return {}


static func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for b: Dictionary in BOARDS:
		out.append(b["id"])
	return out


## Whether a match server's numbers for one player are believable: money and biggest win in
## 0..MAX_MATCH_MONEY and a sane rank and player count.
static func plausible(row: Dictionary) -> bool:
	var money: int = int(row.get("money", -1))
	var big: int = int(row.get("biggest_win", 0))
	var rank: int = int(row.get("rank", 0))
	var players: int = int(row.get("players", 0))
	if money < 0 or money > MAX_MATCH_MONEY or big < 0 or big > MAX_MATCH_MONEY:
		return false
	return players >= 1 and players <= Protocol.MAX_PLAYERS and rank >= 1 and rank <= players


## What the host decides for one row: online room, 2+ players, no dev tools, plausible numbers.
static func ranked(row: Dictionary, room_mode: bool, dev_used: bool) -> bool:
	return room_mode and not dev_used and int(row.get("players", 1)) >= 2 and plausible(row)


## The scores the local player uploads after a match (board id -> score), {} when the row isn't
## ranked. `profile` has already taken the row in (`PlayerProfile.apply_match`), so the lifetime
## boards get the new totals.
static func scores_for(row: Dictionary, profile: PlayerProfile) -> Dictionary:
	var out: Dictionary = {}
	if row.is_empty() or not bool(row.get("ranked", false)) or not plausible(row):
		return out
	out[BEST_MATCH_MONEY] = int(row.get("money", 0))
	if int(row.get("biggest_win", 0)) > 0:
		out[BIGGEST_WIN] = int(row.get("biggest_win", 0))
	if profile != null:
		if profile.online_wins > 0:
			out[MATCHES_WON] = mini(profile.online_wins, MAX_TOTAL)
		var won: int = int(profile.lifetime.get(&"online_winnings", 0))
		if won > 0:
			out[ONLINE_WINNINGS] = mini(won, MAX_TOTAL)
	return out


## "$12,345" for money boards, "12,345" for counts.
static func format_score(id: StringName, score: int) -> String:
	var b: Dictionary = board(id)
	var text: String = group(score)
	return "$" + text if bool(b.get("money", false)) else text


## 1234567 -> "1,234,567".
static func group(n: int) -> String:
	var s: String = str(absi(n))
	var out: String = ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## Steam's downloaded entries as rows for the list: [{rank, steam_id, score, me}], best first.
static func entry_rows(entries: Array, my_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Variant in entries:
		if not e is Dictionary:
			continue
		var d: Dictionary = e
		var sid: int = int(d.get("steam_id", 0))
		out.append({"rank": int(d.get("global_rank", 0)), "steam_id": sid, "score": int(d.get("score", 0)), "me": sid != 0 and sid == my_id})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["rank"]) < int(b["rank"]))
	return out
