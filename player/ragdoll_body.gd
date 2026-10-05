class_name RagdollBody
extends Node3D
## "Active ragdoll lite" (§2.4): 5 rigid bodies (torso, head, two hands, hips) on pin joints.
## Spawned when a player is knocked down, thrown or slips; reports hard impacts and settling.
## The bodies are the physics (simulated on the server, streamed to clients); on top of them sits a
## purely visual layer (M7) that never touches the simulation: floppy arms from the shoulders to the
## hands, little kicking legs, hands that flail while the body flies, and X eyes when knocked out.

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
## Character skin: when it has a model, that model rides the torso instead of the bean parts.
var skin: StringName = &"bean"
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

## Visual-only flail layer (built only with a display, and only for the bean).
var _arm_meshes: Array[MeshInstance3D] = []
var _hand_meshes: Array[MeshInstance3D] = []
var _leg_pivots: Array[Node3D] = []
var _eyes: Array[MeshInstance3D] = []
var _x_eyes: Array[Node3D] = []
var _dazed: bool = false
var _skinned: bool = false
var _vis_t: float = 0.0
var _vis_prev: Vector3 = Vector3.INF
var _vis_speed: float = 0.0


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
		_eyes.append(e)
	_skinned = _wear_skin()
	if not _skinned and DisplayServer.get_name() != "headless":
		_build_flail(mat, dark)
	set_dazed(_dazed)


## Knocked out: the dot eyes turn into little crosses.
func set_dazed(on: bool) -> void:
	_dazed = on
	for e: MeshInstance3D in _eyes:
		e.visible = not on and not _skinned
	for x: Node3D in _x_eyes:
		x.visible = on


## Visual arms (shoulder to hand), legs on the hips and X eyes. Children of the bodies or of this
## node; no collision, no mass.
func _build_flail(mat: Material, dark: Material) -> void:
	for i: int in 2:
		var arm := MeshInstance3D.new()
		arm.name = "ArmVis%d" % i
		var cm := CapsuleMesh.new()
		cm.radius = 0.07
		cm.height = 1.0
		arm.mesh = cm
		arm.material_override = mat
		add_child(arm)
		_arm_meshes.append(arm)
	for hb: RigidBody3D in [hand_l, hand_r]:
		for c: Node in hb.get_children():
			if c is MeshInstance3D:
				_hand_meshes.append(c)
	for x: float in [-0.14, 0.14]:
		var pivot := Node3D.new()
		pivot.name = "LegVis"
		pivot.position = Vector3(x, -0.12, 0.0)
		hips.add_child(pivot)
		var leg := MeshInstance3D.new()
		var lm := CapsuleMesh.new()
		lm.radius = 0.09
		lm.height = 0.34
		leg.mesh = lm
		leg.material_override = dark
		leg.position = Vector3(0.0, -0.12, 0.0)
		pivot.add_child(leg)
		_leg_pivots.append(pivot)
	for x: float in [-0.1, 0.1]:
		var cross := Node3D.new()
		cross.name = "XEye"
		cross.position = Vector3(x, 0.05, -0.27)
		cross.visible = false
		head.add_child(cross)
		for a: float in [PI * 0.25, -PI * 0.25]:
			var bar := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.11, 0.025, 0.025)
			bar.mesh = bm
			bar.material_override = dark
			bar.rotation.z = a
			cross.add_child(bar)
		_x_eyes.append(cross)


func _process(delta: float) -> void:
	if _arm_meshes.is_empty() or torso == null:
		return
	_vis_t += delta
	var tp: Vector3 = torso.global_position
	if _vis_prev != Vector3.INF and delta > 0.0:
		_vis_speed = lerpf(_vis_speed, (tp - _vis_prev).length() / delta, 0.2)
	_vis_prev = tp
	# Flail while the body flies; limp once it lies still.
	var flail: float = clampf((_vis_speed - 0.6) / 5.0, 0.0, 1.0)
	var tb: Basis = torso.global_basis
	var hands: Array[RigidBody3D] = [hand_l, hand_r]
	for i: int in 2:
		var side: float = -1.0 if i == 0 else 1.0
		var shoulder: Vector3 = torso.global_transform * Vector3(side * 0.38, 0.3, 0.0)
		var wiggle: Vector3 = tb * Vector3(side * sin(_vis_t * 19.0 + i) * 0.25, cos(_vis_t * 23.0 + i * 2.0) * 0.3, sin(_vis_t * 15.0 + i) * 0.25) * flail
		var hand_pos: Vector3 = hands[i].global_position + wiggle
		if i < _hand_meshes.size():
			_hand_meshes[i].global_position = hand_pos
		var arm: MeshInstance3D = _arm_meshes[i]
		var span: Vector3 = hand_pos - shoulder
		var length: float = maxf(span.length(), 0.05)
		var up: Vector3 = span / length
		var side_axis: Vector3 = up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
		var fwd: Vector3 = side_axis.cross(up).normalized()
		arm.global_transform = Transform3D(Basis(side_axis, up * length, fwd), shoulder + span * 0.5)
	for i: int in _leg_pivots.size():
		_leg_pivots[i].rotation.x = sin(_vis_t * 21.0 + i * PI) * 0.9 * flail


## Hides the bean parts and pins the skin model to the torso (it tumbles stiffly, in its idle pose).
## Returns whether a skin model is worn.
func _wear_skin() -> bool:
	var model: Node3D = SkinLibrary.instantiate(skin)
	if model == null:
		return false
	for b: RigidBody3D in [torso, head, hand_l, hand_r, hips]:
		for mi: Node in b.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).visible = false
	torso.add_child(model)
	model.position.y = -0.9
	SkinLibrary.relax_pose(model)
	var ap: AnimationPlayer = SkinLibrary.animation_player(model)
	if ap != null:
		var hit: StringName = SkinLibrary.clip(ap, &"idle")
		if hit != &"":
			ap.play(hit)
	return true


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
