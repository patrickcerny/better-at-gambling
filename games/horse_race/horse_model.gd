class_name HorseModel
extends Node3D
## A low-poly racehorse built from primitives (no model file): barrel, chest and rump, an arched
## neck with a mane, a long head with ears, dot eyes and a dark muzzle, four two-part legs with
## hooves, a tail, a saddle cloth in the lane colour and a little bean jockey in matching silks.
## The static parts merge into one vertex-coloured mesh and every leg segment is one more, so a
## horse costs ten draw calls. `gallop` (0 = standing, 1 = flat out) drives a rotary-gallop leg
## cycle with a body bob; `celebrate` rears it up once (the winner).
##
## Built facing −Z with its hooves on y = 0 and its nose at `NOSE_Z`, about `LENGTH` long nose to
## tail and `HEIGHT` tall to the jockey's cap: scale it to the size you need.

## Coat presets: [coat, mane and tail, lower legs ("" = coat), white socks].
const COATS: Dictionary = {
	&"chestnut": [Color("#8C4A27"), Color("#5B2C16"), Color(), false],
	&"bay": [Color("#6A3820"), Color("#1D1512"), Color("#241A15"), false],
	&"grey": [Color("#C2BBB1"), Color("#8A847C"), Color(), true],
	&"black": [Color("#2A2421"), Color("#141110"), Color(), true],
	&"palomino": [Color("#D1A65C"), Color("#F2E6C9"), Color(), false],
}
const NOSE_Z: float = -1.5
const LENGTH: float = 2.25
const HEIGHT: float = 2.2
## Hip pivots (x, y, z) of the legs, and their phase in the stride (rotary gallop: the hind pair
## lands, then the fore pair, with a moment of flight in between).
const LEGS: Array = [
	[Vector3(-0.17, 1.0, -0.52), 0.5, true], [Vector3(0.17, 1.0, -0.52), 0.62, true],
	[Vector3(-0.17, 1.0, 0.52), 0.0, false], [Vector3(0.17, 1.0, 0.52), 0.12, false],
]
## Where the hind hooves stand (z): the horse rears about them.
const REAR_PIVOT_Z: float = 0.52
## Strides per second flat out.
const STRIDE_HZ: float = 2.6
## Where the leader's crown sits (on the jockey's cap, the highest point, in body space).
const CROWN_SPOT: Vector3 = Vector3(0, 2.1, -0.36)
## The "your horse" outline: warm gold, a few millimetres wide in the world whatever the scale.
const OUTLINE_COLOR: Color = Color("#EDBE52")
const OUTLINE_WIDTH: float = 0.01
const OUTLINE_SHADER: Shader = preload("res://client/aim_outline.gdshader")

## 0 = standing still, 1 = full gallop; eases towards `target_gallop`.
var gallop: float = 0.0
var target_gallop: float = 0.0
var body: Node3D
var tail: Node3D
var hips: Array[Node3D] = []
var knees: Array[Node3D] = []
## Every mesh of the horse (body, legs, tail): the outline goes on each, so it gallops along.
var meshes: Array[MeshInstance3D] = []
## True while the local player's money is on this horse (`set_outlined`).
var outlined: bool = false

var _phase: float = 0.0
var _time: float = 0.0
var _fore: Array[bool] = []
var _offsets: Array[float] = []
var _rearing: bool = false

static var _material: StandardMaterial3D
static var _outline: ShaderMaterial
static var _crown_material: StandardMaterial3D


## `coat` is a key of COATS; `silks` colours the saddle cloth and the jockey; `seed_value` shifts
## the stride so a field of horses never moves in lockstep.
func _init(coat: StringName = &"chestnut", silks: Color = Palette.CASINO_RED, seed_value: int = 0) -> void:
	name = "Horse"
	var spec: Array = COATS.get(coat, COATS[&"chestnut"])
	var coat_c: Color = spec[0]
	var mane_c: Color = spec[1]
	var leg_c: Color = spec[2] if spec[2] != Color() else coat_c
	var socks: bool = spec[3]
	_phase = fposmod(seed_value * 0.37, 1.0)
	body = Node3D.new()
	body.name = "Body"
	add_child(body)
	_build_body(coat_c, mane_c, silks)
	for i: int in LEGS.size():
		_build_leg(i, leg_c, socks and i % 2 == 0)
	tail = Node3D.new()
	tail.name = "Tail"
	tail.position = Vector3(0, 1.42, 0.82)
	body.add_child(tail)
	var mb := _MeshBuilder.new()
	var t := CylinderMesh.new()
	t.top_radius = 0.075
	t.bottom_radius = 0.04
	t.height = 0.62
	t.radial_segments = 6
	t.rings = 1
	mb.add(t, Transform3D(Basis(), Vector3(0, -0.31, 0)), mane_c)
	var tuft := SphereMesh.new()
	tuft.radius = 0.07
	tuft.height = 0.2
	tuft.radial_segments = 6
	tuft.rings = 3
	mb.add(tuft, Transform3D(Basis(), Vector3(0, -0.62, 0)), mane_c)
	tail.add_child(_mesh(mb, "TailMesh"))
	_pose(0.0)


func _process(delta: float) -> void:
	_time += delta
	gallop = move_toward(gallop, target_gallop, delta * 2.5)
	_phase = fposmod(_phase + delta * STRIDE_HZ * maxf(gallop, 0.0), 1.0)
	_pose(gallop)


## Runs (`speed` 0..1, about the share of a full gallop) or stands (0).
func set_running(speed: float) -> void:
	target_gallop = clampf(speed, 0.0, 1.0)


## Outlines the horse (the local player backed it) or not: an inverted hull drawn as each mesh's
## overlay, grown along the normals in world space so it stays thin on the miniature.
func set_outlined(on: bool) -> void:
	outlined = on
	for mi: MeshInstance3D in meshes:
		mi.material_overlay = outline_material() if on else null


static func outline_material() -> ShaderMaterial:
	if _outline == null:
		_outline = ShaderMaterial.new()
		_outline.shader = OUTLINE_SHADER
		_outline.set_shader_parameter(&"color", OUTLINE_COLOR)
		_outline.set_shader_parameter(&"width", OUTLINE_WIDTH)
	return _outline


## A little low-poly gold crown (band, five points with ball tips, a red gem at the front) in the
## horse's own units, built to sit at `CROWN_SPOT` on `body`. Facing −Z like the horse.
static func make_crown() -> MeshInstance3D:
	var mb := _MeshBuilder.new()
	var gold := Color("#E0B04A")
	var band := CylinderMesh.new()
	band.top_radius = 0.15
	band.bottom_radius = 0.135
	band.height = 0.075
	band.radial_segments = 10
	band.rings = 1
	mb.add(band, Transform3D(Basis(), Vector3(0, 0.0375, 0)), gold)
	var spike := CylinderMesh.new()
	spike.top_radius = 0.0
	spike.bottom_radius = 0.045
	spike.height = 0.1
	spike.radial_segments = 4
	spike.rings = 1
	var tip := SphereMesh.new()
	tip.radius = 0.02
	tip.height = 0.04
	tip.radial_segments = 6
	tip.rings = 3
	for k: int in 5:
		var a: float = TAU * k / 5.0
		var rim := Vector3(sin(a), 0, -cos(a)) * 0.135  # k = 0 at the front
		mb.add(spike, Transform3D(Basis(Vector3.UP, -a), rim + Vector3(0, 0.12, 0)), gold)
		mb.add(tip, Transform3D(Basis(), rim + Vector3(0, 0.175, 0)), gold.lightened(0.15))
	var gem := SphereMesh.new()
	gem.radius = 0.028
	gem.height = 0.05
	gem.radial_segments = 6
	gem.rings = 3
	mb.add(gem, Transform3D(Basis(), Vector3(0, 0.04, -0.148)), Color("#B3262E"))
	var mi := MeshInstance3D.new()
	mi.name = "Crown"
	mi.mesh = mb.commit()
	if _crown_material == null:
		_crown_material = StandardMaterial3D.new()
		_crown_material.vertex_color_use_as_albedo = true
		_crown_material.metallic = 0.7
		_crown_material.roughness = 0.35
	mi.material_override = _crown_material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = CROWN_SPOT
	return mi


## Rears up once on its hind legs, front hooves in the air (the winner).
func celebrate() -> void:
	if not is_inside_tree() or _rearing:
		return
	_rearing = true
	var angle: float = deg_to_rad(28.0)
	# Turning about the hind hooves, not the middle: the body lifts as it tips back.
	var lift := Vector3(0, REAR_PIVOT_Z * sin(angle), REAR_PIVOT_Z * (1.0 - cos(angle)))
	var tw: Tween = create_tween()
	tw.tween_property(body, ^"rotation:x", angle, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(body, ^"position", lift, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.5)
	tw.tween_property(body, ^"rotation:x", 0.0, 0.4).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(body, ^"position", Vector3.ZERO, 0.4).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void: _rearing = false)


func _pose(g: float) -> void:
	var cycle: float = TAU * _phase
	for i: int in hips.size():
		var c: float = cycle + TAU * _offsets[i]
		var swing: float = sin(c)
		var amp: float = 0.62 if _fore[i] else 0.5
		hips[i].rotation.x = swing * amp * g
		# The leg folds on the way forward (hoof off the ground) and straightens to land.
		knees[i].rotation.x = -maxf(0.0, cos(c)) * (1.15 if _fore[i] else 0.8) * g
	if not _rearing:
		body.rotation.x = sin(cycle * 2.0) * 0.045 * g
		body.position = Vector3(0, absf(sin(cycle)) * 0.07 * g, 0)
	tail.rotation.x = -(0.35 + g * 0.75 + sin(_time * 7.0) * 0.08 * g)  # streams out behind
	tail.rotation.z = sin(_time * 1.3 + _offsets[0]) * 0.18 * (1.0 - g)


func _build_body(coat: Color, mane: Color, silks: Color) -> void:
	var mb := _MeshBuilder.new()
	var dark: Color = coat.darkened(0.55)
	# Barrel, chest and rump.
	var barrel := CapsuleMesh.new()
	barrel.radius = 0.33
	barrel.height = 1.25
	barrel.radial_segments = 10
	barrel.rings = 3
	mb.add(barrel, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 1.2, 0.0)), coat)
	mb.add(_sphere(0.34), Transform3D(Basis().scaled(Vector3(0.9, 1.0, 1.0)), Vector3(0, 1.22, -0.5)), coat)
	mb.add(_sphere(0.35), Transform3D(Basis().scaled(Vector3(0.95, 1.0, 1.05)), Vector3(0, 1.27, 0.52)), coat)
	# Neck, arched up and forward from the chest.
	var neck_from := Vector3(0, 1.3, -0.6)
	var neck_to := Vector3(0, 1.9, -0.98)
	var neck := CylinderMesh.new()
	neck.top_radius = 0.13
	neck.bottom_radius = 0.26
	neck.height = neck_from.distance_to(neck_to) + 0.12
	neck.radial_segments = 8
	neck.rings = 1
	mb.add(neck, _along(neck_from, neck_to), coat)
	# Mane: a crest along the top of the neck and a forelock.
	var up_back: Vector3 = Vector3(0, 0.38, 0.6).normalized()
	var crest := BoxMesh.new()
	crest.size = Vector3(0.07, 0.12, neck.height * 0.92)
	var crest_xf: Transform3D = _along(neck_from, neck_to)
	crest_xf.basis = crest_xf.basis * Basis(Vector3.RIGHT, PI * 0.5)
	crest_xf.origin += up_back * 0.13
	mb.add(crest, crest_xf, mane)
	# Head, pointing forward and down from the poll, with ears, eyes and a dark muzzle.
	var poll := Vector3(0, 1.98, -1.02)
	var muzzle := Vector3(0, 1.66, -1.44)
	var head := CylinderMesh.new()
	head.top_radius = 0.085
	head.bottom_radius = 0.135
	head.height = poll.distance_to(muzzle) + 0.08
	head.radial_segments = 8
	head.rings = 1
	mb.add(head, _along(poll, muzzle), coat)
	mb.add(_sphere(0.1), Transform3D(Basis().scaled(Vector3(1.0, 0.9, 1.15)), muzzle + Vector3(0, 0, -0.02)), dark)
	mb.add(_sphere(0.13), Transform3D(Basis().scaled(Vector3(0.95, 1.0, 1.0)), poll + Vector3(0, -0.02, 0.0)), coat)
	var fore := BoxMesh.new()
	fore.size = Vector3(0.1, 0.05, 0.14)
	mb.add(fore, Transform3D(Basis(Vector3.RIGHT, -0.5), poll + Vector3(0, 0.1, -0.1)), mane)
	var ear := CylinderMesh.new()
	ear.top_radius = 0.0
	ear.bottom_radius = 0.045
	ear.height = 0.15
	ear.radial_segments = 4
	ear.rings = 1
	for sx: float in [-1.0, 1.0]:
		mb.add(ear, Transform3D(Basis(Vector3.FORWARD, sx * 0.25) * Basis(Vector3.RIGHT, -0.2), poll + Vector3(sx * 0.07, 0.15, 0.02)), coat)
		mb.add(_sphere(0.024), Transform3D(Basis(), Vector3(sx * 0.105, 1.9, -1.15)), Palette.CASINO_BLACK)
		mb.add(_sphere(0.022), Transform3D(Basis(), muzzle + Vector3(sx * 0.05, 0.03, -0.1)), Palette.CASINO_BLACK)
	# Saddle cloth in the lane colour with a cream edge, and the saddle on it.
	var cloth := BoxMesh.new()
	cloth.size = Vector3(0.66, 0.035, 0.5)
	var edge := BoxMesh.new()
	edge.size = Vector3(0.68, 0.03, 0.56)
	mb.add(edge, Transform3D(Basis(), Vector3(0, 1.515, -0.02)), Palette.CREAM)
	mb.add(cloth, Transform3D(Basis(), Vector3(0, 1.535, -0.02)), silks)
	var flap := BoxMesh.new()
	flap.size = Vector3(0.03, 0.3, 0.5)
	var flap_edge := BoxMesh.new()
	flap_edge.size = Vector3(0.025, 0.34, 0.56)
	for sx: float in [-1.0, 1.0]:
		mb.add(flap_edge, Transform3D(Basis(Vector3.FORWARD, sx * 0.18), Vector3(sx * 0.325, 1.37, -0.02)), Palette.CREAM)
		mb.add(flap, Transform3D(Basis(Vector3.FORWARD, sx * 0.18), Vector3(sx * 0.34, 1.38, -0.02)), silks)
	var saddle := BoxMesh.new()
	saddle.size = Vector3(0.3, 0.07, 0.34)
	mb.add(saddle, Transform3D(Basis(), Vector3(0, 1.585, -0.06)), Color("#3A2318"))
	# The jockey: a little bean crouched over the withers, silks and a cream cap.
	var bean := CapsuleMesh.new()
	bean.radius = 0.13
	bean.height = 0.46
	bean.radial_segments = 8
	bean.rings = 2
	mb.add(bean, Transform3D(Basis(Vector3.RIGHT, -0.75), Vector3(0, 1.82, -0.16)), silks)
	mb.add(_sphere(0.115), Transform3D(Basis(), Vector3(0, 2.04, -0.36)), Color("#E9C9A8"))
	var cap := SphereMesh.new()
	cap.radius = 0.122
	cap.height = 0.13
	cap.is_hemisphere = true
	cap.radial_segments = 8
	cap.rings = 2
	mb.add(cap, Transform3D(Basis(), Vector3(0, 2.07, -0.36)), Palette.CREAM)
	var brim := BoxMesh.new()
	brim.size = Vector3(0.14, 0.015, 0.09)
	mb.add(brim, Transform3D(Basis(), Vector3(0, 2.075, -0.49)), Palette.CREAM)
	for sx: float in [-1.0, 1.0]:  # arms down the neck to the reins
		var arm := CapsuleMesh.new()
		arm.radius = 0.045
		arm.height = 0.36
		arm.radial_segments = 6
		arm.rings = 1
		mb.add(arm, _along(Vector3(sx * 0.13, 1.9, -0.3), Vector3(sx * 0.1, 1.7, -0.62)), silks)
	body.add_child(_mesh(mb, "BodyMesh"))


func _build_leg(i: int, leg_c: Color, sock: bool) -> void:
	var spec: Array = LEGS[i]
	var fore: bool = spec[2]
	var hip := Node3D.new()
	hip.name = "Hip%d" % i
	hip.position = spec[0]
	body.add_child(hip)
	var upper := CylinderMesh.new()
	upper.top_radius = 0.12 if fore else 0.15
	upper.bottom_radius = 0.072
	upper.height = 0.5
	upper.radial_segments = 6
	upper.rings = 1
	var mb := _MeshBuilder.new()
	mb.add(upper, Transform3D(Basis(), Vector3(0, -0.25, 0)), leg_c)
	hip.add_child(_mesh(mb, "Upper"))
	var knee := Node3D.new()
	knee.name = "Knee"
	knee.position = Vector3(0, -0.5, 0)
	hip.add_child(knee)
	var lower := CylinderMesh.new()
	lower.top_radius = 0.062
	lower.bottom_radius = 0.052
	lower.height = 0.41
	lower.radial_segments = 6
	lower.rings = 1
	var hoof := CylinderMesh.new()
	hoof.top_radius = 0.058
	hoof.bottom_radius = 0.075
	hoof.height = 0.09
	hoof.radial_segments = 6
	hoof.rings = 1
	var lb := _MeshBuilder.new()
	lb.add(lower, Transform3D(Basis(), Vector3(0, -0.205, 0)), leg_c)
	if sock:
		var s := CylinderMesh.new()
		s.top_radius = 0.06
		s.bottom_radius = 0.058
		s.height = 0.14
		s.radial_segments = 6
		s.rings = 1
		lb.add(s, Transform3D(Basis(), Vector3(0, -0.34, 0)), Palette.CREAM)
	lb.add(hoof, Transform3D(Basis(), Vector3(0, -0.455, 0)), Color("#2A211C"))
	knee.add_child(_mesh(lb, "Lower"))
	hips.append(hip)
	knees.append(knee)
	_fore.append(fore)
	_offsets.append(float(spec[1]))


static func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 8
	s.rings = 4
	return s


## A transform that stands a Y-axis primitive (cylinder, capsule) between `from` and `to`.
static func _along(from: Vector3, to: Vector3) -> Transform3D:
	var d: Vector3 = (to - from).normalized()
	var axis: Vector3 = Vector3.UP.cross(d)
	var basis := Basis()
	if axis.length() > 0.0001:
		basis = Basis(axis.normalized(), Vector3.UP.angle_to(d))
	return Transform3D(basis, (from + to) * 0.5)


func _mesh(mb: _MeshBuilder, mesh_name: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = mesh_name
	mi.mesh = mb.commit()
	mi.material_override = shared_material()
	meshes.append(mi)
	return mi


## The one material every horse shares (colours are in the vertices).
static func shared_material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.roughness = 0.72
	return _material


## Merges primitive meshes (each with its own transform and flat colour) into one ArrayMesh.
class _MeshBuilder:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	func add(mesh: PrimitiveMesh, xf: Transform3D, color: Color) -> void:
		var a: Array = mesh.get_mesh_arrays()
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		var nb: Basis = xf.basis.inverse().transposed()
		var base: int = verts.size()
		for i: int in v.size():
			verts.append(xf * v[i])
			normals.append((nb * n[i]).normalized())
			colors.append(color)
		for i: int in idx:
			indices.append(base + i)

	func commit() -> ArrayMesh:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return m
