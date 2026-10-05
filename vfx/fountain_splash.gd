class_name FountainSplash
extends Node3D
## Water splash where someone hits the fountain: droplets thrown up and out, a white spray column
## (big splashes only) and a ripple ring spreading on the water. Frees itself. Purely visual:
## `spawn` returns null and creates nothing headless.

## The lobby fountain's water surface (LuckyLounge basin top) and basin radius.
const WATER_Y: float = 0.74
const BASIN_RADIUS: float = 2.2
const LIFETIME: float = 1.8
const WATER: Color = Color("#8FCBE0")
const FOAM: Color = Color("#F2F6F4")

var big: bool = false

var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _t: float = 0.0


## Splash on the lobby fountain's water at `pos` (snapped onto the surface, inside the basin).
static func at_fountain(parent: Node, pos: Vector3, p_big: bool) -> FountainSplash:
	var c: Vector3 = LuckyLounge.FOUNTAIN_POS
	var flat: Vector2 = Vector2(pos.x - c.x, pos.z - c.z)
	if flat.length() > BASIN_RADIUS:
		flat = flat.normalized() * BASIN_RADIUS
	return spawn(parent, Vector3(c.x + flat.x, WATER_Y, c.z + flat.y), p_big)


## A splash at `pos` (the water surface point). Null headless.
static func spawn(parent: Node, pos: Vector3, p_big: bool) -> FountainSplash:
	if parent == null or DisplayServer.get_name() == "headless":
		return null
	var s := FountainSplash.new()
	s.name = "FountainSplash"
	s.big = p_big
	parent.add_child(s)
	s.global_position = pos
	return s


func _ready() -> void:
	var k: float = 1.0 if big else 0.55
	add_child(_droplets(int(60 * k), 3.4 + 2.8 * k, 0.04, WATER))
	add_child(_droplets(int(26 * k), 2.2 + 2.0 * k, 0.03, FOAM))
	if big:
		add_child(_column())
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.albedo_color = FOAM
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring = MeshInstance3D.new()
	_ring.name = "Ripple"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.42
	torus.outer_radius = 0.5
	torus.rings = 28
	torus.ring_segments = 4
	_ring.mesh = torus
	_ring.material_override = _ring_mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.position.y = 0.02
	_ring.scale = Vector3(0.4, 0.08, 0.4)
	add_child(_ring)


func _process(delta: float) -> void:
	_t += delta
	var k: float = clampf(_t / 1.1, 0.0, 1.0)
	var r: float = lerpf(0.4, 3.4 if big else 2.0, 1.0 - pow(1.0 - k, 2.0))
	_ring.scale = Vector3(r, 0.08, r)
	_ring_mat.albedo_color.a = 0.85 * (1.0 - k)
	if _t >= LIFETIME:
		queue_free()


func _droplets(amount: int, speed: float, size: float, col: Color) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Droplets"
	p.amount = maxi(amount, 8)
	p.one_shot = true
	p.explosiveness = 0.92
	p.lifetime = 0.85
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.35
	p.direction = Vector3.UP
	p.spread = 30.0
	p.initial_velocity_min = speed * 0.55
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -14.0, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(0.75, 0.8))
	curve.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = curve
	var mesh := SphereMesh.new()
	mesh.radius = size
	mesh.height = size * 2.0
	mesh.radial_segments = 6
	mesh.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.1
	mat.metallic_specular = 0.9
	mesh.material = mat
	p.mesh = mesh
	p.emitting = true
	return p


## A short burst of white spray going straight up.
func _column() -> CPUParticles3D:
	var p: CPUParticles3D = _droplets(36, 7.0, 0.05, FOAM)
	p.name = "Column"
	p.spread = 9.0
	p.emission_sphere_radius = 0.2
	p.lifetime = 0.95
	p.initial_velocity_min = 4.5
	return p
