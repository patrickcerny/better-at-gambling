class_name Economy
extends RefCounted
## The only writer of money (§2.6). Integer dollars, never negative. Every change is recorded in
## the ledger with a reason and emitted as a `money_changed` event.

## Emitted for every applied change (also appended to `pending_events`).
signal money_changed(event: Dictionary)

var ledger: MoneyLedger = MoneyLedger.new()
## When false, changes are not logged or emitted (Monte-Carlo sims only; never in a match).
var record_history: bool = true
## Events not yet collected by the match server.
var pending_events: Array[Dictionary] = []

var _balances: Dictionary[int, int] = {}


## Registers a player with a starting balance (recorded as reason `start`).
func add_player(player: int, start_money: int) -> void:
	_balances[player] = 0
	apply(player, start_money, &"start")


## Forgets a lobby participant before the match starts (a player removed from the lobby). The start money
## goes back with reason `removed` so the ledger still sums to the balances.
func remove_player(player: int) -> void:
	if not _balances.has(player):
		return
	apply(player, -_balances[player], &"removed")
	_balances.erase(player)


## True if the player is known.
func has_player(player: int) -> bool:
	return _balances.has(player)


## Current balance (0 for unknown players).
func balance(player: int) -> int:
	return _balances.get(player, 0)


## True if the player can pay `amount`.
func can_afford(player: int, amount: int) -> bool:
	return _balances.has(player) and amount >= 0 and _balances[player] >= amount


## Applies a change. Fails (returns false, nothing changes) if the player is unknown, the reason is
## empty, or the change would make the balance negative.
func apply(player: int, amount: int, reason: StringName, source: StringName = &"") -> bool:
	if not _balances.has(player) or reason == &"":
		return false
	var next: int = _balances[player] + amount
	if next < 0:
		return false
	if amount == 0:
		return true
	_balances[player] = next
	if not record_history:
		return true
	ledger.record(player, amount, reason, source, next)
	var ev: Dictionary = GameEvents.money_changed(player, amount, reason, next, source)
	pending_events.append(ev)
	money_changed.emit(ev)
	return true


## Takes up to `amount` (>= 0) from a player, never more than they have. Returns what was taken.
func take_up_to(player: int, amount: int, reason: StringName, source: StringName = &"") -> int:
	var taken: int = mini(maxi(amount, 0), balance(player))
	if taken > 0:
		apply(player, -taken, reason, source)
	return taken


## Collects and clears pending events.
func drain_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = pending_events
	pending_events = []
	return out


## Snapshot of all balances.
func balances() -> Dictionary[int, int]:
	return _balances.duplicate()
