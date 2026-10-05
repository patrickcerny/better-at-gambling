class_name RewardDirector
extends RefCounted
## The reward phase after a minigame (§2.10): cash by placement right away, then a simultaneous
## item draft (`draft_time` s, default = first option). Items are stubbed until M5: picks land in
## the inventory without effects. With items disabled the cash is doubled and there is no draft.
##
## Offers are private (`private_state`), everyone else only learns what a player ended up with.

enum State { IDLE, DRAFT, OUTRO, DONE }

const INVENTORY_SLOTS: int = 3

var state: State = State.IDLE
var timer: float = 0.0
## player → {placement, cash, choices: Array[StringName], bonus: Array[StringName], pick: int}
var rewards: Dictionary[int, Dictionary] = {}
var events: Array[Dictionary] = []
## Hands an item to a player: Callable(player: int, item: StringName) (the ItemSystem, which runs
## the discard choice when the inventory is full). Unset: items that don't fit are lost.
var grant: Callable
var _balance: BalanceConfig


## Starts the reward phase from a minigame ranking ([{player, rank, ...}]). Pays the cash through
## `economy`, builds draft offers with `loot` (null or items off = cash only).
func start(ranking: Array[Dictionary], economy: Economy, loot: LootTables, items_enabled: bool, limits_multiplier: float, balance: BalanceConfig, rng: SeededRng) -> void:
	_balance = balance
	rewards.clear()
	var worst: int = 0
	for row: Dictionary in ranking:
		worst = maxi(worst, int(row["rank"]))
	var summary: Array = []
	for row: Dictionary in ranking:
		var p: int = int(row["player"])
		var placement: int = int(row["rank"])
		var cash: int = cash_for(placement, items_enabled, limits_multiplier, balance)
		var r: Dictionary = {"placement": placement, "cash": cash, "choices": [], "bonus": [], "pick": -1}
		if items_enabled and loot != null:
			var d: Dictionary = loot.draft(placement, placement == worst and ranking.size() > 1, ranking.size(), rng)
			r["choices"] = d["choices"]
			r["bonus"] = d["bonus"]
		rewards[p] = r
		if cash > 0:
			economy.apply(p, cash, &"minigame_prize", &"rewards")
		summary.append({"player": p, "placement": placement, "cash": cash, "draft": not (r["choices"] as Array).is_empty(), "bonus_count": (r["bonus"] as Array).size()})
	state = State.DRAFT
	timer = balance.draft_time if _any_draft() else 0.0
	events.append(GameEvents.make(&"rewards_started", {"rewards": summary, "seconds": timer}))


## Cash for a placement (1st/2nd/3rd from `quiz_cash_prizes`, then 0), scaled by the limits
## multiplier and doubled when items are off.
static func cash_for(placement: int, items_enabled: bool, limits_multiplier: float, balance: BalanceConfig) -> int:
	if placement < 1 or placement > balance.quiz_cash_prizes.size():
		return 0
	var base: float = balance.quiz_cash_prizes[placement - 1] * limits_multiplier
	if not items_enabled:
		base *= balance.cash_only_factor
	return int(floor(base + 0.000001))


## A player picks draft option `choice`. Returns {ok, error}.
func pick(player: int, choice: int) -> Dictionary:
	if state != State.DRAFT:
		return StationLogicBase.fail(&"too_late")
	if not rewards.has(player):
		return StationLogicBase.fail(&"no_reward")
	var r: Dictionary = rewards[player]
	if choice < 0 or choice >= (r["choices"] as Array).size():
		return StationLogicBase.fail(&"bad_value")
	if int(r["pick"]) >= 0:
		return StationLogicBase.fail(&"already_picked")
	r["pick"] = choice
	events.append(GameEvents.make(&"draft_picked", {"player": player}))
	return StationLogicBase.OK_RESULT


## Advances the phase; grants items when the draft closes. `players` is the match's player table
## (inventories are written there).
func tick(delta: float, players: Dictionary[int, PlayerState]) -> void:
	if state == State.IDLE or state == State.DONE:
		return
	timer -= delta
	if state == State.DRAFT and (timer <= 0.0 or _all_picked()):
		_grant(players)
		state = State.OUTRO
		timer = _balance.reward_outro_time
	elif state == State.OUTRO and timer <= 0.0:
		state = State.DONE


func is_done() -> bool:
	return state == State.DONE


## Offer for one player ({} when none or the draft is over).
func private_state(player: int) -> Dictionary:
	if state != State.DRAFT or not rewards.has(player):
		return {}
	var r: Dictionary = rewards[player]
	if (r["choices"] as Array).is_empty() and (r["bonus"] as Array).is_empty():
		return {}
	return {"draft": {"choices": (r["choices"] as Array).duplicate(), "bonus": (r["bonus"] as Array).duplicate(), "pick": r["pick"], "placement": r["placement"], "cash": r["cash"]}}


## Public view for snapshots.
func get_public_state() -> Dictionary:
	var rows: Array = []
	for p: int in rewards:
		rows.append({"player": p, "placement": rewards[p]["placement"], "cash": rewards[p]["cash"], "picked": int(rewards[p]["pick"]) >= 0})
	return {"state": state, "timer": snappedf(maxf(timer, 0.0), 0.01), "rewards": rows}


func drain_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = events
	events = []
	return out


func _any_draft() -> bool:
	for p: int in rewards:
		if not (rewards[p]["choices"] as Array).is_empty():
			return true
	return false


func _all_picked() -> bool:
	for p: int in rewards:
		if not (rewards[p]["choices"] as Array).is_empty() and int(rewards[p]["pick"]) < 0:
			return false
	return true


func _grant(players: Dictionary[int, PlayerState]) -> void:
	for p: int in rewards:
		var r: Dictionary = rewards[p]
		var got: Array[StringName] = []
		var choices: Array = r["choices"]
		if not choices.is_empty():
			got.append(StringName(choices[maxi(int(r["pick"]), 0)]))
		for b: Variant in r["bonus"]:
			got.append(StringName(b))
		var kept: Array[StringName] = []
		if grant.is_valid():
			for item: StringName in got:
				grant.call(p, item)
				kept.append(item)
		elif players.has(p):
			for item: StringName in got:
				if players[p].inventory.size() < INVENTORY_SLOTS:
					players[p].inventory.append(item)
					kept.append(item)
		if not got.is_empty():
			events.append(GameEvents.make(&"draft_result", {"player": p, "items": got, "kept": kept, "inventory": players[p].inventory.duplicate() if players.has(p) else []}))
