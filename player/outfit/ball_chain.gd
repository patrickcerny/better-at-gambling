class_name BallChain
extends Node3D
## The Jailbird boots' ball and chain (Patrick 2026-11-17: "ball and chain actually freely wiggly
## not attach hard"): a loose chain from the ankle shackle to an iron ball, simulated as a little
## rope (Verlet points, fixed length links) in world space, so it swings, drags and lands on the
## floor wherever the foot goes. Lives under the boot (`AvatarVisuals`), drawn in world space
## (`top_level`); everything is cosmetic, nothing collides with the world but the floor.

const LINKS: int = 9
const LINK_LEN: float = 0.045
const BALL_R: float = 0.105
const LINK_R: float = 0.03
const GRAVITY: float = 9.8
const STEP: float = 1.0 / 60.0
const ITERATIONS: int = 6
## Where the chain hangs from, in the boot's space (the ring at the back of the shackle).
const ANCHOR: Vector3 = Vector3(0.0, 0.07, 0.125)
## The foot's centre sits this high over the floor (boot space).
const FOOT_LIFT: float = 0.065

var _anchor_node: Node3D
var _pts: PackedVector3Array = []
var _prev: PackedVector3Array = []
var _links: Array[MeshInstance3D] = []
var _ball: MeshInstance3D
var _acc: float = 0.0
var _scale: float = 1.0


## A chain hanging from `holder` (the right boot), laid out behind the foot and settled.
static func make(holder: Node3D) -> BallChain:
	var c := BallChain.new()
	c.name = "BallChain"
	c._anchor_node = holder
	holder.add_child(c)
	return c


func _ready() -> void:
	top_level = true
	var link_mesh: ArrayMesh = _link_mesh()
	for i: int in LINKS:
		var mi: MeshInstance3D = AvatarVisuals._outfit_mesh(link_mesh, "Link%d" % i)
		add_child(mi)
		_links.append(mi)
	var k := OutfitMeshKit.new()
	k.sphere(Vector3.ZERO, Vector3.ONE * BALL_R, Color("#4A4744"), 16, 10)
	k.sphere(Vector3(-0.035, 0.05, -0.04), Vector3.ONE * 0.022, OutfitMeshes._glow(OutfitMeshes.WHITE, 0.15), 6, 3)
	k.torus(Vector3(0, BALL_R * 0.95, 0), 0.012, 0.026, OutfitMeshes.STEEL.darkened(0.3), 8, Basis(Vector3.FORWARD, PI * 0.5))
	_ball = AvatarVisuals._outfit_mesh(k.commit(), "Ball")
	add_child(_ball)
	reset()


func _link_mesh() -> ArrayMesh:
	var k := OutfitMeshKit.new()
	# Along +Z (the way to the next point), an oval ring.
	k.torus(Vector3.ZERO, 0.012, LINK_R, OutfitMeshes.STEEL, 8, Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(1.0, 1.0, 1.35)))
	return k.commit()


## Lays the chain out straight behind the foot and lets it settle (new outfit, respawn, teleport).
func reset() -> void:
	if _anchor_node == null or not _anchor_node.is_inside_tree():
		return
	_scale = maxf(_anchor_node.global_transform.basis.get_scale().y, 0.01)
	var a: Vector3 = _anchor_world()
	var back: Vector3 = _anchor_node.global_transform.basis * Vector3(0, 0, 1)
	back.y = 0.0
	back = back.normalized() if back.length() > 0.01 else Vector3.BACK
	_pts.resize(LINKS + 1)
	_prev.resize(LINKS + 1)
	for i: int in LINKS + 1:
		_pts[i] = a + back * LINK_LEN * _scale * float(i)
		_prev[i] = _pts[i]
	for i: int in 90:
		_step(STEP)
	_draw_chain()


func _anchor_world() -> Vector3:
	return _anchor_node.global_transform * ANCHOR


func _floor_y() -> float:
	return (_anchor_node.global_transform * Vector3(0, -FOOT_LIFT, 0)).y if _anchor_node != null else 0.0


func _process(delta: float) -> void:
	if _anchor_node == null or not _anchor_node.is_inside_tree() or _pts.is_empty():
		return
	# Teleported (respawn, a new seat): start over instead of a mile-long chain.
	if _pts[0].distance_to(_anchor_world()) > 1.5:
		reset()
		return
	_acc = minf(_acc + delta, STEP * 4.0)
	while _acc >= STEP:
		_acc -= STEP
		_step(STEP)
	_draw_chain()


func _step(dt: float) -> void:
	var n: int = _pts.size()
	var floor_y: float = _floor_y()
	var seg: float = LINK_LEN * _scale
	for i: int in range(1, n):
		var p: Vector3 = _pts[i]
		var v: Vector3 = (p - _prev[i]) * 0.985
		_prev[i] = p
		_pts[i] = p + v + Vector3(0, -GRAVITY * dt * dt, 0)
	_pts[0] = _anchor_world()
	for _it: int in ITERATIONS:
		for i: int in range(1, n):
			var a: Vector3 = _pts[i - 1]
			var b: Vector3 = _pts[i]
			var d: Vector3 = b - a
			var len: float = d.length()
			var want: float = seg if i < n - 1 else seg + (BALL_R - LINK_R) * _scale
			if len < 0.0001:
				continue
			var fix: Vector3 = d * ((len - want) / len)
			if i == 1:
				_pts[i] = b - fix  # the first link hangs from the shackle
			elif i == n - 1:
				_pts[i - 1] = a + fix * 0.8  # the heavy ball barely gives
				_pts[i] = b - fix * 0.2
			else:
				_pts[i - 1] = a + fix * 0.5
				_pts[i] = b - fix * 0.5
		# The floor: links and the ball rest on it, the ball drags (friction).
		for i: int in range(1, n):
			var r: float = (BALL_R if i == n - 1 else LINK_R * 0.5) * _scale
			if _pts[i].y < floor_y + r:
				_pts[i].y = floor_y + r
				var slide: Vector3 = _pts[i] - _prev[i]
				_prev[i] = _pts[i] - Vector3(slide.x * (0.6 if i == n - 1 else 0.85), 0.0, slide.z * (0.6 if i == n - 1 else 0.85))


func _draw_chain() -> void:
	var n: int = _pts.size()
	for i: int in LINKS:
		var a: Vector3 = _pts[i]
		var b: Vector3 = _pts[i + 1]
		var d: Vector3 = b - a
		if i == LINKS - 1:
			d = d.normalized() * LINK_LEN * _scale  # the last link sits at the ball's ring
			b = a + d
		var mid: Vector3 = (a + b) * 0.5
		var basis := Basis.IDENTITY
		if d.length() > 0.0001:
			var up: Vector3 = Vector3.UP if absf(d.normalized().y) < 0.95 else Vector3.RIGHT
			basis = Basis.looking_at(-d.normalized(), up) * Basis(Vector3.BACK, PI * 0.5 * float(i % 2))
		_links[i].global_transform = Transform3D(basis.scaled(Vector3.ONE * _scale), mid)
	var last: Vector3 = _pts[n - 1]
	var from: Vector3 = (last - _pts[n - 2]).normalized()
	var ball_basis := Basis.IDENTITY
	if from.length() > 0.5 and absf(from.y) < 0.99:
		ball_basis = Basis.looking_at(from, Vector3.UP) * Basis(Vector3.RIGHT, PI * 0.5)  # its ring towards the chain
	_ball.global_transform = Transform3D(ball_basis.scaled(Vector3.ONE * _scale), last)
