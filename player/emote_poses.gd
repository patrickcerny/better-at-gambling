class_name EmotePoses
extends RefCounted
## The emotes' choreography (`AvatarVisuals.emote`): where the bean is `t` seconds into an emote.
## Each one is acted in beats: a wind-up, the key poses reached with an overshoot and held, the
## body bouncing, squashing and tilting along, the face playing its part, and a closing pose
## (`Emotes.length` sets how long each one runs; `AvatarVisuals` eases every emote in and out).
##
## A pose is a Dictionary; every key is optional:
## - `arms` Vector4 (left pitch, left splay, right pitch, right splay; `AvatarVisuals._set_arm`),
##   `rolls` Vector2 (glove roll left/right), `fists` / `fists_l` (0..1 right/left fist), `flat`
##   (open flat hands), set together by `_hands` from where each arm points and its thumb points;
##   `reach` Vector2 (arm length × 1, stretching like a rubber hose), `point` Vector2 (0..1, the
##   thumb becomes a finger pointing along the arm).
## - body: `lean` (Vector2 on the lean spring; -x tips forward, +y tips to the right), `tilt`
##   (Vector2 added straight onto the body, same axes, for crisp nods and head tilts), `twist`
##   (yaw of the body), `shift` (body offset), `squash` (+ stretches tall), `lift` (whole character,
##   for hops: the feet leave the floor too), `spin` (yaw of the whole character, for turns).
## - feet: `feet` Vector4 (left x/z, right x/z offsets), `step` Vector2 (left/right foot lift).
## - face: `smile` (-1 frown .. 1 grin), `open` (mouth), `round` (`O` mouth), `smirk` (one corner
##   up), `eyes` (how open), `wink` (+1 shuts the left eye, -1 the right), `brow` Vector2 (raise,
##   worry), `brow_side` (+ raises the right brow, lowers the left), `look` (pupils: yaw right, pitch
##   up; leave it out to keep eye contact with whoever watches), `pupil` (size), `tears`, `blush`.
## - `skin`: upper-arm and forearm directions (left, then right) for character skins' arm bones.

## Easing curves for `curve` / `track`.
enum { LIN, IO, OUT, BACK, IN }

## 6-7: when the weighing starts, how long one "six, seven" (both hands up once) takes, how many
## of them, and when the shrug comes.
const SIX_SEVEN_START: float = 0.3
const SIX_SEVEN_CYCLE: float = 0.5
const SIX_SEVEN_CYCLES: int = 4
const SIX_SEVEN_SHRUG: float = SIX_SEVEN_START + SIX_SEVEN_CYCLE * SIX_SEVEN_CYCLES
## Disco: one beat (the arm stabs up or down on each), and when the twirl starts and ends.
const DISCO_BEAT: float = 0.5
const DISCO_SPIN: Vector2 = Vector2(2.2, 2.85)
## Default dance tempo (beats per second).
const DANCE_BPS: float = 2.35


## The pose for emote `id` at `t` seconds in (empty for an unknown id).
static func pose(id: StringName, t: float) -> Dictionary:
	match id:
		&"six_seven":
			return _six_seven(t)
		&"wave":
			return _wave(t)
		&"laugh":
			return _laugh(t)
		&"taunt":
			return _taunt(t)
		&"cry":
			return _cry(t)
		&"dance":
			return _disco(t)
		&"gg":
			return _gg(t)
		&"thumbs_up":
			return _thumbs_up(t)
		&"thumbs_down":
			return _thumbs_down(t)
		&"default_dance":
			return _default_dance(t)
	return {}


# --- Curves --------------------------------------------------------------------------------------

## 0 → 1 across [a, b], clamped.
static func span(t: float, a: float, b: float) -> float:
	return clampf((t - a) / (b - a), 0.0, 1.0)


## 0 → 1 → 0 across [a, b] (a smooth bump).
static func bump(t: float, a: float, b: float) -> float:
	return sin(span(t, a, b) * PI)


## Shapes a 0..1 progress: ease in and out, ease out, ease in, or back (overshoots ~8% and
## settles, for poses that snap into place).
static func curve(x: float, kind: int) -> float:
	match kind:
		IO:
			return x * x * (3.0 - 2.0 * x)
		OUT:
			return 1.0 - pow(1.0 - x, 3.0)
		IN:
			return x * x * x
		BACK:
			# Eases in, overshoots ~8% near the end and settles: never faster than twice the
			# average speed, so even a quick snap has in-betweens instead of popping.
			return x * x * (3.0 - 2.0 * x) + 0.5 * sin(PI * x) * x * x
	return x


## Keyframes `[[time, value, curve into it], ...]` (rising times; values float, Vector2 or
## Vector3, all the same type): holds the first before it and the last after it.
static func track(t: float, keys: Array) -> Variant:
	var first: Array = keys[0]
	if t <= float(first[0]):
		return first[1]
	for i: int in range(1, keys.size()):
		var k: Array = keys[i]
		if t < float(k[0]):
			var prev: Array = keys[i - 1]
			var x: float = curve(span(t, float(prev[0]), float(k[0])), int(k[2]) if k.size() > 2 else IO)
			return lerp(prev[1], k[1], x)
	var last: Array = keys[keys.size() - 1]
	return last[1]


## Like `track` for directions: the arm swings along an arc between keys, not a straight line.
static func arc(t: float, keys: Array) -> Vector3:
	var first: Array = keys[0]
	if t <= float(first[0]):
		return (first[1] as Vector3).normalized()
	for i: int in range(1, keys.size()):
		var k: Array = keys[i]
		if t < float(k[0]):
			var prev: Array = keys[i - 1]
			var x: float = curve(span(t, float(prev[0]), float(k[0])), int(k[2]) if k.size() > 2 else IO)
			return swing(prev[1] as Vector3, k[1] as Vector3, x)
	var last: Array = keys[keys.size() - 1]
	return (last[1] as Vector3).normalized()


## The direction `x` of the way from `a` to `b` along the arc between them (`x` > 1 overshoots).
static func swing(a: Vector3, b: Vector3, x: float) -> Vector3:
	var an: Vector3 = a.normalized()
	var bn: Vector3 = b.normalized()
	if an.dot(bn) > 0.9999:
		return bn
	var axis: Vector3 = an.cross(bn)
	if axis.length() < 0.0001:  # opposite: go round over the top
		axis = an.cross(Vector3.UP if absf(an.y) < 0.9 else Vector3.RIGHT)
	return an.rotated(axis.normalized(), an.angle_to(bn) * x)


# --- Arms ----------------------------------------------------------------------------------------

## Where an arm hangs at rest (rig space), `side` -1 left, +1 right.
static func rest(side: float) -> Vector3:
	return AvatarVisuals.arm_direction(AvatarVisuals.ARM_REST, -0.38, side)


## The glove roll that turns the thumb towards `thumb` (rig space; the part of it across the arm)
## for an arm posed (`pitch`, `splay`) as in `arms`.
static func thumb_roll(arm: Vector2, side: float, thumb: Vector3) -> float:
	var splay: float = arm.y if side < 0.0 else -arm.y
	var basis: Basis = Basis(Vector3.BACK, splay) * Basis(Vector3.RIGHT, arm.x)
	var local: Vector3 = basis.inverse() * thumb
	# A thumb asked to point along the arm has no roll to give: lean towards thumb-up as it gets
	# close, so the glove never flips round in a frame.
	var across: float = Vector2(local.x, local.y).length()
	return atan2(local.x, local.y + maxf(0.4 - across, 0.0) * 2.0)


## Points the arms along `left` / `right` (rig space, -Z forward, +X the bean's right) with the
## thumbs towards `thumb_l` / `thumb_r`.
static func _hands(p: Dictionary, left: Vector3, right: Vector3, thumb_l: Vector3, thumb_r: Vector3) -> void:
	var l: Vector2 = AvatarVisuals.arm_pose(left, -1.0)
	var r: Vector2 = AvatarVisuals.arm_pose(right, 1.0)
	p["arms"] = Vector4(l.x, l.y, r.x, r.y)
	p["rolls"] = Vector2(thumb_roll(l, -1.0, thumb_l), thumb_roll(r, 1.0, thumb_r))


## `v` turned about the arm `axis` by `angle` (a wrist flick).
static func _flick(v: Vector3, axis: Vector3, angle: float) -> Vector3:
	return v.rotated(axis.normalized(), angle)


# --- The emotes ----------------------------------------------------------------------------------

## 6-7 (the meme): the hands come up in front at chest height, palms up, and weigh "six... seven"
## up and down in turn like a pair of scales, four times, snapping to the top and bottom and
## holding there a beat. The bean bounces on every word, tilts towards the heavier hand, eyes the
## one going up and mouths the words; then a shrug: hands out to the sides, shoulders up, head
## cocked, brows up, mouth flat ("eh").
static func _six_seven(t: float) -> Dictionary:
	var p: Dictionary = {}
	var into: float = curve(span(t, 0.0, SIX_SEVEN_START), BACK)
	var u: float = maxf(t - SIX_SEVEN_START, 0.0) / SIX_SEVEN_CYCLE
	var s: float = sin(u * TAU) if t < SIX_SEVEN_SHRUG else 0.0
	var sh: float = signf(s) * pow(absf(s), 0.55)  # quick to the ends, a hold at each
	var amp: float = lerpf(0.62, 0.75, span(t, SIX_SEVEN_START, SIX_SEVEN_SHRUG)) * span(t, 0.15, SIX_SEVEN_START + 0.1)
	var shrug: float = curve(span(t, SIX_SEVEN_SHRUG, SIX_SEVEN_SHRUG + 0.22), BACK)
	var shrug_face: float = span(t, SIX_SEVEN_SHRUG, SIX_SEVEN_SHRUG + 0.15)
	var dirs: Array[Vector3] = []
	var thumbs: Array[Vector3] = []
	for side: float in [-1.0, 1.0]:
		var pitch: float = -0.05 - side * amp * sh  # left up when sh > 0
		var weigh: Vector3 = Vector3(side * 0.28, sin(pitch), -cos(pitch))
		var out: Vector3 = Vector3(side * 0.85, 0.5, -0.25)
		dirs.append(swing(swing(rest(side), weigh, into), out, shrug))
		thumbs.append(Vector3(side, 0.0, 0.0).slerp(Vector3(side * 0.2, 0.0, 1.0).normalized(), clampf(shrug, 0.0, 1.0)))
	_hands(p, dirs[0], dirs[1], thumbs[0], thumbs[1])
	p["flat"] = 1.0
	p["reach"] = Vector2.ONE * (1.1 + 0.05 * absf(sh))
	var settle: float = -0.07 * bump(t, 0.0, 0.25)  # a little dip as the hands come up
	var word: float = absf(sh)
	p["squash"] = settle + (0.05 * word - 0.03) * span(t, 0.2, 0.35) * (1.0 - shrug_face) + 0.1 * shrug * (1.0 - span(t, 2.75, 2.95))
	p["shift"] = Vector3(0.0, 0.04 * word, 0.0)
	p["tilt"] = Vector2(0.05 * shrug, 0.14 * sh + 0.2 * shrug)
	p["lean"] = Vector2(0.03, 0.08 * sh)
	p["twist"] = 0.1 * sh
	p["step"] = Vector2(maxf(sh, 0.0), maxf(-sh, 0.0)) * 0.35
	# Face: deadpan, mouthing the words, eyes on the hand going up; then "eh".
	p["smile"] = lerpf(0.25, -0.25, shrug_face)
	p["smirk"] = lerpf(0.55, 0.85, shrug_face)
	p["open"] = lerpf(0.1 + 0.3 * word * span(t, 0.25, 0.35), 0.0, shrug_face)
	p["brow"] = Vector2(lerpf(0.55, 1.0, shrug_face), lerpf(0.1, 0.6, shrug_face))
	p["brow_side"] = lerpf(0.8 * sh, 0.6, shrug_face)
	p["look"] = Vector2(-0.35 * sh, -0.12).lerp(Vector2(0.3, 0.25), shrug_face)
	p["eyes"] = lerpf(0.8, 0.85, shrug_face)
	# Skins: elbows at the sides, forearms out front doing the weighing.
	var lp: float = 0.05 - 0.55 * sh
	var rp: float = 0.05 + 0.55 * sh
	p["skin"] = [Vector3(-0.12, -0.95, 0.2), Vector3(-0.05, sin(lp), -cos(lp)), Vector3(0.12, -0.95, 0.2), Vector3(0.05, sin(rp), -cos(rp))]
	return p


## Wave: a little crouch, a hop as the right arm swings up in an arc, then big waves over the
## head with the wrist flicking behind the arm, the body swaying along, one foot kicked up behind
## and a big "hiii" grin with the brows bouncing.
static func _wave(t: float) -> Dictionary:
	var p: Dictionary = {}
	var phi: float = maxf(t - 0.42, 0.0) * TAU * 1.6
	var wav: float = sin(phi) * span(t, 0.36, 0.6)
	var centre: Vector3 = Vector3(0.45 + 0.5 * wav, 0.85, -0.25)
	var right: Vector3 = arc(t, [[0.0, rest(1.0)], [0.13, Vector3(0.4, -0.8, 0.45)], [0.4, Vector3(0.45, 0.85, -0.25), BACK]])
	right = swing(right, centre, span(t, 0.38, 0.5))
	var left: Vector3 = Vector3(-0.38, -0.9, 0.05 - 0.12 * wav)
	var thumb_r: Vector3 = _flick(Vector3.FORWARD.slerp(Vector3.LEFT, span(t, 0.25, 0.42)), right, 0.55 * cos(phi) * span(t, 0.4, 0.6))
	_hands(p, left, right, Vector3(-0.2, 0.0, -1.0), thumb_r)
	p["flat"] = 1.0
	p["reach"] = Vector2(1.0, float(track(t, [[0.13, 1.0], [0.4, 1.45, OUT], [0.6, 1.35]])))
	p["fists_l"] = 0.3
	p["squash"] = -0.1 * bump(t, 0.0, 0.26) - 0.06 * bump(t, 0.4, 0.55) + 0.06 * bump(t, 0.16, 0.4)
	p["lift"] = Vector3(0.0, 0.16 * bump(t, 0.14, 0.42), 0.0)
	p["tilt"] = Vector2(0.0, (0.1 + 0.05 * sin(phi - 0.7)) * span(t, 0.3, 0.5))
	p["twist"] = -0.15 + 0.07 * sin(phi - 0.9) * span(t, 0.4, 0.6)
	p["lean"] = Vector2(0.06, 0.04)
	p["step"] = Vector2(0.9 * span(t, 0.45, 0.6), 0.0)  # left foot kicked up behind
	p["feet"] = Vector4(0.0, 0.07 * span(t, 0.45, 0.6), 0.0, 0.0)
	p["smile"] = 1.0
	p["open"] = 0.45 + 0.2 * absf(wav)
	p["brow"] = Vector2(0.85 + 0.15 * sin(phi * 2.0), 0.0)
	p["pupil"] = 1.15
	p["blush"] = 0.6
	return p


## Laugh (pointing and laughing at you): a snort as the bean scrunches up, then the right fist jabs
## out at whoever watches and the bean rocks back cackling "ha-ha-ha", eyes squeezed shut and the
## mouth wide; then it doubles over clutching its belly with both hands, stamping a foot, tears of
## joy running; and comes up again with a happy sigh, still holding its belly.
static func _laugh(t: float) -> Dictionary:
	var p: Dictionary = {}
	var ha: float = sin(t * TAU * 6.0) * span(t, 0.16, 0.3) * (1.0 - span(t, 2.2, 2.4))
	var hah: float = absf(ha)
	var belly_l: Vector3 = Vector3(0.35, -0.5, -0.8)
	var belly_r: Vector3 = Vector3(-0.35, -0.5, -0.8)
	var point: Vector3 = Vector3(-0.05, 0.08 + 0.05 * ha, -1.0)
	var right: Vector3 = arc(t, [[0.0, rest(1.0)], [0.16, Vector3(0.35, -0.6, 0.3), OUT], [0.32, point, BACK], [1.2, point], [1.45, belly_r]])
	var left: Vector3 = arc(t, [[0.0, rest(-1.0)], [0.3, belly_l]])
	_hands(p, left, right, Vector3(0.0, 0.0, -1.0), Vector3(0.0, 1.0, 0.0))
	p["fists"] = 1.0 - 0.7 * span(t, 1.2, 1.4)
	p["fists_l"] = 0.0
	p["flat"] = 0.5 * span(t, 1.2, 1.4)
	var pointing: float = span(t, 0.16, 0.26) * (1.0 - span(t, 1.15, 1.25))
	p["point"] = Vector2(0.0, pointing)
	p["reach"] = Vector2(1.0, float(track(t, [[0.16, 1.0], [0.32, 1.4, OUT], [0.5, 1.28], [1.2, 1.28], [1.35, 1.0]])) + 0.05 * ha * pointing)
	var over: float = curve(span(t, 1.2, 1.5), BACK) * (1.0 - curve(span(t, 2.25, 2.55), IO))
	var back: float = curve(span(t, 0.18, 0.4), OUT) * (1.0 - span(t, 1.15, 1.35))
	var sigh: float = bump(t, 2.3, 2.8)
	p["lean"] = Vector2(0.3 * back - 0.5 * over + 0.12 * sigh, 0.04 * ha)
	p["tilt"] = Vector2(0.08 * back - 0.08 * over + 0.03 * ha, 0.0)
	p["squash"] = -0.09 * bump(t, 0.0, 0.2) + 0.05 * ha + 0.06 * sigh
	p["shift"] = Vector3(0.0, 0.04 * hah, 0.0)
	p["step"] = Vector2(bump(t, 1.5, 1.68) + bump(t, 1.88, 2.06), 0.0)  # stamping the floor
	p["smile"] = 1.0
	p["open"] = lerpf(0.05, 0.7 + 0.3 * hah, span(t, 0.14, 0.24)) * (1.0 - 0.6 * span(t, 2.3, 2.5))
	p["eyes"] = lerpf(1.0, 0.12, span(t, 0.1, 0.25)) + 0.35 * span(t, 2.3, 2.55)
	p["brow"] = Vector2(0.75, -0.25)
	p["pupil"] = lerpf(0.7, 1.0, span(t, 0.0, 0.2))
	p["tears"] = span(t, 1.3, 1.5) * (1.0 - span(t, 2.55, 2.7))
	p["blush"] = 1.0
	return p


## Taunt: a crouch and a pop, thumbs at the temples with the fingers waggling, head tilting side to
## side, a wink and the tongue out; a half turn to wiggle its bum at you with a slap; a turn back and
## a smug finish, arms crossed, chin up, one brow raised.
static func _taunt(t: float) -> Dictionary:
	var p: Dictionary = {}
	var spin: float = PI * curve(span(t, 1.2, 1.42), BACK) + PI * curve(span(t, 2.0, 2.22), BACK)
	var facing_back: float = span(t, 1.25, 1.35) * (1.0 - span(t, 2.0, 2.1))
	var wag: float = sin(t * TAU * 4.5)
	var tilt_lr: float = sin((t - 0.2) * TAU * 2.0)
	var temple_l: Vector3 = Vector3(-0.38, 0.92, -0.12)
	var temple_r: Vector3 = Vector3(0.38, 0.92, -0.12)
	var cross_l: Vector3 = Vector3(0.48, -0.18, -0.86)
	var cross_r: Vector3 = Vector3(-0.44, -0.04, -0.9)
	var slap: float = bump(t, 1.52, 1.66) + bump(t, 1.76, 1.9)
	var bum_r: Vector3 = Vector3(0.45, -0.6, 0.66)
	var left: Vector3 = arc(t, [[0.0, rest(-1.0)], [0.2, Vector3(-0.85, -0.2, 0.0), OUT], [0.42, temple_l, BACK], [1.18, temple_l], [1.35, rest(-1.0)], [2.15, rest(-1.0)], [2.4, cross_l, BACK]])
	var right: Vector3 = arc(t, [[0.0, rest(1.0)], [0.2, Vector3(0.85, -0.2, 0.0), OUT], [0.42, temple_r, BACK], [1.18, temple_r], [1.35, rest(1.0)], [2.15, rest(1.0)], [2.4, cross_r, BACK]])
	right = swing(right, bum_r, clampf(slap, 0.0, 1.0) * 0.8)
	var at_temples: float = span(t, 0.3, 0.42) * (1.0 - span(t, 1.15, 1.25))
	var crossed: float = span(t, 2.2, 2.35)
	var raise: float = span(t, 0.1, 0.42) * (1.0 - span(t, 1.15, 1.35))
	var thumb_l: Vector3 = _flick(Vector3.FORWARD.slerp(Vector3.RIGHT, raise), left, 0.7 * wag * at_temples).lerp(Vector3.UP, crossed)
	var thumb_r: Vector3 = _flick(Vector3.FORWARD.slerp(Vector3.LEFT, raise), right, -0.7 * wag * at_temples).lerp(Vector3.UP, crossed)
	_hands(p, left, right, thumb_l, thumb_r)
	p["reach"] = Vector2.ONE * (1.0 + 0.3 * crossed)
	p["flat"] = at_temples
	p["fists"] = crossed
	p["fists_l"] = crossed
	p["spin"] = spin
	p["lift"] = Vector3(0.0, 0.1 * bump(t, 0.18, 0.4) + 0.06 * bump(t, 1.2, 1.4) + 0.06 * bump(t, 2.0, 2.2), 0.0)
	p["squash"] = -0.09 * bump(t, 0.0, 0.22) + 0.04 * absf(wag) * at_temples
	var wiggle: float = sin(t * TAU * 4.0) * facing_back
	p["shift"] = Vector3(0.09 * wiggle, 0.0, 0.0)
	p["tilt"] = Vector2(0.1 * crossed, 0.16 * tilt_lr * at_temples + 0.12 * wiggle - 0.08 * crossed)
	p["lean"] = Vector2(0.12 * bump(t, 0.0, 0.25) - 0.1 * at_temples + 0.25 * facing_back + 0.08 * crossed, 0.0)
	p["twist"] = 0.2 * tilt_lr * at_temples + 0.3 * wiggle
	p["step"] = Vector2(maxf(tilt_lr, 0.0), maxf(-tilt_lr, 0.0)) * 0.6 * at_temples
	p["smile"] = lerpf(0.75, 0.5, crossed)
	p["open"] = 0.55 * span(t, 0.25, 0.4) * (1.0 - crossed)
	p["smirk"] = lerpf(0.3, 1.0, crossed)
	p["wink"] = at_temples
	p["brow"] = Vector2(lerpf(0.7, 0.2, crossed), -0.35)
	p["brow_side"] = lerpf(0.6, 0.9, crossed)
	p["eyes"] = lerpf(1.0, 0.5, crossed)
	if crossed > 0.0:
		p["look"] = Vector2(-0.25, 0.08)
	return p


## Cry: the lip wobbles and the eyes go big and wet, then a wail with the head thrown back and the
## arms flung up; then both fists rub the eyes in turn while the shoulders hitch with every sob, a
## foot stamps and the tears run; it ends with a big sniff and a slump, eyes on the floor.
static func _cry(t: float) -> Dictionary:
	var p: Dictionary = {}
	var hitch: float = pow(maxf(sin((t - 0.6) * TAU * 3.0), 0.0), 4.0) * span(t, 0.6, 0.7) * (1.0 - span(t, 2.25, 2.35))
	var rub: float = (t - 0.6) * TAU * 2.6
	var chin_l: Vector3 = Vector3(0.4, -0.1, -0.9)
	var chin_r: Vector3 = Vector3(-0.4, -0.1, -0.9)
	var wail_l: Vector3 = Vector3(-0.75, 0.6, -0.25)
	var wail_r: Vector3 = Vector3(0.75, 0.6, -0.25)
	var eye_l: Vector3 = Vector3(0.3 + 0.08 * cos(rub), 0.4 + 0.1 * sin(rub), -0.5)
	var eye_r: Vector3 = Vector3(-0.3 - 0.08 * cos(rub + PI), 0.4 + 0.1 * sin(rub + PI), -0.5)
	var limp_l: Vector3 = Vector3(-0.22, -0.96, -0.12)
	var limp_r: Vector3 = Vector3(0.22, -0.96, -0.12)
	var left: Vector3 = arc(t, [[0.0, rest(-1.0)], [0.35, chin_l], [0.5, wail_l, BACK], [0.62, wail_l], [0.85, eye_l, BACK], [2.25, eye_l], [2.5, limp_l, OUT]])
	var right: Vector3 = arc(t, [[0.0, rest(1.0)], [0.35, chin_r], [0.5, wail_r, BACK], [0.62, wail_r], [0.85, eye_r, BACK], [2.25, eye_r], [2.5, limp_r, OUT]])
	var rubbing: float = span(t, 0.8, 0.9) * (1.0 - span(t, 2.2, 2.3))
	left = swing(left, eye_l, rubbing)
	right = swing(right, eye_r, rubbing)
	_hands(p, left, right, Vector3(0.0, 1.0, 0.0), Vector3(0.0, 1.0, 0.0))
	p["reach"] = Vector2.ONE * (1.0 + 0.2 * rubbing + 0.2 * wail_arms(t))
	p["fists"] = 0.6 + 0.4 * rubbing
	p["fists_l"] = 0.6 + 0.4 * rubbing
	var wail: float = wail_arms(t)
	var sulk: float = span(t, 2.45, 2.7)
	p["lean"] = Vector2(0.24 * wail - (0.16 + 0.06 * hitch) * rubbing - 0.3 * sulk, 0.06 * sin(t * TAU * 0.8) * rubbing)
	p["tilt"] = Vector2(0.1 * wail - 0.06 * sulk, 0.06 * sin(t * TAU * 0.8 + 0.5) * rubbing + 0.08 * sulk)
	p["twist"] = 0.1 * sin(t * TAU * 0.8) * rubbing
	p["squash"] = -0.07 * span(t, 0.0, 0.35) * (1.0 - wail) + 0.07 * hitch - 0.04 * rubbing + 0.1 * bump(t, 2.3, 2.5) - 0.07 * sulk
	p["shift"] = Vector3(0.0, 0.045 * hitch - 0.03 * sulk, 0.0)
	p["lift"] = Vector3(0.0, 0.05 * bump(t, 0.4, 0.6), 0.0)
	p["step"] = Vector2(bump(t, 1.3, 1.45), bump(t, 1.65, 1.8))  # stamp, stamp
	var quiver: float = sin(t * TAU * 9.0) * 0.18
	p["smile"] = lerpf(-0.55 + quiver, -1.0, span(t, 0.35, 0.45)) if t < 2.45 else -0.7 + quiver * (1.0 - sulk * 0.5)
	p["open"] = 0.08 * (1.0 - span(t, 0.35, 0.45)) + (1.0 * wail + (0.5 + 0.35 * hitch) * rubbing) * (1.0 - sulk) + 0.05 * sulk
	p["eyes"] = lerpf(1.0, 0.1, span(t, 0.4, 0.5)) * (1.0 - sulk) + 0.4 * sulk
	p["pupil"] = lerpf(1.3, 1.0, span(t, 0.35, 0.5))
	p["brow"] = Vector2(lerpf(0.2, -0.1, span(t, 0.0, 0.4)), lerpf(0.4, 1.0, span(t, 0.0, 0.4)))
	if t < 0.4 or sulk > 0.0:
		p["look"] = Vector2(0.0, -0.4 * sulk)
	p["tears"] = span(t, 0.45, 0.6)
	return p


## The cry's wail: arms flung up, head back (0 → 1 → 0).
static func wail_arms(t: float) -> float:
	return bump(t, 0.38, 0.8)


## Dance (the disco, Saturday-night style): a dip, then on every beat the right fist stabs up to
## the ceiling and down across to the other hip, snapping there and holding, hips swaying towards
## it, a foot tapping out and the knees bouncing; a hop into a full twirl with the arms out; and a
## finishing pose, finger to the sky.
static func _disco(t: float) -> Dictionary:
	var p: Dictionary = {}
	var up_dir: Vector3 = Vector3(0.45, 0.88, -0.15)
	var down_dir: Vector3 = Vector3(-0.5, -0.72, -0.45)
	var hip_l: Vector3 = Vector3(-0.78, -0.58, 0.22)
	var beats_end: float = DISCO_SPIN.x
	var beat: float = maxf(t - 0.15, 0.0) / DISCO_BEAT
	var n: int = mini(int(floor(beat)), 3)  # four stabs, the last one held into the twirl
	var f: float = beat - floor(beat) if beat < 4.0 else 1.0
	var k: float = curve(span(f, 0.0, 0.4), BACK)
	var prev: Vector3 = (up_dir if n % 2 == 1 else down_dir) if n > 0 else rest(1.0)
	var target: Vector3 = up_dir if n % 2 == 0 else down_dir
	var right: Vector3 = swing(prev, target, k)
	var side: float = 1.0 if n % 2 == 0 else -1.0  # hips go towards the pointing hand
	var sway: float = lerpf(-side if n > 0 else 0.0, side, curve(span(f, 0.0, 0.35), IO))
	var hit: float = 1.0 - curve(span(f, 0.0, 0.45), OUT)  # the knees give on the beat
	var dancing: float = span(t, 0.1, 0.2) * (1.0 - span(t, beats_end - 0.05, beats_end + 0.05))
	var spin_k: float = curve(span(t, DISCO_SPIN.x, DISCO_SPIN.y), IO)
	var twirl: float = span(t, beats_end - 0.05, beats_end + 0.1) * (1.0 - span(t, DISCO_SPIN.y - 0.05, DISCO_SPIN.y + 0.08))
	var finale: float = curve(span(t, DISCO_SPIN.y - 0.02, DISCO_SPIN.y + 0.15), BACK)
	var left: Vector3 = swing(rest(-1.0), hip_l, span(t, 0.0, 0.2))
	right = swing(right, Vector3(0.95, 0.28, 0.0), twirl)
	left = swing(left, Vector3(-0.95, 0.28, 0.0), twirl)
	right = swing(right, up_dir, finale)
	left = swing(left, hip_l, finale)
	# The thumb sticks out of the plane the arm stabs in, so the glove never turns over mid-stab.
	_hands(p, left, right, Vector3(0.0, 0.0, -1.0), up_dir.cross(down_dir).normalized())
	var stab_up: float = (k if n % 2 == 0 else 1.0 - k) * dancing
	p["point"] = Vector2(0.0, maxf(stab_up, finale))
	p["reach"] = Vector2(1.0, 1.0 + 0.3 * maxf(stab_up, finale))
	p["fists"] = 1.0 - 0.6 * twirl
	p["fists_l"] = 0.3
	p["flat"] = 0.5 * twirl
	p["spin"] = TAU * spin_k
	p["lift"] = Vector3(0.0, 0.28 * bump(t, DISCO_SPIN.x + 0.05, DISCO_SPIN.y - 0.02), 0.0)
	var crouch: float = bump(t, beats_end - 0.12, DISCO_SPIN.x + 0.08) + bump(t, DISCO_SPIN.y - 0.04, DISCO_SPIN.y + 0.16)
	p["squash"] = -0.08 * bump(t, 0.0, 0.18) - 0.07 * hit * dancing - 0.09 * crouch + 0.1 * bump(t, DISCO_SPIN.x + 0.08, DISCO_SPIN.y - 0.08)
	p["shift"] = Vector3(0.07 * sway * dancing, -0.05 * hit * dancing, 0.0)
	p["tilt"] = Vector2(0.0, 0.1 * sway * dancing + 0.1 * finale)
	p["lean"] = Vector2(-0.04, 0.06 * sway * dancing)
	p["twist"] = 0.22 * sway * dancing + 0.15 * finale
	p["feet"] = Vector4(0.0, 0.0, 0.08 * maxf(sway, 0.0) * dancing, -0.03 * maxf(sway, 0.0) * dancing)
	p["step"] = Vector2(maxf(-sway, 0.0) * 0.6 * hit, maxf(sway, 0.0) * hit) * dancing
	p["smile"] = 1.0
	p["open"] = 0.35 + 0.25 * finale
	p["brow"] = Vector2(0.6 + 0.3 * finale, 0.0)
	p["wink"] = -finale
	p["look"] = Vector2(right.x * 0.4, right.y * 0.35) * dancing
	p["blush"] = 0.8
	return p


## GG: a wind-up and the right hand shoots out for a handshake, a step in, three firm pumps with
## the left hand coming in on top; then the hand goes to the belly, the other behind the back, a
## slow deep bow with the eyes shut, and a hop back up with a thumbs up and a wink.
static func _gg(t: float) -> Dictionary:
	var p: Dictionary = {}
	var pump_t: float = maxf(t - 0.45, 0.0)
	var pump: float = sin(pump_t * TAU * 3.8) * span(t, 0.42, 0.5) * (1.0 - span(t, 1.15, 1.25))
	var shake: Vector3 = Vector3(0.1, -0.12 + 0.22 * pump, -1.0)
	var belly: Vector3 = Vector3(-0.45, -0.5, -0.75)
	var thumb_up: Vector3 = Vector3(0.25, 0.55, -0.8)
	var right: Vector3 = arc(t, [[0.0, rest(1.0)], [0.22, Vector3(0.3, -0.85, 0.42), OUT], [0.42, Vector3(0.1, -0.12, -1.0), BACK], [1.2, Vector3(0.1, -0.12, -1.0)], [1.45, belly], [2.3, belly], [2.5, thumb_up, BACK]])
	if t >= 0.42 and t < 1.2:
		right = shake.normalized()
	var on_top: Vector3 = Vector3(0.42, -0.2 + 0.22 * pump, -0.88)
	var behind: Vector3 = Vector3(-0.3, -0.75, 0.6)
	var left: Vector3 = arc(t, [[0.0, rest(-1.0)], [0.55, rest(-1.0)], [0.72, on_top, BACK], [1.2, on_top], [1.45, behind], [2.3, behind], [2.55, rest(-1.0)]])
	if t >= 0.72 and t < 1.2:
		left = on_top.normalized()
	var fist: float = span(t, 2.3, 2.42)
	_hands(p, left, right, Vector3(1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0))
	p["reach"] = Vector2(1.0, float(track(t, [[0.22, 1.0], [0.42, 1.3, OUT], [0.55, 1.2], [1.2, 1.2], [1.4, 1.0]])))
	p["flat"] = 1.0 - fist
	p["fists"] = fist
	var bow: float = curve(span(t, 1.5, 1.9), IO) * (1.0 - curve(span(t, 2.15, 2.4), BACK))
	p["tilt"] = Vector2(-0.6 * bow + 0.05 * sin(pump_t * TAU * 1.9) * span(t, 0.45, 0.6) * (1.0 - span(t, 1.1, 1.2)), 0.08 * fist)
	p["lean"] = Vector2(0.1 * bump(t, 0.0, 0.3) - 0.08 * span(t, 0.3, 0.45) * (1.0 - span(t, 1.2, 1.4)), 0.0)
	p["shift"] = Vector3(0.0, 0.025 * pump - 0.03 * bow, 0.0)
	p["squash"] = -0.08 * bump(t, 2.3, 2.45) + 0.07 * bump(t, 2.4, 2.6)
	p["lift"] = Vector3(0.0, 0.14 * bump(t, 2.38, 2.65), 0.0)
	p["feet"] = Vector4(0.0, 0.0, 0.0, -0.08 * span(t, 0.3, 0.42) * (1.0 - span(t, 1.25, 1.4)))
	p["step"] = Vector2(0.0, bump(t, 0.28, 0.45))
	p["smile"] = lerpf(0.9, 0.7, bow) + 0.1 * fist
	p["open"] = lerpf(0.35, 0.0, bow) + 0.25 * fist
	p["eyes"] = lerpf(1.0, 0.1, bow)
	p["brow"] = Vector2(lerpf(0.6, 0.2, bow), 0.0)
	p["wink"] = -fist
	if bow > 0.0:
		p["look"] = Vector2(0.0, -0.3 * bow)
	return p


## Thumbs up: the fist pulls in, then punches out thumb up with a pop and a wink; a confident nod;
## the other hand joins in with a hop, and both pump while the brows waggle.
static func _thumbs_up(t: float) -> Dictionary:
	var p: Dictionary = {}
	var out_r: Vector3 = Vector3(0.18, 0.15, -0.97)
	var out_l: Vector3 = Vector3(-0.18, 0.15, -0.97)
	var pump: float = sin(maxf(t - 0.95, 0.0) * TAU * 2.2) * span(t, 0.92, 1.05)
	var right: Vector3 = arc(t, [[0.0, rest(1.0)], [0.18, Vector3(-0.15, -0.5, -0.85), OUT], [0.33, out_r, BACK]])
	var left: Vector3 = arc(t, [[0.0, rest(-1.0)], [0.74, rest(-1.0)], [0.92, out_l, BACK]])
	right = right + Vector3(0.0, 0.1 * pump, 0.0)
	left = left + Vector3(0.0, -0.1 * pump * span(t, 0.92, 1.0), 0.0)
	_hands(p, left, right, Vector3.UP, Vector3.UP)
	p["fists"] = 1.0
	p["fists_l"] = 1.0
	p["reach"] = Vector2(float(track(t, [[0.74, 1.0], [0.92, 1.3, OUT], [1.05, 1.15]])), float(track(t, [[0.18, 0.9], [0.33, 1.35, OUT], [0.48, 1.15]])))
	var punch: float = bump(t, 0.2, 0.42)
	p["lean"] = Vector2(0.1 * bump(t, 0.0, 0.25) - 0.08 * span(t, 0.2, 0.35), 0.0)
	p["tilt"] = Vector2(0.07 * sin(maxf(t - 0.35, 0.0) * TAU * 2.0) * span(t, 0.35, 0.45) * (1.0 - span(t, 0.7, 0.8)), 0.06 * pump)
	p["squash"] = -0.07 * bump(t, 0.0, 0.22) + 0.08 * punch + 0.04 * absf(pump)
	p["lift"] = Vector3(0.0, 0.09 * bump(t, 0.76, 0.98), 0.0)
	p["twist"] = 0.05 * pump
	p["smile"] = 1.0
	p["open"] = 0.15 + 0.35 * span(t, 0.2, 0.32)
	p["eyes"] = lerpf(0.55, 1.0, span(t, 0.2, 0.3))
	p["wink"] = bump(t, 0.25, 0.7)
	p["brow"] = Vector2(0.5 + 0.35 * sin(t * TAU * 3.0) * span(t, 1.0, 1.1), 0.0)
	p["brow_side"] = -0.4 * bump(t, 0.2, 0.75)
	p["blush"] = 0.5
	return p


## Thumbs down: the thumb goes up first with a hopeful face, then turns slowly over as the smile
## sinks into a frown; three "boo" pumps downwards, the other hand joining, the head shaking.
static func _thumbs_down(t: float) -> Dictionary:
	var p: Dictionary = {}
	var out_r: Vector3 = Vector3(0.18, 0.05, -0.98)
	var out_l: Vector3 = Vector3(-0.18, 0.05, -0.98)
	var boo: float = 0.0
	for at: float in [0.75, 1.15, 1.55]:
		boo += bump(t, at - 0.08, at + 0.2) * (1.0 if t < at else 1.0 - 0.3 * span(t, at, at + 0.2))
	var right: Vector3 = arc(t, [[0.0, rest(1.0)], [0.25, out_r, BACK], [0.6, out_r], [0.7, Vector3(0.2, -0.15, -0.97)]])
	right = right + Vector3(0.0, -0.3 * boo, 0.0)
	var left: Vector3 = arc(t, [[0.0, rest(-1.0)], [0.85, rest(-1.0)], [1.02, Vector3(-0.2, -0.15, -0.97), BACK]])
	left = left + Vector3(0.0, -0.3 * boo * span(t, 1.0, 1.1), 0.0)
	var turn: float = curve(span(t, 0.28, 0.58), IO)
	var thumb_r: Vector3 = swing(Vector3.UP, Vector3.RIGHT, minf(turn * 2.0, 1.0))
	thumb_r = swing(thumb_r, Vector3.DOWN, maxf(turn * 2.0 - 1.0, 0.0)) if turn > 0.5 else thumb_r
	_hands(p, left, right, Vector3(-0.05, -1.0, 0.0), thumb_r)
	p["reach"] = Vector2(1.0 + 0.15 * boo * span(t, 1.0, 1.1), 1.1 + 0.15 * boo)
	p["fists"] = 1.0
	p["fists_l"] = 1.0
	var shake: float = sin(maxf(t - 0.6, 0.0) * TAU * 1.4) * span(t, 0.6, 0.8)
	p["lean"] = Vector2(-0.1 * span(t, 0.5, 0.8) - 0.06 * boo, 0.0)
	p["tilt"] = Vector2(-0.04 * boo, 0.05 * shake)
	p["twist"] = 0.22 * shake
	p["squash"] = -0.05 * span(t, 0.5, 0.8) - 0.04 * boo
	p["smile"] = lerpf(0.6, -1.0, turn)
	p["open"] = 0.2 * (1.0 - turn) + 0.45 * clampf(boo, 0.0, 1.0)
	p["round"] = 0.9 * clampf(boo, 0.0, 1.0)
	p["eyes"] = lerpf(1.0, 0.7, turn)
	p["brow"] = Vector2(lerpf(0.7, -0.6, turn), lerpf(0.2, 0.3, turn))
	p["look"] = Vector2(0.0, -0.15 * turn)
	return p


## The Fortnite default dance, two bars of four beats, hitting a pose on every beat and swinging
## through to the next: (1) the right fist punches down across to the left hip with the left elbow
## up, (2) the same mirrored, (3) both arms swing up over the head to the right, (4) and to the left;
## the hips sway towards the punch, the knees give on every beat, a foot kicks out on the arm swings
## and there is a little hop at the end of each bar.
static func _default_dance(t: float) -> Dictionary:
	var p: Dictionary = {}
	var beat: float = t * DANCE_BPS
	var n: int = int(floor(beat))
	var b: int = n % 4
	var f: float = beat - floor(beat)
	var hit: float = curve(span(f, 0.0, 0.4), BACK)  # swings into the beat's pose and holds it
	var poses: Array[Array] = [
		[Vector3(-0.8, 0.45, -0.3), Vector3(-0.55, -0.75, -0.45)],  # right punches across
		[Vector3(0.55, -0.75, -0.45), Vector3(0.8, 0.45, -0.3)],  # left punches across
		[Vector3(0.3, 0.92, -0.25), Vector3(0.75, 0.62, -0.25)],  # both up, to the right
		[Vector3(-0.75, 0.62, -0.25), Vector3(-0.3, 0.92, -0.25)],  # both up, to the left
	]
	var from: Array = poses[(b + 3) % 4] if n > 0 else [rest(-1.0), rest(1.0)]
	var to: Array = poses[b]
	var left: Vector3 = swing(from[0] as Vector3, to[0] as Vector3, hit)
	var right: Vector3 = swing(from[1] as Vector3, to[1] as Vector3, hit)
	_hands(p, left, right, Vector3(0.0, 0.0, -1.0), Vector3(0.0, 0.0, -1.0))
	p["fists"] = 1.0
	p["fists_l"] = 1.0
	p["reach"] = Vector2.ONE * (1.0 + 0.15 * (hit if b >= 2 else 0.0))
	var side: float = 1.0 if b == 0 or b == 2 else -1.0  # where the hips go: towards the move
	var prev_side: float = -side if n > 0 else 0.0
	var sway: float = lerpf(prev_side, side, curve(span(f, 0.0, 0.45), IO))
	var give: float = 1.0 - curve(span(f, 0.0, 0.55), OUT)  # the knees give on the beat
	p["lean"] = Vector2(-0.05, 0.12 * sway)
	p["tilt"] = Vector2(0.0, 0.07 * sway)
	p["twist"] = -0.3 * sway if b < 2 else 0.15 * sway
	p["shift"] = Vector3(0.08 * sway, -0.06 * give, 0.0)
	p["squash"] = -0.08 * give
	var kick: float = bump(f, 0.05, 0.75) if b >= 2 else 0.0
	p["feet"] = Vector4(-0.05 * kick if side < 0.0 else 0.0, -0.1 * kick if side < 0.0 else 0.0, 0.05 * kick if side > 0.0 else 0.0, -0.1 * kick if side > 0.0 else 0.0)
	p["step"] = Vector2(maxf(-sway, 0.0) * 0.5 + (kick if side < 0.0 else 0.0), maxf(sway, 0.0) * 0.5 + (kick if side > 0.0 else 0.0))
	p["lift"] = Vector3(0.0, 0.1 * bump(f, 0.1, 0.9) if b == 3 else 0.0, 0.0)
	p["smile"] = 0.9
	p["open"] = 0.3
	p["brow"] = Vector2(0.5, 0.0)
	p["smirk"] = 0.3
	p["look"] = Vector2(0.15 * sway, 0.1 if b >= 2 else -0.05)
	return p
