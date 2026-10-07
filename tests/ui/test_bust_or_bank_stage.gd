extends GutTest
## Bust or Bank stage fed by the real logic's events and snapshots (the schema contract): points
## update from round results, busts show immediately, replays and the final ranking display.

var logic: BustOrBankLogic
var stage: BustOrBankStage


func before_each() -> void:
	var st := ClientMatchState.new()
	st.players = {1: {"id": 1, "name": "Me", "color": 0}, 2: {"id": 2, "name": "Bo", "color": 1}, 3: {"id": 3, "name": "Cy", "color": 2}}
	logic = BustOrBankLogic.new()
	logic.setup([1, 2, 3] as Array[int], SeededRng.new(3), BalanceConfig.new(), {}, {})
	stage = BustOrBankStage.new()
	add_child_autofree(stage)
	stage.begin(st, 1, {"minigame": &"bust_or_bank", "players": [1, 2, 3]}, {})
	_pump()


## Forwards everything the logic emitted to the stage, like the match scene does.
func _pump() -> void:
	for ev: Dictionary in logic.drain_events():
		stage.on_event(ev)


func _open(ranks: Array[int]) -> void:
	var cards: Array[int] = []
	for r: int in ranks:
		cards.append(Card.make(r))
	logic.shoe.stack_top(cards)
	logic.tick(BustOrBankLogic.INTRO_TIME, 0.0)
	_pump()


func _next_card() -> void:
	logic.tick(BustOrBankLogic.DEAL_INTERVAL, 0.0)
	_pump()


func _stand(p: int) -> void:
	assert_true(logic.submit(p, {"action": "stand"}, 0.0)["ok"])
	_pump()


func _row(p: int) -> Label:
	for row: Node in stage.board.get_children():
		if row.is_queued_for_deletion():
			continue
		if int(row.get_meta("player", -1)) == p:
			return stage.board_rows[p]["label"] as Label
	return null


## The cards a row of `CardFace`s shows, in order.
func _faces(row: HBoxContainer) -> Array[int]:
	var out: Array[int] = []
	for f: Node in row.get_children():
		if not f.is_queued_for_deletion():
			out.append((f as CardFace).card)
	return out


func test_cards_and_totals_follow_the_shared_shoe() -> void:
	_open([10, 5])
	assert_eq(stage.hands[1]["total"], 15)
	assert_eq(stage.hands[3]["total"], 15)
	assert_eq(stage.my_total_label.text, "15")
	assert_eq(stage.dealt_face.card, Card.make(5))
	assert_true(stage.dealt_face.is_face_up())
	assert_eq(_faces(stage.my_hand_row), [Card.make(10), Card.make(5)] as Array[int], "real card faces in your hand")
	assert_eq(_faces(stage.board_rows[2]["cards"]), [Card.make(10), Card.make(5)] as Array[int])
	assert_eq((stage.board_rows[2]["total"] as Label).text, "Total 15", "total under each hand")
	assert_false(stage.stand_button.disabled, "can stand while cards are coming")


func test_next_card_is_shown_face_up_and_then_dealt() -> void:
	_open([10, 2, 5, 3])
	assert_eq(stage.next_card, Card.make(5))
	assert_eq(stage.next_face.card, Card.make(5))
	assert_true(stage.next_face.is_face_up(), "everyone sees the next card")
	assert_eq(stage.next_face.text(), "5♠")
	_next_card()
	assert_eq(stage.dealt_face.card, Card.make(5), "the shown card is the one dealt")
	assert_eq(stage.next_face.card, Card.make(3), "and the one after it is revealed")
	assert_eq(_faces(stage.my_hand_row).back(), Card.make(5))


func test_deal_bar_follows_the_event_timings() -> void:
	assert_almost_eq(stage.deal_left, BustOrBankLogic.INTRO_TIME, 0.001, "intro countdown from round_started")
	assert_string_contains(stage.deal_time_label.text, "Dealing in")
	_open([10, 2, 5])
	assert_almost_eq(stage.deal_left, BustOrBankLogic.DEAL_INTERVAL, 0.001, "next_in from the card event")
	assert_almost_eq(stage.deal_span, BustOrBankLogic.DEAL_INTERVAL, 0.001)
	assert_string_contains(stage.deal_time_label.text, "Next card in 3.2")
	stage.on_event({"type": &"bust_or_bank_card", "card": Card.make(5), "next_card": Card.make(6), "receivers": [1, 2, 3], "totals": {1: 17, 2: 17, 3: 17}, "next_in": 7.5})
	assert_almost_eq(stage.deal_span, 7.5, 0.001, "uses the server's value, not a local constant")
	stage._process(2.5)
	assert_almost_eq(stage.deal_bar.value, 2.5 / 7.5, 0.001)


func test_points_update_from_round_end() -> void:
	_open([10, 2, 5, 3])
	_stand(2)  # 12: worst
	_next_card()
	_stand(1)  # 17
	_next_card()
	_stand(3)  # 20
	assert_eq(stage.points, {1: 1, 2: 0, 3: 1})
	assert_string_contains(stage.points_label.text, "1")
	assert_string_contains(_row(2).text, "OUT")
	assert_eq(stage.in_game, [1, 3] as Array[int])
	assert_string_contains(stage.banner.text, "Bo")


func test_points_are_set_not_accumulated() -> void:
	_open([10, 2, 5, 3])
	_stand(2)
	_next_card()
	_stand(1)
	_next_card()
	_stand(3)
	var ev: Dictionary = {"type": &"bust_or_bank_round_end", "points": {1: 1, 2: 0, 3: 1}, "remaining": [1, 3], "replay": false, "busted": [], "worst": [2]}
	stage.on_event(ev)  # same absolute values again (e.g. a resend) must not double
	assert_eq(int(stage.points[1]), 1)


func test_bust_shows_immediately_before_the_round_ends() -> void:
	_open([10, 2, 10])
	_stand(2)
	_stand(3)
	logic.shoe.stack_top([Card.make(10)] as Array[int])
	# Feed only the card + bust events, not the round end yet.
	logic.tick(BustOrBankLogic.DEAL_INTERVAL, 0.0)
	for ev: Dictionary in logic.drain_events():
		if ev["type"] == &"bust_or_bank_round_end":
			break
		stage.on_event(ev)
	assert_true(stage.hands[1]["busted"])
	assert_eq(stage.status_label.text, "BUST!")
	assert_string_contains(_row(1).text, "BUST")
	assert_true(stage.stand_button.disabled)


func test_everyone_busting_shows_a_replay_not_an_elimination() -> void:
	_open([10, 2, 10])
	_next_card()  # all 22
	assert_string_contains(stage.banner.text, "Replay")
	assert_eq(stage.in_game, [1, 2, 3] as Array[int])
	assert_string_contains(_row(2).text, "replay")
	logic.tick(BustOrBankLogic.RESULT_TIME, 0.0)
	_pump()
	assert_true(stage.replay)
	assert_eq(stage.hands[1]["total"], 0, "fresh count")
	assert_eq(_faces(stage.my_hand_row), [] as Array[int], "hands cleared for the new round")
	assert_eq(stage.next_face.card, logic.next_card, "the new round reveals its first card")
	assert_string_contains(stage.round_label.text, "replay")


func test_finish_names_the_winner() -> void:
	_open([10, 2, 5, 10])
	_stand(2)  # 12
	_next_card()
	_stand(1)  # 17
	_next_card()  # 3 busts → 1 wins, 2 second, 3 third
	assert_true(stage.over)
	assert_string_contains(stage.banner.text, "You are the last one standing")
	assert_eq(stage.points, {1: 2, 2: 1, 3: 0})


func test_snapshot_catches_up_mid_round() -> void:
	_open([10, 2, 5, 3])
	_stand(2)
	_next_card()
	var late: BustOrBankStage = BustOrBankStage.new()
	add_child_autofree(late)
	var st := ClientMatchState.new()
	late.begin(st, 3, {"minigame": &"bust_or_bank", "players": [1, 2, 3]}, logic.get_public_state())
	assert_eq(late.hands[3]["total"], 17)
	assert_true(late.hands[2]["stood"])
	assert_eq(late.next_face.card, Card.make(3), "late joiners see the next card")
	assert_eq(late.dealt_face.card, Card.make(5))
	assert_eq(_faces(late.my_hand_row), [Card.make(10), Card.make(2), Card.make(5)] as Array[int])
	assert_true(late.dealing)
	assert_false(late.stand_button.disabled)


func test_space_does_nothing_once_out() -> void:
	_open([10, 2, 10])
	_stand(2)
	_stand(3)
	_next_card()  # 1 busts and is out
	assert_false(stage.can_stand())
