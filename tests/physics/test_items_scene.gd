extends GutTest
## Items in the real match scene (0.8.19): keys, wheel and clicks put an item in the hand and use
## it, aimed items hit whoever is in front (ring and outline), the greed choice on the bar, banners,
## banana peel meshes, effect tags, the HUD luck meter and the discard choice. Everything goes
## through intents and server events, like a player.

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


func _give(items: Array[StringName]) -> void:
	for it: StringName in items:
		scene.server.items.give(scene.local_id, it, scene.server.match_time)


func _others() -> Array[int]:
	var out: Array[int] = []
	for pid: int in scene.avatars:
		if pid != scene.local_id:
			out.append(pid)
	return out


func _key(code: Key, shift: bool = false) -> void:
	var k := InputEventKey.new()
	k.keycode = code
	k.physical_keycode = code
	k.shift_pressed = shift
	k.pressed = true
	Input.parse_input_event(k)
	await wait_process_frames(2)
	var up: InputEventKey = k.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	await wait_process_frames(1)


func _click(button: MouseButton) -> void:
	var m := InputEventMouseButton.new()
	m.button_index = button
	m.pressed = true
	Input.parse_input_event(m)
	await wait_process_frames(2)
	var up: InputEventMouseButton = m.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	await wait_process_frames(1)


## Puts `front` a few metres in front of the local player and every other dummy behind them.
func _line_up(front: int, dist: float = 2.5) -> void:
	var me: Vector3 = Vector3(6, 0, 6)
	scene.local.teleport(me, 0.0)
	scene.server.set_server_position(scene.local_id, me)
	var fwd: Vector3 = scene.local.facing()
	for pid: int in _others():
		var p: Vector3 = me + fwd * dist if pid == front else me - fwd * (6.0 + pid)
		scene.avatars[pid].teleport(p, 0.0)
		scene.server.set_server_position(pid, p)
		scene.view.state.players[pid]["pos"] = Serializer.vec3(p)  # dummies walk to their last known spot


func test_key_holds_the_item_then_uses_it() -> void:
	_give([&"lucky_clover"])
	await wait_process_frames(2)
	assert_eq(scene.hud.items.slot_names[0].text, "Lucky Clover")
	assert_eq(scene.items_ctl.held, -1, "hands empty at first")
	await _key(KEY_1)
	assert_eq(scene.items_ctl.held, 0, "key 1 takes it out")
	assert_eq(scene.hud.items.selected, 0)
	assert_not_null(scene.items_ctl.held_model, "the item is in the hand")
	assert_true(scene.local.is_ancestor_of(scene.items_ctl.held_model), "on the avatar (hand, or the view in first person)")
	assert_true(scene.hud.items.selection_panel.visible, "name and description pop up")
	assert_eq(scene.hud.items.selection_name.text, "Lucky Clover")
	assert_string_contains(scene.hud.items.selection_desc.text, "Luck")
	assert_eq(_of(&"item_used").size(), 0, "taking it out uses nothing")
	await _click(MOUSE_BUTTON_LEFT)
	await wait_seconds(0.4)
	assert_eq(_of(&"item_used").size(), 1, "left click used the held item")
	assert_eq(scene.server.modifiers.get_luck(scene.local_id), 2)
	assert_eq(scene.hud.items.luck, 2, "luck meter")
	assert_string_contains(scene.hud.items.effects_label.text, "Lucky Clover")
	assert_true(scene.hud.item_banner.visible, "activation banner")
	assert_eq(scene.effect_tags[scene.local_id].text, "LUCKY")
	assert_eq(scene.hud.items.slot_names[0].text, "—")
	assert_eq(scene.items_ctl.held, -1, "used up: hands empty again")
	assert_null(scene.items_ctl.held_model)


func test_wheel_moves_the_hand_and_right_click_puts_it_away() -> void:
	_give([&"lucky_clover", &"bodyguard"])
	await wait_process_frames(2)
	await _click(MOUSE_BUTTON_WHEEL_DOWN)
	assert_eq(scene.items_ctl.held, 0)
	await _click(MOUSE_BUTTON_WHEEL_DOWN)
	assert_eq(scene.items_ctl.held, 1)
	assert_eq(scene.hud.items.selection_name.text, "Bodyguard")
	assert_eq(scene.items_ctl.held_model.get_meta(&"item"), &"bodyguard")
	await _click(MOUSE_BUTTON_WHEEL_DOWN)
	assert_eq(scene.items_ctl.held, 0, "wraps around the filled slots")
	await _click(MOUSE_BUTTON_RIGHT)
	assert_eq(scene.items_ctl.held, -1, "right click: put away")
	assert_eq(scene.hud.items.selected, -1)
	assert_null(scene.items_ctl.held_model)
	assert_eq(_of(&"item_used").size(), 0)
	assert_eq(_of(&"player_shoved").size(), 0, "the right click didn't shove anyone")


func test_aimed_item_hits_the_player_in_front() -> void:
	var others: Array[int] = _others()
	assert_gt(others.size(), 1, "needs two dummies")
	var front: int = others[1]
	_give([&"black_cat"])
	_line_up(front)
	await wait_process_frames(2)
	scene.items_ctl.on_slot(0)
	_line_up(front)
	await wait_process_frames(3)
	assert_eq(scene.items_ctl.aimed, front, "the one in front is aimed at")
	assert_true(scene.items_ctl.ring.visible, "floor ring under them")
	assert_false(scene.items_ctl._outlined.is_empty(), "outline on them")
	assert_string_contains(scene.hud.items.target_label.text, scene.view.state.player_name(front))
	scene.items_ctl.use_held()
	await wait_seconds(0.3)
	var used: Array[Dictionary] = _of(&"item_used")
	assert_eq(used.size(), 1)
	assert_eq(int(used[0]["target"]), front)
	assert_eq(scene.server.modifiers.get_luck(front), -2)
	assert_eq(scene.effect_tags[front].text, "JINXED")
	await wait_process_frames(2)
	assert_eq(scene.items_ctl.aimed, -1)
	assert_false(scene.items_ctl.ring.visible)
	assert_true(scene.items_ctl._outlined.is_empty(), "outline gone with the item")


func test_nobody_in_the_cone_does_nothing() -> void:
	_give([&"black_cat"])
	_line_up(-1)
	await wait_process_frames(2)
	scene.items_ctl.on_slot(0)
	_line_up(-1)
	await wait_process_frames(2)
	assert_eq(scene.items_ctl.aimed, -1)
	assert_string_contains(scene.hud.items.target_label.text, "no one in reach")
	scene.items_ctl.use_held()
	await wait_seconds(0.3)
	assert_eq(_of(&"item_used").size(), 0)
	assert_eq(scene.hud.toast_label.text, "No one in reach")
	assert_eq(scene.items_ctl.held, 0, "still in the hand")


func test_pickpocket_asks_greed_on_the_bar_first() -> void:
	var front: int = _others()[0]
	_give([&"pickpocket"])
	_line_up(front, 1.5)
	await wait_process_frames(2)
	scene.items_ctl.on_slot(0)
	_line_up(front, 1.5)
	await wait_process_frames(2)
	scene.items_ctl.on_slot(0)  # the same key again uses it: the choice opens
	assert_true(scene.hud.items.choice_panel.visible, "two-button choice")
	assert_eq(_of(&"item_used").size(), 0, "nothing sent yet")
	scene.hud.items.choice_buttons[1].pressed.emit()
	await wait_seconds(0.3)
	assert_false(scene.hud.items.choice_panel.visible)
	var used: Array[Dictionary] = _of(&"item_used")
	assert_eq(used.size(), 1)
	assert_eq(int(used[0]["target"]), front)
	assert_eq(int(used[0]["tier"]), 1, "the greedy button")


func test_banana_peel_mesh_and_slip() -> void:
	var victim: int = _others()[0]
	scene.local.teleport(Vector3(6, 0, 6), 0.0)
	scene.server.set_server_position(scene.local_id, Vector3(6, 0, 6))
	_give([&"banana_peel"])
	await wait_seconds(0.2)
	await _key(KEY_1)
	await _key(KEY_1)
	await wait_seconds(0.3)
	assert_eq(scene.peel_nodes.size(), 1, "a peel lies on the floor")
	scene.avatars[victim].teleport(Vector3(6, 0, 6), 0.0)
	scene.server.set_server_position(victim, Vector3(6, 0, 6))
	await wait_seconds(0.4)
	var slips: Array[Dictionary] = _of(&"banana_slip")
	if slips.is_empty():
		# The dummy may have wandered off before the server saw it on the peel: place it again.
		scene.server.set_server_position(victim, Vector3(6, 0, 6))
		await wait_seconds(0.3)
		slips = _of(&"banana_slip")
	assert_eq(slips.size(), 1, "the dummy slipped")
	assert_eq(scene.peel_nodes.size(), 0, "peel gone")


func test_discard_choice_with_number_keys() -> void:
	# Three slots: the fourth item asks which one to throw away; key 2 swaps out slot 2.
	_give([&"lucky_clover", &"black_cat", &"mirror", &"bodyguard"])
	await wait_seconds(0.5)
	assert_true(scene.hud.items.discard_panel.visible, "inventory full panel")
	assert_string_contains(scene.hud.items.discard_label.text, "Bodyguard")
	await _key(KEY_2)
	await wait_seconds(0.3)
	assert_false(scene.hud.items.discard_panel.visible)
	assert_eq(scene.server.state.players[scene.local_id].inventory, [&"lucky_clover", &"mirror", &"bodyguard"] as Array[StringName])
	assert_eq(_of(&"item_used").size(), 0, "the key answered the discard, not an item")


func test_seated_number_keys_pick_chips_shift_uses_items() -> void:
	scene.router.set_mode(InputRouter.Mode.SEATED)
	var plain := InputEventKey.new()
	plain.keycode = KEY_1
	plain.physical_keycode = KEY_1
	plain.pressed = true
	assert_eq(scene.router._item_slot(plain), -1)
	plain.shift_pressed = true
	assert_eq(scene.router._item_slot(plain), 0)
	scene.router.set_mode(InputRouter.Mode.WALK)
	plain.shift_pressed = false
	assert_eq(scene.router._item_slot(plain), 0)


func before_all() -> void:
	MatchScene.test_dummies = 3  # standing dummies to shove, grab and target


func after_all() -> void:
	MatchScene.test_dummies = 0
