class_name HorseRaceStation
extends StationBase
## The horse race table: a long dark-wood cabinet with a miniature four-lane turf track under a
## low glass wall and brass rail, a starting gate at the west end, a checkered finish line under a
## gold arch at the east end, name plates at the gate, four betting pads on the players' ledge and
## a tote board behind the track. Six stools along the south (+z) side face the track.
##
## The race on the table is a replay of `HorseRaceLogic.simulate(seed)`: the server sends the seed
## when the gates open (`horse_race_started`) and its race clock in every snapshot, so every
## client runs the same race and catches up if it falls behind. Presentation only (client-side):
## money is settled by the server when its own clock reaches the winner's time.

## Cabinet size (x along the track) and the height of its top.
const TABLE_L: float = 8.6
const TABLE_D: float = 2.5
const TABLE_TOP: float = 0.9
## The turf: top height, lane width, lane 0 nearest the players.
const TURF_Y: float = 0.925
const LANE_W: float = 0.42
const LANE_Z0: float = 0.5
const TRACK_X0: float = -3.75
const TRACK_X1: float = 4.15
const TRACK_Z_NEAR: float = 0.71
const TRACK_Z_FAR: float = -0.97
## Where the noses stand in the gate (progress 0) and where the line is (progress 1).
const START_X: float = -3.15
const FINISH_X: float = 3.3
## Miniature size: the model is about 2.25 long, the minis a little over half a metre.
const HORSE_SCALE: float = 0.24
## Silks and saddle cloths per lane (1 red, 2 blue, 3 gold, 4 cream).
const LANE_COLORS: Array[Color] = [Color("#C83D3D"), Color("#3F6FB5"), Color("#D6A84B"), Color("#F2E6C9")]
const COAT_KEYS: Array[StringName] = [&"chestnut", &"bay", &"grey", &"black", &"palomino"]
## The players' ledge in front of the glass: the betting pads, and where lost chips go.
const LEDGE_Z: float = 1.0
const PAD_XS: Array[float] = [-1.05, -0.35, 0.35, 1.05]
const HOUSE_SPOT: Vector3 = Vector3(3.85, TABLE_TOP + 0.02, LEDGE_Z)
const SEAT_XS: Array[float] = [-2.25, -1.35, -0.45, 0.45, 1.35, 2.25]
const SEAT_Z: float = 1.85

## Client-side presentation (empty on a headless server).
var horses: Array[HorseModel] = []
var gates: Array[Node3D] = []
var plate_labels: Array[Label3D] = []
var board_rows: Array[Label3D] = []
## Each horse's place in the running race, beside its row.
var board_places: Array[Label3D] = []
var board_status: Label3D
var names: Array[String] = []
## The race being shown: its seed (−1 = horses in the gate), plan and local clock.
var race_seed: int = -1
var race_t: float = 0.0
var plan: Dictionary = {}
## Lane the server says won (−1 until it does); shown once the local race gets there.
var winner: int = -1
var _celebrated: bool = false
var _last_prog: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _state: int = HorseRaceLogic.State.IDLE
var _counting: bool = false
var _timer: float = 0.0
var _status_text: String = ""


func _build_visuals() -> void:
	game_id = &"horse_race"
	seat_count = SEAT_XS.size()
	interact_radius = 3.2
	hot_center = Vector3(0, 0, 0.6)
	_rug(Vector2(11.4, 6.6), Palette.FELT_GREEN.darkened(0.55))
	var wood := Color("#3A2A1E")
	GreyboxKit.box(self, Vector3(TABLE_L, TABLE_TOP - 0.04, TABLE_D), Vector3(0, (TABLE_TOP - 0.04) * 0.5, 0), wood, "Body")
	GreyboxKit.box(self, Vector3(TABLE_L, 0.04, TABLE_D), Vector3(0, TABLE_TOP - 0.02, 0), Color("#1E1917"), "Top", false)
	for i: int in SEAT_XS.size():
		var spot := Vector3(SEAT_XS[i], 0, SEAT_Z)
		_stool(spot, "Stool%d" % i)
		_add_seat(spot + Vector3(0, 0.5, 0), 0.0)
	# The tote board's legs stand on the floor behind the track (solid; the board is above heads).
	for x: float in [-2.45, 2.45]:
		GreyboxKit.cylinder(self, 0.07, 3.0, Vector3(x, 1.5, -1.85), Palette.WARM_GOLD, "ToteLeg", true, 0.8)
	camera_anchor = Node3D.new()
	camera_anchor.name = "CameraAnchor"
	camera_anchor.position = Vector3(0.0, 2.75, 3.55)  # behind the stools, over their heads
	camera_anchor.rotation.x = deg_to_rad(-30.0)
	add_child(camera_anchor)
	if Vfx.enabled():
		_build_dressing()
		_build_track()
		_build_gate()
		_build_finish()
		_build_ledge()
		_build_board()
		var ticker := _Ticker.new()
		ticker.name = "RaceTicker"
		ticker.station = self
		add_child(ticker)
		_set_names(["", "", "", ""])
		_place_horses([0.0, 0.0, 0.0, 0.0])


## Local x of a horse's nose at `progress` (0 = gate, 1 = finish line).
static func track_x(progress: float) -> float:
	return START_X + progress * (FINISH_X - START_X)


## Local z of a lane's centre.
static func lane_z(lane: int) -> float:
	return LANE_Z0 - lane * LANE_W


## Local spot on the ledge where chips on `horse` go (its betting pad).
static func bet_spot(horse: int) -> Vector3:
	return Vector3(PAD_XS[clampi(horse, 0, PAD_XS.size() - 1)], TABLE_TOP + 0.02, LEDGE_Z)


## Coat for a horse name: the same name is always the same horse.
static func coat_for(horse_name: String) -> StringName:
	return COAT_KEYS[posmod(horse_name.hash(), COAT_KEYS.size())]


# --- Server state and events (client) -----------------------------------------------------------

## Newest public state: names, the countdown on the board, and the race clock to catch up to.
func show_state(pub: Dictionary) -> void:
	var n: Array = pub.get("names", [])
	if n.size() == HorseRaceLogic.HORSES:
		_set_names(n)
	_state = int(pub.get("state", HorseRaceLogic.State.IDLE))
	_counting = bool(pub.get("counting", false))
	_timer = float(pub.get("timer", 0.0))
	var seed_value: int = int(pub.get("race_seed", -1))
	var t: float = float(pub.get("race_time", 0.0))
	if (_state == HorseRaceLogic.State.RACING or _state == HorseRaceLogic.State.RESULT) and seed_value > 0:
		if seed_value != race_seed:
			start_race(seed_value, t)
		elif absf(t - race_t) > 0.5 and t < float(plan.get("duration", 0.0)):
			race_t = t  # fell behind (or ran ahead): rejoin the server's race
		if _state == HorseRaceLogic.State.RESULT and int(pub.get("winner", -1)) >= 0:
			winner = int(pub["winner"])
	elif race_seed != -1:
		reset_table()
	_update_board()


## New names for the round (from `round_started` or the state).
func set_names(n: Array) -> void:
	if n.size() == HorseRaceLogic.HORSES:
		_set_names(n)
		_update_board()


## The gates open on the server's race `seed_value`, `at` seconds in.
func start_race(seed_value: int, at: float = 0.0) -> void:
	if seed_value == race_seed:
		return
	race_seed = seed_value
	plan = HorseRaceLogic.simulate(seed_value)
	race_t = at
	winner = -1
	_celebrated = false
	_last_prog = HorseRaceLogic.sample(plan, at)
	_state = HorseRaceLogic.State.RACING
	_place_horses(_last_prog)
	for g: Node3D in gates:
		if g.is_inside_tree() and at < 0.5:
			g.create_tween().tween_property(g, ^"rotation:y", deg_to_rad(105.0), 0.25).set_ease(Tween.EASE_OUT)
		else:
			g.rotation.y = deg_to_rad(105.0)
	if at < 0.5 and is_inside_tree():
		Audio.play_at(&"last_call_bell", self, -12.0, 1.35)  # the starting bell
	_update_board()


## The server's result: lane `lane` won. Returns the seconds until its nose crosses the line on this
## table (the result waits for that, so the money never spoils the race).
func finish(lane: int, seed_value: int = -1) -> float:
	if seed_value > 0 and seed_value != race_seed:
		start_race(seed_value, 0.0)
	winner = lane
	if plan.is_empty():
		return 0.0
	return maxf(0.0, float(plan["finish"][lane]) - race_t)


## Back to the gate (a new round, or the minigame called the race off).
func reset_table() -> void:
	race_seed = -1
	plan = {}
	race_t = 0.0
	winner = -1
	_celebrated = false
	_last_prog = [0.0, 0.0, 0.0, 0.0]
	for g: Node3D in gates:
		g.rotation.y = 0.0
	_place_horses(_last_prog)
	for h: HorseModel in horses:
		h.set_running(0.0)


## Lanes in the order the table shows them right now (leader first).
func shown_order() -> Array[int]:
	return HorseRaceLogic.order_of(_last_prog)


## True once the local replay has the winner over the line.
func winner_shown() -> bool:
	return winner >= 0 and not plan.is_empty() and race_t >= float(plan["finish"][winner])


func _tick_race(delta: float) -> void:
	if plan.is_empty():
		return
	race_t = minf(race_t + delta, float(plan["duration"]))
	var prog: Array[float] = HorseRaceLogic.sample(plan, race_t)
	var base: float = HorseRaceLogic.FINISH / HorseRaceLogic.RACE_SECONDS
	for h: int in mini(horses.size(), prog.size()):
		var v: float = (prog[h] - _last_prog[h]) / maxf(delta, 0.001)
		horses[h].set_running(clampf(v / base, 0.0, 1.0) if v > 0.0005 else 0.0)
	_place_horses(prog)
	_last_prog = prog
	if winner_shown() and not _celebrated:
		_celebrated = true
		var champ: HorseModel = horses[winner] if winner < horses.size() else null
		if champ != null and is_inside_tree():
			# Bound to the horse itself, so the connection goes away with it (no dangling capture).
			get_tree().create_timer(0.6).timeout.connect(champ.celebrate)
		Audio.play_at(&"chime", self, -6.0)
	_update_board()


func _place_horses(prog: Array) -> void:
	for h: int in horses.size():
		var p: float = float(prog[h]) if h < prog.size() else 0.0
		horses[h].position = Vector3(track_x(p) + HorseModel.NOSE_Z * HORSE_SCALE, TURF_Y, lane_z(h))


func _set_names(n: Array) -> void:
	var fresh: Array[String] = []
	for x: Variant in n:
		fresh.append(String(x))
	if fresh == names:
		return
	names = fresh
	for i: int in mini(plate_labels.size(), names.size()):
		plate_labels[i].text = "%d\n%s" % [i + 1, names[i].to_upper()] if names[i] != "" else str(i + 1)
	if not Vfx.enabled():
		return
	# A new line-up walks in: each name always brings the same coat.
	for i: int in names.size():
		var coat: StringName = coat_for(names[i]) if names[i] != "" else COAT_KEYS[i]
		if i < horses.size() and horses[i].get_meta(&"coat", &"") == coat:
			continue
		var h := HorseModel.new(coat, LANE_COLORS[i], i)
		h.set_meta(&"coat", coat)
		h.name = "Horse%d" % (i + 1)
		h.scale = Vector3.ONE * HORSE_SCALE
		h.rotation.y = -PI * 0.5  # faces down the track (+x)
		if i < horses.size():
			h.position = horses[i].position
			horses[i].queue_free()
			horses[i] = h
		else:
			horses.append(h)
		add_child(h)
	if plan.is_empty():
		_place_horses([0.0, 0.0, 0.0, 0.0])


func _update_board() -> void:
	if board_status == null:
		return
	var text: String = ""
	var order: Array[int] = shown_order()
	var racing: bool = not plan.is_empty()
	match _state:
		HorseRaceLogic.State.IDLE:
			text = "TAKE A SEAT  ·  PAYS 1:4"
		HorseRaceLogic.State.BETTING:
			text = ("GATES OPEN IN %d" % ceili(maxf(_timer, 0.0))) if _counting else "PICK YOUR HORSE  ·  PAYS 1:4"
		_:
			if winner_shown():
				text = "WINNER: %d  %s" % [winner + 1, names[winner].to_upper() if winner < names.size() else ""]
			elif racing:
				text = "AND THEY'RE OFF!"
	if text != _status_text:
		_status_text = text
		board_status.text = text
		board_status.modulate = Palette.VIP_GOLD if text.begins_with("WINNER") else Palette.CREAM
	for i: int in board_rows.size():
		var place: String = ""
		if racing and race_t > 0.3:
			place = ["1ST", "2ND", "3RD", "4TH"][order.find(i)]
		var row: String = "%d  %s" % [i + 1, names[i].to_upper() if i < names.size() else ""]
		if board_rows[i].text != row:
			board_rows[i].text = row
		if board_places[i].text != place:
			board_places[i].text = place
		var lit: Color = Palette.VIP_GOLD if (winner_shown() and i == winner) else Palette.CREAM
		board_rows[i].modulate = lit
		board_places[i].modulate = lit


# --- Building (client only) -----------------------------------------------------------------------

func _build_dressing() -> void:
	# Burgundy velvet front and back, brass kick strips and a brass edge round the top.
	var velvet: StandardMaterial3D = GreyboxKit.material(Palette.VIP_BURGUNDY, 0.0, 0.95)
	var brass: StandardMaterial3D = GreyboxKit.material(Palette.WARM_GOLD, 0.8, 0.35)
	for side: float in [-1.0, 1.0]:
		_mesh_box(Vector3(TABLE_L - 0.4, 0.5, 0.02), Vector3(0, 0.45, side * (TABLE_D * 0.5 + 0.01)), velvet)
		_mesh_box(Vector3(TABLE_L, 0.06, 0.03), Vector3(0, 0.08, side * (TABLE_D * 0.5 + 0.015)), brass)
		_mesh_box(Vector3(TABLE_L + 0.04, 0.03, 0.04), Vector3(0, TABLE_TOP - 0.005, side * (TABLE_D * 0.5 + 0.01)), brass)
		_mesh_box(Vector3(0.04, 0.03, TABLE_D + 0.04), Vector3(side * (TABLE_L * 0.5 + 0.01), TABLE_TOP - 0.005, 0), brass)
	var leg: StandardMaterial3D = GreyboxKit.material(Color("#2A1E16"), 0.0, 0.7)
	for x: float in [-TABLE_L * 0.5 + 0.2, TABLE_L * 0.5 - 0.2]:
		for side: float in [-1.0, 1.0]:
			_mesh_box(Vector3(0.12, 0.84, 0.12), Vector3(x, 0.42, side * (TABLE_D * 0.5 - 0.04)), leg)


func _build_track() -> void:
	var length: float = TRACK_X1 - TRACK_X0
	var mid_x: float = (TRACK_X0 + TRACK_X1) * 0.5
	var mid_z: float = (TRACK_Z_NEAR + TRACK_Z_FAR) * 0.5
	# Turf in mown stripes, one lane each, on a dark bed.
	_mesh_box(Vector3(length + 0.04, 0.02, TRACK_Z_NEAR - TRACK_Z_FAR + 0.04), Vector3(mid_x, TURF_Y - 0.015, mid_z), GreyboxKit.material(Color("#1E2A1E"), 0.0, 0.9))
	for lane: int in HorseRaceLogic.HORSES:
		var turf: Color = Color("#3F7A4B") if lane % 2 == 0 else Color("#386E44")
		_mesh_box(Vector3(length, 0.01, LANE_W - 0.01), Vector3(mid_x, TURF_Y - 0.005, lane_z(lane)), GreyboxKit.material(turf, 0.0, 0.95))
	# White running rails between the lanes and along both edges.
	var rail: StandardMaterial3D = GreyboxKit.material(Palette.CREAM, 0.0, 0.5)
	for k: int in HorseRaceLogic.HORSES + 1:
		var z: float = LANE_Z0 + LANE_W * 0.5 - k * LANE_W
		_mesh_box(Vector3(length, 0.03, 0.016), Vector3(mid_x, TURF_Y + 0.02, z), rail)
	# Furlong posts on the far rail.
	var tip: StandardMaterial3D = GreyboxKit.material(Palette.WARM_GOLD, 0.8, 0.35)
	for q: float in [0.25, 0.5, 0.75]:
		var x: float = track_x(q)
		_mesh_box(Vector3(0.025, 0.12, 0.025), Vector3(x, TURF_Y + 0.06, TRACK_Z_FAR + 0.03), rail)
		_mesh_box(Vector3(0.04, 0.03, 0.04), Vector3(x, TURF_Y + 0.13, TRACK_Z_FAR + 0.03), tip)
	# Glass wall round the track with a brass handrail and posts.
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.82, 0.9, 0.92, 0.14)
	glass.roughness = 0.05
	glass.metallic_specular = 1.0
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var brass: StandardMaterial3D = GreyboxKit.material(Palette.WARM_GOLD, 0.85, 0.3)
	var h: float = 0.24
	var zs: Array[float] = [TRACK_Z_NEAR + 0.05, TRACK_Z_FAR - 0.05]
	var x0: float = TRACK_X0 - 0.05
	var x1: float = TRACK_X1 + 0.05
	var rail_y: float = TABLE_TOP + h + 0.015
	for z: float in zs:
		var gm: MeshInstance3D = _mesh_box(Vector3(x1 - x0, h, 0.012), Vector3(mid_x, TABLE_TOP + h * 0.5, z), glass)
		gm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_rail_bar(Vector3(x0, rail_y, z), Vector3(x1, rail_y, z), brass)
	for x: float in [x0, x1]:
		var gm: MeshInstance3D = _mesh_box(Vector3(0.012, h, zs[0] - zs[1]), Vector3(x, TABLE_TOP + h * 0.5, mid_z), glass)
		gm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_rail_bar(Vector3(x, rail_y, zs[0]), Vector3(x, rail_y, zs[1]), brass)
	var posts: int = 9
	for i: int in posts:
		var x: float = lerpf(x0, x1, float(i) / (posts - 1))
		for z: float in zs:
			_mesh_box(Vector3(0.03, h + 0.02, 0.03), Vector3(x, TABLE_TOP + (h + 0.02) * 0.5, z), brass)


func _rail_bar(from: Vector3, to: Vector3, mat: Material) -> void:
	var c := CylinderMesh.new()
	c.top_radius = 0.016
	c.bottom_radius = 0.016
	c.height = from.distance_to(to)
	c.radial_segments = 8
	c.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = c
	mi.material_override = mat
	var d: Vector3 = (to - from).normalized()
	mi.transform = Transform3D(Basis(Vector3.UP.cross(d).normalized(), Vector3.UP.angle_to(d)), (from + to) * 0.5)
	add_child(mi)


## The starting gate: stalls behind the noses, a red-and-gold frame over the lanes, a numbered door
## per lane that swings open when the race starts, and the name plates on the marble before it.
func _build_gate() -> void:
	var back: float = START_X - HorseModel.LENGTH * HORSE_SCALE - 0.05
	var front: float = START_X + 0.03
	var cream: StandardMaterial3D = GreyboxKit.material(Palette.CREAM, 0.0, 0.5)
	var red: StandardMaterial3D = GreyboxKit.material(Palette.CASINO_RED, 0.0, 0.6)
	var gold: StandardMaterial3D = GreyboxKit.material(Palette.WARM_GOLD, 0.8, 0.35)
	var top_y: float = TURF_Y + 0.55
	for k: int in HorseRaceLogic.HORSES + 1:
		var z: float = LANE_Z0 + LANE_W * 0.5 - k * LANE_W
		_mesh_box(Vector3(front - back, 0.3, 0.02), Vector3((front + back) * 0.5, TURF_Y + 0.17, z), cream)  # stall wall
		for x: float in [back, front]:
			_mesh_box(Vector3(0.035, top_y - TURF_Y, 0.035), Vector3(x, (top_y + TURF_Y) * 0.5, z), gold)
	var span: float = TRACK_Z_NEAR - TRACK_Z_FAR
	var mid_z: float = (TRACK_Z_NEAR + TRACK_Z_FAR) * 0.5
	for x: float in [back, front]:
		_mesh_box(Vector3(0.06, 0.08, span + 0.04), Vector3(x, top_y, mid_z), red)
	_mesh_box(Vector3(front - back + 0.06, 0.03, span + 0.04), Vector3((front + back) * 0.5, top_y + 0.055, mid_z), gold)
	for lane: int in HorseRaceLogic.HORSES:
		var hinge := Node3D.new()
		hinge.name = "GateDoor%d" % (lane + 1)
		hinge.position = Vector3(front, TURF_Y, lane_z(lane) + LANE_W * 0.5 - 0.02)
		add_child(hinge)
		var door := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.02, 0.26, LANE_W - 0.05)
		door.mesh = bm
		door.material_override = red
		door.position = Vector3(0.0, 0.15, -(LANE_W - 0.05) * 0.5)
		hinge.add_child(door)
		var num := Label3D.new()
		num.text = str(lane + 1)
		num.font = Vfx.font()
		num.font_size = 64
		num.pixel_size = 0.0022
		num.modulate = Palette.CREAM
		num.outline_size = 0
		num.rotation.y = PI * 0.5
		num.position = Vector3(0.012, 0.15, -(LANE_W - 0.05) * 0.5)
		hinge.add_child(num)
		gates.append(hinge)
	# Name plates on the marble at the gate end, one per lane with its colour, read from the stools.
	for lane: int in HorseRaceLogic.HORSES:
		var c := Vector3(-TABLE_L * 0.5 + 0.3, TABLE_TOP + 0.004, lane_z(lane))
		_mesh_box(Vector3(0.46, 0.008, LANE_W - 0.06), c, gold)
		_mesh_box(Vector3(0.06, 0.01, LANE_W - 0.1), c + Vector3(-0.19, 0.002, 0), GreyboxKit.material(LANE_COLORS[lane], 0.0, 0.6))
		var l := Label3D.new()
		l.font = Vfx.font()
		l.font_size = 34
		l.pixel_size = 0.0016
		l.modulate = Palette.CASINO_BLACK
		l.outline_size = 0
		l.width = 240.0
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.rotation.x = -PI * 0.5
		l.position = c + Vector3(0.03, 0.006, 0)
		l.text = str(lane + 1)
		add_child(l)
		plate_labels.append(l)


func _build_finish() -> void:
	# Checkered line across the turf (one textured strip), gold posts either side and an arch.
	var img := Image.create(2, 16, false, Image.FORMAT_RGB8)
	for y: int in 16:
		for x: int in 2:
			img.set_pixel(x, y, Palette.CASINO_BLACK if (x + y) % 2 == 0 else Palette.CREAM)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.roughness = 0.8
	var span: float = TRACK_Z_NEAR - TRACK_Z_FAR
	var mid_z: float = (TRACK_Z_NEAR + TRACK_Z_FAR) * 0.5
	var strip := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(0.08, span)
	strip.mesh = pm
	strip.material_override = mat
	strip.position = Vector3(FINISH_X + 0.04, TURF_Y + 0.003, mid_z)
	add_child(strip)
	var gold: StandardMaterial3D = GreyboxKit.material(Palette.WARM_GOLD, 0.85, 0.3)
	var arch_y: float = TABLE_TOP + 0.62
	for z: float in [TRACK_Z_NEAR + 0.1, TRACK_Z_FAR - 0.1]:
		_mesh_box(Vector3(0.045, arch_y - TABLE_TOP, 0.045), Vector3(FINISH_X, (arch_y + TABLE_TOP) * 0.5, z), gold)
	_mesh_box(Vector3(0.05, 0.12, span + 0.25), Vector3(FINISH_X, arch_y, mid_z), GreyboxKit.material(Palette.CASINO_BLACK, 0.0, 0.5))
	for dy: float in [-0.07, 0.07]:
		_mesh_box(Vector3(0.06, 0.02, span + 0.27), Vector3(FINISH_X, arch_y + dy, mid_z), gold)
	var l := Label3D.new()
	l.text = "FINISH"
	l.font = Vfx.font()
	l.font_size = 48
	l.pixel_size = 0.0024
	l.modulate = Palette.VIP_GOLD
	l.outline_modulate = Palette.CASINO_BLACK
	l.outline_size = 10
	l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y  # reads from every stool
	l.position = Vector3(FINISH_X, arch_y + 0.16, mid_z)
	add_child(l)


## The players' ledge: four numbered betting pads in the lane colours between the glass
## and the stools.
func _build_ledge() -> void:
	for i: int in PAD_XS.size():
		var c: Vector3 = bet_spot(i) - Vector3(0, 0.018, 0)
		_mesh_box(Vector3(0.62, 0.006, 0.34), c, GreyboxKit.material(Palette.WARM_GOLD, 0.8, 0.35))
		_mesh_box(Vector3(0.58, 0.008, 0.3), c + Vector3(0, 0.002, 0), GreyboxKit.material(LANE_COLORS[i].darkened(0.15), 0.0, 0.9))
		var l := Label3D.new()
		l.font = Vfx.font()
		l.text = "%d" % (i + 1)
		l.font_size = 96
		l.pixel_size = 0.0018
		l.modulate = Palette.CASINO_BLACK if i >= 2 else Palette.CREAM
		l.outline_size = 0
		l.rotation.x = -PI * 0.5
		l.position = c + Vector3(0, 0.008, 0)
		add_child(l)


## The tote board behind the track: title, four rows (number, name, place in the race) and a
## status line; marquee bulbs along the top.
func _build_board() -> void:
	var z: float = -1.85
	var y: float = 2.35
	var w: float = 4.9
	var hgt: float = 1.6
	_mesh_box(Vector3(w, hgt, 0.1), Vector3(0, y, z), GreyboxKit.material(Palette.CASINO_BLACK.lightened(0.06), 0.0, 0.6))
	var gold: StandardMaterial3D = GreyboxKit.material(Palette.WARM_GOLD, 0.85, 0.3)
	for dy: float in [-1.0, 1.0]:
		_mesh_box(Vector3(w + 0.12, 0.07, 0.14), Vector3(0, y + dy * (hgt * 0.5 + 0.02), z), gold)
	for dx: float in [-1.0, 1.0]:
		_mesh_box(Vector3(0.07, hgt + 0.1, 0.14), Vector3(dx * (w * 0.5 + 0.02), y, z), gold)
	var bulb_mat := StandardMaterial3D.new()
	bulb_mat.albedo_color = Color(1.0, 0.82, 0.52)
	bulb_mat.emission_enabled = true
	bulb_mat.emission = Color(1.0, 0.82, 0.52)
	bulb_mat.emission_energy_multiplier = 2.6
	bulb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var bulb := SphereMesh.new()
	bulb.radius = 0.035
	bulb.height = 0.07
	bulb.radial_segments = 6
	bulb.rings = 3
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = bulb
	mm.instance_count = 24
	for i: int in mm.instance_count:
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(-w * 0.5 + 0.1 + i * (w - 0.2) / (mm.instance_count - 1), y + hgt * 0.5 + 0.1, z + 0.04)))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Bulbs"
	mmi.multimesh = mm
	mmi.material_override = bulb_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	var title: Label3D = _board_label("THE BEAN DERBY", 88, Vector3(0, y + 0.58, z + 0.06))
	title.modulate = Palette.VIP_GOLD
	for i: int in HorseRaceLogic.HORSES:
		var ry: float = y + 0.28 - i * 0.22
		_mesh_box(Vector3(0.15, 0.15, 0.02), Vector3(-w * 0.5 + 0.35, ry, z + 0.06), GreyboxKit.material(LANE_COLORS[i], 0.0, 0.6))
		board_rows.append(_board_label("%d" % (i + 1), 54, Vector3(-0.35, ry, z + 0.06)))
		board_places.append(_board_label("", 50, Vector3(w * 0.5 - 1.05, ry, z + 0.06)))
		_board_label("1:4", 50, Vector3(w * 0.5 - 0.35, ry, z + 0.06)).modulate = Palette.WARM_GOLD
	board_status = _board_label("", 60, Vector3(0, y - 0.62, z + 0.06))


func _board_label(text: String, size: int, pos: Vector3) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = Vfx.font()
	l.font_size = size
	l.pixel_size = 0.0035
	l.modulate = Palette.CREAM
	l.outline_size = 0
	l.position = pos
	add_child(l)
	return l


func _mesh_box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi


## Runs the race replay every frame (StationBase turns its own processing on and off with the Hot
## marker).
class _Ticker:
	extends Node
	var station: HorseRaceStation

	func _process(delta: float) -> void:
		if station != null:
			station._tick_race(delta)
