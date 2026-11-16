extends Node3D
## Dev: the roulette table in the Lucky Lounge with a bean on every stool but yours. Run with
## scripts/screenshot.sh res://tools/dev/roulette_shot.tscn roulette 60 --view seat|floor [--seat n]
## [--ui]: seat = stool `--seat n`'s view at the default field of view (85°), `--ui` adds the
## docked betting panel; floor = the table from the casino floor.


func _ready() -> void:
	var c: Cmdline = Cmdline.parse(OS.get_cmdline_user_args())
	var map := LuckyLounge.new()
	map.bake_navmesh = false
	add_child(map)
	var rs: RouletteStation = map.stations[&"roulette_1"] as RouletteStation
	var mine: int = c.get_int("seat", 0)
	for i: int in rs.seats.size():
		if i == mine and c.get_string("view", "seat") == "seat":
			continue  # our own body is hidden in the seated view
		var bean := AvatarVisuals.new()
		add_child(bean)
		bean.set_color(Palette.player_color(i + 1))
		bean.sitting = true
		bean.global_position = rs.seat_position(i)
		bean.rotation.y = rs.seats[i].global_rotation.y
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	match c.get_string("view", "seat"):
		"seat":
			cam.fov = 85.0
			cam.global_transform = rs.camera_for_seat(mine).global_transform
			if c.has("ui"):
				_overlay()
		_:
			cam.fov = 50.0
			cam.global_position = rs.global_position + Vector3(-4.5, 4.0, 5.5)
			cam.look_at(rs.global_position + Vector3(0, 0.7, 0))


func _overlay() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var ui := RouletteUi.new()
	layer.add_child(ui)
	var st := ClientMatchState.new()
	st.players[1] = {"name": "Ada", "color": 0}
	st.balances[1] = 1000
	st.stations[&"roulette_1"] = {"game": &"roulette", "state": RouletteLogic.State.BETTING, "timer": 8.0, "players": [1], "bets": [], "result": -1, "history": []}
	ui.open(&"roulette_1", 1, st)
