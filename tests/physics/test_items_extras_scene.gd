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
	# The overlay stays clear of the item bar.
	assert_true(ui.panel.get_global_rect().end.y <= scene.hud.items.slots[0].get_global_rect().position.y + 1.0, "station panel above the item slots")


func test_plinko_panel_leaves_the_board_visible() -> void:
	scene._autosit(&"plinko_1")
	await wait_seconds(4.0)
	var ui: StationUi = scene.current_ui
	assert_not_null(ui)
	var view: Vector2 = scene.get_viewport().get_visible_rect().size
	assert_gt(ui.panel.get_global_rect().position.x, view.x * 0.7, "panel docked at the right edge")


func before_all() -> void:
	MatchScene.test_dummies = 3  # standing dummies to shove, grab and target


func after_all() -> void:
	MatchScene.test_dummies = 0
