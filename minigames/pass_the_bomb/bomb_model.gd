class_name BombModel
extends Node3D
## The cartoon bomb of Pass the Bomb: a glossy black ball with a brass collar, a curled fuse and a
## sputtering spark at its tip. `heat` (0..1, from the bomb's age) speeds up the sparks and the red
## pulse of the ball; `pulse()` flashes it on each tick. Low-poly, built in code.

const BALL: Color = Color("#17151A")
const FUSE: Color = Color("#B79A6A")
const SPARK: Color = Color(1.0, 0.78, 0.35)
const HOT: Color = Color(0.85, 0.16, 0.08)

var radius: float = 0.16
var heat: float = 0.0
var _ball_mat: StandardMaterial3D
var _spark: MeshInstance3D
var _spark_mat: StandardMaterial3D
var _sparks: CPUParticles3D
var _flash: float = 0.0
var _t: float = 0.0


## `p_radius`: ball radius in metres (0.16 in the hand, smaller over a name tag).
func _init(p_radius: float = 0.16, with_particles: bool = true) -> void:
	radius = p_radius
	name = "Bomb"
	_ball_mat = StandardMaterial3D.new()
	_ball_mat.albedo_color = BALL
	_ball_mat.metallic = 0.3
	_ball_mat.roughness = 0.18
	_ball_mat.emission_enabled = true
	_ball_mat.emission = HOT
	_ball_mat.emission_energy_multiplier = 0.0
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 16
	sm.rings = 8
	ball.mesh = sm
	ball.material_override = _ball_mat
	add_child(ball)
	# A white highlight dab keeps it reading as a glossy ball in the warm light.
	var dab := MeshInstance3D.new()
	var dm := SphereMesh.new()
	dm.radius = radius * 0.22
	dm.height = radius * 0.3
	dm.radial_segments = 8
	dm.rings = 4
	dab.mesh = dm
	dab.material_override = Vfx.glow_material(Color(1, 1, 1, 0.55))
	dab.position = Vector3(-radius * 0.45, radius * 0.55, radius * 0.55)
	add_child(dab)
	# Brass collar and the fuse curling out of it.
	var brass := GreyboxKit.material(Palette.WARM_GOLD, 0.85, 0.3)
	var collar := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius * 0.38
	cm.bottom_radius = radius * 0.45
	cm.height = radius * 0.35
	cm.radial_segments = 12
	collar.mesh = cm
	collar.material_override = brass
	collar.position = Vector3(0, radius * 0.98, 0)
	add_child(collar)
	var fuse_mat := GreyboxKit.material(FUSE, 0.0, 0.9)
	var tip: Vector3 = Vector3(0, radius * 1.15, 0)
	var dir: Vector3 = Vector3(0.25, 1.0, 0.0).normalized()
	for i: int in 4:
		var seg := MeshInstance3D.new()
		var fm := CylinderMesh.new()
		fm.top_radius = radius * 0.06
		fm.bottom_radius = radius * 0.07
		fm.height = radius * 0.32
		fm.radial_segments = 6
		fm.rings = 1
		seg.mesh = fm
		seg.material_override = fuse_mat
		var mid: Vector3 = tip + dir * fm.height * 0.5
		seg.position = mid
		seg.basis = Basis(Quaternion(Vector3.UP, dir))
		add_child(seg)
		tip += dir * fm.height * 0.95
		dir = dir.rotated(Vector3.BACK, -0.35).normalized()
	# The spark: a hot billboard dot and, in the hand, a spray of sparks.
	_spark = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE * radius * 1.2
	_spark.mesh = q
	_spark_mat = Vfx.glow_material(SPARK, true, true)
	_spark_mat.albedo_texture = Vfx.soft_dot()
	_spark.material_override = _spark_mat
	_spark.position = tip
	add_child(_spark)
	if with_particles:
		_sparks = CPUParticles3D.new()
		var dot := QuadMesh.new()
		dot.size = Vector2.ONE * radius * 0.22
		_sparks.mesh = dot
		_sparks.material_override = Vfx.glow_material(Color.WHITE, true, true)
		_sparks.amount = 14
		_sparks.lifetime = 0.35
		_sparks.direction = Vector3.UP
		_sparks.spread = 70.0
		_sparks.initial_velocity_min = 0.6
		_sparks.initial_velocity_max = 1.6
		_sparks.gravity = Vector3(0, -3.0, 0)
		var g := Gradient.new()
		g.set_color(0, Color(1.0, 0.95, 0.7))
		g.set_color(g.get_point_count() - 1, Color(1.0, 0.4, 0.1, 0.0))
		_sparks.color_ramp = g
		_sparks.local_coords = false
		_sparks.position = tip
		add_child(_sparks)
		_sparks.emitting = Vfx.enabled()


func set_heat(h: float) -> void:
	heat = clampf(h, 0.0, 1.0)
	if _sparks != null:
		_sparks.speed_scale = 1.0 + heat * 1.8
		_sparks.initial_velocity_max = 1.6 + heat * 1.6


## A tick: the ball glows red for a moment and the spark flares.
func pulse() -> void:
	_flash = 1.0


func _process(delta: float) -> void:
	_t += delta
	_flash = maxf(_flash - delta * 5.0, 0.0)
	_ball_mat.emission_energy_multiplier = _flash * (0.6 + 1.6 * heat)
	var flicker: float = 0.85 + 0.3 * sin(_t * (30.0 + 40.0 * heat))
	_spark.scale = Vector3.ONE * (flicker + _flash * 0.8 + heat * 0.4)
