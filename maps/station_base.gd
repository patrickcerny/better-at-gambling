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
## Per-seat views (stations that seat you at your own spot); empty = everyone uses `camera_anchor`.
var seat_cameras: Array[Node3D] = []
var interaction_area: Area3D
var hot_light: OmniLight3D
## Bouncing arrow over the hot table, drawn on top of everything (through walls) so it reads across
## the floor, and always the same size on screen (Patrick: "a bit too big. Make it always the same
## size, wall see through is good"): `hot_marker_scale` follows the camera's distance and FOV.
var hot_marker: Node3D
## "HOT ×1.25" over the arrow.
var hot_label: Label3D
const HOT_MARKER_Y: float = 4.2
## The arrow's height (tip to tail, `HOT_ARROW_LENGTH` m at scale 1) as a share of the screen height.
const HOT_MARKER_SCREEN: float = 0.12
const HOT_ARROW_LENGTH: float = 1.5
## Bounce height in arrow lengths.
const HOT_MARKER_BOUNCE: float = 0.35
## Hot right now (the server says so).
var hot: bool = false
## The marker is drawn on top of everything, so it would show through a minigame room's walls:
## the match scene hides it while a stage is open (Patrick: "clear the hot marker when you are in
## minigames") and the table stays hot underneath.
var hot_marker_hidden: bool = false
## Spotlight cone, embers and sparks while hot (client only, built on first use).
var hot_fx: HotTableFx
## Middle of the table's footprint (local) for the hot spotlight and fire ring.
var hot_center: Vector3 = Vector3.ZERO
var _hot_time: float = 0.0
## "OUT OF ORDER" sign (item) hung over the station; built on first use.
var out_of_order_sign: Label3D
## Traffic cones on the seats while the station is out of order.
var out_of_order_cones: Node3D
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


## Spotlight energy while hot. Card tables use less so the cards don't bloom (see BlackjackStation).
func hot_light_energy() -> float:
	return 6.0


## Marks the station hot (spotlight and bouncing arrow) or not.
func set_hot(is_hot: bool) -> void:
	hot = is_hot
	hot_light.light_energy = hot_light_energy() if hot else 0.0
	if hot and hot_fx == null and Vfx.enabled():
		hot_fx = HotTableFx.new()
		hot_fx.radius = interact_radius * 0.8
		hot_fx.position = hot_center
		add_child(hot_fx)
	if hot_fx != null:
		hot_fx.set_on(hot)
	if hot and hot_marker == null:
		_build_hot_marker()
	if hot_marker != null:
		hot_marker.visible = hot and not hot_marker_hidden
	set_process(hot)


## Hides the arrow and label while a minigame stage is on screen (they draw through its walls);
## shows them again afterwards if the table is still hot.
func set_hot_marker_hidden(hidden: bool) -> void:
	hot_marker_hidden = hidden
	if hot_marker != null:
		hot_marker.visible = hot and not hidden


func _process(delta: float) -> void:
	if hot_marker != null and hot_marker.visible:
		_hot_time += delta
		hot_marker.rotation.y += delta * 1.5
		var k: float = 1.0
		var cam: Camera3D = get_viewport().get_camera_3d()
		if cam != null:
			k = hot_marker_scale(cam.global_position.distance_to(global_position + Vector3(0, HOT_MARKER_Y, 0)), cam.fov)
		hot_marker.scale = Vector3.ONE * k
		# The label is `fixed_size` (already the same on screen): undo the marker's scale for it.
		hot_label.scale = Vector3.ONE / k
		# The bounce scales too, so it looks the same from anywhere.
		hot_marker.position.y = HOT_MARKER_Y + absf(sin(_hot_time * 4.0)) * HOT_MARKER_BOUNCE * HOT_ARROW_LENGTH * k


## Scale for the arrow seen from `distance` metres with a vertical `fov_deg`, so it covers
## `HOT_MARKER_SCREEN` of the screen's height wherever the camera is.
static func hot_marker_scale(distance: float, fov_deg: float) -> float:
	var view_h: float = 2.0 * maxf(distance, 0.5) * tan(deg_to_rad(fov_deg) * 0.5)
	return HOT_MARKER_SCREEN * view_h / HOT_ARROW_LENGTH


func _build_hot_marker() -> void:
	hot_marker = Node3D.new()
	hot_marker.name = "HotMarker"
	hot_marker.position.y = HOT_MARKER_Y
	add_child(hot_marker)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.55, 0.1)
	mat.no_depth_test = true
	mat.render_priority = 10
	var head := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.55
	cone.height = 0.7
	head.mesh = cone
	head.material_override = mat
	head.rotation.x = PI  # point down at the table
	head.position.y = 0.35
	hot_marker.add_child(head)
	var shaft := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.32, 0.8, 0.32)
	shaft.mesh = box
	shaft.material_override = mat
	shaft.position.y = 1.1
	hot_marker.add_child(shaft)
	hot_label = Label3D.new()
	hot_label.name = "HotLabel"
	hot_label.text = "HOT ×%.2f" % Registry.balance.hot_table_multiplier
	hot_label.font_size = 64
	hot_label.pixel_size = 0.0009
	hot_label.fixed_size = true  # same size on screen from anywhere on the floor
	hot_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hot_label.no_depth_test = true
	hot_label.modulate = Palette.VIP_GOLD
	hot_label.outline_modulate = Palette.CASINO_BLACK
	hot_label.outline_size = 18
	hot_label.position.y = 2.0
	hot_marker.add_child(hot_label)


## The camera view for a seat.
func camera_for_seat(index: int) -> Node3D:
	return seat_cameras[index] if index >= 0 and index < seat_cameras.size() else camera_anchor


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
			out_of_order_cones.visible = false
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
		out_of_order_cones = Node3D.new()
		out_of_order_cones.name = "Cones"
		add_child(out_of_order_cones)
		for s: Node3D in seats:
			var cone: Node3D = PropModels.make(&"cone", 0.75)
			cone.position = Vector3(s.position.x, 0.0, s.position.z) + s.transform.basis.z * 0.5
			out_of_order_cones.add_child(cone)
	out_of_order_cones.visible = true
	out_of_order_sign.text = "OUT OF ORDER\n%ds" % ceili(seconds)
	out_of_order_sign.visible = true


## Interaction prompt text.
func prompt_text(min_bet: int) -> String:
	if out_of_order_left > 0.0:
		return "OUT OF ORDER (%ds)" % ceili(out_of_order_left)
	return "%s Play %s — Min $%d" % [InputGlyphs.hint(&"interact"), game_id.capitalize(), min_bet]


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


## A seat's own view: a camera anchor at `eye` (local) looking at `aim` (local), no roll, added to
## `seat_cameras` (the player camera reads its pitch and yaw as the middle of the seated head turn).
func _add_seat_camera(eye: Vector3, aim: Vector3) -> Node3D:
	var a := Node3D.new()
	a.name = "SeatCamera%d" % seat_cameras.size()
	a.position = eye
	a.rotation = look_rotation(eye, aim)
	add_child(a)
	seat_cameras.append(a)
	return a


## Euler rotation (pitch, yaw, no roll) of a view from `eye` towards `aim`.
static func look_rotation(eye: Vector3, aim: Vector3) -> Vector3:
	var look: Vector3 = aim - eye
	return Vector3(atan2(look.y, Vector2(look.x, look.z).length()), atan2(-look.x, -look.z), 0.0)


## A bar stool (Patrick's model, collision kept from the greybox cylinder) with its seat on top.
func _stool(local_pos: Vector3, name: String = "Stool") -> void:
	var solid: Node3D = GreyboxKit.cylinder(self, 0.22, 0.5, local_pos + Vector3(0, 0.25, 0), Palette.CASINO_RED.darkened(0.3), name)
	PropModels.shade(PropModels.dress(solid, &"seat", 0.25, 0.5), 0.7)


## Patrick's round rug, `width` across.
func _round_rug(width: float) -> void:
	var rug: Node3D = PropModels.shade(PropModels.make(&"rug", 0.0, width), 0.45)
	rug.position.y = LuckyLounge.STATION_RUG_Y
	add_child(rug)


func _rug(size: Vector2, color: Color) -> void:
	var mesh := PlaneMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.name = "Rug"
	mi.mesh = mesh
	# Patterned carpet on clients (same shader as the lounge floor), flat colour headless.
	mi.material_override = LoungeDecor._carpet(color, color.darkened(0.25), 1.0) if Vfx.enabled() else GreyboxKit.material(color)
	mi.position.y = LuckyLounge.STATION_RUG_Y
	add_child(mi)
