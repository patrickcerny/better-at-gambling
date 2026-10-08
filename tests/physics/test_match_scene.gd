extends GutTest
## Physics/world integration (M2 acceptance): the real match scene with an in-process server and
## standing test dummies. Everything goes through intents and server events; the scene reports world outcomes.

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
	# Skip the intro so intents are accepted.
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


## Puts the local player at `pos` looking along `yaw` with the dummy standing `dist` metres ahead.
var _spot: Array = []


func _face_off(pos: Vector3, dist: float = 1.5, yaw: float = 0.0) -> void:
	_spot = [pos, dist, yaw]
	scene.local.teleport(pos, yaw)
	var bpos: Vector3 = pos + Vector3(-sin(yaw), 0.0, -cos(yaw)) * dist
	scene.avatars[bot].teleport(bpos, yaw + PI)
	scene.server.set_server_position(bot, bpos)
	scene.server.set_server_position(scene.local_id, pos)


## Waits until the server's shove cooldown is over (its clock steps at 20 Hz, so a fixed real-time
## wait can land a hair early and get the shove refused).
func _cooldown_over() -> void:
	var st: InteractionRules.Status = scene.server.rules.status(scene.local_id)
	while scene.server.match_time - st.last_shove_given < Registry.balance.shove_cooldown + 0.01:
		await wait_physics_frames(1)


## Shoves the dummy, first closing in on it like a player would (a shove slides it ~1.7 m away).
func _shove() -> Dictionary:
	_close_in()
	return Net.send_intent(Intents.make(&"shove", {"aim": Serializer.vec3(scene.local.facing())}))


## Shoves from the last face-off spot with the dummy put back in front (guard tests need the fight
## to stay where the guards can or can't see it).
func _shove_here() -> Dictionary:
	_face_off(_spot[0], _spot[1], _spot[2])
	return Net.send_intent(Intents.make(&"shove", {"aim": Serializer.vec3(scene.local.facing())}))


func _close_in(dist: float = 1.4) -> void:
	var bp: Vector3 = scene.server.world.get_position(bot)
	var me: Vector3 = scene.local.global_position
	var away: Vector3 = Vector3(me.x - bp.x, 0.0, me.z - bp.z)
	if away.length() <= dist + 0.3:
		return
	var pos: Vector3 = Vector3(bp.x, me.y, bp.z) + away.normalized() * dist
	scene.local.teleport(pos, atan2(away.x, away.z))
	scene.server.set_server_position(scene.local_id, pos)


func test_three_shoves_knock_out_then_get_up() -> void:
	_face_off(Vector3(0, 0, 5))
	await wait_seconds(0.2)
	for i: int in 3:
		await _cooldown_over()
		var res: Dictionary = _shove()
		assert_true(res["ok"], "shove %d accepted: %s" % [i + 1, res])
		await wait_seconds(1.3)
	assert_eq(_of(&"player_shoved").size(), 3)
	assert_eq(_of(&"player_knocked_out").size(), 1, "third shove inside the window knocks out")
	var b: PlayerAvatar = scene.avatars[bot]
	assert_eq(b.state, PlayerAvatar.State.RAGDOLL, "the dummy ragdolls")
	assert_true(b.visuals.stars.visible, "dizzy stars")
	await wait_seconds(Registry.balance.knockout_time + 1.0)
	assert_eq(b.state, PlayerAvatar.State.STANDING, "gets back up after the knockout time")
	assert_false(b.visuals.stars.visible)
	assert_almost_eq(scene.server.world.get_position(bot).x, b.global_position.x, 0.01, "server learns where it got up")


func test_shake_drops_exactly_the_capped_amount_as_piles_and_pickup_pays_it() -> void:
	_face_off(Vector3(-4, 0, 5))
	await wait_seconds(0.2)
	for i: int in 3:
		await _cooldown_over()
		_shove()
		await wait_seconds(1.3)
	assert_eq(_of(&"player_knocked_out").size(), 1)
	var before: int = scene.server.economy.balance(bot)
	var mine_before: int = scene.server.economy.balance(scene.local_id)
	# The knockout launched the ragdoll (the server tracks where it lies); walk up to it.
	var lie: Vector3 = scene.server.world.get_position(bot)
	scene.local.teleport(Vector3(lie.x, 0.0, lie.z + 1.0), 0.0)
	scene.server.set_server_position(scene.local_id, scene.local.global_position)
	await wait_physics_frames(2)
	var shaken: int = 0
	for i: int in 3:
		var res: Dictionary = Net.send_intent(Intents.make(&"shake"))
		assert_true(res["ok"], "shake %d: %s" % [i + 1, res])
		await wait_seconds(0.3)
	for ev: Dictionary in _of(&"chips_shaken_out"):
		shaken += int(ev["amount"])
	var dropped: int = 0
	for ev: Dictionary in _of(&"chips_dropped"):
		dropped += int(ev["amount"])
	assert_gt(shaken, 0, "money came out")
	assert_eq(dropped, shaken, "chip piles sum exactly to what was shaken out")
	assert_eq(scene.server.economy.balance(bot), before - shaken, "victim lost exactly that")
	# Piles that landed within reach were picked up on the spot; walk over the rest.
	var remaining: int = scene.piles.size()
	assert_eq(remaining + _of(&"chips_collected").size(), _of(&"chips_dropped").size(), "every drop is a pile or already collected")
	# A pile can still be sliding when we land on it: walk over what is left a few times.
	for attempt: int in 4:
		for pid: int in scene.piles.keys():
			if not scene.piles.has(pid):
				continue
			scene.local.teleport(scene.piles[pid].global_position)
			await wait_physics_frames(3)
		await wait_physics_frames(3)
		if scene.piles.is_empty():
			break
	assert_eq(scene.piles.size(), 0, "all piles collected")
	assert_eq(scene.server.economy.balance(scene.local_id), mine_before + shaken, "pickups paid the full amount")
	assert_eq(scene.view.state.balance(scene.local_id), scene.server.economy.balance(scene.local_id), "HUD mirror matches the server")


func test_seated_player_is_immune() -> void:
	var sid: StringName = &"blackjack_1"
	var spos: Vector3 = scene.map.stations[sid].global_position
	scene.server.set_server_position(bot, spos + Vector3(0, 0, 2.0))
	var res: Dictionary = scene.server.submit_intent(bot, Intents.make(&"sit", {"station": sid}))
	assert_true(res["ok"], "dummy sits: %s" % res)
	await wait_physics_frames(2)
	var b: PlayerAvatar = scene.avatars[bot]
	assert_eq(b.state, PlayerAvatar.State.SEATED)
	scene.local.teleport(b.global_position + Vector3(0, 0, 1.2), 0.0)
	scene.server.set_server_position(scene.local_id, scene.local.global_position)
	await wait_physics_frames(2)
	var shove: Dictionary = _shove()
	assert_false(shove["ok"])
	assert_eq(shove["error"], &"seated")
	var grab: Dictionary = Net.send_intent(Intents.make(&"grab", {"target": bot}))
	assert_eq(grab["error"], &"seated")


func test_grab_throw_ragdolls_and_fountain_knocks_out_and_soaks() -> void:
	var fountain: Vector3 = LuckyLounge.FOUNTAIN_POS
	_face_off(fountain + Vector3(0, 0, 4.4), 1.6)
	await wait_seconds(0.2)
	var grab: Dictionary = Net.send_intent(Intents.make(&"grab", {"target": bot}))
	assert_true(grab["ok"], "grab: %s" % grab)
	await wait_physics_frames(2)
	var b: PlayerAvatar = scene.avatars[bot]
	assert_eq(b.state, PlayerAvatar.State.HELD)
	var rel: Dictionary = Net.send_intent(Intents.make(&"release", {"throw": true, "aim": [0, 0, -1]}))
	assert_true(rel["ok"])
	await wait_physics_frames(2)
	assert_eq(_of(&"player_thrown").size(), 1)
	assert_eq(b.state, PlayerAvatar.State.RAGDOLL, "thrown players ragdoll")
	# Whatever the arc did, dunk the ragdoll in the water: the hazard must knock out and soak.
	b.ragdoll.torso.global_position = fountain + Vector3(0.9, 1.1, 0.0)
	b.ragdoll.torso.linear_velocity = Vector3.ZERO
	await wait_physics_frames(4)
	var kos: Array[Dictionary] = _of(&"player_knocked_out")
	assert_eq(kos.size(), 1, "fountain knockout reported once")
	if not kos.is_empty():
		assert_eq(kos[0]["cause"], &"fountain")
		assert_eq(int(kos[0]["attacker"]), scene.local_id, "credited to the thrower")
	assert_true(b.is_soaked(), "soaked after the dunk")


func test_walking_into_the_fountain_slows_the_player() -> void:
	scene.local.teleport(LuckyLounge.FOUNTAIN_POS + Vector3(0, 0.75, 0))
	await wait_physics_frames(3)
	assert_true(scene.local.is_soaked(), "soaked in the water")
	scene.local.teleport(Vector3(0, 0, 14))
	await wait_physics_frames(2)
	assert_true(scene.local.is_soaked(), "stays soaked for a while after leaving")
	await wait_seconds(Registry.balance.soaked_seconds + 0.2)
	assert_false(scene.local.is_soaked(), "dries off")


func test_guard_chases_an_attacker_in_sight_but_not_behind_a_wall() -> void:
	var g: Guard = scene.guards[0]
	# Park guard 1 north of the fight looking +z over open carpet (on its patrol corridor).
	g.route = [Vector3(-12, 0, -6)]
	g.global_position = Vector3(-12, 0, -6)
	g.yaw = PI
	g.state = Guard.State.PATROL
	# Guard 2 east of the fight looking −x, with the lobby pillar in between.
	var g2: Guard = scene.guards[1]
	g2.route = [Vector3(-8, 0, -1)]
	g2.global_position = Vector3(-8, 0, -1)
	g2.yaw = PI * 0.5  # forward = −x
	g2.state = Guard.State.PATROL
	_face_off(Vector3(-12, 0, -1), 1.5, PI)  # we look +z at the dummy; the pillar at (−11, −1) is just east
	assert_true(scene.map.has_line_of_sight(g.global_position, scene.local.global_position), "guard 1 sees the spot")
	assert_false(scene.map.has_line_of_sight(g2.global_position, scene.local.global_position), "pillar blocks guard 2")
	assert_true(scene.server.rules.guard_sees(g2.global_position, g2.forward(), scene.local.global_position, true), "guard 2 would see it if not for the pillar")
	await wait_seconds(0.2)
	for i: int in 2:
		await _cooldown_over()
		_shove_here()
		await wait_seconds(1.3)
	await _cooldown_over()
	_shove_here()
	await wait_seconds(0.25)  # the knockout lands with the swing
	assert_eq(_of(&"player_knocked_out").size(), 1)
	assert_eq(g.state, Guard.State.CHASE, "offence in the sight cone starts a chase")
	assert_eq(g.target_id, scene.local_id)
	assert_eq(g2.state, Guard.State.PATROL, "no line of sight, no chase")
	await wait_seconds(2.0)
	assert_eq(_of(&"player_thrown_out").size(), 1, "and the chase ends with a throw-out")
	assert_eq(g2.state, Guard.State.PATROL, "guard 2 never saw a thing")


func test_guard_catching_throws_out_and_respawns_at_the_door() -> void:
	var g: Guard = scene.guards[0]
	g.route = [Vector3(-12, 0, -6)]
	g.global_position = Vector3(-12, 0, -6)
	g.yaw = PI
	g.state = Guard.State.PATROL
	_face_off(Vector3(-12, 0, -1), 1.5, PI)
	await wait_seconds(0.2)
	for i: int in 3:
		await _cooldown_over()
		_shove_here()
		await wait_seconds(1.3)
	var money: int = scene.server.economy.balance(scene.local_id)
	await wait_seconds(3.0)
	assert_eq(_of(&"player_thrown_out").size(), 1, "guard reached the attacker and threw them out")
	assert_eq(scene.server.economy.balance(scene.local_id), money, "no money lost on a throw-out")
	await wait_seconds(Registry.balance.throw_out_respawn_seconds + 2.5)
	assert_eq(scene.local.state, PlayerAvatar.State.STANDING)
	assert_lt(scene.local.global_position.distance_to(LuckyLounge.RESPAWN_POS), 1.5, "back at the entrance")


func test_sit_bet_and_leave_mid_round_through_the_scene() -> void:
	var sid: StringName = &"blackjack_2"
	var st: StationBase = scene.map.stations[sid]
	scene.local.teleport(st.global_position + Vector3(0, 0, 2.4), 0.0)
	await wait_physics_frames(3)
	assert_eq(scene.nearest_station, st, "prompt targets the table we stand at")
	scene._on_interact()
	await wait_physics_frames(2)
	assert_eq(scene.local.state, PlayerAvatar.State.SEATED)
	assert_not_null(scene.current_ui)
	assert_true(scene.current_ui.visible, "blackjack overlay opens")
	var before: int = scene.server.economy.balance(scene.local_id)
	var bet: Dictionary = Net.send_intent(Intents.make(&"place_bet", {"station": sid, "bet": {"amount": 50}}))
	assert_true(bet["ok"], "bet: %s" % bet)
	await wait_seconds(Registry.balance.bj_betting_window + 0.5)  # cards are dealt, we're acting
	if int(scene.view.state.stations[sid]["state"]) == BlackjackLogic.State.PAYOUT:
		# A natural blackjack on either side (random seed) ends the round before we can leave mid-hand.
		assert_eq(_of(&"round_result").size(), 1, "the natural settled the hand")
		return
	assert_eq(int(scene.view.state.stations[sid]["state"]), BlackjackLogic.State.ACTING, "mid-round")
	var leave: Dictionary = Net.send_intent(Intents.make(&"leave"))
	assert_true(leave["ok"])
	await wait_physics_frames(2)
	assert_eq(scene.local.state, PlayerAvatar.State.STANDING)
	assert_null(scene.current_ui, "overlay closed")
	assert_eq(_of(&"round_result").size(), 1, "leaving mid-round auto-resolved the hand")
	var after: int = scene.server.economy.balance(scene.local_id)
	assert_true(after == before - 50 or after >= before, "stake lost or paid back: %d -> %d" % [before, after])
	assert_eq(scene.view.state.balance(scene.local_id), after, "HUD mirror in sync")


func before_all() -> void:
	MatchScene.test_dummies = 3  # standing dummies to shove, grab and target


func after_all() -> void:
	MatchScene.test_dummies = 0
