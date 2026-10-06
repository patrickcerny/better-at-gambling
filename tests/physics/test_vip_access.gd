extends GutTest
## The VIP mezzanine is reachable on foot: a player walks from the casino floor up the stairs,
## is bounced by the bouncer while broke, and once rich enough walks through the gate and sits
## at the VIP blackjack table. Movement goes through the avatar's own walking code (auto_target),
## so the stairs, landings, gate and railing collision are all exercised.

var scene: MatchScene


func before_all() -> void:
	MatchScene.test_dummies = 1


func after_all() -> void:
	MatchScene.test_dummies = 0


func before_each() -> void:
	Net.stop()
	scene = (load("res://match/match_scene.tscn") as PackedScene).instantiate()
	add_child_autofree(scene)
	scene.server.timescale = 1.0
	await wait_seconds(3.3)
	assert_eq(scene.server.phases.phase, Phase.Id.CASINO, "casino phase after the intro")


## Walks the local player to `goal` (x/z) and returns true when it got within `tol` of it.
func _walk_to(goal: Vector3, timeout: float = 8.0, tol: float = 0.6) -> bool:
	scene.local.auto_target = goal
	var t: float = 0.0
	while t < timeout:
		await wait_physics_frames(1)
		t += get_physics_process_delta_time()
		var p: Vector3 = scene.local.global_position
		if Vector2(p.x, p.z).distance_to(Vector2(goal.x, goal.z)) < tol:
			scene.local.auto_target = Vector3.INF
			scene.server.set_server_position(scene.local_id, scene.local.global_position)
			return true
	scene.local.auto_target = Vector3.INF
	return false


func test_rich_player_walks_up_to_the_vip_table_and_sits() -> void:
	var me: int = scene.local_id
	scene.server.economy.apply(me, 5000, &"test")
	scene.local.teleport(Vector3(12.0, 0.0, 10.0), PI)
	await wait_physics_frames(2)
	assert_true(await _walk_to(Vector3(12.0, 0.0, 4.6)), "first flight: %s" % scene.local.global_position)
	assert_almost_eq(scene.local.global_position.y, LuckyLounge.MEZZ_Y * 0.5, 0.35, "on the landing")
	assert_true(await _walk_to(Vector3(12.0, 0.0, -3.0)), "second flight: %s" % scene.local.global_position)
	assert_almost_eq(scene.local.global_position.y, LuckyLounge.MEZZ_Y, 0.3, "on the mezzanine landing")
	assert_true(await _walk_to(Vector3(6.5, 0.0, -3.0)), "through the gate: %s" % scene.local.global_position)
	assert_almost_eq(scene.local.global_position.y, LuckyLounge.MEZZ_Y, 0.3, "still on the mezzanine")
	var table: Vector3 = scene.map.stations[&"vip_blackjack_1"].global_position
	assert_true(await _walk_to(table + Vector3(0, 0, 2.8)), "at the VIP table: %s" % scene.local.global_position)
	var res: Dictionary = Net.send_intent(Intents.make(&"sit", {"station": &"vip_blackjack_1"}))
	assert_true(res["ok"], "sits at the VIP blackjack table: %s" % res)
	await wait_physics_frames(3)
	assert_eq(scene.local.state, PlayerAvatar.State.SEATED)


func test_broke_player_is_bounced_at_the_gate() -> void:
	var me: int = scene.local_id
	assert_lt(scene.server.economy.balance(me), scene.server.vip_threshold(), "starts under the VIP threshold")
	scene.local.teleport(Vector3(12.0, LuckyLounge.MEZZ_Y, -3.0), PI * 0.5)
	scene.server.set_server_position(me, scene.local.global_position)
	await wait_physics_frames(2)
	var got_in: bool = await _walk_to(Vector3(6.5, 0.0, -3.0), 4.0)
	assert_false(got_in, "the bouncer keeps a broke player out: %s" % scene.local.global_position)
	assert_gt(scene.local.global_position.x, LuckyLounge.VIP_GATE_POS.x - 0.5, "pushed back towards the stairs")
	assert_almost_eq(scene.local.global_position.y, LuckyLounge.MEZZ_Y, 0.3, "and not knocked off the mezzanine")
	assert_true(scene.hud.toast_label.text.begins_with("VIP ACCESS"), "the gate says what it takes: %s" % scene.hud.toast_label.text)
	# Money opens the gate: the same walk succeeds once the player is rich enough.
	scene.server.economy.apply(me, 5000, &"test")
	await wait_physics_frames(3)
	assert_true(await _walk_to(Vector3(6.5, 0.0, -3.0), 6.0), "rich now, walks in: %s" % scene.local.global_position)
