extends Node
## Scripted local player for `--autoplay`: walks to each station type, plays a few rounds,
## shoves/grabs/throws another player (a test dummy), shakes chips, tries the VIP door, walks by
## the jail, then idles.
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


## `--autoplay-variant 1` swaps the single-seat slot machine (and the last table) so two scripted
## clients share the blackjack table, roulette and Plinko but never queue for one seat.
var variant: int = 0
## `--autoplay-script thrower|victim`: the networked physics scenario (two clients, no dummies):
## the victim waits at THROW_SPOT, the thrower grabs and throws them; both check the ragdoll's
## resting place against the server's and the victim checks it gets its body back.
var script_name: String = ""
## Last client-side position of every ragdolled avatar (compared on `player_got_up`).
var _last_rag: Dictionary[int, Vector3] = {}
## "wait_event" step: [type, deadline].
var _awaiting: Array = []
## Quiz answers given / reward rows that gave us an item (logged for the network tests).
var answers_sent: int = 0
var rewards_items: int = 0
## Items: the default script presses an item key every few seconds through the real ItemController
## (target picker included) and counts the server's confirmations.
var items_used: int = 0
var _item_timer: float = 0.0
const ITEM_EVERY: float = 7.0

const THROW_SPOT: Vector3 = Vector3(5.0, 0.0, 2.0)

const VARIANT_STATIONS: Dictionary[StringName, StringName] = {
	&"blackjack_2": &"blackjack_1", &"slot_8": &"slot_9",
}


func _ready() -> void:
	scene = get_parent() as MatchScene
	variant = SceneRouter.cmdline.get_int("autoplay-variant", 0) if SceneRouter.cmdline != null else 0
	script_name = SceneRouter.cmdline.get_string("autoplay-script", "") if SceneRouter.cmdline != null else ""
	if scene.view.state.room_mode:
		await _lobby()
	else:
		await get_tree().create_timer(3.5).timeout  # intro
	if not is_inside_tree():
		return
	_build_steps()
	Net.event_received.connect(_on_event)
	Log.info(&"autoplay", "starting %d steps" % steps.size())


## Online: get ready in the lobby (pad or panel) and wait for the intro to finish.
func _lobby() -> void:
	await get_tree().create_timer(1.0).timeout
	if not is_inside_tree():
		return
	if scene.view.state.phase == Phase.Id.LOBBY:
		Log.info(&"autoplay", "lobby: ready")
		Net.send_intent(Intents.make(&"set_ready", {"ready": true}))
	while is_inside_tree() and scene.view.state.phase != Phase.Id.CASINO:
		await get_tree().create_timer(0.2).timeout
	Log.info(&"autoplay", "match is on")


func _on_event(ev: Dictionary) -> void:
	if ev["type"] in [&"player_knocked_out", &"player_thrown_out", &"player_thrown", &"chips_shaken_out", &"jackpot_won", &"intent_rejected", &"player_grabbed", &"player_shoved"]:
		Log.info(&"autoplay", "event %s" % ev)
	if ev["type"] == &"player_got_up" and Net.is_client():
		var pid: int = int(ev["player"])
		if _last_rag.has(pid):
			# Ground-plane distance: getting up drops the torso height (`end_ragdoll`).
			var at: Vector3 = Serializer.to_vec3(ev["pos"])
			var d: float = Vector2(_last_rag[pid].x - at.x, _last_rag[pid].z - at.z).length()
			Log.info(&"nettest", "NETTEST got_up player=%d agreement=%.3f" % [pid, d])
			_last_rag.erase(pid)
	match ev["type"]:
		&"quiz_question":
			_answer(int(ev["index"]), (ev["answers"] as Array).size())
		&"roulette_royale_pick_open":
			if scene.local_id in (ev.get("alive", []) as Array):
				_answer(int(ev["spin"]), 2)  # red or black; the pick window is 5 s
		&"rewards_started":
			for row: Dictionary in ev["rewards"]:
				if int(row["player"]) == scene.local_id and StringName(row.get("item", &"")) != &"":
					rewards_items += 1
					Log.info(&"autoplay", "reward item %s" % row["item"])
		&"match_ended":
			Log.info(&"nettest", "NETTEST autoplay answers=%d rewards=%d items=%d" % [answers_sent, rewards_items, items_used])
		&"item_used":
			if int(ev["player"]) == scene.local_id:
				items_used += 1
				Log.info(&"autoplay", "item used %s" % ev)
	if not _awaiting.is_empty() and ev["type"] == _awaiting[0] and int(ev.get("player", ev.get("target", -1))) == int(_awaiting[2]):
		_awaiting.clear()


## Casino Quiz: a random answer after a human-ish pause (keys/buttons go through the same intent).
func _answer(question: int, count: int) -> void:
	await get_tree().create_timer(randf_range(1.0, 5.0)).timeout
	if not is_inside_tree() or count <= 0:
		return
	var res: Dictionary = Net.send_intent(Intents.make(&"submit_answer", {"question": question, "index": randi() % count}))
	answers_sent += 1
	Log.info(&"autoplay", "quiz answer %d -> %s" % [question, res])


func _build_steps() -> void:
	# Any other player (a test dummy in Practice) is the shove/grab partner.
	var bot: int = -1
	for pid: int in scene.avatars:
		if pid != scene.local_id and bot < 0:
			bot = pid
	match script_name:
		"thrower":
			steps = [
				["walk", THROW_SPOT + Vector3(0, 0, 1.4)],
				["wait_near", bot, 1.0], ["wait", 1.0],
				["face_partner", bot], ["wait", 0.2],
				["shove_partner", bot],
				["wait_event", &"player_shoved", 30.0], ["wait", 0.5],  # the victim shoves back
				["wait_near", bot, 1.0], ["wait", 0.5],
				["approach_partner", bot], ["wait", 0.3],
				["face_partner", bot], ["wait", 0.2],
				["intent", &"grab", {"target": bot}], ["wait", 0.8],
				["intent", &"release", {"throw": true, "aim": [1, 0, -0.4]}],
				["wait_event", &"player_got_up", 30.0, bot], ["wait", 5.0],  # victim checks its body
				# Three quick shoves knock the victim out.
				["approach_if_far", bot], ["face_partner", bot], ["shove_partner", bot], ["wait", 1.25],
				["approach_if_far", bot], ["face_partner", bot], ["shove_partner", bot], ["wait", 1.25],
				["approach_if_far", bot], ["face_partner", bot], ["shove_partner", bot], ["wait", 8.0],
				["done", null],
			]
			return
		"victim":
			steps = [
				["walk", THROW_SPOT], ["wait", 0.5],
				["wait_event", &"player_shoved", 45.0], ["wait", 0.6],
				["walk", THROW_SPOT], ["wait", 0.3],
				["face_partner", bot], ["wait", 0.2], ["shove_partner", bot],
				["wait_event", &"player_got_up", 45.0], ["wait", 1.0],
				["walk_by", Vector3(0, 0, 3.0)], ["wait", 1.5],
				["check_authority"],
				["done", null],
			]
			return
	steps = [
		["walk_station", _st(&"blackjack_3"), Vector3(0, 0, 2.6)],
		["sit", _st(&"blackjack_3")], ["wait", 0.5],
		["intent", &"place_bet", {"station": _st(&"blackjack_3"), "bet": {"amount": 25}}], ["wait", 9.0],
		["intent", &"action", {"station": _st(&"blackjack_3"), "action": &"stand"}], ["wait", 3.0],
		["intent", &"place_bet", {"station": _st(&"blackjack_3"), "bet": {"amount": 50}}], ["wait", 9.0],
		["intent", &"action", {"station": _st(&"blackjack_3"), "action": &"hit"}], ["wait", 0.5],
		["intent", &"action", {"station": _st(&"blackjack_3"), "action": &"stand"}], ["wait", 3.5],
		["intent", &"leave", {}], ["wait", 0.5],
		# Casino Hold'em: ante + AA Bonus, fold or call by the simple strategy; then a fold.
		["walk_station", &"holdem_1", Vector3(0.45, 0, 2.3)],
		["sit", &"holdem_1"], ["wait", 0.5],
		["intent", &"place_bet", {"station": &"holdem_1", "bet": {"amount": 20, "bonus": 10}}], ["wait", 9.0],
		["holdem_play", &"holdem_1"], ["wait", 5.0],
		["intent", &"place_bet", {"station": &"holdem_1", "bet": {"amount": 20}}], ["wait", 9.0],
		["intent", &"action", {"station": &"holdem_1", "action": &"fold"}], ["wait", 4.5],
		["intent", &"leave", {}], ["wait", 0.5],
		["walk_station", _st(&"roulette_1"), Vector3(1.0, 0, 2.0)],
		["sit", _st(&"roulette_1")], ["wait", 1.0],
		["intent", &"place_bet", {"station": _st(&"roulette_1"), "bet": {"type": &"red", "value": 0, "amount": 25}}],
		["intent", &"place_bet", {"station": _st(&"roulette_1"), "bet": {"type": &"straight", "value": 17, "amount": 10}}],
		["wait", 23.0],
		["intent", &"place_bet", {"station": _st(&"roulette_1"), "bet": {"type": &"dozen", "value": 2, "amount": 25}}],
		["wait", 22.0],
		["intent", &"leave", {}], ["wait", 0.5],
		["walk_station", _st(&"slot_8"), Vector3(0, 0, 1.2)],
		["sit", _st(&"slot_8")], ["wait", 0.5],
		["intent", &"place_bet", {"station": _st(&"slot_8"), "bet": {"amount": 10}}], ["wait", 2.2],
		["intent", &"place_bet", {"station": _st(&"slot_8"), "bet": {"amount": 25}}], ["wait", 0.8],
		["intent", &"action", {"station": _st(&"slot_8"), "action": &"stop"}], ["wait", 1.0],
		["intent", &"place_bet", {"station": _st(&"slot_8"), "bet": {"amount": 50}}], ["wait", 2.2],
		["intent", &"leave", {}], ["wait", 0.5],
		["walk_station", _st(&"plinko_1"), Vector3(-0.8, 0, 2.4)],
		["sit", _st(&"plinko_1")], ["wait", 0.5],
		["intent", &"place_bet", {"station": _st(&"plinko_1"), "bet": {"amount": 25, "risk": &"medium"}}], ["wait", 3.5],
		["intent", &"place_bet", {"station": _st(&"plinko_1"), "bet": {"amount": 10, "risk": &"high"}}], ["wait", 3.5],
		["intent", &"leave", {}], ["wait", 0.5],
		["walk", LuckyLounge.SPAWNS[1] + Vector3(0, 0, -1.5)],
		["face_partner", bot], ["wait", 0.3],
		["shove_partner", bot], ["wait", 1.4],
		["shove_partner", bot], ["wait", 1.4],
		["shove_partner", bot], ["wait", 1.0],
		["intent", &"shake", {}], ["wait", 0.7], ["intent", &"shake", {}], ["wait", 0.7], ["intent", &"shake", {}], ["wait", 4.0],
		["approach_partner", bot], ["wait", 0.5],
		["face_partner", bot], ["intent", &"grab", {"target": bot}], ["wait", 1.0],
		["intent", &"release", {"throw": true, "aim": [0, 0, -1]}], ["wait", 4.0],
		["emote", &"laugh"], ["wait", 2.0],
		["walk", LuckyLounge.VIP_GATE_POS + Vector3(0, 0, 2.5)], ["wait", 0.5],
		["jump_to", LuckyLounge.VIP_GATE_POS + Vector3(0, 0, -1.0)], ["wait", 3.0],
		["walk", LuckyLounge.JAIL_DOOR + Vector3(-1.0, 0, 0)], ["wait", 1.0],
		["walk_station", _st(&"blackjack_2"), Vector3(0, 0, 2.6)],
		["sit", _st(&"blackjack_2")], ["wait", 0.5],
		["intent", &"place_bet", {"station": _st(&"blackjack_2"), "bet": {"amount": 100}}], ["wait", 9.0],
		["intent", &"action", {"station": _st(&"blackjack_2"), "action": &"double"}], ["wait", 4.0],
		["intent", &"leave", {}],
		["done", null],
	]


func _use_items(delta: float) -> void:
	_item_timer += delta
	if _item_timer < ITEM_EVERY or not scene.local.is_standing():
		return
	_item_timer = 0.0
	var inv: Array = scene.view.state.players.get(scene.local_id, {}).get("inventory", [])
	if inv.is_empty():
		return
	var slot: int = randi() % inv.size()
	Log.info(&"autoplay", "item key %d (%s)" % [slot + 1, inv[slot]])
	# Hold-and-aim bar: face the nearest other player so aimed items find a target, hold the slot,
	# use it, and take the first button of any two-button choice.
	var me: Vector3 = scene.local.global_position
	var best: PlayerAvatar = null
	for pid: int in scene.avatars:
		if pid == scene.local_id:
			continue
		var a: PlayerAvatar = scene.avatars[pid]
		if best == null or a.global_position.distance_to(me) < best.global_position.distance_to(me):
			best = a
	if best != null and scene.local.cam != null:
		var to: Vector3 = best.global_position - me
		scene.local.cam.yaw = atan2(-to.x, -to.z)
		scene.local.yaw = scene.local.cam.yaw
	scene.items_ctl.hold(slot)
	scene.items_ctl.use_held()
	if not scene.items_ctl.pending.is_empty():
		scene.items_ctl._confirm_choice(0)


func _st(id: StringName) -> StringName:
	return VARIANT_STATIONS.get(id, id) if variant == 1 else id


## The station a step means on tonight's floor (docs/FLOOR_PLAN.md): the one it names when it is
## there (always on the full floor), else another table of the same game, else &"" (the step is
## skipped: nothing is guaranteed in an online room).
func _actual(id: StringName) -> StringName:
	if scene.map.stations.has(id):
		return id
	if not LuckyLounge.STATIONS.has(id):
		return &""
	var game: StringName = (LuckyLounge.STATIONS[id] as Array)[0]
	var ids: Array = scene.map.stations.keys()
	ids.sort()
	for sid: StringName in ids:
		var same_room: bool = String(sid).begins_with("vip_") == String(id).begins_with("vip_")  # the bouncer
		if same_room and not FunRoom.is_fun(sid) and scene.map.stations[sid].game_id == game:
			return sid
	return &""


func _process(delta: float) -> void:
	elapsed += delta
	for pid: int in scene.avatars:
		if scene.avatars[pid].state == PlayerAvatar.State.RAGDOLL:
			_last_rag[pid] = scene.avatars[pid].global_position
	if steps.is_empty() or scene.local == null:
		return
	# The script pauses while the casino is closed (quiz, rewards, results).
	var phase: Phase.Id = scene.view.state.phase
	if phase != Phase.Id.CASINO and phase != Phase.Id.PRE_MINIGAME:
		if walking_to != Vector3.INF:
			walking_to = Vector3.INF
			scene.local.auto_target = Vector3.INF
			index = maxi(index - 1, 0)  # walk there again afterwards
		return
	if script_name == "":
		_use_items(delta)
	if not _awaiting.is_empty():
		if elapsed > float(_awaiting[1]):
			Log.warn(&"autoplay", "gave up waiting for %s" % _awaiting[0])
			_awaiting.clear()
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
		"walk_station":
			# In front of the table in its own frame (it may stand on another spot tonight).
			var sid: StringName = _actual(step[1])
			if sid == &"":
				Log.info(&"autoplay", "no %s on tonight's floor, skipping" % step[1])
				return
			var st: StationBase = scene.map.stations[sid]
			steps.insert(index, ["walk", st.global_transform * Vector3(step[2])])
		"sit":
			var sit_at: StringName = _actual(step[1])
			if sit_at == &"":
				return
			var res: Dictionary = Net.send_intent(Intents.make(&"sit", {"station": sit_at}))
			Log.info(&"autoplay", "sit %s -> %s" % [sit_at, res])
		"intent":
			var payload: Dictionary = (step[2] as Dictionary).duplicate()
			if payload.has("station"):
				payload["station"] = _actual(StringName(payload["station"]))
				if payload["station"] == &"":
					return
			var res: Dictionary = Net.send_intent(Intents.make(step[1], payload))
			Log.info(&"autoplay", "%s %s -> %s" % [step[1], payload, res])
		"holdem_play":
			# Fold or call from the cards on the felt (the strategy the RTP sim plays).
			var at: StringName = _actual(step[1])
			if at == &"":
				return
			var pub: Dictionary = scene.view.state.stations.get(at, {})
			var mine: Dictionary = HoldemStation.hand_of(pub.get("hands", {}), scene.local_id)
			var hole: Array[int] = []
			for c: Variant in mine.get("hole", []):
				hole.append(int(c))
			var board: Array[int] = []
			for c: Variant in pub.get("board", []):
				board.append(int(c))
			var act: StringName = HoldemLogic.CALL if hole.size() == 2 and HoldemLogic.simple_call(hole, board) else HoldemLogic.FOLD
			var res: Dictionary = Net.send_intent(Intents.make(&"action", {"station": at, "action": act}))
			Log.info(&"autoplay", "holdem %s %s -> %s" % [mine.get("hand", "?"), act, res])
		"approach_partner":
			var partner: PlayerAvatar = scene.avatars.get(int(step[1]), null)
			if partner != null:
				var to: Vector3 = scene.local.global_position - partner.global_position
				to.y = 0.0
				var goal: Vector3 = partner.global_position + (to.normalized() if to.length() > 0.1 else Vector3.BACK) * 1.3
				steps.insert(index, ["walk", goal])
		"shove_partner":
			# Like a real client: aim at the partner and name them, so lag on their position
			# (150 ms, 2% loss in the net tests) doesn't turn the swing into a whiff.
			var mark: PlayerAvatar = scene.avatars.get(int(step[1]), null)
			var aim: Vector3 = scene.local.facing()
			if mark != null:
				var to: Vector3 = mark.global_position - scene.local.global_position
				to.y = 0.0
				if to.length() > 0.05:
					aim = to.normalized()
			var payload: Dictionary = {"aim": Serializer.vec3(aim), "target": int(step[1])}
			var res: Dictionary = Net.send_intent(Intents.make(&"shove", payload))
			Log.info(&"autoplay", "shove %s -> %s" % [payload, res])
		"approach_if_far":
			var other: PlayerAvatar = scene.avatars.get(int(step[1]), null)
			if other != null and other.global_position.distance_to(scene.local.global_position) > 1.7:
				steps.insert(index, ["approach_partner", step[1]])
		"face_partner":
			var partner: PlayerAvatar = scene.avatars.get(int(step[1]), null)
			if partner != null and scene.local.cam != null:
				var to: Vector3 = partner.global_position - scene.local.global_position
				scene.local.cam.yaw = atan2(-to.x, -to.z)
				scene.local.yaw = scene.local.cam.yaw
		"walk_by":
			steps.insert(index, ["walk", scene.local.global_position + Vector3(step[1])])
		"wait_near":
			var other: PlayerAvatar = scene.avatars.get(int(step[1]), null)
			if other == null or other.global_position.distance_to(THROW_SPOT) > float(step[2]):
				index -= 1
				wait_left = 0.3
		"wait_event":
			_awaiting = [step[1], elapsed + float(step[2]), step[3] if step.size() > 3 else scene.local_id]
		"check_authority":
			var srv: Vector3 = scene.net_world.server_position(scene.local_id)
			var d: float = srv.distance_to(scene.local.global_position)
			Log.info(&"nettest", "NETTEST authority player=%d state=%d drift=%.3f" % [scene.local_id, scene.local.state, d])
		"emote":
			Net.send_intent(Intents.make(&"emote", {"id": step[1]}))
		"wait":
			wait_left = float(step[1])
		"done":
			Log.info(&"autoplay", "script finished after %.1f s, money=$%d" % [elapsed, scene.view.state.balance(scene.local_id)])
