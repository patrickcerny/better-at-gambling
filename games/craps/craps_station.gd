class_name CrapsStation
extends StationBase
## The craps table: a dark-wood tub with a padded burgundy rail and brass trim round a green felt
## printed with the four bets (Pass Line and the Don't Pass bar along the players' side, the Field
## across the middle, the point boxes 4 to 10 with the ON/OFF puck, Any Seven in front of the
## stickman), six stools along the south (+z) side, the stickman on the north side and a brass
## sign behind him with the point and the last roll.
##
## The dice: when the server rolls (`craps_rolled`, with the faces and a throw seed) the two dice
## leave the shooter's hand, tumble across the felt, bounce off the rails and come to rest showing
## the server's faces (`CrapsDice.simulate`: a deterministic throw steered onto the faces). Money
## never waits on them beyond the server's own throw time. Headless servers build nothing.

## Cabinet size (x along the table) and the heights of the felt and of the rail's top.
const TABLE_L: float = 4.3
const TABLE_D: float = 2.2
const FELT_Y: float = 0.88
const RAIL_TOP: float = 0.98
## The felt's inner half sizes (the rails' inner faces): the dice stay inside.
const FELT_HX: float = 1.85
const FELT_HZ: float = 0.8
const SEAT_XS: Array[float] = [-1.75, -1.05, -0.35, 0.35, 1.05, 1.75]
const SEAT_Z: float = 1.5
## The layout (z ranges on the felt, the players' side is +z).
const PASS_Z: float = 0.5
const DONT_Z: float = 0.27
const FIELD_Z: float = -0.04
const POINT_Z: float = -0.4
const SEVEN_Z: float = -0.67
const POINT_W: float = 0.42
## Where the stickman rakes lost chips (the rail in front of him).
const HOUSE_SPOT: Vector3 = Vector3(0.0, RAIL_TOP + 0.01, -TABLE_D * 0.5 + 0.12)
## Where the dice wait for a shooter at a fresh table (in front of the stickman).
const DICE_HOME: Vector3 = Vector3(1.0, FELT_Y + CrapsDice.HALF, -0.66)
const FELT_COLOR: Color = Color("#22553F")
## The seat view: the eye high over the players' rail, a little right of the middle and looking
## down at `SEAT_AIM`, so the whole felt and the stickman fill the left two thirds of the screen
## (the overlay is a column down the right third). Each seat's eye moves `SEAT_EYE_SHIFT` of its
## stool's x along.
const SEAT_EYE: Vector3 = Vector3(1.0, 3.2, 1.35)
const SEAT_AIM: Vector3 = Vector3(1.0, 1.31, -0.98)
const SEAT_EYE_SHIFT: float = 0.05

## Client-side presentation (empty on a headless server).
var dice_nodes: Array[Node3D] = []
var puck: Node3D
var puck_label: Label3D
var sign_point: Label3D
var sign_roll: Label3D
## The throw being shown: its seed (−1 = dice resting), plan and local clock.
var throw_seed: int = -1
var throw_t: float = 0.0
var plan: Dictionary = {}
## The faces the dice show (or will show once the throw rests).
var faces: Array[int] = [5, 2]
var point: int = 0
var _state: int = CrapsLogic.State.IDLE
var _outcome: StringName = &""
var _last_shooter_seat: int = -1


func _build_visuals() -> void:
	game_id = &"craps"
	seat_count = SEAT_XS.size()
	interact_radius = 3.0
	hot_center = Vector3(0, 0, 0.3)
	_rug(Vector2(6.4, 4.8), Color("#41243A").darkened(0.35))
	var wood := Color("#3A2A1E")
	GreyboxKit.box(self, Vector3(TABLE_L, FELT_Y - 0.02, TABLE_D), Vector3(0, (FELT_Y - 0.02) * 0.5, 0), wood, "Body")
	# The rails: solid walls round the felt up to the leaning rail.
	var rail_h: float = RAIL_TOP - FELT_Y + 0.02
	var rail_y: float = FELT_Y - 0.02 + rail_h * 0.5
	var side_t: float = TABLE_D * 0.5 - FELT_HZ
	var end_t: float = TABLE_L * 0.5 - FELT_HX
	for s: float in [-1.0, 1.0]:
		GreyboxKit.box(self, Vector3(TABLE_L, rail_h, side_t), Vector3(0, rail_y, s * (FELT_HZ + side_t * 0.5)), wood, "RailSide")
		GreyboxKit.box(self, Vector3(end_t, rail_h, FELT_HZ * 2.0), Vector3(s * (FELT_HX + end_t * 0.5), rail_y, 0), wood, "RailEnd")
	GreyboxKit.box(self, Vector3(FELT_HX * 2.0, 0.02, FELT_HZ * 2.0), Vector3(0, FELT_Y - 0.01, 0), FELT_COLOR, "Felt", false)
	for i: int in SEAT_XS.size():
		var spot := Vector3(SEAT_XS[i], 0, SEAT_Z)
		_stool(spot, "Stool%d" % i)
		_add_seat(spot + Vector3(0, 0.5, 0), 0.0)
		_add_seat_camera(SEAT_EYE + Vector3(SEAT_XS[i] * SEAT_EYE_SHIFT, 0, 0), SEAT_AIM)
	# The sign's posts stand on the floor behind the stickman (solid; the sign is above heads).
	for x: float in [-1.2, 1.2]:
		GreyboxKit.cylinder(self, 0.05, 2.6, Vector3(x, 1.3, -TABLE_D * 0.5 - 0.95), Palette.WARM_GOLD, "SignPost", true, 0.8)
	camera_anchor = Node3D.new()
	camera_anchor.name = "CameraAnchor"
	camera_anchor.position = SEAT_EYE  # the middle seat view: the whole felt, left of the overlay
	camera_anchor.rotation = look_rotation(SEAT_EYE, SEAT_AIM)
	add_child(camera_anchor)
	if Vfx.enabled():
		_build_dressing()
		_build_layout()
		_build_sign()
		_build_dice()
		var ticker := _Ticker.new()
		ticker.name = "DiceTicker"
		ticker.station = self
		add_child(ticker)
		_update_puck()
		_update_sign()


## The felt inside the rails, as x0, z0 … x1, z1 (Rect2 position and end in x/z).
static func felt_rect() -> Rect2:
	return Rect2(-FELT_HX, -FELT_HZ, FELT_HX * 2.0, FELT_HZ * 2.0)


## Local spot on the felt where `type` chips from `seat` go (each seat its own spot on the line
## bets and the Field, the Any Seven box shared in a row).
static func bet_spot(type: StringName, seat: int) -> Vector3:
	var s: int = clampi(seat, 0, SEAT_XS.size() - 1)
	var x: float = SEAT_XS[s] * 0.86
	match type:
		&"pass":
			return Vector3(x, FELT_Y + 0.003, PASS_Z)
		&"dont_pass":
			return Vector3(x, FELT_Y + 0.003, DONT_Z)
		&"field":
			return Vector3(x, FELT_Y + 0.003, FIELD_Z)
		&"any_seven":
			return Vector3(-0.5 + s * 0.2, FELT_Y + 0.003, SEVEN_Z)
	return Vector3(x, FELT_Y + 0.003, PASS_Z)


## Middle of the point box for `number` (4, 5, 6, 8, 9, 10).
static func point_spot(number: int) -> Vector3:
	var i: int = maxi(CrapsLogic.POINTS.find(number), 0)
	return Vector3((i - 2.5) * POINT_W, FELT_Y, POINT_Z)


## Where a throw from `seat` leaves the hand (−1 = the stickman) and the point on the felt it is
## aimed at: lengthwise to the far end, like at a real table.
static func throw_from(seat: int) -> Vector3:
	if seat < 0:
		return Vector3(-0.3, FELT_Y + 0.28, -FELT_HZ + 0.16)
	return Vector3(clampf(SEAT_XS[clampi(seat, 0, SEAT_XS.size() - 1)], -1.45, 1.45), FELT_Y + 0.3, FELT_HZ - 0.16)


static func throw_target(seat: int) -> Vector3:
	var x: float = SEAT_XS[clampi(seat, 0, SEAT_XS.size() - 1)] if seat >= 0 else -0.3
	var far: float = -1.0 if x > 0.0 else 1.0
	return Vector3(far * FELT_HX, FELT_Y, -0.15 if seat >= 0 else 0.25)


# --- Server state and events (client) -----------------------------------------------------------

## Newest public state: the point and the sign, and a throw to catch up to (a late joiner sees the
## dice in the air; `seat_of` maps a player to their seat index, −1 = unknown).
func show_state(pub: Dictionary, seat_of: Callable = Callable()) -> void:
	_state = int(pub.get("state", CrapsLogic.State.IDLE))
	point = int(pub.get("point", 0))
	_outcome = StringName(pub.get("outcome", &""))
	var d: Array = pub.get("dice", [])
	var seed_value: int = int(pub.get("throw_seed", -1))
	if _state == CrapsLogic.State.ROLLING and d.size() == 2 and seed_value > 0 and seed_value != throw_seed:
		var by: int = int(pub.get("thrown_by", -1))
		throw(d, seed_value, seat_of.call(by) if by >= 0 and seat_of.is_valid() else -1, float(pub.get("roll_time", 0.0)))
	elif _state == CrapsLogic.State.RESULT and d.size() == 2 and plan.is_empty() and faces != _ints(d):
		show_at_rest(d)
	_update_puck()
	_update_sign()


## The server rolled `dice` with throw `seed_value` from `seat` (−1 = the stickman): the dice fly
## now (`at` seconds into the throw). Returns the seconds until they rest on the table.
func throw(dice: Array, seed_value: int, seat: int, at: float = 0.0) -> float:
	faces = _ints(dice)
	if dice_nodes.is_empty():
		throw_seed = seed_value
		return 0.0
	if seed_value == throw_seed and not plan.is_empty():
		return maxf(0.0, float(plan["rest"]) - throw_t)
	throw_seed = seed_value
	plan = CrapsDice.simulate(seed_value, throw_from(seat), throw_target(seat), felt_rect(), FELT_Y, faces)
	throw_t = clampf(at, 0.0, float(plan["duration"]))
	_place_dice()
	_state = CrapsLogic.State.ROLLING
	_update_sign()
	if at < 0.3 and is_inside_tree():
		Audio.play_at(&"chip_clack", self, -8.0, 0.7)  # the dice leave the hand
	return maxf(0.0, float(plan["rest"]) - throw_t)


## The dice lie showing `dice` without a throw (a client that joined after it rested; headless
## tests): in front of the stickman.
func show_at_rest(dice: Array) -> void:
	faces = _ints(dice)
	plan = {}
	for i: int in dice_nodes.size():
		var flat: Basis = _flat_showing(faces[i], 0.35 * i)
		dice_nodes[i].transform = Transform3D(flat, DICE_HOME + Vector3(i * CrapsDice.EDGE * 1.5, 0, 0))


## The roll is over on the server (`craps_result`): the point moves and the sign shows the roll.
func show_result(total: int, outcome: StringName, new_point: int) -> void:
	_outcome = outcome
	point = new_point
	_state = CrapsLogic.State.RESULT
	_update_puck()
	_update_sign(total)


## A minigame called the round off: the puck goes off, the dice go home.
func reset_table() -> void:
	point = 0
	plan = {}
	throw_seed = -1
	_outcome = &""
	_state = CrapsLogic.State.IDLE
	show_at_rest(faces)
	_update_puck()
	_update_sign()


## True while the dice are still moving on this table.
func rolling() -> bool:
	return not plan.is_empty() and throw_t < float(plan["rest"])


## The faces the dice show right now (read off their orientation, not remembered).
func shown_faces() -> Array[int]:
	var out: Array[int] = []
	for n: Node3D in dice_nodes:
		out.append(CrapsDice.face_up(n.transform.basis))
	return out


func _tick_dice(delta: float) -> void:
	if plan.is_empty():
		return
	var was_rolling: bool = rolling()
	throw_t = minf(throw_t + delta, float(plan["duration"]))
	_place_dice()
	if was_rolling and not rolling() and is_inside_tree():
		Audio.play_at(&"chip_clack", self, -12.0, 0.6)


func _place_dice() -> void:
	for i: int in dice_nodes.size():
		dice_nodes[i].transform = CrapsDice.sample(plan, i, throw_t)


## A die lying flat with `value` on top, turned `yaw` about the vertical.
static func _flat_showing(value: int, yaw: float) -> Basis:
	var n: Vector3 = CrapsDice.FACE_NORMALS[clampi(value, 1, 6) - 1]
	var to_up: Basis = Basis.IDENTITY
	if n == Vector3.DOWN:
		to_up = Basis(Vector3.RIGHT, PI)
	elif n != Vector3.UP:
		to_up = Basis(n.cross(Vector3.UP).normalized(), PI * 0.5)
	return Basis(Vector3.UP, yaw) * to_up


static func _ints(a: Array) -> Array[int]:
	var out: Array[int] = []
	for x: Variant in a:
		out.append(int(x))
	return out


func _update_puck() -> void:
	if puck == null:
		return
	if point in CrapsLogic.POINTS:
		puck.position = point_spot(point) + Vector3(0.13, 0.012, -0.07)
		puck_label.text = "ON"
		puck_label.modulate = Palette.CASINO_BLACK
		(puck.get_child(0) as MeshInstance3D).material_override = GreyboxKit.material(Palette.CREAM, 0.0, 0.5)
	else:
		puck.position = Vector3(-FELT_HX + 0.22, FELT_Y + 0.012, POINT_Z)
		puck_label.text = "OFF"
		puck_label.modulate = Palette.CREAM
		(puck.get_child(0) as MeshInstance3D).material_override = GreyboxKit.material(Palette.CASINO_BLACK, 0.0, 0.5)


func _update_sign(total: int = -1) -> void:
	if sign_point == null:
		return
	sign_point.text = ("POINT  %d" % point) if point > 0 else "COME-OUT ROLL"
	if _state == CrapsLogic.State.ROLLING:
		sign_roll.text = "DICE ARE OUT"
		sign_roll.modulate = Palette.CREAM
		return
	if total < 0:
		if _state != CrapsLogic.State.RESULT:
			sign_roll.text = "PLACE YOUR BETS" if _state == CrapsLogic.State.BETTING else "TAKE A SEAT"
			sign_roll.modulate = Palette.CREAM
		return
	var words: Dictionary = {&"natural": "WINNER!", &"craps": "CRAPS!", &"point_set": "MARK THE POINT", &"point_made": "WINNER! POINT MADE", &"seven_out": "SEVEN OUT", &"roll": ""}
	var w: String = String(words.get(_outcome, ""))
	sign_roll.text = "%d%s" % [total, ("  ·  " + w) if w != "" else ""]
	sign_roll.modulate = Palette.VIP_GOLD if _outcome in [&"natural", &"point_made"] else (Palette.LOSS_RED if _outcome in [&"craps", &"seven_out"] else Palette.CREAM)


# --- Building (client only) -----------------------------------------------------------------------

func _build_dressing() -> void:
	var leather: StandardMaterial3D = GreyboxKit.material(Palette.VIP_BURGUNDY.darkened(0.15), 0.0, 0.55)
	var brass: StandardMaterial3D = GreyboxKit.material(Palette.WARM_GOLD, 0.8, 0.35)
	var dark: StandardMaterial3D = GreyboxKit.material(Color("#1E1917"), 0.0, 0.8)
	# Padded leather on the rail's top, a brass line on its inner edge, dark inner walls.
	var side_t: float = TABLE_D * 0.5 - FELT_HZ
	var end_t: float = TABLE_L * 0.5 - FELT_HX
	var velvet: StandardMaterial3D = GreyboxKit.material(Palette.VIP_BURGUNDY, 0.0, 0.95)
	for s: float in [-1.0, 1.0]:
		# The padded rail rolls a little over the outside, like a real tub's bumper.
		_mesh_box(Vector3(TABLE_L + 0.12, 0.07, side_t + 0.06), Vector3(0, RAIL_TOP + 0.035, s * (FELT_HZ + side_t * 0.5 + 0.03)), leather)
		_mesh_box(Vector3(end_t + 0.06, 0.07, FELT_HZ * 2.0), Vector3(s * (FELT_HX + end_t * 0.5 + 0.03), RAIL_TOP + 0.035, 0), leather)
		# Velvet panels framed in brass round the cabinet.
		_mesh_box(Vector3(TABLE_L - 0.36, 0.5, 0.02), Vector3(0, 0.45, s * (TABLE_D * 0.5 + 0.01)), velvet)
		_mesh_box(Vector3(0.02, 0.5, TABLE_D - 0.36), Vector3(s * (TABLE_L * 0.5 + 0.01), 0.45, 0), velvet)
		_mesh_box(Vector3(TABLE_L + 0.03, 0.025, 0.03), Vector3(0, FELT_Y - 0.03, s * (TABLE_D * 0.5 + 0.015)), brass)
		_mesh_box(Vector3(0.03, 0.025, TABLE_D + 0.03), Vector3(s * (TABLE_L * 0.5 + 0.015), FELT_Y - 0.03, 0), brass)
		_mesh_box(Vector3(FELT_HX * 2.0, 0.015, 0.02), Vector3(0, RAIL_TOP + 0.005, s * (FELT_HZ + 0.01)), brass)
		_mesh_box(Vector3(0.02, 0.015, FELT_HZ * 2.0), Vector3(s * (FELT_HX + 0.01), RAIL_TOP + 0.005, 0), brass)
		_mesh_box(Vector3(FELT_HX * 2.0, RAIL_TOP - FELT_Y - 0.01, 0.01), Vector3(0, (RAIL_TOP + FELT_Y) * 0.5, s * (FELT_HZ - 0.004)), dark)
		_mesh_box(Vector3(0.01, RAIL_TOP - FELT_Y - 0.01, FELT_HZ * 2.0), Vector3(s * (FELT_HX - 0.004), (RAIL_TOP + FELT_Y) * 0.5, 0), dark)
		# Brass kick strip along the outside, near the floor.
		_mesh_box(Vector3(TABLE_L, 0.06, 0.03), Vector3(0, 0.08, s * (TABLE_D * 0.5 + 0.015)), brass)
		_mesh_box(Vector3(0.03, 0.06, TABLE_D), Vector3(s * (TABLE_L * 0.5 + 0.015), 0.08, 0), brass)
	# The rubber diamonds on the end walls the dice bounce off.
	var rubber: StandardMaterial3D = GreyboxKit.material(Color("#2B2422"), 0.0, 0.95)
	for s: float in [-1.0, 1.0]:
		for k: int in 9:
			var z: float = lerpf(-FELT_HZ + 0.1, FELT_HZ - 0.1, k / 8.0)
			var d := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.024, 0.045, 0.045)
			d.mesh = bm
			d.material_override = rubber
			d.position = Vector3(s * (FELT_HX - 0.014), FELT_Y + 0.05, z)
			d.rotation.x = PI * 0.25
			add_child(d)


## The betting layout printed on the felt, read from the stools (the players' side is +z).
func _build_layout() -> void:
	var root := Node3D.new()
	root.name = "LayoutPrint"
	add_child(root)
	var y: float = FELT_Y + 0.001
	var line_c: Color = Palette.CREAM
	var w: float = 3.5
	_outline(root, Vector3(0, y, PASS_Z), Vector2(w, 0.2), line_c)
	_print(root, "PASS LINE", Vector3(-1.1, y, PASS_Z), 64, Palette.CREAM)
	_print(root, "PASS LINE", Vector3(1.1, y, PASS_Z), 64, Palette.CREAM)
	_print(root, "PAYS 1 TO 1", Vector3(0, y, PASS_Z), 34, Palette.WARM_GOLD)
	_outline(root, Vector3(0, y, DONT_Z), Vector2(w, 0.18), line_c)
	_print(root, "DON'T PASS BAR", Vector3(-0.85, y, DONT_Z), 48, Palette.CREAM)
	_print(root, "12 PUSHES", Vector3(0.95, y, DONT_Z), 36, Palette.CREAM)
	_dice_pips(root, Vector3(0.35, y, DONT_Z), [6, 6])
	# The Field: the winning numbers, 2 and 12 circled as double.
	_fill(root, Vector3(0, y - 0.0004, FIELD_Z), Vector2(w, 0.36), FELT_COLOR.lightened(0.07))
	_outline(root, Vector3(0, y, FIELD_Z), Vector2(w, 0.36), line_c)
	_print(root, "FIELD", Vector3(-1.4, y, FIELD_Z), 72, Palette.VIP_GOLD)
	var nums: Array[int] = [2, 3, 4, 9, 10, 11, 12]
	for k: int in nums.size():
		var x: float = -0.8 + k * 0.33
		var dbl: bool = nums[k] == 2 or nums[k] == 12
		if dbl:
			_ring(root, Vector3(x, y, FIELD_Z), 0.1, Palette.WARM_GOLD)
		_print(root, str(nums[k]), Vector3(x, y, FIELD_Z), 72 if not dbl else 64, Palette.CREAM if not dbl else Palette.VIP_GOLD)
	_print(root, "2 & 12 PAY DOUBLE", Vector3(1.5, y, FIELD_Z), 28, Palette.WARM_GOLD)
	# The point boxes.
	for k: int in CrapsLogic.POINTS.size():
		var n: int = CrapsLogic.POINTS[k]
		var c: Vector3 = point_spot(n) + Vector3(0, 0.001, 0)
		_outline(root, c, Vector2(POINT_W - 0.02, 0.28), line_c)
		_print(root, {6: "SIX", 9: "NINE"}.get(n, str(n)), c, 96 if n != 6 and n != 9 else 60, Palette.CREAM)
	# Any Seven, in front of the stickman.
	_fill(root, Vector3(0, y - 0.0004, SEVEN_Z), Vector2(1.3, 0.2), Palette.CASINO_RED.darkened(0.15))
	_outline(root, Vector3(0, y, SEVEN_Z), Vector2(1.3, 0.2), Palette.WARM_GOLD)
	_print(root, "ANY SEVEN  ·  4 TO 1", Vector3(0, y, SEVEN_Z), 52, Palette.CREAM)
	# The puck (OFF on the come-out, ON on the point).
	puck = Node3D.new()
	puck.name = "Puck"
	add_child(puck)
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.055
	cm.bottom_radius = 0.055
	cm.height = 0.02
	cm.radial_segments = 20
	disc.mesh = cm
	puck.add_child(disc)
	puck_label = Label3D.new()
	puck_label.font = Vfx.font()
	puck_label.font_size = 44
	puck_label.pixel_size = 0.0015
	puck_label.outline_size = 0
	puck_label.rotation.x = -PI * 0.5
	puck_label.position.y = 0.011
	puck.add_child(puck_label)


## Two little dice printed on the felt showing `values` (the bar 12 mark).
func _dice_pips(root: Node3D, c: Vector3, values: Array) -> void:
	for k: int in values.size():
		var at: Vector3 = c + Vector3((k - 0.5) * 0.12, 0, 0)
		_fill(root, at, Vector2(0.1, 0.1), Palette.CREAM)
		for s: Vector2 in CrapsDice.PIP_SPOTS[int(values[k])]:
			_fill(root, at + Vector3(s.x * 0.027, 0.0004, s.y * 0.027), Vector2(0.018, 0.018), Palette.CASINO_RED)


## The brass sign behind the stickman: the game, the odds, the point and the last roll.
func _build_sign() -> void:
	var z: float = -TABLE_D * 0.5 - 0.95
	var y: float = 2.15
	var w: float = 2.7
	var h: float = 0.95
	_mesh_box(Vector3(w, h, 0.08), Vector3(0, y, z), GreyboxKit.material(Palette.CASINO_BLACK.lightened(0.06), 0.0, 0.6))
	var gold: StandardMaterial3D = GreyboxKit.material(Palette.WARM_GOLD, 0.85, 0.3)
	for dy: float in [-1.0, 1.0]:
		_mesh_box(Vector3(w + 0.1, 0.06, 0.12), Vector3(0, y + dy * (h * 0.5 + 0.02), z), gold)
	for dx: float in [-1.0, 1.0]:
		_mesh_box(Vector3(0.06, h + 0.1, 0.12), Vector3(dx * (w * 0.5 + 0.02), y, z), gold)
	var title: Label3D = _sign_label("CRAPS", 92, Vector3(0, y + 0.3, z + 0.05))
	title.modulate = Palette.VIP_GOLD
	_sign_label("PASS 1:1  ·  FIELD 1:1, 2 & 12 2:1  ·  ANY SEVEN 4:1", 30, Vector3(0, y + 0.1, z + 0.05)).modulate = Palette.WARM_GOLD
	sign_point = _sign_label("COME-OUT ROLL", 54, Vector3(0, y - 0.09, z + 0.05))
	sign_roll = _sign_label("TAKE A SEAT", 54, Vector3(0, y - 0.3, z + 0.05))


func _build_dice() -> void:
	var body := StandardMaterial3D.new()
	body.albedo_color = Color("#B3262E")
	body.roughness = 0.22
	body.clearcoat_enabled = true
	body.clearcoat = 0.8
	var pips: StandardMaterial3D = GreyboxKit.material(Palette.CREAM, 0.0, 0.4)
	for i: int in 2:
		var d: Node3D = CrapsDice.make_die(body, pips)
		d.name = "Die%d" % (i + 1)
		add_child(d)
		dice_nodes.append(d)
	show_at_rest(faces)


func _sign_label(text: String, size: int, pos: Vector3) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = Vfx.font()
	l.font_size = size
	l.pixel_size = 0.0032
	l.modulate = Palette.CREAM
	l.outline_size = 0
	l.position = pos
	add_child(l)
	return l


## Flat text on the felt, read from the stools.
func _print(root: Node3D, text: String, pos: Vector3, size: int, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = Vfx.font()
	l.font_size = size
	l.pixel_size = 0.0015
	l.modulate = color
	l.outline_size = 0
	l.rotation.x = -PI * 0.5
	l.position = pos + Vector3(0, 0.0015, 0)
	root.add_child(l)
	return l


func _fill(root: Node3D, pos: Vector3, size: Vector2, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size
	mi.mesh = pm
	mi.material_override = GreyboxKit.material(color, 0.0, 0.85)
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


## A printed rectangle outline (cream lines 1.2 cm wide).
func _outline(root: Node3D, c: Vector3, size: Vector2, color: Color) -> void:
	var t: float = 0.012
	for s: float in [-1.0, 1.0]:
		_fill(root, c + Vector3(0, 0.0003, s * (size.y - t) * 0.5), Vector2(size.x, t), color)
		_fill(root, c + Vector3(s * (size.x - t) * 0.5, 0.0003, 0), Vector2(t, size.y), color)


## A printed circle around a number (the Field's doubles).
func _ring(root: Node3D, c: Vector3, radius: float, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = radius - 0.008
	tm.outer_radius = radius
	tm.rings = 24
	tm.ring_segments = 4
	mi.mesh = tm
	mi.material_override = GreyboxKit.material(color, 0.0, 0.85)
	mi.scale = Vector3(1.0, 0.05, 1.0)
	mi.position = c + Vector3(0, 0.0003, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


func _mesh_box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi


## Runs the dice throw every frame (StationBase turns its own processing on and off with the Hot
## marker).
class _Ticker:
	extends Node
	var station: CrapsStation

	func _process(delta: float) -> void:
		if station != null:
			station._tick_dice(delta)
