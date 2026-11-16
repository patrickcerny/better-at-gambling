class_name Cigarette
extends Node3D
## The animated cigarette mouth piece (Patrick 2026-11-16: "Animated zigarette for skin"): a
## cigarette held in the corner of the mouth that bobs gently, takes a drag every few seconds (it
## tips up, the ember brightens), and lets a thin wisp of smoke curl up from the tip, plus a small
## puff out of the mouth after each drag. Built like every other outfit piece (`OutfitMeshKit`,
## vertex colours, warm casino colours, no neon). `OutfitMeshes.mesh` uses `build` for the still
## model (ragdolls, shop thumbnails); a worn one is this node (`AvatarVisuals.wear`).
##
## Space: a pivot at the corner of the mouth (body space, `pivot`); the cigarette runs along the
## pivot's -Z, out of the face, the filter end a little inside the lips so it reads as held.

const ID := &"mouth_cigarette"

const PAPER := Color("#EFE8DA")
const FILTER := Color("#C98A4B")
const FILTER_DOT := Color("#A86C35")
const GOLD_BAND := Color("#D9AE52")
const ASH := Color("#8C8580")
const EMBER := Color("#E0602A")
const SMOKE := Color("#D8D0C4")

const RADIUS: float = 0.02
## Inside the lips, then filter, paper, ash, ember (pivot -Z).
const INSIDE: float = 0.02
const FILTER_LEN: float = 0.06
const PAPER_LEN: float = 0.15
const ASH_LEN: float = 0.012
const EMBER_LEN: float = 0.014

## A drag every `CYCLE` seconds: lifting for `DRAG` seconds, the exhale puff right after.
const CYCLE: float = 6.5
const DRAG: float = 1.3

var _t: float = 0.0
var _phase: float = 0.0
var _ember_mat: StandardMaterial3D = null
var _smoke: CPUParticles3D = null
var _puff: CPUParticles3D = null
var _puffed: bool = false
var _rest: Basis = Basis.IDENTITY


## Where the cigarette sits: the right corner of the mouth (body space), pointing out of the face,
## a little down and outward.
static func pivot() -> Transform3D:
	var my: float = OutfitMeshes._mouth_y() - 0.015
	var x: float = 0.075
	var at := Vector3(x, my, AvatarVisuals.face_z(my, x) + 0.006)
	var dir: Vector3 = Vector3(0.32, -0.24, -0.92).normalized()
	return Transform3D(Basis.looking_at(dir, Vector3.UP), at)


## Distance from the pivot to the tip (along -Z).
static func length() -> float:
	return FILTER_LEN + PAPER_LEN + ASH_LEN + EMBER_LEN - INSIDE


## The cigarette into `k` with `xf` (pivot space -> the kit's space); the ember too when `ember`.
static func build(k: OutfitMeshKit, xf: Transform3D, ember: bool) -> void:
	var old: Transform3D = k.xf
	k.xf = xf
	var along := Basis(Vector3.RIGHT, -PI * 0.5)  # the kit's cylinders stand along +Y; lay them along -Z
	var z: float = INSIDE  # +Z is into the mouth
	var f0: float = z
	k.cylinder(Vector3(0, 0, f0 - FILTER_LEN * 0.5), RADIUS, RADIUS, FILTER_LEN, FILTER, 10, along)
	for i: int in 7:  # cork speckles round the filter
		var a: float = TAU * float(i) / 7.0 + 0.4
		var zz: float = f0 - FILTER_LEN * (0.25 + 0.5 * float(i % 3) / 2.0)
		k.box(Vector3(cos(a) * RADIUS, sin(a) * RADIUS, zz), Vector3(0.008, 0.008, 0.006), FILTER_DOT, Basis(Vector3.BACK, a))
	z = f0 - FILTER_LEN
	k.cylinder(Vector3(0, 0, z), RADIUS + 0.002, RADIUS + 0.002, 0.006, GOLD_BAND, 10, along)  # the gold ring
	k.cylinder(Vector3(0, 0, z - PAPER_LEN * 0.5), RADIUS, RADIUS, PAPER_LEN, PAPER, 10, along)
	z -= PAPER_LEN
	k.cylinder(Vector3(0, 0, z - ASH_LEN * 0.5), RADIUS * 0.96, RADIUS, ASH_LEN, ASH, 10, along)
	if ember:
		z -= ASH_LEN
		_ember(k, z)
	k.xf = old


static func _ember(k: OutfitMeshKit, z: float) -> void:
	var along := Basis(Vector3.RIGHT, -PI * 0.5)
	k.cylinder(Vector3(0, 0, z - EMBER_LEN * 0.5), RADIUS * 0.82, RADIUS * 0.96, EMBER_LEN, OutfitMeshes._glow(EMBER, 0.9), 10, along)
	k.sphere(Vector3(0, 0, z - EMBER_LEN), Vector3(RADIUS * 0.8, RADIUS * 0.8, RADIUS * 0.45), OutfitMeshes._glow(EMBER, 0.9), 10, 4)


func _init() -> void:
	name = "Cigarette"
	transform = pivot()
	_rest = transform.basis
	_phase = randf() * CYCLE  # beans at one table don't all drag together


func _ready() -> void:
	var k := OutfitMeshKit.new()
	build(k, Transform3D.IDENTITY, false)
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = k.commit()
	body.material_override = OutfitMeshes.material()
	add_child(body)
	var ek := OutfitMeshKit.new()
	_ember(ek, -(length() - EMBER_LEN))
	var ember := MeshInstance3D.new()
	ember.name = "Ember"
	ember.mesh = ek.commit()
	_ember_mat = StandardMaterial3D.new()
	_ember_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ember_mat.albedo_color = EMBER
	_ember_mat.emission_enabled = true
	_ember_mat.emission = Color("#FF8A3D")
	_ember_mat.emission_energy_multiplier = 1.2
	ember.material_override = _ember_mat
	add_child(ember)
	if DisplayServer.get_name() == "headless":
		return
	_smoke = _wisps()
	_smoke.position = Vector3(0, 0, -length() - 0.01)
	add_child(_smoke)
	_puff = _exhale()
	_puff.position = Vector3(-0.05, 0.0, -0.02)  # out of the mouth, beside the cigarette
	add_child(_puff)


func _process(delta: float) -> void:
	_t += minf(delta, 0.1)
	var c: float = fposmod(_t + _phase, CYCLE)
	# The drag: up over the first half, held, back down; the ember brightens with it.
	var drag: float = 0.0
	if c < DRAG:
		drag = sin(PI * c / DRAG)
		drag = drag * drag
	var tilt: float = 0.05 * sin(_t * 1.7) + 0.16 * drag  # gentle bob, lifted on the drag
	var sway: float = 0.04 * sin(_t * 1.1 + 0.6)
	basis = _rest * Basis(Vector3.UP, sway) * Basis(Vector3.RIGHT, tilt)
	if _ember_mat != null:
		var flicker: float = 0.18 * sin(_t * 13.0) * sin(_t * 7.3)
		_ember_mat.emission_energy_multiplier = 1.6 + 2.6 * drag + flicker
	if _smoke != null:
		_smoke.gravity = Vector3(0.07 * sin(_t * 0.8), 0.2, 0.05 * cos(_t * 0.6))  # the wisp curls
		# Exhale shortly after the drag.
		if c > DRAG + 0.25 and not _puffed:
			_puffed = true
			_puff.restart()
		elif c < DRAG:
			_puffed = false


static func _smoke_mesh(size: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = size
	mesh.height = size * 2.0
	mesh.radial_segments = 6
	mesh.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color.WHITE
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material = mat
	return mesh


static func _fade(peak: float) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(SMOKE, 0.0))
	g.set_color(1, Color(SMOKE.lightened(0.1), 0.0))
	g.add_point(0.15, Color(SMOKE, peak))
	g.add_point(0.6, Color(SMOKE, peak * 0.55))
	return g


static func _grow(from: float, to: float) -> Curve:
	var curve := Curve.new()
	curve.max_value = maxf(from, to)
	curve.add_point(Vector2(0.0, from))
	curve.add_point(Vector2(1.0, to))
	return curve


## The thin wisp rising from the tip all the time (world space, so it trails behind a walking bean).
static func _wisps() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Smoke"
	p.amount = 28
	p.lifetime = 2.6
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 8.0
	p.initial_velocity_min = 0.06
	p.initial_velocity_max = 0.12
	p.gravity = Vector3(0, 0.2, 0)
	p.damping_min = 0.02
	p.damping_max = 0.06
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.1
	p.scale_amount_curve = _grow(0.5, 2.6)
	p.color_ramp = _fade(0.32)
	p.mesh = _smoke_mesh(0.02)
	p.emitting = true
	return p


## A small cloud out of the mouth after a drag (one burst, restarted each cycle).
static func _exhale() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Exhale"
	p.amount = 9
	p.one_shot = true
	p.explosiveness = 0.55
	p.lifetime = 1.8
	p.local_coords = false
	p.direction = Vector3(0, 0.4, -1)  # forward out of the face (pivot space), then up
	p.spread = 22.0
	p.initial_velocity_min = 0.12
	p.initial_velocity_max = 0.22
	p.gravity = Vector3(0, 0.16, 0)
	p.damping_min = 0.1
	p.damping_max = 0.2
	p.scale_amount_curve = _grow(0.6, 2.4)
	p.color_ramp = _fade(0.38)
	p.mesh = _smoke_mesh(0.02)
	p.emitting = false
	return p
