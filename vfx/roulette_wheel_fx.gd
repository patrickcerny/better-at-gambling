class_name RouletteWheelFx
extends Node3D
## Spins Patrick's roulette wheel (Rolley.fbx, `RouletteStation.WHEEL_MODEL`) and its ball. Lives
## inside the wheel model, so positions are in the model's native units (4 m across). The rotor
## carries a number ring (Patrick's `roulette_table_1.png`, European order like
## `RouletteLogic.WHEEL_ORDER`). The ball circles the track while the server spins and drops into
## the winning pocket when `roulette_result` arrives.

## Model parts that turn with the rotor.
const ROTOR_PARTS: Array[String] = ["Handle", "Cloner_1", "Cloner_2", "Cloner_2_2", "Cloner_3", "Tube_3", "Cylinder_2_2"]
const RING_TEXTURE: String = "res://assets/casino/roulette_table_1.png"
const POCKETS: int = 37
## Native radii / heights: ball track, pockets, number ring.
const TRACK_R: float = 1.7
const TRACK_Y: float = 0.29
const POCKET_R: float = 0.74
const POCKET_Y: float = -0.05
const RING_R: float = 0.84
const RING_Y: float = -0.03
const BALL_R: float = 0.075
## Seconds from `roulette_result` until the ball rests in its pocket.
const DROP_TIME: float = 2.0  # spin (3.4 s) + drop = the 5.4 s wheel recording

## Rotor angle (clockwise seen from above, radians) and speed.
var rotor_angle: float = 0.0
var rotor_speed: float = 0.35
## Ball angle (clockwise, radians) and speed (negative: against the rotor).
var ball_angle: float = 0.0
var ball_speed: float = 0.0
var ball: MeshInstance3D
var ring: MeshInstance3D
## Pocket index the ball sits in (-1 while rolling / no ball).
var pocket: int = -1
## Last landed number (for the readout label).
var number: int = -1

var _rotor_nodes: Array[Node3D] = []
var _rotor_base: Array[float] = []
var _spinning: bool = false
var _spin_left: float = 0.0
var _dropping: float = -1.0
var _drop_from_rel: float = 0.0
var _drop_delta: float = 0.0
var _ball_r: float = TRACK_R
var _ball_y: float = TRACK_Y
var _readout: Label3D


func _ready() -> void:
	name = "WheelFx"
	var model: Node = get_parent()
	for n: String in ROTOR_PARTS:
		var part: Node3D = model.get_node_or_null(NodePath(n)) as Node3D
		if part != null:
			_rotor_nodes.append(part)
			_rotor_base.append(part.rotation.y)
	_build_ring()
	ball = MeshInstance3D.new()
	ball.name = "Ball"
	var s := SphereMesh.new()
	s.radius = BALL_R
	s.height = BALL_R * 2.0
	s.radial_segments = 12
	s.rings = 6
	ball.mesh = s
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.97, 0.96, 0.93)
	m.roughness = 0.25
	m.metallic_specular = 0.9
	ball.material_override = m
	ball.visible = false
	add_child(ball)


func _build_ring() -> void:
	var tex: Texture2D = load(RING_TEXTURE) as Texture2D
	if tex == null:
		return
	ring = MeshInstance3D.new()
	ring.name = "NumberRing"
	var pm := PlaneMesh.new()
	pm.size = Vector2(RING_R * 2.0, RING_R * 2.0)
	ring.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.roughness = 0.6
	ring.material_override = m
	ring.position.y = RING_Y
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	# The texture leaves a gap for the green zero.
	var zero := MeshInstance3D.new()
	zero.name = "Zero"
	var zm := BoxMesh.new()
	zm.size = Vector3(RING_R * 0.15, 0.004, RING_R * 0.2)
	zero.mesh = zm
	zero.material_override = GreyboxKit.material(Palette.FELT_GREEN.lightened(0.15))
	zero.position = Vector3(0, -0.002, -RING_R * 0.9)
	ring.add_child(zero)
	var zl := Label3D.new()
	zl.text = "0"
	zl.font = Vfx.font()
	zl.font_size = 64
	zl.pixel_size = 0.0016
	zl.modulate = Palette.CREAM
	zl.rotation = Vector3(-PI * 0.5, 0, 0)
	zl.position = Vector3(0, 0.004, -RING_R * 0.9)
	ring.add_child(zl)


## Starts a spin that the server resolves after about `seconds`.
func start_spin(seconds: float) -> void:
	_spinning = true
	_spin_left = seconds
	_dropping = -1.0
	pocket = -1
	rotor_speed = 1.6
	ball_speed = -9.0
	ball_angle = rotor_angle + randf() * TAU
	_ball_r = TRACK_R
	_ball_y = TRACK_Y
	ball.visible = true
	if _readout != null:
		_readout.visible = false


## The server's number: the ball spirals in and drops into its pocket over `DROP_TIME`.
func land(p_number: int) -> float:
	number = p_number
	var idx: int = maxi(RouletteLogic.WHEEL_ORDER.find(p_number), 0)
	if not ball.visible:  # joined mid-spin or missed the start: appear on the track
		start_spin(0.0)
	_spinning = false
	pocket = idx
	var rel: float = ball_angle - rotor_angle
	var target: float = pocket_angle(idx)
	# Keep rolling the way it was (against the rotor), at least half a lap more.
	var d: float = fposmod(rel - target, TAU)
	if d < PI:
		d += TAU
	_drop_from_rel = rel
	_drop_delta = -d
	_dropping = 0.0
	return DROP_TIME


## Clockwise angle of pocket `idx` on the rotor (0 = the zero, at the ring's -z).
static func pocket_angle(idx: int) -> float:
	return float(idx) * TAU / POCKETS


## Model-space position at clockwise angle `a`, radius `r`, height `y`.
static func ring_point(a: float, r: float, y: float) -> Vector3:
	return Vector3(sin(a) * r, y, -cos(a) * r)


## Number under the ball right now (-1 while rolling); used by tests and the readout.
func number_under_ball() -> int:
	if pocket < 0 or _dropping >= 0.0:
		return -1
	var rel: float = fposmod(ball_angle - rotor_angle, TAU)
	var idx: int = int(round(rel / (TAU / POCKETS))) % POCKETS
	return RouletteLogic.WHEEL_ORDER[idx]


func _process(delta: float) -> void:
	# Rotor: quick while spinning, coasting down afterwards.
	if _spinning:
		_spin_left -= delta
		ball_speed = lerpf(ball_speed, -2.6, minf(1.0, delta * 0.55))
	else:
		rotor_speed = maxf(rotor_speed - delta * 0.12, 0.25)
	rotor_angle = fposmod(rotor_angle + rotor_speed * delta, TAU)
	for i: int in _rotor_nodes.size():
		_rotor_nodes[i].rotation.y = _rotor_base[i] - rotor_angle
	if ring != null:
		ring.rotation.y = -rotor_angle
	if not ball.visible:
		return
	if _dropping >= 0.0:
		_dropping = minf(_dropping + delta, DROP_TIME)
		var f: float = _dropping / DROP_TIME
		var eased: float = 1.0 - pow(1.0 - f, 2.2)
		ball_angle = rotor_angle + _drop_from_rel + _drop_delta * eased
		# Spiral in over the first 60 %, a couple of bounces off the pocket frets, then settle.
		var fin: float = clampf(f / 0.6, 0.0, 1.0)
		_ball_r = lerpf(TRACK_R, POCKET_R, fin * fin)
		var hop: float = 0.0
		if f > 0.45:
			var b: float = (f - 0.45) / 0.55
			hop = absf(sin(b * PI * 3.0)) * 0.12 * (1.0 - b)
		_ball_y = lerpf(TRACK_Y, POCKET_Y, fin) + hop
		if _dropping >= DROP_TIME:
			_dropping = -1.0
			_show_readout()
	elif pocket >= 0:
		ball_angle = rotor_angle + pocket_angle(pocket)
		_ball_r = POCKET_R
		_ball_y = POCKET_Y
	else:
		ball_angle += ball_speed * delta
	ball.position = ring_point(ball_angle, _ball_r, _ball_y + BALL_R)


func _show_readout() -> void:
	if _readout == null:
		_readout = Label3D.new()
		_readout.name = "Readout"
		_readout.font = Vfx.font()
		_readout.font_size = 160
		_readout.pixel_size = 0.004
		_readout.outline_size = 28
		_readout.outline_modulate = Palette.CASINO_BLACK
		_readout.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_readout.position = Vector3(0, 1.9, 0)
		add_child(_readout)
	var col: StringName = RouletteLogic.color_of(number)
	_readout.text = "%d %s" % [number, String(col).to_upper()]
	_readout.modulate = Palette.CASINO_RED.lightened(0.15) if col == &"red" else (Palette.MONEY_GREEN if col == &"green" else Palette.CREAM)
	_readout.visible = true
	_readout.scale = Vector3.ONE * 0.3
	var t: Tween = _readout.create_tween()
	t.tween_property(_readout, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(2.6)
	t.tween_callback(func() -> void: _readout.visible = false)
