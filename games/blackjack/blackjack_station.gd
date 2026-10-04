class_name BlackjackStation
extends StationBase
## Half-moon blackjack table: green felt, dark wood rim, 4 seats on the curved side, dealer opposite.


func _build_visuals() -> void:
	game_id = &"blackjack"
	seat_count = 4
	_rug(Vector2(5.5, 5.0), Palette.FELT_GREEN.darkened(0.5))
	GreyboxKit.cylinder(self, 1.7, 0.12, Vector3(0, 0.85, 0), Color("#3A2A1E"), "Rim")
	GreyboxKit.cylinder(self, 1.55, 0.14, Vector3(0, 0.86, 0), Palette.FELT_GREEN, "Felt", false)
	GreyboxKit.cylinder(self, 0.25, 0.8, Vector3(0, 0.4, 0), Color("#3A2A1E"), "Leg")
	# Dealer spot (north side), chip rack.
	GreyboxKit.box(self, Vector3(0.9, 0.08, 0.25), Vector3(0, 0.98, -1.1), Color("#1E1B19"), "ChipRack", false)
	for i: int in seat_count:
		var angle: float = deg_to_rad(-45.0 + 30.0 * i)  # fan on the south side
		var pos: Vector3 = Vector3(sin(angle) * 2.2, 0.0, cos(angle) * 2.2)
		GreyboxKit.cylinder(self, 0.22, 0.5, pos + Vector3(0, 0.25, 0), Palette.CASINO_RED.darkened(0.3), "Stool%d" % i)
		_add_seat(pos + Vector3(0, 0.5, 0), angle)  # yaw = angle looks at the table centre
	camera_anchor = Node3D.new()
	camera_anchor.name = "CameraAnchor"
	camera_anchor.position = Vector3(0, 1.45, 2.3)
	camera_anchor.rotation.x = deg_to_rad(-25.0)
	add_child(camera_anchor)
