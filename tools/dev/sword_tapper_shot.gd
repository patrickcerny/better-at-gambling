extends Node3D
## Dev: a Sword Tapper pedestal for screenshots. Run with
## scripts/screenshot.sh res://tools/dev/sword_tapper_shot.tscn sword 90 --view front|seat|close|floor
## [--free 0|1] [--gems n] [--mult m] [--at seconds] [--stake n] [--column 1]
## The pull is frozen `at` seconds into its reveal (default: the end, every gem lit). seat: the
## seat camera with the bean at the pedestal and the overlay column on the right; close: the ring
## from above; floor: as seen from across the casino floor (with --column 1, the big-win column).
## match: the real match scene under the casino's own lights: the local player steps up to sword_1,
## pulls, and `--shot out.png` is saved `--at` seconds after the tap (run with --frames 100000).

var _station: SwordTapperStation
var _scene: MatchScene
var _t: float = 0.0
var _pulled_at: float = -1.0
var _at: float = 2.6
var _shot: String = ""


func _ready() -> void:
	var c: Cmdline = Cmdline.parse(OS.get_cmdline_user_args())
	var view: String = c.get_string("view", "front")
	if view == "match":
		_at = c.get_float("at", 2.6)
		_shot = c.get_string("shot", "build/screenshots/sword_match.png")
		_scene = (load("res://match/match_scene.tscn") as PackedScene).instantiate()
		add_child(_scene)
		return
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Palette.WARM_CHARCOAL
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(1.0, 0.88, 0.75)
	env.environment.ambient_light_energy = 0.55
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment.glow_enabled = true
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_color = Color(1.0, 0.9, 0.75)
	sun.light_energy = 0.8
	sun.shadow_enabled = true
	add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	floor_mesh.mesh = pm
	floor_mesh.material_override = GreyboxKit.material(Palette.CASINO_RED.darkened(0.6))
	add_child(floor_mesh)
	GreyboxKit.lamp(self, Vector3(-1.2, 3.6, 1.2), 1.0, 7.0)
	GreyboxKit.lamp(self, Vector3(1.2, 3.6, 1.2), 1.0, 7.0)
	Vfx.force_enabled = true
	_station = SwordTapperStation.new()
	_station.station_id = &"sword_1"
	add_child(_station)
	_station.get_node(^"SwordTicker").process_mode = Node.PROCESS_MODE_DISABLED  # frozen where we put it
	var free: bool = c.get_int("free", 1) == 1
	var n: int = clampi(c.get_int("gems", 7), SwordTapperLogic.MIN_GEMS, SwordTapperLogic.RING_SIZE)
	var order: Array[int] = [0, 2, 3, 5, 8, 9, 11, 12, 13, 14, 15, 16, 1, 4, 6, 7, 10]
	var gems: Array[int] = order.slice(0, n)
	gems.sort()
	var stake: int = c.get_int("stake", 25)
	var ev: Dictionary = {"serial": 1, "stake": stake, "free": free, "gems": gems if free else [], "mult": c.get_int("mult", 3 if n <= 9 else 1)}
	var at: float = c.get_float("at", Registry.balance.sword_reveal_time)
	_station.play_pull(ev, true, at)
	if c.get_int("column", 0) == 1:
		_station.big_win_column()
	var bean := AvatarVisuals.new()
	add_child(bean)
	bean.position = _station.seat_position(0)
	bean.set_color(Palette.player_color(0))
	var cam := Camera3D.new()
	cam.fov = 50.0
	add_child(cam)
	match view:
		"seat":
			bean.visible = false  # your own bean (and its crown) is hidden in the seat view
			cam.fov = 85.0
			cam.global_transform = _station.camera_for_seat(0).global_transform
			_overlay(stake)
		"close":
			cam.fov = 45.0
			cam.position = Vector3(0, 3.0, 1.1)
			cam.look_at(Vector3(0, SwordTapperStation.TOP_Y, 0))
		"floor":
			cam.position = Vector3(4.5, 3.2, 9.0)
			cam.look_at(Vector3(0, 2.2, 0))
		_:
			bean.visible = false
			cam.position = Vector3(1.2, 2.0, 3.4)
			cam.look_at(Vector3(0, 1.1, 0))
	cam.current = true


## Match view: step up at 3.5 s, pull at 4 s, save the shot `_at` seconds later.
func _process(delta: float) -> void:
	if _scene == null or _scene.server == null or _scene.local == null:
		return
	_t += delta
	var st: StationBase = _scene.map.stations.get(&"sword_1", null)
	if st == null:
		return
	if _t > 3.5 and _scene.current_ui == null and _pulled_at < 0.0:
		var spot: Vector3 = st.to_global(Vector3(0, 0, 1.25)) * Vector3(1, 0, 1)
		_scene.local.teleport(spot, st.global_rotation.y)
		_scene.server.set_server_position(_scene.local_id, spot)
		Net.send_intent(Intents.make(&"sit", {"station": &"sword_1"}))
	elif _t > 4.0 and _pulled_at < 0.0 and _scene.current_ui is SwordTapperUi:
		(_scene.current_ui as SwordTapperUi).pull()
		_pulled_at = _t
	elif _pulled_at >= 0.0 and _t - _pulled_at >= _at and _shot != "":
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png(_shot)
		print("sword tapper shot %s" % _shot)
		_shot = ""
		get_tree().quit(0)


## The overlay over the seat view, as at the pedestal: the last pull's result and a few past pulls.
func _overlay(stake: int) -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var ui := SwordTapperUi.new()
	layer.add_child(ui)
	var st := ClientMatchState.new()
	st.players[1] = {"name": "Ada", "color": 0}
	st.balances[1] = 1000
	var history: Array = [{"free": true, "gems": 7, "mult": 3, "stake": stake, "returned": 445}, {"free": false, "gems": 0, "mult": 1, "stake": stake, "returned": 0},
		{"free": false, "gems": 0, "mult": 1, "stake": stake, "returned": 0}, {"free": true, "gems": 4, "mult": 1, "stake": stake, "returned": 20}]
	st.stations[&"sword_1"] = {"game": &"sword_tapper", "player": 1, "pulling": false, "pull": {}, "stake": 0, "serial": 0, "reveal_left": 0.0, "last": {}, "history": history}
	ui.open(&"sword_1", 1, st)
	var pub: Dictionary = (st.stations[&"sword_1"] as Dictionary).duplicate(true)
	pub["serial"] = 1
	pub["last"] = {"pull": {"free": true, "gems": [0, 3, 8, 9, 12, 14, 16], "mult": 3}, "stake": stake, "returned": 445, "serial": 1}
	ui.update_state(pub, {})
