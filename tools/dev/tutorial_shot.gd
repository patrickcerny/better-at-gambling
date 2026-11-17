extends Node
## Dev: the pictures on the tutorial pages (`HowToPlayPanel`), staged in the real match scene and
## saved at `--at` seconds to `--shot`. tools/tutorial_pictures.sh renders every view; one by hand:
##   xvfb-run -a tools/godot/godot --path . --rendering-method gl_compatibility -s tools/screenshot.gd
##     -- --scene res://tools/dev/tutorial_shot.tscn --frames 100000 --view jail --shot /tmp/jail.png
## Views: hall (the casino floor from above), table (sat at blackjack with a bet down), shop (the
## gift shop open, items in the HUD slots), jail (two beans behind the bars, a guard outside),
## lobby (ready pedestals glowing in the start room), rough (a shove knockdown, from the brawl clip),
## items (four beans in a row, each holding an item out), leaderboard (the standings over the casino), oddjobs (broke at the Odd Jobs cabinet, aiming at the
## glowing red button, the shared bar part full). Dev checks of PLAY ONLINE-style views (the cards now use generated splash arts):
## online_public (an empty table with an OPEN sign), online_private (the same behind a velvet rope,
## RESERVED), online_browse (players at tables across the floor), online_friends (three friends
## waving you over). Dev checks only: race, racehall, and floor (the
## casino floor from just inside the lobby doors; `--floor <layout id>` picks the floor, e.g.
## `--floor floor_1234` (a drawn floor by its seed), `--floor random` or `--floor grand_hall`,
## docs/FLOOR_PLAN.md; `--from x,y,z --to x,y,z` moves the camera).

var _scene: MatchScene
var _view: String = "hall"
var _shot: String = ""
var _at: float = 6.0
var _t: float = 0.0
var _staged: bool = false
var _cam: Camera3D
## Floor view: where the camera stands and looks (`--from`, `--to`).
var _from: Vector3 = Vector3(0.0, 4.2, 7.6)
var _to: Vector3 = Vector3(0.0, 0.0, -6.0)
## Items view: where the row of beans stands and which way they face (`--items-at x,y,z`, `--items-yaw`).
var _items_at: Vector3 = Vector3(0.0, 0.0, 2.0)
var _items_yaw: float = PI
## Lobby view: whose pedestal glows.
var _ready_ids: Array[int] = []
## Friends view: who waves (again and again, until the shot).
var _waves: Array[int] = []
var _wave_t: float = 0.0


func _ready() -> void:
	var c: Cmdline = Cmdline.parse(OS.get_cmdline_user_args())
	_view = c.get_string("view", "hall")
	_from = _vec3(c.get_string("from", ""), _from)
	_to = _vec3(c.get_string("to", ""), _to)
	_items_at = _vec3(c.get_string("items-at", ""), _items_at)
	_items_yaw = c.get_float("items-yaw", _items_yaw)
	_shot = c.get_string("shot", "/tmp/tutorial_%s.png" % _view)
	_at = c.get_float("at", float({"table": 17.0, "rough": 7.4, "oddjobs": 9.0}.get(_view, 5.0)))
	if _view == "rough":
		# The scripted brawl (shoves through the real input path until the rival goes down).
		var clip: Node = (load("res://tools/dev/brawl_clip.tscn") as PackedScene).instantiate()
		add_child(clip)  # run with `--seconds 60` so the clip does not quit before the shot
		_scene = clip.get(&"_scene")
		return
	MatchScene.test_dummies = {"online_public": 0, "online_private": 0, "online_browse": 7, "online_friends": 3}.get(_view, 4 if _view in ["lobby", "leaderboard", "hall", "items"] else 2)
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
	_wave_t -= delta
	if not _waves.is_empty() and _wave_t <= 0.0:
		_wave_t = 2.4
		var k: int = 0
		for pid: int in _waves:
			(_scene.avatars[pid] as PlayerAvatar).play_emote(&"wave", 0.05 + 0.35 * k)  # past 0: no speech bubble
			k += 1
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
	if _view.begins_with("online_"):
		for g: Guard in _scene.guards:  # no security guard walking into PLAY ONLINE's pictures
			g.visible = false
			g.process_mode = Node.PROCESS_MODE_DISABLED
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
		"items":  # beans in a row, each with an item out in their hand (the items page)
			var kit: Array[StringName] = [&"baseball_bat", &"lucky_clover", &"black_cat", &"beer"]
			var i: int = 0
			for pid: int in _others():
				var id: StringName = kit[i % kit.size()]
				srv.items.give(pid, id, srv.match_time)
				_place(pid, _items_at + Vector3(-2.4 + 1.6 * i, 0, 0), _items_yaw)
				srv.submit_intent(pid, Intents.make(&"hold_item", {"item": String(id)}))
				i += 1
			_place(_scene.local_id, _items_at + Vector3(0, 0, -6), 0.0)
			_scene.hud.visible = false
			_free_cam(_items_at + Vector3(0.3, 1.7, 4.2), _items_at + Vector3(0, 0.9, 0), 55.0)
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
		"floor":  # the casino floor from just inside the lobby doors (dev check; `--floor <layout>`)
			_free_cam(_from, _to, 85.0)
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
		"online_public", "online_private":  # PLAY ONLINE's create cards: an empty table waiting
			_scene.hud.visible = false
			_place(_scene.local_id, Vector3(0, 0, 60), 0.0)
			var st: StationBase = _table(0)
			var fwd: Vector3 = (st.seat_position(0) - st.global_position)
			fwd.y = 0.0
			fwd = fwd.normalized()
			var side: Vector3 = fwd.cross(Vector3.UP)
			var at: Vector3 = st.global_position
			if _view == "online_public":
				_sign(at - side * 1.7 + fwd * 1.3, "OPEN", Palette.VIP_GOLD, fwd)
			else:
				_velvet_rope(at + fwd * 1.9, side, fwd)
				_sign(at + fwd * 2.05 + Vector3(0, 0.25, 0), "RESERVED", Palette.CREAM, fwd)
			_free_cam(at + fwd * 4.3 + side * 1.6 + Vector3(0, 2.2, 0), at + Vector3(0, 0.6, 0), 52.0)
		"online_browse":  # BROWSE LOBBIES: busy tables across the floor
			_scene.hud.visible = false
			_place(_scene.local_id, Vector3(0, 0, 60), 0.0)
			var i: int = 0
			for pid: int in _others():
				var st: StationBase = _table(i / 2)
				_sit_dummy(pid, st, i % 2)
				i += 1
			var first: StationBase = _table(0)
			_free_cam(first.global_position + Vector3(6.5, 5.0, 7.5), first.global_position + Vector3(-3.0, 0.0, -4.0), 70.0)
		"online_friends":  # FRIENDS' LOBBIES: your friends at a table, waving you over
			_scene.hud.visible = false
			var st: StationBase = _table(0)
			var fwd: Vector3 = (st.seat_position(0) - st.global_position)
			fwd.y = 0.0
			fwd = fwd.normalized()
			var side: Vector3 = fwd.cross(Vector3.UP)
			var spot: Vector3 = st.global_position + fwd * 1.8
			spot.y = 0.0
			var i: int = 0
			for pid: int in _others():
				_place(pid, spot + side * (-1.15 + 1.15 * i), atan2(-fwd.x, -fwd.z))
				i += 1
			_place(_scene.local_id, spot + fwd * 30.0, 0.0)
			_waves = _others()
			_free_cam(spot + fwd * 5.4 + Vector3(0, 1.6, 0), spot + Vector3(0, 0.8, 0), 55.0)
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


## The `n`-th blackjack table of the floor (by id), else any table.
func _table(n: int) -> StationBase:
	var ids: Array = _scene.map.stations.keys().filter(func(k: StringName) -> bool: return String(k).begins_with("blackjack") or String(k).begins_with("roulette"))
	ids.sort()
	if ids.is_empty():
		ids = _scene.map.stations.keys()
	return _scene.map.stations[ids[n % ids.size()]]


## A dummy on seat `seat` of `st` (stood next to it first, like `MatchScene._autosit`).
func _sit_dummy(pid: int, st: StationBase, seat: int) -> void:
	var p: Vector3 = st.seat_position(seat)
	var out: Vector3 = p + (p - st.global_position).normalized() * 0.8
	out.y = st.global_position.y
	_place(pid, out, atan2(-(st.global_position.x - out.x), -(st.global_position.z - out.z)))
	_scene.server.submit_intent(pid, Intents.make(&"sit", {"station": _station_id(st)}))


func _station_id(st: StationBase) -> StringName:
	for k: StringName in _scene.map.stations:
		if _scene.map.stations[k] == st:
			return k
	return &""


## A brass-framed sign with `text` on a stand at `pos`, facing along `facing`.
func _sign(pos: Vector3, text: String, color: Color, facing: Vector3) -> void:
	var root := Node3D.new()
	_scene.pixel_view.world.add_child(root)
	root.global_position = Vector3(pos.x, 0.0, pos.z)
	root.look_at(root.global_position - facing, Vector3.UP)
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Palette.WARM_GOLD
	brass.metallic = 0.8
	brass.roughness = 0.35
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.035
	pm.bottom_radius = 0.035
	pm.height = 1.25
	pole.mesh = pm
	pole.material_override = brass
	pole.position = Vector3(0, 0.62, 0)
	root.add_child(pole)
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.95 if text.length() > 5 else 0.7, 0.36, 0.04)
	board.mesh = bm
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Palette.VIP_BURGUNDY
	board.material_override = wood
	board.position = Vector3(0, 1.38 + pos.y, 0)
	root.add_child(board)
	var frame := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = bm.size + Vector3(0.06, 0.06, -0.01)
	frame.mesh = fm
	frame.material_override = brass
	frame.position = board.position
	root.add_child(frame)
	var label := Label3D.new()
	label.text = text
	label.font_size = 96
	label.pixel_size = 0.0022
	label.modulate = color
	label.outline_size = 0
	label.position = board.position + Vector3(0, 0, 0.03)
	root.add_child(label)


## Two brass posts with a red velvet rope between them, across the way to the table.
func _velvet_rope(center: Vector3, side: Vector3, facing: Vector3) -> void:
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Palette.WARM_GOLD
	brass.metallic = 0.8
	brass.roughness = 0.35
	var velvet := StandardMaterial3D.new()
	velvet.albedo_color = Palette.CASINO_RED.darkened(0.25)
	velvet.roughness = 0.9
	var c: Vector3 = Vector3(center.x, 0.0, center.z)
	var ends: Array[Vector3] = [c - side * 1.1, c + side * 1.1]
	for e: Vector3 in ends:
		var post := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.045
		pm.bottom_radius = 0.06
		pm.height = 0.95
		post.mesh = pm
		post.material_override = brass
		_scene.pixel_view.world.add_child(post)
		post.global_position = e + Vector3(0, 0.475, 0)
		var base := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = 0.16
		bm.bottom_radius = 0.18
		bm.height = 0.05
		base.mesh = bm
		base.material_override = brass
		_scene.pixel_view.world.add_child(base)
		base.global_position = e + Vector3(0, 0.025, 0)
		var knob := MeshInstance3D.new()
		var km := SphereMesh.new()
		km.radius = 0.07
		km.height = 0.14
		knob.mesh = km
		knob.material_override = brass
		_scene.pixel_view.world.add_child(knob)
		knob.global_position = e + Vector3(0, 0.97, 0)
	var segs: int = 10  # the rope sags between the posts
	for i: int in segs:
		var t0: float = float(i) / segs
		var t1: float = float(i + 1) / segs
		var p0: Vector3 = ends[0].lerp(ends[1], t0) + Vector3(0, 0.86 - 0.22 * sin(PI * t0), 0)
		var p1: Vector3 = ends[0].lerp(ends[1], t1) + Vector3(0, 0.86 - 0.22 * sin(PI * t1), 0)
		var seg := MeshInstance3D.new()
		var sm := CylinderMesh.new()
		sm.top_radius = 0.035
		sm.bottom_radius = 0.035
		sm.height = p0.distance_to(p1) + 0.02
		seg.mesh = sm
		seg.material_override = velvet
		_scene.pixel_view.world.add_child(seg)
		seg.global_position = (p0 + p1) * 0.5
		var dir: Vector3 = (p1 - p0).normalized()
		seg.global_basis = Basis(Quaternion(Vector3.UP, dir))
	var _unused: Vector3 = facing


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


## A free camera inside the `PixelView` world (the match renders its 3D there).
## "x,y,z" as a Vector3 (`fallback` when empty or malformed).
static func _vec3(text: String, fallback: Vector3) -> Vector3:
	var parts: PackedStringArray = text.split(",")
	if parts.size() != 3:
		return fallback
	return Vector3(parts[0].to_float(), parts[1].to_float(), parts[2].to_float())


func _free_cam(pos: Vector3, look: Vector3, fov: float) -> void:
	_cam = Camera3D.new()
	_cam.fov = fov
	_cam.near = 0.05
	_scene.pixel_view.world.add_child(_cam)
	_cam.global_position = pos
	_cam.look_at(look, Vector3.UP)
	_cam.current = true
