class_name ItemSystem
extends RefCounted
## Items on the server (§2.8): inventories (3 slots with a discard choice when full), activation
## with cooldowns and target checks, protections (Bodyguard, Mirror, spawn and away protection,
## the negative-item grace window), effect expiry, and banana peels lying on the floor.
## Player intents and bots both go through `use`.

const SLOTS: int = 3
## `discard_item` slot meaning "throw away the incoming item" while a discard choice is open.
const DISCARD_INCOMING: int = 3

var defs: Dictionary[StringName, ItemDefinition] = {}
var balance: BalanceConfig
var players: Dictionary[int, PlayerState]
var economy: Economy
var modifiers: ModifierStack
var rules: InteractionRules
var world: WorldQuery
var pickups: PickupSystem
var rng: SeededRng
## Set by the MatchServer: knockouts (Baseball Bat), the current limits multiplier, standing a
## player up from a VIP table when their pass runs out, and the loot pool (Scratch Ticket).
var interactions: InteractionResolver = null
var limits: Callable = func() -> float: return 1.0
var on_vip_lost: Callable = Callable()
var loot: LootTables = null
var jackpot: ProgressiveJackpot = null
## Out of Order: nearest station to a player within a range (&"" = none), and closing one.
var find_station: Callable = Callable()
## Rock Paper Scissors wagers and the Gift Shop (built in `setup_extras`).
var duels: RpsDuels
var shop: GiftShop
var close_station: Callable = Callable()
var events: Array[Dictionary] = []
## When each player last used an item, and when each was last hit by a negative one.
var last_use: Dictionary[int, float] = {}
var last_hit: Dictionary[int, float] = {}
## player → items waiting for a discard choice: [{item, deadline}] (only the first is open).
var pending: Dictionary[int, Array] = {}
## peel id → {owner, pos: Vector3, expires_at}
var peels: Dictionary[int, Dictionary] = {}

var _effects: Dictionary[StringName, ItemEffect] = {}
var _next_peel: int = 1
var _now: float = 0.0


func _init(p_defs: Dictionary[StringName, ItemDefinition], p_balance: BalanceConfig, p_players: Dictionary[int, PlayerState], p_economy: Economy, p_modifiers: ModifierStack, p_rules: InteractionRules, p_world: WorldQuery, p_pickups: PickupSystem, p_rng: SeededRng) -> void:
	defs = p_defs
	balance = p_balance
	players = p_players
	economy = p_economy
	modifiers = p_modifiers
	rules = p_rules
	world = p_world
	pickups = p_pickups
	rng = p_rng
	modifiers.modifier_removed.connect(_on_modifier_removed)
	duels = RpsDuels.new(economy, rng.fork())


## Builds what needs the loot pool (call after setting `loot`).
func setup_extras() -> void:
	shop = GiftShop.new(loot, rng.fork())


## Buys Gift Shop offer `index` for `player`. Returns {ok, error}.
func buy(player: int, index: int, now: float) -> Dictionary:
	if shop == null or index < 0 or index >= shop.offers.size():
		return StationLogicBase.fail(&"bad_value")
	if shop.bought.has(player):
		return StationLogicBase.fail(&"already_bought")
	var offer: Dictionary = shop.offers[index]
	if economy.balance(player) < int(offer["price"]):
		return StationLogicBase.fail(&"insufficient_funds")
	economy.apply(player, -int(offer["price"]), &"shop", StringName(offer["item"]))
	shop.bought[player] = true
	events.append(GameEvents.make(&"shop_bought", {"player": player, "item": offer["item"], "price": offer["price"]}))
	give(player, StringName(offer["item"]), now)
	return StationLogicBase.OK_RESULT


# --- Inventory ---------------------------------------------------------------------------------

## Hands an item to a player. Returns true if it went straight into the inventory, false if it
## waits for a discard choice (inventory full) or can't be given.
func give(player: int, item: StringName, now: float) -> bool:
	_now = now
	if not players.has(player) or not defs.has(item):
		return false
	var inv: Array[StringName] = players[player].inventory
	if inv.size() < SLOTS and (pending.get(player, []) as Array).is_empty():
		inv.append(item)
		_inventory_changed(player)
		return true
	if not pending.has(player):
		pending[player] = []
	pending[player].append({"item": item, "deadline": INF})
	_open_next_choice(player, now)
	return false


## Throws away an item: slot 0–2 from the inventory, or (while a discard choice is open)
## `DISCARD_INCOMING` for the item that just arrived. Returns {ok, error}.
func discard(player: int, slot: int, now: float) -> Dictionary:
	_now = now
	if not players.has(player):
		return StationLogicBase.fail(&"unknown_player")
	var inv: Array[StringName] = players[player].inventory
	var queue: Array = pending.get(player, [])
	if not queue.is_empty():
		if slot != DISCARD_INCOMING and (slot < 0 or slot >= inv.size()):
			return StationLogicBase.fail(&"bad_slot")
		_resolve_choice(player, slot, now)
		return StationLogicBase.OK_RESULT
	if slot < 0 or slot >= inv.size():
		return StationLogicBase.fail(&"bad_slot")
	var dropped: StringName = inv[slot]
	inv.remove_at(slot)
	events.append(GameEvents.make(&"item_discarded", {"player": player, "item": dropped}))
	_inventory_changed(player)
	return StationLogicBase.OK_RESULT


func _open_next_choice(player: int, now: float) -> void:
	var queue: Array = pending.get(player, [])
	if queue.is_empty():
		return
	var inv: Array[StringName] = players[player].inventory
	if inv.size() < SLOTS:
		# Room appeared (an item was used meanwhile): no choice needed.
		inv.append(StringName(queue.pop_front()["item"]))
		_inventory_changed(player)
		_open_next_choice(player, now)
		return
	if float(queue[0]["deadline"]) == INF:
		queue[0]["deadline"] = now + balance.discard_time
		events.append(GameEvents.make(&"discard_needed", {"player": player, "item": queue[0]["item"], "seconds": balance.discard_time}))


## Closes the open discard choice: `slot` 0–2 swaps that item out, `DISCARD_INCOMING` (or no room
## issue) drops the newcomer.
func _resolve_choice(player: int, slot: int, now: float) -> void:
	var queue: Array = pending[player]
	var incoming: StringName = StringName(queue.pop_front()["item"])
	var inv: Array[StringName] = players[player].inventory
	var dropped: StringName = incoming
	if slot != DISCARD_INCOMING:
		if inv.size() >= SLOTS:
			dropped = inv[slot]
			inv.remove_at(slot)
		else:
			dropped = &""
		inv.append(incoming)
	if dropped != &"":
		events.append(GameEvents.make(&"item_discarded", {"player": player, "item": dropped}))
	_inventory_changed(player)
	if queue.is_empty():
		pending.erase(player)
	else:
		_open_next_choice(player, now)


func _inventory_changed(player: int) -> void:
	events.append(GameEvents.make(&"inventory_changed", {"player": player, "inventory": players[player].inventory.duplicate()}))


# --- Activation --------------------------------------------------------------------------------

## A player uses the item in `slot` (on `target`, -1 = automatic). Returns {ok, error}.
func use(player: int, slot: int, target: int, now: float, options: Dictionary = {}) -> Dictionary:
	_now = now
	if not players.has(player):
		return StationLogicBase.fail(&"unknown_player")
	var inv: Array[StringName] = players[player].inventory
	if slot < 0 or slot >= inv.size():
		return StationLogicBase.fail(&"bad_slot")
	if now - last_use.get(player, -INF) < balance.item_cooldown:
		return StationLogicBase.fail(&"cooldown")
	if rules.is_knocked_down(player, now) or rules.status(player).away:
		return StationLogicBase.fail(&"incapacitated")
	var id: StringName = inv[slot]
	var def: ItemDefinition = defs.get(id, null)
	if def == null:
		return StationLogicBase.fail(&"bad_item")
	var resolved: Dictionary = resolve_target(player, def, target, now)
	if resolved["error"] != &"":
		return StationLogicBase.fail(resolved["error"])
	var tgt: int = resolved["target"]
	var ctx := ItemContext.new(self, def, player, tgt, now)
	ctx.options = options
	var effect: ItemEffect = _effect(def)
	var why: StringName = effect.can_activate(ctx)
	if why != &"":
		return StationLogicBase.fail(why)
	var result: StringName = &"applied"
	if def.is_negative and targets_player(def):
		last_hit[tgt] = now
		if modifiers.consume_flag(tgt, &"mirror"):
			ctx.user = tgt
			ctx.target = player
			ctx.reflected = true
			result = &"reflected"
		elif modifiers.consume_flag(tgt, &"bodyguard"):
			result = &"blocked"
	inv.remove_at(slot)
	last_use[player] = now
	var ev: Dictionary = {"player": player, "item": id, "target": tgt, "result": result}
	if result != &"blocked":
		ev.merge(effect.activate(ctx), true)
	if bool(ev.get("keep", false)) and inv.size() < SLOTS:
		inv.insert(mini(slot, inv.size()), id)  # multi-use items stay in their slot
	events.append(GameEvents.make(&"item_used", ev))
	_inventory_changed(player)
	if not (pending.get(player, []) as Array).is_empty() and inv.size() < SLOTS:
		_resolve_choice(player, 0, now)  # a slot just freed up: the waiting item moves in
	return StationLogicBase.OK_RESULT


## True for items aimed at another player (protections and the grace window apply).
static func targets_player(def: ItemDefinition) -> bool:
	return def.target_mode != ItemDefinition.TargetMode.SELF and def.target_mode != ItemDefinition.TargetMode.PLACED


## Who an activation hits: {target, error}. `target` -1 picks the only valid one automatically.
func resolve_target(player: int, def: ItemDefinition, target: int, now: float) -> Dictionary:
	if not targets_player(def):
		return {"target": player, "error": &""}
	if def.target_mode != ItemDefinition.TargetMode.ANY_PLAYER and def.target_mode != ItemDefinition.TargetMode.NEAR_PLAYER:
		return {"target": -1, "error": &"not_supported"}
	if target < 0:
		var cands: Array[int] = candidates(player, def)
		if cands.is_empty():
			return {"target": -1, "error": &"no_target"}
		if cands.size() > 1:
			return {"target": -1, "error": &"need_target"}
		target = cands[0]
	if target == player:
		return {"target": -1, "error": &"self_target"}
	if not players.has(target):
		return {"target": -1, "error": &"bad_target"}
	if def.is_negative:
		var why: StringName = protection(target, now)
		if why != &"":
			return {"target": -1, "error": why}
	if def.target_mode == ItemDefinition.TargetMode.NEAR_PLAYER and not in_range(player, target, def.range_m):
		return {"target": -1, "error": &"out_of_range"}
	return {"target": target, "error": &""}


## Other players an item could be aimed at (present, and in range for proximity items).
func candidates(player: int, def: ItemDefinition) -> Array[int]:
	var out: Array[int] = []
	var ids: Array = players.keys()
	ids.sort()
	for id: int in ids:
		if id == player or not _present(id):
			continue
		if def.target_mode == ItemDefinition.TargetMode.NEAR_PLAYER and not in_range(player, id, def.range_m):
			continue
		out.append(id)
	return out


## Why a negative item can't hit `target` right now (&"" = it can).
func protection(target: int, now: float) -> StringName:
	if not _present(target) or rules.status(target).away:
		return &"target_away"
	if now < rules.status(target).protected_until:
		return &"target_protected"
	if now - last_hit.get(target, -INF) < balance.item_grace:
		return &"grace"
	return &""


func in_range(a: int, b: int, range_m: float) -> bool:
	return world.get_position(a).distance_to(world.get_position(b)) <= range_m + 0.001


func _present(id: int) -> bool:
	return players.has(id) and (players[id].connected or players[id].is_bot)


func _effect(def: ItemDefinition) -> ItemEffect:
	if not _effects.has(def.id):
		var e: ItemEffect = def.effect_script.new() as ItemEffect if def.effect_script != null else null
		_effects[def.id] = e if e != null else ItemEffect.new()
	return _effects[def.id]


# --- Effects over time -------------------------------------------------------------------------

## Bodyguard also absorbs one knockout from an attacker who used an item recently (§2.8).
## Returns true if the knockout is cancelled.
func shield_knockout(target: int, attacker: int, now: float) -> bool:
	if attacker < 0 or attacker == target or now - last_use.get(attacker, -INF) > balance.bodyguard_ko_window:
		return false
	if not modifiers.consume_flag(target, &"bodyguard"):
		return false
	events.append(GameEvents.make(&"bodyguard_saved", {"player": target, "attacker": attacker}))
	return true


## The casino segment ended: segment-long items (Hot Hands, Loaded Reels) run out.
func end_segment() -> void:
	modifiers.expire_flag(&"segment_end")
	duels.cancel_all()


## Discard deadlines always; banana peels only while the casino is open.
func tick(now: float, casino_open: bool) -> void:
	_now = now
	for player: int in pending.keys():
		var queue: Array = pending.get(player, [])
		if not queue.is_empty() and now >= float(queue[0]["deadline"]):
			_resolve_choice(player, 0, now)  # default: the oldest item goes
	if casino_open:
		_tick_peels(now)
		var bots: Dictionary = {}
		for id: int in players:
			if players[id].is_bot:
				bots[id] = true
		duels.tick(now, bots)


func _on_modifier_removed(player: int, mod: Modifier, reason: StringName) -> void:
	if not defs.has(mod.id):
		return
	events.append(GameEvents.make(&"effect_ended", {"player": player, "item": mod.id, "reason": reason}))
	var ctx := ItemContext.new(self, defs[mod.id], mod.source_player, player, _now)
	ctx.options["modifier"] = mod
	_effect(defs[mod.id]).on_expire(ctx, reason)


# --- Helpers for effects ----------------------------------------------------------------------

## Bad Luck Monkey is a hot potato: shoving someone hands it to them.
func pass_monkey(from: int, to: int, now: float) -> void:
	if to < 0 or to == from or not players.has(to) or rules.status(to).away:
		return
	var m: Modifier = modifiers.move_flag(from, to, &"monkey")
	if m != null:
		last_hit[to] = now
		events.append(GameEvents.make(&"monkey_passed", {"from": from, "to": to, "item": m.id, "left": snappedf(m.expires_at - now, 0.1) if m.expires_at != INF else -1.0}))


## Knocks a player down for `seconds` (they drop to the floor and can't act).
func knock_down(player: int, seconds: float, attacker: int, cause: StringName, now: float) -> void:
	rules.status(player).knocked_down_until = maxf(rules.status(player).knocked_down_until, now + seconds)
	events.append(GameEvents.make(&"player_knocked_down", {"target": player, "attacker": attacker, "seconds": seconds, "cause": cause}))


## Spills `pct` of a player's money (min/max, never more than they have) as chip piles around them.
## Returns {amount, piles}.
func spill(player: int, pct: float, min_amount: int, max_amount: int, reason: StringName, now: float) -> Dictionary:
	var amount: int = slip_amount(economy.balance(player), pct, min_amount, max_amount)
	var ids: Array[int] = []
	if amount > 0:
		ids = pickups.drop_from(player, amount, world.get_position(player), 4, rng, reason, now, 3.0)
	return {"amount": amount, "piles": ids}


## Hands out a random item from the loot pool of `rarity` (Scratch Ticket). Returns its id.
func random_item(rarity: int) -> StringName:
	if loot == null:
		return &""
	var pool: Array[StringName] = loot.ids_of(rarity)
	if pool.is_empty():
		return &""
	return pool[rng.range_int(0, pool.size() - 1)]


# --- Banana peels ------------------------------------------------------------------------------

## Drops a peel; returns its id.
func place_peel(owner: int, pos: Vector3, now: float, lifetime: float) -> int:
	var id: int = _next_peel
	_next_peel += 1
	peels[id] = {"owner": owner, "pos": pos, "expires_at": now + lifetime}
	events.append(GameEvents.make(&"banana_placed", {"peel": id, "owner": owner, "pos": Serializer.vec3(pos), "seconds": lifetime}))
	return id


## Chips dropped by a slip: `pct` of the money, at least `min_amount`, at most `max_amount`,
## never more than the player has.
static func slip_amount(money: int, pct: float, min_amount: int, max_amount: int) -> int:
	if money <= 0:
		return 0
	return mini(clampi(int(floor(money * pct)), min_amount, max_amount), money)


func _tick_peels(now: float) -> void:
	var ids: Array = peels.keys()
	ids.sort()
	var who_ids: Array = players.keys()
	who_ids.sort()
	for id: int in ids:
		var peel: Dictionary = peels[id]
		if now >= float(peel["expires_at"]):
			peels.erase(id)
			events.append(GameEvents.make(&"banana_removed", {"peel": id, "reason": &"expired"}))
			continue
		for pid: int in who_ids:
			if pid == int(peel["owner"]) or not _steps_on(pid, peel["pos"], now):
				continue
			_slip(id, pid, now)
			break


func _steps_on(pid: int, peel_pos: Vector3, now: float) -> bool:
	if not _present(pid):
		return false
	var st: InteractionRules.Status = rules.status(pid)
	if st.away or st.seated or now < st.protected_until or rules.is_knocked_down(pid, now) or world.is_airborne(pid):
		return false
	if now - last_hit.get(pid, -INF) < balance.item_grace:
		return false
	var d: Vector3 = world.get_position(pid) - peel_pos
	return Vector2(d.x, d.z).length() <= balance.banana_radius and absf(d.y) < 1.2


func _slip(peel_id: int, victim: int, now: float) -> void:
	var peel: Dictionary = peels[peel_id]
	peels.erase(peel_id)
	var owner: int = peel["owner"]
	var who: int = victim
	var result: StringName = &"slipped"
	last_hit[victim] = now
	if modifiers.consume_flag(victim, &"mirror"):
		result = &"reflected"
		who = owner
	elif modifiers.consume_flag(victim, &"bodyguard"):
		result = &"blocked"
	var amount: int = 0
	var piles: Array[int] = []
	var def: ItemDefinition = defs.get(&"banana_peel", null)
	if result != &"blocked" and players.has(who):
		last_hit[who] = now
		var p: Dictionary = def.params if def != null else {}
		amount = slip_amount(economy.balance(who), float(p.get("pct", 0.06)), int(p.get("min", 20)), int(p.get("max", 300)))
		if amount > 0:
			piles = pickups.drop_from(who, amount, world.get_position(who), 4, rng, &"banana_slip", now, 3.0)
		rules.status(who).knocked_down_until = now + balance.banana_stun
	events.append(GameEvents.make(&"banana_slip", {"peel": peel_id, "player": victim, "owner": owner, "result": result, "victim": who, "amount": amount, "piles": piles, "pos": Serializer.vec3(peel["pos"])}))
	if result != &"blocked" and players.has(who):
		events.append(GameEvents.make(&"player_knocked_down", {"target": who, "attacker": owner, "seconds": balance.banana_stun, "cause": &"banana"}))
	events.append(GameEvents.make(&"banana_removed", {"peel": peel_id, "reason": result}))


# --- Replication -------------------------------------------------------------------------------

## Active item effects per player (ids) for everyone's VFX.
func public_effects() -> Dictionary:
	var out: Dictionary = {}
	for pid: int in players:
		var ids: Array = []
		for m: Modifier in modifiers.get_mods(pid):
			if defs.has(m.id):
				ids.append(m.id)
		if not ids.is_empty():
			out[pid] = ids
	return out


func peels_wire() -> Array:
	var out: Array = []
	for id: int in peels:
		out.append({"peel": id, "owner": peels[id]["owner"], "pos": Serializer.vec3(peels[id]["pos"]), "seconds": snappedf(maxf(float(peels[id]["expires_at"]) - _now, 0.0), 0.1)})
	return out


## One player's own view: luck, effects with time/uses left, an open discard choice.
func private_state(player: int, now: float) -> Dictionary:
	var effects: Array = []
	for m: Modifier in modifiers.get_mods(player):
		if not defs.has(m.id):
			continue
		effects.append({"item": m.id, "luck": m.luck, "game": m.game_id, "left": snappedf(m.expires_at - now, 0.1) if m.expires_at != INF else -1.0, "uses": m.rounds_left})
	var out: Dictionary = {"luck": modifiers.get_luck(player), "effects": effects}
	if shop != null and shop.bought.has(player):
		out["shop_bought"] = true
	for d: Dictionary in duels.duels.values():
		if int(d["a"]) == player or int(d["b"]) == player:
			out["duel"] = {"duel": d["duel"], "a": d["a"], "b": d["b"], "stake": d["stake"], "state": d["state"], "left": snappedf(maxf(float(d["deadline"]) - now, 0.0), 0.1), "picked": (d["picks"] as Dictionary).has(player)}
	var queue: Array = pending.get(player, [])
	if not queue.is_empty() and float(queue[0]["deadline"]) != INF:
		out["discard"] = {"item": queue[0]["item"], "left": snappedf(maxf(float(queue[0]["deadline"]) - now, 0.0), 0.1)}
	return out


func drain_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = events
	events = []
	out.append_array(duels.drain_events())
	return out
