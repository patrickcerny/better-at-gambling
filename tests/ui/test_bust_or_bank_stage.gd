extends GutTest
## Bust or Bank stage fed by the real logic's events and snapshots (the schema contract): the table
## with everyone's seat, the current player highlighted with a countdown, HIT / STAND only on your
## own turn, and the result view with the winner(s).

var logic: BustOrBankLogic
var stage: BustOrBankStage
## Intents the stage sent (instead of the network).
var sent: Array[Dictionary] = []


func before_each() -> void:
	sent.clear()
	var st := ClientMatchState.new()
	st.players = {1: {"id": 1, "name": "Me", "color": 0}, 2: {"id": 2, "name": "Bo", "color": 1}, 3: {"id": 3, "name": "Cy", "color": 2}}
	logic = BustOrBankLogic.new()
	logic.setup([1, 2, 3] as Array[int], SeededRng.new(3), BalanceConfig.new(), {}, {})
	stage = BustOrBankStage.new()
	stage.send_intent = func(i: Dictionary) -> Dictionary:
		sent.append(i)
		return logic.submit(1, i, 0.0)
	add_child_autofree(stage)
	stage.begin(st, 1, {"minigame": &"bust_or_bank", "players": [1, 2, 3]}, {})
	_pump()


## Forwards everything the logic emitted to the stage, like the match scene does.
func _pump() -> void:
	for ev: Dictionary in logic.drain_events():
		stage.on_event(ev)


func _cards(ranks: Array[int]) -> Array[int]:
	var cards: Array[int] = []
	for r: int in ranks:
		cards.append(Card.make(r))
	return cards


## Stacks the shoe and plays the intro: one card each, then player 1's turn.
func _open(ranks: Array[int]) -> void:
	logic.shoe.stack_top(_cards(ranks))
	logic.tick(BustOrBankLogic.INTRO_TIME, 0.0)
	_pump()


func _act(p: int, action: String) -> void:
	assert_true(logic.submit(p, {"action": action}, 0.0)["ok"], "%d %s" % [p, action])
	_pump()


func _seat_status(p: int) -> String:
	return str((stage.seats[p]["panel"] as Control).get_meta("status", ""))


## The cards a row of `CardFace`s shows, in order.
func _faces(row: HBoxContainer) -> Array[int]:
	var out: Array[int] = []
	for f: Node in row.get_children():
		if not f.is_queued_for_deletion():
			out.append((f as CardFace).card)
	return out


func _key(action: StringName) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	stage._unhandled_input(ev)


func test_a_seat_for_everyone_round_the_table() -> void:
	assert_eq(stage.seats.size(), 3)
	assert_not_null(stage.table)
	assert_eq(stage._seat_order(), [1, 2, 3] as Array[int], "you sit at the bottom, then the circle")
	for p: int in [1, 2, 3]:
		assert_eq(_seat_status(p), "WAITING")
	assert_string_contains((stage.seats[1]["name"] as Label).text, "Me")
	assert_string_contains((stage.seats[2]["name"] as Label).text, "Bo")
	assert_true(stage.hit_button.disabled, "no buttons during the intro")
	assert_almost_eq(stage.time_left, BustOrBankLogic.INTRO_TIME, 0.001, "intro countdown from round_started")


func test_opening_deal_one_card_each() -> void:
	_open([10, 5, 7, 3])
	assert_eq(_faces(stage.seats[1]["cards"]), _cards([10]))
	assert_eq(_faces(stage.seats[2]["cards"]), _cards([5]))
	assert_eq(_faces(stage.seats[3]["cards"]), _cards([7]))
	assert_eq((stage.seats[2]["total"] as Label).text, "5")
	assert_eq(stage.next_face.card, Card.make(3), "the next card is shown face up")
	assert_true(stage.next_face.is_face_up())


func test_own_turn_highlight_countdown_and_buttons() -> void:
	_open([10, 5, 7, 3])
	assert_eq(stage.current, 1)
	assert_true(stage.can_act())
	assert_false(stage.hit_button.disabled)
	assert_false(stage.stand_button.disabled)
	assert_eq(stage.turn_label.text, "YOUR TURN")
	assert_eq(_seat_status(1), "YOUR TURN")
	assert_true((stage.seats[1]["bar"] as ProgressBar).visible, "the current seat has a countdown bar")
	assert_false((stage.seats[2]["bar"] as ProgressBar).visible)
	assert_eq((stage.seats[1]["style"] as StyleBoxFlat).border_color, Palette.VIP_GOLD, "highlighted")
	assert_almost_eq(stage.time_left, BustOrBankLogic.TURN_TIME, 0.001)
	assert_eq(stage.countdown_label.text, "20")
	stage._process(5.5)
	assert_eq(stage.countdown_label.text, "15")
	assert_almost_eq(stage.countdown_bar.value, 14.5 / 20.0, 0.001)
	assert_string_contains(stage.prompt_label.text, "3♠", "asks about the next card")


func test_hit_button_sends_hit_and_passes_the_turn() -> void:
	_open([10, 5, 7, 3])
	stage.hit_button.pressed.emit()
	assert_eq(sent.size(), 1)
	assert_eq(sent[0]["type"], &"bust_or_bank_action")
	assert_eq(sent[0]["action"], "hit")
	_pump()
	assert_eq(_faces(stage.seats[1]["cards"]), _cards([10, 3]))
	assert_eq((stage.seats[1]["total"] as Label).text, "13")
	assert_eq(stage.current, 2)
	assert_true(stage.hit_button.disabled, "not your turn any more")
	assert_eq(_seat_status(1), "WAITING")


func test_keys_hit_and_stand() -> void:
	_open([10, 5, 7, 3])
	_key(&"bj_stand")
	assert_eq(sent.size(), 1)
	assert_eq(sent[0]["action"], "stand")
	_pump()
	assert_eq(_seat_status(1), "STOOD")
	_key(&"bj_hit")
	assert_eq(sent.size(), 1, "keys do nothing when it is not your turn")


func test_other_players_turn_disables_buttons() -> void:
	_open([10, 5, 7, 3])
	_act(1, "stand")
	assert_eq(stage.current, 2)
	assert_false(stage.can_act())
	assert_true(stage.hit_button.disabled)
	assert_true(stage.stand_button.disabled)
	assert_eq(stage.turn_label.text, "BO'S TURN")
	assert_eq(_seat_status(2), "TURN")
	assert_true((stage.seats[2]["bar"] as ProgressBar).visible)
	assert_true(stage.countdown_label.visible, "the countdown is always shown")
	assert_eq((stage.seats[2]["style"] as StyleBoxFlat).border_color, Palette.VIP_GOLD)
	stage.hit_button.pressed.emit()
	assert_eq(sent.size(), 0)


func test_bust_shows_on_the_seat() -> void:
	_open([10, 5, 7, 10, 10])
	_act(1, "hit")  # 20
	_act(2, "hit")  # 15
	_act(3, "stand")
	logic.shoe.stack_top(_cards([5]))
	_act(1, "hit")  # 25
	assert_true(stage.hands[1]["busted"])
	assert_eq(_seat_status(1), "BUST")
	assert_string_contains(stage.banner.text, "BUST")
	assert_string_contains(stage.prompt_label.text, "Bust")


func test_timeout_stand_is_announced() -> void:
	_open([10, 5, 7])
	logic.tick(BustOrBankLogic.TURN_TIME, 0.0)
	_pump()
	assert_eq(_seat_status(1), "STOOD")
	assert_string_contains(stage.banner.text, "Time's up")
	assert_eq(stage.current, 2)


func test_result_shows_every_hand_and_the_winner() -> void:
	_open([10, 5, 7, 9, 5])
	_act(1, "hit")  # 19
	_act(2, "hit")  # 10
	_act(3, "stand")  # 7
	_act(1, "stand")
	_act(2, "stand")
	assert_true(stage.over)
	assert_eq(stage.winners, [1] as Array[int])
	assert_eq(_seat_status(1), "WINNER")
	assert_eq(_seat_status(2), "STOOD")
	assert_eq((stage.seats[1]["style"] as StyleBoxFlat).border_color, Palette.VIP_GOLD)
	assert_string_contains(stage.turn_label.text, "You win with 19")
	assert_true(stage.result_grid.visible)
	assert_eq(stage.result_grid.get_child_count(), 3, "every hand is listed")
	assert_false(stage.countdown_label.visible)
	assert_true(stage.hit_button.disabled)
	assert_string_contains(stage.prompt_label.text, "#1")
	assert_eq(_faces(stage.seats[2]["cards"]), _cards([5, 5]))


func test_tied_winners_share() -> void:
	_open([10, 10, 5])
	_act(1, "stand")
	_act(2, "stand")
	_act(3, "stand")
	assert_eq(stage.winners, [1, 2] as Array[int])
	assert_eq(_seat_status(2), "WINNER")
	assert_string_contains(stage.turn_label.text, "share the win")


func test_snapshot_catches_up_mid_turn() -> void:
	_open([10, 5, 7, 3])
	_act(1, "hit")
	logic.tick(4.0, 0.0)
	var late: BustOrBankStage = BustOrBankStage.new()
	late.send_intent = func(_i: Dictionary) -> Dictionary: return {"ok": true}
	add_child_autofree(late)
	var st := ClientMatchState.new()
	late.begin(st, 2, {"minigame": &"bust_or_bank", "players": [1, 2, 3]}, logic.get_public_state())
	assert_eq(late.current, 2)
	assert_true(late.can_act(), "it's the late joiner's turn")
	assert_almost_eq(late.time_left, BustOrBankLogic.TURN_TIME - 4.0, 0.01)
	assert_eq(_faces(late.seats[1]["cards"]), _cards([10, 3]))
	assert_eq(late.next_face.card, logic.next_card, "late joiners see the next card")
	assert_eq(late._seat_order(), [2, 3, 1] as Array[int], "their own seat at the bottom")


func test_eight_seats_do_not_overlap() -> void:
	var st := ClientMatchState.new()
	var ids: Array = []
	for i: int in 8:
		st.players[i + 1] = {"id": i + 1, "name": "Player %d" % (i + 1), "color": i}
		ids.append(i + 1)
	var big: BustOrBankStage = BustOrBankStage.new()
	add_child_autofree(big)
	big.begin(st, 1, {"minigame": &"bust_or_bank", "players": ids}, {})
	big.arena.size = Vector2(1856, 860)
	big._layout()
	var rects: Array[Rect2] = []
	for p: Variant in big.seats:
		var c: Control = big.seats[p]["panel"]
		rects.append(Rect2(c.position, c.size))
	for i: int in rects.size():
		for j: int in range(i + 1, rects.size()):
			assert_false(rects[i].intersects(rects[j]), "seats %d and %d overlap" % [i, j])


func test_a_player_leaving_mid_turn_loses_their_seat() -> void:
	_open([10, 5, 7, 3])
	_act(1, "hit")
	logic.remove_player(2)
	_pump()
	assert_eq(stage.players, [1, 3] as Array[int])
	assert_false((stage.seats[2]["panel"] as Control).visible)
	assert_eq(stage.current, 3)
	assert_eq(stage.turn_label.text, "CY'S TURN")
