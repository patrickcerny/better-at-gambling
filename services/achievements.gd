class_name Achievements
extends RefCounted
## Steam achievements (Patrick 2026-11-14: "Steam Errungenschaften draften und hinzufügen"). Pure
## rules, no Steam calls: the match scene, the profile and the cosmetics shop ask these functions
## which achievements a moment earns and hand the ids to `SteamSvc.unlock_achievements` (which
## does nothing without Steam, so tests, Practice without Steam and the dedicated server are fine).
## Steam remembers what is unlocked; unlocking twice is harmless. The API names in `DEFS` must
## match the ones set up in Steamworks (App 5623410 → Stats & Achievements), see
## docs/STEAM_ACHIEVEMENTS.md for the names, texts and icons.
##
## Wins only count online against at least one other player (Practice is solo, so it would be a
## free win). Lifetime ones (`from_profile`) are checked again whenever Steam starts, so progress
## made before an achievement existed (or offline) unlocks it on the next start.

## Single table win ($) for BIG_WIN, and the money to finish a match with for HIGH_ROLLER
## (everyone starts with $1,000).
const BIG_WIN_AMOUNT: int = 2_500
const HIGH_ROLLER_MONEY: int = 5_000

## API name → [English name, English description]. Order = the order in Steamworks.
const DEFS: Dictionary[StringName, Array] = {
	&"ACH_FIRST_MATCH": ["Doors Open", "Finish your first match."],
	&"ACH_FIRST_WIN": ["Beginner's Luck", "Win an online match."],
	&"ACH_WINS_10": ["House Favourite", "Win 10 online matches."],
	&"ACH_MATCHES_50": ["Regular", "Finish 50 matches."],
	&"ACH_LEVEL_10": ["Rising Star", "Reach level 10."],
	&"ACH_LEVEL_50": ["Living Legend", "Reach level 50."],
	&"ACH_BIG_WIN": ["Big Win", "Win $2,500 or more in a single bet."],
	&"ACH_HIGH_ROLLER": ["Better at Gambling", "Finish an online match with $5,000 or more."],
	&"ACH_BROKE": ["Rock Bottom", "Finish an online match with $0."],
	&"ACH_JACKPOT": ["Jackpot!", "Win the jackpot."],
	&"ACH_MINIGAME_WIN": ["Party Animal", "Win a minigame."],
	&"ACH_MINIGAME_SWEEP": ["Minigame Master", "Win 3 minigames in one match."],
	&"ACH_KNOCKOUT": ["Lights Out", "Knock out another player."],
	&"ACH_THROWN_OUT": ["Caught Red-Handed", "Get thrown out by a guard."],
	&"ACH_BANANA": ["Slapstick", "Make someone slip on your banana peel."],
	&"ACH_ROULETTE_SURVIVOR": ["Nerves of Steel", "Pull the trigger in Russian Roulette and survive."],
	&"ACH_DUEL_WIN": ["Rock Solid", "Win a Rock Paper Scissors duel."],
	&"ACH_HOUSE_COMP": ["On the House", "Get a comp from the house."],
	&"ACH_SHOPPING": ["Dressed to Impress", "Buy something in the cosmetics shop."],
}


## A finished match's progress row (`Progression.breakdown` + minigames_won, money, players):
## a win that counts for the win achievements.
static func counts_as_online_win(row: Dictionary) -> bool:
	return int(row.get("rank", 0)) == 1 and not bool(row.get("practice", false)) and int(row.get("players", 1)) >= 2


## What the local player's row of `match_ended` earns (the lifetime ones come from `from_profile`).
static func from_match(row: Dictionary) -> Array[StringName]:
	var out: Array[StringName] = []
	if row.is_empty():
		return out
	out.append(&"ACH_FIRST_MATCH")
	if counts_as_online_win(row):
		out.append(&"ACH_FIRST_WIN")
	var minigames: int = int(row.get("minigames_won", 0))
	if minigames >= 1:
		out.append(&"ACH_MINIGAME_WIN")
	if minigames >= 3:
		out.append(&"ACH_MINIGAME_SWEEP")
	if int(row.get("biggest_win", 0)) >= BIG_WIN_AMOUNT:
		out.append(&"ACH_BIG_WIN")
	var online: bool = not bool(row.get("practice", false)) and int(row.get("players", 1)) >= 2
	if online and row.has("money"):
		var money: int = int(row["money"])
		if money >= HIGH_ROLLER_MONEY:
			out.append(&"ACH_HIGH_ROLLER")
		if money <= 0:
			out.append(&"ACH_BROKE")
	return out


## Lifetime achievements from the local profile (matches, online wins, level, biggest win, shop).
static func from_profile(p: PlayerProfile) -> Array[StringName]:
	var out: Array[StringName] = []
	if p == null:
		return out
	if p.matches >= 1:
		out.append(&"ACH_FIRST_MATCH")
	if p.matches >= 50:
		out.append(&"ACH_MATCHES_50")
	if p.online_wins >= 1:
		out.append(&"ACH_FIRST_WIN")
	if p.online_wins >= 10:
		out.append(&"ACH_WINS_10")
	if p.level >= 10:
		out.append(&"ACH_LEVEL_10")
	if p.level >= 50:
		out.append(&"ACH_LEVEL_50")
	if p.biggest_win >= BIG_WIN_AMOUNT:
		out.append(&"ACH_BIG_WIN")
	if not p.owned.is_empty():
		out.append(&"ACH_SHOPPING")
	return out


## What one server event earns the local player (`local_id`) during a match.
static func from_event(ev: Dictionary, local_id: int) -> Array[StringName]:
	var out: Array[StringName] = []
	if local_id < 0:
		return out
	match StringName(ev.get("type", &"")):
		&"jackpot_won":
			if int(ev.get("player", -1)) == local_id:
				out.append(&"ACH_JACKPOT")
		&"player_knocked_out":
			if int(ev.get("attacker", -1)) == local_id and int(ev.get("target", -1)) != local_id:
				out.append(&"ACH_KNOCKOUT")
		&"player_thrown_out":
			if int(ev.get("target", -1)) == local_id:
				out.append(&"ACH_THROWN_OUT")
		&"banana_slip":
			if int(ev.get("owner", -1)) == local_id and int(ev.get("victim", -1)) != local_id and StringName(ev.get("result", &"")) != &"blocked":
				out.append(&"ACH_BANANA")
		&"item_used":
			if StringName(ev.get("item", &"")) == &"russian_roulette" and int(ev.get("player", -1)) == local_id and not bool(ev.get("bang", false)):
				out.append(&"ACH_ROULETTE_SURVIVOR")
		&"rps_result":
			if not bool(ev.get("replay", false)) and int(ev.get("winner", -1)) == local_id:
				out.append(&"ACH_DUEL_WIN")
		&"house_comp":
			if int(ev.get("player", -1)) == local_id:
				out.append(&"ACH_HOUSE_COMP")
	return out
