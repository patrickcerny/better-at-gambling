extends GutTest
## The waiting room's play money (`FunRoom`, Patrick: "it doesn't add money or anything"): the
## blackjack table and the slots there run the real station logic on their own ledger. A win or a
## loss there never reaches the real balance, and every visit starts from fresh play chips.

const BJ: StringName = &"fun_blackjack_1"
const SLOT: StringName = &"fun_slot_1"
const OUTSIDE: Vector3 = Vector3(0, 0, 12.0)
const INSIDE: Vector3 = Vector3(0, 0, 18.0)

var real: Economy
var fun: FunRoom


func before_each() -> void:
	real = Economy.new()
	real.add_player(1, 1000)
	real.drain_events()
	fun = FunRoom.new({BJ: &"blackjack", SLOT: &"slots"}, Registry.game_logic_scripts(), Registry.balance, SeededRng.new(5), LuckyLounge.WAITING_AREA)


func _c(ranks: Array) -> Array[int]:
	var out: Array[int] = []
	for r: int in ranks:
		out.append(Card.make(r))
	return out


func _real_untouched() -> void:
	assert_eq(real.balance(1), 1000, "the real balance never moves")
	assert_eq(real.drain_events().size(), 0, "no real money events")


func test_ids_and_the_room() -> void:
	assert_true(FunRoom.is_fun(BJ))
	assert_true(FunRoom.is_fun("fun_slot_4"))
	assert_false(FunRoom.is_fun(&"blackjack_1"))
	assert_false(FunRoom.is_fun(&"slot_1"))
	assert_true(fun.contains(INSIDE))
	assert_false(fun.contains(OUTSIDE), "the start room is not the waiting room")
	for sid: StringName in LuckyLounge.FUN_STATIONS:
		assert_true(FunRoom.is_fun(sid), "%s carries the fun_ prefix" % sid)
		assert_false(Registry.maps[&"lucky_lounge"].stations.has(sid), "%s is not a casino station" % sid)


func test_every_visit_starts_from_fresh_play_chips() -> void:
	assert_false(fun.update_presence(1, OUTSIDE))
	assert_eq(fun.balance(1), 0, "no chips before the first visit")
	assert_true(fun.update_presence(1, INSIDE), "walking in is a visit")
	assert_eq(fun.balance(1), FunRoom.PLAY_CHIPS)
	assert_false(fun.update_presence(1, INSIDE + Vector3(1, 0, 1)), "walking around inside is the same visit")
	fun.economy.apply(1, -400, &"bet_blackjack")
	assert_false(fun.update_presence(1, OUTSIDE))
	assert_eq(fun.balance(1), 600, "the chips stay as they are while away")
	assert_true(fun.update_presence(1, INSIDE), "back in: a new visit")
	assert_eq(fun.balance(1), FunRoom.PLAY_CHIPS, "reset to the fixed stack on re-entry")
	fun.economy.apply(1, 2500, &"win_slots")
	fun.update_presence(1, OUTSIDE)
	fun.update_presence(1, INSIDE)
	assert_eq(fun.balance(1), FunRoom.PLAY_CHIPS, "winnings don't carry over either")
	for ev: Dictionary in fun.drain_events():
		assert_true(bool(ev.get("fun", false)), "%s is tagged fun" % ev["type"])
	_real_untouched()


func test_a_fun_blackjack_win_pays_only_play_chips() -> void:
	fun.update_presence(1, INSIDE)
	assert_true(fun.sit(1, BJ)["ok"])
	assert_true(fun.route(1, {"type": &"place_bet", "station": BJ, "bet": {"amount": 100}})["ok"])
	assert_eq(fun.balance(1), 900, "the stake comes off the play chips")
	(fun.stations.logics[BJ] as BlackjackLogic).shoe.stack_top(_c([1, 9, 13, 7]))  # A,K vs 9,7
	fun.tick(8.5)
	assert_eq(fun.balance(1), 1150, "blackjack pays 3:2 in play chips")
	var results: Array = []
	for ev: Dictionary in fun.drain_events():
		assert_true(bool(ev.get("fun", false)), "%s is tagged fun" % ev["type"])
		if ev["type"] == &"round_result":
			results.append(ev)
	assert_eq(results.size(), 1)
	assert_eq(int(results[0]["net"]), 150)
	_real_untouched()


func test_a_fun_slots_loss_costs_only_play_chips() -> void:
	fun.update_presence(1, INSIDE)
	assert_true(fun.sit(1, SLOT)["ok"])
	var sl: SlotsLogic = fun.stations.logics[SLOT] as SlotsLogic
	var bet: int = sl.bet_sizes()[0]
	assert_true(fun.route(1, {"type": &"place_bet", "station": SLOT, "bet": {"amount": bet}})["ok"])
	var S := SlotsLogic.Sym
	sl.line = [S.LEMON, S.BELL, S.BAR] as Array[int]  # a sure loss
	for i: int in 200:
		fun.tick(0.05)
	assert_false(sl.has_stake(1), "the spin settled")
	assert_eq(fun.balance(1), FunRoom.PLAY_CHIPS - bet, "lost on play chips")
	assert_null(sl.jackpot, "play money never feeds the progressive jackpot")
	_real_untouched()


func test_no_luck_or_items_at_the_fun_tables() -> void:
	var mods: ModifierStack = (fun.stations.logics[BJ] as StationLogicBase).modifiers
	assert_eq(mods.get_luck(1, &"blackjack"), 0, "an empty modifier stack of its own")
	assert_false(fun.stations.hot.has(BJ))


func test_a_closed_room_refuses_everything() -> void:
	fun.update_presence(1, INSIDE)
	assert_true(fun.sit(1, SLOT)["ok"])
	var seated: Array[int] = fun.close()
	assert_eq(seated, [1] as Array[int], "the server stands them up")
	assert_false(fun.open)
	assert_eq(fun.sit(1, BJ)["error"], &"room_closed")
	assert_eq(fun.route(1, {"type": &"place_bet", "station": BJ, "bet": {"amount": 100}})["error"], &"room_closed")
	fun.update_presence(1, OUTSIDE)
	assert_false(fun.update_presence(1, INSIDE), "no new visits while shut")
	_real_untouched()
