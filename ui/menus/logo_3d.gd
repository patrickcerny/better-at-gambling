class_name Logo3D
extends Node3D
## The 3D "BETTER AT GAMBLING" sign (mesh from tools/logo/build_logo3d.py) with its own camera,
## warm lights and a lighting-only environment, so it renders on a transparent background inside
## a SubViewport. Sways slowly when `sway` is on.

const MODEL: PackedScene = preload("res://assets/models/logo/logo_3d.glb")
## Per-material look, keyed by the material names the generator writes.
const LOOK: Dictionary = {
	&"LogoLetters": {"metallic": 0.35, "roughness": 0.38, "specular": 0.6},
	&"LogoOutline": {"metallic": 0.0, "roughness": 0.7, "specular": 0.3},
	&"LogoBanner": {"metallic": 0.0, "roughness": 0.72, "specular": 0.35},
	&"LogoTrim": {"metallic": 0.6, "roughness": 0.3, "specular": 0.7},
}

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
	var model: Node3D = MODEL.instantiate()
	_pivot.add_child(model)
	_apply_materials(model)
	camera = Camera3D.new()
	camera.fov = 30.0
	camera.position = Vector3(0, 0, 14.8)
	camera.current = true
	add_child(camera)
	_add_lights()
	_apply_pose()


func _process(delta: float) -> void:
	if not sway:
		return
	_t += delta
	_apply_pose()


func _apply_pose() -> void:
	var s: float = sin(_t * 0.6) if sway else 0.0
	var c: float = sin(_t * 0.45 + 1.3) if sway else 0.0
	_pivot.rotation = Vector3(deg_to_rad(pitch_deg + c * 2.0), deg_to_rad(yaw_deg + s * 7.0), deg_to_rad(s * -0.8))
	_pivot.position.y = sin(_t * 0.9) * 0.08 if sway else 0.0


func _apply_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var src: Material = mi.mesh.surface_get_material(i)
			var key: StringName = StringName(src.resource_name) if src != null else &""
			var look: Dictionary = LOOK.get(key, LOOK[&"LogoBanner"])
			var m := StandardMaterial3D.new()
			m.vertex_color_use_as_albedo = true
			m.metallic = look["metallic"]
			m.roughness = look["roughness"]
			m.metallic_specular = look["specular"]
			mi.set_surface_override_material(i, m)
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
