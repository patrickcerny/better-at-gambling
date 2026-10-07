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
## Entrance-hall lobby rules (online rooms only; Practice starts the match straight away).
var lobby: LobbyController = LobbyController.new()
## Server-side checks on client-reported movement (online).
var sanity: MoveSanity = MoveSanity.new()
## True for an online room: the match waits in LOBBY until everyone is ready.
var room_mode: bool = false
var schedule: MatchSchedule
var phases: PhaseMachine
## Minigames between segments (§2.9), the reward phase after them (§2.10) and the Hot Table event.
var minigames: MinigameDirector
var minigame: MinigameLogicBase = null
var rewards: RewardDirector = RewardDirector.new()
var hot_tables: HotTableDirector
var loot: LootTables
var items: ItemSystem
## The waiter NPC's trips and drink puddles, and the Megaphone prop by the bar (M7, npc/).
var waiter: WaiterLogic
var megaphone: MegaphoneLogic
## Dealers at blackjack and roulette tables (v0.8.4, npc/): station_id → DealerLogic.
var dealers: Dictionary[StringName, DealerLogic] = {}
## Smoothed half round-trip time of a player in seconds (set by the network layer; 0 offline).
var half_rtt_provider: Callable = func(_p: int) -> float: return 0.0
## Per-player match stats for awards and dynamic quiz questions.
var stats: Dictionary[int, Dictionary] = {}
## Balance samples over casino time for the results graph (in `match_ended` standings rows).
var money_history: MoneyHistory = MoneyHistory.new()
## Results screen: seconds until an online room goes back to its lobby on its own.
var results_return_in: float = -1.0
## Time acceleration for sims/tests.
var timescale: float = 1.0
## Match seconds elapsed (all phases), the server clock.
var match_time: float = 0.0
## Settings: minigames, gamble_minutes, seed, items_enabled; dev/tests may add `gamble_seconds`
## (> 0 overrides the minutes, so tests can run short matches).
var settings: Dictionary = {"minigames": 5, "gamble_minutes": 3, "seed": 0, "items_enabled": true}
## Recent events kept for gap recovery.
var event_log: Array[Dictionary] = []
var running: bool = false
var map_def: MapDefinition

var _accumulator: float = 0.0
var _next_player_id: int = 1
var _logic_scripts: Dictionary = {}
## Players whose body the server simulates right now (ragdolled, thrown): their moves are ignored.
var _server_owned: Dictionary[int, bool] = {}
## Real seconds since the server started (lobby ordering, network clock).
var _uptime: float = 0.0
var _leader: int = -1
## player → casino segment in which they got the House Comp (once per segment).
var _comped: Dictionary[int, int] = {}
var _logic_rng: SeededRng


## Wires balance/presets/registry data. Call before `add_player`/`start_match`.
func configure(p_settings: Dictionary, p_balance: BalanceConfig, p_presets: MatchPresets, logic_scripts: Dictionary, p_map: MapDefinition) -> void:
	settings.merge(p_settings, true)
	balance = p_balance
	presets = p_presets
	map_def = p_map
	_logic_scripts = logic_scripts
	lobby.presets = presets
	lobby.settings["minigames"] = int(settings.get("minigames", presets.default_minigames))
	lobby.settings["gamble_minutes"] = int(settings.get("gamble_minutes", presets.default_gamble_minutes))
	_apply_length()
	var defs: Array[MinigameDefinition] = []
	for id: StringName in Registry.minigames:
		defs.append(Registry.minigames[id])
	minigames = MinigameDirector.new(defs, Registry.quiz_bank)
	var rarities: Dictionary[StringName, int] = {}
	for id: StringName in Registry.items:
		if Registry.items[id].in_loot:
			rarities[id] = Registry.items[id].rarity
	loot = LootTables.new(Registry.loot, rarities)
	lobby.settings["items_enabled"] = bool(settings.get("items_enabled", true))
	_build_match_systems(int(settings.get("seed", 0)))
	Log.info(&"server", "configured: %d minigames, %.0f s gambling between, seed %d, %d stations" % [state.minigames, state.gamble_s, state.match_seed, stations.logics.size()])


## Match length from the lobby settings (`minigames`, `gamble_minutes`) or the dev override
## `settings.gamble_seconds` (Patrick's note #12).
func _apply_length() -> void:
	state.minigames = int(lobby.settings.get("minigames", presets.default_minigames))
	var override_s: float = float(settings.get("gamble_seconds", 0.0))
	state.gamble_s = override_s if override_s > 0.0 else int(lobby.settings.get("gamble_minutes", presets.default_gamble_minutes)) * 60.0
	state.duration_s = state.gamble_s * (state.minigames + 1)


## Everything that lives for one match (money, tables, RNG, schedule). Called by `configure` and
## again for "play again in the same room"; players, lobby and the room survive.
func _build_match_systems(seed_value: int) -> void:
	if seed_value == 0:
		seed_value = int(Time.get_unix_time_from_system()) ^ randi()
	settings["seed"] = seed_value
	state.match_seed = seed_value
	rng = SeededRng.new(seed_value)
	luck_rng = LuckRng.new(rng, balance.luck_reroll_per_point, balance.luck_clamp)
	modifiers = ModifierStack.new(balance.luck_clamp)
	jackpot = ProgressiveJackpot.new(balance.jackpot_feed_rate, balance.jackpot_seed)
	rules = InteractionRules.new(balance)
	pickups = PickupSystem.new(economy)
	interactions = InteractionResolver.new(rules, world, economy, pickups, rng.fork())
	_build_schedule()
	var vip_ids: Array = []
	for sid: Variant in map_def.stations:
		if str(sid).begins_with("vip_"):
			vip_ids.append(StringName(sid))
	stations = StationManager.new()
	stations.setup(map_def.stations, _logic_scripts, balance, economy, modifiers, rng.fork(), jackpot, vip_ids)
	hot_tables = HotTableDirector.new(stations, balance, rng.fork())
	_logic_rng = rng.fork()
	items = ItemSystem.new(Registry.items, balance, state.players, economy, modifiers, rules, world, pickups, rng.fork())
	interactions.ko_shield = items.shield_knockout
	items.interactions = interactions
	items.unseat = stand_up
	items.limits = func() -> float: return stations._limits_multiplier
	items.on_vip_lost = _on_vip_pass_ended
	items.loot = loot
	items.setup_extras()
	items.jackpot = jackpot
	items.find_station = _nearest_station
	items.close_station = func(sid: StringName, seconds: float) -> void: stations.out_of_order[sid] = seconds
	items.clear_jail = clear_catch_count  # Jail system (v0.8.3)
	waiter = WaiterLogic.new(state.players, rules, world, SeededRng.new(seed_value ^ 0x3A11E5))
	megaphone = MegaphoneLogic.new(state.players, rules, world)
	# Initialize dealers for each blackjack and roulette station (v0.8.4)
	dealers.clear()
	for sid: StringName in stations.logics:
		var logic: StationLogicBase = stations.logics[sid]
		if logic.game_id == &"blackjack" or logic.game_id == &"roulette":
			var dealer_rng: SeededRng = SeededRng.new(seed_value ^ StringName(sid).hash())
			# For headless/testing: initialize dealer at a default position in front of the table
			# In actual gameplay, this will be updated by CasinoFloor._physics_process
			var dealer_pos: Vector3 = Vector3(0.0, 0.5, 0.5)  # A default position in front
			dealers[sid] = DealerLogic.new(sid, state.players, rules, world, dealer_rng, stations, dealer_pos)
	minigames.reset()
	minigame = null
	rewards = RewardDirector.new()
	_comped.clear()
	results_return_in = -1.0
	money_history = MoneyHistory.new()
	for id: int in state.players:
		_reset_stats(id)
		rules.status(id).away = not state.players[id].connected


func _build_schedule() -> void:
	schedule = MatchSchedule.new(state.minigames, state.gamble_s, balance.last_call_seconds)
	phases = PhaseMachine.new(schedule, balance.regroup_time)
	phases.phase_changed.connect(_on_phase_changed)


## Online room: wait in the entrance-hall lobby until everyone is ready (§2.2).
func open_lobby() -> void:
	room_mode = true


## Adds a participant and returns its player id. Colors are fixed and unique; `skin` is the
## player's saved character skin.
func add_player(uid: String, display_name: String, color_index: int = -1, skin: StringName = &"bean") -> int:
	var p := PlayerState.new()
	p.id = _next_player_id
	_next_player_id += 1
	p.uid = uid
	p.display_name = display_name
	# No color picker (Patrick, 2026-10-05): everyone gets the first free color and the client's
	# `color_index` wish is ignored. Skins are the only look players choose.
	p.color_index = lobby.free_color(_taken_colors(), -1)
	p.skin = skin if Cosmetics.is_valid_skin(skin) else &"bean"
	state.add_player(p)
	economy.add_player(p.id, balance.start_money)
	_reset_stats(p.id)
	money_history.add_player(p.id, balance.start_money)
	world.set_transform(p.id, Vector3.ZERO, 0.0)
	lobby.join(p.id, _uptime + p.id * 0.001)
	_emit(GameEvents.make(&"player_joined", {"player": p.to_wire()}))
	_check_leader()
	return p.id


## Number of seats taken (connected players), for "room full".
func occupied_slots() -> int:
	var n: int = 0
	for id: int in state.players:
		if state.players[id].connected:
			n += 1
	return n


## A client dropped: the avatar stays as "away" (§2.12), money and seat are kept.
func player_disconnected(player: int) -> void:
	if not state.players.has(player):
		return
	state.players[player].connected = false
	state.players[player].ready = false
	rules.status(player).away = true  # untouchable while away (§2.12)
	lobby.set_connected(player, false, _uptime)
	if minigame != null:
		minigame.remove_player(player)  # away players score 0 and get no minigame reward (§2.12)
	_emit(GameEvents.make(&"player_left", {"player": player}))
	_check_leader()
	_flush()


## The same identity came back.
func player_reconnected(player: int) -> void:
	if not state.players.has(player):
		return
	state.players[player].connected = true
	rules.status(player).away = false
	lobby.set_connected(player, true, _uptime)
	_emit(GameEvents.make(&"player_rejoined", {"player": player}))
	_check_leader()
	_flush()


func _taken_colors() -> Array[int]:
	var out: Array[int] = []
	for id: int in state.players:
		if state.players[id].connected:
			out.append(state.players[id].color_index)
	return out


func _check_leader() -> void:
	var now: int = lobby.leader()
	if now != _leader:
		_leader = now
		Log.info(&"server", "party leader is now player %d" % now)
		_emit(GameEvents.make(&"leader_changed", {"player": now}))


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
	if room_mode:
		# Lobby settings apply now: the match length rebuilds the schedule.
		settings["items_enabled"] = bool(lobby.settings["items_enabled"])
		_apply_length()
		if schedule.minigames != state.minigames or not is_equal_approx(schedule.segment_s, state.gamble_s):
			_build_schedule()
	running = true
	match_time = 0.0
	phases.start()
	money_history.start(schedule.duration_s, _balances())
	stations.set_limits_multiplier(balance.limits_multiplier(0))
	for id: int in state.players:
		rules.protect(id, match_time)
	_emit(GameEvents.make(&"match_started", {"seed": state.match_seed, "minigames": schedule.minigames, "gamble_s": schedule.segment_s, "duration_s": schedule.duration_s, "segment_s": schedule.segment_s}))
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
	snap["lobby"] = lobby.to_wire()
	snap["room"] = room_mode
	snap["effects"] = items.public_effects()
	snap["peels"] = items.peels_wire()
	snap["floor"] = {"puddles": waiter.wire(), "megaphone": megaphone.wire()}
	snap["shop"] = items.shop.wire() if items.shop != null else {}
	snap["hot_table"] = {"station": hot_tables.current, "time_left": snappedf(hot_tables.time_left, 0.01)} if hot_tables.current != &"" else {}
	if minigame != null:
		snap["minigame"] = minigame.get_public_state()
	if phases.phase == Phase.Id.REWARDS:
		snap["rewards"] = rewards.get_public_state()
	if phases.phase == Phase.Id.REGROUP:
		snap["regroup_in"] = snappedf(maxf(phases.phase_timer, 0.0), 0.01)
	if phases.phase == Phase.Id.RESULTS:
		snap["standings"] = get_standings()
		snap["awards"] = get_awards()
		snap["results_return_in"] = snappedf(results_return_in, 0.01)
	return snap


## Private data for one player (own station secrets, inventory offers).
func get_private_snapshot(player: int) -> Dictionary:
	var out: Dictionary = {"station": stations.private_state(player)}
	if minigame != null:
		out["minigame"] = minigame.private_state(player)
	out["items"] = items.private_state(player, match_time)
	return out


## Advances the simulation by real seconds (scaled by `timescale`), in fixed 20 Hz steps.
func advance(real_delta: float) -> void:
	_uptime += real_delta
	if not running:
		if room_mode and phases.phase == Phase.Id.LOBBY:
			_tick_lobby(real_delta)
		elif room_mode and phases.phase == Phase.Id.RESULTS and results_return_in > 0.0:
			results_return_in -= real_delta
			if results_return_in <= 0.0:
				return_to_lobby()
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
		_flush()
		elapsed += TICK


## Game-time step.
func _step(delta: float) -> void:
	match_time += delta
	var notes: Array[StringName] = phases.advance(delta)
	for n: StringName in notes:
		_on_phase_note(n)
	var casino_open: bool = phases.phase == Phase.Id.CASINO or phases.phase == Phase.Id.PRE_MINIGAME
	if casino_open:
		stations.closing_in = _closing_in()
		stations.tick(delta)
		hot_tables.tick(delta)
		_check_comps()
		money_history.tick(phases.casino_time, _balances())
	elif phases.phase == Phase.Id.MINIGAME and minigame != null:
		minigame.tick(delta, match_time)
		if minigame.is_finished():
			_finish_minigame()
	elif phases.phase == Phase.Id.REWARDS:
		rewards.tick(delta)
		if rewards.is_done():
			phases.rewards_finished()
	modifiers.expire(match_time)
	items.tick(match_time, casino_open)
	waiter.tick(match_time, casino_open)
	megaphone.tick(match_time)
	interactions.tick(match_time)
	_tick_jail(delta)
	pickups.tick(match_time)


func _tick_lobby(delta: float) -> void:
	match lobby.tick(delta):
		&"countdown_started":
			_emit(GameEvents.make(&"lobby_countdown", {"seconds": LobbyController.COUNTDOWN_SECONDS}))
		&"countdown_cancelled":
			_emit(GameEvents.make(&"lobby_countdown_cancelled", {}))
		&"start":
			start_match()


## Server time in seconds (real time since start; the network clock).
func uptime() -> float:
	return _uptime


func _on_phase_note(note: StringName) -> void:
	match note:
		&"last_call":
			stations.set_global_multiplier(balance.last_call_multiplier)
			_emit(GameEvents.make(&"last_call", {"seconds": balance.last_call_seconds, "multiplier": balance.last_call_multiplier}))
		&"minigame_due":
			_emit(GameEvents.make(&"minigame_warning", {"seconds": PhaseMachine.PRE_MINIGAME_SECONDS}))
		&"segment_ended":
			if phases.phase == Phase.Id.MINIGAME:
				_refund_and_stand_everyone()
			else:
				stations.auto_resolve_all()  # end of the match: open rounds play out
			items.end_segment()
			_emit(GameEvents.make(&"segment_ended", {"segment": phases.segment_index()}))
		&"minigame_started":
			_start_minigame()
		&"match_over":
			_finish_match()


func _on_phase_changed(from: Phase.Id, to: Phase.Id) -> void:
	Log.info(&"server", "phase %s (casino %.1f s, segment %d)" % [Phase.name_of(to), phases.casino_time, phases.segment_index()])
	if to == Phase.Id.CASINO:
		var seg: int = phases.segment_index()
		state.segment_index = seg
		stations.set_limits_multiplier(balance.limits_multiplier(seg))
		interactions.limits_multiplier = balance.limits_multiplier(seg)
		if from == Phase.Id.INTRO or from == Phase.Id.REGROUP:
			items.shop.restock(balance.limits_multiplier(seg))
			_emit(GameEvents.make(&"shop_restocked", items.shop.wire()))
		if from == Phase.Id.REGROUP:
			for id: int in state.players:
				rules.protect(id, match_time)
	_emit(GameEvents.make(&"phase_changed", {"phase": to, "from": from, "phase_name": Phase.name_of(to), "casino_time": snappedf(phases.casino_time, 0.001), "segment": phases.segment_index()}))
	if to == Phase.Id.REGROUP:
		_start_regroup()


## A minigame starts (Patrick's notes #9, #21): every open bet is refunded first (blackjack would
## auto-stand a hand on leave), then everyone seated is stood up.
func _refund_and_stand_everyone() -> void:
	stations.refund_all()
	_flush()
	for id: int in state.players:
		if stations.is_seated(id):
			stand_up(id, &"minigame")


## After the rewards everyone is back in the entrance hall (Patrick's note #10): holds end,
## ragdolls and knockouts are over, bodies go to their hall spot and the doors stay shut for
## `regroup_time` seconds. `regroup_started {seconds, positions: {player: [x, y, z]}}`.
func _start_regroup() -> void:
	interactions.regroup()
	_flush()
	var positions: Dictionary = {}
	for id: int in state.players:
		if stations.is_seated(id):
			stand_up(id, &"regroup")
		_server_owned.erase(id)
		var spot: Vector3 = map_def.lobby_spawn(id) if map_def != null else Vector3.INF
		if spot.is_finite():
			set_server_position(id, spot)
			positions[id] = Serializer.vec3(spot)
	_emit(GameEvents.make(&"regroup_started", {"seconds": balance.regroup_time, "positions": positions}))


func _finish_match() -> void:
	running = false
	hot_tables.stop()
	stations.set_global_multiplier(1.0)
	money_history.finish(_balances())
	var standings: Array[Dictionary] = get_standings()
	if room_mode:
		results_return_in = balance.results_return_time
	_emit(GameEvents.make(&"match_ended", {"standings": standings, "awards": get_awards(), "jackpot": jackpot.pot, "return_in": results_return_in}))


# --- Minigames & rewards -----------------------------------------------------------------------

func _start_minigame() -> void:
	# Release all jailed players when minigame starts (v0.8.3)
	for id: int in state.players:
		if state.players[id].jail_time_remaining > 0.0:
			release_from_jail(id)
	var players: Array[int] = []
	for id: int in state.players:
		if state.players[id].connected:
			players.append(id)
	minigame = minigames.begin(players, _logic_rng.fork(), balance, _quiz_stats(), half_rtt_provider) if minigames.has_minigames() and not players.is_empty() else null
	if minigame == null:
		_emit(GameEvents.make(&"minigame_skipped", {}))
		phases.minigame_finished()
		phases.rewards_finished()
		return
	_emit(GameEvents.make(&"minigame_started", {"minigame": minigames.current_def.id, "name": minigames.current_def.display_name, "rules": minigames.current_def.rules_text, "players": players}))
	_flush()


func _finish_minigame() -> void:
	var ranking: Array[Dictionary] = minigame.ranking()
	for row: Dictionary in ranking:
		var p: int = int(row["player"])
		if state.players.has(p):
			state.players[p].quiz_points += int(row.get("points", 0))
			state.players[p].quiz_correct_time += float(row.get("time", 0.0))
	# Jail system (v0.8.3): decrement catch count after each minigame
	for id: int in state.players:
		if state.players[id].catch_count > 0:
			state.players[id].catch_count -= 1
	_flush()
	minigame = null
	minigames.end()
	_emit(GameEvents.make(&"minigame_finished", {"ranking": ranking}))
	phases.minigame_finished()
	var played_segment: int = maxi(phases.segment_index() - 1, 0)
	rewards = RewardDirector.new()
	rewards.grant = func(p: int, item: StringName) -> void: items.give(p, item, match_time)
	# The House Comp is checked here too (W5), for the segment that starts after this minigame,
	# so the casino check later in that segment doesn't pay it twice.
	var seg: int = phases.segment_index()
	rewards.start(ranking, economy, loot, bool(settings.get("items_enabled", true)), balance.limits_multiplier(played_segment), balance, _logic_rng.fork(), state.players, func(p: int) -> int: return _try_comp(p, seg, false))
	_flush()


## Match stats the dynamic quiz questions draw from.
func _quiz_stats() -> Dictionary:
	var players: Dictionary = {}
	for id: int in state.players:
		players[id] = {"name": state.players[id].display_name, "balance": economy.balance(id), "won_by_game": (stats[id]["won_by_game"] as Dictionary).duplicate()}
	return {"players": players, "game_names": _game_names()}


func _game_names() -> Dictionary:
	var out: Dictionary = {}
	for id: StringName in Registry.games:
		out[id] = Registry.games[id].display_name
	return out


# --- Casino rules: comps, closing tables -------------------------------------------------------

## Seconds until the casino closes (pre-minigame warning or the final seconds of the match);
## INF otherwise. Bets whose round would not finish in time are refused ("Table closing!").
func _closing_in() -> float:
	if phases.phase == Phase.Id.PRE_MINIGAME:
		return phases.phase_timer
	var left: float = phases.time_left()
	return left if left <= PhaseMachine.PRE_MINIGAME_SECONDS else INF


## House Comp (§2.1): below the comp threshold (× table limits), nothing in play → once per
## segment, $300 growing by $150 per minigame played up to $900 (`BalanceConfig.comp_amounts`).
func _check_comps() -> void:
	var seg: int = phases.segment_index()
	for id: int in state.players:
		_try_comp(id, seg, true)


## Pays the House Comp to a broke player once per segment. Returns the amount (0 = none).
## `toast`: also emit `house_comp` (the reward screen shows its own row instead and emits it too,
## flagged `rewards: true`, for the feed and stats).
func _try_comp(id: int, seg: int, toast: bool) -> int:
	var p: PlayerState = state.players.get(id, null)
	if p == null or not p.connected or _comped.get(id, -1) == seg:
		return 0
	var threshold: int = int(floor(balance.comp_threshold * balance.limits_multiplier(seg)))
	if economy.balance(id) >= threshold or stations.has_stake(id) or interactions.is_held(id):
		return 0
	var amount: int = balance.comp_amount_for(seg)
	if amount <= 0:
		return 0
	_comped[id] = seg
	economy.apply(id, amount, &"house_comp", &"house")
	if stats.has(id):
		stats[id]["comps"] = int(stats[id]["comps"]) + 1
	_emit(GameEvents.make(&"house_comp", {"player": id, "amount": amount, "rewards": not toast}))
	return amount


# --- Results & play again ----------------------------------------------------------------------

## Fun awards for the results screen (§2.11): up to 4, each to a different player where possible.
func get_awards() -> Array[Dictionary]:
	for row: Dictionary in get_standings():
		if stats.has(int(row["player"])):
			stats[int(row["player"])]["final_rank"] = int(row["rank"])
	return Awards.pick(stats, _names(), 4)


func _balances() -> Dictionary:
	var out: Dictionary = {}
	for id: int in state.players:
		out[id] = economy.balance(id)
	return out


func _names() -> Dictionary:
	var out: Dictionary = {}
	for id: int in state.players:
		out[id] = state.players[id].display_name
	return out


## Online room: back to the entrance-hall lobby for another match with the same people (the
## leader's choice on the results screen, or automatically after `results_return_time`).
func return_to_lobby() -> void:
	if not room_mode or phases.phase != Phase.Id.RESULTS:
		return
	running = false
	economy = Economy.new()
	for id: int in state.players:
		economy.add_player(id, balance.start_money)
		var p: PlayerState = state.players[id]
		p.inventory.clear()
		p.quiz_points = 0
		p.quiz_correct_time = 0.0
		p.biggest_win = 0
		p.station = &""
		p.seat = -1
		p.ready = false
		p.catch_count = 0
		p.jail_time_remaining = 0.0
		p.jail_fine = 0
		lobby.set_on_pad(id, false)
		lobby.set_panel_ready(id, false)
	_server_owned.clear()
	_accumulator = 0.0
	match_time = 0.0
	_apply_length()
	_build_match_systems(0)
	_emit(GameEvents.make(&"match_reset", {"minigames": state.minigames, "gamble_s": state.gamble_s, "duration_s": state.duration_s}))
	_flush()


func _reset_stats(id: int) -> void:
	stats[id] = {"won_by_game": {}, "biggest_bet": 0, "biggest_win": 0, "biggest_loss": 0, "knockouts_suffered": 0,
		"thrown_out": 0, "shaken_out": 0, "quiz_points": 0, "comps": 0, "lowest_rank": 1, "final_rank": 1,
		"jackpot_won": 0, "knockouts_dealt": 0, "times_shoved": 0, "loss_streak": 0, "losing_now": 0}


## Final ranking: money, then quiz points, then biggest win; ties share placement.
func get_standings() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for id: int in state.players:
		var p: PlayerState = state.players[id]
		rows.append({"player": id, "name": p.display_name, "money": economy.balance(id), "quiz_points": p.quiz_points, "biggest_win": p.biggest_win})
		if not running and money_history.samples() > 0:
			rows[-1]["series"] = money_history.of(id)  # results graph: ~60 ints per player at most
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
			if stations.vip.get(sid, false) and economy.balance(player) < vip_threshold() and not modifiers.has_flag(player, &"vip_pass"):
				return StationLogicBase.fail(&"vip_denied")
			var res: Dictionary = stations.sit(player, sid)
			if res["ok"]:
				rules.status(player).seated = true
				state.players[player].station = sid
				state.players[player].seat = _free_seat(sid, player)
				_emit(GameEvents.make(&"player_sat", {"player": player, "station": sid, "seat": state.players[player].seat}))
			return res
		&"leave":
			return stand_up(player)
		&"place_bet", &"clear_bets", &"action":
			return stations.route(player, intent)
		&"move":
			if not can_move(player):
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
			var glove: bool = modifiers.has_flag(player, &"spring_glove", &"spring_glove")
			# Optional "target": who the client swung at (older clients leave it out).
			var hint: int = int(intent.get("target", -1)) if typeof(intent.get("target", -1)) in [TYPE_INT, TYPE_FLOAT] else -1
			var shoved: Dictionary = interactions.shove(player, Serializer.to_vec3(intent["aim"]), match_time, glove, hint)
			if glove and shoved["ok"]:
				modifiers.consume_round(player, &"spring_glove")
			if shoved["ok"]:
				items.pass_monkey(player, int(shoved["target"]), match_time)
			elif shoved["error"] == &"no_target":
				# Try waiter or dealer
				if waiter.shove(player, Serializer.to_vec3(intent["aim"]), match_time):
					return StationLogicBase.OK_RESULT  # nobody to push, but the waiter goes flying
				# Try dealer at any table with a dealer
				var dealer_hit: bool = false
				for sid: StringName in dealers:
					if dealers[sid].shove(player, Serializer.to_vec3(intent["aim"]), match_time):
						# Dealer attacked! Go to jail and refund bets.
						put_in_jail(player)
						dealer_hit = true
						break
				if dealer_hit:
					return StationLogicBase.OK_RESULT  # dealer attacked
			return shoved
		&"shake":
			if stations.is_seated(player) or rules.is_knocked_down(player, match_time):
				return StationLogicBase.fail(&"not_standing")
			return interactions.shake(player, match_time)
		&"break_free":
			return interactions.break_free(player, match_time)
		&"megaphone":
			return megaphone.take(player, match_time)
		&"emote":
			if not Emotes.has(StringName(str(intent["id"]))):
				return StationLogicBase.fail(&"unknown_emote")
			_emit(GameEvents.make(&"emote", {"player": player, "id": StringName(intent["id"])}))
			return StationLogicBase.OK_RESULT
		&"submit_answer":
			if minigame == null:
				return StationLogicBase.fail(&"too_late")
			return minigame.submit(player, intent, match_time)
		&"use_item":
			if not bool(settings.get("items_enabled", true)):
				return StationLogicBase.fail(&"items_off")
			var opts: Dictionary = {}
			if intent.has("option"):
				opts["option"] = int(intent["option"])
			return items.use(player, int(intent["slot"]), int(intent.get("target", -1)), match_time, opts)
		&"discard_item":
			return items.discard(player, int(intent["slot"]), match_time)
		&"rps_answer":
			return items.duels.answer(player, int(intent["duel"]), bool(intent["accept"]), match_time)
		&"rps_pick":
			return items.duels.pick(player, int(intent["duel"]), int(intent["pick"]), match_time)
		&"shop_buy":
			var shop_pos: Vector3 = map_def.shop_position
			if shop_pos.is_finite() and world.get_position(player).distance_to(shop_pos) > map_def.interact_range:
				return StationLogicBase.fail(&"too_far")
			return items.buy(player, int(intent["index"]), match_time)
		&"return_to_lobby":
			if player != lobby.leader():
				return StationLogicBase.fail(&"not_leader")
			if not room_mode:
				return StationLogicBase.fail(&"not_room")
			return_to_lobby()
			return StationLogicBase.OK_RESULT
		&"set_ready":
			lobby.set_panel_ready(player, bool(intent["ready"]))
			_sync_ready(player)
			return StationLogicBase.OK_RESULT
		&"set_skin":
			var skin: StringName = StringName(intent["skin"])
			if not Cosmetics.is_valid_skin(skin):
				return StationLogicBase.fail(&"bad_value")
			(state.players[player] as PlayerState).skin = skin
			_emit(GameEvents.make(&"player_skin", {"player": player, "skin": skin}))
			return StationLogicBase.OK_RESULT
		&"lobby_setting":
			var err: StringName = lobby.set_setting(player, str(intent["key"]), intent["value"])
			if err != &"":
				return StationLogicBase.fail(err)
			_emit(GameEvents.make(&"lobby_settings", {"settings": lobby.settings.duplicate()}))
			return StationLogicBase.OK_RESULT
	return StationLogicBase.fail(&"not_implemented")


## Gets a seated player off their seat, exactly like their own "leave" (a round in play is settled
## by the station the same way). Items that knock people down use it on seated targets; the
## server uses it with a `reason` (minigame, regroup, thrown_out, vip_pass_ended).
func stand_up(player: int, reason: StringName = &"") -> Dictionary:
	var res: Dictionary = stations.leave(player)
	if res["ok"]:
		rules.status(player).seated = false
		state.players[player].station = &""
		state.players[player].seat = -1
		var ev: Dictionary = {"player": player}
		if reason != &"":
			ev["reason"] = reason
		_emit(GameEvents.make(&"player_stood", ev))
	return res


## True while the player's own client drives their body (standing, not held or ragdolled).
func can_move(player: int) -> bool:
	return not (stations.is_seated(player) or rules.is_knocked_down(player, match_time) or interactions.is_held(player) or _server_owned.get(player, false))


## Online movement report (unreliable stream, not rate-limited like intents). Returns false when
## the move was refused and the client must be snapped back to `sanity.last_good(player)`.
func apply_move(player: int, pos: Vector3, yaw: float, airborne: bool) -> bool:
	if not state.players.has(player) or not can_move(player):
		return true  # ignored, not a cheat: the server owns the body right now
	if not sanity.check(player, pos, _uptime):
		return false
	world.set_transform(player, pos, yaw, airborne)
	state.players[player].position = pos
	return true


## The server simulates this player's body (ragdoll/thrown) or hands it back to the client.
func set_server_owned(player: int, owned: bool) -> void:
	_server_owned[player] = owned


func is_server_owned(player: int) -> bool:
	return _server_owned.get(player, false)


## The scene got a ragdolled player back on their feet at `pos`: authority returns to the client.
func report_got_up(player: int, pos: Vector3) -> void:
	if not state.players.has(player):
		return
	_server_owned.erase(player)
	set_server_position(player, pos)
	_emit(GameEvents.make(&"player_got_up", {"player": player, "pos": Serializer.vec3(pos)}))


## A thrown-out player walks back in at `pos`.
func report_respawned(player: int, pos: Vector3) -> void:
	if not state.players.has(player):
		return
	_server_owned.erase(player)
	set_server_position(player, pos)
	_emit(GameEvents.make(&"player_respawned", {"player": player, "pos": Serializer.vec3(pos)}))


## Lobby: a player stepped on or off their ready pad.
func report_on_pad(player: int, on: bool) -> void:
	if lobby.set_on_pad(player, on):
		_sync_ready(player)


func _sync_ready(player: int) -> void:
	var ready: bool = lobby.is_ready(player)
	if state.players[player].ready != ready:
		state.players[player].ready = ready
		_emit(GameEvents.make(&"player_ready", {"player": player, "ready": ready}))


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
	sanity.allow_teleport(player, pos, _uptime)


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
	batch.append_array(hot_tables.drain_events())
	if minigame != null:
		batch.append_array(minigame.drain_events())
	batch.append_array(rewards.drain_events())
	batch.append_array(items.drain_events())
	batch.append_array(waiter.drain_events())
	batch.append_array(megaphone.drain_events())
	for sid: StringName in dealers:
		batch.append_array(dealers[sid].drain_events())
	var caught: Array[Dictionary] = []
	for ev: Dictionary in batch:
		_track_stats(ev)
		_emit(ev)
		if ev["type"] == &"fake_cash_used" and bool(ev["caught"]):
			caught.append(ev)
	for ev: Dictionary in caught:
		_fake_cash_caught(int(ev["player"]), int(ev["amount"]))
	if not caught.is_empty():
		_flush()


func _track_stats(ev: Dictionary) -> void:
	match ev["type"]:
		&"round_result":
			var p: int = ev["player"]
			if not stats.has(p):
				return
			var net: int = int(ev["net"])
			if state.players.has(p):
				state.players[p].biggest_win = maxi(state.players[p].biggest_win, net)
			var st: Dictionary = stats[p]
			st["biggest_win"] = maxi(int(st["biggest_win"]), net)
			st["biggest_loss"] = maxi(int(st["biggest_loss"]), -net)
			st["losing_now"] = int(st["losing_now"]) + 1 if net < 0 else 0 if net > 0 else int(st["losing_now"])
			st["loss_streak"] = maxi(int(st["loss_streak"]), int(st["losing_now"]))
			if net > 0:
				var game: StringName = stations.game_of.get(StringName(ev["station"]), &"")
				st["won_by_game"][game] = int(st["won_by_game"].get(game, 0)) + net
		&"bet_placed":
			if stats.has(int(ev["player"])):
				stats[int(ev["player"])]["biggest_bet"] = maxi(int(stats[int(ev["player"])]["biggest_bet"]), int(ev["amount"]))
		&"player_knocked_out":
			if stats.has(int(ev["target"])):
				stats[int(ev["target"])]["knockouts_suffered"] += 1
			if stats.has(int(ev.get("attacker", -1))) and int(ev["attacker"]) != int(ev["target"]):
				stats[int(ev["attacker"])]["knockouts_dealt"] += 1
		&"player_shoved":
			if stats.has(int(ev["target"])):
				stats[int(ev["target"])]["times_shoved"] += 1
		&"jackpot_won":
			if stats.has(int(ev["player"])):
				stats[int(ev["player"])]["jackpot_won"] += int(ev["amount"])
		&"player_thrown_out":
			if stats.has(int(ev["target"])):
				stats[int(ev["target"])]["thrown_out"] += 1
		&"chips_shaken_out":
			if stats.has(int(ev["attacker"])):
				stats[int(ev["attacker"])]["shaken_out"] += int(ev["amount"])
		&"quiz_finished":
			for row: Dictionary in ev["ranking"]:
				if stats.has(int(row["player"])):
					stats[int(row["player"])]["quiz_points"] += int(row["points"])
		&"money_changed":
			_track_ranks()


func _emit(ev: Dictionary) -> void:
	state.event_seq += 1
	ev["seq"] = state.event_seq
	ev["t"] = snappedf(match_time, 0.001)
	event_log.append(ev)
	if event_log.size() > 2000:
		event_log = event_log.slice(event_log.size() - 1000)
	event_emitted.emit(ev)


## Lowest rank each player sank to (for the Comeback Kid award).
func _track_ranks() -> void:
	if not running:
		return
	var money: Array = []
	for id: int in state.players:
		money.append(economy.balance(id))
	for id: int in state.players:
		if not stats.has(id):
			continue
		var mine: int = economy.balance(id)
		var rank: int = 1 + money.filter(func(m: int) -> bool: return m > mine).size()
		stats[id]["lowest_rank"] = maxi(int(stats[id]["lowest_rank"]), rank)


## Lowest seat index at `sid` no other seated player holds.
func _free_seat(sid: StringName, player: int) -> int:
	var logic: StationLogicBase = stations.logics.get(sid, null)
	if logic is BlackjackLogic and (logic as BlackjackLogic).seats.has(player):
		return (logic as BlackjackLogic).seats.find(player)  # the hand's own seat
	var used: Dictionary = {}
	for id: int in state.players:
		if id != player and state.players[id].station == sid:
			used[state.players[id].seat] = true
	var i: int = 0
	while used.has(i):
		i += 1
	return i


## The bouncer spotted Fake Cash: the player pays the same amount as a fine (as far as they can)
## and gets thrown out (the bet stays in and settles normally).
func _fake_cash_caught(player: int, amount: int) -> void:
	var fine: int = economy.take_up_to(player, amount, &"fake_cash_fine")
	_emit(GameEvents.make(&"fake_cash_caught", {"player": player, "fine": fine}))
	if stations.is_seated(player):
		stand_up(player, &"thrown_out")
	interactions.report_thrown_out(player, &"bouncer", match_time)


## Nearest station whose interaction point is within `range_m` of the player (&"" = none).
func _nearest_station(player: int, range_m: float) -> StringName:
	var pos: Vector3 = world.get_position(player)
	var best: StringName = &""
	var best_d: float = range_m
	for sid: Variant in map_def.station_positions:
		var d: float = (Vector3(map_def.station_positions[sid]) - pos).length()
		if d <= best_d and stations.logics.has(StringName(sid)):
			best_d = d
			best = StringName(sid)
	return best


## Money needed to sit at a VIP table right now.
func vip_threshold() -> int:
	return int(floor(balance.vip_entry_money * stations._limits_multiplier))


## An Early VIP Pass ran out: a player at a VIP table who couldn't afford it is walked out.
func _on_vip_pass_ended(player: int) -> void:
	var sid: StringName = stations.station_of(player)
	if sid == &"" or not stations.vip.get(sid, false) or economy.balance(player) >= vip_threshold():
		return
	stand_up(player, &"vip_pass_ended")


# --- Jail system (v0.8.3) ---


## Jail timing and fine amounts based on catch_count: [8s, 15s, 25s, 40s] and [$100, $200, $400, $800]
const JAIL_TIMES: Array[float] = [8.0, 15.0, 25.0, 40.0]
const JAIL_FINES: Array[int] = [100, 200, 400, 800]


## The guard catches a player and puts them in jail. Increases catch count and applies jail timer/fine.
func put_in_jail(player: int) -> void:
	if not state.players.has(player) or state.players[player].jail_time_remaining > 0.0:
		return  # already in jail
	var p: PlayerState = state.players[player]
	# Stand them up and release any holds
	if stations.is_seated(player):
		stand_up(player, &"caught")
	if interactions.is_held(player):
		interactions.release(player, false, Vector3.ZERO, match_time)
	# Get jail time and fine based on catch count (capped at 3+)
	var level: int = mini(p.catch_count, JAIL_TIMES.size() - 1)
	p.jail_time_remaining = JAIL_TIMES[level]
	p.jail_fine = JAIL_FINES[level]
	p.catch_count += 1
	_emit(GameEvents.make(&"player_jailed", {"player": player, "time": snappedf(p.jail_time_remaining, 0.01), "fine": p.jail_fine, "catch_count": p.catch_count}))


## Release a jailed player and deduct the fine from their balance (never below $0).
func release_from_jail(player: int) -> void:
	if not state.players.has(player) or state.players[player].jail_time_remaining <= 0.0:
		return  # not in jail
	var p: PlayerState = state.players[player]
	var fine: int = p.jail_fine
	p.jail_time_remaining = 0.0
	p.jail_fine = 0
	var deducted: int = economy.take_up_to(player, fine, &"jail_fine")
	_emit(GameEvents.make(&"player_released_from_jail", {"player": player, "fine": deducted}))


## Reset a player's catch count to 0 (used by Get Out of Jail Free item).
func clear_catch_count(player: int) -> void:
	if not state.players.has(player):
		return
	state.players[player].catch_count = 0
	if state.players[player].jail_time_remaining > 0.0:
		release_from_jail(player)
	_emit(GameEvents.make(&"catch_count_cleared", {"player": player}))


## Advance jail timers and release players when time is up.
func _tick_jail(delta: float) -> void:
	for id: int in state.players:
		var p: PlayerState = state.players[id]
		if p.jail_time_remaining > 0.0:
			p.jail_time_remaining -= delta
			if p.jail_time_remaining <= 0.0:
				release_from_jail(id)
