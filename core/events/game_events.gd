class_name GameEvents
extends RefCounted
## Factory + validation for typed game events: `{type: StringName, ...payload}`.
## Events are applied server-side (stats) and broadcast to clients (presentation).

## Required payload keys per event type. Types not listed only need `type`.
const SCHEMA: Dictionary = {
	&"money_changed": ["player", "amount", "reason", "balance"],
	&"bet_placed": ["player", "station", "amount"],
	&"round_started": ["station"],
	&"round_result": ["station", "player", "stake", "returned", "net"],
	&"cards_dealt": ["station"],
	&"luck_flourish": ["player", "station", "kind"],
	&"jackpot_won": ["player", "station", "amount"],
	&"jackpot_changed": ["amount"],
	&"player_shoved": ["attacker", "target"],
	&"player_knocked_down": ["target"],
	&"player_knocked_out": ["target"],
	&"chips_shaken_out": ["attacker", "target", "amount"],
	&"phase_changed": ["phase"],
	&"item_used": ["player", "item", "target", "result"],
	&"inventory_changed": ["player", "inventory"],
	&"discard_needed": ["player", "item", "seconds"],
	&"item_discarded": ["player", "item"],
	&"effect_ended": ["player", "item", "reason"],
	&"bodyguard_saved": ["player", "attacker"],
	&"banana_placed": ["peel", "owner", "pos", "seconds"],
	&"banana_slip": ["peel", "player", "owner", "result", "victim", "amount"],
	&"banana_removed": ["peel", "reason"],
	&"rps_invite": ["duel", "from", "to", "stake", "seconds"],
	&"rps_start": ["duel", "a", "b", "stake", "seconds", "replay"],
	&"rps_picked": ["duel", "player"],
	&"rps_result": ["duel", "a", "b", "pick_a", "pick_b", "winner", "amount", "replay"],
	&"rps_cancelled": ["duel", "a", "b", "reason"],
	&"shop_restocked": ["offers"],
	&"shop_bought": ["player", "item", "price"],
	&"bets_refunded": ["station", "player", "amount"],
	&"table_reset": ["station"],
	&"regroup_started": ["seconds", "positions"],
	&"rewards_started": ["rewards", "seconds"],
	&"house_comp": ["player", "amount"],
	&"match_started": ["minigames", "gamble_s", "duration_s"],
}


## Builds an event dictionary.
static func make(type: StringName, payload: Dictionary = {}) -> Dictionary:
	var ev: Dictionary = payload.duplicate()
	ev["type"] = type
	return ev


## Money moved through the Economy.
static func money_changed(player: int, amount: int, reason: StringName, balance: int, source: StringName = &"") -> Dictionary:
	return make(&"money_changed", {"player": player, "amount": amount, "reason": reason, "balance": balance, "source": source})


## A bet was accepted at a station.
static func bet_placed(player: int, station: StringName, amount: int, details: Dictionary = {}) -> Dictionary:
	return make(&"bet_placed", {"player": player, "station": station, "amount": amount, "details": details})


## A player's bet at a station was settled. `returned` is what was paid back (0 on a loss).
static func round_result(station: StringName, player: int, stake: int, returned: int, details: Dictionary = {}) -> Dictionary:
	return make(&"round_result", {"station": station, "player": player, "stake": stake, "returned": returned, "net": returned - stake, "details": details})


## Luck visibly changed an outcome (UI shows a clover or black cat).
static func luck_flourish(player: int, station: StringName, kind: StringName) -> Dictionary:
	return make(&"luck_flourish", {"player": player, "station": station, "kind": kind})


## Missing required keys for an event (empty = valid).
static func validate(ev: Dictionary) -> Array[String]:
	var missing: Array[String] = []
	if not ev.has("type"):
		missing.append("type")
		return missing
	for key: String in SCHEMA.get(ev["type"], []):
		if not ev.has(key):
			missing.append(key)
	return missing
