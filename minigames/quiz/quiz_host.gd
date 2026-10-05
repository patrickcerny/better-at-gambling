class_name QuizHost
extends Node3D
## Lucky the dealer cat, host of the Casino Quiz: a black bean of a cat with yellow eyes, a gold
## bow tie and a cue card. Poses: idle (sways), happy (bounces, eyes squeezed shut in a grin,
## paws up), surprised (jumps, wide eyes, "O" mouth, ears up) and disappointed (droops, ears
## flat, head tilted, half-shut eyes). `say` fills the speech bubble the stage shows.

enum Pose { IDLE, HAPPY, SURPRISED, DISAPPOINTED, DRUMROLL }

signal said(text: String)

var pose: Pose = Pose.IDLE
var head: Node3D
var body: MeshInstance3D
var eyes: Array[MeshInstance3D] = []
var ears: Array[MeshInstance3D] = []
var paws: Array[Node3D] = []
var mouth: MeshInstance3D
var tail: Node3D
var _t: float = 0.0
var _pose_t: float = 0.0
var _jump: float = -1.0
var _shown_text: String = ""


func _ready() -> void:
	_build()
	set_process(DisplayServer.get_name() != "headless")


## Strikes a pose with a little hop (it relaxes back to idle after `hold` seconds; 0 = keep).
func set_pose(p: Pose, hold: float = 2.2) -> void:
	pose = p
	_pose_t = hold if hold > 0.0 else INF
	if p != Pose.IDLE and p != Pose.DRUMROLL:
		_jump = 0.0


func say(text: String) -> void:
	_shown_text = text
	said.emit(text)


func line() -> String:
	return _shown_text


## World position just above the head (where the speech bubble points).
func bubble_anchor() -> Vector3:
	return to_global(Vector3(0.0, 2.55, 0.0))


func _process(delta: float) -> void:
	_t += delta
	_pose_t -= delta
	if _pose_t <= 0.0 and pose != Pose.IDLE:
		pose = Pose.IDLE
	var y: float = absf(sin(_t * 2.6)) * 0.04
	var head_tilt: Vector3 = Vector3(0.0, sin(_t * 1.3) * 0.2, sin(_t * 0.9) * 0.05)
	var eye_scale: Vector3 = Vector3.ONE
	var ear_rot: float = 0.0
	var paw_up: float = 0.15
	var mouth_scale: Vector3 = Vector3(1.0, 0.25, 1.0)
	var lean: float = 0.0
	match pose:
		Pose.HAPPY:
			y += absf(sin(_t * 9.0)) * 0.22
			eye_scale = Vector3(1.4, 0.25, 1.0)  # ^ ^ grin
			paw_up = 2.6 + sin(_t * 14.0) * 0.35
			mouth_scale = Vector3(1.8, 0.9, 1.0)
			head_tilt.z = sin(_t * 7.0) * 0.18
		Pose.SURPRISED:
			eye_scale = Vector3(1.6, 1.6, 1.0)
			ear_rot = -0.25
			paw_up = 1.6
			mouth_scale = Vector3(1.1, 1.6, 1.0)
			lean = -0.12
		Pose.DISAPPOINTED:
			y -= 0.06
			eye_scale = Vector3(1.1, 0.45, 1.0)
			ear_rot = 0.6
			paw_up = -0.1
			head_tilt = Vector3(0.35, 0.0, 0.28)
			lean = 0.18
		Pose.DRUMROLL:
			# Drumming on the lectern: paws alternate fast, leaning in.
			paw_up = 0.9
			lean = 0.12
			eye_scale = Vector3(1.2, 1.2, 1.0)
			y += absf(sin(_t * 18.0)) * 0.03
	if _jump >= 0.0:
		_jump += delta
		var k: float = _jump / 0.35
		if k >= 1.0:
			_jump = -1.0
		else:
			y += sin(k * PI) * 0.35
	var s: float = clampf(delta * 12.0, 0.0, 1.0)
	position.y = lerpf(position.y, y, s * 1.5)
	rotation.x = lerpf(rotation.x, lean, s)
	head.rotation = head.rotation.lerp(head_tilt, s)
	for e: MeshInstance3D in eyes:
		e.scale = e.scale.lerp(eye_scale, s)
	for i: int in ears.size():
		ears[i].rotation.z = lerpf(ears[i].rotation.z, ear_rot * (1.0 if i == 0 else -1.0), s)
	mouth.scale = mouth.scale.lerp(mouth_scale, s)
	for i: int in paws.size():
		var target: float = paw_up
		if pose == Pose.DRUMROLL:
			target = 0.9 + sin(_t * 26.0 + i * PI) * 0.45
		paws[i].rotation.x = lerpf(paws[i].rotation.x, -target, s)  # negative = forward/up
	tail.rotation.z = sin(_t * (6.0 if pose == Pose.HAPPY else 2.0)) * 0.4


func _build() -> void:
	name = "LuckyTheCat"
	var black: StandardMaterial3D = _mat(Palette.CASINO_BLACK.lightened(0.1))
	body = MeshInstance3D.new()
	var bm := CapsuleMesh.new()
	bm.radius = 0.45
	bm.height = 1.4
	body.mesh = bm
	body.position = Vector3(0, 0.7, 0)
	body.material_override = black
	add_child(body)
	var belly := MeshInstance3D.new()
	var blm := SphereMesh.new()
	blm.radius = 0.3
	blm.height = 0.7
	belly.mesh = blm
	belly.position = Vector3(0, 0.7, 0.24)
	belly.scale = Vector3(1.0, 1.0, 0.45)
	belly.material_override = _mat(Palette.WARM_CHARCOAL.lightened(0.15))
	add_child(belly)
	head = Node3D.new()
	head.position = Vector3(0, 1.6, 0)
	add_child(head)
	var skull := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.44
	hm.height = 0.82
	skull.mesh = hm
	skull.position = Vector3(0, 0.05, 0)
	skull.material_override = black
	head.add_child(skull)
	for sx: float in [-0.24, 0.24]:
		var ear := MeshInstance3D.new()
		var em := PrismMesh.new()
		em.size = Vector3(0.3, 0.36, 0.12)
		ear.mesh = em
		ear.position = Vector3(sx, 0.45, 0)
		ear.material_override = black
		head.add_child(ear)
		ears.append(ear)
		var eye := MeshInstance3D.new()
		var eye_m := SphereMesh.new()
		eye_m.radius = 0.085
		eye_m.height = 0.17
		eye.mesh = eye_m
		eye.position = Vector3(sx * 0.62, 0.1, 0.38)
		eye.material_override = _mat(Color("#F2D04B"), 0.0, true)
		head.add_child(eye)
		eyes.append(eye)
		# Whiskers.
		for wy: float in [-0.04, 0.03]:
			var w := MeshInstance3D.new()
			var wm := BoxMesh.new()
			wm.size = Vector3(0.32, 0.012, 0.012)
			w.mesh = wm
			w.position = Vector3(sx * 1.35, wy - 0.06, 0.32)
			w.rotation.z = signf(sx) * wy * 4.0
			w.material_override = _mat(Palette.CREAM)
			head.add_child(w)
	var nose := MeshInstance3D.new()
	var nm := SphereMesh.new()
	nm.radius = 0.04
	nm.height = 0.08
	nose.mesh = nm
	nose.position = Vector3(0, -0.02, 0.43)
	nose.material_override = _mat(Color("#C9737B"))
	head.add_child(nose)
	mouth = MeshInstance3D.new()
	var mm := BoxMesh.new()
	mm.size = Vector3(0.12, 0.06, 0.03)
	mouth.mesh = mm
	mouth.position = Vector3(0, -0.13, 0.41)
	mouth.scale = Vector3(1.0, 0.25, 1.0)
	mouth.material_override = _mat(Palette.VIP_BURGUNDY.darkened(0.3))
	head.add_child(mouth)
	# Gold bow tie: two wings pointing at a knot.
	for sx: float in [-1.0, 1.0]:
		var wing := MeshInstance3D.new()
		var wm2 := PrismMesh.new()
		wm2.size = Vector3(0.2, 0.18, 0.08)
		wing.mesh = wm2
		wing.rotation_degrees = Vector3(0, 0, 90.0 * sx)
		wing.position = Vector3(0.1 * sx, 1.3, 0.43)
		wing.material_override = _mat(Palette.WARM_GOLD, 0.8)
		add_child(wing)
	var knot := MeshInstance3D.new()
	var km := SphereMesh.new()
	km.radius = 0.05
	km.height = 0.1
	knot.mesh = km
	knot.position = Vector3(0, 1.3, 0.46)
	knot.material_override = _mat(Palette.VIP_GOLD, 0.8)
	add_child(knot)
	for sx: float in [-0.5, 0.5]:
		var pivot := Node3D.new()
		pivot.position = Vector3(sx, 1.05, 0.05)
		add_child(pivot)
		var arm := MeshInstance3D.new()
		var am := CapsuleMesh.new()
		am.radius = 0.08
		am.height = 0.6
		arm.mesh = am
		arm.position = Vector3(0, -0.26, 0)
		arm.material_override = black
		pivot.add_child(arm)
		var paw := MeshInstance3D.new()
		var pm := SphereMesh.new()
		pm.radius = 0.11
		pm.height = 0.22
		paw.mesh = pm
		paw.position = Vector3(0, -0.56, 0)
		paw.material_override = _mat(Palette.CREAM)
		pivot.add_child(paw)
		pivot.rotation.z = signf(sx) * 0.2
		paws.append(pivot)
	tail = Node3D.new()
	tail.position = Vector3(0, 0.35, -0.42)
	add_child(tail)
	var tail_m := MeshInstance3D.new()
	var tlm := CapsuleMesh.new()
	tlm.radius = 0.07
	tlm.height = 1.1
	tail_m.mesh = tlm
	tail_m.rotation_degrees = Vector3(-35, 0, 0)
	tail_m.position = Vector3(0, 0.4, -0.25)
	tail_m.material_override = black
	tail.add_child(tail_m)


func _mat(c: Color, metallic: float = 0.0, emissive: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metallic
	m.roughness = 0.45 if metallic > 0.0 else 0.75
	if emissive:
		m.emission_enabled = true
		m.emission = c
	return m
