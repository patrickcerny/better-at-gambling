class_name BlackjackStation
extends StationBase
## Half-moon blackjack table (Patrick's model, flat casino colors since its textures did not come
## along): green felt, padded rail, gold legs, 4 seats on the curved side, dealer on the straight one.


func _build_visuals() -> void:
	game_id = &"blackjack"
	seat_count = 4
	_round_rug(4.8)
	# Collision stays a simple cylinder; Patrick's half-moon table model is what you see.
	var rim: Node3D = GreyboxKit.cylinder(self, 1.7, 0.9, Vector3(0, 0.45, 0), Color("#3A2A1E"), "Rim")
	(rim.get_node(^"Mesh") as Node3D).visible = false
	_add_table_model()
	# Dealer spot (north side, the straight edge), chip rack.
	GreyboxKit.box(self, Vector3(0.9, 0.08, 0.25), Vector3(0, 0.96, -0.2), Color("#1E1B19"), "ChipRack", false)
	for i: int in seat_count:
		var angle: float = deg_to_rad(-45.0 + 30.0 * i)  # fan on the south side
		var pos: Vector3 = Vector3(sin(angle) * 2.2, 0.0, cos(angle) * 2.2)
		_stool(pos, "Stool%d" % i)
		_add_seat(pos + Vector3(0, 0.5, 0), angle)  # yaw = angle looks at the table centre
	camera_anchor = Node3D.new()
	camera_anchor.name = "CameraAnchor"
	camera_anchor.position = Vector3(0, 1.45, 2.3)
	camera_anchor.rotation.x = deg_to_rad(-25.0)
	add_child(camera_anchor)


const TABLE_MODEL: String = "res://assets/casino/blackjack_table.dae"
## Flat colors per part of the model (its texture files were not included).
const TABLE_COLORS: Dictionary = {
	"Table top": Color("#275E49"), "arm rest (for players)": Color("#681F2C"), "Rubber pad strip": Color("#151414"),
}


func _add_table_model() -> void:
	var ps: PackedScene = load(TABLE_MODEL) as PackedScene
	if ps == null:
		return
	var model: Node3D = ps.instantiate()
	model.name = "Table"
	# Native: 2.24 m across, straight edge on z = 0, curved side towards +z, top at ~0.97 m.
	model.scale = Vector3(1.7, 0.95, 1.7)
	model.position = Vector3(0, 0, -0.4)
	add_child(model)
	for n: Node in model.find_children("*", "", true, false):
		if n is Camera3D or n is Light3D:
			n.queue_free()
		elif n is MeshInstance3D:
			var c: Color = TABLE_COLORS.get(String(n.name), Palette.WARM_GOLD)
			(n as MeshInstance3D).material_override = GreyboxKit.gold() if c == Palette.WARM_GOLD else GreyboxKit.material(c, 0.0, 0.7)
