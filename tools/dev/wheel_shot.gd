extends Node3D
## Dev: the Wheel of Fortune for screenshots. Run with
## scripts/screenshot.sh res://tools/dev/wheel_shot.tscn wheel 90 --pixel 1 --view front|seat|close|back
## [--segment n] (the wheel at rest on segment n, chips on the layout; close: the clicker and the
## top of the wheel; back: as seen from the casino floor).

var _station: WheelStation


func _ready() -> void:
	var c: Cmdline = Cmdline.parse(OS.get_cmdline_user_args())
	var view: String = c.get_string("view", "front")
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
	GreyboxKit.lamp(self, Vector3(-2, 4.5, 1.5), 2.5, 12.0)
	GreyboxKit.lamp(self, Vector3(2, 4.5, 1.5), 2.5, 12.0)
	Vfx.force_enabled = true
	_station = WheelStation.new()
	_station.station_id = &"wheel_1"
	add_child(_station)
	_station.get_node(^"WheelTicker").process_mode = Node.PROCESS_MODE_DISABLED  # frozen where we put it
	_station.snap_to(c.get_int("segment", WheelLogic.LAYOUT.find(5)))
	_station.show_state({"state": WheelLogic.State.RESULT, "segment": _station.landed_segment, "history": [5, 0, 1, 0, 2, 3]})
	for b: Array in [[0, 40], [0, 20], [2, 25], [5, 10], [3, 50]]:
		var stack: ChipStack = ChipStack.make(int(b[1]), Palette.player_color(int(b[0]) % 8), 10)
		_station.add_child(stack)
		stack.position = WheelStation.bet_spot(int(b[0]))
	var cam := Camera3D.new()
	cam.fov = 50.0
	add_child(cam)
	match view:
		"seat":
			cam.fov = 75.0
			cam.global_transform = _station.camera_anchor.global_transform
		"close":
			var top: Vector3 = Vector3(0, WheelStation.WHEEL_Y + WheelStation.WHEEL_R, WheelStation.WHEEL_Z)
			cam.fov = 40.0
			cam.position = top + Vector3(0.5, -0.25, 1.4)
			cam.look_at(top + Vector3(0, -0.2, 0))
		"back":
			cam.position = Vector3(2.5, 2.8, -6.5)
			cam.look_at(Vector3(0, 2.0, -1.4))
		_:
			cam.position = Vector3(1.6, 2.4, 5.6)
			cam.look_at(Vector3(0, 1.7, -0.8))
	cam.current = true
