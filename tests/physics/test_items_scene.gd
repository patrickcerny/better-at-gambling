extends GutTest
## Items in the real match scene (M5): item keys through the InputRouter, the target picker, the
## proximity ring, banners, banana peel meshes, effect tags, the HUD luck meter and the discard
## choice. Everything goes through intents and server events, like a player.

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


func test_self_item_from_the_key_updates_hud_and_tag() -> void:
	_give([&"lucky_clover"])
	await wait_process_frames(2)
	assert_eq(scene.hud.items.slot_names[0].text, "Lucky Clover")
	await _key(KEY_1)
	await wait_seconds(0.4)
	assert_eq(_of(&"item_used").size(), 1, "key 1 used the item")
	assert_eq(scene.server.modifiers.get_luck(scene.local_id), 2)
	assert_eq(scene.hud.items.luck, 2, "luck meter")
	assert_string_contains(scene.hud.items.effects_label.text, "Lucky Clover")
	assert_true(scene.hud.item_banner.visible, "activation banner")
	assert_eq(scene.effect_tags[scene.local_id].text, "LUCKY")
	assert_eq(scene.hud.items.slot_names[0].text, "—")


func test_target_picker_cycles_and_confirms() -> void:
	var others: Array[int] = _others()
	assert_gt(others.size(), 1, "needs two dummies to pick between")
	_give([&"black_cat"])
	await wait_process_frames(2)
	scene.items_ctl.on_slot(0)
	assert_eq(scene.items_ctl.picking_slot, 0, "picker open")
	assert_true(scene.items_ctl.marker.visible)
	assert_string_contains(scene.hud.items.target_label.text, "Black Cat")
	var first: int = scene.items_ctl.picking_candidates[0]
	scene.items_ctl.cycle(1)
	var chosen: int = scene.items_ctl.picking_candidates[scene.items_ctl.picking_index]
	assert_ne(chosen, first)
	scene.items_ctl.on_slot(0)  # same key confirms
	await wait_seconds(0.3)
	assert_eq(scene.items_ctl.picking_slot, -1)
	var used: Array[Dictionary] = _of(&"item_used")
	assert_eq(used.size(), 1)
	assert_eq(int(used[0]["target"]), chosen)
	assert_eq(scene.server.modifiers.get_luck(chosen), -2)
	assert_eq(scene.effect_tags[chosen].text, "JINXED")


func test_picker_times_out() -> void:
	_give([&"black_cat"])
	await wait_process_frames(2)
	scene.items_ctl.on_slot(0)
	await wait_seconds(ItemController.PICK_SECONDS + 0.3)
	assert_eq(scene.items_ctl.picking_slot, -1)
	assert_eq(_of(&"item_used").size(), 0)


func test_near_item_shows_ring_and_needs_range() -> void:
	for pid: int in _others():
		var far := Vector3(-10, 0, 8) + Vector3(pid, 0, 0)
		scene.avatars[pid].teleport(far, 0.0)
		scene.server.set_server_position(pid, far)
	scene.local.teleport(Vector3(8, 0, 8), 0.0)
	scene.server.set_server_position(scene.local_id, Vector3(8, 0, 8))
	_give([&"pickpocket"])
	await wait_process_frames(2)
	scene.items_ctl.on_slot(0)
	assert_eq(scene.items_ctl.picking_slot, -1, "nobody in range: no picker")
	assert_true(scene.items_ctl.ring.visible, "the range ring shows")
	assert_almost_eq((scene.items_ctl.ring.mesh as TorusMesh).outer_radius, Registry.items[&"pickpocket"].range_m, 0.01)
	assert_eq(_of(&"item_used").size(), 0)


func test_banana_peel_mesh_and_slip() -> void:
	var victim: int = _others()[0]
	scene.local.teleport(Vector3(6, 0, 6), 0.0)
	scene.server.set_server_position(scene.local_id, Vector3(6, 0, 6))
	_give([&"banana_peel"])
	await wait_seconds(0.2)
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
