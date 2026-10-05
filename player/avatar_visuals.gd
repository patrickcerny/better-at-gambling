class_name AvatarVisuals
extends Node3D
## The bean: capsule body in the player colour, dot eyes, a `-`/`o`/`O` mouth driven by voice,
## long floppy arms with oversized hands, or a character skin. Procedural wobble: spring lean on
## acceleration, squash/stretch on landing, idle bob. (docs/ART_DIRECTION.md)

const BODY_RADIUS: float = 0.42
const BODY_HEIGHT: float = 1.5
const EYE_Y: float = 1.12

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
var stars: Node3D
var color: Color = Palette.CREAM
## Character skin (`Cosmetics.SKINS`); &"bean" shows the procedural bean.
var skin_id: StringName = &"bean"
## The skin model while one is worn (bean parts are hidden then).
var skin_root: Node3D
## Set while the player sits at a station (skins with a sitting clip use it).
var sitting: bool = false

## 0 = closed `-`, ~0.5 = `o`, 1 = `O`.
var mouth_open: float = 0.0
## Where the arms reach (local, null = relaxed).
var reach_target: Vector3 = Vector3.ZERO
var reaching: bool = false

var _lean: Vector2 = Vector2.ZERO
var _lean_vel: Vector2 = Vector2.ZERO
var _squash: float = 1.0
var _squash_vel: float = 0.0
var _prev_velocity: Vector3 = Vector3.ZERO
var _time: float = 0.0
var _eye_scale: float = 1.0
var _eye_target: float = 1.0
var _mouth_smoothed: float = 0.0
var _body_mat: StandardMaterial3D
var _legs: Array[MeshInstance3D] = []
var _anim: AnimationPlayer
var _motion: StringName = &""
## Player-colored ring at the feet: skins hide the bean, so this keeps who-is-who readable.
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D


func _ready() -> void:
	_build()
	if skin_id != &"bean":
		var id: StringName = skin_id
		skin_id = &"bean"
		set_skin(id)


## Applies the player colour.
func set_color(c: Color) -> void:
	color = c
	if _body_mat != null:
		_body_mat.albedo_color = c
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
		add_child(model)
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
	_ring.visible = not bean


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


func update_motion(velocity: Vector3, on_floor: bool, delta: float) -> void:
	_time += delta
	var accel: Vector3 = (velocity - _prev_velocity) / maxf(delta, 0.0001)
	_prev_velocity = velocity
	# Local-space lean: forward acceleration tips the bean back, like a slightly drunk bean.
	var local_acc: Vector3 = global_transform.basis.inverse() * Vector3(accel.x, 0.0, accel.z)
	var target: Vector2 = Vector2(clampf(-local_acc.z * 0.012, -0.35, 0.35), clampf(local_acc.x * 0.012, -0.35, 0.35))
	var speed: float = Vector2(velocity.x, velocity.z).length()
	target.x += sin(_time * 9.0) * 0.03 * clampf(speed / 5.0, 0.0, 1.0)
	_lean_vel += (target - _lean) * 60.0 * delta - _lean_vel * 8.0 * delta
	_lean += _lean_vel * delta
	body.rotation = Vector3(_lean.x, 0.0, -_lean.y)
	arm_l.rotation.x = _lean.x * 0.5 + (sin(_time * 10.0) * 0.4 * clampf(speed / 5.0, 0.0, 1.0) if not reaching else 0.0)
	arm_r.rotation.x = _lean.x * 0.5 + (-sin(_time * 10.0) * 0.4 * clampf(speed / 5.0, 0.0, 1.0) if not reaching else 0.0)
	# Landing squash.
	if on_floor and _prev_velocity.y < -3.0:
		_squash_vel = -6.0
	_squash_vel += (1.0 - _squash) * 120.0 * delta - _squash_vel * 10.0 * delta
	_squash += _squash_vel * delta
	var bob: float = 1.0 + sin(_time * 2.2) * 0.012
	body.scale = Vector3(1.0 / sqrt(_squash), _squash * bob, 1.0 / sqrt(_squash))
	if skin_root != null:
		skin_root.rotation = Vector3(_lean.x * 0.6, 0.0, -_lean.y * 0.6)
		skin_root.scale = Vector3(1.0 / sqrt(_squash), _squash, 1.0 / sqrt(_squash))
		if sitting:
			_play(&"sit")
		elif speed > 4.2:
			_play(&"run")
		elif speed > 0.4:
			_play(&"walk")
		else:
			_play(&"idle")
	# Face.
	_eye_scale = lerpf(_eye_scale, _eye_target, 10.0 * delta)
	eye_l.scale = Vector3.ONE * _eye_scale
	eye_r.scale = Vector3.ONE * _eye_scale
	_mouth_smoothed = lerpf(_mouth_smoothed, mouth_open, 18.0 * delta)
	var open: float = clampf(_mouth_smoothed, 0.0, 1.0)
	mouth.scale = Vector3(1.0 + open * 0.6, 0.15 + open * 2.2, 1.0)
	if reaching:
		_point_arms(reach_target)


## Big eyes (win) or droopy (loss) for a moment.
func react(kind: StringName) -> void:
	match kind:
		&"win":
			_eye_target = 1.7
		&"loss":
			_eye_target = 0.6
		&"ko":
			_eye_target = 0.4
			stars.visible = true
		&"wake":
			stars.visible = false
	var t: Tween = create_tween()
	t.tween_interval(1.2)
	t.tween_callback(func() -> void: _eye_target = 1.0)


## Shows dizzy stars.
func set_knocked_out(ko: bool) -> void:
	stars.visible = ko
	_eye_target = 0.4 if ko else 1.0


func _process(delta: float) -> void:
	if stars.visible:
		stars.rotation.y += delta * 4.0


func _build() -> void:
	_body_mat = StandardMaterial3D.new()
	_body_mat.albedo_color = color
	_body_mat.roughness = 0.8
	body = MeshInstance3D.new()
	body.name = "Body"
	var cap := CapsuleMesh.new()
	cap.radius = BODY_RADIUS
	cap.height = BODY_HEIGHT
	body.mesh = cap
	body.material_override = _body_mat
	body.position.y = BODY_HEIGHT * 0.5
	add_child(body)
	var dark: StandardMaterial3D = GreyboxKit.material(Palette.CASINO_BLACK)
	eye_l = _dot(body, Vector3(-0.13, EYE_Y - BODY_HEIGHT * 0.5, -BODY_RADIUS + 0.04), 0.05, dark, "EyeL")
	eye_r = _dot(body, Vector3(0.13, EYE_Y - BODY_HEIGHT * 0.5, -BODY_RADIUS + 0.04), 0.05, dark, "EyeR")
	mouth = MeshInstance3D.new()
	mouth.name = "Mouth"
	var mm := BoxMesh.new()
	mm.size = Vector3(0.16, 0.06, 0.03)
	mouth.mesh = mm
	mouth.material_override = dark
	mouth.position = Vector3(0.0, EYE_Y - 0.28 - BODY_HEIGHT * 0.5, -BODY_RADIUS + 0.02)
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
		add_child(leg)
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
	stars = Node3D.new()
	stars.name = "Stars"
	stars.position.y = BODY_HEIGHT + 0.5
	stars.visible = false
	add_child(stars)
	for i: int in 3:
		var a: float = i * TAU / 3.0
		_dot(stars, Vector3(cos(a) * 0.35, 0.0, sin(a) * 0.35), 0.06, GreyboxKit.material(Palette.VIP_GOLD), "Star")


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
	add_child(pivot)
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
	pivot.rotation.x = -1.3  # hanging down
	return pivot


func _point_arms(target_local: Vector3) -> void:
	for pivot: Node3D in [arm_l, arm_r]:
		var to: Vector3 = target_local - pivot.position
		if to.length() < 0.01:
			continue
		pivot.look_at(global_transform * target_local, Vector3.UP)
