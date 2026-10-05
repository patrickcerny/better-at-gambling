extends Node3D
## Dev: the waiter NPC carrying his tray, a second one mid-trip next to his drink puddle, and the
## Megaphone stand by the bar, in the Lucky Lounge. Run with tools/screenshot.gd
## --scene res://tools/dev/waiter_shot.tscn (pass `-- --cam far` for the wide view).


func _ready() -> void:
	var map := LuckyLounge.new()
	map.bake_navmesh = false
	add_child(map)
	var walking := Waiter.new()
	add_child(walking)
	walking.global_position = Vector3(14.6, 0, 0.6)
	walking.yaw = deg_to_rad(20.0)
	walking.rotation.y = walking.yaw
	var tripped := Waiter.new()
	add_child(tripped)
	tripped.global_position = Vector3(16.6, 0, -1.2)
	tripped.yaw = deg_to_rad(120.0)
	tripped.rotation.y = tripped.yaw
	var puddle: Node3D = CasinoFloor.make_puddle(1)
	add_child(puddle)
	puddle.global_position = tripped.global_position + tripped.forward() * WaiterLogic.SPILL_AHEAD + Vector3(0, 0.015, 0)
	var floor_node := CasinoFloor.new()
	add_child(floor_node)
	floor_node._build_stand()
	var cam := Camera3D.new()
	add_child(cam)
	var far: bool = Cmdline.parse(OS.get_cmdline_user_args()).get_string("cam", "") == "far"
	cam.global_position = Vector3(12.0, 4.0, -7.0) if far else Vector3(13.4, 2.0, -4.2)
	cam.look_at(Vector3(15.5, 0.6, 0.5) if far else Vector3(15.4, 0.9, 0.6))
	cam.current = true
	await get_tree().create_timer(0.5).timeout
	tripped.trip()
