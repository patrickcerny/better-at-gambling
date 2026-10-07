extends GutTest
## Minigame transitions in the real match scene (Patrick's notes #9, #10, #21): a seated player
## with a spin going is stood up and refunded when the minigame starts, and after the rewards
## everyone stands in the entrance hall behind shut doors until the regroup countdown is over.

var scene: MatchScene
var events: Array[Dictionary] = []


func before_each() -> void:
	events.clear()
	Net.stop()
	MatchScene.test_dummies = 1
	scene = (load("res://match/match_scene.tscn") as PackedScene).instantiate()
	add_child_autofree(scene)
	Net.event_received.connect(_collect)
	await wait_seconds(3.3)


func after_each() -> void:
	MatchScene.test_dummies = 0
	if Net.event_received.is_connected(_collect):
		Net.event_received.disconnect(_collect)


func _collect(ev: Dictionary) -> void:
	events.append(ev)


## Runs server game time without waiting for real time (like `--skip-to`).
func _skip_until(cond: Callable, max_seconds: float = 900.0) -> bool:
	var t: float = 0.0
	while not cond.call() and t < max_seconds:
		scene.server.advance(MatchServer.TICK)
		t += MatchServer.TICK
	return cond.call()


func test_minigame_stands_up_and_refunds_then_everyone_regroups_in_the_hall() -> void:
	assert_eq(scene.server.phases.phase, Phase.Id.CASINO)
	var me: int = scene.local_id
	var st: StationBase = scene.map.stations[&"slot_1"]
	var near: Vector3 = st.global_position + (scene.map.spawn_points()[0] - st.global_position).normalized() * 1.2
	near.y = st.global_position.y
	scene.local.teleport(near, 0.0)
	scene.server.set_server_position(me, near)
	assert_true(Net.send_intent(Intents.make(&"sit", {"station": &"slot_1"}))["ok"])
	await wait_physics_frames(2)
	assert_eq(scene.local.state, PlayerAvatar.State.SEATED)
	var t_due: float = scene.server.schedule.minigame_times()[0] - 0.5
	assert_true(_skip_until(func() -> bool: return scene.server.phases.casino_time >= t_due - 9.0))
	var money: int = scene.server.economy.balance(me)
	var bet: int = (scene.server.stations.logics[&"slot_1"] as SlotsLogic).bet_sizes()[0]
	# Long spin: the reels can't stop on their own before the minigame starts.
	(scene.server.stations.logics[&"slot_1"] as SlotsLogic).balance = scene.server.balance.duplicate() as BalanceConfig
	(scene.server.stations.logics[&"slot_1"] as SlotsLogic).balance.slots_spin_time = 60.0
	scene.server.stations.closing_in = INF
	assert_true(scene.server.stations.route(me, Intents.make(&"place_bet", {"station": &"slot_1", "bet": {"amount": bet}}))["ok"])
	assert_true(_skip_until(func() -> bool: return scene.server.phases.phase == Phase.Id.MINIGAME))
	await wait_physics_frames(2)
	assert_eq(scene.server.economy.balance(me), money, "the spin was refunded")
	assert_ne(scene.local.state, PlayerAvatar.State.SEATED, "stood up for the minigame")
	assert_true(events.any(func(e: Dictionary) -> bool: return e["type"] == &"bets_refunded" and int(e["player"]) == me))
	# Through the minigame and the round results into the regroup.
	scene.local.teleport(Vector3(4, 0, -6), 0.0)
	scene.server.set_server_position(me, Vector3(4, 0, -6))
	assert_true(_skip_until(func() -> bool: return scene.server.phases.phase == Phase.Id.REGROUP))
	await wait_physics_frames(3)
	assert_false(scene.map.lobby_open, "the hall doors are shut")
	for pid: int in scene.avatars:
		var spot: Vector3 = scene.map.lobby_spawn(pid)
		var a: PlayerAvatar = scene.avatars[pid]
		assert_lt(Vector2(a.global_position.x - spot.x, a.global_position.z - spot.z).length(), 0.6, "player %d stands in the hall" % pid)
		assert_lt(scene.server.world.get_position(pid).distance_to(spot), 0.01, "the server agrees")
	assert_true(scene.stage == null, "the minigame stage is closed")
	assert_false(scene.reward_panel.visible)
	assert_true(scene.hud.visible)
	# The doors open when the countdown is over.
	await wait_seconds(Registry.balance.regroup_time + 0.4)
	assert_eq(scene.server.phases.phase, Phase.Id.CASINO)
	assert_true(scene.map.lobby_open, "the doors open on CASINO")
	assert_eq(Log.error_count, 0)
