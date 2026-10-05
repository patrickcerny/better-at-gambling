class_name StationLogicBase
extends RefCounted
## Interface every casino game's pure logic implements (§2.5). Runs only on the server.
##
## Money flow: the stake is taken when a bet is accepted (`_take_stake`), and `_settle` pays back
## the base return times any multipliers. Multipliers (items, Hot Table, Last Call) apply to the
## winnings only and are rounded down once.

## Result of an intent: `{ok: bool, error: StringName}`.
const OK_RESULT: Dictionary = {"ok": true, "error": &""}

var game_id: StringName
var station_id: StringName
var balance: BalanceConfig
var economy: Economy
var modifiers: ModifierStack
var rng: SeededRng
var luck: LuckRng
## Shared progressive jackpot (slots and Plinko feed it), may be null.
var jackpot: ProgressiveJackpot
## Table-limit multiplier for the current segment.
var limits_multiplier: float = 1.0
## Global winnings multiplier (Last Call), set by the match server.
var global_multiplier: float = 1.0
## Hot Table multiplier for this station (1.0 when not hot).
var hot_multiplier: float = 1.0
## Outgoing events since last drain.
var events: Array[Dictionary] = []


## Wires dependencies. Call once after construction.
func setup(p_station_id: StringName, p_balance: BalanceConfig, p_economy: Economy, p_modifiers: ModifierStack, p_rng: SeededRng, p_jackpot: ProgressiveJackpot = null) -> void:
	station_id = p_station_id
	balance = p_balance
	economy = p_economy
	modifiers = p_modifiers
	rng = p_rng
	luck = LuckRng.new(rng, balance.luck_reroll_per_point, balance.luck_clamp)
	jackpot = p_jackpot
	_on_setup()


## Hook for subclasses after `setup`.
func _on_setup() -> void:
	pass


## True if the player may join (seat free etc.).
func can_join(_player: int) -> bool:
	return false


## Seats / places the player. Returns an intent result.
func join(_player: int) -> Dictionary:
	return fail(&"not_implemented")


## Removes the player; open bets stay in and resolve by the game's auto rule.
func leave(_player: int) -> void:
	pass


## Places a bet; shape of `bet` is game-specific.
func place_bet(_player: int, _bet: Dictionary) -> Dictionary:
	return fail(&"not_implemented")


## A game action (hit, stand, spin, stop, …).
func player_action(_player: int, _action: StringName, _params: Dictionary = {}) -> Dictionary:
	return fail(&"not_implemented")


## Advances timers by `delta` seconds.
func tick(_delta: float) -> void:
	pass


## Seconds a bet placed now needs until it settles; bets that would outlast the casino closing
## are refused ("Table closing!").
func round_seconds() -> float:
	return 0.0


## True while the player has money in play here (unsettled bet).
func has_stake(_player: int) -> bool:
	return false


## Resolves everything open right now (phase end).
func auto_resolve() -> void:
	pass


## State everyone may see.
func get_public_state() -> Dictionary:
	return {}


## State only `player` may see (e.g. peeked hole card).
func get_private_state(_player: int) -> Dictionary:
	return {}


## Collects and clears events.
func drain_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = events
	events = []
	return out


## Integer limit scaled by the limits multiplier.
func scaled(amount: int) -> int:
	return int(floor(amount * limits_multiplier))


## Builds a failed intent result.
static func fail(error: StringName) -> Dictionary:
	return {"ok": false, "error": error}


## Takes a stake from the player; false if they can't afford it.
func _take_stake(player: int, amount: int) -> bool:
	return economy.apply(player, -amount, StringName("bet_" + game_id), station_id)


## Pays out a settled bet. `base_return` is what the game pays before multipliers (0 = loss,
## == stake = push). Returns the amount actually returned and emits `round_result`.
func _settle(player: int, stake: int, base_return: int, details: Dictionary = {}) -> int:
	var returned: int = base_return
	if base_return > stake:
		var mult: float = modifiers.get_payout_multiplier(player, game_id) * hot_multiplier * global_multiplier
		returned = stake + int(floor((base_return - stake) * mult + 0.000001))
		modifiers.consume_on_win(player, game_id)
		if mult != 1.0:
			details["multiplier"] = mult
	elif base_return == 0 and stake > 0 and modifiers.consume_on_loss(player, game_id):
		returned = stake
		details["refunded"] = true
	if returned > 0:
		economy.apply(player, returned, StringName("win_" + game_id) if returned > stake else StringName("return_" + game_id), station_id)
	events.append(GameEvents.round_result(station_id, player, stake, returned, details))
	return returned
