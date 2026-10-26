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
## The rules briefing before a minigame: the logic doesn't tick and refuses input until everyone
## playing sent `minigame_ready` or the briefing ran out (`minigame_briefing` seconds, default 30).
var briefing_left: float = 0.0
var ready_players: Dictionary = {}
var rewards: RewardDirector = RewardDirector.new()
var hot_tables: HotTableDirector
var loot: LootTables
var items: ItemSystem
## The Odd Jobs button-smash cabinet next to the Gift Shop (broke players earn $50 a bar).
var odd_jobs: OddJobs
## The waiter NPC's trips and drink puddles, and the Megaphone prop by the Gift Shop (M7, npc/).
var waiter: WaiterLogic
var megaphone: MegaphoneLogic
## Dealers at blackjack, roulette and craps tables (v0.8.4, npc/): station_id → DealerLogic.
var dealers: Dictionary[StringName, DealerLogic] = {}
## Online room: drops a kicked player's connection (`RoomHost.kick_player`; tests leave it unset).
var kick_handler: Callable
## Smoothed half round-trip time of a player in seconds (set by the network layer; 0 offline).
var half_rtt_provider: Callable = func(_p: int) -> float: return 0.0
## Per-player match stats for awards and dynamic quiz questions.
var stats: Dictionary[int, Dictionary] = {}
## Balance samples over casino time for the results graph (in `match_ended` standings rows).
var money_history: MoneyHistory = MoneyHistory.new()
## Results screen: seconds until an online room goes back to its lobby on its own.
var results_return_in: float = -1.0
## The last finished match's XP/Coins rows, player → `Progression.breakdown` (in `match_ended`
## and the results snapshot), and its id: clients add their row to their profile once per id.
var progress: Dictionary = {}
var match_id: String = ""
var _matches_finished: int = 0
## Tells this server's matches apart from another run's (`match_id`).
var _instance_token: int = Time.get_ticks_usec() ^ int(Time.get_unix_time_from_system())
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
## Simulated seconds ever stepped (never reset, unlike `match_time`).
var _stepped: float = 0.0
var _leader: int = -1
## player → casino segment in which they got the House Comp (once per segment).
var _comped: Dictionary[int, int] = {}
var _logic_rng: SeededRng
## Kicked uids → server uptime until which they may not come back (Protocol.KICK_REJOIN_SECONDS).
var _kicked: Dictionary[String, float] = {}
## Who the current/last minigame started with (late joiners are not in it; the snapshot tells
## them to sit it out). Kept through its rewards.
var _minigame_roster: Array[int] = []
## player → [emote id, server uptime it started]: the emote each player acted out last, so a
## late joiner's snapshot can replay one still playing (`emotes`). Cosmetic only.
var _emotes: Dictionary[int, Array] = {}
## Walkable minigame ("W", minigames/common/walkable_logic_base.gd) whose room is up: set when it
## starts, kept through its rewards (everyone still stands in the room) and dropped at the regroup.
## While set, positions are clamped to the room and casino intents are refused (`minigame`).
var _room: WalkableLogicBase = null
## The waiting room's play-money games while an online room waits in LOBBY (null otherwise, and
## for maps without one). Its own ledger: see `FunRoom`.
var fun_room: FunRoom = null
## The casino floor of this round (docs/FLOOR_PLAN.md): the layout standing (its id, &"" on a map
## without layouts), its stations in wire form {station id: [game, [x, y, z], yaw degrees]}, and
## how many floors this match has put in. Online rooms take the next layout from the rotation when
## the lobby opens and at every regroup; Practice keeps the full floor (the first layout).
var floor_plan: Dictionary = {}
var floor_layout: StringName = &""
var floor_round: int = 0
## The layouts and their rules (Registry.floor_plan unless a test sets its own).
var floor_config: FloorPlanConfig
## Called with the new plan right after the server switched floors (the host's map rebuilds and
## refills the station seats in `map_def`; tests leave it unset).
var floor_changed: Callable
## Stations that never move with the floor layouts (the horse race, the VIP lounge): station id →
## game id.
var _fixed_stations: Dictionary = {}
## The shuffled bag of layouts (seeded from the match seed), and each layout's fit on this map
## (layout id → its problems, `FloorPlan.problems`; measured once per match).
var _floor_rotation: FloorRotation
var _layout_fit: Dictionary = {}


## Wires balance/presets/registry data. Call before `add_player`/`start_match`.
func configure(p_settings: Dictionary, p_balance: BalanceConfig, p_presets: MatchPresets, logic_scripts: Dictionary, p_map: MapDefinition) -> void:
	settings.merge(p_settings, true)
	balance = p_balance
	presets = p_presets
	map_def = p_map
	_logic_scripts = logic_scripts
	lobby.presets = presets
	settings["mode"] = MatchMode.normalize(settings.get("mode", MatchMode.CASINO))
	lobby.settings["mode"] = settings["mode"]
	lobby.settings["minigames"] = int(settings.get("minigames", presets.default_minigames))
	lobby.settings["gamble_minutes"] = int(settings.get("gamble_minutes", presets.default_gamble_minutes))
	_apply_length()
	# Which minigames are in the rotation: the lobby's `minigame_pool` ("quiz,vote_race"; empty =
	# every minigame), seeded from the settings (dev/tests pin it there) and changed by the host.
	lobby.known_minigames.clear()
	for id: StringName in Registry.minigames:
		lobby.known_minigames.append(String(id))
	lobby.settings["minigame_pool"] = LobbyController.normalize_pool(settings.get("minigame_pool", ""), lobby.known_minigames)
	minigames = MinigameDirector.new(MinigameDirector.pool_defs(Registry.minigames, lobby.settings["minigame_pool"]), Registry.quiz_bank)
	var rarities: Dictionary[StringName, int] = {}
	for id: StringName in Registry.items:
		if Registry.items[id].in_loot:
			rarities[id] = Registry.items[id].rarity
	loot = LootTables.new(Registry.loot, rarities)
	for id: StringName in rarities:
		if Registry.items[id].target_mode == ItemDefinition.TargetMode.LEADER:
			loot.leader_only.append(id)
	lobby.settings["items_enabled"] = bool(settings.get("items_enabled", true))
	if MatchMode.is_minigames_only(settings):
		settings["items_enabled"] = false  # no casino to use them in
	if floor_config == null:
		floor_config = Registry.floor_plan
	_fixed_stations = map_def.stations.duplicate()
	if map_def.has_floor_plan():
		for sid: Variant in map_def.floor_layouts[0].stations:
			_fixed_stations.erase(StringName(sid))
	floor_plan = _full_floor()  # the map scene was built with the full floor
	_build_match_systems(int(settings.get("seed", 0)))
	Log.info(&"server", "configured: %d minigames, %.0f s gambling between, seed %d, %d stations" % [state.minigames, state.gamble_s, state.match_seed, stations.logics.size()])


## Match length from the lobby settings (`minigames`, `gamble_minutes`) or the dev override
## `settings.gamble_seconds` (Patrick's note #12).
func _apply_length() -> void:
	state.minigames = int(lobby.settings.get("minigames", presets.default_minigames))
	if MatchMode.is_minigames_only(settings):
		state.minigames = maxi(state.minigames, 1)
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
	# The full floor first; `_new_floor` below puts in the rotation's first layout where the match
	# rotates them (a seed of its own, so the rotation never shifts the match's other streams).
	_floor_rotation = FloorRotation.new(_rotation_ids(), SeededRng.new(seed_value ^ 0xF1002), _full_layout_id())
	_layout_fit.clear()
	floor_round = 0
	if map_def.has_floor_plan():
		_set_floor_stations(_full_floor())
		floor_layout = _full_layout_id()
	stations = StationManager.new()
	stations.setup(map_def.stations, _logic_scripts, balance, economy, modifiers, rng.fork(), jackpot, _vip_ids())
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
	odd_jobs = OddJobs.new(economy)
	items.jackpot = jackpot
	items.find_station = _nearest_station
	items.close_station = func(sid: StringName, seconds: float) -> void: stations.out_of_order[sid] = seconds
	items.clear_jail = clear_catch_count  # Jail system (v0.8.3)
	waiter = WaiterLogic.new(state.players, rules, world, SeededRng.new(seed_value ^ 0x3A11E5))
	megaphone = MegaphoneLogic.new(state.players, rules, world)
	_build_dealers()
	minigames.reset()
	minigame = null
	_room = null
	sanity.close_room()
	rewards = RewardDirector.new()
	_comped.clear()
	results_return_in = -1.0
	money_history = MoneyHistory.new()
	for id: int in state.players:
		_reset_stats(id)
		rules.status(id).away = not state.players[id].connected
	if draws_floor():
		_new_floor()
	elif map_def.has_floor_plan() and floor_changed.is_valid():
		floor_changed.call(floor_plan)  # Play Again without a rotation: back to the full floor


## Dealers at each blackjack and roulette table (v0.8.4), again whenever the floor changes.
func _build_dealers() -> void:
	dealers.clear()
	for sid: StringName in stations.logics:
		var logic: StationLogicBase = stations.logics[sid]
		if DealerLogic.OFFSETS.has(logic.game_id):
			var dealer_rng: SeededRng = SeededRng.new(state.match_seed ^ StringName(sid).hash())
			dealers[sid] = DealerLogic.new(sid, state.players, rules, world, dealer_rng, stations, map_def, DealerLogic.OFFSETS[logic.game_id])


func _vip_ids() -> Array:
	var vip_ids: Array = []
	for sid: Variant in map_def.stations:
		if str(sid).begins_with("vip_"):
			vip_ids.append(StringName(sid))
	return vip_ids


# --- Floor layouts (docs/FLOOR_PLAN.md) -------------------------------------------------------

## True when this match rotates the floor layouts at each casino round start: the map has layouts,
## and it is an online room (`FloorPlanConfig.rotate_in_rooms`) or Practice with
## `rotate_in_practice`. The `floor` setting overrides: "random" always rotates (dev/tests), "full"
## never does, and a layout id puts that layout in every round (dev renders).
func draws_floor() -> bool:
	if not map_def.has_floor_plan():
		return false
	var forced: String = String(settings.get("floor", ""))
	match forced:
		"random":
			return true
		"full":
			return false
	if forced != "" and map_def.floor_layout(StringName(forced)) != null:
		return true
	return floor_config.rotate_in_rooms if room_mode else floor_config.rotate_in_practice


## The full floor (the map's first layout) in wire form.
func _full_floor() -> Dictionary:
	return map_def.floor_layouts[0].wire_stations() if map_def.has_floor_plan() else {}


func _full_layout_id() -> StringName:
	return map_def.floor_layouts[0].id if map_def.has_floor_plan() else &""


## The layouts in the rotation: the map's enabled ones, in order.
func _rotation_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for l: FloorLayout in map_def.floor_layouts:
		if l != null and l.enabled:
			out.append(l.id)
	return out


## Why a layout can't stand tonight (empty when it can): a game of it is off or unknown, or it
## does not fit this map (`FloorPlan.problems`; the geometry is checked once per match).
func layout_problems(layout_id: StringName) -> Array[String]:
	var layout: FloorLayout = map_def.floor_layout(layout_id)
	var out: Array[String] = FloorPlan.problems(layout, floor_config, Registry.games)
	if layout == null or not out.is_empty():
		return out
	if not _layout_fit.has(layout_id):
		var geo: FloorGeometry = FloorGeometry.of_map(map_def, floor_config.gap)
		var fit: Array[String] = []
		if geo != null:
			fit = FloorPlan.fit_problems(layout.wire_stations(), geo)
		_layout_fit[layout_id] = fit
		for why: String in fit:
			Log.warn(&"server", "floor layout %s skipped: %s" % [layout_id, why])
	out.append_array(_layout_fit[layout_id] as Array[String])
	return out


## Puts in the next layout from the rotation (one that can be used tonight; a layout pinned by the
## `floor` setting instead) and switches the casino to it.
func _new_floor() -> void:
	var pinned: StringName = StringName(String(settings.get("floor", "")))
	var next: StringName
	if map_def.floor_layout(pinned) != null:
		next = pinned
	else:
		next = _floor_rotation.next(func(id: StringName) -> bool: return layout_problems(id).is_empty())
	var layout: FloorLayout = map_def.floor_layout(next)
	if layout == null:
		layout = map_def.floor_layouts[0]
	_apply_floor(layout.wire_stations(), layout.id)


## Switches the casino to a floor layout (wire form; `layout_id` names it). Anyone still seated at
## a table that goes or moves is stood up first and their open bets refunded (nobody should be:
## bets are refunded and seats emptied when the minigame starts, and again at the regroup); a
## table that moves is a fresh table in its new place, and a hot table that goes or moves cools.
func _apply_floor(plan: Dictionary, layout_id: StringName = &"") -> void:
	for id: int in state.players:
		var sid: StringName = stations.station_of(id)
		if sid != &"" and not _fixed_stations.has(sid) and plan.get(sid, []) != floor_plan.get(sid, []):
			stand_up(id, &"floor_changed")
	var moved: Array[StringName] = []
	for sid: Variant in plan:
		if floor_plan.has(sid) and plan[sid] != floor_plan[sid]:
			moved.append(StringName(sid))
	_set_floor_stations(plan)
	floor_layout = layout_id
	floor_round += 1
	stations.apply_stations(map_def.stations, _vip_ids(), moved)
	if hot_tables != null and hot_tables.current != &"" and (not stations.logics.has(hot_tables.current) or hot_tables.current in moved):
		hot_tables.stop()
	_build_dealers()
	Log.info(&"server", "floor %d: layout %s, %d stations" % [floor_round, layout_id, plan.size()])
	if floor_changed.is_valid():
		floor_changed.call(floor_plan)


## Points the map definition at a plan: its stations (the fixed ones plus the plan's), where they
## stand and face (from the plan) and their seats (kept for stations that stay put; the host's
## map refills the rest through `floor_changed`).
func _set_floor_stations(plan: Dictionary) -> void:
	var all: Dictionary = _fixed_stations.duplicate()
	var positions: Dictionary = {}
	var yaws: Dictionary = {}
	var seats: Dictionary = {}
	for sid: Variant in _fixed_stations:
		for pair: Array in [[map_def.station_positions, positions], [map_def.station_yaws, yaws], [map_def.station_seats, seats]]:
			if (pair[0] as Dictionary).has(sid):
				pair[1][sid] = pair[0][sid]
	for sid: Variant in plan:
		var entry: Array = plan[sid]
		all[StringName(sid)] = FloorPlan.game_of(entry)
		positions[StringName(sid)] = FloorPlan.pos_of(entry)
		yaws[StringName(sid)] = FloorPlan.yaw_of(entry)
		if map_def.station_seats.has(sid) and floor_plan.get(sid, []) == entry:
			seats[StringName(sid)] = map_def.station_seats[sid]
	# New dictionaries: a duplicated MapDefinition shares them with the registry's.
	map_def.stations = all
	map_def.station_positions = positions
	map_def.station_yaws = yaws
	map_def.station_seats = seats
	floor_plan = plan.duplicate(true)


## The floor for the wire (events, snapshot): {round, layout, stations: {station id: [game,
## [x, y, z], yaw degrees]}}. Clients build the casino's stations from it.
func floor_wire() -> Dictionary:
	return {"round": floor_round, "layout": floor_layout, "stations": floor_plan.duplicate(true)} if map_def.has_floor_plan() else {}


func _build_schedule() -> void:
	schedule = MatchSchedule.new(state.minigames, state.gamble_s, balance.last_call_seconds)
	phases = PhaseMachine.new(schedule, balance.regroup_time)
	phases.minigames_only = MatchMode.is_minigames_only(settings)
	phases.phase_changed.connect(_on_phase_changed)


## Online room: wait in the entrance-hall lobby until everyone is ready (§2.2).
func open_lobby() -> void:
	room_mode = true
	if draws_floor():
		_new_floor()  # tonight's layout stands behind the shut doors already
	_open_fun_room()


## Adds a participant and returns its player id. The slot colour is fixed and unique; `bean_color`
## is the player's preferred bean colour from their profile (`Cosmetics.bean_color_for`).
func add_player(uid: String, display_name: String, bean_color: int = -1) -> int:
	var p := PlayerState.new()
	p.id = _next_player_id
	_next_player_id += 1
	p.uid = uid
	p.display_name = display_name
	# Slot colours are not picked (Patrick, 2026-10-05): everyone gets the first free one. The bean
	# wears the preferred colour when no other bean does (0.9.16, the pedestal colour panel).
	p.color_index = lobby.free_color(_taken_colors(), -1)
	p.bean_color = Cosmetics.bean_color_for(bean_color, p.color_index, _worn_bean_colors(-1))
	state.add_player(p)
	economy.add_player(p.id, balance.start_money)
	_reset_stats(p.id)
	money_history.add_player(p.id, balance.start_money)
	world.set_transform(p.id, Vector3.ZERO, 0.0)
	lobby.join(p.id, _uptime + p.id * 0.001)
	var late: bool = room_mode and phases.phase != Phase.Id.LOBBY
	if late:
		# Joining a running match (Patrick: "Let players join running rounds"): normal starting cash
		# (above), in at the entrance hall by the lobby doors with spawn protection, and in the
		# next minigame (the one running, if any, has its players already).
		var spot: Vector3 = map_def.lobby_spawn(p.id) if map_def != null else Vector3.INF
		if spot.is_finite():
			set_server_position(p.id, spot)
		rules.protect(p.id, match_time)
		Log.info(&"server", "%s joined the running match (phase %s)" % [display_name, Phase.name_of(phases.phase)])
	_emit(GameEvents.make(&"player_joined", {"player": p.to_wire(), "late": late}))
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
	if fun_room != null and fun_room.stations.is_seated(player):
		stand_up(player)  # nobody keeps a play-money seat while away
	if minigame != null:
		minigame.remove_player(player)  # away players score 0 and get no minigame reward (§2.12)
		_check_all_ready()  # the briefing doesn't wait for someone who left
	_emit(GameEvents.make(&"player_left", {"player": player}))
	_check_leader()
	_flush()


## Removes a lobby participant for good (kicked before the match): no avatar, no slot, no money.
func remove_player(player: int) -> void:
	if not state.players.has(player):
		return
	if stations.is_seated(player):
		stand_up(player)
	state.players.erase(player)
	economy.remove_player(player)
	if fun_room != null:
		fun_room.remove_player(player)
	odd_jobs.remove_player(player)
	lobby.remove(player)
	stats.erase(player)
	_server_owned.erase(player)
	_emit(GameEvents.make(&"player_removed", {"player": player}))
	_check_leader()
	_flush()


## The party leader kicks `target` (Patrick: "Give the party lead the right to kick players"):
## `player_kicked {player, by}` goes out, the room drops their connection with the reason
## (`kick_handler`), and they can't rejoin for `Protocol.KICK_REJOIN_SECONDS`. In the lobby they
## are removed outright; in a running match they stay as "away" like any disconnected player.
func kick(target: int, by: int) -> void:
	if not state.players.has(target):
		return
	_kicked[state.players[target].uid] = _uptime + Protocol.KICK_REJOIN_SECONDS
	Log.info(&"server", "player %d kicked by the party leader (player %d)" % [target, by])
	_emit(GameEvents.make(&"player_kicked", {"player": target, "by": by}))
	if kick_handler.is_valid():
		kick_handler.call(target)
	if phases.phase == Phase.Id.LOBBY:
		remove_player(target)
	elif state.players[target].connected:
		player_disconnected(target)


## Seconds before a kicked identity may join this party again (0 = welcome).
func kick_blocked_for(uid: String) -> float:
	if not _kicked.has(uid):
		return 0.0
	var left: float = _kicked[uid] - _uptime
	if left <= 0.0:
		_kicked.erase(uid)
		return 0.0
	return left


## The same identity came back.
func player_reconnected(player: int) -> void:
	if not state.players.has(player):
		return
	state.players[player].connected = true
	# Someone who joined meanwhile may wear our bean colour now: two beans never share one.
	var ps: PlayerState = state.players[player]
	var worn: Array[int] = _worn_bean_colors(player)
	if ps.bean_color in worn:
		ps.bean_color = Cosmetics.bean_color_for(-1, ps.color_index, worn)
		_emit(GameEvents.make(&"player_color", {"player": player, "bean_color": ps.bean_color}))
	rules.status(player).away = false
	lobby.set_connected(player, true, _uptime)
	_emit(GameEvents.make(&"player_rejoined", {"player": player}))
	_check_leader()
	_flush()


## Bean colours the connected players other than `except` wear.
func _worn_bean_colors(except: int) -> Array[int]:
	var out: Array[int] = []
	for id: int in state.players:
		if id != except and state.players[id].connected:
			out.append(state.players[id].bean_color)
	return out


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
		# Lobby settings apply now: the mode and match length rebuild the schedule.
		settings["mode"] = MatchMode.normalize(lobby.settings.get("mode", MatchMode.CASINO))
		settings["items_enabled"] = bool(lobby.settings["items_enabled"]) and not MatchMode.is_minigames_only(settings)
		_apply_length()
		if schedule.minigames != state.minigames or not is_equal_approx(schedule.segment_s, state.gamble_s) or phases.minigames_only != MatchMode.is_minigames_only(settings):
			_build_schedule()
	_close_fun_room()
	running = true
	match_time = 0.0
	phases.start()
	money_history.start(schedule.duration_s, _balances())
	stations.set_limits_multiplier(balance.limits_multiplier(0))
	for id: int in state.players:
		rules.protect(id, match_time)
	_emit(GameEvents.make(&"match_started", {"seed": state.match_seed, "minigames": schedule.minigames, "gamble_s": schedule.segment_s, "duration_s": schedule.duration_s, "segment_s": schedule.segment_s, "mode": settings["mode"], "floor_plan": floor_wire()}))
	_flush()


## Clock for the intent rate limit. Not `match_time`: that stands still in the lobby and on the
## results screen (the bucket never refilled there) and goes back to 0 on Play Again (a debt of
## the whole last match, every click ignored for as long). Both counters here only ever grow.
func _intent_clock() -> float:
	return maxf(_uptime, _stepped)


## Handles one client intent. Returns {ok, error}.
func submit_intent(player: int, intent: Dictionary) -> Dictionary:
	var why: StringName = validator.check(player, intent, phases.phase, _intent_clock(), state.players.has(player))
	if _room != null and (why == &"" or why == &"wrong_phase") and _room.blocks_intent(StringName(intent.get("type", &""))):
		why = &"minigame"  # walkable room: stations, items, shop, tips and the megaphone are off
	if why == &"wrong_phase" and _is_fun_intent(intent):
		why = &""  # the waiting room's play-money games run in the lobby
	if why == &"wrong_phase" and StringName(intent.get("type", &"")) == &"odd_jobs_press" and MatchMode.is_minigames_only(settings):
		why = &"money_off"  # no casino money to earn in minigames-only matches
	if why == &"" and _jail_blocks(player, intent):
		why = &"jailed"
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
	if fun_room != null:
		var with_fun: Dictionary = (snap.get("stations", {}) as Dictionary).duplicate()
		with_fun.merge(fun_room.public_states())
		snap["stations"] = with_fun
		snap["fun"] = fun_room.to_wire()
	snap["room"] = room_mode
	snap["mode"] = settings.get("mode", MatchMode.CASINO)
	snap["effects"] = items.public_effects()
	snap["peels"] = items.peels_wire()
	snap["emotes"] = _emotes_wire()
	snap["floor"] = {"puddles": waiter.wire(), "megaphone": megaphone.wire()}
	snap["shop"] = items.shop.wire() if items.shop != null else {}
	snap["floor_plan"] = floor_wire()
	snap["hot_table"] = {"station": hot_tables.current, "time_left": snappedf(hot_tables.time_left, 0.01)} if hot_tables.current != &"" else {}
	if minigame != null:
		snap["minigame"] = minigame.get_public_state().duplicate()
		if briefing_left > 0.0:
			snap["minigame"]["briefing"] = {"left": snappedf(briefing_left, 0.01), "ready": ready_players.keys()}
	if phases.phase == Phase.Id.MINIGAME or phases.phase == Phase.Id.REWARDS:
		snap["minigame_roster"] = _minigame_roster.duplicate()
	if phases.phase == Phase.Id.REWARDS:
		snap["rewards"] = rewards.get_public_state()
	if phases.phase == Phase.Id.REGROUP:
		snap["regroup_in"] = snappedf(maxf(phases.phase_timer, 0.0), 0.01)
	if phases.phase == Phase.Id.RESULTS:
		snap["standings"] = get_standings()
		snap["awards"] = get_awards()
		snap["progress"] = progress.duplicate(true)
		snap["match_id"] = match_id
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
	_stepped += delta
	var notes: Array[StringName] = phases.advance(delta)
	for n: StringName in notes:
		_on_phase_note(n)
	var casino_open: bool = phases.phase == Phase.Id.CASINO or phases.phase == Phase.Id.PRE_MINIGAME
	if casino_open:
		stations.closing_in = _closing_in()
		stations.tick(delta)
		hot_tables.tick(delta)
		_check_comps()
		odd_jobs.tick(delta, match_time)
		money_history.tick(phases.casino_time, _balances())
	elif phases.phase == Phase.Id.MINIGAME and minigame != null:
		if briefing_left > 0.0:
			briefing_left -= delta
			if briefing_left <= 0.0:
				_go_minigame()
		else:
			minigame.tick(delta, match_time)
			if minigame.is_finished():
				_finish_minigame()
	elif phases.phase == Phase.Id.REWARDS:
		rewards.tick(delta)
		if rewards.is_done():
			phases.rewards_finished()
	if _room != null:
		_tick_room()
	modifiers.expire(match_time)
	items.tick(match_time, casino_open)
	waiter.tick(match_time, casino_open)
	megaphone.tick(match_time)
	interactions.tick(match_time)
	_tick_jail(delta)
	pickups.tick(match_time)


func _tick_lobby(delta: float) -> void:
	_keep_out_of_casino()
	_tick_fun_room(delta)
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
## `regroup_time` seconds. `regroup_started {seconds, positions: {player: [x, y, z]}, floor_plan}`
## (`floor_plan` is the new layout when this regroup put one in, else {}).
func _start_regroup() -> void:
	if _room != null:
		for id: int in _room.roster:
			if state.players.has(id) and not stations.is_seated(id):
				rules.status(id).seated = false
	_room = null  # the walkable room (if any) closes: everyone goes back to the hall below
	sanity.close_room()
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
	# The next casino round: everyone is in the hall behind the shut doors, nobody is seated, so
	# the next layout goes in now (Patrick: "After every minigame, the games (and layout change)").
	var floor_now: Dictionary = {}
	if draws_floor() and not MatchMode.is_minigames_only(settings):
		_new_floor()
		floor_now = floor_wire()
	_emit(GameEvents.make(&"regroup_started", {"seconds": balance.regroup_time, "positions": positions, "floor_plan": floor_now}))


func _finish_match() -> void:
	running = false
	hot_tables.stop()
	stations.set_global_multiplier(1.0)
	# The end screen takes over: nobody stays at a table (the open rounds were resolved at
	# `segment_ended`), so every table panel closes with a `player_stood` before `match_ended`.
	for id: int in state.players:
		if stations.is_seated(id):
			stand_up(id, &"match_over")
	money_history.finish(_balances())
	var standings: Array[Dictionary] = get_standings()
	if room_mode:
		results_return_in = balance.results_return_time
	_matches_finished += 1
	match_id = "%d-%d" % [_instance_token, _matches_finished]
	progress = progress_rows(standings)
	_emit(GameEvents.make(&"match_ended", {"standings": standings, "awards": get_awards(), "jackpot": jackpot.pot, "return_in": results_return_in,
		"progress": progress.duplicate(true), "match_id": match_id}))


## XP and Coins per player for the match that just ended (`Progression.breakdown`, data in
## data/progression/progression.tres): placement, minigames won, money won and hands played.
## Practice (no online room) earns at the practice rate.
func progress_rows(standings: Array[Dictionary]) -> Dictionary:
	var cfg: ProgressionConfig = ProgressionConfig.default()
	var out: Dictionary = {}
	for row: Dictionary in standings:
		var id: int = int(row["player"])
		var st: Dictionary = stats.get(id, {})
		out[id] = Progression.breakdown(cfg, int(row.get("rank", 1)), int(st.get("minigames_won", 0)),
			economy.balance(id) - balance.start_money, int(st.get("hands", 0)), not room_mode, int(st.get("biggest_win", 0)))
	return out


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
	briefing_left = maxf(float(settings.get("minigame_briefing", 30.0)), 0.0)
	ready_players = {}
	_minigame_roster = players.duplicate()
	var started: Dictionary = {"minigame": minigames.current_def.id, "name": minigames.current_def.display_name, "rules": minigames.current_def.rules_text, "players": players, "briefing": briefing_left}
	if minigame is WalkableLogicBase:
		started["room"] = _open_room(minigame as WalkableLogicBase)
	_emit(GameEvents.make(&"minigame_started", started))
	_flush()


## The briefing is over (everyone ready, or time ran out): the minigame starts ticking.
func _go_minigame() -> void:
	if minigame == null:
		return
	briefing_left = 0.0
	_emit(GameEvents.make(&"minigame_go", {}))


## True while the pre-minigame briefing holds the minigame.
func in_briefing() -> bool:
	return minigame != null and briefing_left > 0.0


func _check_all_ready() -> void:
	if not in_briefing():
		return
	for id: int in minigame.players:
		if state.players.has(id) and state.players[id].connected and not ready_players.has(id):
			return
	_go_minigame()


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
	for i: int in ranking.size():
		var winner: int = int(ranking[i]["player"])
		if int(ranking[i].get("rank", i + 1)) == 1 and stats.has(winner):
			stats[winner]["minigames_won"] = int(stats[winner].get("minigames_won", 0)) + 1
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
		# Everyone is back in the start room (the scene moves the bodies on `match_reset`), so the
		# shut doors don't count them as stragglers in the casino.
		var spot: Vector3 = map_def.lobby_spawn(id) if map_def != null else Vector3.INF
		if spot.is_finite():
			set_server_position(id, spot)
	_server_owned.clear()
	_accumulator = 0.0
	match_time = 0.0
	_apply_length()
	_build_match_systems(0)
	_emit(GameEvents.make(&"match_reset", {"minigames": state.minigames, "gamble_s": state.gamble_s, "duration_s": state.duration_s, "floor_plan": floor_wire()}))
	_open_fun_room()
	_flush()


func _reset_stats(id: int) -> void:
	stats[id] = {"won_by_game": {}, "biggest_bet": 0, "biggest_win": 0, "biggest_loss": 0, "knockouts_suffered": 0,
		"thrown_out": 0, "shaken_out": 0, "quiz_points": 0, "comps": 0, "lowest_rank": 1, "final_rank": 1,
		"jackpot_won": 0, "knockouts_dealt": 0, "times_shoved": 0, "loss_streak": 0, "losing_now": 0,
		"hands": 0, "minigames_won": 0}


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
			if FunRoom.is_fun(sid) and (fun_room == null or not fun_room.open):
				return StationLogicBase.fail(&"room_closed" if fun_room != null else &"unknown_station")
			var pos: Vector3 = world.get_position(player)
			var spos: Variant = map_def.station_positions.get(sid, null)
			if spos != null and (Vector3(spos) - pos).length() > map_def.interact_range:
				return StationLogicBase.fail(&"too_far")
			if FunRoom.is_fun(sid):
				return _sit_fun(player, sid)
			if stations.vip.get(sid, false) and economy.balance(player) < vip_threshold() and not modifiers.has_flag(player, &"vip_pass"):
				return StationLogicBase.fail(&"vip_denied")
			if modifiers.has_flag(player, &"bounced"):
				return StationLogicBase.fail(&"bounced")  # Bouncer item: no seat for a while
			var res: Dictionary = stations.sit(player, sid)
			if res["ok"]:
				rules.status(player).seated = true
				state.players[player].station = sid
				state.players[player].seat = _free_seat(sid, player)
				_move_to_seat(player, sid, state.players[player].seat)
				_emit(GameEvents.make(&"player_sat", {"player": player, "station": sid, "seat": state.players[player].seat}))
			return res
		&"leave":
			return stand_up(player)
		&"place_bet", &"clear_bets", &"action":
			if FunRoom.is_fun(intent.get("station", "")):
				return fun_room.route(player, intent) if fun_room != null else StationLogicBase.fail(&"unknown_station")
			return stations.route(player, intent)
		&"move":
			if not can_move(player):
				return StationLogicBase.fail(&"not_standing")
			world.set_transform(player, _clamp_position(player, Serializer.to_vec3(intent["pos"])), float(intent["yaw"]), bool(intent.get("airborne", false)))
			state.players[player].position = world.get_position(player)
			return StationLogicBase.OK_RESULT
		&"grab":
			if is_seated_anywhere(player) or rules.is_knocked_down(player, match_time):
				return StationLogicBase.fail(&"not_standing")
			return interactions.grab(player, int(intent["target"]), match_time)
		&"release":
			var thrown: int = int(interactions.holding.get(player, -1))
			var released: Dictionary = interactions.release(player, bool(intent["throw"]), Serializer.to_vec3(intent.get("aim", [])), match_time)
			if released["ok"] and bool(intent["throw"]) and _room != null and minigame == _room:
				_room.on_thrown(thrown, player)  # e.g. Bat Heist: a thrown bean lands knocked down
			return released
		&"shove":
			if is_seated_anywhere(player) or rules.is_knocked_down(player, match_time) or interactions.is_held(player):
				return StationLogicBase.fail(&"not_standing")
			var glove: bool = modifiers.has_flag(player, &"spring_glove", &"spring_glove")
			# Optional "target": who the client swung at (older clients leave it out).
			var hint: int = int(intent.get("target", -1)) if typeof(intent.get("target", -1)) in [TYPE_INT, TYPE_FLOAT] else -1
			var shoved: Dictionary = interactions.shove(player, Serializer.to_vec3(intent["aim"]), match_time, glove, hint)
			if glove and shoved["ok"]:
				modifiers.consume_round(player, &"spring_glove")
			if shoved["ok"]:
				items.pass_monkey(player, int(shoved["target"]), match_time)
				if _room != null and minigame == _room:
					_room.on_shoved(int(shoved["target"]), player)  # e.g. Grab Your Hand: drop a card
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
			if is_seated_anywhere(player) or rules.is_knocked_down(player, match_time):
				return StationLogicBase.fail(&"not_standing")
			return interactions.shake(player, match_time)
		&"break_free":
			return interactions.break_free(player, match_time)
		&"megaphone":
			return megaphone.take(player, match_time)
		&"emote":
			if not Emotes.has(StringName(str(intent["id"]))):
				return StationLogicBase.fail(&"unknown_emote")
			_emotes[player] = [StringName(intent["id"]), _uptime]
			_emit(GameEvents.make(&"emote", {"player": player, "id": StringName(intent["id"])}))
			return StationLogicBase.OK_RESULT
		&"play_emote":
			return _play_emote(player, intent)
		&"minigame_ready":
			if not in_briefing() or not minigame.players.has(player):
				return StationLogicBase.fail(&"too_late")
			if not ready_players.has(player):
				ready_players[player] = true
				_emit(GameEvents.make(&"minigame_ready", {"player": player, "ready": ready_players.keys()}))
				_check_all_ready()
			return StationLogicBase.OK_RESULT
		&"submit_answer":
			if minigame == null:
				return StationLogicBase.fail(&"too_late")
			if in_briefing():
				return StationLogicBase.fail(&"too_early")
			return minigame.submit(player, intent, match_time)
		&"split_or_steal_pick":
			if minigame == null or not minigame is SplitOrStealLogic:
				return StationLogicBase.fail(&"too_late")
			if in_briefing():
				return StationLogicBase.fail(&"too_early")
			return minigame.submit(player, intent, match_time)
		&"bust_or_bank_action":
			if minigame == null or not minigame is BustOrBankLogic:
				return StationLogicBase.fail(&"too_late")
			if in_briefing():
				return StationLogicBase.fail(&"too_early")
			return minigame.submit(player, intent, match_time)
		&"vote_race_vote":
			if minigame == null or not minigame is VoteRaceLogic:
				return StationLogicBase.fail(&"too_late")
			if in_briefing():
				return StationLogicBase.fail(&"too_early")
			return minigame.submit(player, intent, match_time)
		&"find_the_lady_pick":
			if minigame == null or not minigame is FindTheLadyLogic:
				return StationLogicBase.fail(&"too_late")
			if in_briefing():
				return StationLogicBase.fail(&"too_early")
			return minigame.submit(player, intent, match_time)
		&"forehead_poker_action":
			if minigame == null or not minigame is ForeheadPokerLogic:
				return StationLogicBase.fail(&"too_late")
			if in_briefing():
				return StationLogicBase.fail(&"too_early")
			return minigame.submit(player, intent, match_time)
		&"spy_clue", &"spy_call_vote", &"spy_vote":
			if minigame == null or not minigame is SpyLogic:
				return StationLogicBase.fail(&"too_late")
			if in_briefing():
				return StationLogicBase.fail(&"too_early")
			return minigame.submit(player, intent, match_time)
		&"minigame_action":
			# A walkable game's action button (tag, steal, drop...): the logic decides from the
			# server's own positions; `target` is only a hint like a shove's.
			if minigame == null or not minigame is WalkableLogicBase:
				return StationLogicBase.fail(&"too_late")
			if in_briefing():
				return StationLogicBase.fail(&"too_early")
			return minigame.submit(player, intent, match_time)
		&"lonely_number_pick":
			if minigame == null or not minigame is LonelyNumberLogic:
				return StationLogicBase.fail(&"too_late")
			if in_briefing():
				return StationLogicBase.fail(&"too_early")
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
		&"rps_pick":
			return items.duels.pick(player, int(intent["duel"]), int(intent["pick"]), match_time)
		&"shop_buy":
			var shop_pos: Vector3 = map_def.shop_position
			if shop_pos.is_finite() and world.get_position(player).distance_to(shop_pos) > map_def.interact_range:
				return StationLogicBase.fail(&"too_far")
			return items.buy(player, int(intent["index"]), match_time)
		&"odd_jobs_press":
			if MatchMode.is_minigames_only(settings):
				return StationLogicBase.fail(&"money_off")
			var jobs_pos: Vector3 = map_def.odd_jobs_position
			if jobs_pos.is_finite() and world.get_position(player).distance_to(jobs_pos) > map_def.interact_range:
				return StationLogicBase.fail(&"too_far")
			if stations.is_seated(player) or interactions.is_held(player):
				return StationLogicBase.fail(&"not_standing")
			return odd_jobs.press(player, match_time)
		&"return_to_lobby":
			if player != lobby.leader():
				return StationLogicBase.fail(&"not_leader")
			if not room_mode:
				return StationLogicBase.fail(&"not_room")
			return_to_lobby()
			return StationLogicBase.OK_RESULT
		&"kick_player":
			if not room_mode:
				return StationLogicBase.fail(&"not_room")
			if player != lobby.leader():
				return StationLogicBase.fail(&"not_leader")
			var t: Variant = intent["target"]
			if not (typeof(t) in [TYPE_INT, TYPE_FLOAT]) or int(t) == player or not state.players.has(int(t)):
				return StationLogicBase.fail(&"bad_target")
			kick(int(t), player)
			return StationLogicBase.OK_RESULT
		&"set_ready":
			lobby.set_panel_ready(player, bool(intent["ready"]))
			_sync_ready(player)
			return StationLogicBase.OK_RESULT
		&"set_color":
			var c: Variant = intent["color"]
			if not (typeof(c) in [TYPE_INT, TYPE_FLOAT]) or not Cosmetics.is_valid_color(int(c)):
				return StationLogicBase.fail(&"bad_value")
			var ps: PlayerState = state.players[player]
			if int(c) == ps.bean_color:
				return StationLogicBase.OK_RESULT
			if int(c) in _worn_bean_colors(player):
				return StationLogicBase.fail(&"color_taken")
			ps.bean_color = int(c)
			_emit(GameEvents.make(&"player_color", {"player": player, "bean_color": ps.bean_color}))
			return StationLogicBase.OK_RESULT
		&"lobby_setting":
			var err: StringName = lobby.set_setting(player, str(intent["key"]), intent["value"])
			if err != &"":
				return StationLogicBase.fail(err)
			if str(intent["key"]) == "minigame_pool":
				minigames.set_defs(MinigameDirector.pool_defs(Registry.minigames, lobby.settings["minigame_pool"]))
			_emit(GameEvents.make(&"lobby_settings", {"settings": lobby.settings.duplicate()}))
			return StationLogicBase.OK_RESULT
	return StationLogicBase.fail(&"not_implemented")


## Number-key emote (`play_emote {emote}`): a known animated emote is shown to everyone as
## `player_emote {player, emote}`; knocked-down players can't emote.
func _play_emote(player: int, intent: Dictionary) -> Dictionary:
	var v: Variant = intent["emote"]
	if not (v is StringName or v is String) or not Emotes.is_animated(StringName(v)):
		return StationLogicBase.fail(&"unknown_emote")
	if rules.is_knocked_down(player, match_time):
		return StationLogicBase.fail(&"not_standing")
	_emotes[player] = [StringName(v), _uptime]
	_emit(GameEvents.make(&"player_emote", {"player": player, "emote": StringName(v)}))
	return StationLogicBase.OK_RESULT


## Emotes still playing, for the snapshot: player → {id, t (seconds since it started)}.
func _emotes_wire() -> Dictionary:
	var out: Dictionary = {}
	for pid: int in _emotes.keys():
		var t: float = _uptime - float(_emotes[pid][1])
		if t >= Emotes.length(StringName(_emotes[pid][0])) or not state.players.has(pid):
			_emotes.erase(pid)
			continue
		out[pid] = {"id": _emotes[pid][0], "t": snappedf(t, 0.01)}
	return out


## Gets a seated player off their seat, exactly like their own "leave" (a round in play is settled
## by the station the same way). Items that knock people down use it on seated targets; the
## server uses it with a `reason` (minigame, regroup, thrown_out, vip_pass_ended).
func stand_up(player: int, reason: StringName = &"") -> Dictionary:
	var res: Dictionary = stations.leave(player)
	if not res["ok"] and fun_room != null and fun_room.stations.is_seated(player):
		res = fun_room.stations.leave(player)  # a play-money seat in the waiting room
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
	return not (is_seated_anywhere(player) or rules.is_knocked_down(player, match_time) or interactions.is_held(player) or _server_owned.get(player, false))


## Online movement report (unreliable stream, not rate-limited like intents). Returns false when
## the move was refused and the client must be snapped back to `sanity.last_good(player)`.
func apply_move(player: int, pos: Vector3, yaw: float, airborne: bool) -> bool:
	if not state.players.has(player) or not can_move(player):
		return true  # ignored, not a cheat: the server owns the body right now
	var held: Vector3 = _clamp_position(player, pos)
	if held != pos:  # walked out of the jail cell or the minigame room: snapped back inside
		set_server_position(player, held)
		return false
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
	if _room != null and minigame == _room:
		_room.on_player_got_up(player)


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


## SCENE: a guard caught `attacker` (Patrick 2026-10-10: security puts you in jail, no more
## throw-outs): their offences are forgotten and they go to jail (`player_jailed` names the guard,
## the scene has that bouncer carry them to the cell).
func report_caught(attacker: int, guard: StringName) -> void:
	if not state.players.has(attacker):
		return
	interactions.report_caught(attacker, match_time)
	put_in_jail(attacker, guard)
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
	_flush_fun()
	var batch: Array[Dictionary] = []
	batch.append_array(stations.drain_events())
	batch.append_array(interactions.drain_events())
	batch.append_array(pickups.drain_events())
	batch.append_array(economy.drain_events())
	batch.append_array(odd_jobs.drain_events())
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
		items.observe(ev, match_time)  # Jackpot Magnet, Butter Fingers react to wins and shakes
		if ev["type"] == &"fake_cash_used" and bool(ev["caught"]):
			caught.append(ev)
	for ev: Dictionary in caught:
		_fake_cash_caught(int(ev["player"]), int(ev["amount"]))
	if not caught.is_empty() or not items.events.is_empty():
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
			st["hands"] = int(st.get("hands", 0)) + 1
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
## A seated body sits at its seat as far as the server is concerned, so bats, bottles and
## dealers reach it there and not where the player stood before sitting down.
func _move_to_seat(player: int, sid: StringName, seat: int) -> void:
	var seats: Array = map_def.station_seats.get(sid, []) if map_def != null else []
	if seat < 0 or seat >= seats.size():
		return
	var pos: Vector3 = Vector3(seats[seat])
	world.set_transform(player, pos, world.get_yaw(player))
	state.players[player].position = pos


func _free_seat(sid: StringName, player: int) -> int:
	var logic: StationLogicBase = stations.logics.get(sid, null)
	if logic == null and fun_room != null:
		logic = fun_room.stations.logics.get(sid, null)
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
func put_in_jail(player: int, guard: StringName = &"") -> void:
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
	var ev: Dictionary = {"player": player, "time": snappedf(p.jail_time_remaining, 0.01), "fine": p.jail_fine, "catch_count": p.catch_count}
	if guard != &"":
		ev["guard"] = guard
	if map_def != null and map_def.has_jail():
		# Locked in the cell: the scene shows the bouncer bringing them (or a knockout).
		_server_owned.erase(player)
		set_server_position(player, map_def.jail_spot(player))
		ev["pos"] = Serializer.vec3(map_def.jail_spot(player))
	_emit(GameEvents.make(&"player_jailed", ev))


## Release a jailed player and deduct the fine from their balance (never below $0); the Get Out of
## Jail Free card waives it.
func release_from_jail(player: int, with_fine: bool = true) -> void:
	if not state.players.has(player) or state.players[player].jail_time_remaining <= 0.0:
		return  # not in jail
	var p: PlayerState = state.players[player]
	var fine: int = p.jail_fine if with_fine else 0
	p.jail_time_remaining = 0.0
	p.jail_fine = 0
	var deducted: int = economy.take_up_to(player, fine, &"jail_fine") if fine > 0 else 0
	var ev: Dictionary = {"player": player, "fine": deducted}
	if map_def != null and map_def.has_jail() and map_def.jail_exit(player) != Vector3.INF:
		# Out of the cell at the lobby doors (the client plays the curtain over the move).
		set_server_position(player, map_def.jail_exit(player))
		ev["pos"] = Serializer.vec3(map_def.jail_exit(player))
	_emit(GameEvents.make(&"player_released_from_jail", ev))


## Reset a player's catch count to 0 (used by Get Out of Jail Free item).
func clear_catch_count(player: int) -> void:
	if not state.players.has(player):
		return
	state.players[player].catch_count = 0
	if state.players[player].jail_time_remaining > 0.0:
		release_from_jail(player, false)
	_emit(GameEvents.make(&"catch_count_cleared", {"player": player}))


## Advance jail timers and release players when time is up.
func _tick_jail(delta: float) -> void:
	for id: int in state.players:
		var p: PlayerState = state.players[id]
		if p.jail_time_remaining <= 0.0:
			continue
		if p.jail_time_remaining <= delta:
			release_from_jail(id)  # while still "in jail", so the release takes the fine
		else:
			p.jail_time_remaining -= delta
			var at: Vector3 = world.get_position(id)
			if not _server_owned.get(id, false) and _jail_clamp(id, at) != at:
				set_server_position(id, _jail_clamp(id, at))


## Intents a jailed player can't use from the cell (the bars hold the body; this holds the hands),
## and nobody grabs a prisoner through the bars. Only with a physical cell on the map.
const JAIL_BLOCKED: Array[StringName] = [&"sit", &"grab", &"shove", &"megaphone"]


func _is_jailed(player: int) -> bool:
	return map_def != null and map_def.has_jail() and state.players.has(player) and state.players[player].jail_time_remaining > 0.0


func _jail_blocks(player: int, intent: Dictionary) -> bool:
	var type: StringName = StringName(intent.get("type", &""))
	if type in JAIL_BLOCKED and _is_jailed(player):
		return true
	return type == &"grab" and _is_jailed(int(intent.get("target", -1)))


## Where a jailed player's reported position may be: inside the cell (a step against the bars is
## clamped, anything further is their spot in the cell). Everyone else: `pos` unchanged.
func _jail_clamp(player: int, pos: Vector3) -> Vector3:
	if not _is_jailed(player) or map_def.in_jail(pos):
		return pos
	var inside: Vector3 = map_def.clamp_to_jail(pos)
	return inside if inside.distance_to(pos) < 1.5 else map_def.jail_spot(player)


## Every reported position goes through here: the jail cell, then a walkable minigame's room.
func _clamp_position(player: int, pos: Vector3) -> Vector3:
	var held: Vector3 = _jail_clamp(player, pos)
	return _room.clamp_position(player, held) if _room != null else held


# --- Walkable minigame rooms (W) ---


## A walkable minigame starts: holds and knockdowns end, every participant stands on their spawn in
## the room (the scene builds it from `minigame_started.room` and teleports the bodies it owns).
func _open_room(wl: WalkableLogicBase) -> Dictionary:
	_room = wl
	wl.world = world
	sanity.open_room(wl.arena.merge(wl.gallery).grow(2.0))  # moves in the room are on the map
	interactions.regroup()
	for id: int in wl.players:
		_server_owned.erase(id)
		world.set_transform(id, wl.spawn_for(id), wl.spawn_yaw_for(id))
		set_server_position(id, wl.spawn_for(id))
	return wl.room_wire()


## Each tick while a room is up: the logic's knockdowns (ragdolls) and gallery moves, then the
## clamp for bodies the server set itself (a ragdoll that got up, a throw). A body moved here goes
## out as `minigame_player_moved {player, pos}` and the scene puts it there.
func _tick_room() -> void:
	for kd: Dictionary in _room.pending_knockdowns:
		var p: int = int(kd["player"])
		if state.players.has(p) and rules.knock_down(p, match_time, float(kd["seconds"])):
			_emit(GameEvents.make(&"player_knocked_down", {"target": p, "attacker": int(kd.get("attacker", -1)), "seconds": kd["seconds"], "cause": kd.get("cause", &"minigame")}))
	_room.pending_knockdowns.clear()
	for id: int in _room.roster:
		if state.players.has(id) and not stations.is_seated(id):
			rules.status(id).seated = _room.is_untouchable(id)  # shove/grab immunity (Last Seat stools)
	for id: int in _room.roster:
		if not state.players.has(id) or _server_owned.get(id, false) or rules.is_knocked_down(id, match_time):
			continue  # a ragdoll in flight: once it is up, it is moved/clamped
		var at: Vector3 = world.get_position(id)
		var to: Vector3 = _room.pending_moves.get(id, _room.clamp_position(id, at))
		_room.pending_moves.erase(id)
		if to != at:
			set_server_position(id, to)
			_emit(GameEvents.make(&"minigame_player_moved", {"player": id, "pos": Serializer.vec3(to)}))


# --- Start room (online lobby) ---


## LOBBY: the casino is shut. Anyone the server finds past the lobby doors (thrown through, a
## physics glitch) goes straight back to their spot in the start room; the scene puts the body
## there on `player_sent_back`.
func _keep_out_of_casino() -> void:
	if map_def == null:
		return
	for id: int in state.players:
		if not world.positions.has(id):
			continue  # no body in the world yet
		var pos: Vector3 = world.get_position(id)
		var spot: Vector3 = map_def.lobby_spawn(id)
		if spot == Vector3.INF or not map_def.past_lobby_doors(pos):
			continue
		_server_owned.erase(id)
		set_server_position(id, spot)
		Log.info(&"server", "player %d was past the lobby doors at %s: back to %s" % [id, pos, spot])
		_emit(GameEvents.make(&"player_sent_back", {"player": id, "pos": Serializer.vec3(spot)}))


# --- The waiting room (play money) ---


## True while the player sits at any table: the casino's or the waiting room's.
func is_seated_anywhere(player: int) -> bool:
	return stations.is_seated(player) or (fun_room != null and fun_room.stations.is_seated(player))


## The lobby opens (or reopens after a match): the waiting room's door opens with fresh play-money
## tables, and walking into it is on the map again.
func _open_fun_room() -> void:
	if not room_mode or map_def == null or not map_def.has_waiting_room():
		return
	fun_room = FunRoom.new(map_def.fun_stations, _logic_scripts, balance, SeededRng.new(state.match_seed ^ 0xF0F0F0), map_def.waiting_area)
	sanity.closed_bounds.clear()
	_emit(GameEvents.make(&"waiting_room", {"open": true}))


## The match starts: the waiting room's tables close (everyone stands up, open play rounds settle
## on play chips), anyone still inside goes back to their start-room spot (`player_sent_back`, the
## scene moves the body), the door locks and moves into the room are refused until the next lobby.
func _close_fun_room() -> void:
	if fun_room == null or not fun_room.open:
		return
	for p: int in fun_room.close():
		stand_up(p, &"waiting_room_closed")
	_flush_fun()
	for id: int in state.players:
		if not world.positions.has(id) or not fun_room.contains(world.get_position(id)):
			continue
		var spot: Vector3 = map_def.lobby_spawn(id)
		if not spot.is_finite():
			continue
		_server_owned.erase(id)
		set_server_position(id, spot)
		Log.info(&"server", "player %d was in the waiting room at the start: back to %s" % [id, spot])
		_emit(GameEvents.make(&"player_sent_back", {"player": id, "pos": Serializer.vec3(spot), "reason": &"waiting_room_closed"}))
	sanity.closed_bounds = [fun_room.area]
	_emit(GameEvents.make(&"waiting_room", {"open": false}))


## LOBBY: fresh play chips for whoever walks in, and the play tables run.
func _tick_fun_room(delta: float) -> void:
	if fun_room == null or not fun_room.open:
		return
	for id: int in state.players:
		if world.positions.has(id) and state.players[id].connected:
			fun_room.update_presence(id, world.get_position(id))
	fun_room.tick(delta)
	_flush_fun()


## Emits the waiting room's events (tagged `fun`) straight out: they never reach the stats, the
## items or anything else that reads the real ledger.
func _flush_fun() -> void:
	if fun_room == null:
		return
	for ev: Dictionary in fun_room.drain_events():
		_emit(ev)


## A station intent the validator refused for the phase, aimed at an open waiting-room table in
## the lobby: allowed (the play-money games only run there).
func _is_fun_intent(intent: Dictionary) -> bool:
	var type: StringName = StringName(intent.get("type", &""))
	return fun_room != null and fun_room.open and phases.phase == Phase.Id.LOBBY and type in [&"place_bet", &"clear_bets", &"action"] and FunRoom.is_fun(intent.get("station", ""))


## Sits a player at a waiting-room table (the reach check already passed).
func _sit_fun(player: int, sid: StringName) -> Dictionary:
	if fun_room == null:
		return StationLogicBase.fail(&"unknown_station")
	if stations.is_seated(player):
		return StationLogicBase.fail(&"already_seated")
	var res: Dictionary = fun_room.sit(player, sid)
	if res["ok"]:
		rules.status(player).seated = true
		state.players[player].station = sid
		state.players[player].seat = _free_seat(sid, player)
		_move_to_seat(player, sid, state.players[player].seat)
		_emit(GameEvents.make(&"player_sat", {"player": player, "station": sid, "seat": state.players[player].seat, "fun": true}))
	return res
