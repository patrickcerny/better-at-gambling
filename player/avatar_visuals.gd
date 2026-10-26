class_name AvatarVisuals
extends Node3D
## The bean: a chubby jelly bean in the player colour with a glossy shine, big googly eyes whose
## pupils follow the camera (or make eye contact with whoever watches), eyebrows, a mouth that
## grins, frowns, gasps `O` and talks with the voice (`-`/`o`/`O`), stubby arms with oversized
## cartoon gloves, and little feet that paddle when walking. It is the only body there is (the
## character skins were removed in 0.9.16); its colour is the player's bean colour (`PlayerState.bean_color`).
## Procedural animation (M7): spring lean on acceleration, squash on landing and stretch in the
## air, a squash and gasp when hit, idle bob, blinking, a banana slip, cheering / sulking / big-win
## reactions with matching faces, flailing while carried, a wobbly get-up after a ragdoll,
## knockout birdies, and every emote (`emote`): the wheel's wave, laugh, taunt, cry, dance and GG
## and the number keys' 67, thumbs up, thumbs down and default dance, each its own motion of the
## arms, body, feet and face.
## (docs/ART_DIRECTION.md)
##
## `update_motion` feeds movement in; everything is drawn once per frame in `_process`, so beans
## nobody moves (quiz podiums, results) still react. Headless (servers, tests) only the state is
## kept: no animation runs.

## Widest radius of the body (near the bottom).
const BODY_RADIUS: float = 0.46
## Body length from the bottom of the bean to the top of its head.
const BODY_HEIGHT: float = 1.4
## Height of the body's bottom above the feet (the feet stick out below it).
const BODY_BOTTOM: float = 0.1
## The body is a little flatter front-to-back than side-to-side, like a real jelly bean.
const BODY_DEPTH: float = 0.9
const EYE_Y: float = 1.08
const EYE_RADIUS: float = 0.13
const EYE_SPREAD: float = 0.128
const MOUTH_Y: float = 0.82
## Shoulder height on the body (local to its centre) and the arm's length to the glove.
const SHOULDER_Y: float = -0.02
const ARM_LENGTH: float = 0.36
const HAND_RADIUS: float = 0.135
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
## Shove / throw swing: wind-up, a two-handed thrust that lands at `SWING_CONTACT`, recovery.
const SWING_WINDUP: float = 0.07
const SWING_CONTACT: float = 0.12
const SWING_SECONDS: float = 0.38
## Walking faster than this cancels an emote (after the first moment).
const EMOTE_CANCEL_SPEED: float = 2.2
## The gasp face after a hit.
const HIT_FACE_SECONDS: float = 0.55
const GLOVE_COLOR: Color = Color("#FBF4E4")
const SHOE_COLOR: Color = Color("#2B2421")

var body: MeshInstance3D
## The eye whites (each holds a pupil that looks around).
var eye_l: MeshInstance3D
var eye_r: MeshInstance3D
var brow_l: MeshInstance3D
var brow_r: MeshInstance3D
var mouth: MeshInstance3D
var arm_l: Node3D
var arm_r: Node3D
## The gloves (each has a thumb child for thumbs up / down).
var hand_l: MeshInstance3D
var hand_r: MeshInstance3D
## Top of the head (guards wear their cap here).
var hat_slot: Node3D
## Knockout stars and birdies (a `KnockoutOrbit`); visible while knocked out.
var stars: Node3D
var color: Color = Palette.CREAM
## Set while the player sits at a station.
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
## Seconds into the current shove/throw swing (-1 = none).
var swing_time: float = -1.0
## World direction the eyes look (the local player's camera aim). Zero: make eye contact with the
## camera drawing us when it is in front, otherwise look ahead.
var gaze: Vector3 = Vector3.ZERO
## The emote playing now (`Emotes`, &"" = none), for how long it has played, and how long it runs
## (`Emotes.length`).
var emote_id: StringName = &""
var emote_time: float = 0.0
var emote_length: float = Emotes.SECONDS
## A pose the right arm keeps while it carries something (a waiter's tray, the megaphone at the
## mouth): (pitch, splay, glove roll) in `_set_arm` terms. Wins over walking, emotes and reactions
## so what the hand holds stays put; `Vector3.INF` = none.
var hold_arm_r: Vector3 = Vector3.INF
## Run the animation headless too (tests read the pose; servers never set it).
var animate_headless: bool = false

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
var _smile: float = 0.3
var _round: float = 0.0
var _smirk: float = 0.0
var _pupil_size: float = 1.0
var _brow: Vector2 = Vector2.ZERO  # (raise, worry tilt), smoothed
var _hit_face: float = 0.0
var _get_up_from: Quaternion = Quaternion.IDENTITY
var _get_up_t: float = -1.0
var _ragdoll: RagdollBody = null
var _body_mat: Material
var _mouth_mat: ShaderMaterial
## The feet (kept under the old name: they are what is left of the legs).
var _legs: Array[MeshInstance3D] = []
var _pupils: Array[Node3D] = []
var _thumbs: Array[MeshInstance3D] = []
## Each arm's segment and cuff (emotes stretch the arms like rubber hoses: `reach`).
var _segments: Array[MeshInstance3D] = []
var _cuffs: Array[MeshInstance3D] = []
var _cheeks: Array[MeshInstance3D] = []
var _hand_slot: Node3D
var _look: Vector2 = Vector2.ZERO
var _saccade: Vector2 = Vector2.ZERO
var _saccade_in: float = 1.0
## Whole-body offset and turn from the emote (hops, twirls), added on the rig.
var _emote_lift: Vector3 = Vector3.ZERO
var _emote_spin: float = 0.0
## Right brow above the left (emotes' cocked brow), smoothed.
var _brow_side: float = 0.0
var _tears: Array[MeshInstance3D] = []
var _headless: bool = false


func _ready() -> void:
	_headless = DisplayServer.get_name() == "headless"
	_build()


## Applies the player colour.
func set_color(c: Color) -> void:
	color = c
	if _body_mat != null:
		ToonMaterial.set_color(_body_mat, c)


## The right hand: a node at the glove for held items. Its -Z points
## out of the fist along the arm and +Y along the thumb.
func hand_node() -> Node3D:
	return _hand_slot


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
	if k in [&"slip", &"surprise", &"ko"]:
		stop_emote()
	reaction = k
	reaction_time = 0.0


## Starts a shove (or throw) swing: lean back, thrust both arms out, lunge, recover. Runs on
## real game time, so the local press shows at once while the server confirms.
func swing() -> void:
	swing_time = 0.0
	stop_emote()


func is_swinging() -> bool:
	return swing_time >= 0.0 and swing_time < SWING_SECONDS


## Took a hit pushing us along `dir` (world): the body tips that way on its lean spring, squashes
## and gasps (`O` mouth, squeezed eyes), then wobbles back.
func hit(dir: Vector3, strength: float = 1.0) -> void:
	var d: Vector3 = global_basis.inverse() * Vector3(dir.x, 0.0, dir.z)
	if d.length() > 0.01:
		d = d.normalized()
		_lean_vel += Vector2(d.z, d.x) * 9.0 * strength
	_squash_vel -= 3.6 * strength
	_hit_face = HIT_FACE_SECONDS
	stop_emote()


## Plays an emote (any in `Emotes`, wheel or number key) for `Emotes.length(id)`, starting `at`
## seconds in (a late joiner catching up). A new emote replaces the one playing. Unknown ids are
## ignored. Returns whether it started.
func emote(id: StringName, at: float = 0.0) -> bool:
	if not Emotes.has_animation(id) or carried or knocked_out or _ragdoll != null or at >= Emotes.length(id):
		return false
	emote_id = id
	emote_time = maxf(at, 0.0)
	emote_length = Emotes.length(id)
	if reaction != &"big_win":
		reaction = &""
	return true


## Keeps the right arm in `pose` (see `hold_arm_r`); `Vector3.INF` lets it hang and swing again.
func hold_right_arm(pose: Vector3) -> void:
	if pose == hold_arm_r:
		return
	hold_arm_r = pose


func is_emoting() -> bool:
	return emote_id != &""


## Ends the emote early (hit, shove, ragdoll, walking off).
func stop_emote() -> void:
	if emote_id == &"":
		return
	emote_id = &""
	emote_time = 0.0
	_emote_lift = Vector3.ZERO
	_emote_spin = 0.0


## The reaction for a round's net result.
static func reaction_for_net(net: int) -> StringName:
	if net >= BIG_WIN:
		return &"big_win"
	return &"win" if net > 0 else &"loss"


## Shows the knockout stars and birdies.
func set_knocked_out(ko: bool) -> void:
	knocked_out = ko
	if ko:
		stop_emote()
	if stars != null:
		stars.visible = ko
	if _ragdoll != null and is_instance_valid(_ragdoll):
		_ragdoll.set_dazed(ko)


## While ragdolled the bean is hidden and the ragdoll stands in for it; the knockout halo follows
## the ragdoll's head. `null` brings the bean back.
func set_ragdoll(rb: RagdollBody) -> void:
	_ragdoll = rb
	_rig.visible = rb == null
	if rb != null:
		stop_emote()
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
		stop_emote()


func _process(delta: float) -> void:
	var step: float = minf(delta, 1.0 / 30.0)
	if swing_time >= 0.0:
		swing_time += step
		if swing_time >= SWING_SECONDS:
			swing_time = -1.0
	if emote_id != &"":
		emote_time += minf(delta, 0.25)  # real time (a slow frame must not stretch the emote)
		var speed: float = Vector2(_velocity.x, _velocity.z).length()
		if emote_time >= emote_length or (emote_time > 0.3 and speed > EMOTE_CANCEL_SPEED):
			stop_emote()
	if (_headless and not animate_headless) or not is_visible_in_tree():
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
	_hit_face = maxf(_hit_face - delta, 0.0)
	var speed: float = Vector2(_velocity.x, _velocity.z).length()
	var walk: float = clampf(speed / 5.0, 0.0, 1.0)
	var em: Dictionary = _emote_pose()
	# Lean spring (like a slightly drunk bean), plus a walking waddle.
	var target: Vector2 = Vector2(clampf(-_accel_local.x * 0.012, -0.35, 0.35), clampf(_accel_local.y * 0.012, -0.35, 0.35))
	target.x += sin(_time * 9.0) * 0.03 * walk
	target.y += sin(_time * 9.0 + 1.3) * 0.06 * walk  # side-to-side waddle
	target.x -= 0.14 * walk  # leans into the walk
	if reaction == &"loss":
		target.x -= 0.28  # slumped forward
	target += em.get("lean", Vector2.ZERO) as Vector2
	_lean_vel += (target - _lean) * 60.0 * delta - _lean_vel * 8.0 * delta
	_lean += _lean_vel * delta
	var tilt: Vector2 = em.get("tilt", Vector2.ZERO) as Vector2
	body.rotation = Vector3(_lean.x + tilt.x, float(em.get("twist", 0.0)), -_lean.y - tilt.y + (sin(_time * 3.0) * 0.06 if reaction == &"loss" else 0.0))
	# Squash and stretch: stretch along the fall/jump speed, squash on landing.
	var squash_target: float = 1.0 + float(em.get("squash", 0.0))
	if not _on_floor and not carried:
		squash_target = 1.0 + clampf(absf(_velocity.y) * 0.026, 0.0, 0.28)
	if _land_kick > 0.0:
		_squash_vel -= 1.2 + _land_kick * 0.55
		_land_kick = 0.0
	_squash_vel += (squash_target - _squash) * 120.0 * delta - _squash_vel * 10.0 * delta
	_squash = clampf(_squash + _squash_vel * delta, 0.55, 1.35)
	var bob: float = 1.0 + sin(_time * 2.2) * 0.015 + absf(sin(_time * 9.0)) * 0.03 * walk
	var sq: Vector3 = Vector3(1.0 / sqrt(_squash), _squash * bob, 1.0 / sqrt(_squash))
	body.scale = sq
	body.position = Vector3(0.0, BODY_BOTTOM + BODY_HEIGHT * 0.5 * sq.y, 0.0) + (em.get("shift", Vector3.ZERO) as Vector3)
	_animate_rig()
	_animate_arms(walk, em)
	_animate_legs(walk, em)
	_animate_face(delta, em)
	if reaching and not is_swinging():
		_point_arms(reach_target)


## Where a bean arm posed (`pitch`, `splay`) points, in the rig's space (-Z forward); `side` -1
## for the left arm, +1 for the right.
static func arm_direction(pitch: float, splay: float, side: float) -> Vector3:
	var roll: float = splay if side < 0.0 else -splay
	return Basis(Vector3.BACK, roll) * Basis(Vector3.RIGHT, pitch) * Vector3.FORWARD


## The (pitch, splay) that points a bean arm along `dir` (rig space); inverse of `arm_direction`.
static func arm_pose(dir: Vector3, side: float) -> Vector2:
	var d: Vector3 = dir.normalized()
	var h: float = Vector2(d.x, d.y).length()
	var roll: float = 0.0
	var pitch: float = 0.0
	if d.y >= 0.0:
		roll = atan2(-d.x, d.y) if h > 0.0001 else 0.0
		pitch = atan2(h, -d.z)
	else:
		roll = atan2(d.x, -d.y)
		pitch = -atan2(h, -d.z)
	return Vector2(pitch, roll if side < 0.0 else -roll)


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
	if swing_time >= 0.0 and not carried:
		var lunge: float = _swing_curve(swing_time)
		pitch += 0.12 * (1.0 - lunge) * (1.0 if swing_time < SWING_WINDUP else 0.0) - 0.38 * lunge
		lift.z -= 0.22 * lunge
	if carried:
		roll = -PI * 0.5
		lift = Vector3(-(BODY_HEIGHT * 0.5 + BODY_BOTTOM - PIVOT.y), 0.0, 0.0)  # centre the lying body
	lift += _emote_lift
	spin += _emote_spin
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


## 0 → 1 → 0 over the swing: snaps out by the contact moment, eases back.
func _swing_curve(t: float) -> float:
	if t < SWING_WINDUP:
		return 0.0
	if t < SWING_CONTACT:
		return smoothstep(SWING_WINDUP, SWING_CONTACT, t)
	if t < SWING_CONTACT + 0.06:
		return 1.0
	return 1.0 - smoothstep(SWING_CONTACT + 0.06, SWING_SECONDS, t)


func _slip_curve(t: float) -> float:
	if t < 0.18:
		return smoothstep(0.0, 0.18, t)
	if t < 0.5:
		return 1.0
	return 1.0 - smoothstep(0.5, 1.05, t)


## The current emote's pose (`EmotePoses.pose`: arms, body, feet and face), eased in over ~0.2 s
## and out over its last 0.25 s; `w` is that weight. Empty when no emote plays.
func _emote_pose() -> Dictionary:
	if emote_id == &"":
		_emote_lift = Vector3.ZERO
		_emote_spin = 0.0
		return {}
	var t: float = emote_time
	var w: float = smoothstep(0.0, 0.18, t) * (1.0 - smoothstep(emote_length - 0.25, emote_length, t))
	var p: Dictionary = EmotePoses.pose(emote_id, t)
	for key: String in ["lean", "tilt", "twist", "shift", "squash", "lift", "spin"]:
		if p.has(key):
			p[key] = p[key] * w
	_emote_lift = p.get("lift", Vector3.ZERO) as Vector3
	_emote_spin = float(p.get("spin", 0.0))
	p["w"] = w
	return p


func _animate_arms(walk: float, em: Dictionary) -> void:
	var t: float = reaction_time
	var swing: float = sin(_time * 10.0) * 0.6 * walk
	var l: Vector2 = Vector2(ARM_REST + swing, -0.38 - walk * 0.15)  # (pitch, splay)
	var r: Vector2 = Vector2(ARM_REST - swing, -0.38 - walk * 0.15)
	var rolls: Vector2 = Vector2.ZERO
	var fists: float = 0.0
	var fists_l: float = 0.0
	var flat: float = 0.0
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
			fists = 1.0
		&"loss":
			l = Vector2(-1.5, 0.02)
			r = Vector2(-1.5, 0.02)
		&"slip", &"surprise":
			l = Vector2(1.2 + sin(t * 25.0) * 0.6, 0.8)
			r = Vector2(1.2 + cos(t * 23.0) * 0.6, 0.8)
	if not em.is_empty():
		var w: float = float(em["w"])
		var a: Vector4 = em.get("arms", Vector4(l.x, l.y, r.x, r.y)) as Vector4
		l = l.lerp(Vector2(a.x, a.y), w)
		r = r.lerp(Vector2(a.z, a.w), w)
		rolls = rolls.lerp(em.get("rolls", Vector2.ZERO) as Vector2, w)
		fists = lerpf(fists, float(em.get("fists", 0.0)), w)
		fists_l = float(em.get("fists_l", 0.0)) * w
		flat = float(em.get("flat", 0.0)) * w
	if swing_time >= 0.0 and not carried:
		# Wind-up pulls the hands back by the hips, the thrust shoots them straight out.
		var k: float = _swing_curve(swing_time)
		var back: float = smoothstep(0.0, SWING_WINDUP, swing_time) if swing_time < SWING_WINDUP else 0.0
		var pitch: float = lerpf(ARM_REST - 0.5 * back, 0.08, k)
		l = Vector2(pitch, lerpf(-0.12, -0.2, k))
		r = Vector2(pitch, lerpf(-0.12, -0.2, k))
		fists = k
	if hold_arm_r != Vector3.INF and not carried:
		r = Vector2(hold_arm_r.x, hold_arm_r.y)
		rolls.y = hold_arm_r.z
	if carried:
		l = Vector2(0.4 + sin(_time * 19.0) * 0.8, 0.3 + cos(_time * 13.0) * 0.4)
		r = Vector2(0.4 + cos(_time * 17.0) * 0.8, 0.3 + sin(_time * 11.0) * 0.4)
	# Shoulders ride the body (lean, squash, dance shifts).
	for i: int in 2:
		var side: float = -1.0 if i == 0 else 1.0
		var pivot: Node3D = arm_l if i == 0 else arm_r
		pivot.position = body.transform * Vector3(side * (_radius_at(0.5 + SHOULDER_Y / BODY_HEIGHT) - 0.03), SHOULDER_Y, 0.02)
	_set_arm(arm_l, l.x, l.y)
	_set_arm(arm_r, r.x, -r.y)
	hand_l.rotation.z = -rolls.x
	hand_r.rotation.z = -rolls.y
	for i: int in 2:
		var glove: MeshInstance3D = hand_l if i == 0 else hand_r
		var f: float = fists if i == 1 or emote_id == &"default_dance" or reaction != &"" or swing_time >= 0.0 else fists_l
		glove.scale = Vector3(1.0 - 0.12 * f - 0.45 * flat, 1.0 - 0.1 * f + 0.15 * flat, 0.92 - 0.1 * f + 0.25 * flat)
		var thumb: MeshInstance3D = _thumbs[i]
		thumb.scale = Vector3.ONE * (1.0 + 0.45 * f)
		thumb.position = Vector3(0.0, HAND_RADIUS * (0.72 + 0.25 * f), 0.03 - 0.04 * f)
		thumb.rotation.x = lerpf(0.55, 0.0, f)
	_stretch_arms(em)


## Emote arm extras: `reach` (Vector2, left/right arm length × 1 = normal) stretches an arm like a
## rubber hose, `point` (Vector2, 0..1) turns that glove's thumb into a finger pointing along it.
func _stretch_arms(em: Dictionary) -> void:
	var w: float = float(em.get("w", 0.0))
	var reach: Vector2 = Vector2.ONE.lerp(em.get("reach", Vector2.ONE) as Vector2, w)
	var point: Vector2 = (em.get("point", Vector2.ZERO) as Vector2) * w
	for i: int in 2:
		var k: float = reach.x if i == 0 else reach.y
		_segments[i].position.z = -ARM_LENGTH * 0.5 * k
		_segments[i].scale = Vector3(1.0, k, 1.0)
		_cuffs[i].position.z = -ARM_LENGTH * k + 0.05
		var glove: MeshInstance3D = hand_l if i == 0 else hand_r
		glove.position = Vector3(0.0, 0.0, -ARM_LENGTH * k - HAND_RADIUS * 0.55)
		var pt: float = point.x if i == 0 else point.y
		if pt > 0.0:
			var thumb: MeshInstance3D = _thumbs[i]
			thumb.position = thumb.position.lerp(Vector3(0.0, HAND_RADIUS * 0.15, -HAND_RADIUS * 0.95), pt)
			thumb.rotation.x = lerpf(thumb.rotation.x, -PI * 0.5, pt)


## `splay` rolls the arm outward from the body (positive = away from the body for the left arm).
func _set_arm(pivot: Node3D, pitch: float, splay: float) -> void:
	pivot.basis = Basis(Vector3.BACK, splay) * Basis(Vector3.RIGHT, pitch)


## Little feet paddle forward and up in turn while walking, kick while flying, step in the dance.
func _animate_legs(walk: float, em: Dictionary) -> void:
	var kick: float = 0.0
	if carried or reaction == &"slip":
		kick = 1.0
	var w: float = float(em.get("w", 0.0))
	var feet: Vector4 = em.get("feet", Vector4.ZERO) as Vector4
	var step: Vector2 = em.get("step", Vector2.ZERO) as Vector2
	for i: int in _legs.size():
		var side: float = -1.0 if i == 0 else 1.0
		var phase: float = _time * 10.0 + (0.0 if i == 0 else PI)
		var stride: float = sin(phase) * 0.21 * walk
		var lift: float = maxf(cos(phase), 0.0) * 0.13 * walk
		var foot: MeshInstance3D = _legs[i]
		var off: Vector2 = Vector2(feet.x, feet.y) if i == 0 else Vector2(feet.z, feet.w)
		var dance_lift: float = (step.x if i == 0 else step.y) * 0.07
		foot.position = Vector3(side * 0.17 + off.x * w, 0.065 + lift + dance_lift * w + absf(sin(_time * 24.0 + i * PI)) * 0.12 * kick, -0.05 - stride + off.y * w)
		foot.rotation = Vector3(-sin(phase) * 0.5 * walk + sin(_time * 24.0 + i * PI) * 0.9 * kick, side * -0.25, 0.0)


func _animate_face(delta: float, em: Dictionary) -> void:
	var t: float = reaction_time
	var w: float = float(em.get("w", 0.0))
	# Eye size and openness, mouth shape and brows per reaction.
	var size: float = 1.0
	var open: float = 1.0
	var face_mouth: float = 0.0
	var smile: float = 0.35
	var round_o: float = 0.0
	var brow: Vector2 = Vector2.ZERO
	# Idle: a cocky half-smile and one brow cocked.
	var smirk: float = 0.7 if reaction == &"" and w <= 0.0 else 0.0
	if smirk > 0.0:
		brow = Vector2(0.1, 0.0)
	match reaction:
		&"win":
			size = 1.25
			face_mouth = 0.55
			smile = 1.0
			brow = Vector2(0.8, 0.0)
		&"big_win":
			size = 1.4
			face_mouth = 1.0 if t < 1.8 else 0.6
			smile = 1.0
			brow = Vector2(1.0, 0.0)
		&"loss":
			size = 0.95
			open = 0.45
			smile = -1.0
			brow = Vector2(-0.2, 1.0)
		&"slip", &"surprise":
			size = 1.35
			face_mouth = 1.0
			smile = 0.0
			round_o = 1.0
			brow = Vector2(1.0, 0.3)
	var brow_side: float = 0.0
	if w > 0.0:
		smile = lerpf(smile, float(em.get("smile", smile)), w)
		face_mouth = lerpf(face_mouth, float(em.get("open", face_mouth)), w)
		round_o = lerpf(round_o, float(em.get("round", round_o)), w)
		brow = brow.lerp(em.get("brow", brow) as Vector2, w)
		open = lerpf(open, float(em.get("eyes", open)), w)
		size = lerpf(size, float(em.get("eye_size", size)), w)
		smirk = float(em.get("smirk", 0.0)) * w
		brow_side = float(em.get("brow_side", 0.0)) * w
	if _hit_face > 0.0:
		# Gasp: eyes pop wide with tiny pupils, round `O`, brows up.
		size = maxf(size, 1.3)
		face_mouth = maxf(face_mouth, 0.85)
		round_o = 1.0
		smile = 0.0
		brow = Vector2(1.0, 0.8)
	if carried:
		size = 1.35
		face_mouth = 0.8 + sin(_time * 14.0) * 0.2
		round_o = 1.0
		smile = 0.0
		brow = Vector2(1.0, 1.0)
	if knocked_out:
		size = 0.85
		open = 0.15
		smile = -0.3
		brow = Vector2(-0.3, 0.6)
	# Blinking now and then.
	_blink_in -= delta
	if _blink_in <= 0.0:
		if _blink_in < -0.11:
			_blink_in = randf_range(2.2, 5.0)
		else:
			open = minf(open, 0.1)
	_eye_scale = lerpf(_eye_scale, size, minf(1.0, 12.0 * delta))
	_eye_open = lerpf(_eye_open, open, minf(1.0, 18.0 * delta))
	var wink: float = float(em.get("wink", 0.0)) * w  # + the left eye, - the right
	for eye: MeshInstance3D in [eye_l, eye_r]:
		var shut: float = maxf(wink, 0.0) if eye == eye_l else maxf(-wink, 0.0)
		var lid: float = _eye_open * (1.0 - 0.9 * shut)
		eye.scale = Vector3(_eye_scale, _eye_scale * maxf(lid, 0.08), _eye_scale * 0.8)
	_animate_tears(float(em.get("tears", 0.0)) * w)
	_brow = _brow.lerp(brow, minf(1.0, 12.0 * delta))
	_brow_side = lerpf(_brow_side, brow_side, minf(1.0, 12.0 * delta))
	for i: int in 2:
		var side: float = -1.0 if i == 0 else 1.0
		var b: MeshInstance3D = brow_l if i == 0 else brow_r
		var cocked: float = _smirk * 0.045 if i == 0 else 0.0  # the smirk side's brow goes up
		var y: float = EYE_Y - _body_center_y() + EYE_RADIUS * _eye_scale * 0.95 + 0.05 + _brow.x * 0.05 - (1.0 - _eye_open) * 0.03 + cocked + side * _brow_side * 0.035
		var x: float = side * EYE_SPREAD * 1.05
		b.position = Vector3(x, y, _front_z(y, x) - 0.012)
		# Worry tilts the inner ends up (sad / scared); a negative raise frowns them down and in.
		b.rotation = Vector3(-0.25, side * 0.2, PI * 0.5 + side * (-_brow.y * 0.45 + minf(_brow.x, 0.0) * -0.6))
	var pupil: float = 1.0
	if _hit_face > 0.0 or carried or reaction in [&"slip", &"surprise"]:
		pupil = 0.62  # shock
	elif reaction in [&"win", &"big_win"]:
		pupil = 1.15
	if w > 0.0:
		pupil = lerpf(pupil, float(em.get("pupil", pupil)), w)
	_pupil_size = lerpf(_pupil_size, pupil, minf(1.0, 14.0 * delta))
	_animate_pupils(delta, em)
	# Mouth: the voice wins when it is louder than the expression.
	_mouth_smoothed = lerpf(_mouth_smoothed, mouth_open, minf(1.0, 18.0 * delta))
	_face_mouth = lerpf(_face_mouth, face_mouth, minf(1.0, 14.0 * delta))
	_smile = lerpf(_smile, smile, minf(1.0, 12.0 * delta))
	_round = lerpf(_round, round_o, minf(1.0, 16.0 * delta))
	if _hit_face > 0.0 or carried or knocked_out:
		smirk = 0.0
	_smirk = lerpf(_smirk, smirk, minf(1.0, 10.0 * delta))
	_mouth_mat.set_shader_parameter(&"smirk", _smirk)
	var m: float = clampf(maxf(_mouth_smoothed, _face_mouth), 0.0, 1.0)
	var voice_round: float = clampf((_mouth_smoothed - _face_mouth) * 2.0, 0.0, 1.0) * 0.7
	_mouth_mat.set_shader_parameter(&"open", m)
	_mouth_mat.set_shader_parameter(&"smile", _smile * (1.0 - voice_round))
	_mouth_mat.set_shader_parameter(&"round_o", maxf(_round, voice_round))
	_mouth_mat.set_shader_parameter(&"width", 0.62 + 0.3 * maxf(_smile, 0.0) * clampf(m * 1.5, 0.0, 1.0))
	var cheeks: float = clampf(maxf(_smile, 0.0) * (0.4 + m), 0.0, 1.0) if reaction in [&"win", &"big_win"] or (w > 0.0 and _smile > 0.5) else 0.0
	cheeks = maxf(cheeks, float(em.get("blush", 0.0)) * w)
	for c: MeshInstance3D in _cheeks:
		c.scale = c.scale.lerp(Vector3(0.07, 0.04, 0.03) * maxf(cheeks, 0.001), minf(1.0, 10.0 * delta))
		c.visible = c.scale.x > 0.004


## Crying: a drop runs down from under each eye, again and again (`amount` 0 hides them).
func _animate_tears(amount: float) -> void:
	for i: int in _tears.size():
		var tear: MeshInstance3D = _tears[i]
		tear.visible = amount > 0.3
		if not tear.visible:
			continue
		var side: float = -1.0 if i == 0 else 1.0
		var k: float = fposmod(_time * 1.3 + i * 0.45, 1.0)
		var x: float = side * (EYE_SPREAD + 0.03)
		var y: float = EYE_Y - _body_center_y() - EYE_RADIUS * 0.8 - k * 0.3
		tear.position = Vector3(x, y, _front_z(y, x) - 0.02)
		tear.scale = Vector3(0.028, 0.04, 0.028) * (1.0 - k * 0.4)


## Pupils look along `gaze`, at the watching camera, or around; little saccades keep them alive.
func _animate_pupils(delta: float, em: Dictionary) -> void:
	var want: Vector2 = Vector2.ZERO  # (yaw right, pitch up) in radians
	var dir: Vector3 = gaze
	if dir == Vector3.ZERO:
		var cam: Camera3D = get_viewport().get_camera_3d() if get_viewport() != null else null
		if cam != null:
			dir = cam.global_position - body.global_transform * Vector3(0.0, EYE_Y - _body_center_y(), 0.0)
	if dir.length() > 0.01:
		var d: Vector3 = (body.global_basis.orthonormalized().inverse() * dir).normalized()
		if d.z < 0.15 or gaze != Vector3.ZERO:  # in front of the face (or our own aim)
			want = Vector2(atan2(d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))
	_saccade_in -= delta
	if _saccade_in <= 0.0:
		_saccade_in = randf_range(0.8, 2.6)
		_saccade = Vector2(randf_range(-0.25, 0.25), randf_range(-0.12, 0.12))
	want += _saccade
	if not em.is_empty():
		want = want.lerp(em.get("look", want) as Vector2, float(em["w"]))
	if knocked_out:
		want = Vector2(sin(_time * 7.0), cos(_time * 7.0)) * 0.4  # spinning dizzy eyes
	want = Vector2(clampf(want.x, -0.6, 0.6), clampf(want.y, -0.5, 0.5))
	_look = _look.lerp(want, minf(1.0, 20.0 * delta))
	for i: int in _pupils.size():
		var cross: float = 0.06 * (1.0 if i == 0 else -1.0)  # a hint of cross-eyed goofiness
		_pupils[i].rotation = Vector3(_look.y, -_look.x + cross, 0.0)
		_pupils[i].scale = Vector3(_pupil_size, _pupil_size, 1.0)


## Body radius at height fraction `t` (0 = bottom, 1 = top): fuller at the bottom, rounded ends.
static func _radius_at(t: float) -> float:
	var u: float = clampf(t, 0.0, 1.0) * 2.0 - 1.0
	var roundness: float = pow(maxf(0.0, 1.0 - pow(absf(u), 2.4)), 1.0 / 2.4)
	return lerpf(BODY_RADIUS, BODY_RADIUS * 0.86, clampf(t, 0.0, 1.0)) * roundness


## The bean's slight curve: the belly bulges forward a touch, the back is a little hollow.
static func _bend_at(t: float) -> float:
	var u: float = clampf(t, 0.0, 1.0) * 2.0 - 1.0
	return -0.045 * (1.0 - u * u)


## Z of the body's front surface (local to the body centre) at height `y` and sideways `x`.
static func face_z(y: float, x: float) -> float:
	return _front_z(y, x)


static func _front_z(y: float, x: float) -> float:
	var t: float = y / BODY_HEIGHT + 0.5
	var r: float = _radius_at(t)
	return _bend_at(t) - sqrt(maxf(r * r - x * x, 0.0)) * BODY_DEPTH


static func _body_center_y() -> float:
	return BODY_BOTTOM + BODY_HEIGHT * 0.5


## The jelly-bean body mesh (shared by every bean, and by the ragdoll).
static func bean_mesh() -> ArrayMesh:
	if _bean_mesh_cache != null:
		return _bean_mesh_cache
	var rings: int = 20
	var segs: int = 28
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.add_vertex(Vector3(0.0, -BODY_HEIGHT * 0.5, _bend_at(0.0)))
	for i: int in range(1, rings):
		var t: float = (1.0 - cos(PI * float(i) / rings)) * 0.5
		var r: float = _radius_at(t)
		var y: float = (t - 0.5) * BODY_HEIGHT
		for j: int in segs:
			var a: float = TAU * float(j) / segs
			st.add_vertex(Vector3(sin(a) * r, y, _bend_at(t) + cos(a) * r * BODY_DEPTH))
	st.add_vertex(Vector3(0.0, BODY_HEIGHT * 0.5, _bend_at(1.0)))
	var top: int = 1 + (rings - 1) * segs
	for j: int in segs:
		var j2: int = (j + 1) % segs
		st.add_index(0)
		st.add_index(1 + j)
		st.add_index(1 + j2)
	for i: int in range(0, rings - 2):
		var a0: int = 1 + i * segs
		var b0: int = 1 + (i + 1) * segs
		for j: int in segs:
			var j2: int = (j + 1) % segs
			st.add_index(a0 + j)
			st.add_index(b0 + j)
			st.add_index(a0 + j2)
			st.add_index(a0 + j2)
			st.add_index(b0 + j)
			st.add_index(b0 + j2)
	var last: int = 1 + (rings - 2) * segs
	for j: int in segs:
		var j2: int = (j + 1) % segs
		st.add_index(last + j)
		st.add_index(top)
		st.add_index(last + j2)
	st.generate_normals()
	_bean_mesh_cache = st.commit()
	return _bean_mesh_cache


static var _bean_mesh_cache: ArrayMesh = null


## A small patch hugging the face for the mouth shader (UV 0..1 across it).
static func _mouth_mesh(y: float, w: float, h: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nx: int = 10
	var ny: int = 4
	for iy: int in ny + 1:
		for ix: int in nx + 1:
			var u: float = float(ix) / nx
			var v: float = float(iy) / ny
			var x: float = (u - 0.5) * w
			var yy: float = y + (0.5 - v) * h
			st.set_uv(Vector2(u, v))
			st.set_normal(Vector3.BACK)
			st.add_vertex(Vector3(x, yy, _front_z(yy, x) - 0.006))
	for iy: int in ny:
		for ix: int in nx:
			var a: int = iy * (nx + 1) + ix
			var b: int = a + nx + 1
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(b)
			st.add_index(a + 1)
			st.add_index(b + 1)
			st.add_index(b)
	return st.commit()


func _build() -> void:
	_body_mat = ToonMaterial.make(color, 0.4)
	_rig = Node3D.new()
	_rig.name = "Rig"
	add_child(_rig)
	body = MeshInstance3D.new()
	body.name = "Body"
	body.mesh = bean_mesh()
	body.material_override = _body_mat
	body.position.y = _body_center_y()
	_rig.add_child(body)
	var cy: float = _body_center_y()
	var dark: StandardMaterial3D = GreyboxKit.material(Palette.CASINO_BLACK)
	var white := StandardMaterial3D.new()
	white.albedo_color = Color("#FFFDF7")
	white.roughness = 0.35
	white.metallic_specular = 0.6
	# A glossy candy shine high on the body.
	var shine_mat := StandardMaterial3D.new()
	shine_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shine_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shine_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.45)
	var shine := _blob(body, Vector3(-0.17, 0.42, 0.0), Vector3(0.06, 0.12, 0.03), shine_mat, "Shine")
	shine.position.z = _front_z(0.42, -0.17) + 0.04
	shine.rotation = Vector3(-0.5, 0.35, 0.35)
	shine.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Big googly eyes: whites with a pupil (and a sparkle) on a pivot that turns to look around.
	var eyes: Array[MeshInstance3D] = []
	for side: float in [-1.0, 1.0]:
		var x: float = side * EYE_SPREAD
		var y: float = EYE_Y - cy
		var e: MeshInstance3D = _blob(body, Vector3(x, y, _front_z(y, x) + EYE_RADIUS * 0.45), Vector3.ONE, white, "EyeL" if side < 0.0 else "EyeR")
		(e.mesh as SphereMesh).radius = EYE_RADIUS
		(e.mesh as SphereMesh).height = EYE_RADIUS * 2.0
		eyes.append(e)
		var pivot := Node3D.new()
		pivot.name = "Look"
		e.add_child(pivot)
		var pupil: MeshInstance3D = _blob(pivot, Vector3(0.0, 0.0, -EYE_RADIUS * 0.82), Vector3(0.62, 0.62, 0.3) * EYE_RADIUS, dark, "Pupil")
		_blob(pupil, Vector3(0.3, 0.38, -0.8), Vector3.ONE * 0.28, white, "Sparkle")
		_pupils.append(pivot)
	eye_l = eyes[0]
	eye_r = eyes[1]
	var brows: Array[MeshInstance3D] = []
	for side: float in [-1.0, 1.0]:
		var b := MeshInstance3D.new()
		b.name = "BrowL" if side < 0.0 else "BrowR"
		var cm := CapsuleMesh.new()
		cm.radius = 0.022
		cm.height = 0.15
		cm.radial_segments = 8
		cm.rings = 2
		b.mesh = cm
		b.material_override = dark
		b.rotation.z = PI * 0.5
		body.add_child(b)
		brows.append(b)
	brow_l = brows[0]
	brow_r = brows[1]
	# Blush for big grins.
	var blush := StandardMaterial3D.new()
	blush.albedo_color = Color("#F08080")
	blush.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	blush.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	blush.albedo_color.a = 0.6
	for side: float in [-1.0, 1.0]:
		var x: float = side * 0.25
		var y: float = MOUTH_Y - cy + 0.08
		var c: MeshInstance3D = _blob(body, Vector3(x, y, _front_z(y, x) + 0.012), Vector3.ONE * 0.001, blush, "Cheek")
		c.visible = false
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_cheeks.append(c)
	mouth = MeshInstance3D.new()
	mouth.name = "Mouth"
	mouth.mesh = _mouth_mesh(MOUTH_Y - cy, 0.32, 0.26)
	_mouth_mat = ShaderMaterial.new()
	_mouth_mat.shader = preload("res://player/bean_mouth.gdshader")
	mouth.material_override = _mouth_mat
	mouth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mouth)
	var tear_mat := StandardMaterial3D.new()
	tear_mat.albedo_color = Color("#8FD3FF")
	tear_mat.emission_enabled = true
	tear_mat.emission = Color("#8FD3FF") * 0.4
	for side: float in [-1.0, 1.0]:
		var tear: MeshInstance3D = _blob(body, Vector3(side * EYE_SPREAD, 0.0, 0.0), Vector3.ONE * 0.03, tear_mat, "TearL" if side < 0.0 else "TearR")
		tear.visible = false
		tear.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_tears.append(tear)
	arm_l = _arm("ArmL")
	arm_r = _arm("ArmR")
	hand_l = arm_l.get_node("Hand")
	hand_r = arm_r.get_node("Hand")
	_hand_slot = Node3D.new()
	_hand_slot.name = "HandSlot"
	hand_r.add_child(_hand_slot)
	# Little feet in shoes.
	var shoe: StandardMaterial3D = GreyboxKit.material(SHOE_COLOR, 0.0, 0.6)
	for side: float in [-1.0, 1.0]:
		var foot: MeshInstance3D = _blob(_rig, Vector3(side * 0.17, 0.065, -0.05), Vector3(0.11, 0.075, 0.16), shoe, "FootL" if side < 0.0 else "FootR")
		_legs.append(foot)
	hat_slot = Node3D.new()
	hat_slot.name = "HatSlot"
	hat_slot.position.y = BODY_HEIGHT * 0.5 - 0.05
	body.add_child(hat_slot)
	stars = KnockoutOrbit.new()
	stars.name = "Stars"
	stars.visible = false
	add_child(stars)
	_animate_arms(0.0, {})


## A sphere scaled to `radii` (an ellipsoid blob).
func _blob(parent: Node, pos: Vector3, radii: Vector3, mat: Material, node_name: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 16
	sm.rings = 8
	mi.mesh = sm
	mi.material_override = mat
	mi.position = pos
	mi.scale = radii
	parent.add_child(mi)
	return mi


## Centre of a glove in its arm's space (the arm pivot sits at the shoulder).
static func hand_center() -> Vector3:
	return Vector3(0.0, 0.0, -ARM_LENGTH - HAND_RADIUS * 0.55)


## A stubby arm in the body colour ending in an oversized glove with a thumb. The pivot sits at
## the shoulder; the arm points along its -Z (`_set_arm` turns it), the thumb along +Y.
func _arm(node_name: String) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = node_name
	_rig.add_child(pivot)
	var seg := MeshInstance3D.new()
	seg.name = "Segment"
	var cm := CapsuleMesh.new()
	cm.radius = 0.075
	cm.height = ARM_LENGTH + 0.08
	cm.radial_segments = 10
	cm.rings = 3
	seg.mesh = cm
	seg.material_override = _body_mat
	seg.rotation.x = PI * 0.5
	seg.position = Vector3(0.0, 0.0, -ARM_LENGTH * 0.5)
	pivot.add_child(seg)
	_segments.append(seg)
	var glove_mat: StandardMaterial3D = GreyboxKit.material(GLOVE_COLOR, 0.0, 0.55)
	# Cuff where the glove meets the arm.
	var cuff := MeshInstance3D.new()
	cuff.name = "Cuff"
	var tm := TorusMesh.new()
	tm.inner_radius = 0.06
	tm.outer_radius = 0.105
	tm.rings = 12
	tm.ring_segments = 6
	cuff.mesh = tm
	cuff.material_override = glove_mat
	cuff.rotation.x = PI * 0.5
	cuff.position = Vector3(0.0, 0.0, -ARM_LENGTH + 0.05)
	pivot.add_child(cuff)
	_cuffs.append(cuff)
	var hand := MeshInstance3D.new()
	hand.name = "Hand"
	var hm := SphereMesh.new()
	hm.radius = HAND_RADIUS
	hm.height = HAND_RADIUS * 2.0
	hm.radial_segments = 14
	hm.rings = 7
	hand.mesh = hm
	hand.material_override = glove_mat
	hand.position = hand_center()
	pivot.add_child(hand)
	var thumb := MeshInstance3D.new()
	thumb.name = "Thumb"
	var th := CapsuleMesh.new()
	th.radius = 0.042
	th.height = 0.15
	th.radial_segments = 8
	th.rings = 2
	thumb.mesh = th
	thumb.material_override = glove_mat
	thumb.position = Vector3(0.0, HAND_RADIUS * 0.72, 0.03)
	hand.add_child(thumb)
	_thumbs.append(thumb)
	pivot.rotation.x = ARM_REST  # hanging down
	return pivot


func _point_arms(target_local: Vector3) -> void:
	for pivot: Node3D in [arm_l, arm_r]:
		var to: Vector3 = target_local - pivot.position
		if to.length() < 0.01:
			continue
		pivot.look_at(global_transform * target_local, Vector3.UP)
