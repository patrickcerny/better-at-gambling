extends Node
## Dev: the real match scene with three dummies; one gets rich (crown) and is caught by a guard
## who carries them toward the door. Saves `--shot` at `--at` seconds after the catch and quits.
## Run with tools/screenshot.gd --scene res://tools/dev/throwout_shot.tscn --frames 100000
## --shot out.png [--at 0.8] [--ko]
## (`--ko` knocks a dummy out instead, for the birdies).

var _scene: MatchScene
var _t: float = 0.0
var _caught_at: float = -1.0
var _at: float = 0.8
var _shot: String = ""
var _ko: bool = false


func _ready() -> void:
	var c: Cmdline = Cmdline.parse(OS.get_cmdline_user_args())
	_at = c.get_float("at", 0.8)
	_shot = c.get_string("shot", "/tmp/throwout.png")
	_ko = c.has_flag("ko")
	MatchScene.test_dummies = 3
	_scene = (load("res://match/match_scene.tscn") as PackedScene).instantiate()
	add_child(_scene)


func _process(delta: float) -> void:
	_t += delta
	if _scene.server == null or _scene.local == null:
		return
	var ids: Array[int] = []
	for pid: int in _scene.avatars:
		if pid != _scene.local_id:
			ids.append(pid)
	if ids.size() < 2:
		return
	var bot: int = ids[0]
	if _t > 4.0 and _caught_at < 0.0 and not _scene.guards.is_empty():
		_caught_at = _t
		_scene.server.economy.apply(ids[1], 800, &"dev")
		var spot: Vector3 = Vector3(-4, 0, 2)
		var b: PlayerAvatar = _scene.avatars[bot]
		b.teleport(spot, PI * 0.5)
		_scene.server.set_server_position(bot, spot)
		var rich: PlayerAvatar = _scene.avatars[ids[1]]
		rich.teleport(Vector3(-1.5, 0, 4.5), PI)
		_scene.server.set_server_position(ids[1], rich.global_position)
		_scene.local.teleport(Vector3(-2.0, 0, 6.5), atan2(2.0, 4.5))
		_scene.local.cam.yaw = _scene.local.yaw
		_scene.local.cam.pitch = -0.2
		if _scene.local.cam.mode != PlayerCamera.Mode.THIRD:
			_scene.local.cam.toggle_mode()
		_scene.server.set_server_position(_scene.local_id, _scene.local.global_position)
		var g: Guard = _scene.guards[0]
		g.global_position = spot + Vector3(-1.0, 0, 0)
		if _ko:
			_scene.server.report_knockout(bot, -1, &"wall")
		else:
			_scene.server.report_thrown_out(bot, g.guard_id)
	if _caught_at > 0.0 and _t - _caught_at >= _at and _shot != "":
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png(_shot)
		print("throwout shot %s" % _shot)
		_shot = ""
		MatchScene.test_dummies = 0
		get_tree().quit(0)
