extends GutTest
## Hitting and chip pickups in the real match scene (Patrick: "the hitting players and picking up
## the chips is weird", "pushing around doesn't work very well yet, you can't cause trouble"):
## a shove slides the target a readable distance and the server follows it, a quick second shove
## or a slam into a table knocks them down into a ragdoll that gets back up, the client's reach
## cone picks what the server picks, chips land on the floor and are collected within the pickup
## radius (not before they land), money credit stays exact, a predicted pickup rolls back, and
## items (not hands) knock people off their seats.

var scene: MatchScene
var events: Array[Dictionary] = []
var bot: int = -1
var bot2: int = -1

## Open carpet between the lobby and the tables (nothing within ~3 m along -z).
const OPEN: Vector3 = Vector3(5.0, 0.0, 4.5)


func before_each() -> void:
	events.clear()
	Net.stop()
	scene = (load("res://match/match_scene.tscn") as PackedScene).instantiate()
	add_child_autofree(scene)
	Net.event_received.connect(_collect)
	var others: Array[int] = []
	for pid: int in scene.avatars:
		if pid != scene.local_id:
			others.append(pid)
	bot = others[0]
	bot2 = others[1]
	for i: int in range(2, others.size()):  # spare dummies wait at the far end of the lobby
		scene.avatars[others[i]].teleport(Vector3(-8.0 + i, 0.0, 12.0))
		scene.server.set_server_position(others[i], Vector3(-8.0 + i, 0.0, 12.0))
	scene.server.timescale = 1.0
	await wait_seconds(3.3)
	assert_eq(scene.server.phases.phase, Phase.Id.CASINO, "casino phase after the intro")
	# Security and the waiter sit these out (their own tests cover them).
	for g: Guard in scene.guards:
		g.process_mode = Node.PROCESS_MODE_DISABLED
		g.global_position = Vector3(-18.0, 0.0, -12.0)
	if scene.casino_floor != null and scene.casino_floor.waiter != null:
		scene.casino_floor.waiter.process_mode = Node.PROCESS_MODE_DISABLED
		scene.casino_floor.waiter.global_position = Vector3(-18.0, 0.0, 12.0)


func after_each() -> void:
	if Net.event_received.is_connected(_collect):
		Net.event_received.disconnect(_collect)


func before_all() -> void:
	MatchScene.test_dummies = 3


func after_all() -> void:
	MatchScene.test_dummies = 0


func _collect(ev: Dictionary) -> void:
	events.append(ev)


func _of(type: StringName) -> Array[Dictionary]:
	return events.filter(func(e: Dictionary) -> bool: return e["type"] == type)


func _place(pid: int, pos: Vector3, yaw: float = 0.0) -> void:
	scene.avatars[pid].teleport(pos, yaw)
	scene.server.set_server_position(pid, pos)


## Local player at `pos` facing -z (yaw 0), the dummy `dist` m ahead facing us.
func _face_off(pos: Vector3, dist: float = 1.5) -> void:
	_place(scene.local_id, pos, 0.0)
	_place(bot, pos + Vector3(0.0, 0.0, -dist), PI)
	_place(bot2, Vector3(-6.0, 0.0, 9.0))


## The real button: the router's shove signal (prediction, reach target, intent).
func _press_shove() -> void:
	scene.router.shove.emit()


func test_shove_slides_the_target_a_readable_distance_and_the_server_follows() -> void:
	_face_off(OPEN)
	await wait_physics_frames(2)
	var start: Vector3 = scene.avatars[bot].global_position
	_press_shove()
	assert_eq(_of(&"player_shoved").size(), 1, "the press reached the server")
	assert_eq(int(_of(&"player_shoved")[0]["target"]), bot)
	await wait_seconds(1.2)
	var b: PlayerAvatar = scene.avatars[bot]
	var moved: float = start.z - b.global_position.z
	assert_gt(moved, 1.2, "pushed back a readable distance (%.2f m)" % moved)
	assert_lt(moved, 3.0, "but not across the room")
	assert_almost_eq(absf(b.global_position.x - start.x), 0.0, 0.2, "straight along the push")
	assert_eq(b.state, PlayerAvatar.State.STANDING, "a single shove only staggers")
	assert_lt(scene.server.world.get_position(bot).distance_to(b.global_position), 0.2, "the server knows where the shove left them (no rubber band)")
	await wait_seconds(0.5)
	assert_lt(start.z - b.global_position.z, moved + 0.3, "and they stay there")


func test_press_on_cooldown_does_not_swing_or_send() -> void:
	_face_off(OPEN)
	await wait_physics_frames(2)
	_press_shove()
	_press_shove()
	assert_eq(_of(&"player_shoved").size(), 1)
	assert_eq(_of(&"intent_rejected").size(), 0, "the client gate keeps cooldown presses off the wire")


func test_quick_second_shove_knocks_down_into_a_ragdoll_that_gets_up() -> void:
	_face_off(OPEN)
	await wait_physics_frames(2)
	_press_shove()
	await wait_seconds(Registry.balance.shove_cooldown + 0.15)
	# Chase: step up to them and shove again inside the knockdown window.
	var bp: Vector3 = scene.avatars[bot].global_position
	_place(scene.local_id, Vector3(bp.x, 0.0, bp.z + 1.3), 0.0)
	await wait_physics_frames(1)
	_press_shove()
	assert_eq(_of(&"player_shoved").size(), 2)
	assert_eq(_of(&"player_knocked_down").size(), 1, "second shove inside the window knocks down")
	await wait_seconds(0.3)
	var b: PlayerAvatar = scene.avatars[bot]
	assert_eq(b.state, PlayerAvatar.State.RAGDOLL, "down they go, as a ragdoll")
	assert_true(scene.server.is_server_owned(bot), "the host simulates the body while it's down")
	await wait_seconds(Registry.balance.knockdown_time + 0.5)
	assert_eq(b.state, PlayerAvatar.State.STANDING, "back up when the knockdown ends")
	assert_false(scene.server.is_server_owned(bot))
	assert_eq(_of(&"player_got_up").size(), 1)
	assert_lt(scene.server.world.get_position(bot).distance_to(b.global_position), 0.3)


func test_shove_into_a_table_knocks_down() -> void:
	var st: StationBase = scene.map.stations[&"blackjack_1"]
	var table: Vector3 = Vector3(st.global_position.x, 0.0, st.global_position.z)
	# Find a side of the table with open floor: dummy 1.9 m from its centre, us further out.
	var placed: bool = false
	for i: int in 8:
		var out: Vector3 = Vector3(sin(i * TAU / 8.0), 0.0, cos(i * TAU / 8.0))
		var bpos: Vector3 = table + out * 1.9
		var me: Vector3 = table + out * 3.3
		if scene._obstacle_between(bpos, bpos - out * InteractionResolver.SLAM_DISTANCE) and not scene._obstacle_between(me, bpos):
			_place(scene.local_id, me, atan2(out.x, out.z))
			_place(bot, bpos, atan2(-out.x, -out.z))
			placed = true
			break
	assert_true(placed, "found a spot next to the table")
	_place(bot2, Vector3(-6.0, 0.0, 9.0))
	await wait_physics_frames(2)
	_press_shove()
	var downs: Array[Dictionary] = _of(&"player_knocked_down")
	assert_eq(downs.size(), 1, "slammed into the table: down on the first shove")
	if not downs.is_empty():
		assert_eq(downs[0]["cause"], &"wall")
	await wait_seconds(0.3)
	assert_eq(scene.avatars[bot].state, PlayerAvatar.State.RAGDOLL)


func test_client_reach_cone_matches_the_server() -> void:
	var cases: Array = [
		[Vector3(0, 0, -2.0), true, "2 m straight ahead"],
		[Vector3(0, 0, -2.5), false, "2.5 m: out of reach"],
		[Vector3(1.0, 0, -1.4), true, "35° off-centre"],
		[Vector3(1.6, 0, 0.0), false, "90° to the side"],
		[Vector3(0.9, 0, 0.1), true, "touching, slightly behind the shoulder"],
		[Vector3(0, 0, 1.2), false, "behind us"],
	]
	for c: Array in cases:
		_place(scene.local_id, OPEN, 0.0)
		_place(bot, OPEN + Vector3(c[0]), PI)
		_place(bot2, Vector3(-6.0, 0.0, 9.0))
		await wait_seconds(0.4)  # the dummies follow the server's (mirrored) position
		var client: int = scene._reach_target(false)
		var server: int = scene.server.interactions._shove_target(scene.local_id, scene.local.facing(), -1, scene.server.match_time)
		assert_eq(client == bot, bool(c[1]), "client: %s (picked %d, bot %d, state %d, away %s)" % [c[2], client, bot, scene.avatars[bot].state, scene.avatars[bot].connection_away])
		assert_eq(server, client, "server agrees: %s" % c[2])


func test_chips_land_on_the_floor_and_are_picked_up_within_the_radius_with_exact_money() -> void:
	_place(scene.local_id, OPEN, 0.0)
	_place(bot, Vector3(-6.0, 0.0, 6.0))
	_place(bot2, Vector3(-6.0, 0.0, 9.0))
	var before: int = scene.server.economy.balance(scene.local_id)
	# A pile dropped at torso height (where a ragdoll was) lands on the carpet.
	var spot: Vector3 = OPEN + Vector3(0.0, 1.0, -(MatchScene.PICKUP_RADIUS + 0.4))
	var ids: Array[int] = scene.server.pickups.spawn(137, spot, 1, SeededRng.new(3), scene.server.match_time, 0.01)
	await wait_physics_frames(1)
	var pile: CoinPile = scene.piles.get(ids[0], null)
	assert_not_null(pile, "the pile is in the world")
	assert_almost_eq(pile.global_position.y, 0.0, 0.05, "on the floor, not floating where it was dropped")
	var at: Vector3 = Vector3(pile.global_position.x, 0.0, pile.global_position.z)
	_place(scene.local_id, at + Vector3(0.0, 0.0, MatchScene.PICKUP_RADIUS + 0.4), 0.0)
	await wait_physics_frames(5)
	assert_true(scene.piles.has(ids[0]), "%.2f m away: out of the pickup radius" % (MatchScene.PICKUP_RADIUS + 0.4))
	_place(scene.local_id, at + Vector3(0.0, 0.0, 1.0), 0.0)
	await wait_physics_frames(3)
	assert_false(scene.piles.has(ids[0]), "inside the radius: collected without standing on it")
	assert_eq(scene.server.economy.balance(scene.local_id), before + 137, "exactly the pile's amount")
	assert_eq(scene.view.state.balance(scene.local_id), before + 137, "HUD mirror agrees")
	assert_eq(_of(&"chips_collected").size(), 1)


func test_shaken_chips_cannot_be_grabbed_mid_air() -> void:
	_place(scene.local_id, OPEN, 0.0)
	_place(bot, OPEN + Vector3(0.0, 0.0, -0.3))
	_place(bot2, Vector3(-6.0, 0.0, 9.0))
	await wait_physics_frames(1)
	var ids: Array[int] = scene.server.pickups.drop_from(bot, 60, OPEN, 1, SeededRng.new(1), &"test", scene.server.match_time, 0.31)
	scene.server._flush()
	await wait_physics_frames(3)
	assert_true(scene.piles.has(ids[0]), "still flying out of the victim")
	await wait_seconds(CoinPile.SETTLE_SECONDS + 0.1)
	assert_false(scene.piles.has(ids[0]), "landed: now it's anyone's")


func test_predicted_pickup_rolls_back_when_the_server_does_not_confirm() -> void:
	_place(scene.local_id, OPEN, 0.0)
	_place(bot, Vector3(-6.0, 0.0, 6.0))
	_place(bot2, Vector3(-6.0, 0.0, 9.0))
	var before: int = scene.server.economy.balance(scene.local_id)
	# Act as an online client for a moment: the pickup is ours to predict, not to decide.
	scene._owns_server = false
	scene._spawn_pile(9001, 40, OPEN + Vector3(0.0, 0.0, -0.5))
	var pile: Node3D = scene.piles[9001]
	await wait_physics_frames(2)
	assert_true(pile.is_leaving(), "chips fly to us at once")
	assert_gt(pile.predicted_until, scene._clock)
	_place(scene.local_id, OPEN + Vector3(0.0, 0.0, 4.0), 0.0)
	await wait_seconds(MatchScene.PICKUP_PREDICT_TIMEOUT + 0.2)
	assert_false(pile.is_leaving(), "no confirmation: the chips drop back")
	assert_true(pile.visible)
	assert_true(scene.piles.has(9001))
	# Someone else's confirmed pickup takes it away from under a prediction.
	_place(scene.local_id, OPEN, 0.0)
	await wait_physics_frames(2)
	assert_true(pile.is_leaving())
	scene._on_chips_collected(9001, bot, 40)
	assert_false(scene.piles.has(9001), "gone to the player who really got it")
	scene._owns_server = true
	assert_eq(scene.server.economy.balance(scene.local_id), before, "money never moved on a prediction")


func test_items_knock_a_seated_dummy_off_their_seat_but_hands_do_not() -> void:
	var sid: StringName = &"blackjack_1"
	var spos: Vector3 = scene.map.stations[sid].global_position
	scene.server.set_server_position(bot, spos + Vector3(0, 0, 2.0))
	assert_true(scene.server.submit_intent(bot, Intents.make(&"sit", {"station": sid}))["ok"])
	await wait_physics_frames(2)
	var b: PlayerAvatar = scene.avatars[bot]
	assert_eq(b.state, PlayerAvatar.State.SEATED)
	_place(scene.local_id, b.global_position + Vector3(0, 0, 1.2), 0.0)
	await wait_physics_frames(2)
	assert_eq(scene._reach_target(false), -1, "hands don't pick seated players")
	assert_eq(Net.send_intent(Intents.make(&"shove", {"aim": [0, 0, -1], "target": bot}))["error"], &"seated")
	scene.server.items.give(scene.local_id, &"empty_bottle", scene.server.match_time)
	var res: Dictionary = Net.send_intent(Intents.make(&"use_item", {"slot": 0, "target": bot}))
	assert_true(res["ok"], "items do: %s" % res)
	await wait_seconds(0.3)
	assert_eq(_of(&"player_stood").size(), 1)
	assert_eq(b.state, PlayerAvatar.State.RAGDOLL, "off the stool and onto the floor")
	assert_null(b.seat)
