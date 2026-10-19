extends Node3D
## Dev: the Hi-Lo table for screenshots, three hands on the felt (one riding up the ladder) and a
## stand-in dealer. Run with
## scripts/screenshot.sh res://tools/dev/hilo_shot.tscn hilo 60 --view close|seat|wide

var _station: HiLoStation


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
	_station = HiLoStation.new()
	_station.station_id = &"hilo_1"
	add_child(_station)
	var dealer := Dealer.new()
	dealer.puppet = false
	dealer.position_offset = DealerLogic.OFFSETS[&"hilo"]
	dealer.yaw = DealerLogic.FACINGS[&"hilo"]
	add_child(dealer)
	var hands: Dictionary = {
		1: {"stake": 20, "cards": [Card.make(5), Card.make(9, 1), Card.make(3, 2)], "phase": "play", "rung": 2, "pot": 77, "outcome": ""},
		2: {"stake": 10, "cards": [Card.make(12, 3)], "phase": "play", "rung": 0, "pot": 10, "outcome": ""},
		3: {"stake": 50, "cards": [Card.make(8), Card.make(1, 1)], "phase": "done", "rung": 1, "pot": 99, "outcome": "cashed"},
	}
	_station.show_round({"seats": [1, 2, -1, 3], "hands": hands, "deck_left": 33})
	var cam := Camera3D.new()
	cam.fov = 50.0
	add_child(cam)
	match view:
		"seat":
			cam.fov = 75.0
			cam.global_transform = _station.camera_for_seat(0).global_transform
		"wide":
			cam.position = Vector3(3.2, 3.4, 5.2)
			cam.look_at(Vector3(0, 0.6, 0))
		_:
			cam.position = Vector3(0.9, 2.1, 2.6)
			cam.look_at(Vector3(-0.1, 0.9, 0.0))
	cam.current = true
