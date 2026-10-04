class_name MatchServer
extends Node
## Server-only orchestration (§3.6): owns the match state, economy, stations, phase machine and
## physical-interaction resolution, ticks at a fixed 20 Hz, validates intents and emits events.
## Runs in-process for Practice/Tutorial and in the dedicated server process online: one code path.

## Every event the server produces, in order, with a `seq`.
signal event_emitted(event: Dictionary)

const TICK: float = 1.0 / Protocol.SERVER_TICK_HZ

var balance: BalanceConfig
var presets: MatchPresets
var state: MatchState = MatchState.new()
var economy: Economy = Economy.new()
var modifiers: ModifierStack
var rng: SeededRng
var luck_rng: LuckRng
var jackpot: ProgressiveJackpot
var stations: StationManager = StationManager.new()
var rules: InteractionRules
var world: WorldQuery = WorldQuery.new()
var pickups: PickupSystem
var interactions: InteractionResolver
var validator: IntentValidator = IntentValidator.new()
var schedule: MatchSchedule
var phases: PhaseMachine
## Optional minigame director (M4). Without one, minigames are skipped with equal scores.
var minigame_director: RefCounted = null
## Time acceleration for sims/tests.
var timescale: float = 1.0
## Match seconds elapsed (all phases), the server clock.
var match_time: float = 0.0
## Settings: duration, seed, items_enabled, bots.
var settings: Dictionary = {"duration": 10, "seed": 0, "items_enabled": true}
## Recent events kept for gap recovery.
var event_log: Array[Dictionary] = []
var running: bool = false
var map_def: MapDefinition

var _accumulator: float = 0.0
var _next_player_id: int = 1
var _logic_scripts: Dictionary = {}


## Wires balance/presets/registry data. Call before `add_player`/`start_match`.
func configure(p_settings: Dictionary, p_balance: BalanceConfig, p_presets: MatchPresets, logic_scripts: Dictionary, p_map: MapDefinition) -> void:
	settings.merge(p_settings, true)
	balance = p_balance
	presets = p_presets
	map_def = p_map
	_logic_scripts = logic_scripts
	var seed_value: int = int(settings.get("seed", 0))
	if seed_value == 0:
		seed_value = int(Time.get_unix_time_from_system()) ^ randi()
	settings["seed"] = seed_value
	state.match_seed = seed_value
	state.duration_minutes = int(settings.get("duration", presets.default_duration))
	rng = SeededRng.new(seed_value)
	luck_rng = LuckRng.new(rng, balance.luck_reroll_per_point, balance.luck_clamp)
	modifiers = ModifierStack.new(balance.luck_clamp)
	jackpot = ProgressiveJackpot.new(balance.jackpot_feed_rate, balance.jackpot_seed)
	rules = InteractionRules.new(balance)
	pickups = PickupSystem.new(economy)
	interactions = InteractionResolver.new(rules, world, economy, pickups, rng.fork())
	schedule = MatchSchedule.new(state.duration_minutes, presets, balance.last_call_seconds)
	phases = PhaseMachine.new(schedule)
	phases.phase_changed.connect(_on_phase_changed)
	var vip_ids: Array = []
	for sid: Variant in map_def.stations:
		if str(sid).begins_with("vip_"):
			vip_ids.append(StringName(sid))
	stations.setup(map_def.stations, logic_scripts, balance, economy, modifiers, rng.fork(), jackpot, vip_ids)
	Log.info(&"server", "configured: duration %d min, seed %d, %d stations" % [state.duration_minutes, seed_value, stations.logics.size()])


## Adds a participant and returns its player id.
func add_player(uid: String, display_name: String, is_bot: bool = false, color_index: int = -1) -> int:
	var p := PlayerState.new()
	p.id = _next_player_id
	_next_player_id += 1
	p.uid = uid
	p.display_name = display_name
	p.is_bot = is_bot
	p.color_index = color_index if color_index >= 0 else (p.id - 1) % 8
	state.add_player(p)
	economy.add_player(p.id, balance.start_money)
	world.set_transform(p.id, Vector3.ZERO, 0.0)
	_emit(GameEvents.make(&"player_joined", {"player": p.to_wire()}))
	return p.id


## Player id for a uid, or -1.
func player_by_uid(uid: String) -> int:
	for id: int in state.players:
		if state.players[id].uid == uid:
			return id
	return -1


## Starts the match (lobby → intro → casino).
func start_match() -> void:
	if running:
		return
	running = true
	match_time = 0.0
	phases.start()
	stations.set_limits_multiplier(balance.limits_multiplier(0))
	for id: int in state.players:
		rules.protect(id, match_time)
	_emit(GameEvents.make(&"match_started", {"seed": state.match_seed, "duration": state.duration_minutes, "segment_s": schedule.segment_s, "minigames": schedule.minigames}))
	_flush()


## Handles one client intent. Returns {ok, error}.
func submit_intent(player: int, intent: Dictionary) -> Dictionary:
	var why: StringName = validator.check(player, intent, phases.phase, match_time, state.players.has(player))
	if why != &"":
		if why != &"rate_limited":
			Log.debug(&"server", "intent rejected (%s): %s" % [why, intent])
		return StationLogicBase.fail(why)
	var res: Dictionary = _apply_intent(player, intent)
	if not res["ok"]:
		_emit(GameEvents.make(&"intent_rejected", {"player": player, "intent": intent.get("type"), "error": res["error"]}))
	_flush()
	return res


## Full snapshot for join/reconnect (no secrets).
func get_snapshot() -> Dictionary:
	_sync_state()
	var snap: Dictionary = state.to_wire()
	snap["match_time"] = snappedf(match_time, 0.001)
	snap["time_left"] = snappedf(phases.time_left(), 0.001)
	snap["next_minigame_in"] = snappedf(phases.next_minigame_in(), 0.001) if phases.next_minigame_in() != INF else -1.0
	snap["last_call"] = phases.last_call_announced
	snap["piles"] = _piles_wire()
	return snap


## Private data for one player (own station secrets, inventory offers).
func get_private_snapshot(player: int) -> Dictionary:
	return {"station": stations.private_state(player)}


## Advances the simulation by real seconds (scaled by `timescale`), in fixed 20 Hz steps.
func advance(real_delta: float) -> void:
	if not running:
		return
	_accumulator += real_delta * timescale
	var steps: int = 0
	while _accumulator >= TICK and steps < 2000:
		_accumulator -= TICK
		_step(TICK)
		steps += 1
	_flush()


## Runs the simulation until the match is over or `max_seconds` elapsed (tests/sims).
func run_to_end(max_seconds: float = 36000.0) -> void:
	var elapsed: float = 0.0
	while running and phases.phase != Phase.Id.RESULTS and elapsed < max_seconds:
		_step(TICK)
		elapsed += TICK
	_flush()


## Game-time step.
func _step(delta: float) -> void:
	match_time += delta
	var notes: Array[StringName] = phases.advance(delta)
	for n: StringName in notes:
		_on_phase_note(n)
	if phases.phase == Phase.Id.CASINO or phases.phase == Phase.Id.PRE_MINIGAME:
		stations.tick(delta)
	modifiers.expire(match_time)
	interactions.tick(match_time)
	pickups.tick(match_time)
	_tick_bots()


func _on_phase_note(note: StringName) -> void:
	match note:
		&"last_call":
			stations.set_global_multiplier(balance.last_call_multiplier)
			_emit(GameEvents.make(&"last_call", {"seconds": balance.last_call_seconds, "multiplier": balance.last_call_multiplier}))
		&"minigame_due":
			_emit(GameEvents.make(&"minigame_warning", {"seconds": PhaseMachine.PRE_MINIGAME_SECONDS}))
		&"segment_ended":
			stations.auto_resolve_all()
			_emit(GameEvents.make(&"segment_ended", {"segment": phases.segment_index()}))
		&"minigame_started":
			if minigame_director != null and minigame_director.has_method("begin"):
				minigame_director.call("begin", self)
			else:
				_emit(GameEvents.make(&"minigame_skipped", {}))
				phases.minigame_finished()
				phases.rewards_finished()
		&"match_over":
			_finish_match()


func _on_phase_changed(from: Phase.Id, to: Phase.Id) -> void:
	if to == Phase.Id.CASINO:
		var seg: int = phases.segment_index()
		state.segment_index = seg
		stations.set_limits_multiplier(balance.limits_multiplier(seg))
		interactions.limits_multiplier = balance.limits_multiplier(seg)
		if from == Phase.Id.REWARDS:
			for id: int in state.players:
				rules.protect(id, match_time)
	_emit(GameEvents.make(&"phase_changed", {"phase": to, "from": from, "phase_name": Phase.name_of(to), "casino_time": snappedf(phases.casino_time, 0.001), "segment": phases.segment_index()}))


func _finish_match() -> void:
	running = false
	var standings: Array[Dictionary] = get_standings()
	_emit(GameEvents.make(&"match_ended", {"standings": standings, "jackpot": jackpot.pot}))


## Final ranking: money, then quiz points, then biggest win; ties share placement.
func get_standings() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for id: int in state.players:
		var p: PlayerState = state.players[id]
		rows.append({"player": id, "name": p.display_name, "money": economy.balance(id), "quiz_points": p.quiz_points, "biggest_win": p.biggest_win})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["money"] != b["money"]:
			return a["money"] > b["money"]
		if a["quiz_points"] != b["quiz_points"]:
			return a["quiz_points"] > b["quiz_points"]
		if a["biggest_win"] != b["biggest_win"]:
			return a["biggest_win"] > b["biggest_win"]
		return a["player"] < b["player"])
	for i: int in rows.size():
		var tie: bool = i > 0 and rows[i]["money"] == rows[i - 1]["money"] and rows[i]["quiz_points"] == rows[i - 1]["quiz_points"] and rows[i]["biggest_win"] == rows[i - 1]["biggest_win"]
		rows[i]["rank"] = rows[i - 1]["rank"] if tie else i + 1
	return rows


func _apply_intent(player: int, intent: Dictionary) -> Dictionary:
	var type: StringName = StringName(intent["type"])
	match type:
		&"sit":
			if rules.is_knocked_down(player, match_time) or interactions.is_held(player):
				return StationLogicBase.fail(&"incapacitated")
			var sid: StringName = StringName(intent["station"])
			var pos: Vector3 = world.get_position(player)
			var spos: Variant = map_def.station_positions.get(sid, null)
			if spos != null and (Vector3(spos) - pos).length() > map_def.interact_range:
				return StationLogicBase.fail(&"too_far")
			if stations.vip.get(sid, false) and economy.balance(player) < int(floor(balance.vip_entry_money * stations._limits_multiplier)):
				return StationLogicBase.fail(&"vip_denied")
			var res: Dictionary = stations.sit(player, sid)
			if res["ok"]:
				rules.status(player).seated = true
				state.players[player].station = sid
				_emit(GameEvents.make(&"player_sat", {"player": player, "station": sid}))
			return res
		&"leave":
			var res: Dictionary = stations.leave(player)
			if res["ok"]:
				rules.status(player).seated = false
				state.players[player].station = &""
				_emit(GameEvents.make(&"player_stood", {"player": player}))
			return res
		&"place_bet", &"clear_bets", &"action":
			return stations.route(player, intent)
		&"move":
			if stations.is_seated(player) or rules.is_knocked_down(player, match_time) or interactions.is_held(player):
				return StationLogicBase.fail(&"not_standing")
			world.set_transform(player, Serializer.to_vec3(intent["pos"]), float(intent["yaw"]), bool(intent.get("airborne", false)))
			state.players[player].position = world.get_position(player)
			return StationLogicBase.OK_RESULT
		&"grab":
			if stations.is_seated(player) or rules.is_knocked_down(player, match_time):
				return StationLogicBase.fail(&"not_standing")
			return interactions.grab(player, int(intent["target"]), match_time)
		&"release":
			return interactions.release(player, bool(intent["throw"]), Serializer.to_vec3(intent.get("aim", [])), match_time)
		&"shove":
			if stations.is_seated(player) or rules.is_knocked_down(player, match_time) or interactions.is_held(player):
				return StationLogicBase.fail(&"not_standing")
			return interactions.shove(player, Serializer.to_vec3(intent["aim"]), match_time, modifiers.has_flag(player, &"spring_glove"))
		&"shake":
			if stations.is_seated(player) or rules.is_knocked_down(player, match_time):
				return StationLogicBase.fail(&"not_standing")
			return interactions.shake(player, match_time)
		&"break_free":
			return interactions.break_free(player, match_time)
		&"emote":
			_emit(GameEvents.make(&"emote", {"player": player, "id": StringName(intent["id"])}))
			return StationLogicBase.OK_RESULT
		&"set_ready":
			state.players[player].ready = bool(intent["ready"])
			_emit(GameEvents.make(&"player_ready", {"player": player, "ready": bool(intent["ready"])}))
			return StationLogicBase.OK_RESULT
	return StationLogicBase.fail(&"not_implemented")


## World callbacks (the scene reports physical outcomes the server can't see itself).
func report_knockout(target: int, attacker: int, cause: StringName) -> bool:
	var ok: bool = interactions.report_knockout(target, attacker, match_time, cause)
	_flush()
	return ok


func report_pickup(player: int, pile_id: int) -> bool:
	var ok: bool = pickups.collect(player, pile_id)
	_flush()
	return ok


func report_thrown_out(attacker: int, guard: StringName) -> void:
	interactions.report_thrown_out(attacker, guard, match_time)
	_flush()


## Sets a player's position from the server side (ragdoll settled, respawn).
func set_server_position(player: int, pos: Vector3) -> void:
	world.set_transform(player, pos, world.get_yaw(player))
	state.players[player].position = pos


func _tick_bots() -> void:
	pass  # BotDirector (M6) hooks in here.


func _sync_state() -> void:
	state.phase = phases.phase
	state.casino_time = phases.casino_time
	state.segment_index = phases.segment_index()
	state.balances = economy.balances()
	state.jackpot = jackpot.pot
	state.stations = stations.public_states()


func _piles_wire() -> Array:
	var out: Array = []
	for id: int in pickups.piles:
		var p: Dictionary = pickups.piles[id]
		out.append({"pile": id, "amount": p["amount"], "pos": Serializer.vec3(p["pos"])})
	return out


## Drains subsystem events and emits them in order.
func _flush() -> void:
	var batch: Array[Dictionary] = []
	batch.append_array(stations.drain_events())
	batch.append_array(interactions.drain_events())
	batch.append_array(pickups.drain_events())
	batch.append_array(economy.drain_events())
	for ev: Dictionary in batch:
		_track_stats(ev)
		_emit(ev)


func _track_stats(ev: Dictionary) -> void:
	if ev["type"] == &"round_result":
		var p: int = ev["player"]
		if state.players.has(p):
			state.players[p].biggest_win = maxi(state.players[p].biggest_win, int(ev["net"]))


func _emit(ev: Dictionary) -> void:
	state.event_seq += 1
	ev["seq"] = state.event_seq
	ev["t"] = snappedf(match_time, 0.001)
	event_log.append(ev)
	if event_log.size() > 2000:
		event_log = event_log.slice(event_log.size() - 1000)
	event_emitted.emit(ev)
