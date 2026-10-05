class_name RagdollBody
extends Node3D
## "Active ragdoll lite" (§2.4): 5 rigid bodies (torso, head, two hands, hips) on pin joints.
## Spawned when a player is knocked down, thrown or slips; reports hard impacts and settling.

## Emitted on a hard hit: `strength` is the speed lost in the collision (m/s), `wall` if the
## contact normal was mostly horizontal.
signal impact(strength: float, wall: bool)
## Emitted once the body has come to rest (or the time limit passed).
signal settled

const LAYER: int = 4
const MASK: int = 1 | 4 | 8
const SETTLE_SPEED: float = 0.35
const SETTLE_TIME: float = 0.4
const MIN_TIME: float = 0.8
const IMPACT_THRESHOLD: float = 4.5

var torso: RigidBody3D
var head: RigidBody3D
var hand_l: RigidBody3D
var hand_r: RigidBody3D
var hips: RigidBody3D
var color: Color = Palette.CREAM
var max_time: float = 2.5
## Player this ragdoll belongs to.
var player_id: int = -1
## Online clients: the server simulates the body; we only show its streamed pose (§4.1).
var puppet: bool = false

var _pose_pos: Vector3 = Vector3.INF
var _pose_rot: Quaternion = Quaternion.IDENTITY
var _pose_parts: Array[Vector3] = []

var _elapsed: float = 0.0
var _still: float = 0.0
var _done: bool = false
var _prev_vel: Vector3 = Vector3.ZERO


func _ready() -> void:
	_build()


## Launches the whole body with a velocity.
func launch(velocity: Vector3) -> void:
	if puppet:
		return
	for b: RigidBody3D in [torso, head, hand_l, hand_r, hips]:
		b.linear_velocity = velocity
	_prev_vel = velocity


## World position of the torso (where the player gets up).
func body_position() -> Vector3:
	return torso.global_position


## Current pose for the world stream: torso position/rotation and head, hands, hips positions.
func pose() -> Dictionary:
	return {"pos": torso.global_position, "rot": torso.global_basis.get_rotation_quaternion(), "parts": [head.global_position, hand_l.global_position, hand_r.global_position, hips.global_position]}


## Puppet: the server's pose to ease toward.
func apply_pose(pos: Vector3, rot: Quaternion, parts: Array) -> void:
	var first: bool = _pose_pos == Vector3.INF
	_pose_pos = pos
	_pose_rot = rot
	_pose_parts.assign(parts)
	if first:
		_snap_to_pose(1.0)


func _snap_to_pose(w: float) -> void:
	if _pose_pos == Vector3.INF:
		return
	torso.global_position = torso.global_position.lerp(_pose_pos, w)
	torso.quaternion = torso.quaternion.slerp(_pose_rot, w)
	var bodies: Array[RigidBody3D] = [head, hand_l, hand_r, hips]
	for i: int in mini(bodies.size(), _pose_parts.size()):
		bodies[i].global_position = bodies[i].global_position.lerp(_pose_parts[i], w)


func _physics_process(delta: float) -> void:
	if puppet:
		_snap_to_pose(minf(1.0, 20.0 * delta))
		return
	if _done:
		return
	_elapsed += delta
	var v: Vector3 = torso.linear_velocity
	var lost: float = (_prev_vel - v).length()
	if lost > IMPACT_THRESHOLD and _elapsed > 0.05:
		# Only a real contact counts: the pin joints can jolt the torso on the first frames of a
		# throw, and that must never read as a wall hit. A wall is static world geometry (layer 1).
		var hit_world: bool = false
		var touched: bool = false
		for body: Node in torso.get_colliding_bodies():
			touched = true
			if body is CollisionObject3D and ((body as CollisionObject3D).collision_layer & 1) != 0:
				hit_world = true
		if touched:
			var horizontal: bool = absf(_prev_vel.x - v.x) + absf(_prev_vel.z - v.z) > absf(_prev_vel.y - v.y)
			impact.emit(lost, horizontal and hit_world)
	_prev_vel = v
	if v.length() < SETTLE_SPEED and _elapsed > MIN_TIME:
		_still += delta
	else:
		_still = 0.0
	if _still >= SETTLE_TIME or _elapsed >= max_time:
		_done = true
		settled.emit()


func _build() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	torso = _body("Torso", Vector3(0, 0.9, 0), _capsule(0.4, 1.2), mat, 6.0)
	head = _body("Head", Vector3(0, 1.75, 0), _sphere(0.3), mat, 1.5)
	hand_l = _body("HandL", Vector3(-0.75, 0.9, 0), _sphere(0.14), GreyboxKit.material(Palette.CREAM), 0.5)
	hand_r = _body("HandR", Vector3(0.75, 0.9, 0), _sphere(0.14), GreyboxKit.material(Palette.CREAM), 0.5)
	hips = _body("Hips", Vector3(0, 0.25, 0), _box(Vector3(0.5, 0.3, 0.4)), GreyboxKit.material(Palette.CASINO_BLACK), 2.0)
	if puppet:
		for b: RigidBody3D in [torso, head, hand_l, hand_r, hips]:
			b.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			b.freeze = true
			b.collision_layer = 0
			b.contact_monitor = false
	else:
		_pin(torso, head, Vector3(0, 1.5, 0))
		_pin(torso, hand_l, Vector3(-0.45, 1.1, 0))
		_pin(torso, hand_r, Vector3(0.45, 1.1, 0))
		_pin(torso, hips, Vector3(0, 0.4, 0))
	# Dot eyes on the head so it still reads as a face while flopping.
	var dark: StandardMaterial3D = GreyboxKit.material(Palette.CASINO_BLACK)
	for x: float in [-0.1, 0.1]:
		var e := MeshInstance3D.new()
		e.mesh = _sphere(0.04)
		e.material_override = dark
		e.position = Vector3(x, 0.05, -0.27)
		head.add_child(e)


func _body(name: String, pos: Vector3, mesh: Mesh, mat: Material, mass: float) -> RigidBody3D:
	var b := RigidBody3D.new()
	b.name = name
	b.mass = mass
	b.collision_layer = LAYER
	b.collision_mask = MASK
	b.position = pos
	b.linear_damp = 0.4
	b.angular_damp = 1.0
	b.continuous_cd = true
	b.contact_monitor = true
	b.max_contacts_reported = 4
	b.set_meta(&"ragdoll", self)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	b.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_convex_shape() if mesh is BoxMesh else _shape_for(mesh)
	b.add_child(cs)
	add_child(b)
	return b


func _shape_for(mesh: Mesh) -> Shape3D:
	if mesh is CapsuleMesh:
		var s := CapsuleShape3D.new()
		s.radius = (mesh as CapsuleMesh).radius
		s.height = (mesh as CapsuleMesh).height
		return s
	var sp := SphereShape3D.new()
	sp.radius = (mesh as SphereMesh).radius
	return sp


func _pin(a: RigidBody3D, b: RigidBody3D, pos: Vector3) -> void:
	var j := PinJoint3D.new()
	j.position = pos
	add_child(j)
	j.node_a = a.get_path()
	j.node_b = b.get_path()


func _capsule(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	return m


func _sphere(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	return m


func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m
