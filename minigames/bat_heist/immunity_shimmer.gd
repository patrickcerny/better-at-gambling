class_name ImmunityShimmer
extends Node3D
## Bat Heist's "you can't touch me" after getting up: a brass ring of light on the floor around the
## bean's feet, a faint warm column rising from it and a few cream motes drifting up, all pulsing
## gently and fading out over the last half second of `seconds`. Warm and soft, not neon.

const RADIUS: float = 0.62
const HEIGHT: float = 2.0

var seconds: float = 3.0
var left: float = 3.0
var _ring_mat: StandardMaterial3D
var _col_mat: StandardMaterial3D
var _ring: MeshInstance3D
var _motes: CPUParticles3D


func _init(p_seconds: float = 3.0) -> void:
	name = "ImmunityShimmer"
	seconds = p_seconds
	left = p_seconds
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = RADIUS - 0.07
	tm.outer_radius = RADIUS
	tm.rings = 32
	tm.ring_segments = 8
	_ring.mesh = tm
	_ring.position.y = 0.05
	_ring_mat = Vfx.glow_material(Color(Palette.VIP_GOLD, 0.9))
	_ring.material_override = _ring_mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	# The column: an open cylinder whose alpha fades upwards (vertex-free: a gradient texture).
	var col := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = RADIUS * 0.92
	cm.bottom_radius = RADIUS
	cm.height = HEIGHT
	cm.radial_segments = 24
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	col.mesh = cm
	col.position.y = HEIGHT * 0.5
	_col_mat = Vfx.glow_material(Color(Palette.CREAM, 0.0))
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.0))
	g.set_color(1, Color(1, 1, 1, 0.55))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)  # UV v runs top (0) to bottom (1): bright at the floor
	tex.width = 4
	tex.height = 64
	_col_mat.albedo_texture = tex
	col.material_override = _col_mat
	col.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(col)
	if Vfx.enabled():
		_motes = CPUParticles3D.new()
		var q := QuadMesh.new()
		q.size = Vector2.ONE * 0.07
		_motes.mesh = q
		var m: StandardMaterial3D = Vfx.glow_material(Color.WHITE, true, true)
		_motes.material_override = m
		_motes.amount = 14
		_motes.lifetime = 1.1
		_motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		_motes.emission_ring_axis = Vector3.UP
		_motes.emission_ring_radius = RADIUS * 0.9
		_motes.emission_ring_inner_radius = RADIUS * 0.6
		_motes.emission_ring_height = 0.0
		_motes.direction = Vector3.UP
		_motes.spread = 8.0
		_motes.gravity = Vector3.ZERO
		_motes.initial_velocity_min = 0.8
		_motes.initial_velocity_max = 1.5
		var cg := Gradient.new()
		cg.set_color(0, Color(Palette.CREAM, 0.9))
		cg.set_color(1, Color(Palette.VIP_GOLD, 0.0))
		_motes.color_ramp = cg
		_motes.local_coords = false
		add_child(_motes)


## Restarts the countdown (the bean got up again).
func restart(p_seconds: float) -> void:
	seconds = p_seconds
	left = p_seconds


func _process(delta: float) -> void:
	left -= delta
	var fade: float = clampf(left / 0.5, 0.0, 1.0)
	var pulse: float = 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.009)
	_ring_mat.albedo_color.a = 0.9 * pulse * fade
	_col_mat.albedo_color.a = 0.5 * pulse * fade
	_ring.rotation.y += delta * 1.5
	var s: float = 1.0 + 0.04 * sin(Time.get_ticks_msec() * 0.006)
	_ring.scale = Vector3(s, 1.0, s)
	if _motes != null:
		_motes.emitting = left > 0.4
