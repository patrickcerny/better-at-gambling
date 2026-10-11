extends GutTest
## Find the Lady stage fed by the real logic's events and private state, built the way the match
## scene builds it: after `find_the_lady_started` already went out behind the curtain. It opens
## on Lucky's card table, deals and shows the Queen, animates the shuffle from the server's swap
## sequence, sends a pick as an intent, and the reveal puts every picker's chip on their card.

var logic: FindTheLadyLogic
var stage: FindTheLadyStage
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
	logic = FindTheLadyLogic.new()
	logic.setup(ids, SeededRng.new(5), BalanceConfig.new(), {}, {})
	logic.drain_events()  # sent before the stage existed
	stage = FindTheLadyStage.new()
	stage.send_intent = func(i: Dictionary) -> Dictionary:
		sent.append(i)
		return logic.submit(1, i, 50.0)
	add_child_autofree(stage)
	stage.begin(st, 1, {"minigame": &"find_the_lady", "players": ids}, {})
	_pump()


func _pump() -> void:
	for ev: Dictionary in logic.drain_events():
		stage.on_event(ev)
	stage.on_private({"minigame": logic.private_state(1)})


func _to_shuffle() -> void:
	if logic.phase == FindTheLadyLogic.Step.INTRO:
		logic.tick(FindTheLadyLogic.INTRO_TIME + 0.01, 0.0)
	if logic.phase == FindTheLadyLogic.Step.REVEAL:
		logic.tick(FindTheLadyLogic.REVEAL_TIME + 0.01, 0.0)
	_pump()
	logic.tick(FindTheLadyLogic.SHOW_TIME + 0.01, 0.0)
	_pump()


func _to_pick() -> void:
	_to_shuffle()
	logic.tick(logic.timer + 0.01, 49.0)
	_pump()


func _key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	stage._unhandled_input(ev)


func _lady_node() -> TableCard3D:
	for c: TableCard3D in stage.cards:
		if c.card == FindTheLadyStage.lady_card():
			return c
	return null


func test_opens_on_the_card_table() -> void:
	assert_not_null(stage.table)
	assert_true(stage.camera.current)
	assert_eq(stage.table.seats.size(), 4, "every player's bean has a chair")
	assert_not_null(stage.host, "Lucky deals")
	assert_eq(stage.cards.size(), 3)
	assert_eq(stage.phase, "intro")
	assert_eq(stage.prompt_label.text, "FIND THE LADY")


func test_round_deals_the_queen_face_up() -> void:
	logic.tick(FindTheLadyLogic.INTRO_TIME + 0.01, 0.0)
	_pump()
	assert_eq(stage.phase, "show")
	stage._kill_deal()
	stage._deal_round(logic.card_count, logic.lady_start, false)
	var lady: TableCard3D = _lady_node()
	assert_not_null(lady)
	assert_eq(stage.cards.find(lady), logic.lady_start)
	assert_true(lady.is_face_up())
	assert_almost_eq(lady.position.x, stage.slot_point(logic.lady_start).x, 0.001)


func test_shuffle_animates_the_server_sequence() -> void:
	_to_shuffle()
	assert_eq(stage.phase, "shuffle")
	assert_eq(stage.swaps, logic.swaps)
	# Mid-way through the first swap the two cards are between their slots, bowed apart.
	var a: int = int(logic.swaps[0][0])
	var b: int = int(logic.swaps[0][1])
	stage.shuffle_pose(stage.flip_time + stage.swap_time * 0.5)
	var ca: TableCard3D = stage.cards[a]
	var cb: TableCard3D = stage.cards[b]
	var mid_x: float = (stage.slot_point(a).x + stage.slot_point(b).x) * 0.5
	assert_almost_eq(ca.position.x, mid_x, 0.01)
	assert_almost_eq(cb.position.x, mid_x, 0.01)
	assert_gt(absf(ca.position.z - cb.position.z), 0.3, "one passes in front of the other")
	assert_false(ca.is_face_up(), "face down once the shuffle runs")
	# At the end, every card sits where the sequence put it: the Queen where the server says.
	stage.shuffle_pose(stage.shuffle_length() + 0.1)
	assert_eq(stage.slot_of[logic.lady_start], logic.lady_slot)
	assert_eq(stage.card_in_slot(logic.lady_slot), stage.lady_id)
	var lady: TableCard3D = stage.cards[stage.lady_id]
	assert_almost_eq(lady.position.x, stage.slot_point(logic.lady_slot).x, 0.001)
	# Driven by the clock too.
	stage.shuffle_t = 0.0
	stage._process(stage.shuffle_length() + 0.5)
	assert_almost_eq(lady.position.x, stage.slot_point(logic.lady_slot).x, 0.001)


func test_pick_sends_the_intent() -> void:
	_to_shuffle()
	_key(KEY_1)
	assert_eq(sent.size(), 0, "no picking during the shuffle")
	logic.tick(logic.timer + 0.01, 49.0)
	_pump()
	assert_eq(stage.phase, "pick")
	assert_true(stage.can_act())
	assert_eq(stage.prompt_label.text, "FIND THE LADY!")
	_key(KEY_2)
	assert_eq(sent.size(), 1)
	assert_eq(sent[0]["type"], &"find_the_lady_pick")
	assert_eq(int(sent[0]["slot"]), 1)
	assert_eq(int(sent[0]["round"]), 0)
	assert_eq(logic.picks.get(1, -1), 1, "the server took it")
	_pump()
	assert_eq(stage.my_pick, 1)
	assert_false(stage.can_act())
	_key(KEY_3)
	assert_eq(sent.size(), 1, "one pick per round")
	assert_eq(stage.prompt_label.text, "LOCKED IN!")
	assert_true(stage.picked_players.has(1))


func test_click_picks_the_card_under_the_mouse() -> void:
	_to_pick()
	var r: Rect2 = stage.slot_rect(2)
	assert_true(r.size.x > 0.0)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = r.get_center()
	stage._unhandled_input(click)
	assert_eq(sent.size(), 1)
	assert_eq(int(sent[0]["slot"]), 2)


func test_reveal_shows_who_picked_which_card() -> void:
	_to_pick()
	var lady: int = logic.lady_slot
	var wrong: int = (lady + 1) % 3
	stage.pick(lady)
	logic.submit(2, {"slot": lady}, 51.0)
	logic.submit(3, {"slot": wrong}, 51.0)
	logic.submit(4, {"slot": wrong}, 52.0)
	_pump()
	assert_eq(stage.chips.size(), 0, "picks stay hidden until the reveal")
	logic.tick(0.01, 52.0)
	_pump()
	assert_eq(stage.phase, "reveal")
	assert_eq(stage.chips_on(lady), [1, 2])
	assert_eq(stage.chips_on(wrong), [3, 4])
	assert_true(stage.cards[stage.card_in_slot(lady)].card == FindTheLadyStage.lady_card(), "the Queen turns up where the server says")
	assert_string_starts_with(stage.prompt_label.text, "YOU FOUND HER!")
	assert_gt(stage.totals[1], 500)
	assert_eq(stage.totals[3], 0)
	var mark: Label = stage.board_rows[3]["mark"]
	assert_eq(mark.text, "-")


func test_fourth_card_and_the_end() -> void:
	for r: int in FindTheLadyLogic.ROUNDS:
		_to_pick()
		logic.submit(2, {"slot": logic.lady_slot}, 50.0)
		logic.tick(FindTheLadyLogic.pick_time(r) + 0.01, 60.0)
		_pump()
		assert_eq(stage.cards.size(), 4 if r >= FindTheLadyLogic.FOURTH_CARD_ROUND else 3)
	logic.tick(FindTheLadyLogic.REVEAL_TIME + 0.01, 90.0)
	_pump()
	assert_true(stage.over)
	assert_eq(stage.phase, "over")
	assert_eq(stage.prompt_label.text, "BO WINS!")


func test_late_join_mid_shuffle() -> void:
	_to_shuffle()
	logic.tick(FindTheLadyLogic.FLIP_TIME + FindTheLadyLogic.swap_time(0) * 1.5, 1.0)
	var snap: Dictionary = logic.get_public_state()
	var late := FindTheLadyStage.new()
	late.send_intent = func(_i: Dictionary) -> Dictionary: return {"ok": true}
	add_child_autofree(late)
	late.begin(st, 2, {"minigame": &"find_the_lady", "players": [1, 2, 3, 4]}, snap)
	assert_eq(late.phase, "shuffle")
	assert_almost_eq(late.shuffle_t, FindTheLadyLogic.FLIP_TIME + FindTheLadyLogic.swap_time(0) * 1.5, 0.05)
	late.shuffle_pose(late.shuffle_length() + 0.1)
	assert_eq(late.card_in_slot(logic.lady_slot), logic.lady_start, "the late joiner ends on the same Queen")
