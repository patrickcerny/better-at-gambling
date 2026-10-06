class_name AvatarVisuals
extends Node3D
## The bean: capsule body in the player colour, dot eyes, a `-`/`o`/`O` mouth driven by voice,
## long floppy arms with oversized hands, or a character skin. Procedural animation (M7): spring
## lean on acceleration, squash on landing and stretch in the air, idle bob, blinking, a banana
## slip, cheering / sulking / big-win reactions with matching faces (eyes widen on wins, droop on
## losses), flailing while carried, a wobbly get-up after a ragdoll, and knockout birdies.
## (docs/ART_DIRECTION.md)
##
## `update_motion` feeds movement in; everything is drawn once per frame in `_process`, so beans
## nobody moves (quiz podiums, results) still react. Headless (servers, tests) only the state is
## kept: no animation runs.

const BODY_RADIUS: float = 0.42
const BODY_HEIGHT: float = 1.5
const EYE_Y: float = 1.12
## Arms hang down at rest (pitch of the arm pivot; 0 points forward, +PI/2 up).
const ARM_REST: float = -1.3
## Reaction lengths in seconds.
const REACTIONS: Dictionary = {
	&"win": 1.4, &"loss": 1.6, &"big_win": 2.6, &"slip": 1.1, &"surprise": 0.8, &"ko": 1.2, &"wake": 0.6,
}
## Reaction names other code uses for the same thing.
const ALIASES: Dictionary = {&"lose": &"loss", &"sad": &"loss", &"cheer": &"win", &"jackpot": &"big_win"}
## Round results at least this big get the big-win celebration.
const BIG_WIN: int = 500
## The bean's centre of rotation for whole-body poses (slip, get-up), near the bottom of the body.
const PIVOT: Vector3 = Vector3(0.0, 0.42, 0.0)
const GET_UP_SECONDS: float = 0.55

var body: MeshInstance3D
var eye_l: MeshInstance3D
var eye_r: MeshInstance3D
var mouth: MeshInstance3D
var arm_l: Node3D
var arm_r: Node3D
var hand_l: MeshInstance3D
var hand_r: MeshInstance3D
## Top of the head (guards wear their cap here).
var hat_slot: Node3D
## Knockout stars and birdies (a `KnockoutOrbit`); visible while knocked out.
var stars: Node3D
var color: Color = Palette.CREAM
## Character skin (`Cosmetics.SKINS`); &"bean" shows the procedural bean.
var skin_id: StringName = &"bean"
## The skin model while one is worn (bean parts are hidden then).
var skin_root: Node3D
## Set while the player sits at a station (skins with a sitting clip use it).
var sitting: bool = false
## Set while a guard carries this bean out over their head (lies flat and flails).
var carried: bool = false
var knocked_out: bool = false

## 0 = closed `-`, ~0.5 = `o`, 1 = `O`.
var mouth_open: float = 0.0
## Where the arms reach (local, null = relaxed).
var reach_target: Vector3 = Vector3.ZERO
var reaching: bool = false
## The reaction playing now (&"" = none) and for how long it has played.
var reaction: StringName = &""
var reaction_time: float = 0.0

var _rig: Node3D
var _lean: Vector2 = Vector2.ZERO
var _lean_vel: Vector2 = Vector2.ZERO
var _squash: float = 1.0
var _squash_vel: float = 0.0
var _prev_velocity: Vector3 = Vector3.ZERO
var _velocity: Vector3 = Vector3.ZERO
var _accel_local: Vector2 = Vector2.ZERO
var _on_floor: bool = true
var _was_on_floor: bool = true
var _land_kick: float = 0.0
var _time: float = 0.0
var _eye_scale: float = 1.0
var _eye_open: float = 1.0
var _blink_in: float = 2.5
var _mouth_smoothed: float = 0.0
var _face_mouth: float = 0.0
var _get_up_from: Quaternion = Quaternion.IDENTITY
var _get_up_t: float = -1.0
var _ragdoll: RagdollBody = null
var _body_mat: Material
var _legs: Array[MeshInstance3D] = []
var _anim: AnimationPlayer
var _motion: StringName = &""
## Player-colored ring at the feet: skins hide the bean, so this keeps who-is-who readable.
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _headless: bool = false


func _ready() -> void:
	_headless = DisplayServer.get_name() == "headless"
	_build()
	if skin_id != &"bean":
		var id: StringName = skin_id
		skin_id = &"bean"
		set_skin(id)


## Applies the player colour.
func set_color(c: Color) -> void:
	color = c
	if _body_mat != null:
		ToonMaterial.set_color(_body_mat, c)
	if _ring_mat != null:
		_ring_mat.albedo_color = c


## Swaps between the bean and a character skin (see `SkinLibrary`).
func set_skin(id: StringName) -> void:
	if id == skin_id:
		return
	skin_id = id
	if body == null:
		return  # applied in _ready
	if skin_root != null:
		skin_root.queue_free()
		skin_root = null
	_anim = null
	_motion = &""
	var model: Node3D = SkinLibrary.instantiate(id)
	if model != null:
		_rig.add_child(model)
		skin_root = model
		SkinLibrary.relax_pose(model)
		_anim = SkinLibrary.animation_player(model)
		_play(&"idle")
	var bean: bool = skin_root == null
	body.visible = bean
	arm_l.visible = bean
	arm_r.visible = bean
	for leg: MeshInstance3D in _legs:
		leg.visible = bean
	_ring.visible = not bean and _rig.visible


func _play(motion: StringName) -> void:
	if _anim == null or motion == _motion:
		return
	var a: StringName = SkinLibrary.clip(_anim, motion)
	if a == &"" and motion == &"sit":
		a = SkinLibrary.clip(_anim, &"idle")
	if a == &"":
		return
	_motion = motion
	_anim.play(a, 0.2)


## Half-transparent "away" look for disconnected players.
func set_ghost(on: bool) -> void:
	for n: Node in find_children("*", "GeometryInstance3D", true, false):
		(n as GeometryInstance3D).transparency = 0.55 if on else 0.0


## Movement input for the procedural animation (call once per physics frame).
func update_motion(velocity: Vector3, on_floor: bool, delta: float) -> void:
	var accel: Vector3 = (velocity - _prev_velocity) / maxf(delta, 0.0001)
	# Local-space acceleration drives the lean (forward acceleration tips the bean back).
	var local_acc: Vector3 = global_transform.basis.inverse() * Vector3(accel.x, 0.0, accel.z)
	_accel_local = _accel_local.lerp(Vector2(local_acc.z, local_acc.x), 0.5)
	if on_floor and not _was_on_floor and _prev_velocity.y < -2.0:
		_land_kick = maxf(_land_kick, clampf(-_prev_velocity.y, 0.0, 14.0))
	elif not on_floor and _was_on_floor and velocity.y > 2.5:
		_squash_vel += 3.5  # take-off pop
	_was_on_floor = on_floor
	_on_floor = on_floor
	_velocity = velocity
	_prev_velocity = velocity
	if skin_root != null:
		var speed: float = Vector2(velocity.x, velocity.z).length()
		if sitting:
			_play(&"sit")
		elif speed > 4.2:
			_play(&"run")
		elif speed > 0.4:
			_play(&"walk")
		else:
			_play(&"idle")


## Plays a reaction: &"win" (cheer, eyes wide), &"loss" / &"lose" (sulk, eyes droop), &"big_win"
## (jump, spin, both arms up), &"slip" (feet fly up), &"surprise", and the state hooks &"ko" /
## &"wake". Unknown names (e.g. &"idle") just reset the face.
func react(kind: StringName) -> void:
	var k: StringName = ALIASES.get(kind, kind)
	match k:
		&"ko":
			set_knocked_out(true)
		&"wake":
			set_knocked_out(false)
	if not REACTIONS.has(k):
		reaction = &""
		return
	# A small win doesn't interrupt a big celebration that just started.
	if reaction == &"big_win" and k == &"win" and reaction_time < 1.0:
		return
	reaction = k
	reaction_time = 0.0


## The reaction for a round's net result.
static func reaction_for_net(net: int) -> StringName:
	if net >= BIG_WIN:
		return &"big_win"
	return &"win" if net > 0 else &"loss"


## Shows the knockout stars and birdies.
func set_knocked_out(ko: bool) -> void:
	knocked_out = ko
	if stars != null:
		stars.visible = ko
	if _ragdoll != null and is_instance_valid(_ragdoll):
		_ragdoll.set_dazed(ko)


## While ragdolled the bean is hidden and the ragdoll stands in for it; the knockout halo follows
## the ragdoll's head. `null` brings the bean back.
func set_ragdoll(rb: RagdollBody) -> void:
	_ragdoll = rb
	_rig.visible = rb == null
	_ring.visible = rb == null and skin_root != null
	var orbit: KnockoutOrbit = stars as KnockoutOrbit
	if orbit != null:
		orbit.follow = rb.head if rb != null else null
	if rb != null:
		rb.set_dazed(knocked_out)


## Lying bean pops back up: starts tilted like `torso_up` (world up axis of the ragdoll's torso)
## and springs upright with a little wobble.
func get_up(torso_up: Vector3) -> void:
	var up_local: Vector3 = (global_basis.inverse() * torso_up).normalized()
	if up_local.length() < 0.5 or up_local.dot(Vector3.UP) > 0.97:
		return
	if up_local.dot(Vector3.UP) < -0.9:
		up_local = Vector3(0.0, 0.0, 1.0)  # upside down: come up from flat on the back instead
	_get_up_from = Quaternion(Vector3.UP, up_local)
	_get_up_t = 0.0
	_squash = 0.8


## Starts/ends the carried pose (flat, arms and legs flailing).
func set_carried(on: bool) -> void:
	carried = on
	if on:
		reaction = &""


func _process(delta: float) -> void:
	if _headless or not is_visible_in_tree():
		return
	_animate(delta)


func _animate(frame_delta: float) -> void:
	# Springs and smoothing are explicit steps: a long frame (loading, a slow machine) must not
	# blow them up, so they never step more than 1/30 s at a time.
	var delta: float = minf(frame_delta, 1.0 / 30.0)
	_time += delta
	if reaction != &"":
		reaction_time += delta
		if reaction_time >= float(REACTIONS[reaction]):
			reaction = &""
	var speed: float = Vector2(_velocity.x, _velocity.z).length()
	var walk: float = clampf(speed / 5.0, 0.0, 1.0)
	# Lean spring (like a slightly drunk bean), plus a walking waddle.
	var target: Vector2 = Vector2(clampf(-_accel_local.x * 0.012, -0.35, 0.35), clampf(_accel_local.y * 0.012, -0.35, 0.35))
	target.x += sin(_time * 9.0) * 0.03 * walk
	if reaction == &"loss":
		target.x -= 0.28  # slumped forward
	_lean_vel += (target - _lean) * 60.0 * delta - _lean_vel * 8.0 * delta
	_lean += _lean_vel * delta
	body.rotation = Vector3(_lean.x, 0.0, -_lean.y + (sin(_time * 3.0) * 0.06 if reaction == &"loss" else 0.0))
	# Squash and stretch: stretch along the fall/jump speed, squash on landing.
	var squash_target: float = 1.0
	if not _on_floor and not carried:
		squash_target = 1.0 + clampf(absf(_velocity.y) * 0.022, 0.0, 0.22)
	if _land_kick > 0.0:
		_squash_vel -= 1.2 + _land_kick * 0.55
		_land_kick = 0.0
	_squash_vel += (squash_target - _squash) * 120.0 * delta - _squash_vel * 10.0 * delta
	_squash = clampf(_squash + _squash_vel * delta, 0.55, 1.35)
	var bob: float = 1.0 + sin(_time * 2.2) * 0.012
	var sq: Vector3 = Vector3(1.0 / sqrt(_squash), _squash * bob, 1.0 / sqrt(_squash))
	body.scale = sq
	if skin_root != null:
		skin_root.rotation = Vector3(_lean.x * 0.6, 0.0, -_lean.y * 0.6)
		skin_root.scale = Vector3(sq.x, _squash, sq.z)
	_animate_rig()
	_animate_arms(walk)
	_animate_legs(walk)
	_animate_face(delta)
	if reaching:
		_point_arms(reach_target)


## Whole-body pose on the rig: slip, big-win hop and spin, carried, get-up.
func _animate_rig() -> void:
	var pitch: float = 0.0
	var roll: float = 0.0
	var spin: float = 0.0
	var lift: Vector3 = Vector3.ZERO
	var t: float = reaction_time
	match reaction:
		&"slip":
			# Feet fly forward and up, the bean lands on its back, then bounces upright.
			var e: float = _slip_curve(t)
			pitch = 1.45 * e
			lift.y = sin(clampf(t / 0.35, 0.0, 1.0) * PI) * 0.35
		&"big_win":
			var hop: float = absf(sin(t * TAU * 1.6)) if t < 1.9 else 0.0
			lift.y = hop * 0.45
			spin = TAU * smoothstep(0.25, 0.95, t)
		&"win":
			lift.y = absf(sin(t * TAU * 1.8)) * 0.18 if t < 1.1 else 0.0
		&"surprise":
			lift.y = sin(clampf(t / 0.3, 0.0, 1.0) * PI) * 0.2
	if carried:
		roll = -PI * 0.5
		lift = Vector3(-(BODY_HEIGHT * 0.5 - PIVOT.y), 0.0, 0.0)  # centre the lying body
	var q: Quaternion = Quaternion.from_euler(Vector3(pitch, spin, roll))
	if _get_up_t >= 0.0:
		_get_up_t += minf(get_process_delta_time(), 1.0 / 30.0)
		var k: float = clampf(_get_up_t / GET_UP_SECONDS, 0.0, 1.0)
		# Back-out ease: overshoots upright a touch, like a bean flopping up.
		var e: float = 1.0 + 2.2 * pow(k - 1.0, 3.0) + 1.2 * pow(k - 1.0, 2.0)
		q = _get_up_from.slerp(Quaternion.IDENTITY, clampf(e, 0.0, 1.15)) * q
		if k >= 1.0:
			_get_up_t = -1.0
	var b: Basis = Basis(q)
	_rig.transform = Transform3D(b, PIVOT - b * PIVOT + lift)


func _slip_curve(t: float) -> float:
	if t < 0.18:
		return smoothstep(0.0, 0.18, t)
	if t < 0.5:
		return 1.0
	return 1.0 - smoothstep(0.5, 1.05, t)


func _animate_arms(walk: float) -> void:
	var t: float = reaction_time
	var swing: float = sin(_time * 10.0) * 0.45 * walk
	var l: Vector2 = Vector2(ARM_REST + swing, -0.12)  # (pitch, splay)
	var r: Vector2 = Vector2(ARM_REST - swing, -0.12)
	if not _on_floor and not carried:
		# Airborne: arms fly up and windmill a little.
		var up: float = clampf(absf(_velocity.y) / 8.0, 0.0, 1.0)
		l = Vector2(lerpf(l.x, 0.6 + sin(_time * 17.0) * 0.5, up), -0.5 * up)
		r = Vector2(lerpf(r.x, 0.6 + cos(_time * 17.0) * 0.5, up), -0.5 * up)
	match reaction:
		&"win", &"big_win":
			var fast: float = 16.0 if reaction == &"big_win" else 12.0
			l = Vector2(1.75 + sin(t * fast) * 0.3, 0.45)
			r = Vector2(1.75 + sin(t * fast + PI) * 0.3, 0.45)
		&"loss":
			l = Vector2(-1.5, 0.02)
			r = Vector2(-1.5, 0.02)
		&"slip", &"surprise":
			l = Vector2(1.2 + sin(t * 25.0) * 0.6, 0.8)
			r = Vector2(1.2 + cos(t * 23.0) * 0.6, 0.8)
	if carried:
		l = Vector2(0.4 + sin(_time * 19.0) * 0.8, 0.3 + cos(_time * 13.0) * 0.4)
		r = Vector2(0.4 + cos(_time * 17.0) * 0.8, 0.3 + sin(_time * 11.0) * 0.4)
	_set_arm(arm_l, l.x, l.y)
	_set_arm(arm_r, r.x, -r.y)


## `splay` rolls the arm outward from the body (positive = away from the body for the left arm).
func _set_arm(pivot: Node3D, pitch: float, splay: float) -> void:
	pivot.basis = Basis(Vector3.BACK, splay) * Basis(Vector3.RIGHT, pitch)


func _animate_legs(walk: float) -> void:
	var kick: float = 0.0
	if carried or reaction == &"slip":
		kick = 0.9
	for i: int in _legs.size():
		var phase: float = 0.0 if i == 0 else PI
		_legs[i].rotation.x = sin(_time * 10.0 + phase) * 0.5 * walk + sin(_time * 24.0 + phase) * kick


func _animate_face(delta: float) -> void:
	var t: float = reaction_time
	# Eye size and openness per reaction.
	var size: float = 1.0
	var open: float = 1.0
	var face_mouth: float = 0.0
	match reaction:
		&"win":
			size = 1.7
			face_mouth = 0.55
		&"big_win":
			size = 2.0
			face_mouth = 1.0 if t < 1.8 else 0.5
		&"loss":
			size = 0.9
			open = 0.35
		&"slip", &"surprise":
			size = 1.9
			face_mouth = 1.0
	if carried:
		size = 1.8
		face_mouth = 0.8 + sin(_time * 14.0) * 0.2
	if knocked_out:
		size = 0.8
		open = 0.15
	# Blinking now and then.
	_blink_in -= delta
	if _blink_in <= 0.0:
		if _blink_in < -0.11:
			_blink_in = randf_range(2.2, 5.0)
		else:
			open = minf(open, 0.1)
	_eye_scale = lerpf(_eye_scale, size, minf(1.0, 12.0 * delta))
	_eye_open = lerpf(_eye_open, open, minf(1.0, 18.0 * delta))
	var droop: float = (1.0 - _eye_open) * 0.025
	for eye: MeshInstance3D in [eye_l, eye_r]:
		eye.scale = Vector3(_eye_scale, _eye_scale * _eye_open, _eye_scale)
		eye.position.y = EYE_Y - BODY_HEIGHT * 0.5 - droop
	# Mouth: the voice wins when it is louder than the expression.
	_mouth_smoothed = lerpf(_mouth_smoothed, mouth_open, minf(1.0, 18.0 * delta))
	_face_mouth = lerpf(_face_mouth, face_mouth, minf(1.0, 14.0 * delta))
	var m: float = clampf(maxf(_mouth_smoothed, _face_mouth), 0.0, 1.0)
	var sulk: float = 1.0 if reaction == &"loss" and _mouth_smoothed < 0.2 else 0.0
	mouth.scale = Vector3(1.0 + m * 0.6 - sulk * 0.3, 0.15 + m * 2.2, 1.0)
	mouth.position.y = EYE_Y - 0.28 - BODY_HEIGHT * 0.5 - sulk * 0.03


func _build() -> void:
	_body_mat = ToonMaterial.make(color)
	_rig = Node3D.new()
	_rig.name = "Rig"
	add_child(_rig)
	body = MeshInstance3D.new()
	body.name = "Body"
	var cap := CapsuleMesh.new()
	cap.radius = BODY_RADIUS
	cap.height = BODY_HEIGHT
	body.mesh = cap
	body.material_override = _body_mat
	body.position.y = BODY_HEIGHT * 0.5
	_rig.add_child(body)
	var dark: StandardMaterial3D = GreyboxKit.material(Palette.CASINO_BLACK)
	eye_l = _dot(body, Vector3(-0.13, EYE_Y - BODY_HEIGHT * 0.5, -BODY_RADIUS + 0.04), 0.05, dark, "EyeL")
	eye_r = _dot(body, Vector3(0.13, EYE_Y - BODY_HEIGHT * 0.5, -BODY_RADIUS + 0.04), 0.05, dark, "EyeR")
	mouth = MeshInstance3D.new()
	mouth.name = "Mouth"
	var mm := BoxMesh.new()
	mm.size = Vector3(0.16, 0.06, 0.03)
	mouth.mesh = mm
	mouth.material_override = dark
	mouth.position = Vector3(0.0, EYE_Y - 0.28 - BODY_HEIGHT * 0.5, -BODY_RADIUS + 0.006)
	mouth.scale = Vector3(1.0, 0.15, 1.0)
	body.add_child(mouth)
	arm_l = _arm(Vector3(-BODY_RADIUS - 0.02, 0.95, 0.0), "ArmL")
	arm_r = _arm(Vector3(BODY_RADIUS + 0.02, 0.95, 0.0), "ArmR")
	hand_l = arm_l.get_node("Hand")
	hand_r = arm_r.get_node("Hand")
	# Tiny legs.
	for x: float in [-0.16, 0.16]:
		var leg := MeshInstance3D.new()
		var lm := CapsuleMesh.new()
		lm.radius = 0.09
		lm.height = 0.3
		leg.mesh = lm
		leg.material_override = dark
		leg.position = Vector3(x, 0.12, 0.0)
		_rig.add_child(leg)
		_legs.append(leg)
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.albedo_color = color
	_ring = MeshInstance3D.new()
	_ring.name = "ColorRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.36
	torus.outer_radius = 0.44
	torus.rings = 24
	torus.ring_segments = 6
	_ring.mesh = torus
	_ring.material_override = _ring_mat
	_ring.scale = Vector3(1.0, 0.15, 1.0)
	_ring.position.y = 0.02
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.visible = false
	add_child(_ring)
	hat_slot = Node3D.new()
	hat_slot.name = "HatSlot"
	hat_slot.position.y = BODY_HEIGHT * 0.5 + BODY_RADIUS - 0.05
	body.add_child(hat_slot)
	stars = KnockoutOrbit.new()
	stars.name = "Stars"
	stars.visible = false
	add_child(stars)


func _dot(parent: Node, pos: Vector3, radius: float, mat: Material, name: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	mi.mesh = sm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _arm(shoulder: Vector3, name: String) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = name
	pivot.position = shoulder
	_rig.add_child(pivot)
	var seg := MeshInstance3D.new()
	seg.name = "Segment"
	var cm := CapsuleMesh.new()
	cm.radius = 0.07
	cm.height = 0.8
	seg.mesh = cm
	seg.material_override = _body_mat
	seg.rotation.x = PI * 0.5
	seg.position = Vector3(0.0, 0.0, -0.4)
	pivot.add_child(seg)
	var hand := MeshInstance3D.new()
	hand.name = "Hand"
	var hm := SphereMesh.new()
	hm.radius = 0.14
	hm.height = 0.28
	hand.mesh = hm
	hand.material_override = GreyboxKit.material(Palette.CREAM)
	hand.position = Vector3(0.0, 0.0, -0.8)
	pivot.add_child(hand)
	pivot.rotation.x = ARM_REST  # hanging down
	return pivot


func _point_arms(target_local: Vector3) -> void:
	for pivot: Node3D in [arm_l, arm_r]:
		var to: Vector3 = target_local - pivot.position
		if to.length() < 0.01:
			continue
		pivot.look_at(global_transform * target_local, Vector3.UP)
