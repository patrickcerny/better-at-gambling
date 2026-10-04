class_name SlotsStation
extends StationBase
## Slot machine: tall cabinet with a screen, lever on the right, one stool.


func _build_visuals() -> void:
	game_id = &"slots"
	seat_count = 1
	interact_radius = 1.8
	GreyboxKit.box(self, Vector3(0.9, 1.9, 0.7), Vector3(0, 0.95, 0), Color("#2A1A2E"), "Cabinet")
	GreyboxKit.box(self, Vector3(0.7, 0.5, 0.05), Vector3(0, 1.35, 0.37), Palette.CASINO_BLACK, "Screen", false)
	GreyboxKit.box(self, Vector3(0.7, 0.3, 0.05), Vector3(0, 1.8, 0.37), Palette.WARM_GOLD, "Marquee", false)
	var lever: Node3D = GreyboxKit.cylinder(self, 0.03, 0.5, Vector3(0.55, 1.4, 0.1), Color("#8A8A8A"), "Lever", false, 0.6)
	GreyboxKit.sphere(lever, 0.07, Vector3(0, 0.27, 0), Palette.CASINO_RED, "Knob")
	GreyboxKit.cylinder(self, 0.22, 0.5, Vector3(0, 0.25, 0.9), Palette.CASINO_RED.darkened(0.3), "Stool")
	_add_seat(Vector3(0, 0.5, 0.9), 0.0)  # faces the cabinet (−z)
	camera_anchor = Node3D.new()
	camera_anchor.name = "CameraAnchor"
	camera_anchor.position = Vector3(0, 1.45, 1.0)
	camera_anchor.rotation.x = deg_to_rad(-8.0)
	add_child(camera_anchor)
