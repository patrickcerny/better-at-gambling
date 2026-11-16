class_name WinnerFx
extends Node3D
## The winner's moment on the results podium (`ResultsStage`): a soft visible light cone from
## above, gold coins showering down round the top step, and little gold firework pops over the
## stage every second or so while the screen is up. Nothing is built on a headless run.

const COIN_GOLD := Color("#F2C14E")
const SPARK_COLORS: Array[Color] = [Color("#FFE6A0"), Color("#F2C14E"), Color("#FFF6E0"), Color("#E8604F")]
## Seconds between firework pops, and where they burst (local to the stage).
const POP_GAP: float = 1.15
const POP_AREA: Vector3 = Vector3(9.0, 1.6, 1.0)
const POP_Y: float = 5.2

var _pop_in: float = 0.4
var _rng := RandomNumberGenerator.new()
var _pops: int = 0
## Pops left (keeps going for about half a minute, then the stage calms down).
var pops_left: int = 26


## Puts the show on round `top` (the winner's feet, local to `parent`).
static func start(parent: Node3D, top: Vector3) -> WinnerFx:
	if DisplayServer.get_name() == "headless" or parent == null or not parent.is_inside_tree():
		return null
	var fx := WinnerFx.new()
	fx.name = "WinnerFx"
	fx.position = top
	parent.add_child(fx)
	fx._build()
	return fx


func _build() -> void:
	_rng.seed = 1234
	add_child(_light_cone())
	add_child(_coin_shower())


func _process(delta: float) -> void:
	if pops_left <= 0:
		return
	_pop_in -= delta
	if _pop_in > 0.0:
		return
	_pop_in = POP_GAP * _rng.randf_range(0.7, 1.3)
	pops_left -= 1
	var at := Vector3(_rng.randf_range(-0.5, 0.5) * POP_AREA.x, POP_Y - position.y + _rng.randf_range(-0.5, 0.5) * POP_AREA.y, _rng.randf_range(-0.5, 0.5) * POP_AREA.z)
	# Keep the middle (the winner's face) clear.
	if absf(at.x) < 1.4:
		at.x = signf(at.x if at.x != 0.0 else 1.0) * 1.4 + at.x
	add_child(_spark_pop(at, SPARK_COLORS[_pops % SPARK_COLORS.size()]))
	_pops += 1
	Audio.play(&"chip_clack", &"SFX", -16.0, _rng.randf_range(1.6, 2.1))


## A warm soft cone of light falling on the top step (additive, fades out towards the top).
func _light_cone() -> MeshInstance3D:
	var cone := MeshInstance3D.new()
	cone.name = "LightCone"
	var cm := CylinderMesh.new()
	cm.top_radius = 0.35
	cm.bottom_radius = 1.25
	cm.height = 6.5
	cm.radial_segments = 32
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	cone.mesh = cm
	cone.position = Vector3(0, 3.25 - 0.05, 0)
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 tint : source_color = vec4(1.0, 0.85, 0.55, 1.0);
uniform float strength = 0.16;
void fragment() {
	float down = UV.y;  // 0 at the top, 1 at the floor
	float facing = abs(dot(NORMAL, VIEW));
	float a = strength * mix(0.15, 1.0, down) * pow(facing, 1.6);
	ALBEDO = tint.rgb * a;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	cone.material_override = m
	# Fade in.
	m.set_shader_parameter(&"strength", 0.0)
	var tw: Tween = cone.create_tween()
	tw.tween_method(func(v: float) -> void: m.set_shader_parameter(&"strength", v), 0.0, 0.16, 0.6)
	return cone


## Gold coins tumbling down round the winner, a gentle steady shower.
func _coin_shower() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Coins"
	p.amount = 70
	p.lifetime = 2.6
	p.local_coords = false
	p.position = Vector3(0, 5.6, 0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(2.4, 0.1, 0.8)
	p.direction = Vector3.DOWN
	p.spread = 12.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.4
	p.gravity = Vector3(0, -3.2, 0)
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.angular_velocity_min = -540.0
	p.angular_velocity_max = 540.0
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.2
	p.particle_flag_rotate_y = false
	var coin := CylinderMesh.new()
	coin.top_radius = 0.075
	coin.bottom_radius = 0.075
	coin.height = 0.018
	coin.radial_segments = 12
	coin.rings = 1
	var m := StandardMaterial3D.new()
	m.albedo_color = COIN_GOLD
	m.metallic = 0.85
	m.roughness = 0.3
	m.emission_enabled = true
	m.emission = Color("#7A5410")
	m.emission_energy_multiplier = 0.6
	coin.material = m
	p.mesh = coin
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## One firework pop: a ring of sparks bursting out and fading as they drop.
func _spark_pop(at: Vector3, color: Color) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.position = at
	p.amount = 42
	p.lifetime = 1.1
	p.one_shot = true
	p.explosiveness = 0.95
	p.local_coords = true
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 2.8
	p.damping_min = 2.0
	p.damping_max = 3.0
	p.gravity = Vector3(0, -1.6, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.1
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	fade.colors = PackedColorArray([color.lightened(0.45), color, Color(color, 0.0)])
	p.color_ramp = fade
	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.05)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	quad.material = m
	p.mesh = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emitting = true
	p.finished.connect(p.queue_free)
	return p
