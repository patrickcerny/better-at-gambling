extends Node
## Dev: the real match scene with three dummies and a scripted brawl through the real input path
## (the router's shove / grab / shake signals, the local avatar walking over chip piles), for
## clips of how hitting and picking up chips feel. Quits after `--seconds` (default 22).
## Record frames with Godot's movie maker:
##   xvfb-run -a godot --path . --rendering-method gl_compatibility --resolution 1280x720
##     --write-movie /tmp/brawl/f.png --fixed-fps 30 res://tools/dev/brawl_clip.tscn
## then `ffmpeg -framerate 30 -i /tmp/brawl/f%08d.png -pix_fmt yuv420p brawl.mp4`.

var _scene: MatchScene
var _t: float = 0.0
var _end: float = 22.0
var _steps: Array[Array] = []
var _bot: int = -1
var _bot2: int = -1


func _ready() -> void:
	var c: Cmdline = Cmdline.parse(OS.get_cmdline_user_args())
	_end = c.get_float("seconds", 22.0)
	MatchScene.test_dummies = 3
	_scene = (load("res://match/match_scene.tscn") as PackedScene).instantiate()
	add_child(_scene)
	Net.event_received.connect(func(ev: Dictionary) -> void:
		if String(ev["type"]).begins_with("chips") or String(ev["type"]).begins_with("player_"):
			print("brawl t=%.2f %s" % [_t, ev]))
	_steps = [
		[3.6, _setup],
		[4.4, _shove], [5.1, _approach], [5.75, _shove], [6.6, _approach], [7.2, _shove],
		[7.8, _walk_to_ko], [8.5, _shake], [8.9, _shake], [9.3, _shake],
		[9.5, _collect_piles],
		[15.5, _setup_grab], [16.2, _grab], [17.4, _throw],
		[_end, _quit],
	]


func _process(delta: float) -> void:
	_t += delta
	if _scene.local == null:
		return
	if _scene.server != null:
		_scene.server.interactions.offences.clear()  # keep security out of the clip
	if _scene.casino_floor != null and _scene.casino_floor.waiter != null:
		var w: Waiter = _scene.casino_floor.waiter  # and the waiter's puddles
		w.process_mode = Node.PROCESS_MODE_DISABLED
		w.global_position = Vector3(-18.0, 0.0, 12.0)
	while not _steps.is_empty() and _t >= float(_steps[0][0]):
		var step: Array = _steps.pop_front()
		(step[1] as Callable).call()


func _place(pid: int, pos: Vector3, yaw: float) -> void:
	_scene.avatars[pid].teleport(pos, yaw)
	_scene.server.set_server_position(pid, pos)


func _setup() -> void:
	var ids: Array[int] = []
	for pid: int in _scene.avatars:
		if pid != _scene.local_id:
			ids.append(pid)
	_bot = ids[0]
	_bot2 = ids[1]
	var me: Vector3 = Vector3(5.0, 0.0, 4.5)
	_place(_scene.local_id, me, 0.0)
	_place(_bot, me + Vector3(0.0, 0.0, -1.7), PI)
	_place(_bot2, me + Vector3(3.0, 0.0, -1.0), PI * 0.5)
	_scene.local.cam.yaw = 0.0
	_scene.local.cam.pitch = -0.25
	for g: Guard in _scene.guards:  # security sits this one out
		g.process_mode = Node.PROCESS_MODE_DISABLED
		g.global_position = Vector3(-18.0, 0.0, -12.0)
	if _scene.local.cam.mode != PlayerCamera.Mode.THIRD:
		_scene.local.cam.toggle_mode()


func _face(pid: int) -> void:
	var to: Vector3 = _scene.avatars[pid].global_position - _scene.local.global_position
	_scene.local.cam.yaw = atan2(-to.x, -to.z)
	_scene.local.yaw = _scene.local.cam.yaw


func _approach() -> void:
	var b: PlayerAvatar = _scene.avatars[_bot]
	var away: Vector3 = _scene.local.global_position - b.global_position
	away.y = 0.0
	_scene.local.auto_target = b.global_position + away.normalized() * 1.4


func _shove() -> void:
	_scene.local.auto_target = Vector3.INF
	_face(_bot)
	_scene.router.shove.emit()


func _walk_to_ko() -> void:
	var b: PlayerAvatar = _scene.avatars[_bot]
	_scene.local.auto_target = b.global_position + (_scene.local.global_position - b.global_position).normalized() * 1.0


func _shake() -> void:
	_scene.router.shake.emit()


func _collect_piles() -> void:
	var best: Vector3 = Vector3.INF
	for id: int in _scene.piles:
		var p: Vector3 = _scene.piles[id].global_position
		if best == Vector3.INF or p.distance_to(_scene.local.global_position) < best.distance_to(_scene.local.global_position):
			best = p
	if best != Vector3.INF:
		_scene.local.auto_target = best
		_steps.push_front([_t + 1.0, _collect_piles])


func _setup_grab() -> void:
	_scene.local.auto_target = Vector3.INF
	var me: Vector3 = _scene.local.global_position
	_place(_bot2, me + Vector3(0.0, 0.0, -1.6), PI)
	_scene.local.cam.yaw = 0.0


func _grab() -> void:
	_face(_bot2)
	_scene.router.grab_pressed.emit()


func _throw() -> void:
	_scene.local.cam.yaw += 0.6
	_scene.router.shove.emit()


func _quit() -> void:
	MatchScene.test_dummies = 0
	get_tree().quit(0)
