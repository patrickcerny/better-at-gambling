class_name BeanPuppet
extends Node
## Drives a standing bean (`AvatarVisuals`) on a show set (quiz podiums, results podium), where no
## physics body moves it: an idle sway, a floppy "ragdoll" cheer with flailing arms, a slumped sad
## pose, and one-shot hops. Add it as a child of the bean; `base` is where the bean stands.

enum Mood { IDLE, CHEER, SAD }

var mood: Mood = Mood.IDLE
## Local position the bean stands on (hops and slumps are offsets from it).
var base: Vector3 = Vector3.ZERO
## How high the cheer bounces (metres).
var cheer_height: float = 0.4
var _bean: AvatarVisuals
var _t: float = 0.0
var _hop_t: float = -1.0
var _hop_h: float = 0.0
var _face_t: float = 0.0
var _seed: float = 0.0
## Smoothed body tilt and arm pose (x = raise, y = splay) so moods blend instead of snapping.
var _tilt: Vector3 = Vector3.ZERO
var _arm: Vector2 = Vector2(-1.15, 0.08)
## Falling in from above (height offset and vertical speed), with a squashy bounce on landing.
var _drop: float = 0.0
var _drop_v: float = 0.0
var _land_squash: float = 0.0


## Puppets `bean` from now on.
static func attach(bean: AvatarVisuals) -> BeanPuppet:
	var p := BeanPuppet.new()
	p.name = "Puppet"
	p.base = bean.position
	p._seed = randf() * TAU
	bean.add_child(p)
	return p


func _ready() -> void:
	_bean = get_parent() as AvatarVisuals
	set_process(_bean != null and DisplayServer.get_name() != "headless")


func set_mood(m: Mood) -> void:
	if m == mood:
		return
	mood = m
	_face_t = 0.0


## Drops the bean in from `height` metres above its spot (it bounces once and squashes).
func drop_in(height: float = 4.0) -> void:
	_drop = height
	_drop_v = 0.0
	if _bean != null:
		_bean.position = base + Vector3(0, height, 0)


## A quick hop (`height` metres).
func hop(height: float = 0.35) -> void:
	_hop_t = 0.0
	_hop_h = height


func _process(delta: float) -> void:
	_t += delta
	_bean.update_motion(Vector3.ZERO, true, delta)  # face and breathing
	var y: float = 0.0
	var tilt: Vector3 = Vector3.ZERO
	var arm_x: float = -1.15 + sin(_t * 1.7 + _seed) * 0.06
	var arm_z: float = 0.08
	var squash: float = 1.0
	match mood:
		Mood.CHEER:
			# Floppy ragdoll joy: bouncing, wobbling, arms windmilling over the head.
			var bounce: float = absf(sin(_t * 6.5 + _seed))
			y = bounce * cheer_height
			squash = 1.0 + (bounce - 0.5) * 0.12
			tilt = Vector3(sin(_t * 3.1 + _seed) * 0.12, sin(_t * 2.3) * 0.25, sin(_t * 4.4 + _seed) * 0.22)
			arm_x = 1.7 + sin(_t * 13.0 + _seed) * 0.7
			arm_z = 0.45 + sin(_t * 9.0) * 0.25
			_face_t -= delta
			if _face_t <= 0.0:
				_bean.react(&"win")
				_face_t = 1.1
		Mood.SAD:
			# Slumped forward, arms dangling, a slow sigh.
			y = -0.06
			tilt = Vector3(-0.32 + sin(_t * 0.9) * 0.04, 0.0, sin(_t * 0.7 + _seed) * 0.08)
			arm_x = -1.45 + sin(_t * 1.1 + _seed) * 0.05
			arm_z = -0.05
			squash = 0.94
			_face_t -= delta
			if _face_t <= 0.0:
				_bean.react(&"loss")
				_face_t = 1.1
		_:
			tilt = Vector3(0.0, 0.0, sin(_t * 1.3 + _seed) * 0.04)
	if _hop_t >= 0.0:
		_hop_t += delta
		var k: float = _hop_t / 0.38
		if k >= 1.0:
			_hop_t = -1.0
		else:
			y += sin(k * PI) * _hop_h
			squash *= 1.0 + sin(k * PI) * 0.08
	if _drop > 0.0 or _drop_v != 0.0:
		_drop_v -= 26.0 * delta
		_drop += _drop_v * delta
		if _drop <= 0.0:
			_drop = 0.0
			if _drop_v < -4.0:
				_land_squash = clampf(-_drop_v * 0.03, 0.0, 0.35)
				_drop_v = -_drop_v * 0.3
			else:
				_drop_v = 0.0
	y += _drop
	if _land_squash > 0.0:
		squash *= 1.0 - _land_squash
		_land_squash = maxf(_land_squash - delta * 1.6, 0.0)
	var k_s: float = clampf(delta * (14.0 if mood == Mood.CHEER else 6.0), 0.0, 1.0)
	_tilt = _tilt.lerp(tilt, k_s)
	_arm = _arm.lerp(Vector2(arm_x, arm_z), k_s)
	_bean.position = base + Vector3(0, y, 0)
	if _bean.body != null:
		_bean.body.rotation = _tilt
		_bean.body.scale = Vector3(1.0 / sqrt(squash), squash, 1.0 / sqrt(squash))
	if _bean.skin_root != null:
		_bean.skin_root.rotation = _tilt * 0.7
	if _bean.arm_l != null and _bean.arm_r != null:
		var flap: float = sin(_t * 11.0) * 0.5 if mood == Mood.CHEER else 0.0
		_bean.arm_l.basis = Basis(Vector3.BACK, _arm.y) * Basis(Vector3.RIGHT, _arm.x)
		_bean.arm_r.basis = Basis(Vector3.BACK, -_arm.y) * Basis(Vector3.RIGHT, _arm.x + flap)
