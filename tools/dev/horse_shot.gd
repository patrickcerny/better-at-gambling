extends Node3D
## Dev: the horse race miniatures for screenshots. Run with
## scripts/screenshot.sh res://tools/dev/horse_shot.tscn horse 90 --pixel 1 --view side|field|front|track|seat
## [--at seconds] (track/seat: the race table running a seeded race, frozen `--at` seconds in).

var _view: String = "side"
var _station: HorseRaceStation


func _ready() -> void:
	var c: Cmdline = Cmdline.parse(OS.get_cmdline_user_args())
	_view = c.get_string("view", "side")
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
	var cam := Camera3D.new()
	cam.fov = 50.0
	add_child(cam)
	match _view:
		"track", "seat":
			GreyboxKit.lamp(self, Vector3(-2, 4.5, 0), 2.5, 12.0)
			GreyboxKit.lamp(self, Vector3(2, 4.5, 0), 2.5, 12.0)
			Vfx.force_enabled = true
			_station = HorseRaceStation.new()
			_station.station_id = &"horse_race_1"
			add_child(_station)
			_station.show_state({"state": HorseRaceLogic.State.BETTING, "names": ["Lucky Seven", "Bean Lightning", "Sir Trots-a-Lot", "Hoof Hearted"], "race_seed": -1})
			var at: float = c.get_float("at", 4.0)
			_station.start_race(4242, at)
			if _view == "seat":
				cam.fov = 75.0
				cam.global_transform = _station.camera_anchor.global_transform
			else:
				cam.position = Vector3(1.0, 3.2, 6.2)
				cam.look_at(Vector3(0.3, 0.8, 0))
		"field":
			for i: int in 4:
				var h := HorseModel.new([&"chestnut", &"grey", &"bay", &"black"][i], HorseRaceStation.LANE_COLORS[i], i)
				h.position = Vector3(i * 0.35 - 0.5, 0, i * -0.9)
				h.rotation.y = -PI * 0.5
				h.set_running(1.0 if i > 0 else 0.0)
				h.gallop = h.target_gallop
				add_child(h)
			cam.position = Vector3(1.2, 2.2, 5.0)
			cam.look_at(Vector3(0.6, 1.0, -1.2))
		"front":
			var h := HorseModel.new(&"palomino", HorseRaceStation.LANE_COLORS[1], 1)
			add_child(h)
			cam.position = Vector3(1.6, 2.0, -3.6)
			cam.look_at(Vector3(0, 1.2, -0.2))
		_:
			var h := HorseModel.new(&"chestnut", HorseRaceStation.LANE_COLORS[0], 0)
			h.set_running(c.get_float("gallop", 0.0))
			h.gallop = h.target_gallop
			add_child(h)
			cam.position = Vector3(4.2, 1.5, -0.4)
			cam.look_at(Vector3(0, 1.15, -0.3))
	cam.current = true
