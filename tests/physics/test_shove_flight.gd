extends GutTest
## Patrick: "Shoving sometimes flings players across the room (a test shows about 9 m instead of
## under 3 m)". A shove that knocks someone down or out launches them as a ragdoll; wherever it
## rolls, they must come to rest (and get up) within the intended shove distance of where the hit
## landed, never across the room.

var scene: MatchScene
var events: Array[Dictionary] = []
var bot: int = -1

## Open carpet between the lobby and the tables (nothing within ~3 m along -z).
const OPEN: Vector3 = Vector3(5.0, 0.0, 4.5)


func before_all() -> void:
	MatchScene.test_dummies = 2


func after_all() -> void:
	MatchScene.test_dummies = 0


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
	for i: int in range(1, others.size()):
		_place(others[i], Vector3(-8.0 + i, 0.0, 12.0))
	scene.server.timescale = 1.0
	await wait_seconds(3.3)
	for g: Guard in scene.guards:
		g.process_mode = Node.PROCESS_MODE_DISABLED
		g.global_position = Vector3(-18.0, 0.0, -12.0)
	if scene.casino_floor != null and scene.casino_floor.waiter != null:
		scene.casino_floor.waiter.process_mode = Node.PROCESS_MODE_DISABLED
		scene.casino_floor.waiter.global_position = Vector3(-18.0, 0.0, 12.0)


func after_each() -> void:
	if Net.event_received.is_connected(_collect):
		Net.event_received.disconnect(_collect)


func _collect(ev: Dictionary) -> void:
	events.append(ev)


func _of(type: StringName) -> Array[Dictionary]:
	return events.filter(func(e: Dictionary) -> bool: return e["type"] == type)


func _place(pid: int, pos: Vector3, yaw: float = 0.0) -> void:
	scene.avatars[pid].teleport(pos, yaw)
	scene.server.set_server_position(pid, pos)


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


## Steps up 1.3 m behind the dummy (facing -z) and shoves once the cooldown allows it.
func _chase_and_shove() -> void:
	var st: InteractionRules.Status = scene.server.interactions.rules.status(scene.local_id)
	while scene.server.match_time - st.last_shove_given < Registry.balance.shove_cooldown + 0.01:
		await wait_physics_frames(1)
	await wait_seconds(0.15)  # the client's own swing gate
	var bp: Vector3 = scene.avatars[bot].global_position
	_place(scene.local_id, Vector3(bp.x, 0.0, bp.z + 1.3), 0.0)
	await wait_physics_frames(1)
	scene.router.shove.emit()


## Follows the dummy until it is back on its feet; returns the farthest it got from `from`.
func _farthest_until_up(from: Vector3, seconds: float) -> float:
	var b: PlayerAvatar = scene.avatars[bot]
	var far: float = 0.0
	var t: float = 0.0
	var trace: Array[String] = []
	while t < seconds:
		await wait_physics_frames(1)
		t += get_physics_process_delta_time()
		var at: Vector3 = b.ragdoll.body_position() if b.ragdoll != null else b.global_position
		far = maxf(far, _flat(at - from).length())
	return far


func test_knockdown_shove_does_not_fling_across_the_room() -> void:
	_place(scene.local_id, OPEN, 0.0)
	_place(bot, OPEN + Vector3(0.0, 0.0, -1.5), PI)
	await wait_physics_frames(2)
	scene.router.shove.emit()
	await _chase_and_shove()
	assert_eq(_of(&"player_knocked_down").size(), 1, "second shove inside the window knocks down")
	var from: Vector3 = scene.avatars[bot].global_position
	var far: float = await _farthest_until_up(from, Registry.balance.knockdown_time + 2.5)
	assert_eq(scene.avatars[bot].state, PlayerAvatar.State.STANDING, "back up")
	assert_gt(far, 0.8, "the knockdown still sends them flying a bit (%.2f m)" % far)
	assert_lt(far, 3.0, "but never across the room (%.2f m)" % far)


func test_knockout_shove_does_not_fling_across_the_room() -> void:
	_place(scene.local_id, OPEN, 0.0)
	_place(bot, OPEN + Vector3(0.0, 0.0, -1.5), PI)
	await wait_physics_frames(2)
	scene.router.shove.emit()
	await _chase_and_shove()
	await wait_seconds(Registry.balance.knockdown_time + 1.0)  # up again (still in the knockout window)
	var from: Vector3 = Vector3.ZERO
	for i: int in 3:
		if not _of(&"player_knocked_out").is_empty():
			break
		from = scene.avatars[bot].global_position
		await _chase_and_shove()
	assert_eq(_of(&"player_knocked_out").size(), 1, "knocked out")
	var far: float = await _farthest_until_up(from, Registry.balance.knockout_time + 2.5)
	assert_lt(far, 3.0, "a knockout drops them nearby (%.2f m)" % far)



## The 9 m flights: a body the host simulates chased the client mirror's copy of its position,
## refreshed only every quarter second, at ten times the distance per second. Right after a body
## was moved (a respawn, the regroup, a test putting it somewhere) that copy is still the old spot,
## so a shove there slid it 1.7 m and then yanked it metres back across the floor.
func test_a_body_shoved_right_after_it_was_moved_stays_where_the_shove_sends_it() -> void:
	var old_spot: Vector3 = OPEN + Vector3(-3.9, 0.0, 0.0)
	_place(bot, old_spot, PI)
	_place(scene.local_id, OPEN + Vector3(0.0, 0.0, 6.0), 0.0)
	await wait_seconds(0.6)  # the mirror has caught up with the old spot
	var spot: Vector3 = OPEN + Vector3(0.0, 0.0, -1.5)
	_place(scene.local_id, OPEN, 0.0)
	_place(bot, spot, PI)
	await wait_physics_frames(2)
	scene.router.shove.emit()
	assert_eq(_of(&"player_shoved").size(), 1, "the shove landed")
	var b: PlayerAvatar = scene.avatars[bot]
	var far: float = 0.0
	var t: float = 0.0
	while t < 1.5:
		await wait_physics_frames(1)
		t += get_physics_process_delta_time()
		var at: Vector3 = b.ragdoll.body_position() if b.ragdoll != null else b.global_position
		far = maxf(far, _flat(at - spot).length())
	assert_lt(far, 3.0, "never flung across the room (%.2f m from where it was hit)" % far)
	assert_gt(spot.z - b.global_position.z, 1.0, "slid back along the push (%s)" % b.global_position)
	assert_lt(absf(b.global_position.x - spot.x), 0.3, "not dragged back sideways to the old spot")
	assert_lt(scene.server.world.get_position(bot).distance_to(b.global_position), 0.3, "and the server agrees")
