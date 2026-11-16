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
## BIGGEST_WIN existed until 0.10.53 (Patrick 2026-11-16: "Remove biggest single win please dont
## need that"); its Steam board stays but nothing shows or fills it.
const MATCHES_WON: StringName = &"MATCHES_WON"
const ONLINE_WINNINGS: StringName = &"ONLINE_WINNINGS"

## The boards in menu order: {id, title, hint, money (shown as $)}.
const BOARDS: Array[Dictionary] = [
	{"id": BEST_MATCH_MONEY, "title": "Most money in one match", "hint": "Your money when an online match ends. Your best match counts.", "money": true},
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
	if profile != null:
		if profile.online_wins > 0:
			out[MATCHES_WON] = mini(profile.online_wins, MAX_TOTAL)
		var won: int = int(profile.lifetime.get(&"online_winnings", 0))
		if won > 0:
			out[ONLINE_WINNINGS] = mini(won, MAX_TOTAL)
	return out


## The bests this profile already holds from ranked online matches (`PlayerProfile.lifetime`),
## uploaded on start so a match whose upload was missed still reaches the board.
static func profile_scores(profile: PlayerProfile) -> Dictionary:
	var out: Dictionary = {}
	if profile == null:
		return out
	var best: int = int(profile.lifetime.get(&"best_money", 0))
	if best > 0:
		out[BEST_MATCH_MONEY] = mini(best, MAX_MATCH_MONEY)
	if profile.online_wins > 0:
		out[MATCHES_WON] = mini(profile.online_wins, MAX_TOTAL)
	var won: int = int(profile.lifetime.get(&"online_winnings", 0))
	if won > 0:
		out[ONLINE_WINNINGS] = mini(won, MAX_TOTAL)
	return out


## Each entry carries the player's look in Steam's details array (Patrick 2026-11-16: "show
## current skin in leaderboard"): [SKIN_VERSION, bean colour, one id hash per outfit slot in
## `CosmeticDef.OUTFIT_KINDS` order (0 = nothing)]. Hashes, because Steam stores int32s only.
const SKIN_VERSION: int = 1
const DETAILS_MAX: int = 16

## hash -> item id, built once from the shop.
static var _by_hash: Dictionary = {}


## The local player's look as details for an upload.
static func skin_details(color: int, outfit: PackedStringArray) -> PackedInt32Array:
	var out := PackedInt32Array([SKIN_VERSION, color if Cosmetics.is_valid_color(color) else 0])
	var clean: PackedStringArray = Cosmetics.sanitize_outfit(outfit)
	for id: String in clean:
		out.append(id_hash(id) if id != "" else 0)
	return out


## Steam's details back into {color, outfit (wire list)}; {} when they carry no look.
static func skin_from_details(details: Variant) -> Dictionary:
	var d: Array = Array(details) if details is PackedInt32Array or details is Array else []
	if d.size() < 2 or int(d[0]) != SKIN_VERSION:
		return {}
	if _by_hash.is_empty():
		for item: CosmeticDef in CosmeticShop.default().items:
			_by_hash[id_hash(String(item.id))] = String(item.id)
	var outfit := PackedStringArray()
	for i: int in CosmeticDef.OUTFIT_KINDS.size():
		var h: int = int(d[2 + i]) if 2 + i < d.size() else 0
		outfit.append(str(_by_hash.get(h, "")) if h != 0 else "")
	var color: int = int(d[1])
	return {"color": color if Cosmetics.is_valid_color(color) else 0, "outfit": Cosmetics.sanitize_outfit(outfit)}


## A stable non-zero int32 for an item id.
static func id_hash(id: String) -> int:
	var h: int = id.hash() & 0x7fffffff
	return h if h != 0 else 1


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


## Steam's downloaded entries as rows for the list: [{rank, steam_id, score, me, skin}], best first
## (`skin`: `skin_from_details`, {} when the player never uploaded a look).
static func entry_rows(entries: Array, my_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Variant in entries:
		if not e is Dictionary:
			continue
		var d: Dictionary = e
		var sid: int = int(d.get("steam_id", 0))
		out.append({"rank": int(d.get("global_rank", 0)), "steam_id": sid, "score": int(d.get("score", 0)), "me": sid != 0 and sid == my_id,
			"skin": skin_from_details(d.get("details", []))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["rank"]) < int(b["rank"]))
	return out


## FRIENDS counts among the friends (Patrick 2026-11-16: "warum ist hier 2 und 3 und keine 1"):
## `place` 1, 2, 3 ... in list order, the global rank stays in `rank`. Other scopes: place = rank.
static func with_places(rows: Array[Dictionary], scope: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in rows.size():
		var r: Dictionary = rows[i].duplicate()
		r["place"] = i + 1 if scope == SCOPE_FRIENDS else int(r.get("rank", i + 1))
		out.append(r)
	return out
