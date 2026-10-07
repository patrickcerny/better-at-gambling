extends GutTest
## Bust or Bank minigame logic: one shared shoe, stand any time, bust = out on the spot, worst
## standing hand(s) out each round, last player standing wins. Cards are stacked on the shoe so
## every scenario is deterministic.

var cfg: BalanceConfig
var events: Array[Dictionary] = []


func before_each() -> void:
	cfg = BalanceConfig.new()
	events.clear()


func _game(players: Array[int]) -> BustOrBankLogic:
	var logic := BustOrBankLogic.new()
	logic.setup(players, SeededRng.new(5), cfg, {}, {})
	events.append_array(logic.drain_events())
	return logic


func _tick(logic: BustOrBankLogic, seconds: float) -> void:
	logic.tick(seconds, 0.0)
	events.append_array(logic.drain_events())


## Stacks `ranks` (no aces unless asked) and plays the round's intro: the first two are dealt.
func _open(logic: BustOrBankLogic, ranks: Array[int]) -> void:
	var cards: Array[int] = []
	for r: int in ranks:
		cards.append(Card.make(r))
	logic.shoe.stack_top(cards)
	_tick(logic, BustOrBankLogic.INTRO_TIME)


func _next_card(logic: BustOrBankLogic) -> void:
	_tick(logic, BustOrBankLogic.DEAL_INTERVAL)


func _stand(logic: BustOrBankLogic, p: int) -> Dictionary:
	var r: Dictionary = logic.submit(p, {"action": "stand"}, 0.0)
	events.append_array(logic.drain_events())
	return r


func _of(type: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in events:
		if e["type"] == type:
			out.append(e)
	return out


func _rank_of(logic: BustOrBankLogic, p: int) -> int:
	for row: Dictionary in logic.ranking():
		if int(row["player"]) == p:
			return int(row["rank"])
	return -1


# --- Setup & dealing ---------------------------------------------------------------------------

func test_setup_starts_round_zero_with_everyone() -> void:
	var logic := _game([1, 2, 3])
	assert_false(logic.is_finished())
	assert_eq(logic.round, 0)
	assert_eq(logic.state, BustOrBankLogic.State.INTRO)
	assert_eq(_of(&"bust_or_bank_started").size(), 1)
	var rs: Array[Dictionary] = _of(&"bust_or_bank_round_started")
	assert_eq(rs.size(), 1)
	assert_eq(rs[0]["players"], [1, 2, 3])
	assert_false(rs[0]["replay"])


func test_shared_shoe_deals_the_same_cards_to_everyone_at_once() -> void:
	var logic := _game([1, 2, 3])
	_open(logic, [10, 5])
	var dealt: Array[Dictionary] = _of(&"bust_or_bank_card")
	assert_eq(dealt.size(), 2, "two opening cards")
	for e: Dictionary in dealt:
		assert_eq(e["receivers"], [1, 2, 3], "one card goes to everyone")
	for p: int in [1, 2, 3]:
		assert_eq(logic._total(p), 15)
	assert_eq(logic.state, BustOrBankLogic.State.DEALING)


func test_standing_stops_your_cards_but_not_the_others() -> void:
	var logic := _game([1, 2])
	_open(logic, [10, 5, 3])
	assert_true(_stand(logic, 1)["ok"])
	_next_card(logic)
	assert_eq(logic._total(1), 15, "stood: keeps 15")
	assert_eq(logic._total(2), 18)
	assert_eq(_of(&"bust_or_bank_card").back()["receivers"], [2])


func test_cards_keep_coming_on_a_timer() -> void:
	var logic := _game([1, 2])
	_open(logic, [2, 2, 2, 2])
	_tick(logic, BustOrBankLogic.DEAL_INTERVAL * 0.5)
	assert_eq(logic._total(1), 4, "not yet")
	_tick(logic, BustOrBankLogic.DEAL_INTERVAL * 0.5)
	assert_eq(logic._total(1), 6)


func test_bust_is_announced_immediately_and_player_cannot_stand() -> void:
	var logic := _game([1, 2, 3])
	_open(logic, [10, 2, 10])
	_stand(logic, 1)  # 12
	_next_card(logic)  # 2 and 3 reach 22
	var busts: Array[Dictionary] = _of(&"bust_or_bank_player_bust")
	assert_eq(busts.size(), 2)
	assert_eq(int(busts[0]["total"]), 22)
	assert_false(logic.private_state(2)["can_stand"])
	# Before the round result in the same batch: clients can show the bust right away.
	var types: Array = events.map(func(e: Dictionary) -> StringName: return e["type"])
	assert_lt(types.find(&"bust_or_bank_player_bust"), types.find(&"bust_or_bank_round_end"))


func test_exact_21_stands_automatically() -> void:
	var logic := _game([1, 2])
	_open(logic, [10, 1])  # A + 10 = 21
	var stood: Array[Dictionary] = _of(&"bust_or_bank_player_stood")
	assert_eq(stood.size(), 2)
	assert_true(stood[0]["auto"])


func test_invalid_actions_are_rejected() -> void:
	var logic := _game([1, 2])
	assert_eq(logic.submit(1, {"action": "stand"}, 0.0)["error"], &"not_dealing", "no standing before the cards")
	_open(logic, [10, 5])
	assert_eq(logic.submit(1, {"action": "hit"}, 0.0)["error"], &"invalid_action", "the shoe deals, nobody hits")
	assert_eq(logic.submit(9, {"action": "stand"}, 0.0)["error"], &"not_in_game")
	_stand(logic, 1)
	assert_eq(logic.submit(1, {"action": "stand"}, 0.0)["error"], &"already_stood")


# --- Round end & elimination -------------------------------------------------------------------

func test_worst_standing_hand_is_thrown_out() -> void:
	var logic := _game([1, 2, 3])
	_open(logic, [10, 2, 5, 3])
	_stand(logic, 1)  # 12
	_next_card(logic)  # 17
	_stand(logic, 2)
	_next_card(logic)  # 20
	_stand(logic, 3)
	var ends: Array[Dictionary] = _of(&"bust_or_bank_round_end")
	assert_eq(ends.size(), 1)
	assert_eq(ends[0]["eliminated"], [1])
	assert_eq(ends[0]["worst"], [1])
	assert_eq(ends[0]["remaining"], [2, 3])
	assert_eq(logic.in_round, [2, 3] as Array[int])


func test_ties_for_worst_all_go() -> void:
	var logic := _game([1, 2, 3, 4])
	_open(logic, [10, 2, 5])
	_stand(logic, 1)
	_stand(logic, 2)  # both 12
	_next_card(logic)  # 17
	_stand(logic, 3)
	_stand(logic, 4)
	var end: Dictionary = _of(&"bust_or_bank_round_end")[0]
	assert_eq(end["eliminated"], [1, 2])
	assert_eq(logic.in_round, [3, 4] as Array[int])
	assert_eq(_rank_of(logic, 1), _rank_of(logic, 2), "same round, same rank")


func test_everyone_tied_standing_means_nobody_is_out() -> void:
	var logic := _game([1, 2])
	_open(logic, [10, 7])
	_stand(logic, 1)
	_stand(logic, 2)
	var end: Dictionary = _of(&"bust_or_bank_round_end")[0]
	assert_eq(end["eliminated"], [])
	assert_eq(logic.in_round, [1, 2] as Array[int])
	_tick(logic, BustOrBankLogic.RESULT_TIME)
	assert_eq(_of(&"bust_or_bank_round_started").size(), 2, "they play again")


func test_busted_players_rank_below_the_worst_standing_hand() -> void:
	var logic := _game([1, 2, 3])
	_open(logic, [10, 2, 5, 10])
	_stand(logic, 1)  # 12: worst standing hand
	_next_card(logic)  # 17
	_stand(logic, 2)
	_next_card(logic)  # 3 busts at 27
	var end: Dictionary = _of(&"bust_or_bank_round_end")[0]
	assert_eq(end["busted"], [3])
	assert_eq(end["worst"], [1])
	assert_eq(_rank_of(logic, 2), 1)
	assert_eq(_rank_of(logic, 1), 2, "worst hand above the bust")
	assert_eq(_rank_of(logic, 3), 3)


func test_bust_is_out_even_if_standing_hands_tie() -> void:
	var logic := _game([1, 2, 3])
	_open(logic, [10, 2, 10])
	_stand(logic, 1)
	_stand(logic, 2)  # 12 and 12: nobody strictly better, so no worst-hand cut
	_next_card(logic)  # 3 busts
	var end: Dictionary = _of(&"bust_or_bank_round_end")[0]
	assert_eq(end["eliminated"], [3])
	assert_eq(logic.in_round, [1, 2] as Array[int])


func test_everyone_busting_replays_the_round() -> void:
	var logic := _game([1, 2, 3])
	_open(logic, [10, 2, 10])
	_next_card(logic)  # all at 22
	var end: Dictionary = _of(&"bust_or_bank_round_end")[0]
	assert_true(end["replay"])
	assert_eq(end["eliminated"], [])
	assert_eq(end["busted"], [1, 2, 3])
	assert_eq(logic.in_round, [1, 2, 3] as Array[int])
	_tick(logic, BustOrBankLogic.RESULT_TIME)
	var rs: Array[Dictionary] = _of(&"bust_or_bank_round_started")
	assert_eq(rs.size(), 2)
	assert_true(rs[1]["replay"])
	assert_eq(rs[1]["players"], [1, 2, 3])
	for p: int in [1, 2, 3]:
		assert_eq(logic._total(p), 0, "fresh count")
		assert_false(logic.busted[p])


func test_replay_only_includes_players_still_in() -> void:
	var logic := _game([1, 2, 3])
	_open(logic, [10, 2, 5])
	_stand(logic, 1)
	_next_card(logic)
	_stand(logic, 2)
	_stand(logic, 3)  # tie 17 vs 12: 1 out
	_tick(logic, BustOrBankLogic.RESULT_TIME)
	_open(logic, [10, 2, 10])
	_next_card(logic)  # 2 and 3 both bust
	_tick(logic, BustOrBankLogic.RESULT_TIME)
	var rs: Array[Dictionary] = _of(&"bust_or_bank_round_started")
	assert_eq(rs.back()["players"], [2, 3])
	assert_true(rs.back()["replay"])


# --- Points & ranking --------------------------------------------------------------------------

func test_round_end_carries_absolute_points_for_every_player() -> void:
	var logic := _game([1, 2, 3])
	_open(logic, [10, 2, 5, 3])
	_stand(logic, 1)
	_next_card(logic)
	_stand(logic, 2)
	_next_card(logic)
	_stand(logic, 3)
	var pts: Dictionary = _of(&"bust_or_bank_round_end")[0]["points"]
	assert_eq(pts.size(), 3, "every player, not just a winner")
	assert_eq(int(pts[1]), 0)
	assert_eq(int(pts[2]), 1)
	assert_eq(int(pts[3]), 1)
	assert_eq(logic.get_public_state()["points"], pts)


func test_full_game_to_one_survivor() -> void:
	var logic := _game([1, 2, 3])
	# Round 1: 1 out.
	_open(logic, [10, 2, 5, 3])
	_stand(logic, 1)
	_next_card(logic)
	_stand(logic, 2)
	_next_card(logic)
	_stand(logic, 3)
	_tick(logic, BustOrBankLogic.RESULT_TIME)
	# Round 2: 3 busts.
	_open(logic, [10, 6, 9])
	_stand(logic, 2)  # 16
	_next_card(logic)  # 3 → 25
	assert_eq(_of(&"bust_or_bank_finished").size(), 1, "announced with the last result")
	assert_false(logic.is_finished(), "the result is shown first")
	_tick(logic, BustOrBankLogic.RESULT_TIME)
	assert_true(logic.is_finished())
	var ranking: Array[Dictionary] = logic.ranking()
	assert_eq(ranking.map(func(r: Dictionary) -> int: return r["player"]), [2, 3, 1])
	assert_eq(ranking.map(func(r: Dictionary) -> int: return r["rank"]), [1, 2, 3])
	assert_eq(ranking.map(func(r: Dictionary) -> int: return r["points"]), [2, 1, 0])
	assert_eq(_of(&"bust_or_bank_round_end").back()["points"], {1: 0, 2: 2, 3: 1})


func test_shared_ranks_skip_like_competition_ranking() -> void:
	var logic := _game([1, 2, 3, 4])
	_open(logic, [10, 2, 5, 3])
	_stand(logic, 1)
	_stand(logic, 2)  # 12, 12
	_next_card(logic)
	_stand(logic, 3)  # 17
	_next_card(logic)
	_stand(logic, 4)  # 20; 1 and 2 out together
	_tick(logic, BustOrBankLogic.RESULT_TIME)
	_open(logic, [10, 7, 2])
	_stand(logic, 3)  # 17
	_next_card(logic)
	_stand(logic, 4)  # 19
	_tick(logic, BustOrBankLogic.RESULT_TIME)
	assert_true(logic.is_finished())
	var ranks: Dictionary = {}
	for r: Dictionary in logic.ranking():
		ranks[r["player"]] = r["rank"]
	assert_eq(ranks, {4: 1, 3: 2, 1: 3, 2: 3})


func test_idle_players_still_finish() -> void:
	var logic := _game([1, 2, 3])
	var t: float = 0.0
	while not logic.is_finished() and t < 600.0:
		_tick(logic, 0.1)
		t += 0.1
	assert_true(logic.is_finished(), "nobody pressing anything can't stall the match")
	assert_lte(logic.round, logic.max_rounds)
	assert_eq(logic.max_rounds, 3 + BustOrBankLogic.SPARE_ROUNDS)
	assert_lt(t, 90.0, "idle table ends well inside a minigame slot")
	assert_eq(logic.ranking().size(), 3)


func test_disconnect_drops_the_player_and_can_end_the_game() -> void:
	var logic := _game([1, 2, 3])
	_open(logic, [10, 2])
	logic.remove_player(3)
	assert_eq(logic.in_round, [1, 2] as Array[int])
	logic.remove_player(2)
	events.append_array(logic.drain_events())
	assert_true(logic.is_finished())
	assert_eq(logic.ranking().size(), 1)
	assert_eq(int(logic.ranking()[0]["player"]), 1)


func test_disconnect_of_the_last_drawer_ends_the_round() -> void:
	var logic := _game([1, 2, 3])
	_open(logic, [10, 2, 5])
	_stand(logic, 1)
	_stand(logic, 2)
	logic.remove_player(3)
	events.append_array(logic.drain_events())
	assert_eq(_of(&"bust_or_bank_round_end").size(), 1)
