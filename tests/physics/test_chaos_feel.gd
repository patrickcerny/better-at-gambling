extends GutTest
## M7 characters and physical chaos in the real match scene (headless, in-process server, standing
## test dummies): knockout birdies follow the ragdoll and go away on get-up, the leader crown
## follows the richest player, guards carry offenders toward the door before tossing them, the
## reactions are wired to events, and none of the new effects builds anything visual headless.

var scene: MatchScene
var events: Array[Dictionary] = []
var bot: int = -1


func before_each() -> void:
	events.clear()
	Net.stop()
	scene = (load("res://match/match_scene.tscn") as PackedScene).instantiate()
	add_child_autofree(scene)
	Net.event_received.connect(_collect)
	for pid: int in scene.avatars:
		if pid != scene.local_id:
			bot = pid
			break
	scene.server.timescale = 1.0
	await wait_seconds(3.3)
	assert_eq(scene.server.phases.phase, Phase.Id.CASINO, "casino phase after the intro")


func after_each() -> void:
	if Net.event_received.is_connected(_collect):
		Net.event_received.disconnect(_collect)


func _collect(ev: Dictionary) -> void:
	events.append(ev)


func _of(type: StringName) -> Array[Dictionary]:
	return events.filter(func(e: Dictionary) -> bool: return e["type"] == type)


func _face_off(pos: Vector3, dist: float = 1.5, yaw: float = 0.0) -> void:
	scene.local.teleport(pos, yaw)
	var bpos: Vector3 = pos + Vector3(-sin(yaw), 0.0, -cos(yaw)) * dist
	scene.avatars[bot].teleport(bpos, yaw + PI)
	scene.server.set_server_position(bot, bpos)
	scene.server.set_server_position(scene.local_id, pos)


func _shove() -> Dictionary:
	return Net.send_intent(Intents.make(&"shove", {"aim": Serializer.vec3(scene.local.facing())}))


func _meshes(n: Node) -> int:
	return n.find_children("*", "GeometryInstance3D", true, false).size() + n.find_children("*", "CPUParticles3D", true, false).size()


func test_knockout_birdies_follow_the_ragdoll_head_and_go_away_on_get_up() -> void:
	_face_off(Vector3(0, 0, 5))
	await wait_seconds(0.2)
	for i: int in 3:
		_shove()
		await wait_seconds(1.3)
	assert_eq(_of(&"player_knocked_out").size(), 1)
	var b: PlayerAvatar = scene.avatars[bot]
	var orbit: KnockoutOrbit = b.visuals.stars as KnockoutOrbit
	assert_not_null(orbit, "the stars are a KnockoutOrbit")
	assert_eq(b.state, PlayerAvatar.State.RAGDOLL)
	assert_true(orbit.visible, "birdies on knockout")
	assert_true(b.visuals.knocked_out)
	assert_eq(orbit.follow, b.ragdoll.head, "they circle the ragdoll's head")
	assert_true(b.visuals.is_visible_in_tree(), "the halo stays visible while the bean is a ragdoll")
	assert_eq(_meshes(orbit), 0, "nothing visual is built headless")
	await wait_seconds(Registry.balance.knockout_time + 1.0)
	assert_eq(b.state, PlayerAvatar.State.STANDING, "got up")
	assert_false(orbit.visible, "birdies gone after getting up")
	assert_false(b.visuals.knocked_out)
	assert_null(orbit.follow)


func test_crown_follows_the_money_leader() -> void:
	var crown: LeaderCrown = scene.crown
	assert_not_null(crown, "Practice shows the crown")
	await wait_physics_frames(2)
	assert_eq(crown.leader_id, -1, "everyone starts level: nobody wears it")
	assert_false(crown.visible)
	scene.server.economy.apply(bot, 300, &"test")
	await wait_seconds(0.3)
	assert_eq(crown.leader_id, bot, "the richest player gets the crown")
	assert_true(crown.visible)
	var b: PlayerAvatar = scene.avatars[bot]
	assert_almost_eq(crown.global_position.distance_to(b.global_position + Vector3(0, LeaderCrown.HEIGHT, 0)), 0.0, 0.3, "floats over their head")
	b.teleport(b.global_position + Vector3(2, 0, 0))
	scene.server.set_server_position(bot, b.global_position)
	await wait_seconds(0.6)
	assert_almost_eq(crown.global_position.distance_to(b.global_position + Vector3(0, LeaderCrown.HEIGHT, 0)), 0.0, 0.3, "and follows them around")
	scene.server.economy.apply(scene.local_id, 600, &"test")
	await wait_seconds(0.6)
	assert_eq(crown.leader_id, scene.local_id, "a new leader takes it over")
	assert_almost_eq(crown.global_position.distance_to(scene.local.global_position + Vector3(0, LeaderCrown.HEIGHT, 0)), 0.0, 0.3)
	assert_eq(_meshes(crown), 0, "nothing visual is built headless")


func test_leader_of_needs_a_strict_lead() -> void:
	assert_eq(LeaderCrown.leader_of({}), -1)
	assert_eq(LeaderCrown.leader_of({1: 500, 2: 500}), -1, "tie: nobody")
	assert_eq(LeaderCrown.leader_of({1: 500, 2: 700, 3: 700}), -1)
	assert_eq(LeaderCrown.leader_of({1: 900, 2: 700, 3: 700}), 1)
	assert_eq(LeaderCrown.leader_of({1: 0, 2: 5}), 2)


func test_guard_carries_the_offender_toward_the_door_then_tosses_them() -> void:
	var g: Guard = scene.guards[0]
	g.route = [Vector3(-12, 0, -6)]
	g.global_position = Vector3(-12, 0, -6)
	g.yaw = PI
	g.state = Guard.State.PATROL
	_face_off(Vector3(-12, 0, -1), 1.5, PI)
	await wait_seconds(0.2)
	for i: int in 3:
		_shove()
		await wait_seconds(1.3)
	var money: int = scene.server.economy.balance(scene.local_id)
	var waited: float = 0.0
	while _of(&"player_thrown_out").is_empty() and waited < 4.0:
		await wait_physics_frames(1)
		waited += 1.0 / Engine.physics_ticks_per_second
	assert_eq(_of(&"player_thrown_out").size(), 1, "the guard caught us")
	await wait_physics_frames(2)
	assert_eq(scene.local.state, PlayerAvatar.State.HELD, "lifted up")
	assert_eq(scene.local.carrier, g, "by the guard who caught us")
	assert_eq(g.carrying, scene.local)
	assert_eq(g.state, Guard.State.CARRY)
	assert_true(scene.local.visuals.carried, "lying flat and flailing")
	var start: float = g.global_position.distance_to(LuckyLounge.ENTRANCE_POS)
	await wait_seconds(Guard.CARRY_SECONDS * 0.6)
	assert_eq(scene.local.state, PlayerAvatar.State.HELD, "still carried")
	assert_lt(g.global_position.distance_to(LuckyLounge.ENTRANCE_POS), start - 1.0, "walking toward the door")
	assert_gt(scene.local.global_position.y, g.global_position.y + 1.0, "held overhead")
	await wait_seconds(Guard.CARRY_SECONDS * 0.4 + 0.2)
	assert_null(g.carrying, "tossed")
	assert_null(scene.local.carrier)
	assert_false(scene.local.visuals.carried)
	assert_true(scene.local.state == PlayerAvatar.State.RAGDOLL or scene.local.state == PlayerAvatar.State.AWAY, "flying out")
	assert_ne(g.state, Guard.State.CARRY)
	assert_eq(scene.server.economy.balance(scene.local_id), money, "no money lost on a throw-out")
	await wait_seconds(Registry.balance.throw_out_respawn_seconds)
	assert_eq(scene.local.state, PlayerAvatar.State.STANDING)
	assert_lt(scene.local.global_position.distance_to(LuckyLounge.RESPAWN_POS), 1.5, "back at the entrance")


func test_a_ragdolling_offender_is_tossed_the_old_way() -> void:
	var g: Guard = scene.guards[0]
	var b: PlayerAvatar = scene.avatars[bot]
	b.start_ragdoll(Vector3(0, 2, 0))
	g.global_position = b.global_position
	assert_false(g.carry(b, LuckyLounge.ENTRANCE_POS), "can't pick up a flying ragdoll")
	assert_null(g.carrying)
	b.end_ragdoll()
	g.global_position = b.global_position + Vector3(10, 0, 0)
	assert_false(g.carry(b, LuckyLounge.ENTRANCE_POS), "out of reach")
	assert_eq(b.state, PlayerAvatar.State.STANDING)


func test_reactions_are_wired_to_results_and_slips() -> void:
	var b: PlayerAvatar = scene.avatars[bot]
	scene._on_event({"type": &"round_result", "player": bot, "net": 50, "station": &"blackjack_1", "details": {}})
	assert_eq(b.visuals.reaction, &"win")
	scene._on_event({"type": &"round_result", "player": bot, "net": 5000, "station": &"blackjack_1", "details": {}})
	assert_eq(b.visuals.reaction, &"big_win")
	scene._on_event({"type": &"round_result", "player": bot, "net": -50, "station": &"blackjack_1", "details": {}})
	assert_eq(b.visuals.reaction, &"loss")
	scene._on_event({"type": &"banana_slip", "victim": bot, "player": scene.local_id, "result": &"slipped", "amount": 10})
	assert_eq(b.visuals.reaction, &"slip")
	b.visuals.react(&"lose")
	assert_eq(b.visuals.reaction, &"loss", "lose is an alias")
	b.visuals.react(&"idle")
	assert_eq(b.visuals.reaction, &"", "unknown reactions reset the face")
	assert_eq(AvatarVisuals.reaction_for_net(AvatarVisuals.BIG_WIN), &"big_win")
	assert_eq(AvatarVisuals.reaction_for_net(1), &"win")
	assert_eq(AvatarVisuals.reaction_for_net(-1), &"loss")


func test_fountain_splash_is_display_only() -> void:
	assert_null(FountainSplash.spawn(scene.world_root, LuckyLounge.FOUNTAIN_POS, true), "no splash headless")
	assert_null(FountainSplash.at_fountain(scene.world_root, Vector3(50, 0, 50), false))
	assert_eq(scene.world_root.find_children("FountainSplash*", "", true, false).size(), 0)


func before_all() -> void:
	MatchScene.test_dummies = 3  # standing dummies to shove, grab and target


func after_all() -> void:
	MatchScene.test_dummies = 0
