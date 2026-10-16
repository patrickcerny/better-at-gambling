extends Node
## Dev: the pictures on the tutorial pages (`HowToPlayPanel`), staged in the real match scene and
## saved at `--at` seconds to `--shot`. tools/tutorial_pictures.sh renders every view; one by hand:
##   xvfb-run -a tools/godot/godot --path . --rendering-method gl_compatibility -s tools/screenshot.gd
##     -- --scene res://tools/dev/tutorial_shot.tscn --frames 100000 --view jail --shot /tmp/jail.png
## Views: hall (the casino floor from above), table (sat at blackjack with a bet down), shop (the
## gift shop open, items in the HUD slots), jail (two beans behind the bars, a guard outside),
## lobby (ready pedestals glowing in the start room), rough (a shove knockdown, from the brawl clip),
## leaderboard (the standings over the casino), oddjobs (broke at the Odd Jobs cabinet, aiming at the
## glowing red button, the shared bar part full).

var _scene: MatchScene
var _view: String = "hall"
var _shot: String = ""
var _at: float = 6.0
var _t: float = 0.0
var _staged: bool = false
var _cam: Camera3D
## Lobby view: whose pedestal glows.
var _ready_ids: Array[int] = []


func _ready() -> void:
	var c: Cmdline = Cmdline.parse(OS.get_cmdline_user_args())
	_view = c.get_string("view", "hall")
	_shot = c.get_string("shot", "/tmp/tutorial_%s.png" % _view)
	_at = c.get_float("at", float({"table": 17.0, "rough": 7.4, "oddjobs": 9.0}.get(_view, 5.0)))
	if _view == "rough":
		# The scripted brawl (shoves through the real input path until the rival goes down).
		var clip: Node = (load("res://tools/dev/brawl_clip.tscn") as PackedScene).instantiate()
		add_child(clip)  # run with `--seconds 60` so the clip does not quit before the shot
		_scene = clip.get(&"_scene")
		return
	MatchScene.test_dummies = 4 if _view in ["lobby", "leaderboard", "hall"] else 2
	_scene = (load("res://match/match_scene.tscn") as PackedScene).instantiate()
	add_child(_scene)


func _process(delta: float) -> void:
	_t += delta
	if _scene == null or _scene.local == null:
		return
	if not _staged and _t >= 3.6:
		_staged = true
		_stage()
	if _cam != null:
		_cam.current = true
	if _view == "oddjobs" and _staged and _t >= _at - 0.3 and _scene.server.odd_jobs.fill() == 0.0:
		for i: int in 6:  # a bar part full (late: it drains when left alone)
			_scene.server.odd_jobs.press(_scene.local_id, _scene.server.match_time)
	for pid: int in _ready_ids:  # the scene lights the pedestals from the shared state
		(_scene.view.state.players[pid] as Dictionary)["ready"] = true
	if _shot != "" and _t >= _at:
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png(_shot)
		print("tutorial shot %s" % _shot)
		_shot = ""
		MatchScene.test_dummies = 0
		get_tree().quit(0)


func _stage() -> void:
	var srv: MatchServer = _scene.server
	srv.interactions.offences.clear()
	match _view:
		"hall":
			_free_cam(Vector3(17, 5.6, 7.2), Vector3(-6, 0.5, -6), 80.0)
			_scene.hud.visible = false
			var spots: Array[Vector3] = [Vector3(-2, 0, 2), Vector3(3, 0, 0), Vector3(7, 0, 4), Vector3(-6, 0, 5)]
			var i: int = 0
			for pid: int in _others():
				_place(pid, spots[i % spots.size()], randf() * TAU)
				i += 1
		"table":
			_scene.call(&"_autosit", &"blackjack_2")
		"shop":
			for id: StringName in [&"lucky_clover", &"black_cat", &"banana_peel"]:
				srv.items.give(_scene.local_id, id, srv.match_time)
			_place(_scene.local_id, LuckyLounge.SHOP_POS, -PI * 0.5)
			_scene.local.cam.yaw = -PI * 0.5
			_scene.local.cam.pitch = -0.1
			_scene.router.set_mode(InputRouter.Mode.MENU)
			_scene.shop_panel.open()
		"oddjobs":
			srv._comped[_scene.local_id] = srv.phases.segment_index()  # no House Comp toast in the picture
			srv.economy.take_up_to(_scene.local_id, 1000000, &"dev")
			var stand: Vector3 = LuckyLounge.ODD_JOBS_POS + Vector3(-0.15, 0, 0.35)
			_place(_scene.local_id, stand, -PI * 0.5)
			_scene.local.cam.yaw = -PI * 0.5 + 0.28
			_scene.local.cam.pitch = -0.2
		"race":  # the Race Hall archway from the casino floor (dev check only)
			_free_cam(Vector3(10.0, 3.2, -4.0), Vector3(24.0, 1.8, -13.2), 70.0)
			_scene.hud.visible = false
		"racehall":  # inside the Race Hall (dev check only)
			_free_cam(Vector3(23.2, 2.8, -11.4), Vector3(30.0, 0.9, -19.0), 75.0)
			_scene.hud.visible = false
		"jail":
			var ids: Array[int] = _others()
			for pid: int in ids.slice(0, 2):
				srv.put_in_jail(pid)
			_place(_scene.local_id, Vector3(14, 0, -2), 0.0)
			_scene.hud.visible = false
			if not _scene.guards.is_empty():
				var g: Guard = _scene.guards[0]
				g.process_mode = Node.PROCESS_MODE_DISABLED
				g.global_position = LuckyLounge.JAIL_DOOR + Vector3(-1.0, 0, -1.9)
				g.rotation.y = -PI * 0.75
			_free_cam(Vector3(15.8, 2.3, -4.6), Vector3(22.4, 1.0, -7.8), 70.0)
		"lobby":
			var i: int = 0
			var ids: Array[int] = [_scene.local_id]
			ids.append_array(_others())
			for pid: int in ids:
				var color: int = int((_scene.view.state.players[pid] as Dictionary).get("color", i))
				var pad: Vector3 = _scene.map.ready_pad(color) + Vector3(0, LuckyLounge.PEDESTAL_TOP + 0.05, 0)
				_place(pid, pad, 0.0)
				if i != 2:  # one pedestal stays dark: that player isn't ready yet
					_ready_ids.append(pid)
				i += 1
			if _scene.local.cam.mode != PlayerCamera.Mode.THIRD:
				_scene.local.cam.toggle_mode()  # your own bean shows on its pedestal too
			_scene.hud.visible = false
			_free_cam(Vector3(0, 3.0, 9.4), Vector3(0, 1.6, 15.1), 80.0)
		"leaderboard":
			var cash: Array[int] = [640, -310, 1210, -520]
			var i: int = 0
			for pid: int in _others():
				srv.economy.apply(pid, cash[i % cash.size()], &"dev")
				i += 1
			srv.economy.apply(_scene.local_id, 380, &"dev")
			_place(_scene.local_id, Vector3(0, 0, 1.5), 0.0)
			_scene.local.cam.yaw = 0.0
			_scene.local.cam.pitch = -0.15
			_scene.hud.show_leaderboard.call_deferred(true)


func _others() -> Array[int]:
	var out: Array[int] = []
	for pid: int in _scene.avatars:
		if pid != _scene.local_id:
			out.append(pid)
	out.sort()
	return out


func _place(pid: int, pos: Vector3, yaw: float) -> void:
	_scene.avatars[pid].teleport(pos, yaw)
	_scene.server.set_server_position(pid, pos)


## A free camera inside the pixel view's world (the match renders its 3D there).
func _free_cam(pos: Vector3, look: Vector3, fov: float) -> void:
	_cam = Camera3D.new()
	_cam.fov = fov
	_cam.near = 0.05
	_scene.pixel_view.world.add_child(_cam)
	_cam.global_position = pos
	_cam.look_at(look, Vector3.UP)
	_cam.current = true
