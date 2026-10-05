class_name HotTableFx
extends Node3D
## The Hot Table look while a station is hot: a warm spotlight from above with a soft visible
## cone, embers and sparks rising around the table and a flickering glow (the bouncing arrow stays
## in `StationBase`). Built on first use, client only.

const HEIGHT: float = 6.0

## Ring radius of the embers around the table (set before adding to the tree).
var radius: float = 2.2
## 0..1 fade of the light and cone.
var level: float = 0.0

var spot: SpotLight3D
var cone: MeshInstance3D
var embers: CPUParticles3D
var sparks: CPUParticles3D
## Low flames licking up around the table's footprint.
var flames: CPUParticles3D
var _t: float = 0.0
var _on: bool = false


func _ready() -> void:
	name = "HotFx"
	spot = SpotLight3D.new()
	spot.name = "Spot"
	spot.light_color = Color(1.0, 0.62, 0.25)
	spot.light_energy = 0.0
	spot.spot_range = HEIGHT + 2.0
	spot.spot_angle = rad_to_deg(atan(radius * 1.1 / (HEIGHT - 0.9)))
	spot.spot_attenuation = 0.6
	spot.position = Vector3(0, HEIGHT, 0)
	spot.rotation.x = -PI * 0.5  # straight down
	add_child(spot)
	cone = MeshInstance3D.new()
	cone.name = "Cone"
	var cm := CylinderMesh.new()
	cm.top_radius = 0.15
	cm.bottom_radius = radius * 0.95
	cm.height = HEIGHT - 0.2
	cm.radial_segments = 24
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	cone.mesh = cm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(1.0, 0.42, 0.08, 0.0)
	m.no_depth_test = false
	m.disable_receive_shadows = true
	cone.material_override = m
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cone.position.y = (HEIGHT - 0.2) * 0.5 + 0.1
	add_child(cone)
	embers = _particles("Embers", 60, 2.4, Vector2(0.09, 0.09), 0.6, 1.5)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.85, 0.35, 1.0))
	ramp.add_point(0.5, Color(1.0, 0.45, 0.1, 0.9))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.6, 0.12, 0.05, 0.0))
	embers.color_ramp = ramp
	sparks = _particles("Sparks", 20, 1.2, Vector2(0.035, 0.035), 1.5, 3.0)
	var sr := Gradient.new()
	sr.set_color(0, Color(1.0, 0.95, 0.7, 1.0))
	sr.set_color(1, Color(Palette.VIP_GOLD, 0.0))
	sparks.color_ramp = sr
	flames = _particles("Flames", 70, 0.7, Vector2(0.26, 0.26), 0.5, 1.1)
	flames.position.y = 0.08
	flames.emission_ring_inner_radius = radius * 0.9
	flames.emission_ring_radius = radius * 1.05
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, 0.2))
	flames.scale_amount_curve = shrink
	var fr := Gradient.new()
	fr.set_color(0, Color(1.0, 0.8, 0.3, 0.9))
	fr.add_point(0.4, Color(1.0, 0.4, 0.08, 0.7))
	fr.set_color(fr.get_point_count() - 1, Color(0.5, 0.08, 0.04, 0.0))
	flames.color_ramp = fr
	visible = false


func _particles(n: String, amount: int, lifetime: float, size: Vector2, v_min: float, v_max: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = n
	var q := QuadMesh.new()
	q.size = size
	q.material = Vfx.glow_material(Color.WHITE, true, true)
	p.mesh = q
	p.amount = amount
	p.lifetime = lifetime
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_height = 0.1
	p.emission_ring_radius = radius
	p.emission_ring_inner_radius = radius * 0.75
	p.position.y = 0.95
	p.direction = Vector3.UP
	p.spread = 12.0
	p.initial_velocity_min = v_min
	p.initial_velocity_max = v_max
	p.gravity = Vector3(0, 0.3, 0)
	p.damping_min = 0.2
	p.damping_max = 0.6
	p.emitting = false
	add_child(p)
	return p


## Turns the effect on or off (fades the light and cone, starts/stops the particles).
func set_on(on: bool) -> void:
	if on == _on:
		return
	_on = on
	if on:
		visible = true
	embers.emitting = on
	sparks.emitting = on
	flames.emitting = on
	var t: Tween = create_tween()
	t.tween_property(self, "level", 1.0 if on else 0.0, 0.5)


func is_on() -> bool:
	return _on


func _process(delta: float) -> void:
	if not _on and level <= 0.0:
		visible = false
		return
	_t += delta
	# Fire flicker on the light and a slow breathing cone.
	spot.light_energy = level * (9.0 + sin(_t * 13.0) * 0.8 + sin(_t * 23.0) * 0.5)
	(cone.material_override as StandardMaterial3D).albedo_color.a = level * (0.07 + sin(_t * 2.0) * 0.015)
