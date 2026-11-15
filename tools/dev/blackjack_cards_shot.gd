extends Node3D
## Dev: renders a blackjack table mid-round from a seat's camera (screenshots of the dealt
## cards). Run with tools/screenshot.gd --scene res://tools/dev/blackjack_cards_shot.tscn
## [--seat 0-3] (default seat 2, index 1) [--fov 70-110] [--ui] (the blackjack panel over it, to
## check that no hand sits under it).


func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Palette.CASINO_BLACK
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(1.0, 0.9, 0.8)
	env.environment.ambient_light_energy = 0.7
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, 20, 0)
	add_child(sun)
	var st := BlackjackStation.new()
	add_child(st)
	var cam := Camera3D.new()
	add_child(cam)
	var args: Cmdline = Cmdline.parse(OS.get_cmdline_user_args())
	var seat: int = clampi(args.get_int("seat", 1), 0, 3)
	cam.global_transform = st.camera_for_seat(seat).global_transform
	cam.current = true
	cam.fov = args.get_float("fov", 85.0)  # the game's default
	st.set_viewer_seat(seat)
	# Seat 2 (index 1, the default view) split and plays its second hand; seat 1 split and plays
	# its first; seat 3 never split.
	st.show_round({"state": BlackjackLogic.State.ACTING, "seats": [3, 1, 2, 4], "dealer_revealed": false, "dealer": [Card.make(10, 1)],
		"hands": {1: {"stake": 50, "done": false, "active": 1, "cards": [Card.make(8, 0), Card.make(3, 2), Card.make(9, 1)], "split": {"stake": 50, "cards": [Card.make(8, 2), Card.make(13, 3)]}},
			2: {"stake": 20, "done": false, "cards": [Card.make(13, 3), Card.make(5, 1), Card.make(4, 0)]},
			3: {"stake": 30, "done": false, "active": 0, "cards": [Card.make(7, 1), Card.make(4, 2), Card.make(6, 3)], "split": {"stake": 30, "cards": [Card.make(7, 2)]}},
			4: {"stake": 40, "done": false, "active": 1, "cards": [Card.make(9, 0), Card.make(2, 1), Card.make(5, 2)], "split": {"stake": 40, "cards": [Card.make(9, 3), Card.make(12, 0), Card.make(2, 2)]}}}})
	if args.has_flag("ui"):
		var layer := CanvasLayer.new()
		add_child(layer)
		var ui: BlackjackUi = (load("res://ui/stations/blackjack_ui.tscn") as PackedScene).instantiate()
		ui.theme = load("res://ui/theme/main_theme.tres") as Theme
		layer.add_child(ui)
		ui.open(&"blackjack_1", 4, null)
		ui.update_state({"state": BlackjackLogic.State.ACTING, "timer": 7.2, "seats": [3, 1, 2, 4], "dealer": [Card.make(10, 1)], "dealer_revealed": false,
			"hands": {4: {"stake": 40, "cards": [Card.make(9, 0), Card.make(2, 1), Card.make(5, 2)], "done": false, "total": 16, "active": 1,
				"split": {"stake": 40, "cards": [Card.make(9, 3), Card.make(12, 0), Card.make(2, 2)], "done": false, "total": 21}}}}, {})
