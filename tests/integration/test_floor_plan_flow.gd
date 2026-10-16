extends GutTest
## The per-round casino floor on the authoritative server (docs/FLOOR_PLAN.md): online rooms draw
## a floor when the lobby opens and at every regroup, Practice keeps the full floor, the plan is on
## the wire (match_started, regroup_started, snapshot), stations/dealers/hot table follow it,
## nobody stays seated at a table that closes and no money moves.

var fx: ServerFixture


func after_each() -> void:
	if fx != null:
		fx.server.free()
		fx = null


func _room(seed_value: int = 5, extra: Dictionary = {}) -> void:
	var s: Dictionary = {"minigames": 3, "gamble_seconds": 60.0, "seed": seed_value, "floor": ""}
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
	var out: Dictionary = {&"horse_race_1": &"horse_race"}
	for sid: StringName in fx.server.floor_plan:
		out[sid] = StringName(fx.server.floor_plan[sid][0])
	return out


func _check_server_follows_plan() -> void:
	var srv: MatchServer = fx.server
	var want: Dictionary = _expected_stations()
	assert_eq(srv.map_def.stations, want, "the map definition lists tonight's stations")
	var logics: Array = srv.stations.logics.keys()
	logics.sort()
	var keys: Array = want.keys()
	keys.sort()
	assert_eq(logics, keys, "one station logic per open table, none for closed spots")
	for sid: StringName in srv.floor_plan:
		var a: Dictionary = srv.map_def.floor_anchor(StringName(srv.floor_plan[sid][1]))
		assert_eq(srv.map_def.station_positions[sid], a["pos"], "%s stands on its spot" % sid)
		assert_eq(srv.stations.game_of[sid], StringName(srv.floor_plan[sid][0]))
		assert_eq(srv.stations.vip.get(sid, false), bool(a["vip"]), "%s VIP like its spot" % sid)
	var dealer_tables: Array = want.keys().filter(func(sid: StringName) -> bool: return DealerLogic.OFFSETS.has(want[sid]))
	dealer_tables.sort()
	var dealers: Array = srv.dealers.keys()
	dealers.sort()
	assert_eq(dealers, dealer_tables, "a dealer at every blackjack and roulette table there is")


func test_practice_keeps_the_full_floor() -> void:
	fx = ServerFixture.new(2, {"minigames": 2, "gamble_seconds": 60.0, "seed": 3, "floor": ""})
	assert_false(fx.server.draws_floor())
	assert_eq(fx.server.floor_round, 0)
	assert_eq(fx.server.floor_plan, LuckyLounge.full_floor_plan())
	fx.server.start_match()
	assert_true(_step_until(func() -> bool: return fx.server.phases.phase == Phase.Id.REGROUP))
	assert_eq(fx.server.floor_round, 0, "no draw at the regroup either")
	assert_eq(fx.of_type(&"regroup_started")[0]["floor_plan"], {})
	assert_eq(fx.server.stations.logics.size(), LuckyLounge.STATIONS.size(), "every table, every round")


func test_a_room_draws_at_the_lobby_and_at_every_regroup() -> void:
	_room()
	var srv: MatchServer = fx.server
	assert_true(srv.draws_floor())
	assert_eq(srv.floor_round, 1, "tonight's floor stands behind the shut doors already")
	var first: Dictionary = srv.floor_plan.duplicate(true)
	_check_server_follows_plan()
	srv.start_match()
	var started: Dictionary = fx.of_type(&"match_started")[0]
	assert_eq(started["floor_plan"], {"round": 1, "stations": first}, "match_started carries the floor")
	var plans: Array[Dictionary] = [first]
	for round_i: int in [2, 3, 4]:
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
		assert_eq(int(ev["floor_plan"]["round"]), round_i, "regroup %d draws floor %d" % [round_i - 1, round_i])
		assert_eq(ev["floor_plan"]["stations"], srv.floor_plan)
		for p: int in fx.player_ids:
			assert_eq(srv.economy.balance(p), int(before[p]), "the new floor moves no money")
			assert_false(srv.stations.is_seated(p), "nobody is seated across the switch")
		_check_server_follows_plan()
		plans.append(srv.floor_plan.duplicate(true))
		assert_true(_step_until(func() -> bool: return srv.phases.phase == Phase.Id.CASINO))
		# Late joiners and reconnects rebuild the floor from the snapshot.
		var st := ClientMatchState.new()
		st.apply_snapshot(srv.get_snapshot())
		assert_eq(st.floor_plan, srv.floor_plan, "the snapshot carries the floor")
		assert_eq(st.floor_round, round_i)
		for sid: Variant in st.stations:
			assert_true(srv.stations.logics.has(StringName(sid)), "%s in the snapshot is open" % sid)
	var distinct: Dictionary = {}
	for p: Dictionary in plans:
		distinct[p] = true
	assert_gt(distinct.size(), 1, "the floor changes between rounds")


func test_same_seed_same_floors() -> void:
	var seen: Array = []
	for i: int in 2:
		_room(77)
		fx.server.start_match()
		var plans: Array = [fx.server.floor_plan.duplicate(true)]
		assert_true(_step_until(func() -> bool: return fx.server.floor_round >= 3))
		plans.append(fx.server.floor_plan.duplicate(true))
		seen.append(plans)
		fx.server.free()
		fx = null
	assert_eq(seen[0], seen[1], "deterministic per match seed")


func test_a_seated_player_at_a_table_that_closes_is_stood_up_and_refunded() -> void:
	_room(9)
	var srv: MatchServer = fx.server
	srv.start_match()
	assert_true(_step_until(func() -> bool: return srv.phases.phase == Phase.Id.CASINO))
	var sid: StringName = &""
	for s: StringName in srv.floor_plan:
		if StringName(srv.floor_plan[s][0]) == &"roulette" and not String(s).begins_with("vip_"):
			sid = s
	if sid == &"":  # nothing guaranteed: put one roulette table on the floor for this test
		var plan: Dictionary = srv.floor_plan.duplicate(true)
		for a: Dictionary in srv.map_def.floor_anchors:
			if a["footprint"] == &"table" and not a["vip"]:
				for s: StringName in plan.keys():
					if plan[s][1] == a["id"]:
						plan.erase(s)
				plan[&"roulette_9"] = [&"roulette", a["id"]]
				break
		srv._apply_floor(plan)
		sid = &"roulette_9"
	var p: int = fx.player_ids[0]
	srv.set_server_position(p, srv.map_def.station_positions[sid])
	var money: int = srv.economy.balance(p)
	assert_true(fx.intent(p, &"sit", {"station": sid})["ok"])
	assert_true(fx.intent(p, &"place_bet", {"station": sid, "bet": {"type": &"red", "value": 0, "amount": 25}})["ok"])
	assert_eq(srv.economy.balance(p), money - 25)
	var without: Dictionary = srv.floor_plan.duplicate(true)
	without.erase(sid)
	srv._apply_floor(without)
	srv._flush()
	assert_false(srv.stations.is_seated(p), "stood up")
	assert_eq(srv.state.players[p].station, &"")
	var stood: Array[Dictionary] = fx.of_type(&"player_stood").filter(func(e: Dictionary) -> bool: return int(e["player"]) == p)
	assert_eq(StringName(stood[stood.size() - 1].get("reason", &"")), &"floor_changed")
	assert_eq(srv.economy.balance(p), money, "the open bet came back")
	assert_false(fx.intent(p, &"sit", {"station": sid})["ok"], "the closed table takes nobody")


func test_the_hot_table_goes_cold_when_its_table_closes() -> void:
	_room(4)
	var srv: MatchServer = fx.server
	srv.start_match()
	assert_true(_step_until(func() -> bool: return srv.hot_tables.current != &"" and srv.floor_plan.has(srv.hot_tables.current)))
	var hot: StringName = srv.hot_tables.current
	var without: Dictionary = srv.floor_plan.duplicate(true)
	without.erase(hot)
	srv._apply_floor(without)
	assert_eq(srv.hot_tables.current, &"")
	assert_false(srv.stations.hot.has(hot))


func test_minigames_only_keeps_its_floor() -> void:
	_room(6, {"mode": MatchMode.MINIGAMES})
	var srv: MatchServer = fx.server
	srv.lobby.settings["mode"] = MatchMode.MINIGAMES
	srv.start_match()
	var r: int = srv.floor_round
	assert_true(_step_until(func() -> bool: return srv.phases.phase == Phase.Id.REGROUP))
	assert_eq(srv.floor_round, r, "no casino floor in minigames-only: nothing to redraw")
