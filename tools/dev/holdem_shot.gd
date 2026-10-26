extends Node3D
## Dev: the Casino Hold'em table for screenshots: three hands after the flop (one deciding, one
## called, one folded), the dealer's two face down and a stand-in dealer; `--showdown` turns the
## turn, the river and the dealer's cards over. Run with
## scripts/screenshot.sh res://tools/dev/holdem_shot.tscn holdem 60 --view close|seat|wide [--seat N] [--showdown]

var _station: HoldemStation


func _ready() -> void:
	var c: Cmdline = Cmdline.parse(OS.get_cmdline_user_args())
	var view: String = c.get_string("view", "close")
	var seat: int = clampi(c.get_int("seat", 1), 0, 3)
	var showdown: bool = c.has_flag("showdown")
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
	_station = HoldemStation.new()
	_station.station_id = &"holdem_1"
	add_child(_station)
	var dealer := Dealer.new()
	dealer.puppet = false
	dealer.position_offset = DealerLogic.OFFSETS[&"holdem"]
	dealer.yaw = DealerLogic.FACINGS[&"holdem"]
	add_child(dealer)
	var hands: Dictionary = {
		1: {"ante": 20, "bonus": 10, "hole": [Card.make(1), Card.make(1, 1)], "decision": &"call" if showdown else &"", "hand": "Pair of Aces", "clock": 12.0, "call": 40 if showdown else 0},
		2: {"ante": 10, "hole": [Card.make(12, 3), Card.make(11, 3)], "decision": &"call", "hand": "Queen High", "call": 20},
		3: {"ante": 50, "hole": [Card.make(2, 2), Card.make(7)], "decision": &"fold", "hand": "Ace High", "outcome": &"fold"},
	}
	var pub: Dictionary = {
		"game": &"holdem", "state": HoldemLogic.State.DECIDING, "seats": [2, 1, -1, 3], "hands": hands,
		"board": [Card.make(1, 3), Card.make(9, 1), Card.make(4, 2)], "dealer": [], "dealer_down": 2,
	}
	if showdown:
		pub["state"] = HoldemLogic.State.PAYOUT
		(pub["board"] as Array).append_array([Card.make(13, 2), Card.make(4)])
		pub["dealer"] = [Card.make(4, 1), Card.make(10, 3)]
		pub["dealer_down"] = 0
		pub["dealer_hand"] = "Three of a Kind, Fours"
		pub["qualifies"] = true
		hands[1]["hand"] = "Two Pair, Aces and Fours"
		hands[1]["outcome"] = &"lose"
		hands[2]["outcome"] = &"lose"
	_station.set_viewer_seat(seat)
	_station.show_round(pub)
	var cam := Camera3D.new()
	cam.fov = 50.0
	add_child(cam)
	match view:
		"seat":
			cam.fov = 85.0  # the default (Settings "video/fov")
			cam.global_transform = _station.camera_for_seat(seat).global_transform
		"wide":
			cam.position = Vector3(3.6, 3.6, 5.6)
			cam.look_at(Vector3(0, 0.6, 0))
		_:
			cam.position = Vector3(0.4, 2.4, 2.9)
			cam.look_at(Vector3(0.0, 0.9, -0.1))
	cam.current = true
