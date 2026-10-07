extends GutTest
## Seated at a table (Patrick's playtest: "I can't select any buttons on the blackjack table",
## "I can't see the dealer's cards"): the cursor is free while seated and captured again after
## standing up, the head follows the cursor a little, real mouse clicks on the overlay reach its
## buttons, and the dealt cards lean towards the seat that reads them.

const SID: StringName = &"blackjack_2"

var scene: MatchScene
## GUT's own result window is drawn over the game in the test runner; hidden while we click.
var _hidden_layers: Array[CanvasLayer] = []


func after_each() -> void:
	for l: CanvasLayer in _hidden_layers:
		if is_instance_valid(l):
			l.visible = true
	_hidden_layers.clear()


func _hide_runner_gui() -> void:
	for n: Node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		var l: CanvasLayer = n
		if l.visible and not scene.is_ancestor_of(l):
			l.visible = false
			_hidden_layers.append(l)


func _start_scene() -> void:
	Net.stop()
	scene = (load("res://match/match_scene.tscn") as PackedScene).instantiate()
	add_child_autofree(scene)
	scene.server.timescale = 1.0
	await wait_seconds(3.3)
	assert_eq(scene.server.phases.phase, Phase.Id.CASINO, "casino phase after the intro")


func _sit(sid: StringName) -> void:
	var st: StationBase = scene.map.stations[sid]
	var seat: Vector3 = st.seat_position(0)
	var out: Vector3 = seat + (seat - st.global_position).normalized() * 0.8
	out.y = st.global_position.y
	scene.local.teleport(out, 0.0)
	scene.server.set_server_position(scene.local_id, out)
	await wait_physics_frames(2)
	var res: Dictionary = Net.send_intent(Intents.make(&"sit", {"station": sid}))
	assert_true(res["ok"], "sit: %s" % res)
	await wait_physics_frames(3)


## Moves the cursor onto a control and clicks it with the left button, the way a real mouse
## does (through the viewport, so anything drawn over the button would swallow the click).
## Returns the control the GUI thinks is under the cursor.
func _click(c: Control) -> Control:
	var pos: Vector2 = c.get_global_rect().get_center()
	_move_mouse(pos)
	var hovered: Control = get_viewport().gui_get_hovered_control()
	for pressed: bool in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		get_viewport().push_input(ev, true)
	return hovered


func _move_mouse(pos: Vector2) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = pos
	mm.global_position = pos
	mm.relative = Vector2(10, 0)
	get_viewport().push_input(mm, true)


## Visible STOP controls over `target` that are not the target or one of its parents.
func _blockers_at(target: Control) -> String:
	var pos: Vector2 = target.get_global_rect().get_center()
	var out: PackedStringArray = []
	for n: Node in get_tree().root.find_children("*", "Control", true, false):
		var c: Control = n
		if c == target or c.is_ancestor_of(target):
			continue
		if c.is_visible_in_tree() and c.mouse_filter == Control.MOUSE_FILTER_STOP and c.get_global_rect().has_point(pos):
			out.append(String(c.get_path()))
	return ", ".join(out)


func _hand() -> Dictionary:
	var hands: Dictionary = (scene.view.state.stations[SID] as Dictionary).get("hands", {})
	for k: Variant in hands:
		if int(k) == scene.local_id:
			return hands[k]
	return {}


func test_cursor_is_free_while_seated_and_captured_after_standing() -> void:
	await _start_scene()
	var router: InputRouter = scene.router
	assert_eq(router.mode, InputRouter.Mode.WALK)
	assert_eq(router.desired_mouse_mode(), Input.MOUSE_MODE_CAPTURED, "walking captures the mouse")
	await _sit(SID)
	assert_eq(scene.local.state, PlayerAvatar.State.SEATED)
	assert_eq(router.mode, InputRouter.Mode.SEATED)
	assert_eq(router.desired_mouse_mode(), Input.MOUSE_MODE_CONFINED, "seated at blackjack shows the cursor, kept inside the window")
	# Esc menu while seated, then back to the table with the cursor still free.
	scene._on_pause()
	assert_eq(router.mode, InputRouter.Mode.MENU)
	assert_eq(router.desired_mouse_mode(), Input.MOUSE_MODE_CONFINED)
	scene._on_pause()
	assert_eq(router.mode, InputRouter.Mode.SEATED, "closing the menu goes back to the seat")
	assert_eq(router.desired_mouse_mode(), Input.MOUSE_MODE_CONFINED)
	assert_true(Net.send_intent(Intents.make(&"leave"))["ok"])
	await wait_physics_frames(2)
	assert_eq(scene.local.state, PlayerAvatar.State.STANDING)
	assert_eq(router.mode, InputRouter.Mode.WALK)
	assert_eq(router.desired_mouse_mode(), Input.MOUSE_MODE_CAPTURED, "standing up captures the mouse again")
	# Every other kind of station seats you with a free cursor too.
	for sid: StringName in [&"roulette_1", &"slot_8", &"plinko_1"]:
		await _sit(sid)
		assert_eq(router.mode, InputRouter.Mode.SEATED, String(sid))
		assert_eq(router.desired_mouse_mode(), Input.MOUSE_MODE_CONFINED, "cursor free at %s" % sid)
		Net.send_intent(Intents.make(&"leave"))
		await wait_physics_frames(2)
		assert_eq(router.desired_mouse_mode(), Input.MOUSE_MODE_CAPTURED)


func test_minigame_keeps_the_cursor_when_you_are_stood_up() -> void:
	await _start_scene()
	await _sit(SID)
	var router: InputRouter = scene.router
	assert_eq(router.mode, InputRouter.Mode.SEATED)
	scene.shop_panel.open()
	# Jump the clock to just before the first minigame.
	var ph: PhaseMachine = scene.server.phases
	ph.casino_time = ph.schedule.minigame_times()[0] - 0.3
	await wait_seconds(1.0)
	assert_eq(ph.phase, Phase.Id.MINIGAME)
	assert_not_null(scene.stage, "minigame stage open")
	assert_eq(router.mode, InputRouter.Mode.STAGE)
	assert_eq(router.desired_mouse_mode(), Input.MOUSE_MODE_CONFINED, "visible cursor, inside the window")
	assert_null(scene.current_ui)
	for ui: StationUi in scene.station_uis.values():
		assert_false(ui.visible, "%s panel closed" % ui.name)
	assert_false(scene.shop_panel.visible, "shop closed")
	# The server stood everyone up as the minigame started (Patrick's note #21): the stage keeps
	# the cursor anyway.
	await wait_physics_frames(3)
	assert_false(scene.server.stations.is_seated(scene.local_id), "stood up for the minigame")
	assert_eq(scene.local.state, PlayerAvatar.State.STANDING)
	assert_eq(router.mode, InputRouter.Mode.STAGE, "standing up does not leave the stage mode")
	assert_eq(router.desired_mouse_mode(), Input.MOUSE_MODE_CONFINED)
	scene._on_pause()
	assert_eq(router.mode, InputRouter.Mode.STAGE, "Esc does not open the hidden settings over a minigame")
	scene._back_to_casino()
	assert_eq(router.mode, InputRouter.Mode.WALK)
	assert_eq(router.desired_mouse_mode(), Input.MOUSE_MODE_CAPTURED)


func test_dealer_total_counts_face_up_cards_only() -> void:
	Vfx.force_enabled = true
	var st := BlackjackStation.new()
	add_child_autofree(st)
	await wait_process_frames(1)
	var king: int = Card.make(13, 1)
	st.show_round({"state": BlackjackLogic.State.ACTING, "seats": [7, -1, -1, -1], "dealer_revealed": false,
		"dealer": [king], "hands": {7: {"cards": [Card.make(8, 0), Card.make(3, 2)]}}})
	assert_not_null(st.dealer_total_label)
	assert_true(st.dealer_total_label.visible)
	assert_eq(st.dealer_total_label.text, "10", "K showing, hole card ignored")
	assert_false(st.cards.is_ancestor_of(st.dealer_total_label), "not in the card piles")
	await wait_seconds(1.2)
	assert_eq(st.cards.pile_nodes(-1).size(), 2, "up card and hole card only")
	assert_gt(st.dealer_total_label.global_position.y, st.cards.pile_nodes(-1)[0].global_position.y, "above the dealer's cards")
	st.show_round({"state": BlackjackLogic.State.PAYOUT, "seats": [7, -1, -1, -1], "dealer_revealed": true,
		"dealer": [king, Card.make(1, 2)], "hands": {}})
	assert_eq(st.dealer_total_label.text, "21")
	st.show_round({"state": BlackjackLogic.State.IDLE, "seats": [-1, -1, -1, -1], "dealer": [], "hands": {}})
	assert_false(st.dealer_total_label.visible, "hidden without dealer cards")
	Vfx.force_enabled = false


func test_cards_stay_under_the_bloom() -> void:
	var st := BlackjackStation.new()
	add_child_autofree(st)
	await wait_process_frames(1)
	st.show_round({"state": BlackjackLogic.State.ACTING, "seats": [7, -1, -1, -1], "dealer_revealed": false,
		"dealer": [Card.make(13, 1)], "hands": {7: {"cards": [Card.make(8, 0), Card.make(3, 2)]}}})
	await wait_seconds(1.2)
	var threshold: float = 1.1  # LoungeDecor glow_hdr_threshold
	for n: Node3D in st.cards.pile_nodes(0):
		var m: StandardMaterial3D = (n.get_node(^"Face") as MeshInstance3D).material_override
		var c: Color = m.albedo_color
		assert_lte(maxf(c.r, maxf(c.g, c.b)), 0.851, "card face albedo toned down")
		assert_lt(maxf(c.r, maxf(c.g, c.b)), threshold)
	st.set_hot(true)
	assert_lte(st.hot_light.light_energy, 3.5, "hot spotlight over a card table is softer")
	var rs := RouletteStation.new()
	add_child_autofree(rs)
	await wait_process_frames(1)
	rs.set_hot(true)
	assert_eq(rs.hot_light.light_energy, 6.0, "other tables keep the full spotlight")


func test_head_follows_the_cursor_a_little() -> void:
	await _start_scene()
	await _sit(SID)
	var cam: PlayerCamera = scene.local.cam
	var size: Vector2 = get_viewport().get_visible_rect().size
	_move_mouse(size * 0.5)
	await wait_seconds(0.8)
	var centre_fwd: Vector3 = -cam.camera.global_basis.z
	assert_almost_eq(scene.router.seated_look().length(), 0.0, 0.001, "no turn with the cursor in the middle")
	_move_mouse(Vector2(size.x - 1.0, size.y * 0.5))
	assert_gt(scene.router.seated_look().x, 0.9, "cursor at the right edge")
	await wait_seconds(1.0)
	assert_almost_eq(cam.seated_offset.x, -PlayerCamera.SEATED_LOOK_YAW, deg_to_rad(2.0), "head turned right by the full small range")
	var fwd: Vector3 = -cam.camera.global_basis.z
	var turned: float = rad_to_deg(Vector2(centre_fwd.x, centre_fwd.z).angle_to(Vector2(fwd.x, fwd.z)))
	assert_between(absf(turned), 20.0, 30.0, "turned about 25 degrees (%.1f)" % turned)
	_move_mouse(Vector2(size.x * 0.5, 0.0))
	await wait_seconds(1.0)
	assert_almost_eq(cam.seated_offset.x, 0.0, deg_to_rad(1.0))
	assert_almost_eq(cam.seated_offset.y, PlayerCamera.SEATED_LOOK_PITCH, deg_to_rad(2.0), "cursor at the top looks up")


func test_mouse_clicks_reach_chip_bet_and_action_buttons() -> void:
	await _start_scene()
	await _sit(SID)
	var ui: BlackjackUi = scene.current_ui as BlackjackUi
	assert_not_null(ui)
	_hide_runner_gui()
	await wait_process_frames(2)  # layout
	var chip: Button = ui.bet_panel._chip_buttons[2]
	var hovered: Control = _click(chip)
	assert_eq(hovered, chip, "nothing covers the chip button (STOP controls there: %s)" % _blockers_at(chip))
	assert_eq(ui.bet_panel.selected_chip, 2, "clicking a chip picks it")
	await wait_process_frames(1)
	assert_null(get_viewport().gui_get_focus_owner(), "a click leaves no focus behind for Space to press again")
	var before: int = scene.server.economy.balance(scene.local_id)
	var confirm: Button = ui.bet_panel._confirm
	assert_eq(_click(confirm), confirm, "BET button under the cursor (%s)" % _blockers_at(confirm))
	await wait_seconds(0.5)  # the station state reaches the client view
	assert_false(_hand().is_empty(), "clicking BET placed a bet")
	assert_lt(scene.server.economy.balance(scene.local_id), before)
	await wait_seconds(Registry.balance.bj_betting_window + 0.6)
	var st: int = int(scene.view.state.stations[SID]["state"])
	if st != BlackjackLogic.State.ACTING or bool(_hand().get("done", true)):
		pass_test("a natural settled the hand before we could act (random deal)")
		return
	assert_true(ui.actions.visible, "action buttons shown")
	var cards_before: int = (_hand().get("cards", []) as Array).size()
	assert_eq(_click(ui.hit), ui.hit, "HIT under the cursor (%s)" % _blockers_at(ui.hit))
	await wait_seconds(0.5)
	var h: Dictionary = _hand()
	assert_eq((h.get("cards", []) as Array).size(), cards_before + 1, "clicking HIT drew a card")
	if bool(h.get("done", true)):
		return  # busted or hit 21
	assert_eq(_click(ui.stand), ui.stand)
	await wait_seconds(0.5)
	assert_true(bool(_hand().get("done", false)) or _hand().is_empty(), "clicking STAND ends the hand")


func test_dealt_cards_lean_towards_every_seat() -> void:
	var st := BlackjackStation.new()
	add_child_autofree(st)
	await wait_process_frames(1)
	var c: Callable = func(rank: int, suit: int) -> int: return Card.make(rank, suit)
	for seat: int in st.seat_count:
		st.set_viewer_seat(seat)
		var seats: Array = [-1, -1, -1, -1]
		seats[seat] = 7
		st.show_round({"state": BlackjackLogic.State.ACTING, "seats": seats, "dealer_revealed": false,
			"dealer": [c.call(10, 1)], "hands": {7: {"cards": [c.call(8, 0), c.call(3, 2)]}}})
		await wait_seconds(1.2)  # deal tweens
		var eye: Vector3 = st.camera_for_seat(seat).global_position
		var dealer: Array[Node3D] = st.cards.pile_nodes(-1)
		assert_eq(dealer.size(), 2, "up card and hole card")
		var up: Node3D = dealer[0]
		var face: float = up.global_basis.y.normalized().dot((eye - up.global_position).normalized())
		assert_gt(face, 0.85, "seat %d reads the dealer's up card nearly face-on (%.2f)" % [seat, face])
		var hole: Node3D = dealer[1]
		var hole_face: float = hole.global_basis.y.normalized().dot((eye - hole.global_position).normalized())
		assert_lt(hole_face, -0.5, "the hole card shows its back (%.2f)" % hole_face)
		for n: Node3D in st.cards.pile_nodes(seat):
			var d: float = n.global_basis.y.normalized().dot((eye - n.global_position).normalized())
			assert_gt(d, 0.6, "seat %d's own cards lean towards it (%.2f)" % [seat, d])
		# The dealer's cards sit in view of the seat camera (not off the top of the screen).
		var cam_fwd: Vector3 = -st.camera_for_seat(seat).global_basis.z
		var to_up: Vector3 = (up.global_position - eye).normalized()
		assert_gt(rad_to_deg(cam_fwd.angle_to(to_up)), 0.0)
		assert_lt(rad_to_deg(cam_fwd.angle_to(to_up)), 30.0, "dealer's card near the middle of seat %d's view" % seat)
		st.show_round({"state": BlackjackLogic.State.IDLE, "seats": seats, "dealer": [], "hands": {}})
		await wait_seconds(0.5)
	# Revealed: the hole card flips face up towards the seat.
	st.set_viewer_seat(0)
	st.show_round({"state": BlackjackLogic.State.ACTING, "seats": [7, -1, -1, -1], "dealer_revealed": false,
		"dealer": [c.call(10, 1)], "hands": {7: {"cards": [c.call(8, 0), c.call(3, 2)]}}})
	await wait_seconds(1.2)
	st.show_round({"state": BlackjackLogic.State.PAYOUT, "seats": [7, -1, -1, -1], "dealer_revealed": true,
		"dealer": [c.call(10, 1), c.call(9, 2)], "hands": {7: {"cards": [c.call(8, 0), c.call(3, 2)]}}})
	await wait_seconds(0.8)
	var eye0: Vector3 = st.camera_for_seat(0).global_position
	var hole2: Node3D = st.cards.pile_nodes(-1)[1]
	assert_gt(hole2.global_basis.y.normalized().dot((eye0 - hole2.global_position).normalized()), 0.85, "revealed hole card faces the seat")
