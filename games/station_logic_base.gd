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
## Part of the last stake `_take_stake` took that Fake Cash paid for (never refunded).
var last_covered: int = 0


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


## Resolves everything open right now (end of the match).
func auto_resolve() -> void:
	pass


## A minigame starts (Patrick's note #9): every open bet goes back to its owner, no loss and no
## win, and the table resets. Only the part the player paid comes back (never the Fake Cash part).
func refund_all() -> void:
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


## Dog Collar: part of the wearer's winnings goes to whoever collared them.
func _collar_cut(player: int, profit: int) -> void:
	for m: Modifier in modifiers.get_mods(player):
		if not m.flags.get(&"collar", false) or m.source_player < 0 or m.source_player == player:
			continue
		var cut: int = mini(int(floor(profit * COLLAR_SHARE)), economy.balance(player))
		if cut <= 0:
			continue
		economy.apply(player, -cut, &"item_collar", station_id)
		economy.apply(m.source_player, cut, &"item_collar", station_id)
		events.append(GameEvents.make(&"collar_cut", {"player": player, "owner": m.source_player, "station": station_id, "amount": cut}))


## True when `player` sits here alone with an Energy Drink: table timers run twice as fast.
func _fast_for(players_here: Array) -> bool:
	return players_here.size() == 1 and modifiers.has_flag(int(players_here[0]), &"fast_tables")


## Integer limit scaled by the limits multiplier.
func scaled(amount: int) -> int:
	return int(floor(amount * limits_multiplier))


## Builds a failed intent result.
static func fail(error: StringName) -> Dictionary:
	return {"ok": false, "error": error}


## Most of a bet Fake Cash pays for (× limits), and the chance the bouncer spots it.
const FAKE_CASH_CAP: int = 200
const FAKE_CASH_CAUGHT: float = 0.5
## Share of a Dog Collar wearer's winnings that goes to whoever put it on them.
const COLLAR_SHARE: float = 0.15


## Takes a stake from the player; false if they can't afford it. Fake Cash pays (part of) the
## next stake; whether the bouncer noticed is in the `fake_cash_used` event (the MatchServer fines
## and throws out a caught player).
func _take_stake(player: int, amount: int) -> bool:
	last_covered = 0
	if modifiers.has_flag(player, &"fake_cash"):
		var covered: int = mini(amount, scaled(FAKE_CASH_CAP))
		if economy.balance(player) < amount - covered:
			return false
		modifiers.consume_flag(player, &"fake_cash")
		economy.apply(player, covered, &"item_fake_cash", station_id)
		last_covered = covered
		events.append(GameEvents.make(&"fake_cash_used", {"player": player, "station": station_id, "amount": covered, "caught": rng.chance(FAKE_CASH_CAUGHT)}))
	return economy.apply(player, -amount, StringName("bet_" + game_id), station_id)


## Gives back what a player paid for an unsettled stake (`stake` minus the Fake Cash `covered`
## part) with reason `bet_refunded`. Adds it to `totals` (player → refunded so far).
func _refund(player: int, stake: int, covered: int, totals: Dictionary) -> void:
	var back: int = maxi(stake - covered, 0)
	if back > 0:
		economy.apply(player, back, &"bet_refunded", station_id)
	totals[player] = int(totals.get(player, 0)) + back


## One `bets_refunded {station, player, amount}` per player in `totals` (player → amount), then
## `table_reset {station}` so clients clear chips and cards.
func _emit_refunds(totals: Dictionary) -> void:
	for p: Variant in totals:
		events.append(GameEvents.make(&"bets_refunded", {"station": station_id, "player": int(p), "amount": int(totals[p])}))
	events.append(GameEvents.make(&"table_reset", {"station": station_id}))


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
	if returned > stake:
		_collar_cut(player, returned - stake)
	return returned
