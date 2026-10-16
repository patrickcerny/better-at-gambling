extends Node3D
## Dev: the waiting room behind the start room (play-money blackjack and slots) in the Lucky
## Lounge. Run with tools/screenshot.gd --scene res://tools/dev/waiting_room_shot.tscn and
## `-- --view door` (from the start room through the open door, the default), `--view table` (the
## blackjack table close up), `--view room` (the whole room from a front corner) or `--view shut`
## (the locked door from the start room once the match is on).


func _ready() -> void:
	var map := LuckyLounge.new()
	map.bake_navmesh = false
	add_child(map)
	var cam_name: String = Cmdline.parse(OS.get_cmdline_user_args()).get_string("view", "door")
	map.set_waiting_room_open(cam_name != "shut")
	# A few beans: one at the table, one at a slot, one walking in.
	var bj: StationBase = map.stations[&"fun_blackjack_1"]
	var slot: StationBase = map.stations[&"fun_slot_1"]
	var spots: Array = [
		[bj.seat_position(1) - Vector3(0, 0.5, 0), bj.global_rotation.y + deg_to_rad(-15.0)],
		[slot.seat_position(0) - Vector3(0, 0.5, 0), slot.global_rotation.y],
		[Vector3(0.9, 0, 17.4), PI],
	]
	for i: int in spots.size():
		var bean := AvatarVisuals.new()
		add_child(bean)
		bean.set_color(Palette.player_color(i + 1))
		bean.global_position = spots[i][0]
		bean.rotation.y = spots[i][1]
	var dealer := Dealer.new()
	dealer.position_offset = bj.global_position + (DealerLogic.OFFSETS[&"blackjack"] as Vector3).rotated(Vector3.UP, bj.global_rotation.y)
	dealer.yaw = wrapf(bj.global_rotation.y + float(DealerLogic.FACINGS[&"blackjack"]), -PI, PI)
	add_child(dealer)
	var cam := Camera3D.new()
	add_child(cam)
	match cam_name:
		"table":
			cam.global_position = Vector3(1.8, 2.2, 17.4)
			cam.look_at(Vector3(0, 0.9, 20.9))
		"room":
			cam.global_position = Vector3(-4.7, 3.4, 16.8)
			cam.look_at(Vector3(1.5, 0.8, 21.2))
		_:
			cam.global_position = Vector3(0.0, 1.9, 10.5)
			cam.look_at(Vector3(0, 1.6, 20.0))
	cam.fov = 70.0
	cam.current = true
