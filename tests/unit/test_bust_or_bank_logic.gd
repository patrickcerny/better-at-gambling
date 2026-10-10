extends GutTest
## Bust or Bank minigame logic: turn-based blackjack in elimination rounds. Every round everyone
## still in gets one face-up card, then the turns go round the table: HIT takes exactly one card
## and passes the turn, STAND locks you, 20 s without a decision = STAND, over 21 = bust. After the
## round the busted players are out, else the lowest hand (ties together); if that would be
## everyone, the round is replayed. Last player in wins. Cards are stacked on the shoe so every
## scenario is deterministic.

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
	assert_eq(int(_of(&"bust_or_bank_round_started")[0]["round"]), 1)
	assert_eq(_of(&"bust_or_bank_round_started")[0]["survivors"], [3, 1, 2])
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


func test_the_next_card_is_the_shoes_top_card_and_stays_secret() -> void:
	var logic := _game([1, 2] as Array[int])
	logic.shoe.stack_top(_cards([10, 5, 7, 3]))
	assert_eq(logic.next_card, Card.make(10), "server-side, before the opening deal")
	_tick(logic, BustOrBankLogic.INTRO_TIME)
	assert_eq(logic.next_card, Card.make(7))
	assert_false(_of(&"bust_or_bank_turn")[0].has("next_card"), "the turn event doesn't show it")
	assert_false(logic.get_public_state().has("next_card"), "nor does the snapshot")
	_hit(logic, 1)
	assert_eq(logic.hands[1].back(), Card.make(7), "the top card is the one dealt")
	assert_false(_of(&"bust_or_bank_card").back().has("next_card"), "and the next one stays a gamble")
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




func _round_end() -> Dictionary:
	return _of(&"bust_or_bank_round_end").back()


## Ends the RESULT pause between rounds.
func _next_round(logic: BustOrBankLogic) -> void:
	assert_eq(logic.state, BustOrBankLogic.State.RESULT)
	_tick(logic, BustOrBankLogic.RESULT_TIME + 0.01)


# --- Eliminations ------------------------------------------------------------------------------

func test_round_ends_and_the_lowest_hand_is_out() -> void:
	var logic := _game([1, 2, 3] as Array[int])
	_open(logic, [10, 9, 2, 10])
	_stand(logic, 1)  # 10
	_stand(logic, 2)  # 9
	assert_eq(logic.state, BustOrBankLogic.State.TURN)
	_hit(logic, 3)  # 12
	_stand(logic, 3)
	assert_eq(logic.state, BustOrBankLogic.State.RESULT)
	assert_eq(logic.current, -1)
	assert_eq(logic.next_card, -1, "nothing to deal between rounds")
	var end: Dictionary = _round_end()
	assert_eq(int(end["round"]), 1)
	assert_eq(end["out"], [2], "nobody busted: the lowest standing total (9) is out")
	assert_eq(StringName(end["why"]), &"lowest")
	assert_eq(int(end["lowest"]), 9)
	assert_eq(end["survivors"], [1, 3])
	assert_false(bool(end["final"]))
	assert_eq(int((end["hands"] as Dictionary)[3]["total"]), 12)
	assert_eq(logic.out_round, {2: 1} as Dictionary[int, int])
	assert_eq(_act(logic, 3, "hit")["error"], &"not_your_turn", "nothing to do between rounds")
	assert_eq(_act(logic, 2, "hit")["error"], &"eliminated")
	assert_false(logic.is_finished(), "the next round follows")
	_tick(logic, BustOrBankLogic.RESULT_TIME)
	assert_eq(_of(&"bust_or_bank_round_started").size(), 2)
	var started: Dictionary = _of(&"bust_or_bank_round_started").back()
	assert_eq(int(started["round"]), 2)
	assert_eq(started["survivors"], [1, 3])
	assert_eq(started["players"], [1, 2, 3], "the eliminated stay at the table")
	assert_eq(logic.hands[1].size(), 0, "fresh hands for everyone still in")
	assert_eq(logic.hands[2].size(), 1, "the eliminated keep showing their last hand")


func test_only_the_busted_go_out() -> void:
	var logic := _game([1, 2, 3, 4] as Array[int])
	_open(logic, [10, 9, 8, 2, 10, 10, 6, 5, 5])
	_hit(logic, 1)  # 20
	_hit(logic, 2)  # 19
	_hit(logic, 3)  # 14
	_stand(logic, 4)  # 2: the lowest, but nobody busted yet
	_stand(logic, 1)
	_hit(logic, 2)  # 24: bust
	_hit(logic, 3)  # 19
	assert_eq(logic.current, 3, "the only one still drawing")
	_stand(logic, 3)
	assert_eq(logic.state, BustOrBankLogic.State.RESULT)
	var end: Dictionary = _round_end()
	assert_eq(end["out"], [2], "a bust is out on the spot; the lowest standing hand survives")
	assert_eq(StringName(end["why"]), &"busted")
	assert_eq(end["survivors"], [1, 3, 4])


func test_several_busts_go_out_together() -> void:
	var logic := _game([1, 2, 3] as Array[int])
	_open(logic, [10, 10, 5, 10, 10, 9, 10, 10])
	_hit(logic, 1)  # 20
	_hit(logic, 2)  # 20
	_hit(logic, 3)  # 14
	_hit(logic, 1)  # 30 bust
	_hit(logic, 2)  # 30 bust
	_stand(logic, 3)
	var end: Dictionary = _round_end()
	assert_eq(end["out"], [1, 2])
	assert_eq(end["survivors"], [3])
	assert_true(bool(end["final"]), "one player left: the game is over")
	assert_eq(logic.winners(), [3] as Array[int])
	assert_eq(_rank_of(logic, 1), 2, "the two busts share second place")
	assert_eq(_rank_of(logic, 2), 2)
	assert_eq(logic.points(), {1: 0, 2: 0, 3: 2} as Dictionary[int, int])


func test_a_shared_lowest_total_goes_out_together() -> void:
	var logic := _game([1, 2, 3, 4] as Array[int])
	_open(logic, [10, 7, 10, 7])
	for p: int in [1, 2, 3, 4]:
		_stand(logic, p)
	var end: Dictionary = _round_end()
	assert_eq(end["out"], [2, 4], "both 7s are out")
	assert_eq(end["survivors"], [1, 3])
	assert_eq(_rank_of(logic, 2), _rank_of(logic, 4), "out in the same round with the same hand: shared rank")


func test_everyone_tied_plays_again() -> void:
	var logic := _game([1, 2, 3] as Array[int])
	_open(logic, [10, 10, 10])
	for p: int in [1, 2, 3]:
		_stand(logic, p)
	var end: Dictionary = _round_end()
	assert_eq(end["out"], [], "it would be everyone: nobody is out")
	assert_eq(StringName(end["why"]), &"replay")
	assert_eq(end["survivors"], [1, 2, 3])
	assert_false(bool(end["final"]))
	_next_round(logic)
	assert_eq(int(_of(&"bust_or_bank_round_started").back()["round"]), 2)
	assert_eq(logic.alive, [1, 2, 3] as Array[int])


func test_everyone_busting_plays_again() -> void:
	var logic := _game([1, 2, 3] as Array[int])
	_open(logic, [10, 10, 10, 10, 10, 10, 10, 10, 10])
	for p: int in [1, 2, 3]:
		_hit(logic, p)  # 20 each
	for p: int in [1, 2, 3]:
		_hit(logic, p)  # 30 each: bust
	var end: Dictionary = _round_end()
	assert_eq(end["out"], [])
	assert_eq(StringName(end["why"]), &"replay")
	assert_false(bool(end["final"]))
	_next_round(logic)
	assert_eq(logic.state, BustOrBankLogic.State.INTRO)
	for p: int in [1, 2, 3]:
		assert_false(logic.busted[p], "a fresh start")
		assert_eq(logic.hands[p].size(), 0)


func test_rounds_repeat_until_one_remains() -> void:
	var logic := _game([1, 2, 3, 4] as Array[int])
	assert_eq(logic.max_rounds, 3, "players - 1 rounds at most")
	# Round 1: 3 busts.
	_open(logic, [10, 9, 8, 7, 10, 10, 10, 10, 5])
	for p: int in [1, 2, 3, 4]:
		_hit(logic, p)  # 20, 19, 18, 17
	_stand(logic, 1)
	_stand(logic, 2)
	_hit(logic, 3)  # 23: bust
	_stand(logic, 4)
	assert_eq(_round_end()["out"], [3])
	_next_round(logic)
	# Round 2: the circle starts one seat further (2) and the cards go 2, 4, 1.
	assert_eq(logic.starter, 2)
	_open(logic, [10, 10, 9])
	assert_eq(logic.hands[2], [Card.make(10)])
	assert_eq(logic.hands[1], [Card.make(9)])
	assert_eq(logic.current, 2, "the round's starter goes first")
	assert_eq(logic.hands[3].size(), 3, "3 is out: no new cards, their bust stays on show")
	assert_eq(_act(logic, 3, "stand")["error"], &"eliminated")
	_stand(logic, 2)
	assert_eq(logic.current, 4, "3 is skipped")
	_stand(logic, 4)
	_stand(logic, 1)
	assert_eq(_round_end()["out"], [1])
	assert_eq(int(_round_end()["round"]), 2)
	_next_round(logic)
	# Round 3: after 2 comes 3 (out), so 4 starts.
	assert_eq(logic.starter, 4)
	_open(logic, [10, 9])
	assert_eq(logic.current, 4)
	_stand(logic, 4)
	_stand(logic, 2)
	var end: Dictionary = _round_end()
	assert_eq(end["out"], [2])
	assert_eq(end["survivors"], [4])
	assert_true(bool(end["final"]))
	var fin: Array[Dictionary] = _of(&"bust_or_bank_finished")
	assert_eq(fin.size(), 1)
	assert_eq(fin[0]["winners"], [4])
	assert_eq(_of(&"bust_or_bank_round_started").size(), 3)
	assert_false(logic.is_finished(), "the final result is shown first")
	assert_eq(_act(logic, 4, "hit")["error"], &"game_over")
	_tick(logic, BustOrBankLogic.RESULT_TIME)
	assert_true(logic.is_finished())
	assert_eq(_of(&"bust_or_bank_round_started").size(), 3, "no further rounds")
	# Winner, then later rounds out above earlier ones; points = players outlasted.
	var rk: Array[Dictionary] = logic.ranking()
	var order: Array[int] = []
	for row: Dictionary in rk:
		order.append(int(row["player"]))
	assert_eq(order, [4, 2, 1, 3] as Array[int])
	assert_eq(int(rk[1]["out_round"]), 3)
	assert_eq(int(rk[3]["out_round"]), 1)
	assert_eq(logic.points(), {4: 3, 2: 2, 1: 1, 3: 0} as Dictionary[int, int])
	assert_eq(fin[0]["points"], logic.points())


func test_the_round_limit_ends_a_tied_table_with_a_shared_win() -> void:
	var logic := _game([1, 2, 3] as Array[int])
	_open(logic, [10, 10, 10])
	for p: int in [1, 2, 3]:
		_stand(logic, p)
	_next_round(logic)  # replay
	_open(logic, [9, 9, 9])
	for p: int in [2, 3, 1]:
		_stand(logic, p)
	var end: Dictionary = _round_end()
	assert_eq(end["out"], [])
	assert_true(bool(end["final"]), "round 2 of 2 at most")
	assert_eq(logic.winners(), [1, 2, 3] as Array[int], "the survivors share the win")
	assert_eq(logic.points(), {1: 0, 2: 0, 3: 0} as Dictionary[int, int])


func test_the_game_cap_ends_the_round_and_ranks_survivors_by_hand() -> void:
	var logic := _game([1, 2, 3, 4] as Array[int])
	_open(logic, [10, 9, 8, 7])
	logic.game_time = BustOrBankLogic.GAME_CAP - 1.0
	_tick(logic, 1.1)
	var capped: Array[Dictionary] = _of(&"bust_or_bank_player_stood").filter(func(e: Dictionary) -> bool: return e["reason"] == &"game_cap")
	assert_eq(capped.size(), 4, "everyone undecided stands")
	var end: Dictionary = _round_end()
	assert_eq(end["out"], [4], "the round still counts: the lowest hand is out")
	assert_true(bool(end["final"]), "and it was the last")
	assert_eq(_rank_of(logic, 1), 1)
	assert_eq(_rank_of(logic, 2), 2, "survivors ranked by their hand")
	assert_eq(_rank_of(logic, 3), 3)
	assert_eq(_rank_of(logic, 4), 4)
	assert_eq(logic.winners(), [1] as Array[int])


func test_an_idle_table_of_eight_finishes_within_the_game_cap() -> void:
	var logic := _game([1, 2, 3, 4, 5, 6, 7, 8] as Array[int])
	var t: float = 0.0
	while not logic.is_finished() and t < 1000.0:
		_tick(logic, 0.5)
		t += 0.5
	assert_true(logic.is_finished())
	assert_lte(t, BustOrBankLogic.GAME_CAP + BustOrBankLogic.RESULT_TIME + 1.0, "about 7 minutes at most")
	assert_lte(_of(&"bust_or_bank_round_started").size(), 7, "players - 1 rounds at most")
	assert_eq(_of(&"bust_or_bank_finished").size(), 1)
	assert_eq(logic.ranking().size(), 8)
	assert_false(logic.winners().is_empty())


# --- Spectators --------------------------------------------------------------------------------

func test_eliminated_players_watch_the_rest() -> void:
	var logic := _game([1, 2, 3] as Array[int])
	_open(logic, [10, 9, 5])
	for p: int in [1, 2, 3]:
		_stand(logic, p)
	_next_round(logic)
	_open(logic, [10, 7])
	assert_eq(logic.alive, [1, 2] as Array[int])
	assert_eq(logic.hands[3], [Card.make(5)], "their last hand stays on the table")
	assert_eq(_act(logic, 3, "hit")["error"], &"eliminated")
	assert_true(bool(logic.private_state(3)["out"]))
	assert_false(bool(logic.private_state(3)["my_turn"]))
	assert_false(bool(logic.private_state(2)["out"]))
	var st: Dictionary = logic.get_public_state()
	assert_eq(int(st["round"]), 2)
	assert_eq(st["players"], [1, 2, 3], "spectators keep their seat")
	assert_eq(st["survivors"], [1, 2])
	assert_eq(st["out"], {3: 1})
	assert_eq(int((st["hands"] as Dictionary)[3]["out"]), 1)
	assert_eq(int((st["hands"] as Dictionary)[1]["out"]), 0)
	assert_false(st.has("ranking"), "no final ranking mid-game")
	assert_false(bool(st["final"]))


func test_the_turn_circle_never_includes_the_eliminated() -> void:
	var logic := _game([1, 2, 3] as Array[int])
	_open(logic, [10, 5, 9])
	for p: int in [1, 2, 3]:
		_stand(logic, p)  # 2 out
	_next_round(logic)
	_open(logic, [2, 2, 2, 2, 2])  # starter 3 (after 2... which is out: the next one in)
	_hit(logic, logic.current)
	_hit(logic, logic.current)
	_hit(logic, logic.current)
	var round2: Array[int] = []
	for e: Dictionary in _of(&"bust_or_bank_turn"):
		if int(e["round"]) == 2:
			round2.append(int(e["player"]))
	assert_eq(round2, [3, 1, 3, 1] as Array[int], "the circle starts after the last starter and skips 2")


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
	assert_true(logic.final)
	assert_eq(logic.winners(), [2] as Array[int])
	logic.remove_player(2)
	_tick(logic, BustOrBankLogic.RESULT_TIME)
	assert_true(logic.is_finished())


func test_a_spectator_leaving_changes_nothing() -> void:
	var logic := _game([1, 2, 3, 4] as Array[int])
	_open(logic, [10, 9, 8, 5])
	for p: int in [1, 2, 3, 4]:
		_stand(logic, p)  # 4 out
	_next_round(logic)
	_open(logic, [10, 9, 8])
	var cur: int = logic.current
	logic.remove_player(4)
	events.append_array(logic.drain_events())
	assert_eq(logic.current, cur)
	assert_eq(logic.state, BustOrBankLogic.State.TURN)
	assert_eq(logic.alive.size(), 3)
	assert_false((logic.get_public_state()["out"] as Dictionary).has(4))


func test_leaving_between_rounds_can_decide_the_game() -> void:
	var logic := _game([1, 2, 3] as Array[int])
	_open(logic, [10, 9, 5])
	for p: int in [1, 2, 3]:
		_stand(logic, p)  # 3 out
	assert_false(logic.final)
	logic.remove_player(2)
	events.append_array(logic.drain_events())
	assert_true(logic.final, "only 1 is left in")
	assert_eq(_of(&"bust_or_bank_finished").size(), 1)
	assert_eq(logic.winners(), [1] as Array[int])
	assert_eq(logic.points(), {1: 1, 3: 0} as Dictionary[int, int])
	_tick(logic, BustOrBankLogic.RESULT_TIME + 0.01)
	assert_true(logic.is_finished())
	assert_eq(_of(&"bust_or_bank_round_started").size(), 1)


# --- Snapshots ---------------------------------------------------------------------------------

func test_public_and_private_state() -> void:
	var logic := _game([1, 2] as Array[int])
	_open(logic, [5, 6, 7])
	_tick(logic, 4.0)
	var st: Dictionary = logic.get_public_state()
	assert_eq(int(st["state"]), BustOrBankLogic.State.TURN)
	assert_eq(int(st["current"]), 1)
	assert_eq(int(st["round"]), 1)
	assert_almost_eq(float(st["timer"]), BustOrBankLogic.TURN_TIME - 4.0, 0.01)
	assert_almost_eq(float(st["turn_time"]), BustOrBankLogic.TURN_TIME, 0.001)
	assert_eq(st["players"], [1, 2])
	assert_eq(st["survivors"], [1, 2])
	assert_eq(st["out"], {})
	assert_eq((st["hands"] as Dictionary)[2]["cards"], [Card.make(6)], "every hand is public")
	assert_false(st.has("next_card"), "the next card is nobody's business")
	assert_false(st.has("ranking"))
	assert_true(bool(logic.private_state(1)["my_turn"]))
	assert_false(bool(logic.private_state(2)["my_turn"]))
	_stand(logic, 1)
	_stand(logic, 2)
	st = logic.get_public_state()
	assert_true(bool(st["final"]), "2 players: one round decides it")
	assert_true(st.has("ranking"))
	assert_eq(st["winners"], [2])
	assert_eq(st["last_out"], [1])
	assert_eq(StringName(st["why"]), &"lowest")
	assert_eq(st["points"], {2: 1, 1: 0})


func test_a_full_idle_game_ends_by_timeouts() -> void:
	var logic := _game([1, 2, 3, 4] as Array[int])
	var guard: int = 0
	while not logic.is_finished() and guard < 4000:
		guard += 1
		_tick(logic, 0.5)
	assert_true(logic.is_finished())
	var rounds: int = _of(&"bust_or_bank_round_started").size()
	assert_between(rounds, 1, 3)
	assert_eq(_of(&"bust_or_bank_round_end").size(), rounds)
	assert_true(bool(_round_end()["final"]))
	assert_eq(logic.ranking().size(), 4)


func test_an_idle_table_of_eight_stops_at_the_round_cap() -> void:
	# Patrick: an idle table of 8 ran 170 s. After `ROUND_CAP` seconds of turns everyone still
	# undecided stands and the round ends.
	var logic := _game([1, 2, 3, 4, 5, 6, 7, 8] as Array[int])
	_open(logic, [2, 3, 4, 5, 6, 7, 8, 9] as Array[int])
	assert_gt(8 * BustOrBankLogic.TURN_TIME, BustOrBankLogic.ROUND_CAP, "the cap matters for a full table")
	var waited: float = 0.0
	while logic.state == BustOrBankLogic.State.TURN and waited < 200.0:
		_tick(logic, 0.5)
		waited += 0.5
	assert_eq(logic.state, BustOrBankLogic.State.RESULT, "the round ended")
	assert_almost_eq(waited, BustOrBankLogic.ROUND_CAP, 0.51, "after the cap, not after 8 full turns")
	var capped: Array[Dictionary] = _of(&"bust_or_bank_player_stood").filter(func(e: Dictionary) -> bool: return e["reason"] == &"round_cap")
	assert_eq(capped.size(), 8 - int(BustOrBankLogic.ROUND_CAP / BustOrBankLogic.TURN_TIME), "everyone who never got to decide stands")
	assert_eq(_round_end()["out"], [1], "the lowest hand (2) is out")
	assert_false(bool(_round_end()["final"]))
	_next_round(logic)
	assert_eq(logic.round_time, 0.0, "every round gets its own cap")
	assert_eq(int(_of(&"bust_or_bank_round_started").back()["round"]), 2)


func test_the_cap_spares_a_quick_table() -> void:
	var logic := _game([1, 2] as Array[int])
	_open(logic, [10, 9, 2, 3] as Array[int])
	_stand(logic, 1)
	_tick(logic, 15.0)
	_hit(logic, 2)
	assert_true(logic.round_time < BustOrBankLogic.ROUND_CAP)
	assert_eq(_of(&"bust_or_bank_player_stood").filter(func(e: Dictionary) -> bool: return e["reason"] == &"round_cap").size(), 0, "a normal round never hits the cap")
