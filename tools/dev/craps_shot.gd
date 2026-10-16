extends Node3D
## Dev: the craps table in the Lucky Lounge for screenshots. Run with
## scripts/screenshot.sh res://tools/dev/craps_shot.tscn craps 90 --pixel 1 --view floor|seat|dice
## [--at seconds] [--seed n] [--faces 6,1] [--point 6] (the dice frozen `--at` seconds into a seeded
## throw from seat 2 that rests on `--faces`; floor: the table and its stickman from the casino
## floor; seat: a stool's view; dice: a close-up of the dice where they come to rest).


func _ready() -> void:
	var c: Cmdline = Cmdline.parse(OS.get_cmdline_user_args())
	var view: String = c.get_string("view", "floor")
	var map := LuckyLounge.new()
	map.bake_navmesh = false
	add_child(map)
	for id: StringName in map.stations:
		var station: StationBase = map.stations[id]
		if not DealerLogic.OFFSETS.has(station.game_id):
			continue
		var dealer := Dealer.new()
		dealer.position_offset = station.global_position + (DealerLogic.OFFSETS[station.game_id] as Vector3).rotated(Vector3.UP, station.global_rotation.y)
		dealer.yaw = wrapf(station.global_rotation.y + float(DealerLogic.FACINGS[station.game_id]), -PI, PI)
		add_child(dealer)
		dealer.global_position = dealer.position_offset
	var cs: CrapsStation = map.stations[&"craps_1"] as CrapsStation
	var faces: Array = []
	for f: String in c.get_string("faces", "6,1").split(","):
		faces.append(int(f))
	cs.show_state({"state": CrapsLogic.State.BETTING, "point": c.get_int("point", 6), "dice": [], "throw_seed": -1})
	cs.throw(faces, c.get_int("seed", 4242), 2, c.get_float("at", 3.0))
	cs.get_node(^"DiceTicker").process_mode = Node.PROCESS_MODE_DISABLED  # frozen there
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.fov = 50.0
	match view:
		"seat":
			cam.fov = 75.0
			cam.global_transform = cs.camera_anchor.global_transform
		"dice":
			var mid: Vector3 = (cs.dice_nodes[0].global_position + cs.dice_nodes[1].global_position) * 0.5
			cam.fov = 35.0
			cam.global_position = mid + Vector3(0.15, 0.32, 0.42)
			cam.look_at(mid)
		_:
			cam.global_position = cs.global_position + Vector3(-3.4, 3.3, 5.2)
			cam.look_at(cs.global_position + Vector3(0.2, 0.7, -0.4))
