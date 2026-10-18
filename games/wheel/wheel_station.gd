class_name WheelStation
extends StationBase
## The Wheel of Fortune: a Big Six money wheel standing upright on a velvet-fronted cabinet behind
## a dark-wood betting table. The wheel carries the 54 segments of `WheelLogic.LAYOUT` (cream $1,
## green $2, red $5, charcoal $10, burgundy $20, the black Joker and the gold Logo) between brass
## pegs, inside a frame ring of warm marquee bulbs, with a leather clicker at the top that the pegs
## flick as they pass. The layout on the felt has a box per symbol with its odds; five stools face
## it from the south (+z). The dealer stands beside the wheel (`DealerLogic.OFFSETS`).
##
## The wheel never runs on physics: on `wheel_spin_started` it spins up to `SPIN_SPEED`, and on
## `wheel_result` it slows onto the server's segment along a smooth curve that keeps its speed
## and stops exactly at the end of `WheelLogic.LAND_TIME`, when the server pays. Presentation only
## (client-side); a headless server builds the solid parts and nothing else.

## Betting table: width (x), depth (z), height of its top and of the felt.
const TABLE_W: float = 3.2
const TABLE_D: float = 1.3
const TABLE_TOP: float = 0.9
const FELT_Y: float = 0.94
## The symbol boxes on the felt, left to right in `WheelLogic.SYMBOLS` order, and their size.
const SPOT_X0: float = -1.2
const SPOT_STEP: float = 0.4
const SPOT_Z: float = -0.08
const SPOT_SIZE: Vector2 = Vector2(0.36, 0.56)
## The players' edge of the felt (chips come from here) and where lost chips go (the dealer's rack).
const LEDGE_Z: float = 0.5
const HOUSE_SPOT: Vector3 = Vector3(1.3, FELT_Y, -0.45)
const SEAT_XS: Array[float] = [-1.4, -0.7, 0.0, 0.7, 1.4]
const SEAT_Z: float = 1.3
## The cabinet the wheel stands on (centre z, size) and the wheel itself (centre, radius).
const CAB_Z: float = -1.6
const CAB_SIZE: Vector3 = Vector3(2.5, 1.0, 0.6)
const WHEEL_Y: float = 2.2
const WHEEL_Z: float = -1.45
const WHEEL_R: float = 1.05
## Radii on the wheel face: hub, segment ring, pegs.
const HUB_R: float = 0.3
const SEG_R0: float = 0.34
const SEG_R1: float = 0.99
const PEG_R: float = 0.975
## One segment's angle.
const STEP: float = TAU / WheelLogic.SEGMENTS
## Full spin speed (radians per second, clockwise as the players see it) and how fast it gets there.
const SPIN_SPEED: float = 4.4
const SPIN_UP: float = 0.6
## How far the clicker flips on a peg, and how fast it falls back.
const FLAP_KICK: float = 0.42
const FLAP_RETURN: float = 16.0
## The angle wraps back by this much (64 whole turns) once it gets this far.
const WRAP: float = TAU * 64.0
## The seat view: the eye high over the players' rail and right of the middle, looking at `SEAT_AIM`
## so the wheel, the layout in front of it and the dealer beside it fill the left two thirds of the
## screen (the overlay is a column down the right third). Each seat's eye moves `SEAT_EYE_SHIFT` of
## its stool's x along, so the stools see the wheel from slightly different spots.
const SEAT_EYE: Vector3 = Vector3(0.8, 2.8, 1.3)
const SEAT_AIM: Vector3 = Vector3(0.99, 1.48, -1.39)
const SEAT_EYE_SHIFT: float = 0.08
## Segment colours and the colour of the writing on them, by symbol.
const SYMBOL_COLORS: Array[Color] = [Color("#F2E6C9"), Color("#275E49"), Color("#C83D3D"), Color("#24211F"), Color("#681F2C"), Color("#151414"), Color("#D6A84B")]
const TEXT_COLORS: Array[Color] = [Color("#151414"), Color("#F2E6C9"), Color("#F2E6C9"), Color("#D6A84B"), Color("#E3B95C"), Color("#E3B95C"), Color("#151414")]
## What a symbol says on the wheel and the layout ("LL": the Lucky Lounge's monogram is its logo).
const FACE_TEXT: Array[String] = ["$1", "$2", "$5", "$10", "$20", "JOKER", "LL"]

enum Mode { REST, SPIN, LAND, COAST }

## The wheel's angle (radians, clockwise as seen from the stools; 0 = segment 0 under the pointer)
## and its speed.
var angle: float = 0.0
var speed: float = 0.0
var mode: Mode = Mode.REST
## The segment the wheel came to rest on last (−1 = none yet).
var landed_segment: int = -1
## The clicker's deflection (radians, + = flicked the way the wheel turns).
var flap: float = 0.0
## Pegs that passed the clicker since the wheel was built (one click each).
var clicks: int = 0
## Client-side presentation (null / empty on a headless server).
var wheel: Node3D
var pointer: Node3D
var face_labels: Array[Label3D] = []
var board_label: Label3D
var spot_labels: Array[Label3D] = []

var _land_seg: int = -1
var _land_t: float = 0.0
var _land_time: float = 0.0
var _land_from: float = 0.0
var _land_d: float = 0.0
var _land_v0: float = 0.0
var _last_peg: int = 0
var _last_click_ms: int = -1000
var _history: Array = []


func _build_visuals() -> void:
	game_id = &"wheel"
	seat_count = SEAT_XS.size()
	interact_radius = 3.0
	hot_center = Vector3(0, 0, -0.2)
	_rug(Vector2(5.6, 5.6), Palette.VIP_BURGUNDY.darkened(0.45))
	var wood := Color("#3A2A1E")
	GreyboxKit.box(self, Vector3(TABLE_W, TABLE_TOP - 0.04, TABLE_D), Vector3(0, (TABLE_TOP - 0.04) * 0.5, 0), wood, "Body")
	GreyboxKit.box(self, Vector3(TABLE_W, 0.04, TABLE_D), Vector3(0, TABLE_TOP - 0.02, 0), Color("#1E1917"), "Top", false)
	GreyboxKit.box(self, CAB_SIZE, Vector3(0, CAB_SIZE.y * 0.5, CAB_Z), Color("#2A1E16"), "WheelCabinet")
	for i: int in SEAT_XS.size():
		var spot := Vector3(SEAT_XS[i], 0, SEAT_Z)
		_stool(spot, "Stool%d" % i)
		_add_seat(spot + Vector3(0, 0.5, 0), 0.0)
		_add_seat_camera(SEAT_EYE + Vector3(SEAT_XS[i] * SEAT_EYE_SHIFT, 0, 0), SEAT_AIM)
	camera_anchor = Node3D.new()
	camera_anchor.name = "CameraAnchor"
	camera_anchor.position = SEAT_EYE  # the middle seat view: the wheel and the layout, left of the overlay
	camera_anchor.rotation = look_rotation(SEAT_EYE, SEAT_AIM)
	add_child(camera_anchor)
	if Vfx.enabled():
		_build_table_dressing()
		_build_layout()
		_build_cabinet()
		_build_wheel()
		_build_pointer()
		_build_sign()
		var lamp: OmniLight3D = GreyboxKit.lamp(self, Vector3(0, 3.6, 0.9), 0.7, 5.0)
		lamp.name = "WheelLamp"
		var ticker := _Ticker.new()
		ticker.name = "WheelTicker"
		ticker.station = self
		add_child(ticker)
		_apply_angle()


## Local spot on the felt where chips on `symbol` go (the middle of its box).
static func bet_spot(symbol: int) -> Vector3:
	return Vector3(SPOT_X0 + clampi(symbol, 0, WheelLogic.SYMBOLS.size() - 1) * SPOT_STEP, FELT_Y, SPOT_Z)


## The segment under the pointer when the wheel stands at `at` (radians, clockwise).
static func pointer_segment(at: float) -> int:
	return posmod(roundi(-at / STEP), WheelLogic.SEGMENTS)


## The angle at which `segment` rests under the pointer, `nudge` segments off its middle.
static func rest_angle(segment: int, nudge: float = 0.0) -> float:
	return (-segment + nudge) * STEP


# --- Server state and events (client) -----------------------------------------------------------

## Newest public state: a client that missed the events (joined late) catches up to the spin.
func show_state(pub: Dictionary) -> void:
	var st: int = int(pub.get("state", WheelLogic.State.IDLE))
	var seg: int = int(pub.get("segment", -1))
	if st == WheelLogic.State.SPINNING:
		if bool(pub.get("landing", false)) and seg >= 0:
			if not (mode == Mode.LAND and _land_seg == seg):
				land(seg, maxf(float(pub.get("timer", 0.0)), 0.0))
		elif mode == Mode.REST or mode == Mode.COAST:
			start_spin()
	elif st == WheelLogic.State.RESULT and seg >= 0 and mode != Mode.LAND and landed_segment != seg:
		snap_to(seg)
	var h: Array = pub.get("history", [])
	if h != _history:
		_history = h.duplicate()
		_update_board()


## The dealer spins: the wheel picks up to full speed.
func start_spin() -> void:
	mode = Mode.SPIN
	landed_segment = -1
	_land_seg = -1
	if is_inside_tree():
		Audio.play_at(&"whoosh", self, -10.0, 0.8)


## The server's result: slow onto `segment` and stop on it in `seconds`. Returns the seconds until
## the pointer rests on it (the payout waits for that, so the money never spoils the spin).
func land(segment: int, seconds: float) -> float:
	if mode == Mode.LAND and _land_seg == segment:
		return maxf(_land_time - _land_t, 0.0)  # already slowing onto it (the state came first)
	_land_seg = segment
	var target: float = rest_angle(segment, randf_range(-0.3, 0.3))
	if seconds <= 0.05:
		snap_to(segment)
		angle = target
		_apply_angle()
		return 0.0
	var v0: float = speed if speed > 0.5 else SPIN_SPEED
	var reach: float = v0 * seconds
	# Travel about half of what the current speed would cover (a steady slow-down), corrected by
	# under half a turn either way so it ends on the target.
	var d: float = reach * 0.5 + wrapf(target - (angle + reach * 0.5), -PI, PI)
	var r: float = d / reach
	if r < 1.0 / 3.0 or r > 2.0 / 3.0:
		# Too short a slow-down for this speed (a late joiner): pick the speed that fits.
		while d < 2.0 * TAU:
			d += TAU
		v0 = 2.0 * d / seconds
	_land_from = angle
	_land_d = d
	_land_v0 = v0
	_land_t = 0.0
	_land_time = seconds
	mode = Mode.LAND
	return seconds


## Puts the wheel at rest on `segment` at once.
func snap_to(segment: int) -> void:
	angle = rest_angle(segment)
	speed = 0.0
	mode = Mode.REST
	landed_segment = segment
	_land_seg = -1
	_last_peg = _peg_index(angle)
	_apply_angle()


## The spin was called off (a minigame refunded the bets): the wheel coasts to a stop.
func reset_table() -> void:
	if mode == Mode.SPIN or mode == Mode.LAND:
		mode = Mode.COAST
	_land_seg = -1


## Where the slow-down has the wheel `t` seconds in (angle, speed): a cubic that starts at the spin's
## speed, covers `_land_d` and ends at rest.
func _land_curve(t: float) -> Vector2:
	var u: float = clampf(t / _land_time, 0.0, 1.0)
	var vt: float = _land_v0 * _land_time
	var a: float = 3.0 * _land_d - 2.0 * vt
	var b: float = vt - 2.0 * _land_d
	var s: float = vt * u + a * u * u + b * u * u * u
	var v: float = (vt + 2.0 * a * u + 3.0 * b * u * u) / _land_time
	return Vector2(_land_from + s, maxf(v, 0.0))


func _tick(delta: float) -> void:
	match mode:
		Mode.SPIN:
			speed = minf(speed + SPIN_SPEED / SPIN_UP * delta, SPIN_SPEED)
			angle += speed * delta
		Mode.LAND:
			_land_t += delta
			var p: Vector2 = _land_curve(_land_t)
			angle = p.x
			speed = p.y
			if _land_t >= _land_time:
				angle = _land_from + _land_d
				speed = 0.0
				mode = Mode.REST
				landed_segment = _land_seg
				if is_inside_tree():
					Audio.play_at(&"reel_stop", self, -10.0, 0.9)
		Mode.COAST:
			speed = maxf(speed - 2.5 * delta, 0.0)
			angle += speed * delta
			if speed <= 0.0:
				mode = Mode.REST
	# The clicker: every peg that passed flicks it (one tick each, the sound thinned out at speed).
	var peg: int = _peg_index(angle)
	if peg != _last_peg:
		clicks += absi(peg - _last_peg)
		_last_peg = peg
		flap = FLAP_KICK
		var now: int = Time.get_ticks_msec()
		if pointer != null and pointer.is_inside_tree() and now - _last_click_ms >= 45:
			_last_click_ms = now
			Audio.play_at(&"plink", pointer, -15.0, randf_range(1.75, 1.95))
	else:
		flap = lerpf(flap, 0.0, 1.0 - exp(-FLAP_RETURN * delta))
	if mode != Mode.LAND and absf(angle) > WRAP:
		# Keeps the float precise over a long match: 64 whole turns look the same.
		var turns: float = floorf(angle / WRAP)
		angle -= turns * WRAP
		_last_peg -= roundi(turns) * WheelLogic.SEGMENTS * 64
	_apply_angle()


## Pegs sit on the segment boundaries; this counts boundaries passed at `at`.
static func _peg_index(at: float) -> int:
	return floori(at / STEP + 0.5)


func _apply_angle() -> void:
	if wheel != null:
		wheel.rotation.z = -angle
	if pointer != null:
		pointer.rotation.z = flap


func _update_board() -> void:
	if board_label == null:
		return
	var parts: PackedStringArray = []
	for s: Variant in _history.slice(0, 6):
		parts.append(WheelLogic.LABELS[clampi(int(s), 0, WheelLogic.LABELS.size() - 1)])
	board_label.text = "LAST  " + "  ·  ".join(parts) if not parts.is_empty() else "PLACE YOUR BETS"


# --- Building (client only) -----------------------------------------------------------------------

func _build_table_dressing() -> void:
	var velvet: StandardMaterial3D = GreyboxKit.material(Palette.VIP_BURGUNDY, 0.0, 0.95)
	var brass: StandardMaterial3D = GreyboxKit.material(Palette.WARM_GOLD, 0.8, 0.35)
	for side: float in [-1.0, 1.0]:
		_mesh_box(Vector3(TABLE_W - 0.3, 0.5, 0.02), Vector3(0, 0.45, side * (TABLE_D * 0.5 + 0.01)), velvet)
		_mesh_box(Vector3(TABLE_W, 0.06, 0.03), Vector3(0, 0.08, side * (TABLE_D * 0.5 + 0.015)), brass)
		_mesh_box(Vector3(TABLE_W + 0.04, 0.03, 0.04), Vector3(0, TABLE_TOP - 0.005, side * (TABLE_D * 0.5 + 0.01)), brass)
		_mesh_box(Vector3(0.04, 0.03, TABLE_D + 0.04), Vector3(side * (TABLE_W * 0.5 + 0.01), TABLE_TOP - 0.005, 0), brass)
	# Padded leather arm rest along the players' edge.
	var rail := MeshInstance3D.new()
	rail.name = "ArmRest"
	var cap := CapsuleMesh.new()
	cap.radius = 0.06
	cap.height = TABLE_W
	cap.radial_segments = 10
	cap.rings = 2
	rail.mesh = cap
	rail.material_override = GreyboxKit.material(Color("#2B1712"), 0.0, 0.55)
	rail.rotation.z = PI * 0.5
	rail.position = Vector3(0, TABLE_TOP + 0.04, TABLE_D * 0.5 - 0.02)
	add_child(rail)
	# The dealer's chip rack at the back corner.
	_mesh_box(Vector3(0.5, 0.05, 0.22), HOUSE_SPOT + Vector3(0, -0.015, 0), GreyboxKit.material(Color("#1E1917"), 0.0, 0.6))
	for i: int in 5:
		var stack := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.03
		cyl.bottom_radius = 0.03
		cyl.height = 0.06 + 0.012 * (i % 3)
		cyl.radial_segments = 10
		stack.mesh = cyl
		stack.material_override = GreyboxKit.material([Palette.CASINO_RED, Palette.CREAM, Palette.FELT_GREEN, Palette.CASINO_BLACK, Palette.WARM_GOLD][i], 0.0, 0.5)
		stack.position = HOUSE_SPOT + Vector3(-0.18 + i * 0.09, cyl.height * 0.5, 0)
		add_child(stack)


## The felt and its seven symbol boxes, each with its symbol and the odds it pays, in the wheel's
## colours.
func _build_layout() -> void:
	_mesh_box(Vector3(TABLE_W - 0.14, 0.02, TABLE_D - 0.18), Vector3(0, FELT_Y - 0.03, -0.04), GreyboxKit.material(Palette.FELT_GREEN, 0.0, 0.95))
	var gold: StandardMaterial3D = GreyboxKit.material(Palette.WARM_GOLD, 0.8, 0.35)
	for i: int in WheelLogic.SYMBOLS.size():
		var c: Vector3 = bet_spot(i) - Vector3(0, 0.018, 0)
		_mesh_box(Vector3(SPOT_SIZE.x + 0.02, 0.004, SPOT_SIZE.y + 0.02), c, gold)
		_mesh_box(Vector3(SPOT_SIZE.x - 0.01, 0.006, SPOT_SIZE.y - 0.01), c + Vector3(0, 0.002, 0), GreyboxKit.material(SYMBOL_COLORS[i], 0.0, 0.85))
		var l: Label3D = _flat_label(FACE_TEXT[i], 72 if i < 5 else 52, TEXT_COLORS[i])
		l.position = c + Vector3(0, 0.007, -0.07)
		var odds: Label3D = _flat_label(WheelLogic.odds_text(i), 40, TEXT_COLORS[i])
		odds.position = c + Vector3(0, 0.007, 0.15)
		spot_labels.append(l)
	var title: Label3D = _flat_label("WHEEL OF FORTUNE  ·  THE TABLE PAYS THE ODDS SHOWN", 30, Palette.WARM_GOLD)
	title.position = Vector3(0, FELT_Y - 0.008, 0.33)


func _flat_label(text: String, size: int, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = Vfx.font()
	l.font_size = size
	l.pixel_size = 0.0016
	l.modulate = color
	l.outline_size = 0
	l.rotation.x = -PI * 0.5
	add_child(l)
	return l


func _build_cabinet() -> void:
	var velvet: StandardMaterial3D = GreyboxKit.material(Palette.VIP_BURGUNDY, 0.0, 0.95)
	var brass: StandardMaterial3D = GreyboxKit.material(Palette.WARM_GOLD, 0.8, 0.35)
	var front_z: float = CAB_Z + CAB_SIZE.z * 0.5 + 0.011
	_mesh_box(Vector3(CAB_SIZE.x - 0.24, CAB_SIZE.y - 0.3, 0.02), Vector3(0, CAB_SIZE.y * 0.5 + 0.02, front_z), velvet)
	for y: float in [0.06, CAB_SIZE.y - 0.02]:
		_mesh_box(Vector3(CAB_SIZE.x + 0.04, 0.05, CAB_SIZE.z + 0.04), Vector3(0, y, CAB_Z), brass)
	# The upright behind the wheel, up to the sign, and a brass collar where the axle meets it.
	_mesh_box(Vector3(0.22, WHEEL_Y + WHEEL_R + 0.75 - CAB_SIZE.y, 0.16), Vector3(0, (CAB_SIZE.y + WHEEL_Y + WHEEL_R + 0.75) * 0.5, WHEEL_Z - 0.17), GreyboxKit.material(Color("#2A1E16"), 0.0, 0.7))
	var collar := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.09
	cyl.bottom_radius = 0.09
	cyl.height = 0.18
	collar.mesh = cyl
	collar.material_override = brass
	collar.rotation.x = PI * 0.5
	collar.position = Vector3(0, WHEEL_Y, WHEEL_Z - 0.09)
	add_child(collar)
	# The frame ring round the wheel: dark wood with a ring of warm bulbs (they do not turn).
	var frame := MeshInstance3D.new()
	frame.name = "FrameRing"
	var torus := TorusMesh.new()
	torus.inner_radius = WHEEL_R + 0.02
	torus.outer_radius = WHEEL_R + 0.16
	torus.rings = 48
	torus.ring_segments = 8
	frame.mesh = torus
	frame.material_override = GreyboxKit.material(Color("#2A1E16"), 0.0, 0.6)
	frame.rotation.x = PI * 0.5
	frame.position = Vector3(0, WHEEL_Y, WHEEL_Z - 0.03)
	add_child(frame)
	var bulb_mat := StandardMaterial3D.new()
	bulb_mat.albedo_color = Color(1.0, 0.82, 0.52)
	bulb_mat.emission_enabled = true
	bulb_mat.emission = Color(1.0, 0.82, 0.52)
	bulb_mat.emission_energy_multiplier = 2.4
	bulb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var bulb := SphereMesh.new()
	bulb.radius = 0.028
	bulb.height = 0.056
	bulb.radial_segments = 6
	bulb.rings = 3
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = bulb
	mm.instance_count = 24
	for i: int in mm.instance_count:
		var a: float = (i + 0.5) * TAU / mm.instance_count
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(sin(a), cos(a), 0) * (WHEEL_R + 0.09) + Vector3(0, WHEEL_Y, WHEEL_Z + 0.05)))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Bulbs"
	mmi.multimesh = mm
	mmi.material_override = bulb_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


## The wheel: a dark back disc, the coloured segment ring with the symbols written along each
## segment, brass dividers and pegs, a brass rim and a gold hub. Everything turns with `wheel`.
func _build_wheel() -> void:
	wheel = Node3D.new()
	wheel.name = "Wheel"
	wheel.position = Vector3(0, WHEEL_Y, WHEEL_Z)
	add_child(wheel)
	var back := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = WHEEL_R
	disc.bottom_radius = WHEEL_R
	disc.height = 0.05
	disc.radial_segments = 54
	disc.rings = 1
	back.mesh = disc
	back.material_override = GreyboxKit.material(Palette.VIP_BURGUNDY.darkened(0.3), 0.0, 0.7)
	back.rotation.x = PI * 0.5
	back.position.z = -0.02
	wheel.add_child(back)
	# Segments: one fan of quads per segment, vertex-coloured by symbol.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var subs: int = 3
	for i: int in WheelLogic.SEGMENTS:
		var col: Color = SYMBOL_COLORS[WheelLogic.LAYOUT[i]]
		for k: int in subs:
			var a0: float = (i - 0.5 + float(k) / subs) * STEP
			var a1: float = (i - 0.5 + float(k + 1) / subs) * STEP
			var p0 := Vector3(sin(a0) * SEG_R0, cos(a0) * SEG_R0, 0.01)
			var p1 := Vector3(sin(a0) * SEG_R1, cos(a0) * SEG_R1, 0.01)
			var p2 := Vector3(sin(a1) * SEG_R1, cos(a1) * SEG_R1, 0.01)
			var p3 := Vector3(sin(a1) * SEG_R0, cos(a1) * SEG_R0, 0.01)
			for v: Vector3 in [p0, p1, p2, p0, p2, p3]:  # clockwise from the front
				st.set_color(col)
				st.set_normal(Vector3.BACK)
				st.add_vertex(v)
	var seg_mat := StandardMaterial3D.new()
	seg_mat.vertex_color_use_as_albedo = true
	seg_mat.vertex_color_is_srgb = true  # the palette colours as written
	seg_mat.roughness = 0.75
	var segs := MeshInstance3D.new()
	segs.name = "Segments"
	segs.mesh = st.commit()
	segs.material_override = seg_mat
	wheel.add_child(segs)
	# The writing: each segment's symbol along its radius, reading outwards.
	for i: int in WheelLogic.SEGMENTS:
		var sym: int = WheelLogic.LAYOUT[i]
		var a: float = i * STEP
		var l := Label3D.new()
		l.text = FACE_TEXT[sym]
		l.font = Vfx.font()
		l.font_size = 46 if sym < 5 else 34
		l.pixel_size = 0.0016
		l.modulate = TEXT_COLORS[sym]
		l.outline_size = 0
		l.position = Vector3(sin(a), cos(a), 0) * (SEG_R0 + SEG_R1) * 0.52 + Vector3(0, 0, 0.016)
		l.rotation.z = PI * 0.5 - a
		wheel.add_child(l)
		face_labels.append(l)
	var brass: StandardMaterial3D = GreyboxKit.material(Palette.WARM_GOLD, 0.85, 0.3)
	# Dividers on the boundaries and a peg at the rim end of each.
	var div := BoxMesh.new()
	div.size = Vector3(0.007, SEG_R1 - SEG_R0, 0.006)
	var peg := CylinderMesh.new()
	peg.top_radius = 0.013
	peg.bottom_radius = 0.013
	peg.height = 0.09
	peg.radial_segments = 6
	peg.rings = 1
	var dm := MultiMesh.new()
	dm.transform_format = MultiMesh.TRANSFORM_3D
	dm.mesh = div
	dm.instance_count = WheelLogic.SEGMENTS
	var pm := MultiMesh.new()
	pm.transform_format = MultiMesh.TRANSFORM_3D
	pm.mesh = peg
	pm.instance_count = WheelLogic.SEGMENTS
	for i: int in WheelLogic.SEGMENTS:
		var a: float = (i + 0.5) * STEP
		var radial := Vector3(sin(a), cos(a), 0)
		dm.set_instance_transform(i, Transform3D(Basis(Vector3.BACK, -a), radial * (SEG_R0 + SEG_R1) * 0.5 + Vector3(0, 0, 0.013)))
		pm.set_instance_transform(i, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), radial * PEG_R + Vector3(0, 0, 0.05)))
	for pair: Array in [["Dividers", dm], ["Pegs", pm]]:
		var mi := MultiMeshInstance3D.new()
		mi.name = String(pair[0])
		mi.multimesh = pair[1]
		mi.material_override = brass
		wheel.add_child(mi)
	var rim := MeshInstance3D.new()
	rim.name = "Rim"
	var torus := TorusMesh.new()
	torus.inner_radius = SEG_R1
	torus.outer_radius = WHEEL_R
	torus.rings = 54
	torus.ring_segments = 6
	rim.mesh = torus
	rim.material_override = brass
	rim.rotation.x = PI * 0.5
	rim.position.z = 0.01
	wheel.add_child(rim)
	var inner := MeshInstance3D.new()
	var it := TorusMesh.new()
	it.inner_radius = SEG_R0 - 0.03
	it.outer_radius = SEG_R0 + 0.005
	it.rings = 36
	it.ring_segments = 6
	inner.mesh = it
	inner.material_override = brass
	inner.rotation.x = PI * 0.5
	inner.position.z = 0.01
	wheel.add_child(inner)
	var hub := MeshInstance3D.new()
	hub.name = "Hub"
	var hc := CylinderMesh.new()
	hc.top_radius = HUB_R
	hc.bottom_radius = HUB_R
	hc.height = 0.05
	hc.radial_segments = 24
	hub.mesh = hc
	hub.material_override = GreyboxKit.material(Palette.CASINO_BLACK, 0.0, 0.5)
	hub.rotation.x = PI * 0.5
	hub.position.z = 0.02
	wheel.add_child(hub)
	var boss := MeshInstance3D.new()
	var bc := CylinderMesh.new()
	bc.top_radius = 0.07
	bc.bottom_radius = 0.09
	bc.height = 0.08
	bc.radial_segments = 12
	boss.mesh = bc
	boss.material_override = brass
	boss.rotation.x = PI * 0.5
	boss.position.z = 0.06
	wheel.add_child(boss)
	for k: int in 2:
		var logo := Label3D.new()
		logo.text = ["LUCKY", "LOUNGE"][k]
		logo.font = Vfx.font()
		logo.font_size = 44
		logo.pixel_size = 0.0016
		logo.modulate = Palette.VIP_GOLD
		logo.outline_size = 0
		logo.position = Vector3(0, 0.17 if k == 0 else -0.17, 0.047)
		wheel.add_child(logo)
	# The back, seen from the casino floor: a burgundy cover behind the upright with the name in gold.
	var cover := MeshInstance3D.new()
	cover.name = "BackCover"
	var cc := CylinderMesh.new()
	cc.top_radius = 0.85
	cc.bottom_radius = 0.85
	cc.height = 0.03
	cc.radial_segments = 32
	cover.mesh = cc
	cover.material_override = GreyboxKit.material(Palette.VIP_BURGUNDY, 0.0, 0.8)
	cover.rotation.x = PI * 0.5
	cover.position = Vector3(0, WHEEL_Y, WHEEL_Z - 0.27)
	add_child(cover)
	var back_name := Label3D.new()
	back_name.text = "WHEEL OF\nFORTUNE"
	back_name.font = Vfx.font()
	back_name.font_size = 96
	back_name.pixel_size = 0.0028
	back_name.modulate = Palette.VIP_GOLD
	back_name.outline_size = 0
	back_name.double_sided = false
	back_name.rotation.y = PI
	back_name.position = Vector3(0, WHEEL_Y, WHEEL_Z - 0.29)
	add_child(back_name)


## The clicker: a brass bracket over the top of the wheel with a red leather tongue hanging into
## the pegs, hinged at its top (`pointer` turns about z when a peg flicks it).
func _build_pointer() -> void:
	var brass: StandardMaterial3D = GreyboxKit.material(Palette.WARM_GOLD, 0.85, 0.3)
	var top: float = WHEEL_Y + WHEEL_R + 0.13
	_mesh_box(Vector3(0.1, 0.06, 0.32), Vector3(0, top + 0.03, WHEEL_Z - 0.02), brass)  # arm from the upright
	_mesh_box(Vector3(0.05, 0.12, 0.05), Vector3(0, top - 0.01, WHEEL_Z + 0.11), brass)
	pointer = Node3D.new()
	pointer.name = "Pointer"
	pointer.position = Vector3(0, top - 0.05, WHEEL_Z + 0.07)
	add_child(pointer)
	# A tapering tongue: wide at the hinge, a point at the bottom between the pegs.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var length: float = top - 0.05 - (WHEEL_Y + PEG_R - 0.06)
	var w: float = 0.05
	var d: float = 0.02
	var pts: Array[Vector3] = [Vector3(-w, 0, -d), Vector3(w, 0, -d), Vector3(0, -length, -d), Vector3(-w, 0, d), Vector3(w, 0, d), Vector3(0, -length, d)]
	for tri: Array in [[3, 5, 4], [0, 1, 2], [0, 2, 5], [0, 5, 3], [1, 4, 5], [1, 5, 2], [0, 3, 4], [0, 4, 1]]:
		for k: int in tri:
			st.add_vertex(pts[k])
	st.generate_normals()
	var tongue := MeshInstance3D.new()
	tongue.name = "Tongue"
	tongue.mesh = st.commit()
	tongue.material_override = GreyboxKit.material(Palette.CASINO_RED, 0.0, 0.5)
	pointer.add_child(tongue)
	var pin := MeshInstance3D.new()
	var pc := CylinderMesh.new()
	pc.top_radius = 0.025
	pc.bottom_radius = 0.025
	pc.height = 0.08
	pin.mesh = pc
	pin.material_override = brass
	pin.rotation.x = PI * 0.5
	pointer.add_child(pin)


## The marquee over the wheel: name, the last results, warm bulbs along the top.
func _build_sign() -> void:
	var y: float = WHEEL_Y + WHEEL_R + 0.62
	var z: float = WHEEL_Z - 0.03  # in front of the upright, which ends behind it
	var w: float = 2.6
	var h: float = 0.62
	_mesh_box(Vector3(w, h, 0.1), Vector3(0, y, z), GreyboxKit.material(Palette.CASINO_BLACK.lightened(0.06), 0.0, 0.6))
	var gold: StandardMaterial3D = GreyboxKit.material(Palette.WARM_GOLD, 0.85, 0.3)
	for dy: float in [-1.0, 1.0]:
		_mesh_box(Vector3(w + 0.1, 0.05, 0.13), Vector3(0, y + dy * (h * 0.5 + 0.02), z), gold)
	for dx: float in [-1.0, 1.0]:
		_mesh_box(Vector3(0.05, h + 0.09, 0.13), Vector3(dx * (w * 0.5 + 0.02), y, z), gold)
	for face: int in 2:
		var title := Label3D.new()
		title.text = "WHEEL OF FORTUNE"
		title.font = Vfx.font()
		title.font_size = 80
		title.pixel_size = 0.0034
		title.modulate = Palette.VIP_GOLD
		title.outline_size = 0
		title.double_sided = false
		title.rotation.y = 0.0 if face == 0 else PI
		title.position = Vector3(0, y + 0.1, z + (0.055 if face == 0 else -0.055))
		add_child(title)
	board_label = Label3D.new()
	board_label.name = "History"
	board_label.font = Vfx.font()
	board_label.font_size = 40
	board_label.pixel_size = 0.0034
	board_label.modulate = Palette.CREAM
	board_label.outline_size = 0
	board_label.double_sided = false
	board_label.position = Vector3(0, y - 0.17, z + 0.055)
	add_child(board_label)
	_update_board()


func _mesh_box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi


## Turns the wheel every frame (StationBase turns its own processing on and off with the Hot marker).
class _Ticker:
	extends Node
	var station: WheelStation

	func _process(delta: float) -> void:
		if station != null:
			station._tick(delta)
