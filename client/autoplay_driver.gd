extends Node
## Scripted local player for `--autoplay`: walks to each station type, plays a few rounds,
## shoves/grabs/throws a bot, shakes chips, visits the fountain and the VIP gate, then idles.
## Used by the 3-minute no-errors session (M2 acceptance) and handy for screenshots.
## Every step is an intent or a walk target; nothing bypasses the server.

var scene: MatchScene
var steps: Array[Array] = []
var index: int = 0
var wait_left: float = 0.0
var elapsed: float = 0.0
var walking_to: Vector3 = Vector3.INF
var waypoints: PackedVector3Array = PackedVector3Array()
var _last_pos: Vector3 = Vector3.INF
var _stuck_time: float = 0.0
var _final_leg: bool = false


func _ready() -> void:
	scene = get_parent() as MatchScene
	await get_tree().create_timer(3.5).timeout  # intro
	if not is_inside_tree():
		return
	_build_steps()
	Net.event_received.connect(func(ev: Dictionary) -> void:
		if ev["type"] in [&"player_knocked_out", &"player_thrown_out", &"player_thrown", &"chips_shaken_out", &"jackpot_won", &"intent_rejected"]:
			Log.info(&"autoplay", "event %s" % ev))
	Log.info(&"autoplay", "starting %d steps" % steps.size())


func _build_steps() -> void:
	var sp: Dictionary = scene.map.station_positions()
	var bot: int = -1
	for pid: int in scene.avatars:
		if pid != scene.local_id:
			bot = pid
			break
	steps = [
		["walk", Vector3(sp[&"blackjack_3"]) + Vector3(0, 0, 2.6)],
		["sit", &"blackjack_3"], ["wait", 0.5],
		["intent", &"place_bet", {"station": &"blackjack_3", "bet": {"amount": 25}}], ["wait", 9.0],
		["intent", &"action", {"station": &"blackjack_3", "action": &"stand"}], ["wait", 3.0],
		["intent", &"place_bet", {"station": &"blackjack_3", "bet": {"amount": 50}}], ["wait", 9.0],
		["intent", &"action", {"station": &"blackjack_3", "action": &"hit"}], ["wait", 0.5],
		["intent", &"action", {"station": &"blackjack_3", "action": &"stand"}], ["wait", 3.5],
		["intent", &"leave", {}], ["wait", 0.5],
		["walk", Vector3(sp[&"roulette_1"]) + Vector3(1.0, 0, 2.0)],
		["sit", &"roulette_1"], ["wait", 1.0],
		["intent", &"place_bet", {"station": &"roulette_1", "bet": {"type": &"red", "value": 0, "amount": 25}}],
		["intent", &"place_bet", {"station": &"roulette_1", "bet": {"type": &"straight", "value": 17, "amount": 10}}],
		["wait", 23.0],
		["intent", &"place_bet", {"station": &"roulette_1", "bet": {"type": &"dozen", "value": 2, "amount": 25}}],
		["wait", 22.0],
		["intent", &"leave", {}], ["wait", 0.5],
		["walk", Vector3(sp[&"slot_8"]) + Vector3(0, 0, 1.2)],
		["sit", &"slot_8"], ["wait", 0.5],
		["intent", &"place_bet", {"station": &"slot_8", "bet": {"amount": 10}}], ["wait", 2.2],
		["intent", &"place_bet", {"station": &"slot_8", "bet": {"amount": 25}}], ["wait", 0.8],
		["intent", &"action", {"station": &"slot_8", "action": &"stop"}], ["wait", 1.0],
		["intent", &"place_bet", {"station": &"slot_8", "bet": {"amount": 50}}], ["wait", 2.2],
		["intent", &"leave", {}], ["wait", 0.5],
		["walk", Vector3(sp[&"plinko_1"]) + Vector3(-0.8, 0, 2.4)],
		["sit", &"plinko_1"], ["wait", 0.5],
		["intent", &"place_bet", {"station": &"plinko_1", "bet": {"amount": 25, "risk": &"medium"}}], ["wait", 3.5],
		["intent", &"place_bet", {"station": &"plinko_1", "bet": {"amount": 10, "risk": &"high"}}], ["wait", 3.5],
		["intent", &"leave", {}], ["wait", 0.5],
		["walk", LuckyLounge.SPAWNS[1] + Vector3(0, 0, -1.5)],
		["face_bot", bot], ["wait", 0.3],
		["intent", &"shove", {"aim": [0, 0, 0]}], ["wait", 1.4],
		["intent", &"shove", {"aim": [0, 0, 0]}], ["wait", 1.4],
		["intent", &"shove", {"aim": [0, 0, 0]}], ["wait", 1.0],
		["intent", &"shake", {}], ["wait", 0.7], ["intent", &"shake", {}], ["wait", 0.7], ["intent", &"shake", {}], ["wait", 4.0],
		["approach_bot", bot], ["wait", 0.5],
		["face_bot", bot], ["intent", &"grab", {"target": bot}], ["wait", 1.0],
		["intent", &"release", {"throw": true, "aim": [0, 0, -1]}], ["wait", 4.0],
		["emote", &"laugh"], ["wait", 2.0],
		["walk", LuckyLounge.FOUNTAIN_POS + Vector3(2.6, 0, 0)], ["wait", 0.5],
		["jump_to", LuckyLounge.FOUNTAIN_POS + Vector3(0.5, 0, 0)], ["wait", 6.0],
		["walk", Vector3(12.0, 0, 9.5)], ["walk", Vector3(12.0, LuckyLounge.MEZZ_Y, -1.5)], ["wait", 0.5],
		["walk", LuckyLounge.VIP_GATE_POS + Vector3(-0.8, 0, 0)], ["wait", 2.0],
		["walk", Vector3(12.0, LuckyLounge.MEZZ_Y, -1.5)],
		["walk", Vector3(-1.0, LuckyLounge.MEZZ_Y, -0.6)], ["wait", 0.5],
		["jump_to", Vector3(-1.0, LuckyLounge.MEZZ_Y, 2.0)], ["wait", 5.0],
		["walk", Vector3(sp[&"blackjack_2"]) + Vector3(0, 0, 2.6)],
		["sit", &"blackjack_2"], ["wait", 0.5],
		["intent", &"place_bet", {"station": &"blackjack_2", "bet": {"amount": 100}}], ["wait", 9.0],
		["intent", &"action", {"station": &"blackjack_2", "action": &"double"}], ["wait", 4.0],
		["intent", &"leave", {}],
		["done", null],
	]


func _process(delta: float) -> void:
	elapsed += delta
	if steps.is_empty() or scene.local == null:
		return
	if walking_to != Vector3.INF:
		var flat: float = Vector3(walking_to.x - scene.local.global_position.x, 0, walking_to.z - scene.local.global_position.z).length()
		if not scene.local.is_standing():
			Log.info(&"autoplay", "walk interrupted (state %d) at %s" % [scene.local.state, scene.local.global_position])
			walking_to = Vector3.INF
			scene.local.auto_target = Vector3.INF
			wait_left = 0.5
		elif flat < 0.5:
			Log.info(&"autoplay", "arrived at %s" % scene.local.global_position)
			walking_to = Vector3.INF
			scene.local.auto_target = Vector3.INF
			wait_left = 0.2
		elif scene.local.auto_target == Vector3.INF:
			if waypoints.is_empty():
				# The navmesh keeps half a metre from furniture; close the last bit on foot.
				if flat < 2.0 and not _final_leg:
					_final_leg = true
					scene.local.auto_target = walking_to
				else:
					Log.info(&"autoplay", "ran out of waypoints at %s (%.1f m short)" % [scene.local.global_position, flat])
					walking_to = Vector3.INF
					wait_left = 0.2
			else:
				scene.local.auto_target = waypoints[0]
				waypoints.remove_at(0)
		elif wait_left > 20.0:
			Log.warn(&"autoplay", "walk timed out at %s" % scene.local.global_position)
			walking_to = Vector3.INF
			scene.local.auto_target = Vector3.INF
		else:
			wait_left += delta
			# Caught on a corner (moved < 0.1 m in half a second): hop sideways and try again.
			_stuck_time += delta
			if _stuck_time >= 0.5:
				_stuck_time = 0.0
				if _last_pos != Vector3.INF and scene.local.global_position.distance_to(_last_pos) < 0.1:
					var side: Vector3 = scene.local.facing().cross(Vector3.UP) * (1.0 if randf() < 0.5 else -1.0)
					scene.local.hop(side * 3.0 + Vector3.UP * 4.0)
					Log.info(&"autoplay", "stuck at %s, nudging" % scene.local.global_position)
				_last_pos = scene.local.global_position
		return
	if wait_left > 0.0:
		wait_left -= delta
		return
	if index >= steps.size():
		return
	var step: Array = steps[index]
	index += 1
	match step[0]:
		"walk":
			if scene.local.state == PlayerAvatar.State.RAGDOLL or scene.local.state == PlayerAvatar.State.AWAY:
				wait_left = 1.0
				index -= 1
				return
			walking_to = step[1]
			_final_leg = false
			waypoints = NavigationServer3D.map_get_path(scene.get_world_3d().navigation_map, scene.local.global_position, step[1], true)
			if waypoints.size() > 1:
				waypoints.remove_at(0)
			if waypoints.is_empty():
				waypoints.append(step[1])
			Log.info(&"autoplay", "walk to %s via %d waypoints: %s" % [step[1], waypoints.size(), waypoints])
			scene.local.auto_target = waypoints[0]
			waypoints.remove_at(0)
			wait_left = 0.0
		"jump_to":
			var to: Vector3 = step[1] - scene.local.global_position
			scene.local.hop(Vector3(to.x, 0, to.z).normalized() * 6.0 + Vector3.UP * 7.0)
			wait_left = 0.2
		"sit":
			var res: Dictionary = Net.send_intent(Intents.make(&"sit", {"station": step[1]}))
			Log.info(&"autoplay", "sit %s -> %s" % [step[1], res])
		"intent":
			var res: Dictionary = Net.send_intent(Intents.make(step[1], step[2]))
			Log.info(&"autoplay", "%s %s -> %s" % [step[1], step[2], res])
		"approach_bot":
			var bot: PlayerAvatar = scene.avatars.get(int(step[1]), null)
			if bot != null:
				var to: Vector3 = scene.local.global_position - bot.global_position
				to.y = 0.0
				var goal: Vector3 = bot.global_position + (to.normalized() if to.length() > 0.1 else Vector3.BACK) * 1.3
				steps.insert(index, ["walk", goal])
		"face_bot":
			var bot: PlayerAvatar = scene.avatars.get(int(step[1]), null)
			if bot != null and scene.local.cam != null:
				var to: Vector3 = bot.global_position - scene.local.global_position
				scene.local.cam.yaw = atan2(-to.x, -to.z)
				scene.local.yaw = scene.local.cam.yaw
		"emote":
			Net.send_intent(Intents.make(&"emote", {"id": step[1]}))
		"wait":
			wait_left = float(step[1])
		"done":
			Log.info(&"autoplay", "script finished after %.1f s, money=$%d" % [elapsed, scene.view.state.balance(scene.local_id)])
