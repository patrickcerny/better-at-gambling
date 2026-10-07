extends GutTest
## Gift Shop kiosk, Rock Paper Scissors prompts and the Out of Order sign in the real match scene.

var scene: MatchScene
var events: Array[Dictionary] = []


func before_each() -> void:
	events.clear()
	Net.stop()
	scene = (load("res://match/match_scene.tscn") as PackedScene).instantiate()
	add_child_autofree(scene)
	Net.event_received.connect(_collect)
	await wait_seconds(3.3)
	assert_eq(scene.server.phases.phase, Phase.Id.CASINO, "casino phase after the intro")


func after_each() -> void:
	if Net.event_received.is_connected(_collect):
		Net.event_received.disconnect(_collect)


func _collect(ev: Dictionary) -> void:
	events.append(ev)


func _of(type: StringName) -> Array[Dictionary]:
	return events.filter(func(e: Dictionary) -> bool: return e["type"] == type)


func _bot() -> int:
	for pid: int in scene.avatars:
		if pid != scene.local_id:
			return pid
	return -1


func _key(code: Key) -> void:
	var k := InputEventKey.new()
	k.keycode = code
	k.physical_keycode = code
	k.pressed = true
	Input.parse_input_event(k)
	await wait_process_frames(2)
	var up: InputEventKey = k.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	await wait_process_frames(1)


func test_gift_shop_kiosk_prompt_panel_and_buy() -> void:
	assert_eq(scene.view.state.shop_offers.size(), GiftShop.OFFERS, "stock arrives with the casino")
	assert_not_null(scene.map.find_child("ShopCounter", true, false), "kiosk is built")
	scene.local.teleport(LuckyLounge.SHOP_POS, -PI / 2.0)
	scene.server.set_server_position(scene.local_id, LuckyLounge.SHOP_POS)
	await wait_seconds(0.3)
	assert_string_contains(scene.hud.prompt_label.text, "Gift Shop")
	scene.router.interact.emit()
	await wait_process_frames(2)
	assert_true(scene.shop_panel.visible, "E opens the shop")
	assert_eq(scene.router.mode, InputRouter.Mode.MENU)
	var before: int = scene.server.economy.balance(scene.local_id)
	var cheapest: int = 0
	for i: int in scene.view.state.shop_offers.size():
		if int(scene.view.state.shop_offers[i]["price"]) < int(scene.view.state.shop_offers[cheapest]["price"]):
			cheapest = i
	var item: StringName = StringName(scene.view.state.shop_offers[cheapest]["item"])
	await _key(KEY_1 + cheapest)
	await wait_seconds(0.3)
	assert_false(scene.shop_panel.visible, "buying closes the panel")
	assert_eq(scene.router.mode, InputRouter.Mode.WALK)
	assert_eq(_of(&"shop_bought").size(), 1)
	assert_true(item in scene.server.state.players[scene.local_id].inventory)
	assert_eq(scene.server.economy.balance(scene.local_id), before - int(scene.view.state.shop_offers[cheapest]["price"]))
	scene.shop_panel.open()
	await wait_process_frames(3)
	assert_string_contains(scene.shop_panel._note.text, "already bought")
	scene.shop_panel.close_panel()


func test_duel_prompt_accept_and_pick_with_keys() -> void:
	var bot: int = _bot()
	scene.server.items.duels.challenge(bot, scene.local_id, 1, scene.server.match_time)
	await wait_seconds(0.5)
	assert_true(scene.hud.items.duel_panel.visible, "challenge prompt")
	assert_string_contains(scene.hud.items.duel_label.text, "[Y] Accept")
	await _key(KEY_Y)
	await wait_seconds(0.5)
	assert_string_contains(scene.hud.items.duel_label.text, "[1] Rock")
	await _key(KEY_2)
	await wait_seconds(RpsDuels.PICK_TIME * 2 + 1.0)
	var results: Array[Dictionary] = _of(&"rps_result")
	assert_gt(results.size(), 0)
	assert_eq(results[0]["pick_b"], &"paper", "the local player picked paper with key 2")
	assert_false(results.back()["replay"])
	assert_false(scene.hud.items.duel_panel.visible, "prompt gone after the duel")


func test_declining_with_n() -> void:
	var bot: int = _bot()
	scene.server.items.duels.challenge(bot, scene.local_id, 0, scene.server.match_time)
	await wait_seconds(0.5)
	await _key(KEY_N)
	await wait_seconds(0.3)
	assert_eq(_of(&"rps_cancelled").size(), 1)
	assert_eq(_of(&"rps_cancelled")[0]["reason"], &"declined")


func test_out_of_order_sign_shows_on_the_table() -> void:
	var sid: StringName = &"roulette_1"
	var node: StationBase = scene.map.stations[sid]
	scene.local.teleport(node.global_position + Vector3(0, 0, 1.6), 0.0)
	scene.server.set_server_position(scene.local_id, node.global_position + Vector3(0, 0, 1.6))
	scene.server.items.give(scene.local_id, &"out_of_order", scene.server.match_time)
	await wait_process_frames(2)
	scene.items_ctl.on_slot(0)
	await wait_seconds(1.0)
	assert_eq(_of(&"item_used").size(), 1)
	assert_eq(StringName(_of(&"item_used")[0]["station"]), sid)
	assert_not_null(node.out_of_order_sign)
	assert_true(node.out_of_order_sign.visible)
	assert_string_contains(scene.hud.prompt_label.text, "OUT OF ORDER")


func test_roulette_chip_badge_sits_on_its_own_spot() -> void:
	var sid: StringName = &"roulette_1"
	scene._autosit(sid)
	await wait_seconds(4.0)
	assert_eq(scene.local.state, PlayerAvatar.State.SEATED)
	var ui: RouletteUi = scene.current_ui as RouletteUi
	assert_not_null(ui)
	var res: Dictionary = Net.send_intent(Intents.make(&"place_bet", {"station": sid, "bet": {"type": &"straight", "value": 17, "amount": 10}}))
	assert_true(res["ok"], str(res))
	await wait_seconds(1.0)
	var badge: Label = ui._badges["straight:17"]
	assert_true(badge.visible)
	var spot: Button = badge.get_parent() as Button
	assert_eq(spot.text, "17")
	var centre: Vector2 = badge.get_global_rect().get_center()
	assert_true(centre.x > spot.get_global_rect().position.x and centre.x < spot.get_global_rect().end.x, "badge centred over 17, not the neighbour")
	assert_lt(badge.get_global_rect().size.x, spot.get_global_rect().size.x + 1.0, "badge no wider than its spot")
	# The overlay stays clear of the item bar.
	assert_true(ui.panel.get_global_rect().end.y <= scene.hud.items.slots[0].get_global_rect().position.y + 1.0, "station panel above the item slots")


func test_roulette_panel_leaves_the_table_visible() -> void:
	var sid: StringName = &"roulette_1"
	scene._autosit(sid)
	await wait_seconds(4.0)
	var ui: StationUi = scene.current_ui
	assert_true(ui is RouletteUi)
	var view: Vector2 = scene.get_viewport().get_visible_rect().size
	var rect: Rect2 = ui.panel.get_global_rect()
	assert_gt(rect.position.x, view.x * 0.7, "panel docked at the right edge")
	assert_lt(rect.size.x, view.x * 0.2, "a slim panel")
	assert_true(rect.end.y <= scene.hud.items.slots[0].get_global_rect().position.y + 1.0, "panel above the item slots")
	assert_true(rect.position.y >= 0.0, "panel fully on screen")
	# Projected on a 16:9 1920x1080 frame like a real window (headless views are square); the panel is
	# docked to the right edge, so only its left edge matters for what it covers.
	var st: RouletteStation = scene.map.stations[sid]
	var cam: Camera3D = scene.pixel_view.world_viewport().get_camera_3d()
	var frame: Vector2 = Vector2(1920, 1080)
	var proj: Projection = Projection.create_perspective(cam.fov, frame.x / frame.y, cam.near, cam.far)
	var to_screen: Callable = func(local: Vector3) -> Vector2:
		var p: Vector3 = cam.global_transform.affine_inverse() * st.to_global(local)
		var clip: Vector4 = proj * Vector4(p.x, p.y, p.z, 1.0)
		return Vector2((clip.x / clip.w + 1.0) * 0.5 * frame.x, (1.0 - clip.y / clip.w) * 0.5 * frame.y)
	var panel_left: float = rect.position.x - (view.x - frame.x)
	var points: Dictionary = {
		"wheel's left rim": Vector3(-2.05, RouletteStation.FELT_Y, 0),
		"wheel": Vector3(-1.3, RouletteStation.FELT_Y, 0),
		"felt": RouletteStation.bet_spot(&"straight", 17),
		"column bets": RouletteStation.bet_spot(&"column", 2),
	}
	for what: String in points:
		var p: Vector2 = to_screen.call(points[what])
		assert_true(Rect2(Vector2.ZERO, frame).has_point(p), "%s on screen: %s" % [what, p])
		assert_lt(p.x, panel_left, "panel does not cover the %s: %s" % [what, p])


func test_plinko_panel_leaves_the_board_visible() -> void:
	scene._autosit(&"plinko_1")
	await wait_seconds(4.0)
	var ui: StationUi = scene.current_ui
	assert_not_null(ui)
	var view: Vector2 = scene.get_viewport().get_visible_rect().size
	var rect: Rect2 = ui.panel.get_global_rect()
	assert_gt(rect.position.x, view.x * 0.7, "panel docked at the right edge")
	assert_lt(rect.size.x, view.x * 0.2, "a slim panel")
	assert_lt(rect.size.y, view.y * 0.6)
	# The whole board (funnel to bucket plates) is on screen and clear of the panel.
	var st: PlinkoStation = scene.map.stations[&"plinko_1"]
	var cam: Camera3D = scene.pixel_view.world_viewport().get_camera_3d()  # the pixel look draws the world in a sub viewport
	var proj: Projection = Projection.create_perspective(cam.fov, view.x / view.y, cam.near, cam.far)
	var to_screen: Callable = func(local: Vector3) -> Vector2:  # on a 1920x1080 canvas (headless windows are tiny)
		var p: Vector3 = cam.global_transform.affine_inverse() * st.to_global(local)
		var clip: Vector4 = proj * Vector4(p.x, p.y, p.z, 1.0)
		return Vector2((clip.x / clip.w + 1.0) * 0.5 * view.x, (1.0 - clip.y / clip.w) * 0.5 * view.y)
	var entry: Vector2 = to_screen.call(Vector3(0, PlinkoStation.entry_y(), 0))
	var right_rail: Vector2 = to_screen.call(Vector3(PlinkoStation.BOARD_W * 0.5 + 0.1, PlinkoStation.FLOOR_Y + 1.0, 0.2))
	var plate: Vector2 = to_screen.call(Vector3(PlinkoStation.slot_x(PlinkoStation.SLOTS - 1), PlinkoStation.FLOOR_Y - 0.17, 0.27))
	assert_true(Rect2(Vector2.ZERO, view).has_point(entry), "chip entry on screen: %s" % entry)
	assert_true(Rect2(Vector2.ZERO, view).has_point(plate), "payout plates on screen: %s" % plate)
	assert_lt(right_rail.x, rect.position.x, "board's right edge left of the panel")
	assert_false(rect.has_point(entry), "panel never covers where the chip enters")


func before_all() -> void:
	MatchScene.test_dummies = 3  # standing dummies to shove, grab and target


func after_all() -> void:
	MatchScene.test_dummies = 0
