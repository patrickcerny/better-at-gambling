class_name RouletteStation
extends StationBase
## Roulette table: long red layout, wheel at one end, 6 stools around it.


func _build_visuals() -> void:
	game_id = &"roulette"
	seat_count = 6
	_rug(Vector2(7.0, 5.0), Palette.CASINO_RED.darkened(0.55))
	GreyboxKit.box(self, Vector3(4.2, 0.9, 1.8), Vector3(0.6, 0.45, 0), Color("#3A2A1E"), "Body")
	GreyboxKit.box(self, Vector3(2.6, 0.04, 1.5), Vector3(1.2, 0.92, 0), Palette.FELT_GREEN, "Layout", false)
	var wheel: Node3D = GreyboxKit.cylinder(self, 0.8, 0.2, Vector3(-1.3, 0.95, 0), Color("#5A3A22"), "Wheel", false)
	GreyboxKit.cylinder(wheel, 0.55, 0.06, Vector3(0, 0.12, 0), Palette.CASINO_RED, "WheelInner", false)
	GreyboxKit.sphere(self, 0.05, Vector3(-1.3, 1.12, 0.6), Palette.CREAM, "Ball")
	var spots: Array[Vector3] = [Vector3(-0.2, 0, 1.5), Vector3(1.0, 0, 1.5), Vector3(2.2, 0, 1.5), Vector3(-0.2, 0, -1.5), Vector3(1.0, 0, -1.5), Vector3(2.2, 0, -1.5)]
	for i: int in spots.size():
		_stool(spots[i], "Stool%d" % i)
		_add_seat(spots[i] + Vector3(0, 0.5, 0), 0.0 if spots[i].z > 0 else PI)
	camera_anchor = Node3D.new()
	camera_anchor.name = "CameraAnchor"
	camera_anchor.position = Vector3(1.0, 1.7, 1.9)
	camera_anchor.rotation.x = deg_to_rad(-35.0)
	add_child(camera_anchor)
