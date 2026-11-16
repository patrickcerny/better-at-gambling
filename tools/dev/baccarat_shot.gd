extends Node3D
## Dev: the baccarat table for screenshots: a finished round (Banker wins with three cards), chips on
## the spots, the scoreboard lit and a stand-in dealer. Run with
## scripts/screenshot.sh res://tools/dev/baccarat_shot.tscn baccarat 90 --view close|seat|wide

var _station: BaccaratStation


func _ready() -> void:
	var c: Cmdline = Cmdline.parse(OS.get_cmdline_user_args())
	var view: String = c.get_string("view", "close")
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
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.light_color = Color(1.0, 0.9, 0.75)
	sun.light_energy = 0.7
	sun.shadow_enabled = true
	add_child(sun)
	GreyboxKit.lamp(self, Vector3(-1.0, 3.4, 0.6), 1.0, 7.0)
	GreyboxKit.lamp(self, Vector3(1.0, 3.4, 0.6), 1.0, 7.0)
	var floor_mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	floor_mesh.mesh = pm
	floor_mesh.material_override = GreyboxKit.material(Palette.CASINO_RED.darkened(0.6))
	add_child(floor_mesh)
	Vfx.force_enabled = true
	_station = BaccaratStation.new()
	_station.station_id = &"baccarat_1"
	add_child(_station)
	var dealer := Dealer.new()
	dealer.puppet = false
	dealer.position_offset = DealerLogic.OFFSETS[&"baccarat"]
	dealer.yaw = DealerLogic.FACINGS[&"baccarat"]
	add_child(dealer)
	for spec: Array in [[0, &"player", 50], [0, &"tie", 10], [2, &"banker", 100], [3, &"player_pair", 10], [4, &"banker", 25]]:
		var stack: ChipStack = ChipStack.make(int(spec[2]), Palette.PLAYER_COLORS[int(spec[0])], 10)
		_station.add_child(stack)
		stack.position = BaccaratStation.bet_spot(int(spec[0]), spec[1])
	var hist: Array = [&"banker", &"banker", &"player", &"tie", &"banker", &"player", &"player", &"banker"]
	_station.show_round({"player_cards": [Card.make(3), Card.make(13, 1), Card.make(2, 2)], "banker_cards": [Card.make(4, 3), Card.make(1, 1), Card.make(2)],
		"player_total": 5, "banker_total": 7, "winner": c.get_string("winner", "banker"), "history": hist})
	var cam := Camera3D.new()
	cam.fov = 50.0
	add_child(cam)
	match view:
		"seat":
			cam.fov = 85.0  # the default (Settings "video/fov")
			cam.global_transform = _station.camera_for_seat(0).global_transform
		"wide":
			cam.position = Vector3(3.2, 3.4, 5.2)
			cam.look_at(Vector3(0, 0.6, 0))
		"seat2":
			cam.fov = 85.0  # the default (Settings "video/fov")
			cam.global_transform = _station.camera_for_seat(2).global_transform
		"seat4":
			cam.fov = 85.0  # the default (Settings "video/fov")
			cam.global_transform = _station.camera_for_seat(4).global_transform
		_:
			cam.position = Vector3(0.6, 2.2, 2.9)
			cam.look_at(Vector3(0.0, 0.9, 0.0))
	cam.current = true
