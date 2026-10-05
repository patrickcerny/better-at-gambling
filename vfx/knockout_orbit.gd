class_name KnockoutOrbit
extends Node3D
## Cartoon knockout halo: little gold stars and two cream birdies circling a dazed head. Shown while
## a player is knocked out; follows the ragdoll's head (`follow`) or sits above the bean. Builds no
## meshes and does no work headless (the visible flag still tracks the state for tests).

const STAR_COUNT: int = 3
const BIRD_COUNT: int = 2
const RADIUS: float = 0.38
## Height above the followed head (or above the bean's feet when nothing is followed).
const HEAD_OFFSET: float = 0.42
const BEAN_HEIGHT: float = 1.85

## Ragdoll head to circle (null: stay above the parent bean).
var follow: Node3D = null

var _spin: Node3D
var _birds: Array[Node3D] = []
var _wings: Array[Node3D] = []
var _stars: Array[Node3D] = []
var _t: float = 0.0
var _headless: bool = false


func _ready() -> void:
	_headless = DisplayServer.get_name() == "headless"
	position.y = BEAN_HEIGHT
	if _headless:
		set_process(false)
		return
	_spin = Node3D.new()
	_spin.name = "Spin"
	add_child(_spin)
	var gold: StandardMaterial3D = StandardMaterial3D.new()
	gold.albedo_color = Palette.VIP_GOLD
	gold.emission_enabled = true
	gold.emission = Palette.VIP_GOLD
	gold.emission_energy_multiplier = 0.6
	gold.metallic = 0.4
	gold.roughness = 0.4
	var star_mesh: ArrayMesh = star_mesh(0.085, 0.04, 0.03)
	for i: int in STAR_COUNT:
		var a: float = i * TAU / STAR_COUNT
		var s := MeshInstance3D.new()
		s.name = "Star%d" % i
		s.mesh = star_mesh
		s.material_override = gold
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		s.position = Vector3(cos(a) * RADIUS, 0.0, sin(a) * RADIUS)
		_spin.add_child(s)
		_stars.append(s)
	for i: int in BIRD_COUNT:
		var a: float = (i + 0.5) * TAU / BIRD_COUNT
		_birds.append(_bird(Vector3(cos(a) * RADIUS * 1.15, 0.05, sin(a) * RADIUS * 1.15), -a))


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	if follow != null and is_instance_valid(follow) and follow.is_inside_tree():
		if not top_level:
			top_level = true
		global_position = follow.global_position + Vector3(0.0, HEAD_OFFSET, 0.0)
		global_basis = Basis.IDENTITY
	elif top_level:
		top_level = false
		position = Vector3(0.0, BEAN_HEIGHT, 0.0)
		basis = Basis.IDENTITY
	_spin.rotation.y = _t * 3.2
	# A dizzy wobble: the whole halo tilts around as it spins.
	_spin.rotation.x = sin(_t * 2.1) * 0.25
	_spin.rotation.z = cos(_t * 1.7) * 0.25
	for i: int in _stars.size():
		_stars[i].rotation.y = _t * 6.0 + i
		_stars[i].position.y = sin(_t * 5.0 + i * 2.0) * 0.05
	for i: int in _birds.size():
		_birds[i].position.y = 0.05 + sin(_t * 7.0 + i * PI) * 0.06
	for i: int in _wings.size():
		_wings[i].rotation.z = (1.0 if i % 2 == 0 else -1.0) * (0.3 + sin(_t * 28.0 + i) * 0.6)


## A flat five-point star prism (radius `r`, inner radius `ri`, thickness `t`), facing +Z.
static func star_mesh(r: float, ri: float, t: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array[Vector2] = []
	for k: int in 10:
		var a: float = PI * 0.5 + k * TAU / 10.0
		var rr: float = r if k % 2 == 0 else ri
		pts.append(Vector2(cos(a), sin(a)) * rr)
	for side: float in [1.0, -1.0]:
		var z: float = t * 0.5 * side
		st.set_normal(Vector3(0, 0, side))
		for k: int in 10:
			var a: Vector2 = pts[k]
			var b: Vector2 = pts[(k + 1) % 10]
			if side > 0.0:
				st.add_vertex(Vector3(0, 0, z))
				st.add_vertex(Vector3(a.x, a.y, z))
				st.add_vertex(Vector3(b.x, b.y, z))
			else:
				st.add_vertex(Vector3(0, 0, z))
				st.add_vertex(Vector3(b.x, b.y, z))
				st.add_vertex(Vector3(a.x, a.y, z))
	for k: int in 10:
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[(k + 1) % 10]
		var n: Vector3 = Vector3(b.y - a.y, a.x - b.x, 0.0).normalized()
		st.set_normal(n)
		st.add_vertex(Vector3(a.x, a.y, t * 0.5))
		st.add_vertex(Vector3(a.x, a.y, -t * 0.5))
		st.add_vertex(Vector3(b.x, b.y, t * 0.5))
		st.add_vertex(Vector3(b.x, b.y, t * 0.5))
		st.add_vertex(Vector3(a.x, a.y, -t * 0.5))
		st.add_vertex(Vector3(b.x, b.y, -t * 0.5))
	return st.commit()


## A tiny round cream bird with a gold beak and flapping wings, flying tangentially around the orbit.
func _bird(pos: Vector3, heading: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Birdie"
	root.position = pos
	root.rotation.y = heading
	_spin.add_child(root)
	var cream: StandardMaterial3D = GreyboxKit.material(Palette.CREAM)
	var body := MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = 0.07
	bm.height = 0.12
	bm.radial_segments = 10
	bm.rings = 6
	body.mesh = bm
	body.material_override = cream
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(body)
	var beak := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 0.025
	cm.height = 0.06
	cm.radial_segments = 6
	beak.mesh = cm
	beak.material_override = GreyboxKit.material(Palette.WARM_GOLD)
	beak.rotation.x = -PI * 0.5
	beak.position = Vector3(0, 0.0, -0.085)
	root.add_child(beak)
	var eye := MeshInstance3D.new()
	var em := SphereMesh.new()
	em.radius = 0.012
	em.height = 0.024
	eye.mesh = em
	eye.material_override = GreyboxKit.material(Palette.CASINO_BLACK)
	eye.position = Vector3(0.0, 0.03, -0.055)
	root.add_child(eye)
	for side: float in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(side * 0.05, 0.02, 0.0)
		root.add_child(pivot)
		var wing := MeshInstance3D.new()
		var wm := BoxMesh.new()
		wm.size = Vector3(0.09, 0.012, 0.05)
		wing.mesh = wm
		wing.material_override = cream
		wing.position = Vector3(side * 0.045, 0.0, 0.0)
		pivot.add_child(wing)
		_wings.append(pivot)
	return root
