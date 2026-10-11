class_name Logo3D
extends Node3D
## The 3D "BETTER AT GAMBLING" sign (mesh from tools/logo/build_logo3d.py): the flat banner with
## its letters in front of a big casino chip (Patrick: "the 3d model but flat in front of a Casino
## coin"), with its own camera, warm lights and a lighting-only environment, so it renders on a
## transparent background inside a SubViewport (see `Logo3DView`). The camera frames the whole
## sign for any aspect. Sways gently when `sway` is on. `build_model()` gives just the sign, for
## placing it in the casino.

const MODEL: PackedScene = preload("res://assets/models/logo/logo_3d.glb")
## Per-material look, keyed by the material names the generator writes.
const LOOK: Dictionary = {
	&"LogoLetters": {"metallic": 0.35, "roughness": 0.38, "specular": 0.6},
	&"LogoOutline": {"metallic": 0.0, "roughness": 0.7, "specular": 0.3},
	&"LogoBanner": {"metallic": 0.0, "roughness": 0.72, "specular": 0.35},
	&"LogoTrim": {"metallic": 0.6, "roughness": 0.3, "specular": 0.7},
	&"LogoCoinGold": {"metallic": 0.6, "roughness": 0.34, "specular": 0.7},
	&"LogoCoinEdge": {"metallic": 0.0, "roughness": 0.6, "specular": 0.4},
}
## Size of the sign (m, at full scale) and the camera's distance; the camera fits SIZE * FRAME.
const SIZE: Vector2 = Vector2(13.9, 11.2)
const FRAME: float = 1.08
const CAMERA_DIST: float = 24.0

@export var sway: bool = true
## Yaw/pitch in degrees applied on top of the sway (used for the preview angles).
@export var yaw_deg: float = 0.0
@export var pitch_deg: float = 0.0

var camera: Camera3D
var _pivot: Node3D
var _t: float = 0.0


func _ready() -> void:
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)
	_pivot.add_child(build_model())
	camera = Camera3D.new()
	camera.position = Vector3(0, 0, CAMERA_DIST)
	camera.current = true
	add_child(camera)
	_add_lights()
	_apply_pose()
	get_viewport().size_changed.connect(_frame)
	_frame()


## Fits the whole sign: by width in narrow views, by height in wide ones.
func _frame() -> void:
	var vp: Vector2 = Vector2(get_viewport().get_visible_rect().size)
	var wide: bool = vp.y > 0.0 and vp.x / vp.y > SIZE.x / SIZE.y
	camera.keep_aspect = Camera3D.KEEP_HEIGHT if wide else Camera3D.KEEP_WIDTH
	var span: float = (SIZE.y if wide else SIZE.x) * FRAME
	camera.fov = rad_to_deg(2.0 * atan(span * 0.5 / CAMERA_DIST))


func _process(delta: float) -> void:
	if not sway:
		return
	_t += delta
	_apply_pose()


func _apply_pose() -> void:
	var s: float = sin(_t * 0.6) if sway else 0.0
	var c: float = sin(_t * 0.45 + 1.3) if sway else 0.0
	# Gentle: it must still read as a flat coin sign.
	_pivot.rotation = Vector3(deg_to_rad(pitch_deg + c * 1.5), deg_to_rad(yaw_deg + s * 5.0), deg_to_rad(s * -0.6))
	_pivot.position.y = sin(_t * 0.9) * 0.06 if sway else 0.0


## The sign alone (about 13.9 x 11.2 x 2.3 m, facing +Z, centred on the origin, the banner's front
## at z ~0.6 and the chip's back at z ~-1.7), materials applied.
static func build_model() -> Node3D:
	var model: Node3D = MODEL.instantiate()
	model.name = "LogoSign"
	_apply_materials(model)
	return model


## Swaps the imported materials for the logo's own (vertex colours as albedo) on the shared mesh,
## once; later instances find them already in place.
static func _apply_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		for i in mesh.get_surface_count():
			var src: Material = mesh.surface_get_material(i)
			if src is StandardMaterial3D and (src as StandardMaterial3D).has_meta(&"logo_look"):
				continue
			var key: StringName = StringName(src.resource_name) if src != null else &""
			var look: Dictionary = LOOK.get(key, LOOK[&"LogoBanner"])
			var m := StandardMaterial3D.new()
			m.resource_name = key
			m.set_meta(&"logo_look", true)
			m.vertex_color_use_as_albedo = true
			m.metallic = look["metallic"]
			m.roughness = look["roughness"]
			m.metallic_specular = look["specular"]
			mesh.surface_set_material(i, m)
	for child in node.get_children():
		_apply_materials(child)


func _add_lights() -> void:
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.94, 0.84)
	key.light_energy = 1.15
	key.rotation_degrees = Vector3(-35, -30, 0)
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(1.0, 0.7, 0.5)
	fill.light_energy = 0.45
	fill.rotation_degrees = Vector3(-10, 40, 0)
	add_child(fill)
	var rim := OmniLight3D.new()
	rim.light_color = Color(1.0, 0.8, 0.55)
	rim.light_energy = 3.0
	rim.omni_range = 16.0
	rim.position = Vector3(0, 6, 4)
	add_child(rim)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR  # the viewport stays transparent
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.55, 0.35, 0.2)
	sky_mat.sky_horizon_color = Color(1.0, 0.8, 0.5)
	sky_mat.ground_horizon_color = Color(0.5, 0.25, 0.12)
	sky_mat.ground_bottom_color = Color(0.12, 0.05, 0.03)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.62, 0.56)
	env.ambient_light_energy = 0.7
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
