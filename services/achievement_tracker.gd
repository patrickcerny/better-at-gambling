class_name AchievementTracker
extends RefCounted
## The game and minigame achievements of 0.9.30 (Patrick 2026-11-15: "More achievements for next
## version: lose 4 blackjack hands in a row, hit 2 single numbers after each other, get a
## blackjack, stuff like this"). One tracker lives for one match on a client (`MatchScene`): it
## watches the server events the client gets anyway and remembers the streaks (losses in a row,
## roulette hits on back-to-back spins, jail visits). Pure rules, no Steam calls: `on_event`
## returns the API names a moment earns and the scene hands them to `SteamSvc.unlock_achievements`.
## Steam remembers what is unlocked, so returning an id twice is harmless.

## Blackjack hands lost in a row (a push or a win breaks the streak).
const BJ_LOSSES_IN_A_ROW: int = 4
## Hitting on this total and busting earns "Greedy".
const BJ_GREEDY_TOTAL: int = 20
## Cards in a winning blackjack hand for "Five Card Trick".
const BJ_FIVE_CARDS: int = 5
## Bets lost in a row, any table, for "On Tilt".
const LOSSES_IN_A_ROW: int = 10
## A single bet that loses at least this much earns "Ouch".
const BIG_LOSS: int = 1_000
## Plinko slot multiplier (before items) for "Over the Edge": the 12× and 60× of High, 13× of Medium.
const PLINKO_EDGE_MULT: float = 10.0
## Right Hi-Lo calls in a row for "Ladder Climber".
const HILO_RUNGS: int = 5
## Wheel symbols that pay 40:1 (`WheelLogic.SYMBOLS`: joker, logo).
const WHEEL_WILD_SYMBOLS: Array[int] = [5, 6]
## Hold'em hand category for "Full House" (`HoldemHand.NAMES`: 6 = Full House, up to Royal Flush).
const HOLDEM_FULL_HOUSE: int = 6
## Slots symbol index of the seven (`SlotsLogic.Sym.SEVEN`).
const SLOTS_SEVEN: int = 4
## Jail visits in one match for "Jailbird".
const JAIL_VISITS: int = 3
## Players a minigame needs for "Participation Trophy" (last of two is just losing a duel).
const LAST_PLACE_PLAYERS: int = 3

## Every API name this tracker can hand out, in Steamworks order (they follow `Achievements.DEFS`).
const IDS: Array[StringName] = [
	&"ACH_BJ_NATURAL", &"ACH_BJ_COLD_STREAK", &"ACH_BJ_GREEDY", &"ACH_BJ_FIVE_CARDS",
	&"ACH_ROULETTE_NUMBER", &"ACH_ROULETTE_PSYCHIC", &"ACH_ROULETTE_ZERO",
	&"ACH_SLOTS_SEVENS", &"ACH_PLINKO_EDGE", &"ACH_HILO_LADDER", &"ACH_WHEEL_WILD", &"ACH_HOLDEM_FULL_HOUSE",
	&"ACH_ON_TILT", &"ACH_OUCH", &"ACH_JAILBIRD", &"ACH_WET_FLOOR", &"ACH_TRIP_WAITER", &"ACH_HOT_POTATO",
	&"ACH_BACKSTABBER", &"ACH_COUNTERFEIT", &"ACH_YEET", &"ACH_LAST_PLACE",
]

## Blackjack hands lost in a row right now.
var bj_losing: int = 0
## Bets lost in a row right now (every table).
var losing: int = 0
## Times the local player went to jail this match.
var jail_visits: int = 0
## Roulette station → spins seen there (counted on `roulette_result`, which comes before the bets
## of that spin settle).
var _roulette_spin: Dictionary[StringName, int] = {}
## Roulette station → {spin, hit, prev_hit}: whether the local player hit a single number on the
## spin they last bet on there, and on the one they bet on before it.
var _roulette_me: Dictionary[StringName, Dictionary] = {}


## What one server event earns `local_id`. `game` is the game of the event's station (`&""` when
## the event has none or the station is unknown).
func on_event(ev: Dictionary, local_id: int, game: StringName = &"") -> Array[StringName]:
	var out: Array[StringName] = []
	if local_id < 0:
		return out
	match StringName(ev.get("type", &"")):
		&"round_result":
			if int(ev.get("player", -1)) == local_id:
				_on_result(ev, game, out)
		&"roulette_result":
			var sid: StringName = StringName(ev.get("station", &""))
			_roulette_spin[sid] = int(_roulette_spin.get(sid, 0)) + 1
		&"hilo_call":
			if int(ev.get("player", -1)) == local_id and bool(ev.get("won", false)) and int(ev.get("rung", 0)) >= HILO_RUNGS:
				out.append(&"ACH_HILO_LADDER")
		&"player_jailed":
			if int(ev.get("player", -1)) == local_id:
				jail_visits += 1
				if jail_visits >= JAIL_VISITS:
					out.append(&"ACH_JAILBIRD")
		&"puddle_slip":
			if int(ev.get("player", -1)) == local_id:
				out.append(&"ACH_WET_FLOOR")
		&"waiter_tripped":
			if int(ev.get("player", -1)) == local_id:
				out.append(&"ACH_TRIP_WAITER")
		&"pass_the_bomb_exploded":
			if int(ev.get("player", -1)) == local_id:
				out.append(&"ACH_HOT_POTATO")
		&"split_or_steal_reveal":
			if _backstabbed(ev, local_id):
				out.append(&"ACH_BACKSTABBER")
		&"fake_cash_caught":
			if int(ev.get("player", -1)) == local_id:
				out.append(&"ACH_COUNTERFEIT")
		&"player_thrown":
			if int(ev.get("attacker", -1)) == local_id and int(ev.get("target", -1)) != local_id:
				out.append(&"ACH_YEET")
		&"minigame_finished":
			if is_last(ev.get("ranking", []), local_id):
				out.append(&"ACH_LAST_PLACE")
	return out


## A settled bet of the local player.
func _on_result(ev: Dictionary, game: StringName, out: Array[StringName]) -> void:
	var net: int = int(ev.get("net", 0))
	var d: Dictionary = ev.get("details", {}) if ev.get("details", {}) is Dictionary else {}
	if net < 0:
		losing += 1
		if losing >= LOSSES_IN_A_ROW:
			out.append(&"ACH_ON_TILT")
		if -net >= BIG_LOSS:
			out.append(&"ACH_OUCH")
	elif net > 0:
		losing = 0
	match game:
		&"blackjack":
			_on_blackjack(net, d, out)
		&"roulette":
			_on_roulette(StringName(ev.get("station", &"")), d, out)
		&"slots":
			var line: Array = d.get("line", [])
			if line.size() == 3 and int(line[0]) == SLOTS_SEVEN and int(line[1]) == SLOTS_SEVEN and int(line[2]) == SLOTS_SEVEN:
				out.append(&"ACH_SLOTS_SEVENS")
		&"plinko":
			if float(d.get("multiplier_base", 0.0)) >= PLINKO_EDGE_MULT:
				out.append(&"ACH_PLINKO_EDGE")
		&"wheel":
			var sym: int = int(d.get("symbol", -1))
			if sym in WHEEL_WILD_SYMBOLS and sym == int(d.get("won", -2)):
				out.append(&"ACH_WHEEL_WILD")
		&"holdem":
			if net > 0 and StringName(d.get("type", &"")) == &"ante" and int(d.get("rank", -1)) >= HOLDEM_FULL_HOUSE:
				out.append(&"ACH_HOLDEM_FULL_HOUSE")


func _on_blackjack(net: int, d: Dictionary, out: Array[StringName]) -> void:
	var outcome: StringName = StringName(d.get("outcome", &""))
	if outcome == &"blackjack":
		out.append(&"ACH_BJ_NATURAL")
	if net < 0:
		bj_losing += 1
		if bj_losing >= BJ_LOSSES_IN_A_ROW:
			out.append(&"ACH_BJ_COLD_STREAK")
	else:
		bj_losing = 0
	var cards: Array[int] = []
	for c: Variant in d.get("cards", []):
		cards.append(int(c))
	if outcome == &"bust" and cards.size() >= 3:
		var before: Array[int] = cards.slice(0, cards.size() - 1)
		if HandEval.total(before) >= BJ_GREEDY_TOTAL:
			out.append(&"ACH_BJ_GREEDY")
	if net > 0 and cards.size() >= BJ_FIVE_CARDS:
		out.append(&"ACH_BJ_FIVE_CARDS")


## Roulette: a single number hit (not a Lucky Clover neighbour payout), on 0, and on the spin the
## local player bet on right before it at the same table.
func _on_roulette(sid: StringName, d: Dictionary, out: Array[StringName]) -> void:
	var spin: int = int(_roulette_spin.get(sid, 0))
	var me: Dictionary = _roulette_me.get(sid, {"spin": -1, "hit": false, "prev_hit": false})
	if int(me["spin"]) != spin:
		me["prev_hit"] = bool(me["hit"]) and int(me["spin"]) == spin - 1
		me["hit"] = false
		me["spin"] = spin
	_roulette_me[sid] = me
	var hit: bool = StringName(d.get("type", &"")) == &"straight" and d.has("number") and int(d.get("value", -1)) == int(d["number"])
	if not hit:
		return
	out.append(&"ACH_ROULETTE_NUMBER")
	if int(d["number"]) == 0:
		out.append(&"ACH_ROULETTE_ZERO")
	me["hit"] = true
	if bool(me["prev_hit"]):
		out.append(&"ACH_ROULETTE_PSYCHIC")


## Split or Steal: the local player stole while the other one split (the house seat doesn't count).
static func _backstabbed(ev: Dictionary, local_id: int) -> bool:
	var house: int = int(ev.get("house", -1))
	if local_id == house:
		return false
	if int(ev.get("a", -1)) == local_id:
		return String(ev.get("choice_a", "")) == "STEAL" and String(ev.get("choice_b", "")) == "SPLIT"
	if int(ev.get("b", -1)) == local_id:
		return String(ev.get("choice_b", "")) == "STEAL" and String(ev.get("choice_a", "")) == "SPLIT"
	return false


## A minigame's final ranking (`minigame_finished`): the local player is (one of) the last, with
## at least `LAST_PLACE_PLAYERS` players and not everyone tied.
static func is_last(ranking: Variant, local_id: int) -> bool:
	if not ranking is Array or (ranking as Array).size() < LAST_PLACE_PLAYERS:
		return false
	var rows: Array = ranking
	var worst: int = 0
	var mine: int = 0
	for i: int in rows.size():
		if not rows[i] is Dictionary:
			continue
		var rank: int = int((rows[i] as Dictionary).get("rank", i + 1))
		worst = maxi(worst, rank)
		if int((rows[i] as Dictionary).get("player", -1)) == local_id:
			mine = rank
	return mine > 1 and mine == worst
