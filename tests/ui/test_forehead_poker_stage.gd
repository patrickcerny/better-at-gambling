extends GutTest
## Forehead Poker stage fed by the real logic's events and private state, built the way the match
## scene builds it: after `forehead_poker_started` already went out behind the curtain. It opens
## in the dark card room from our own chair, shows the others' forehead cards but never ours,
## turns the head with the mouse (clamped to the table), sends STAY / FOLD on 1 / 2, and the
## showdown flies every card (ours too) to the felt with the points.

var logic: ForeheadPokerLogic
var stage: ForeheadPokerStage
var st: ClientMatchState
var sent: Array[Dictionary] = []
const NAMES: Array[String] = ["Me", "Bo", "Cy", "Di"]


func before_each() -> void:
	_make(4)


func _make(n: int) -> void:
	sent.clear()
	if stage != null and is_instance_valid(stage):
		stage.free()
	st = ClientMatchState.new()
	var ids: Array[int] = []
	for i: int in n:
		st.players[i + 1] = {"id": i + 1, "name": NAMES[i], "color": i}
		ids.append(i + 1)
	logic = ForeheadPokerLogic.new()
	logic.setup(ids, SeededRng.new(5), BalanceConfig.new(), {}, {})
	logic.drain_events()  # sent before the stage existed
	stage = ForeheadPokerStage.new()
	stage.send_intent = func(i: Dictionary) -> Dictionary:
		sent.append(i)
		return logic.submit(1, i, 50.0)
	add_child_autofree(stage)
	stage.begin(st, 1, {"minigame": &"forehead_poker", "players": ids}, {})
	_pump()


func _pump() -> void:
	for ev: Dictionary in logic.drain_events():
		stage.on_event(ev)
	stage.on_private({"minigame": logic.private_state(1)})


func _to(step: ForeheadPokerLogic.Step) -> void:
	while logic.phase != step:
		logic.tick(maxf(logic.timer, 0.0) + 0.01, 0.0)
		_pump()


func _key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	stage._unhandled_input(ev)


func test_opens_in_the_dark_card_room_from_our_chair() -> void:
	assert_not_null(stage.table)
	assert_true(stage.table.dark, "only the lamp is lit")
	assert_true(stage.camera.current)
	assert_eq(stage.table.seats.size(), 4)
	assert_not_null(stage.host, "Lucky deals")
	assert_true(stage.first_person)
	assert_false((stage.table.seats[1]["bean"] as Node3D).visible, "we look out of our own bean")
	assert_eq(stage.phase, "intro")
	assert_eq(stage.prompt_label.text, "FOREHEAD POKER")
	# We get the front chair, facing Lucky across the felt.
	var mine: Vector3 = (stage.table.seats[1]["root"] as Node3D).position
	for p: int in [2, 3, 4]:
		assert_gt(mine.z, (stage.table.seats[p]["root"] as Node3D).position.z - 0.001)


func test_others_cards_visible_and_our_own_hidden() -> void:
	_to(ForeheadPokerLogic.Step.TALK)
	assert_eq(stage.phase, "talk")
	assert_eq(stage.prompt_label.text, "TALK IT OVER")
	assert_eq(stage.timer_box.modulate.a, 1.0, "the talk timer runs")
	for p: int in [2, 3, 4]:
		var c: TableCard3D = stage.cards[p]
		assert_true(c.visible)
		assert_eq(c.card, logic.cards[p], "player %d's card shows on their forehead" % p)
		assert_true(c.is_face_up())
	assert_false(stage.known.has(1), "our own card never reaches us")
	assert_eq(stage.cards[1].card, TableCard3D.FACE_DOWN, "ours is a plain back")
	assert_false(stage.cards[1].visible, "and out of our first-person view")
	assert_true(stage.own_panel.visible)
	assert_eq(stage.own_mark.text, "?")
	assert_eq(stage.own_caption.text, "Don't peek!")


func test_our_card_is_ignored_even_if_it_arrived() -> void:
	_to(ForeheadPokerLogic.Step.TALK)
	var leaky: Dictionary = logic.private_state(1)
	(leaky["cards"] as Dictionary)[1] = logic.cards[1]
	stage.on_private({"minigame": leaky})
	assert_false(stage.known.has(1))
	assert_eq(stage.cards[1].card, TableCard3D.FACE_DOWN)


func test_mouse_look_turns_the_head_within_the_table() -> void:
	var before: Basis = stage.camera.basis
	stage.look(0.3, 0.0)
	assert_almost_eq(stage.yaw, -0.3, 0.001)
	assert_false(stage.camera.basis.is_equal_approx(before), "the camera turned")
	stage.look(-50.0, 0.0)
	assert_almost_eq(stage.yaw, stage.yaw_limit, 0.001, "clamped to the table")
	assert_lt(stage.yaw_limit, PI * 0.6)
	for p: int in [2, 3, 4]:
		assert_lt(absf(stage.yaw_towards(p)), stage.yaw_limit, "player %d can be looked at" % p)
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(40, 0)
	var y: float = stage.yaw
	stage._unhandled_input(motion)
	assert_lt(stage.yaw, y, "moving the mouse right turns right")


func test_keys_send_the_intent() -> void:
	_to(ForeheadPokerLogic.Step.TALK)
	_key(KEY_1)
	assert_eq(sent.size(), 0, "nothing to answer while talking")
	_to(ForeheadPokerLogic.Step.DECIDE)
	assert_eq(stage.prompt_label.text, "STAY OR FOLD?")
	assert_true(stage.action_box.visible)
	assert_true(stage.can_act())
	_key(KEY_2)
	assert_eq(sent.size(), 1)
	assert_eq(sent[0]["type"], &"forehead_poker_action")
	assert_eq(sent[0]["action"], "fold")
	assert_eq(stage.my_choice, "fold")
	assert_eq(logic.choices[1], "fold")
	_key(KEY_1)
	assert_eq(sent.size(), 1, "once per round")
	_pump()
	assert_eq(stage.prompt_label.text, "YOU FOLD")


func test_ticks_show_who_decided_but_not_what() -> void:
	_to(ForeheadPokerLogic.Step.DECIDE)
	logic.submit(3, {"action": "stay"}, 0.0)
	_pump()
	assert_true(stage.decided.has(3))
	assert_true((stage.board_rows[3]["tick"] as Control).visible)
	assert_false((stage.board_rows[2]["tick"] as Control).visible)
	assert_eq((stage.board_rows[3]["mark"] as Label).text, "", "no choice shown")


func test_showdown_reveal() -> void:
	_to(ForeheadPokerLogic.Step.DECIDE)
	logic.cards[1] = Card.make(1, 0)
	logic.cards[2] = Card.make(5, 1)
	logic.cards[3] = Card.make(9, 2)
	logic.cards[4] = Card.make(12, 3)
	_key(KEY_1)
	logic.submit(2, {"action": "stay"}, 0.0)
	logic.submit(3, {"action": "fold"}, 0.0)
	_to(ForeheadPokerLogic.Step.SHOWDOWN)
	assert_eq(stage.phase, "showdown")
	assert_eq(stage.cards[1].card, Card.make(1, 0), "our own card is revealed at last")
	assert_eq(stage.own_mark.text, "")
	stage.showdown_pose(stage.showdown_length())
	for p: int in [1, 2, 3, 4]:
		var c: TableCard3D = stage.cards[p]
		assert_true(c.visible)
		assert_lt(Vector2(c.position.x, c.position.z).length(), CardTableSet.FELT_RADII.x, "player %d's card is on the felt" % p)
		assert_lt(c.position.y, CardTableSet.TABLE_TOP + 0.4)
	assert_eq(stage.gains, {1: 2, 2: -1, 3: 0, 4: 0} as Dictionary[int, int])
	assert_eq(stage.prompt_label.text, "YOU TAKE THE POT!  +2")
	assert_eq(stage.result_chips.size(), 4)
	assert_eq(stage.pops.size(), 4, "+N / -1 / 0 over every bean")
	assert_eq((stage.board_rows[3]["mark"] as Label).text, "fold")
	assert_eq((stage.board_rows[2]["mark"] as Label).text, "-1")


func test_two_players_and_the_end() -> void:
	_make(2)
	_to(ForeheadPokerLogic.Step.TALK)
	assert_eq(stage.cards[2].card, logic.cards[2])
	_to(ForeheadPokerLogic.Step.OUTRO)
	assert_eq(stage.phase, "over")
	assert_true(stage.over)
	assert_false(stage.ranking.is_empty())


func test_late_join_mid_talk() -> void:
	_to(ForeheadPokerLogic.Step.TALK)
	var snap: Dictionary = logic.get_public_state()
	var late := ForeheadPokerStage.new()
	add_child_autofree(late)
	late.begin(st, 2, {"minigame": &"forehead_poker", "players": [1, 2, 3, 4]}, snap)
	late.on_private({"minigame": logic.private_state(2)})
	assert_eq(late.phase, "talk")
	assert_true(late.cards[1].visible)
	assert_eq(late.cards[1].card, logic.cards[1])
	assert_eq(late.cards[2].card, TableCard3D.FACE_DOWN, "the late joiner's own card stays hidden too")
