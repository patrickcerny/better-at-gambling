extends GutTest
## The casino floor's layouts on the authoritative server (docs/FLOOR_PLAN.md): online rooms take
## the next layout from a seeded bag when the lobby opens and at every regroup, Practice keeps the
## full floor, the layout is on the wire (match_started, regroup_started, snapshot) with every
## station's game, place and facing, stations/dealers/hot table follow it, nobody stays seated at
## a table that goes or moves (stood up, bets refunded), no money moves, and a layout whose game is
## off is skipped.

var fx: ServerFixture


func after_each() -> void:
	if fx != null:
		fx.server.free()
		fx = null


func _room(seed_value: int = 5, extra: Dictionary = {}) -> void:
	var s: Dictionary = {"minigames": 4, "gamble_seconds": 60.0, "seed": seed_value, "floor": ""}
	s.merge(extra, true)
	fx = ServerFixture.new(3, s)
	fx.server.open_lobby()


func _step_until(cond: Callable, max_seconds: float = 2000.0) -> bool:
	var t: float = 0.0
	while not cond.call() and t < max_seconds:
		fx.server._step(MatchServer.TICK)
		fx.server._flush()
		t += MatchServer.TICK
	return cond.call()


func _expected_stations() -> Dictionary:
	var out: Dictionary = {}
	for sid: Variant in LuckyLounge.FIXED_STATIONS:
		out[StringName(sid)] = (LuckyLounge.FIXED_STATIONS[sid] as Array)[0]
	for sid: StringName in fx.server.floor_plan:
		out[sid] = FloorPlan.game_of(fx.server.floor_plan[sid])
	return out


func _check_server_follows_layout() -> void:
	var srv: MatchServer = fx.server
	var layout: FloorLayout = srv.map_def.floor_layout(srv.floor_layout)
	assert_not_null(layout, "a known layout stands (%s)" % srv.floor_layout)
	if layout == null:
		return
	assert_eq(srv.floor_plan, layout.wire_stations(), "the floor is exactly the layout's file")
	var want: Dictionary = _expected_stations()
	assert_eq(srv.map_def.stations, want, "the map definition lists tonight's stations")
	var logics: Array = srv.stations.logics.keys()
	logics.sort()
	var keys: Array = want.keys()
	keys.sort()
	assert_eq(logics, keys, "one station logic per table of the layout plus the fixed ones")
	for sid: Variant in layout.stations:
		var row: Array = layout.stations[sid]
		assert_almost_eq(srv.map_def.station_positions[sid] as Vector3, row[1] as Vector3, Vector3.ONE * 0.001, "%s stands where the layout says" % sid)
		assert_almost_eq(float(srv.map_def.station_yaws[sid]), deg_to_rad(float(row[2])), 0.0001, "%s faces where the layout says" % sid)
		assert_eq(srv.stations.game_of[sid], StringName(row[0]))
		assert_false(srv.stations.vip.get(sid, false), "%s is on the casino floor, not VIP" % sid)
	for sid: Variant in LuckyLounge.FIXED_STATIONS:
		assert_true(srv.stations.logics.has(StringName(sid)), "%s never moves" % sid)
	var dealer_tables: Array = want.keys().filter(func(sid: StringName) -> bool: return DealerLogic.OFFSETS.has(want[sid]))
	dealer_tables.sort()
	var dealers: Array = srv.dealers.keys()
	dealers.sort()
	assert_eq(dealers, dealer_tables, "a dealer at every table that has one")


func test_practice_keeps_the_full_floor() -> void:
	fx = ServerFixture.new(2, {"minigames": 2, "gamble_seconds": 60.0, "seed": 3, "floor": ""})
	assert_false(fx.server.draws_floor())
	assert_eq(fx.server.floor_round, 0)
	assert_eq(fx.server.floor_layout, &"grand_hall")
	assert_eq(fx.server.floor_plan, LuckyLounge.full_floor_plan())
	fx.server.start_match()
	assert_true(_step_until(func() -> bool: return fx.server.phases.phase == Phase.Id.REGROUP))
	assert_eq(fx.server.floor_round, 0, "no new layout at the regroup either")
	assert_eq(fx.of_type(&"regroup_started")[0]["floor_plan"], {})
	assert_eq(fx.server.stations.logics.size(), LuckyLounge.STATIONS.size(), "every table, every round")


func test_a_room_changes_the_layout_at_every_regroup() -> void:
	_room()
	var srv: MatchServer = fx.server
	assert_true(srv.draws_floor())
	assert_eq(srv.floor_round, 1, "the first layout stands behind the shut doors already")
	var first: StringName = srv.floor_layout
	_check_server_follows_layout()
	srv.start_match()
	var started: Dictionary = fx.of_type(&"match_started")[0]
	assert_eq(started["floor_plan"], {"round": 1, "layout": first, "stations": srv.floor_plan}, "match_started names the layout and carries its stations")
	var layouts: Array[StringName] = [first]
	for round_i: int in [2, 3, 4, 5]:
		# Step to the regroup, noting the money on the last tick before it.
		var before: Dictionary = {}
		var t: float = 0.0
		while srv.phases.phase != Phase.Id.REGROUP and t < 2000.0:
			for p: int in fx.player_ids:
				before[p] = srv.economy.balance(p)
			srv._step(MatchServer.TICK)
			srv._flush()
			t += MatchServer.TICK
		assert_eq(srv.phases.phase, Phase.Id.REGROUP)
		var regroups: Array[Dictionary] = fx.of_type(&"regroup_started")
		var ev: Dictionary = regroups[regroups.size() - 1]
		assert_eq(int(ev["floor_plan"]["round"]), round_i, "regroup %d puts in floor %d" % [round_i - 1, round_i])
		assert_eq(StringName(ev["floor_plan"]["layout"]), srv.floor_layout)
		assert_eq(ev["floor_plan"]["stations"], srv.floor_plan)
		assert_ne(srv.floor_layout, layouts[layouts.size() - 1], "the layout changes at every regroup")
		for p: int in fx.player_ids:
			assert_eq(srv.economy.balance(p), int(before[p]), "the new layout moves no money")
			assert_false(srv.stations.is_seated(p), "nobody is seated across the switch")
		_check_server_follows_layout()
		layouts.append(srv.floor_layout)
		assert_true(_step_until(func() -> bool: return srv.phases.phase == Phase.Id.CASINO))
		# Late joiners and reconnects build the floor from the snapshot.
		var st := ClientMatchState.new()
		st.apply_snapshot(srv.get_snapshot())
		assert_eq(st.floor_plan, srv.floor_plan, "the snapshot carries the stations")
		assert_eq(st.floor_layout, srv.floor_layout, "and names the layout")
		assert_eq(st.floor_round, round_i)
		for sid: Variant in st.stations:
			assert_true(srv.stations.logics.has(StringName(sid)), "%s in the snapshot stands tonight" % sid)
	var distinct: Dictionary = {}
	for id: StringName in layouts:
		distinct[id] = true
	assert_eq(distinct.size(), layouts.size(), "five rounds, five different layouts (no repeats in a bag of six): %s" % [layouts])


func test_same_seed_same_layouts() -> void:
	var seen: Array = []
	for i: int in 2:
		_room(77)
		fx.server.start_match()
		var ids: Array = [fx.server.floor_layout]
		assert_true(_step_until(func() -> bool: return fx.server.floor_round >= 3))
		ids.append(fx.server.floor_layout)
		seen.append(ids)
		fx.server.free()
		fx = null
	assert_eq(seen[0], seen[1], "deterministic per match seed")


func test_play_again_starts_a_fresh_bag() -> void:
	_room(12, {"minigames": 1})
	var srv: MatchServer = fx.server
	var first: StringName = srv.floor_layout
	srv.start_match()
	assert_true(_step_until(func() -> bool: return srv.phases.phase == Phase.Id.RESULTS, 4000.0))
	srv.return_to_lobby()
	assert_eq(srv.floor_round, 1, "the new match counts from its first layout")
	assert_true(srv.map_def.floor_layout(srv.floor_layout) != null)
	var resets: Array[Dictionary] = fx.of_type(&"match_reset")
	assert_eq(StringName(resets[resets.size() - 1]["floor_plan"]["layout"]), srv.floor_layout, "match_reset names the layout")
	_check_server_follows_layout()
	gut.p("first match opened on %s, the next on %s" % [first, srv.floor_layout])


func test_a_seated_player_at_a_table_that_moves_is_stood_up_and_refunded() -> void:
	_room(9)
	var srv: MatchServer = fx.server
	srv.start_match()
	assert_true(_step_until(func() -> bool: return srv.phases.phase == Phase.Id.CASINO))
	var sid: StringName = &"roulette_1"  # every layout has it, each in a different place
	assert_true(srv.floor_plan.has(sid))
	var p: int = fx.player_ids[0]
	srv.set_server_position(p, srv.map_def.station_positions[sid])
	var money: int = srv.economy.balance(p)
	assert_true(fx.intent(p, &"sit", {"station": sid})["ok"])
	assert_true(fx.intent(p, &"place_bet", {"station": sid, "bet": {"type": &"red", "value": 0, "amount": 25}})["ok"])
	assert_eq(srv.economy.balance(p), money - 25)
	var was: StringName = srv.floor_layout
	var at: Vector3 = srv.map_def.station_positions[sid]
	srv._new_floor()
	srv._flush()
	assert_ne(srv.floor_layout, was, "another layout")
	assert_false((srv.map_def.station_positions[sid] as Vector3).is_equal_approx(at), "roulette_1 moved")
	assert_false(srv.stations.is_seated(p), "stood up")
	assert_eq(srv.state.players[p].station, &"")
	var stood: Array[Dictionary] = fx.of_type(&"player_stood").filter(func(e: Dictionary) -> bool: return int(e["player"]) == p)
	assert_eq(StringName(stood[stood.size() - 1].get("reason", &"")), &"floor_changed")
	assert_eq(srv.economy.balance(p), money, "the open bet came back")


func test_a_table_that_goes_takes_nobody_and_its_hot_table_cools() -> void:
	_room(4)
	var srv: MatchServer = fx.server
	srv.start_match()
	assert_true(_step_until(func() -> bool: return srv.hot_tables.current != &"" and srv.floor_plan.has(srv.hot_tables.current)))
	var hot: StringName = srv.hot_tables.current
	var without: Dictionary = srv.floor_plan.duplicate(true)
	without.erase(hot)
	srv._apply_floor(without, srv.floor_layout)
	assert_eq(srv.hot_tables.current, &"")
	assert_false(srv.stations.hot.has(hot))
	var p: int = fx.player_ids[1]
	assert_false(fx.intent(p, &"sit", {"station": hot})["ok"], "the table that went takes nobody")


func test_a_layout_with_a_game_that_is_off_is_skipped() -> void:
	_room(21)
	var srv: MatchServer = fx.server
	var off: FloorPlanConfig = Registry.floor_plan.duplicate() as FloorPlanConfig
	off.weights = {&"craps": 0.0}
	srv.floor_config = off
	srv.start_match()
	var seen: Array[StringName] = []
	for i: int in 8:
		srv._new_floor()
		seen.append(srv.floor_layout)
		assert_false(&"craps" in srv.map_def.floor_layout(srv.floor_layout).games(), "%s has no craps table" % srv.floor_layout)
		assert_false(srv.map_def.stations.values().has(&"craps"), "no craps anywhere tonight")
	for i: int in range(1, seen.size()):
		assert_ne(seen[i], seen[i - 1], "still never the same layout twice in a row")
	off.weights = {&"craps": 0.0, &"slots": 0.0, &"blackjack": 0.0}
	srv._new_floor()
	assert_eq(srv.floor_layout, &"grand_hall", "nothing usable: the full floor")


func test_a_pinned_layout_stands_every_round() -> void:
	_room(2, {"floor": "the_salon"})
	var srv: MatchServer = fx.server
	assert_eq(srv.floor_layout, &"the_salon")
	srv.start_match()
	assert_true(_step_until(func() -> bool: return srv.floor_round >= 2))
	assert_eq(srv.floor_layout, &"the_salon")


func test_minigames_only_keeps_its_floor() -> void:
	_room(6, {"mode": MatchMode.MINIGAMES})
	var srv: MatchServer = fx.server
	srv.lobby.settings["mode"] = MatchMode.MINIGAMES
	srv.start_match()
	var r: int = srv.floor_round
	assert_true(_step_until(func() -> bool: return srv.phases.phase == Phase.Id.REGROUP))
	assert_eq(srv.floor_round, r, "no casino floor in minigames-only: nothing to change")
