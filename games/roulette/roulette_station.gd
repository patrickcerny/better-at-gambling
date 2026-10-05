class_name RouletteStation
extends StationBase
## Roulette table: long red layout, Patrick's wheel model at one end, 6 stools around it.


func _build_visuals() -> void:
	game_id = &"roulette"
	seat_count = 6
	_rug(Vector2(7.0, 5.0), Palette.CASINO_RED.darkened(0.55))
	GreyboxKit.box(self, Vector3(4.2, 0.9, 1.8), Vector3(0.6, 0.45, 0), Color("#3A2A1E"), "Body")
	GreyboxKit.box(self, Vector3(2.6, 0.04, 1.5), Vector3(1.2, 0.92, 0), Palette.FELT_GREEN, "Layout", false)
	_add_wheel_model(Vector3(-1.3, 0.9, 0))
	var spots: Array[Vector3] = [Vector3(-0.2, 0, 1.5), Vector3(1.0, 0, 1.5), Vector3(2.2, 0, 1.5), Vector3(-0.2, 0, -1.5), Vector3(1.0, 0, -1.5), Vector3(2.2, 0, -1.5)]
	for i: int in spots.size():
		_stool(spots[i], "Stool%d" % i)
		_add_seat(spots[i] + Vector3(0, 0.5, 0), 0.0 if spots[i].z > 0 else PI)
	camera_anchor = Node3D.new()
	camera_anchor.name = "CameraAnchor"
	camera_anchor.position = Vector3(1.0, 1.7, 1.9)
	camera_anchor.rotation.x = deg_to_rad(-35.0)
	add_child(camera_anchor)


const WHEEL_MODEL: String = "res://assets/casino/roulette_table.fbx"


## Patrick's roulette wheel (native 4 m across with its own floor plane, camera and lights,
## which are dropped), scaled to 1.6 m and resting on the table at `pos`.
func _add_wheel_model(pos: Vector3) -> void:
	var ps: PackedScene = load(WHEEL_MODEL) as PackedScene
	if ps == null:
		return
	var model: Node3D = ps.instantiate()
	model.name = "Wheel"
	add_child(model)
	for n: Node in model.find_children("*", "", true, false):
		if n is Camera3D or n is Light3D or String(n.name) == "Plane":
			n.queue_free()
	model.scale = Vector3.ONE * 0.4
	model.position = pos + Vector3(0, 0.512 * 0.4, 0)  # its base sits 0.51 m below its origin
