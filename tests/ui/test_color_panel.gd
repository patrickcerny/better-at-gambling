extends GutTest
## The colour panel at the foot of your ready pedestal (Patrick: "under the podest should be a
## color panel you can click (choose color). If you choose that, your bean is in that color."):
## it shows the colours you own, looking at a swatch and clicking (or E) sends `set_color`, the
## server recolours your bean for everyone and the colour becomes your preferred one. Colours
## other beans wear are refused, and other players' panels don't work for you.

var scene: MatchScene


func before_each() -> void:
	ProfileManager.reload()
	Net.stop()
	MatchScene.test_dummies = 1
	scene = (load("res://match/match_scene.tscn") as PackedScene).instantiate()
	add_child_autofree(scene)
	await wait_seconds(3.3)
	MatchScene.test_dummies = 0
	# The practice match turned into a room waiting in its lobby.
	scene.server.room_mode = true
	scene.server.running = false
	scene.server.phases.phase = Phase.Id.LOBBY
	scene.view.state.phase = Phase.Id.LOBBY
	await wait_process_frames(3)


func after_each() -> void:
	ProfileManager.reload()


func _plaque(slot: int) -> ColorPlaque:
	return (scene.map as LuckyLounge).color_plaques[slot]


func _my_slot() -> int:
	return scene.server.state.players[scene.local_id].color_index


## Stands the local player in front of plaque `slot` and points the camera at colour `c`.
func _look_at_swatch(slot: int, c: int) -> void:
	var plaque: ColorPlaque = _plaque(slot)
	var spot: Vector3 = plaque.global_position + Vector3(0, 0, -1.1)
	scene.local.teleport(spot, PI)
	scene.server.set_server_position(scene.local_id, spot)
	await wait_process_frames(3)
	var cam: PlayerCamera = scene.local.cam
	for i: int in 3:
		var target: Vector3 = plaque.swatch_position(c)
		var d: Vector3 = target - cam.camera.global_position
		cam.yaw = atan2(-d.x, -d.z)
		scene.local.yaw = cam.yaw
		cam.pitch = atan2(d.y, Vector2(d.x, d.z).length())
		await wait_process_frames(3)
	for i: int in 30:
		if scene.color_panel.aimed == c:
			break
		await wait_process_frames(1)
	await wait_process_frames(2)


func test_every_pedestal_has_a_panel_at_its_foot() -> void:
	var lounge: LuckyLounge = scene.map as LuckyLounge
	assert_eq(lounge.color_plaques.size(), LuckyLounge.PEDESTALS.size())
	for i: int in LuckyLounge.PEDESTALS.size():
		var p: ColorPlaque = lounge.color_plaques[i]
		var flat: Vector2 = Vector2(p.global_position.x - LuckyLounge.PEDESTALS[i].x, p.global_position.z - LuckyLounge.PEDESTALS[i].z)
		assert_lt(flat.length(), 2.5, "plaque %d stands by its pedestal" % i)
		assert_lt(p.global_position.z, LuckyLounge.PEDESTALS[i].z, "on the room side")
		assert_eq(p.find_children("*", "CollisionShape3D", true, false).size(), 0, "nothing to bump into")


func test_click_a_swatch_and_the_bean_takes_the_colour() -> void:
	ProfileManager.profile.coins = 500
	assert_eq(ProfileManager.buy(&"color_mint"), &"")
	var mine: int = _my_slot()
	await wait_process_frames(2)
	var plaque: ColorPlaque = _plaque(mine)
	assert_true(plaque.interactive, "your own panel is lit")
	assert_true(9 in plaque.colors, "the bought colour is on it")
	assert_eq(plaque.colors.size(), Cosmetics.SLOT_COLORS + 1, "only colours you own")
	assert_false(_plaque((mine + 1) % 8).interactive, "the others' are not")
	await _look_at_swatch(mine, 9)
	assert_eq(scene.color_panel.aimed, 9, "looking at Mint")
	assert_string_contains(scene.hud.prompt_label.text, "Wear Mint")
	scene.router.grab_pressed.emit()  # a left click
	await wait_process_frames(3)
	assert_eq(scene.server.state.players[scene.local_id].bean_color, 9, "the server took it")
	assert_eq(scene.view.state.players[scene.local_id]["bean_color"], 9, "and told everyone")
	assert_eq(scene.local.visuals.color, Palette.player_color(9), "the bean is Mint")
	assert_eq(ProfileManager.profile.preferred_color, 9, "and it is the preferred colour now")
	assert_eq(scene.server.state.players[scene.local_id].color_index, mine, "the pedestal stays yours")
	assert_eq(plaque.worn, 9, "framed on the panel")
	# E works too.
	await _look_at_swatch(mine, 4)
	scene._on_interact()
	await wait_process_frames(3)
	assert_eq(scene.local.visuals.color, Palette.player_color(4))
	assert_eq(ProfileManager.profile.preferred_color, 4)


func test_a_colour_another_bean_wears_is_refused() -> void:
	var dummy: int = scene.dummies.keys()[0]
	var theirs: int = scene.server.state.players[dummy].bean_color
	var mine: int = _my_slot()
	await wait_process_frames(2)
	assert_true(theirs in _plaque(mine).colors)
	await _look_at_swatch(mine, theirs)
	assert_string_contains(scene.hud.prompt_label.text, "another bean wears it")
	var before: Color = scene.local.visuals.color
	scene.router.grab_pressed.emit()
	await wait_process_frames(3)
	assert_eq(scene.local.visuals.color, before, "no change")
	assert_ne(ProfileManager.profile.preferred_color, theirs)
	# Someone else's panel does nothing for you.
	var other: int = scene.server.state.players[dummy].color_index
	await _look_at_swatch(other, (theirs + 1) % 8)
	assert_eq(scene.color_panel.aimed, -1, "not your panel")
