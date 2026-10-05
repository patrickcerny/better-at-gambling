extends Node3D
## Dev: renders a blackjack table mid-round from seat 2's camera (screenshots of the dealt
## cards). Run with tools/screenshot.gd --scene res://tools/dev/blackjack_cards_shot.tscn.


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
	cam.global_transform = st.camera_for_seat(1).global_transform
	cam.current = true
	st.show_round({"state": BlackjackLogic.State.ACTING, "seats": [3, 1, 2, -1], "dealer_revealed": false, "dealer": [Card.make(10, 1)],
		"hands": {1: {"cards": [Card.make(1, 0), Card.make(9, 2)]}, 2: {"cards": [Card.make(13, 3), Card.make(5, 1), Card.make(4, 0)]}, 3: {"cards": [Card.make(7, 1), Card.make(7, 2)]}}})
