extends GutTest
## The waiting room behind the start room on the authoritative server (Patrick: "a blackjack table
## just for fun ... it doesn't add money or anything"): its tables play on a separate ledger in the
## lobby, nothing reaches the real money, stats or standings, and once the match starts the room is
## shut: everyone stands up and goes back to the start room, its tables refuse, moves into it are
## off the map. The next lobby opens it again.

const BJ: StringName = &"fun_blackjack_1"
const SLOT: StringName = &"fun_slot_2"
const INSIDE: Vector3 = Vector3(0, 0, 18.0)

var fx: ServerFixture
var p: int
var q: int


func before_each() -> void:
	fx = ServerFixture.new(2, {"minigames": 1, "gamble_seconds": 20.0, "seed": 9})
	LuckyLounge.describe_rooms(fx.server.map_def)
	fx.server.map_def.lobby_spawns = LuckyLounge.LOBBY_SPAWNS.duplicate()
	for sid: StringName in LuckyLounge.FUN_STATIONS:
		fx.server.map_def.station_positions[sid] = LuckyLounge.FUN_STATIONS[sid][1]
	p = fx.player_ids[0]
	q = fx.player_ids[1]
	for id: int in fx.player_ids:
		fx.server.set_server_position(id, fx.server.map_def.lobby_spawn(id))
	fx.server.open_lobby()


func after_each() -> void:
	fx.server.free()


func _lobby_tick(seconds: float) -> void:
	var t: float = 0.0
	while t < seconds:
		fx.server.advance(0.05)
		t += 0.05


func _walk_in(id: int, at: Vector3 = INSIDE) -> void:
	fx.server.set_server_position(id, at)
	_lobby_tick(0.1)


func _c(ranks: Array) -> Array[int]:
	var out: Array[int] = []
	for r: int in ranks:
		out.append(Card.make(r))
	return out


func _fun(id: int) -> int:
	return fx.server.fun_room.balance(id)


func test_play_money_bets_go_all_in_too() -> void:
	_walk_in(p)
	assert_true(fx.intent(p, &"sit", {"station": BJ})["ok"])
	var fun_eco: Economy = fx.server.fun_room.economy
	assert_true(fun_eco.apply(p, 35 - fun_eco.balance(p), &"test_setup"))
	fx.events.clear()
	assert_true(fx.intent(p, &"place_bet", {"station": BJ, "bet": {"amount": 200}})["ok"], "more than the play chips bets them all")
	assert_eq(_fun(p), 0)
	var placed: Array[Dictionary] = fx.of_type(&"bet_placed")
	assert_eq(placed.size(), 1, "the fun table's bet goes out like the casino's")
	if not placed.is_empty():
		assert_eq(int(placed.back()["amount"]), 35)
		assert_true(bool((placed.back()["details"] as Dictionary).get("all_in", false)))


func test_the_lobby_opens_the_room_and_hands_out_play_chips() -> void:
	assert_not_null(fx.server.fun_room, "an online lobby has a waiting room")
	assert_true(fx.server.fun_room.open)
	assert_eq(fx.of_type(&"waiting_room").size(), 1)
	assert_true(bool(fx.of_type(&"waiting_room")[0]["open"]))
	assert_true(fx.server.sanity.in_bounds(Vector3(0, 0, LuckyLounge.WAIT_Z1 - 0.3)), "the back of the room is on the map")
	_walk_in(p)
	assert_eq(_fun(p), FunRoom.PLAY_CHIPS)
	assert_eq(_fun(q), 0, "only who walked in")
	var snap: Dictionary = fx.server.get_snapshot()
	assert_true(bool(snap["fun"]["open"]))
	assert_eq(int(snap["fun"]["balances"][p]), FunRoom.PLAY_CHIPS)
	assert_true(snap["stations"].has(BJ), "the fun tables are in the snapshot for the clients")
	assert_true(bool(snap["stations"][BJ]["fun"]))
	assert_true(snap["stations"].has(&"blackjack_1"), "next to the casino's")
	assert_false(fx.server.stations.logics.has(BJ), "but not among the casino's stations")
	assert_eq(int(snap["balances"][p]), Registry.balance.start_money)


func test_play_money_never_touches_the_real_ledger() -> void:
	var start: int = fx.server.economy.balance(p)
	var ledger_size: int = fx.server.economy.ledger.entries.size()
	_walk_in(p)
	fx.events.clear()
	assert_true(fx.intent(p, &"sit", {"station": BJ})["ok"])
	assert_true(fx.server.is_seated_anywhere(p))
	assert_false(fx.server.can_move(p), "seated at the play table")
	assert_true(fx.intent(p, &"place_bet", {"station": BJ, "bet": {"amount": 100}})["ok"], "betting works in the lobby at a fun table")
	assert_eq(fx.intent(p, &"place_bet", {"station": &"blackjack_1", "bet": {"amount": 100}})["error"], &"wrong_phase", "the casino stays shut")
	(fx.server.fun_room.stations.logics[BJ] as BlackjackLogic).shoe.stack_top(_c([1, 9, 13, 7]))
	_lobby_tick(9.0)
	assert_eq(_fun(p), FunRoom.PLAY_CHIPS + 150, "won 3:2 on play chips")
	# A slots loss.
	assert_true(fx.intent(p, &"leave")["ok"])
	fx.server.set_server_position(p, Vector3(-3.5, 0, 20.3))  # over to the slots
	assert_true(fx.intent(p, &"sit", {"station": SLOT})["ok"])
	var sl: SlotsLogic = fx.server.fun_room.stations.logics[SLOT] as SlotsLogic
	var bet: int = sl.bet_sizes()[0]
	assert_true(fx.intent(p, &"place_bet", {"station": SLOT, "bet": {"amount": bet}})["ok"])
	var S := SlotsLogic.Sym
	sl.line = [S.LEMON, S.BELL, S.BAR] as Array[int]
	_lobby_tick(8.0)
	assert_eq(_fun(p), FunRoom.PLAY_CHIPS + 150 - bet, "lost on play chips")
	# Nothing reached the real side.
	assert_eq(fx.server.economy.balance(p), start, "the real balance never moved")
	assert_eq(fx.server.economy.ledger.entries.size(), ledger_size, "no real ledger entries")
	assert_eq(int(fx.server.stats[p]["biggest_win"]), 0, "no stats from play money")
	assert_eq(int(fx.server.stats[p]["biggest_bet"]), 0)
	assert_eq(fx.server.state.players[p].biggest_win, 0)
	assert_eq(int(fx.server.get_snapshot()["balances"][p]), start)
	var standing: Dictionary = fx.server.get_standings().filter(func(r: Dictionary) -> bool: return r["player"] == p)[0]
	assert_eq(int(standing["money"]), start, "the leaderboard sees only real money")
	# (The fixture's queued start money goes out with the first flush: the only real money events.)
	var money: Array[Dictionary] = fx.of_type(&"money_changed").filter(func(e: Dictionary) -> bool: return e["reason"] != &"start")
	assert_gt(money.size(), 2)
	for ev: Dictionary in money:
		assert_true(bool(ev.get("fun", false)), "every money event in there is play money (%s)" % ev["reason"])
	for ev: Dictionary in fx.of_type(&"round_result"):
		assert_true(bool(ev.get("fun", false)))
	# Walk out and back in: a fresh stack.
	assert_true(fx.intent(p, &"leave")["ok"])
	fx.server.set_server_position(p, fx.server.map_def.lobby_spawn(p))
	_lobby_tick(0.1)
	_walk_in(p)
	assert_eq(_fun(p), FunRoom.PLAY_CHIPS, "reset on re-entry")


func test_the_match_start_shuts_the_room() -> void:
	_walk_in(p)
	_walk_in(q, INSIDE + Vector3(2, 0, 2))
	assert_true(fx.intent(p, &"sit", {"station": BJ})["ok"])
	assert_true(fx.intent(p, &"place_bet", {"station": BJ, "bet": {"amount": 50}})["ok"])
	fx.events.clear()
	fx.server.start_match()
	assert_false(fx.server.fun_room.open)
	assert_false(fx.server.is_seated_anywhere(p), "stood up from the play table")
	var stood: Array[Dictionary] = fx.of_type(&"player_stood")
	assert_eq(stood.size(), 1)
	assert_eq(StringName(stood[0]["reason"]), &"waiting_room_closed")
	var sent: Array = fx.of_type(&"player_sent_back").map(func(e: Dictionary) -> int: return int(e["player"]))
	assert_true(sent.has(q), "whoever was inside goes back to the start room")
	assert_true(sent.has(p))
	for id: int in [p, q]:
		assert_eq(fx.server.world.get_position(id), fx.server.map_def.lobby_spawn(id))
		assert_false(fx.server.fun_room.contains(fx.server.world.get_position(id)))
	var closed: Array[Dictionary] = fx.of_type(&"waiting_room")
	assert_eq(closed.size(), 1)
	assert_false(bool(closed[0]["open"]))
	var started: int = -1
	for i: int in fx.events.size():
		if fx.events[i]["type"] == &"match_started":
			started = i
	assert_gt(started, fx.events.find(closed[0]), "shut before the match starts")
	fx.run(3.2)
	assert_eq(fx.server.phases.phase, Phase.Id.CASINO)
	assert_eq(fx.intent(p, &"sit", {"station": BJ})["error"], &"room_closed")
	assert_eq(fx.intent(q, &"place_bet", {"station": SLOT, "bet": {"amount": 10}})["error"], &"room_closed")
	assert_false(fx.server.sanity.in_bounds(INSIDE), "the shut room is off the map")
	assert_true(fx.server.sanity.in_bounds(Vector3(0, 0, 12)), "the start room is not")
	assert_false(fx.server.apply_move(q, INSIDE, 0.0, false), "walking into it is refused")
	assert_ne(fx.server.world.get_position(q), INSIDE)
	var snap: Dictionary = fx.server.get_snapshot()
	assert_false(bool(snap["fun"]["open"]))
	# The next lobby opens it again with fresh tables.
	fx.server.run_to_end()
	assert_eq(fx.server.phases.phase, Phase.Id.RESULTS)
	fx.events.clear()
	fx.server.return_to_lobby()
	assert_true(fx.server.fun_room.open)
	assert_eq(fx.server.fun_room.balance(p), 0, "a fresh ledger")
	assert_true(bool(fx.of_type(&"waiting_room")[0]["open"]))
	assert_true(fx.server.sanity.in_bounds(INSIDE), "on the map again")


func test_practice_has_no_waiting_room() -> void:
	var solo := ServerFixture.new(1)
	LuckyLounge.describe_rooms(solo.server.map_def)
	solo.server.start_match()
	solo.run(3.2)
	assert_null(solo.server.fun_room, "only online lobbies have one")
	assert_eq(solo.intent(solo.player_ids[0], &"place_bet", {"station": BJ, "bet": {"amount": 50}})["error"], &"unknown_station")
	solo.server.free()
