extends GutTest
## Bust or Bank minigame logic (0.8.18 rules): one round of turn-based blackjack. Everyone gets one
## face-up card, then the turns go round the table in seat order: HIT takes exactly one card and
## passes the turn, STAND locks you, 20 s without a decision = STAND, over 21 = bust. Highest total
## wins. Cards are stacked on the shoe so every scenario is deterministic.

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


func _cards(ranks: Array[int]) -> Array[int]:
	var cards: Array[int] = []
	for r: int in ranks:
		cards.append(Card.make(r))
	return cards


## Stacks `ranks` on the shoe and plays the intro: the first cards go one each in seat order.
func _open(logic: BustOrBankLogic, ranks: Array[int]) -> void:
	logic.shoe.stack_top(_cards(ranks))
	_tick(logic, BustOrBankLogic.INTRO_TIME)


func _act(logic: BustOrBankLogic, p: int, action: String) -> Dictionary:
	var r: Dictionary = logic.submit(p, {"action": action}, 0.0)
	events.append_array(logic.drain_events())
	return r


func _hit(logic: BustOrBankLogic, p: int) -> void:
	var r: Dictionary = _act(logic, p, "hit")
	assert_true(r["ok"], "hit by %d: %s" % [p, str(r)])


func _stand(logic: BustOrBankLogic, p: int) -> void:
	var r: Dictionary = _act(logic, p, "stand")
	assert_true(r["ok"], "stand by %d: %s" % [p, str(r)])


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


func _turn_players() -> Array[int]:
	var out: Array[int] = []
	for e: Dictionary in _of(&"bust_or_bank_turn"):
		out.append(int(e["player"]))
	return out


# --- Start -------------------------------------------------------------------------------------

func test_intro_then_one_card_each_in_seat_order() -> void:
	var logic := _game([3, 1, 2] as Array[int])
	assert_eq(logic.state, BustOrBankLogic.State.INTRO)
	assert_eq(_of(&"bust_or_bank_round_started").size(), 1)
	assert_almost_eq(float(_of(&"bust_or_bank_round_started")[0]["deal_in"]), BustOrBankLogic.INTRO_TIME, 0.001)
	assert_eq(logic.hands[3].size(), 0, "no cards during the intro")
	_open(logic, [10, 5, 7])
	assert_eq(logic.hands[3], [Card.make(10)], "seat order: the order the minigame was set up with")
	assert_eq(logic.hands[1], [Card.make(5)])
	assert_eq(logic.hands[2], [Card.make(7)])
	var cards: Array[Dictionary] = _of(&"bust_or_bank_card")
	assert_eq(cards.size(), 3, "exactly one card each")
	assert_true(bool(cards[0]["opening"]))
	assert_eq(int(cards[1]["player"]), 1)
	assert_eq(int(cards[1]["total"]), 5)
	assert_eq(logic.state, BustOrBankLogic.State.TURN)
	assert_eq(logic.current, 3, "the first seat starts")
	assert_eq(_turn_players(), [3] as Array[int])
	assert_almost_eq(float(_of(&"bust_or_bank_turn")[0]["time"]), BustOrBankLogic.TURN_TIME, 0.001)


func test_next_card_is_the_shoes_top_card() -> void:
	var logic := _game([1, 2] as Array[int])
	logic.shoe.stack_top(_cards([10, 5, 7, 3]))
	assert_eq(logic.next_card, Card.make(10), "shown before the opening deal")
	_tick(logic, BustOrBankLogic.INTRO_TIME)
	assert_eq(logic.next_card, Card.make(7))
	assert_eq(int(_of(&"bust_or_bank_turn")[0]["next_card"]), Card.make(7), "the turn event shows it")
	assert_eq(int(logic.get_public_state()["next_card"]), Card.make(7))
	_hit(logic, 1)
	assert_eq(logic.hands[1].back(), Card.make(7), "the shown card is the one dealt")
	assert_eq(int(_of(&"bust_or_bank_card").back()["next_card"]), Card.make(3), "and the next one is revealed")
	assert_eq(logic.next_card, logic.shoe.peek())


# --- Turns -------------------------------------------------------------------------------------

func test_hit_deals_exactly_one_card_and_passes_the_turn() -> void:
	var logic := _game([1, 2, 3] as Array[int])
	_open(logic, [2, 3, 4, 5])
	_hit(logic, 1)
	assert_eq(logic.hands[1], _cards([2, 5]))
	assert_eq(logic.hands[2].size(), 1, "nobody else got a card")
	assert_eq(logic.current, 2, "next player's turn")
	assert_false(logic.standing[1], "still in after a hit")
	var last: Dictionary = _of(&"bust_or_bank_card").back()
	assert_eq(int(last["player"]), 1)
	assert_eq(int(last["total"]), 7)
	assert_false(bool(last["busted"]))


func test_only_the_current_player_may_act() -> void:
	var logic := _game([1, 2] as Array[int])
	assert_eq(_act(logic, 1, "hit")["error"], &"not_your_turn", "not during the intro")
	_open(logic, [2, 3, 4])
	assert_eq(_act(logic, 2, "hit")["error"], &"not_your_turn")
	assert_eq(_act(logic, 2, "stand")["error"], &"not_your_turn")
	assert_eq(_act(logic, 1, "double")["error"], &"invalid_action")
	assert_eq(_act(logic, 9, "hit")["error"], &"not_in_game")
	assert_eq(logic.hands[2].size(), 1)
	_hit(logic, 1)
	assert_eq(_act(logic, 1, "hit")["error"], &"not_your_turn", "one card per turn")


func test_turns_go_round_in_a_circle() -> void:
	var logic := _game([1, 2, 3] as Array[int])
	_open(logic, [2, 2, 2, 2, 2, 2, 2, 2, 2])
	_hit(logic, 1)
	_hit(logic, 2)
	_hit(logic, 3)
	_hit(logic, 1)
	assert_eq(_turn_players(), [1, 2, 3, 1, 2] as Array[int])


func test_stand_locks_the_player_and_the_circle_skips_them() -> void:
	var logic := _game([1, 2, 3] as Array[int])
	_open(logic, [2, 2, 2, 2, 2, 2, 2, 2])
	_stand(logic, 1)
	assert_true(logic.standing[1])
	assert_eq(logic.current, 2)
	var stood: Dictionary = _of(&"bust_or_bank_player_stood")[0]
	assert_eq(int(stood["player"]), 1)
	assert_false(bool(stood["auto"]))
	_hit(logic, 2)
	_hit(logic, 3)
	assert_eq(logic.current, 2, "1 stood: skipped")
	assert_eq(logic.hands[1].size(), 1, "a standing hand never changes")
	assert_eq(_act(logic, 1, "hit")["error"], &"already_stood")
	assert_eq(_turn_players(), [1, 2, 3, 2] as Array[int])


func test_bust_ends_participation_and_is_skipped() -> void:
	var logic := _game([1, 2, 3] as Array[int])
	_open(logic, [10, 2, 2, 10, 2, 5])
	_hit(logic, 1)  # 20
	_hit(logic, 2)  # 4
	_hit(logic, 3)  # 7
	_open_more(logic, [10])
	_hit(logic, 1)  # 30: bust
	assert_true(logic.busted[1])
	var last: Dictionary = _of(&"bust_or_bank_card").back()
	assert_true(bool(last["busted"]))
	assert_eq(int(last["total"]), 30)
	assert_eq(logic.current, 2)
	assert_eq(_act(logic, 1, "stand")["error"], &"already_busted")
	_hit(logic, 2)
	_hit(logic, 3)
	assert_eq(logic.current, 2, "the busted player is skipped")


func _open_more(logic: BustOrBankLogic, ranks: Array[int]) -> void:
	logic.shoe.stack_top(_cards(ranks))


func test_hitting_to_21_stands_automatically() -> void:
	var logic := _game([1, 2] as Array[int])
	_open(logic, [10, 2, 1])  # 1: 10, then an ace = 21
	_hit(logic, 1)
	assert_eq(logic._total(1), 21)
	assert_true(logic.standing[1], "can't do better than 21")
	assert_eq(StringName(_of(&"bust_or_bank_player_stood")[0]["reason"]), &"21")
	assert_eq(logic.current, 2)


func test_timeout_auto_stands_and_passes_the_turn() -> void:
	var logic := _game([1, 2, 3] as Array[int])
	_open(logic, [5, 6, 7])
	_tick(logic, BustOrBankLogic.TURN_TIME - 0.5)
	assert_eq(logic.current, 1, "still deciding")
	assert_almost_eq(float(logic.get_public_state()["timer"]), 0.5, 0.01)
	_tick(logic, 0.6)
	assert_true(logic.standing[1], "no decision in 20 s = stand")
	var stood: Dictionary = _of(&"bust_or_bank_player_stood")[0]
	assert_true(bool(stood["auto"]))
	assert_eq(StringName(stood["reason"]), &"timeout")
	assert_eq(logic.current, 2)
	assert_almost_eq(logic.timer, BustOrBankLogic.TURN_TIME, 0.001, "a fresh 20 s for the next player")


func test_a_lone_remaining_player_keeps_taking_turns() -> void:
	var logic := _game([1, 2] as Array[int])
	_open(logic, [2, 3, 2, 2, 2])
	_stand(logic, 1)
	assert_eq(logic.current, 2)
	_hit(logic, 2)
	assert_eq(logic.current, 2, "only 2 is still drawing: their turn again")
	_hit(logic, 2)
	assert_eq(logic.state, BustOrBankLogic.State.TURN)
	assert_eq(logic.hands[2].size(), 3)
	_stand(logic, 2)
	assert_eq(logic.state, BustOrBankLogic.State.RESULT)


func test_round_ends_when_everyone_is_done_then_the_minigame_finishes() -> void:
	var logic := _game([1, 2, 3] as Array[int])
	_open(logic, [10, 9, 2, 10])
	_stand(logic, 1)  # 10
	_stand(logic, 2)  # 9
	assert_eq(logic.state, BustOrBankLogic.State.TURN)
	_hit(logic, 3)  # 12
	assert_eq(logic.current, 3)
	_stand(logic, 3)
	assert_eq(logic.state, BustOrBankLogic.State.RESULT)
	assert_eq(logic.current, -1)
	assert_eq(logic.next_card, -1, "nothing more to deal")
	var end: Array[Dictionary] = _of(&"bust_or_bank_round_end")
	assert_eq(end.size(), 1, "one single round")
	assert_eq(end[0]["winners"], [3])
	assert_eq(int((end[0]["hands"] as Dictionary)[3]["total"]), 12)
	assert_eq(_act(logic, 3, "hit")["error"], &"game_over")
	assert_false(logic.is_finished(), "the result is shown first")
	_tick(logic, BustOrBankLogic.RESULT_TIME)
	assert_true(logic.is_finished())
	assert_eq(_of(&"bust_or_bank_round_started").size(), 1, "no further rounds")


# --- Ranking -----------------------------------------------------------------------------------

func test_ranking_highest_total_wins_ties_share_busts_last() -> void:
	var logic := _game([1, 2, 3, 4, 5] as Array[int])
	_open(logic, [10, 10, 9, 10, 10, 9, 9, 9, 10, 2])
	_hit(logic, 1)  # 19
	_hit(logic, 2)  # 19
	_hit(logic, 3)  # 18
	_hit(logic, 4)  # 20
	_hit(logic, 5)  # 12
	_open_more(logic, [10, 10])
	_hit(logic, 1)  # 29 bust
	_stand(logic, 2)
	_stand(logic, 3)
	_stand(logic, 4)
	_hit(logic, 5)  # 22 bust
	assert_eq(logic.state, BustOrBankLogic.State.RESULT)
	assert_eq(_rank_of(logic, 4), 1)
	assert_eq(_rank_of(logic, 2), 2)
	assert_eq(_rank_of(logic, 3), 3)
	assert_eq(_rank_of(logic, 1), 4, "busts below every standing hand")
	assert_eq(_rank_of(logic, 5), 4, "busts share one rank")
	assert_eq(logic.points(), {1: 0, 2: 19, 3: 18, 4: 20, 5: 0})
	var rk: Array[Dictionary] = logic.ranking()
	assert_eq(int(rk[0]["player"]), 4)
	assert_eq(int(rk[0]["points"]), 20)
	assert_true(bool(rk[4]["busted"]))
	assert_eq(logic.winners(), [4] as Array[int])


func test_equal_totals_share_first_place() -> void:
	var logic := _game([1, 2, 3] as Array[int])
	_open(logic, [10, 10, 5])
	_stand(logic, 1)
	_stand(logic, 2)
	_stand(logic, 3)
	assert_eq(_rank_of(logic, 1), 1)
	assert_eq(_rank_of(logic, 2), 1)
	assert_eq(_rank_of(logic, 3), 3)
	assert_eq(logic.winners(), [1, 2] as Array[int])


func test_blackjack_counts_as_21() -> void:
	var logic := _game([1, 2] as Array[int])
	_open(logic, [1, 10, 13])  # 1: A then K = blackjack
	_hit(logic, 1)
	assert_eq(logic._total(1), 21)
	assert_true(logic.standing[1])
	_stand(logic, 2)
	assert_eq(int(logic.ranking()[0]["points"]), 21, "no bonus: just 21")
	assert_eq(logic.winners(), [1] as Array[int])


func test_everyone_busting_shares_last_place() -> void:
	var logic := _game([1, 2] as Array[int])
	_open(logic, [10, 10, 10, 10, 10, 10])
	_hit(logic, 1)  # 20
	_hit(logic, 2)  # 20
	_hit(logic, 1)  # bust
	_hit(logic, 2)  # bust
	assert_eq(logic.state, BustOrBankLogic.State.RESULT)
	assert_eq(_rank_of(logic, 1), 1)
	assert_eq(_rank_of(logic, 2), 1)
	assert_eq(logic.points(), {1: 0, 2: 0})


# --- Leaving -----------------------------------------------------------------------------------

func test_remove_player_mid_turn_passes_the_turn() -> void:
	var logic := _game([1, 2, 3] as Array[int])
	_open(logic, [5, 6, 7])
	_hit(logic, 1)
	assert_eq(logic.current, 2)
	logic.remove_player(2)
	events.append_array(logic.drain_events())
	assert_eq(logic.current, 3, "the turn passes on")
	assert_eq(int(_of(&"bust_or_bank_player_left")[0]["player"]), 2)
	assert_eq(_turn_players().back(), 3)
	assert_almost_eq(logic.timer, BustOrBankLogic.TURN_TIME, 0.001)
	assert_false(logic.order.has(2))
	assert_eq(logic.ranking().size(), 2, "dropped from the ranking")
	_hit(logic, 3)
	assert_eq(logic.current, 1, "the circle closes without them")


func test_remove_other_player_keeps_the_current_turn() -> void:
	var logic := _game([1, 2, 3] as Array[int])
	_open(logic, [5, 6, 7])
	logic.remove_player(3)
	events.append_array(logic.drain_events())
	assert_eq(logic.current, 1)
	_stand(logic, 1)
	assert_eq(logic.current, 2)
	_stand(logic, 2)
	assert_eq(logic.state, BustOrBankLogic.State.RESULT)


func test_last_player_at_the_table_wins_when_the_rest_leave() -> void:
	var logic := _game([1, 2] as Array[int])
	_open(logic, [5, 6])
	logic.remove_player(1)
	events.append_array(logic.drain_events())
	assert_eq(logic.state, BustOrBankLogic.State.RESULT)
	assert_eq(logic.winners(), [2] as Array[int])
	logic.remove_player(2)
	_tick(logic, BustOrBankLogic.RESULT_TIME)
	assert_true(logic.is_finished())


# --- Snapshots ---------------------------------------------------------------------------------

func test_public_and_private_state() -> void:
	var logic := _game([1, 2] as Array[int])
	_open(logic, [5, 6, 7])
	_tick(logic, 4.0)
	var st: Dictionary = logic.get_public_state()
	assert_eq(int(st["state"]), BustOrBankLogic.State.TURN)
	assert_eq(int(st["current"]), 1)
	assert_almost_eq(float(st["timer"]), BustOrBankLogic.TURN_TIME - 4.0, 0.01)
	assert_almost_eq(float(st["turn_time"]), BustOrBankLogic.TURN_TIME, 0.001)
	assert_eq(st["players"], [1, 2])
	assert_eq((st["hands"] as Dictionary)[2]["cards"], [Card.make(6)], "every hand is public")
	assert_eq(int(st["next_card"]), Card.make(7))
	assert_false(st.has("ranking"))
	assert_true(bool(logic.private_state(1)["my_turn"]))
	assert_false(bool(logic.private_state(2)["my_turn"]))
	_stand(logic, 1)
	_stand(logic, 2)
	st = logic.get_public_state()
	assert_true(st.has("ranking"))
	assert_eq(st["winners"], [2])


func test_a_full_idle_game_ends_by_timeouts() -> void:
	var logic := _game([1, 2, 3, 4] as Array[int])
	var guard: int = 0
	while not logic.is_finished() and guard < 1000:
		guard += 1
		_tick(logic, 0.5)
	assert_true(logic.is_finished())
	assert_eq(_of(&"bust_or_bank_turn").size(), 4, "everyone gets one turn, then auto-stands")
	assert_eq(_of(&"bust_or_bank_player_stood").size(), 4)
	assert_eq(logic.ranking().size(), 4)
