class_name StationBase
extends Node3D
## A station in the world: interaction area, seat transforms, camera anchor and placeholder
## visuals. Subclasses per game build their own visuals in `_build_visuals`.

@export var station_id: StringName
@export var game_id: StringName
@export var seat_count: int = 1
@export var interact_radius: float = 2.6
@export var is_vip: bool = false

## Seat transforms (world-space nodes).
var seats: Array[Node3D] = []
## Where the camera eases to while seated.
var camera_anchor: Node3D
var interaction_area: Area3D
var hot_light: OmniLight3D
## "OUT OF ORDER" sign (item) hung over the station; built on first use.
var out_of_order_sign: Label3D
## Seconds left on the sign (0 = open).
var out_of_order_left: float = 0.0


func _ready() -> void:
	add_to_group(&"stations")
	_build_visuals()
	if camera_anchor == null:
		camera_anchor = Node3D.new()
		camera_anchor.name = "CameraAnchor"
		camera_anchor.position = Vector3(0, 1.4, 1.6)
		add_child(camera_anchor)
	interaction_area = Area3D.new()
	interaction_area.name = "InteractionArea"
	interaction_area.collision_layer = 0
	interaction_area.collision_mask = 2  # players
	interaction_area.monitorable = true
	interaction_area.set_meta(&"station", self)
	var cs := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = interact_radius
	cs.shape = shape
	interaction_area.add_child(cs)
	add_child(interaction_area)
	hot_light = OmniLight3D.new()
	hot_light.light_color = Color(1.0, 0.5, 0.1)
	hot_light.light_energy = 0.0
	hot_light.omni_range = 6.0
	hot_light.position = Vector3(0, 2.5, 0)
	add_child(hot_light)


## Marks the station hot (spotlight) or not.
func set_hot(hot: bool) -> void:
	hot_light.light_energy = 6.0 if hot else 0.0


## World position of a seat (first seat by default).
func seat_position(index: int = 0) -> Vector3:
	if seats.is_empty():
		return global_position
	return seats[clampi(index, 0, seats.size() - 1)].global_position


## Shows or hides the Out of Order sign (`seconds` left, 0 = open).
func set_out_of_order(seconds: float) -> void:
	out_of_order_left = seconds
	if seconds <= 0.0:
		if out_of_order_sign != null:
			out_of_order_sign.visible = false
		return
	if out_of_order_sign == null:
		out_of_order_sign = Label3D.new()
		out_of_order_sign.name = "OutOfOrder"
		out_of_order_sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		out_of_order_sign.font_size = 72
		out_of_order_sign.pixel_size = 0.006
		out_of_order_sign.outline_size = 14
		out_of_order_sign.modulate = Palette.LOSS_RED
		out_of_order_sign.outline_modulate = Palette.CASINO_BLACK
		out_of_order_sign.position = Vector3(0, 2.3, 0)
		add_child(out_of_order_sign)
	out_of_order_sign.text = "OUT OF ORDER\n%ds" % ceili(seconds)
	out_of_order_sign.visible = true


## Interaction prompt text.
func prompt_text(min_bet: int) -> String:
	if out_of_order_left > 0.0:
		return "OUT OF ORDER (%ds)" % ceili(out_of_order_left)
	return "[E] Play %s — Min $%d" % [game_id.capitalize(), min_bet]


## Override: build meshes, `seats`, and `camera_anchor`.
func _build_visuals() -> void:
	pass


func _add_seat(local_pos: Vector3, yaw: float = 0.0) -> Node3D:
	var s := Node3D.new()
	s.name = "Seat%d" % seats.size()
	s.position = local_pos
	s.rotation.y = yaw
	add_child(s)
	seats.append(s)
	return s


func _rug(size: Vector2, color: Color) -> void:
	var mesh := PlaneMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.name = "Rug"
	mi.mesh = mesh
	mi.material_override = GreyboxKit.material(color)
	mi.position.y = 0.02
	add_child(mi)
