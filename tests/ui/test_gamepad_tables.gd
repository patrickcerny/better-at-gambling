extends GutTest
## Every casino table on a gamepad. Tables you bet on by clicking a spot get a picker: the left
## stick (free while seated) moves a gold frame between the spots and A puts a chip on the framed
## one; Plinko's risk and Hold'em's AA bonus are picked the same way while A keeps dropping /
## dealing; the roulette layout gets a pointer the stick moves like a mouse, so splits and corners
## work too. The d-pad stays free for items. Intents are captured instead of sent.

var root: Control
var st: ClientMatchState


class CapCraps extends CrapsUi:
	var sent: Array[Dictionary] = []

	func send(type: StringName, payload: Dictionary = {}) -> bool:
		sent.append({"type": type, "payload": payload})
		return true


class CapHorse extends HorseRaceUi:
	var sent: Array[Dictionary] = []

	func send(type: StringName, payload: Dictionary = {}) -> bool:
		sent.append({"type": type, "payload": payload})
		return true


class CapWheel extends WheelUi:
	var sent: Array[Dictionary] = []

	func send(type: StringName, payload: Dictionary = {}) -> bool:
		sent.append({"type": type, "payload": payload})
		return true


class CapBaccarat extends BaccaratUi:
	var sent: Array[Dictionary] = []

	func send(type: StringName, payload: Dictionary = {}) -> bool:
		sent.append({"type": type, "payload": payload})
		return true


class CapRoulette extends RouletteUi:
	var sent: Array[Dictionary] = []

	func send(type: StringName, payload: Dictionary = {}) -> bool:
		sent.append({"type": type, "payload": payload})
		return true


class CapScratch extends ScratchUi:
	var sent: Array[Dictionary] = []

	func send(type: StringName, payload: Dictionary = {}) -> bool:
		sent.append({"type": type, "payload": payload})
		return true


class CapPlinko extends PlinkoUi:
	var sent: Array[Dictionary] = []

	func send(type: StringName, payload: Dictionary = {}) -> bool:
		sent.append({"type": type, "payload": payload})
		return true


func before_each() -> void:
	InputGlyphs.set_gamepad(true)
	root = Control.new()
	root.size = Vector2(1920, 1080)
	add_child_autofree(root)
	st = ClientMatchState.new()
	st.players[1] = {"name": "Ada", "color": 0}
	st.players[2] = {"name": "Bert", "color": 1}
	st.balances[1] = 1000


func after_each() -> void:
	InputGlyphs.set_gamepad(false)


func _open(ui: StationUi, sid: StringName, pub: Dictionary) -> void:
	root.add_child(ui)
	st.stations[sid] = pub
	ui.open(sid, 1, st)
	await wait_process_frames(3)


func _a() -> void:
	for down: bool in [true, false]:
		var ev := InputEventJoypadButton.new()
		ev.button_index = JOY_BUTTON_A
		ev.pressed = down
		get_tree().root.push_input(ev)


## One push of the left stick (and back to the middle).
func _stick(ui: StationUi, dir: Vector2) -> void:
	ui._pad_step(dir, 0.016)
	ui._pad_step(Vector2.ZERO, 0.016)


func test_craps_stick_picks_a_bet_and_a_puts_a_chip_on_it() -> void:
	var ui := CapCraps.new()
	await _open(ui, &"craps_1", {"game": &"craps", "state": CrapsLogic.State.BETTING, "timer": 0.0, "counting": false, "players": [1, 2], "shooter": 2, "point": 0, "bets": [], "dice": [], "shoot_in": 0.0})
	assert_true(ui.pad_active())
	assert_true(ui.pad_frame.visible, "a gold frame on the first bet")
	assert_eq(ui.selected_bet, CrapsLogic.BET_TYPES[0])
	_stick(ui, Vector2.DOWN)
	var below: StringName = ui.selected_bet
	assert_ne(below, CrapsLogic.BET_TYPES[0], "the stick moves the frame (2x2 grid: down)")
	assert_true(ui.pad_frame.get_global_rect().encloses(ui.bet_buttons[below].get_global_rect()), "the frame sits round the picked bet")
	_a()
	assert_eq(ui.sent.size(), 1, "A puts a chip down")
	assert_eq(StringName(ui.sent[0]["payload"]["bet"]["type"]), below)
	assert_string_contains(ui.hint.text, "Left stick")


func test_craps_without_a_pad_no_frame_and_a_is_ignored() -> void:
	InputGlyphs.set_gamepad(false)
	var ui := CapCraps.new()
	await _open(ui, &"craps_1", {"game": &"craps", "state": CrapsLogic.State.BETTING, "timer": 0.0, "counting": false, "players": [1, 2], "shooter": 2, "point": 0, "bets": [], "dice": [], "shoot_in": 0.0})
	assert_false(ui.pad_frame.visible)
	assert_eq(ui.selected_bet, &"", "the mouse picks nothing by itself")


func test_horse_race_stick_and_a() -> void:
	var ui := CapHorse.new()
	await _open(ui, &"horse_race_1", {"game": &"horse_race", "state": HorseRaceLogic.State.BETTING, "timer": 12.0, "counting": false, "players": [1], "bets": [], "names": ["A", "B", "C", "D"]})
	_stick(ui, Vector2.RIGHT)
	_stick(ui, Vector2.RIGHT)
	assert_eq(ui.selected_horse, 2)
	_a()
	assert_eq(ui.sent.size(), 1)
	assert_eq(int(ui.sent[0]["payload"]["bet"]["horse"]), 2)


func test_wheel_stick_and_a() -> void:
	var ui := CapWheel.new()
	await _open(ui, &"wheel_1", {"game": &"wheel", "state": WheelLogic.State.BETTING, "timer": 0.0, "counting": false, "players": [1], "bets": [], "segment": -1, "landing": false, "history": []})
	_stick(ui, Vector2.RIGHT)
	_stick(ui, Vector2.DOWN)
	var want: int = ui.selected_symbol
	assert_gt(want, 1, "right then down in the symbol grid")
	_a()
	assert_eq(int(ui.sent[0]["payload"]["bet"]["symbol"]), want)


func test_baccarat_every_bet_reachable_and_a_bets() -> void:
	var ui := CapBaccarat.new()
	await _open(ui, &"baccarat_1", {"game": &"baccarat", "state": BaccaratLogic.State.BETTING, "timer": 7.2, "players": [1, 2], "bets": [], "player_cards": [], "banker_cards": [], "winner": &"", "history": []})
	var reached: Dictionary = {}
	for i: int in 30:
		reached[ui.pad_index] = true
		_stick(ui, [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP][(i / 3) % 4])
	assert_eq(reached.size(), ui.pad_targets().size(), "the stick reaches all five bets (tie and the pairs too)")
	ui.pad_select(0)
	_a()
	assert_eq(ui.sent.size(), 1, "A bets on the framed spot")


func test_plinko_stick_picks_the_risk_and_a_still_drops() -> void:
	var ui := CapPlinko.new()
	await _open(ui, &"plinko_1", {"game": &"plinko", "players": [1], "drops": []})
	assert_eq(ui.risk, &"medium")
	assert_eq(ui.pad_index, ui._pad_current(), "the frame starts on the risk you have")
	_stick(ui, Vector2.RIGHT)
	assert_eq(ui.risk, &"high")
	_stick(ui, Vector2.LEFT)
	_stick(ui, Vector2.LEFT)
	assert_eq(ui.risk, &"low")
	_a()
	assert_eq(ui.sent.size(), 1, "A drops a chip")
	assert_eq(StringName(ui.sent[0]["payload"]["bet"]["risk"]), &"low")


func test_scratch_stick_picks_a_card_and_a_buys_it() -> void:
	var ui := CapScratch.new()
	await _open(ui, &"scratch_1", {"game": &"scratch", "player": 1, "card": [], "tier": -1, "stake": 0, "serial": -1, "last": {}})
	_stick(ui, Vector2.RIGHT)
	assert_eq(ui.preview_tier, 1, "the framed card is previewed")
	_a()
	assert_eq(ui.sent.size(), 1, "A buys the framed card (the first card too)")
	assert_eq(int(ui.sent[0]["payload"]["bet"]["tier"]), 1)


func test_roulette_pointer_reaches_a_split_and_a_bets_there() -> void:
	var ui := CapRoulette.new()
	await _open(ui, &"roulette_1", {"game": &"roulette", "state": RouletteLogic.State.BETTING, "timer": 10.0, "players": [1], "bets": [], "result": -1})
	ui._process(0.016)
	var b: RouletteBoard = ui.board
	assert_false(is_nan(b.pad_cursor.x), "a pointer shows on the layout")
	assert_eq(b.hover_type, &"straight")
	assert_eq(b.hover_value, 17, "it starts on 17")
	# Push right until the pointer sits on the line between 17 and 18: a split.
	var guard: int = 0
	while b.hover_type == &"straight" and guard < 200:
		b.pad_nudge(Vector2(0.25, 0.0), 0.016)
		guard += 1
	assert_eq(b.hover_type, &"split", "the pointer finds the line between two numbers")
	_a()
	assert_eq(ui.sent.size(), 1, "A puts a chip where it points")
	assert_eq(StringName(ui.sent[0]["payload"]["bet"]["type"]), &"split")
	assert_string_contains(ui.hint.text, "Left stick")


func test_roulette_mouse_hides_the_pointer() -> void:
	InputGlyphs.set_gamepad(false)
	var ui := CapRoulette.new()
	await _open(ui, &"roulette_1", {"game": &"roulette", "state": RouletteLogic.State.BETTING, "timer": 10.0, "players": [1], "bets": [], "result": -1})
	ui._process(0.016)
	assert_true(is_nan(ui.board.pad_cursor.x))


func test_the_dpad_is_never_taken_by_a_picker() -> void:
	var ui := CapCraps.new()
	await _open(ui, &"craps_1", {"game": &"craps", "state": CrapsLogic.State.BETTING, "timer": 0.0, "counting": false, "players": [1, 2], "shooter": 2, "point": 0, "bets": [], "dice": [], "shoot_in": 0.0})
	var before: int = ui.pad_index
	var ev := InputEventJoypadButton.new()
	ev.button_index = JOY_BUTTON_DPAD_RIGHT
	ev.pressed = true
	get_tree().root.push_input(ev)
	assert_eq(ui.pad_index, before, "the d-pad still uses items while seated")
	assert_null(get_viewport().gui_get_focus_owner(), "no GUI focus at a table (it would eat the d-pad's item)")
	for b: Node in ui.find_children("*", "BaseButton", true, false):
		assert_eq((b as BaseButton).focus_mode, Control.FOCUS_NONE, "%s takes no focus" % b.name)


func test_tables_name_their_pad_buttons() -> void:
	for ui: StationUi in [SlotsUi.new(), SwordTapperUi.new(), RouletteUi.new(), CrapsUi.new(), WheelUi.new(), HorseRaceUi.new(), BaccaratUi.new()]:
		root.add_child(ui)
		await wait_process_frames(1)
		var t: String = ui._hint_text()
		assert_false("[1-4]" in t or "[1–4]" in t, "%s: no number keys on a pad: %s" % [ui.game_title, t])
		assert_false("?" in t, "%s: every action has a pad button: %s" % [ui.game_title, t])
