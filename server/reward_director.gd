class_name RewardDirector
extends RefCounted
## The reward phase after a minigame (§2.10, Patrick's note #11): no draft. Everyone gets cash by
## placement and one item rolled by rarity (placement shifts the odds), the House Comp if they are
## broke, all paid and granted at once; then a short reveal while the screen flips the cards.
## With items disabled the cash is multiplied by `cash_only_factor` and nobody gets an item.
##
## Everything here is public: one `rewards_started {rewards: [{player, placement, cash, item,
## bonus?, comp?}], seconds}` event.

enum State { IDLE, REVEAL, DONE }

const INVENTORY_SLOTS: int = 3

var state: State = State.IDLE
var timer: float = 0.0
## Rows in placement order: {player, placement, cash, item, bonus?, comp?}.
var rows: Array[Dictionary] = []
var events: Array[Dictionary] = []
## Hands an item to a player: Callable(player: int, item: StringName) (the ItemSystem, which runs
## the discard choice when the inventory is full). Unset: items that don't fit are lost.
var grant: Callable


## Starts the reward phase from a minigame ranking ([{player, rank, ...}]). `comp` (optional)
## pays the House Comp to a broke player and returns the amount (0 = none); it runs before the
## prize cash so "broke" means broke at the end of the round.
func start(ranking: Array[Dictionary], economy: Economy, loot: LootTables, items_enabled: bool, limits_multiplier: float, balance: BalanceConfig, rng: SeededRng, players: Dictionary[int, PlayerState] = {}, comp: Callable = Callable()) -> void:
	rows.clear()
	var worst: int = 0
	for row: Dictionary in ranking:
		worst = maxi(worst, int(row["rank"]))
	var sorted: Array[Dictionary] = ranking.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["rank"]) < int(b["rank"]) if int(a["rank"]) != int(b["rank"]) else int(a["player"]) < int(b["player"]))
	for row: Dictionary in sorted:
		var p: int = int(row["player"])
		var placement: int = int(row["rank"])
		var out: Dictionary = {"player": p, "placement": placement, "cash": 0, "item": &""}
		if comp.is_valid():
			var c: int = int(comp.call(p))
			if c > 0:
				out["comp"] = c
		var cash: int = cash_for(placement, items_enabled, limits_multiplier, balance)
		out["cash"] = cash
		if cash > 0:
			economy.apply(p, cash, &"minigame_prize", &"rewards")
		if items_enabled and loot != null:
			out["item"] = loot.roll(placement, ranking.size(), rng)
			var extra: StringName = loot.underdog(placement, worst, ranking.size(), rng)
			if extra != &"":
				out["bonus"] = extra
		rows.append(out)
	for out: Dictionary in rows:
		for key: String in ["item", "bonus"]:
			if StringName(out.get(key, &"")) != &"":
				_give(int(out["player"]), StringName(out[key]), players)
	state = State.REVEAL
	timer = balance.reward_reveal_time + balance.reward_row_time * rows.size()
	events.append(GameEvents.make(&"rewards_started", {"rewards": rows.duplicate(true), "seconds": snappedf(timer, 0.01)}))


## Cash for a placement from `quiz_cash_prizes` (places past the list get its last entry), scaled
## by the limits multiplier and by `cash_only_factor` when items are off.
static func cash_for(placement: int, items_enabled: bool, limits_multiplier: float, balance: BalanceConfig) -> int:
	if placement < 1 or balance.quiz_cash_prizes.is_empty():
		return 0
	var base: float = balance.quiz_cash_prizes[mini(placement, balance.quiz_cash_prizes.size()) - 1] * limits_multiplier
	if not items_enabled:
		base *= balance.cash_only_factor
	return int(floor(base + 0.000001))


## Advances the reveal.
func tick(delta: float) -> void:
	if state != State.REVEAL:
		return
	timer -= delta
	if timer <= 0.0:
		state = State.DONE


func is_done() -> bool:
	return state == State.DONE


## Public view for snapshots (late join, reconnect during the reveal).
func get_public_state() -> Dictionary:
	return {"state": state, "timer": snappedf(maxf(timer, 0.0), 0.01), "rewards": rows.duplicate(true)}


func drain_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = events
	events = []
	return out


func _give(p: int, item: StringName, players: Dictionary[int, PlayerState]) -> void:
	if grant.is_valid():
		grant.call(p, item)
	elif players.has(p) and players[p].inventory.size() < INVENTORY_SLOTS:
		players[p].inventory.append(item)
