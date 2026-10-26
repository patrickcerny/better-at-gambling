class_name Progression
extends RefCounted
## The XP and Coins a finished match is worth (docs/GDD.md "Progression"). The server builds one
## row per player from match data it already has (`MatchServer.progress_rows`) and sends them in
## `match_ended` ("progress"), so every client shows the same numbers; each client then adds its
## own row to its local profile (`PlayerProfile.apply_match`). Clients never send XP.

## A row never claims more than this (a sanity cap the profile applies too).
const MAX_MATCH_XP: int = 2000


## The breakdown for one player: {"xp", "coins", "parts": [{"id", "label", "xp"}], "rank",
## "biggest_win", "practice"}. `rank` is the final placement (1 = first), `minigames_won` the
## minigames finished first, `profit` the final $ minus the starting $, `hands` the table rounds
## played; Practice earns at `cfg.practice_rate`.
static func breakdown(cfg: ProgressionConfig, rank: int, minigames_won: int, profit: int, hands: int, practice: bool = false, biggest_win: int = 0) -> Dictionary:
	var parts: Array[Dictionary] = []
	parts.append(_part(&"match", "Match played", cfg.xp_match))
	if not cfg.xp_by_rank.is_empty():
		var i: int = clampi(rank - 1, 0, cfg.xp_by_rank.size() - 1)
		parts.append(_part(&"placement", ordinal(maxi(rank, 1)) + " place", cfg.xp_by_rank[i]))
	if minigames_won > 0:
		parts.append(_part(&"minigames", "Minigames won x%d" % minigames_won, cfg.xp_per_minigame_win * minigames_won))
	if profit > 0 and cfg.money_per_xp > 0:
		@warning_ignore("integer_division")
		parts.append(_part(&"money", "Money won", mini(profit / cfg.money_per_xp, cfg.xp_money_cap)))
	if hands > 0:
		parts.append(_part(&"hands", "Hands played x%d" % hands, mini(hands * cfg.xp_per_hand, cfg.xp_hands_cap)))
	var xp: int = 0
	for p: Dictionary in parts:
		if practice:
			p["xp"] = int(floor(int(p["xp"]) * cfg.practice_rate))
		xp += int(p["xp"])
	xp = clampi(xp, 0, MAX_MATCH_XP)
	return {"xp": xp, "coins": coins_for_xp(cfg, xp), "parts": parts, "rank": rank, "biggest_win": maxi(biggest_win, 0), "practice": practice}


## Coins earned with `xp` (before any level-up bonus).
static func coins_for_xp(cfg: ProgressionConfig, xp: int) -> int:
	return int(floor(maxi(xp, 0) * cfg.coins_per_xp))


static func _part(id: StringName, label: String, xp: int) -> Dictionary:
	return {"id": id, "label": label, "xp": maxi(xp, 0)}


## "1st", "2nd", "3rd", "4th", "11th", "22nd".
static func ordinal(n: int) -> String:
	var suffix: String = "th"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1:
				suffix = "st"
			2:
				suffix = "nd"
			3:
				suffix = "rd"
	return "%d%s" % [n, suffix]
