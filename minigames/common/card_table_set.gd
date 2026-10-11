class_name CardTableSet
extends Node3D
## The card table set (tech piece C) for the card table minigames (Find the Lady, Forehead Poker):
## a small private card room with an oval green felt table (padded leather rail, wooden apron,
## brass pedestal), a low hanging card-room lamp over it, Lucky the dealer standing behind the
## far rail, and every player's bean on a burgundy chair around the near ends, each with a chip
## stack in their colour and a name tag (the local seat ringed in gold).
##
## `dark` keeps only the lamp (Forehead Poker's dark room); the default adds warm wall sconces and
## a soft fill. The set builds its own camera (`camera`, aimed with `frame`). Purely visual: the
## stages put their cards on `felt_point()` and drive the beans through `set_mood` / `hop`.

const TABLE_TOP: float = 0.92
## Half extents of the felt oval (x across, z towards the camera).
const FELT_RADII: Vector2 = Vector2(1.75, 0.98)
const RAIL_WIDTH: float = 0.2
## Seats sit on this ellipse around the table centre.
const SEAT_RADII: Vector2 = Vector2(2.5, 1.72)
const BEAN_SCALE: float = 0.6
const CHAIR_SEAT_H: float = 0.5
const LAMP_HEIGHT: float = 3.05
const DEALER_Z: float = -1.38
const WARM_LIGHT: Color = Color(1.0, 0.82, 0.58)
## Seat arcs (degrees on the seat ellipse, 90 = nearest the camera, -90 = the dealer): the right
## and the left end of the table; players alternate between them so the front stays open.
const ARC_RIGHT: Vector2 = Vector2(-62.0, 50.0)
const ARC_LEFT: Vector2 = Vector2(130.0, 242.0)

var dark: bool = false
var state: ClientMatchState
var local_id: int = -1
var players: Array[int] = []
var camera: Camera3D
var host: QuizHost
var host_root: Node3D
var lamp: SpotLight3D
## player → {root: Node3D (the chair), bean: AvatarVisuals, puppet: BeanPuppet, tag: Label3D, chips: ChipStack}
var seats: Dictionary[int, Dictionary] = {}
var you_marker: Node3D


## Builds the room, the table, Lucky, the lamp, one seat per player and the camera.
func build(p_state: ClientMatchState, p_local_id: int, p_players: Array[int], p_dark: bool = false) -> void:
	state = p_state
	local_id = p_local_id
	players = p_players.duplicate()
	dark = p_dark
	_build_room()
	_build_table()
	_build_host()
	_build_lights()
	for i: int in players.size():
		_build_seat(players[i], i, players.size())
	camera = Camera3D.new()
	camera.name = "TableCamera"
	camera.fov = 44.0
	camera.far = 60.0  # the casino floor is 400 m away: keep it out
	add_child(camera)
	frame(Vector3(0, 4.25, 4.15), Vector3(0, TABLE_TOP - 0.2, -0.3))


## Points the camera from `eye` at `target` (both in set space).
func frame(eye: Vector3, target: Vector3) -> void:
	camera.transform = Transform3D(Basis.looking_at(target - eye, Vector3.UP), eye)


## A point on the felt surface (set space), `xz` from the table centre.
func felt_point(xz: Vector2, lift: float = 0.0) -> Vector3:
	return Vector3(xz.x, TABLE_TOP + 0.012 + lift, xz.y)


## Where seat `i` of `n` goes: alternating right / left end of the table, spread over each arc.
static func seat_position(i: int, n: int) -> Vector3:
	var right: bool = i % 2 == 0
	var count: int = int(ceil(n / 2.0)) if right else n / 2
	var slot: int = i / 2
	var arc: Vector2 = ARC_RIGHT if right else ARC_LEFT
	var f: float = (float(slot) + 0.5) / float(maxi(count, 1))
	if count == 1:
		f = 0.62  # a lone player sits a little towards the camera
	var deg: float = lerpf(arc.x, arc.y, f) if right else lerpf(arc.y, arc.x, f)
	var a: float = deg_to_rad(deg)
	return Vector3(SEAT_RADII.x * cos(a), 0.0, SEAT_RADII.y * sin(a))


func set_mood(pid: int, mood: BeanPuppet.Mood) -> void:
	if seats.has(pid):
		(seats[pid]["puppet"] as BeanPuppet).set_mood(mood)


func hop(pid: int, height: float = 0.25) -> void:
	if seats.has(pid):
		(seats[pid]["puppet"] as BeanPuppet).hop(height)


## Every bean back to idle.
func calm_all() -> void:
	for pid: int in seats:
		set_mood(pid, BeanPuppet.Mood.IDLE)


## Resizes a seat's chip stack (e.g. to the player's points).
func set_chips(pid: int, amount: int) -> void:
	if not seats.has(pid):
		return
	var seat: Dictionary = seats[pid]
	var old: ChipStack = seat.get("chips", null)
	var pos: Vector3 = old.position if old != null else Vector3.ZERO
	if old != null:
		old.queue_free()
	var stack := ChipStack.make(maxi(amount, 25), _color(pid))
	stack.position = pos
	add_child(stack)
	seat["chips"] = stack


## A seat's screen anchor (above the bean's head), for name chips and bubbles.
func head_point(pid: int) -> Vector3:
	if not seats.has(pid):
		return to_global(Vector3.ZERO)
	return (seats[pid]["root"] as Node3D).to_global(Vector3(0, CHAIR_SEAT_H + 1.25 * BEAN_SCALE + 0.35, 0))


func _color(pid: int) -> Color:
	var idx: int = pid
	if state != null and state.players.has(pid):
		idx = int(state.players[pid].get("color", pid))
	return Palette.player_color(idx)


func _name(pid: int) -> String:
	return state.player_name(pid) if state != null else "Player %d" % pid


# --- Building ----------------------------------------------------------------------------------

func _build_room() -> void:
	# Dark herringbone-ish wooden floor (two tones of planks) under a burgundy rug.
	_box(self, Vector3(16, 0.2, 12), Vector3(0, -0.1, -1.0), Color("#3A2418"))
	for k: int in 14:
		_box(self, Vector3(16, 0.012, 0.04), Vector3(0, 0.006, -6.8 + k * 0.85), Color("#2A190F"))
	var rug := _cyl(self, 1.0, 1.0, 0.02, Vector3(0, 0.012, 0.0), Palette.VIP_BURGUNDY.darkened(0.25))
	rug.scale = Vector3(3.6, 1.0, 2.55)
	var rug_rim := _cyl(self, 1.0, 1.0, 0.016, Vector3(0, 0.01, 0.0), Palette.WARM_GOLD.darkened(0.35))
	rug_rim.scale = Vector3(3.75, 1.0, 2.7)
	if dark:
		return
	# Back wall: burgundy silk above dark wood wainscoting with a gold rail; two framed pictures.
	_box(self, Vector3(16, 6.0, 0.2), Vector3(0, 3.0, -4.2), Palette.VIP_BURGUNDY.darkened(0.3))
	_box(self, Vector3(16, 1.2, 0.26), Vector3(0, 0.6, -4.12), Color("#3B2416"))
	_box(self, Vector3(16, 0.07, 0.3), Vector3(0, 1.22, -4.1), Palette.WARM_GOLD, 0.7)
	for x: float in [-3.4, 3.4]:
		_box(self, Vector3(1.5, 1.05, 0.06), Vector3(x, 2.55, -4.08), Palette.WARM_GOLD.darkened(0.15), 0.6)
		_box(self, Vector3(1.32, 0.87, 0.07), Vector3(x, 2.55, -4.06), Palette.FELT_GREEN.darkened(0.35))
		var suit := Label3D.new()
		suit.text = "♥" if x < 0.0 else "♠"
		suit.font_size = 96
		suit.pixel_size = 0.006
		suit.modulate = Palette.CASINO_RED if x < 0.0 else Palette.CREAM
		suit.position = Vector3(x, 2.55, -4.02)
		add_child(suit)
	# Side walls in shadow, so the room closes around the table.
	for sx: float in [-6.5, 6.5]:
		var wall := _box(self, Vector3(0.2, 6.0, 9.0), Vector3(sx, 3.0, -0.5), Palette.VIP_BURGUNDY.darkened(0.5))
		wall.rotation.y = 0.35 * signf(sx)
	# Wall sconces: brass plate, warm glowing shade.
	for x: float in [-1.7, 1.7]:
		_box(self, Vector3(0.18, 0.3, 0.05), Vector3(x, 2.1, -4.07), Palette.WARM_GOLD, 0.7)
		_cyl(self, 0.07, 0.13, 0.2, Vector3(x, 2.28, -3.95), WARM_LIGHT, 0.0, 10, true)


func _build_table() -> void:
	var table := Node3D.new()
	table.name = "CardTable"
	add_child(table)
	var rx: float = FELT_RADII.x
	var rz: float = FELT_RADII.y
	# Brass pedestal on a wide foot.
	_cyl(table, 0.55, 0.62, 0.08, Vector3(0, 0.04, 0), Palette.WARM_GOLD.darkened(0.25), 0.6)
	_cyl(table, 0.16, 0.22, TABLE_TOP - 0.2, Vector3(0, (TABLE_TOP - 0.2) * 0.5 + 0.06, 0), Palette.WARM_GOLD.darkened(0.2), 0.6)
	# Wooden apron, padded leather rail, the felt and a thin gold betting line.
	var apron := _cyl(table, 1.0, 0.9, 0.16, Vector3(0, TABLE_TOP - 0.1, 0), Color("#4A2C1A"), 0.0, 40)
	apron.scale = Vector3(rx + RAIL_WIDTH, 1.0, rz + RAIL_WIDTH)
	var rail := MeshInstance3D.new()
	rail.name = "Rail"
	rail.mesh = _oval_rail(rx, rz, RAIL_WIDTH, 0.075)
	rail.position.y = TABLE_TOP - 0.01
	rail.material_override = _mat(Color("#2A1A14"))
	(rail.material_override as StandardMaterial3D).roughness = 0.45
	(rail.material_override as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	table.add_child(rail)
	var felt := _cyl(table, 1.0, 1.0, 0.04, Vector3(0, TABLE_TOP - 0.008, 0), Palette.FELT_GREEN, 0.0, 40)
	felt.name = "Felt"
	felt.scale = Vector3(rx, 1.0, rz)
	var line := _cyl(table, 1.0, 1.0, 0.003, Vector3(0, TABLE_TOP + 0.0135, 0), Palette.WARM_GOLD.darkened(0.1), 0.3, 40)
	line.scale = Vector3(rx * 0.86, 1.0, rz * 0.8)
	var inner := _cyl(table, 1.0, 1.0, 0.003, Vector3(0, TABLE_TOP + 0.0145, 0), Palette.FELT_GREEN, 0.0, 40)
	inner.scale = Vector3(rx * 0.86 - 0.025, 1.0, rz * 0.8 - 0.025)
	# The house's chip tray in front of the dealer.
	_box(table, Vector3(0.9, 0.05, 0.2), Vector3(0, TABLE_TOP + 0.02, -rz + 0.12), Color("#2A1A14"))
	for c: int in 5:
		var tray_chips := ChipStack.make(100 * (c + 1))
		tray_chips.position = Vector3(-0.32 + c * 0.16, TABLE_TOP + 0.045, -rz + 0.12)
		table.add_child(tray_chips)


func _build_host() -> void:
	host_root = Node3D.new()
	host_root.name = "Dealer"
	host_root.position = Vector3(0, 0.0, DEALER_Z)
	add_child(host_root)
	host_root.scale = Vector3.ONE * 1.1
	host = QuizHost.new()
	host_root.add_child(host)


func _build_lights() -> void:
	# The card-room lamp: cord, a deep green shade with a brass rim, a hot bulb under it.
	var lamp_root := Node3D.new()
	lamp_root.name = "Lamp"
	lamp_root.position = Vector3(0, LAMP_HEIGHT, 0)
	add_child(lamp_root)
	_cyl(lamp_root, 0.012, 0.012, 3.0, Vector3(0, 1.6, 0), Palette.CASINO_BLACK)
	_cyl(lamp_root, 0.07, 0.62, 0.3, Vector3(0, 0.0, 0), Palette.FELT_GREEN.darkened(0.25), 0.2, 24)
	_cyl(lamp_root, 0.63, 0.63, 0.035, Vector3(0, -0.15, 0), Palette.WARM_GOLD, 0.7, 24)
	_cyl(lamp_root, 0.06, 0.06, 0.06, Vector3(0, 0.17, 0), Palette.WARM_GOLD, 0.7)
	var bulb := _sphere(lamp_root, 0.12, Vector3(0, -0.12, 0), WARM_LIGHT, true)
	bulb.scale = Vector3(1.6, 0.6, 1.6)
	lamp = SpotLight3D.new()
	lamp.name = "LampLight"
	lamp.position = Vector3(0, LAMP_HEIGHT - 0.15, 0)
	lamp.rotation.x = -PI * 0.5
	lamp.spot_range = 6.0
	lamp.spot_angle = 62.0
	lamp.spot_angle_attenuation = 0.6
	lamp.light_energy = 2.6
	lamp.light_color = WARM_LIGHT
	lamp.shadow_enabled = true
	add_child(lamp)
	# A soft warm fill so faces and the dealer don't drown in shadow.
	var fill := OmniLight3D.new()
	fill.name = "Fill"
	fill.position = Vector3(0, 2.4, 2.6)
	fill.omni_range = 7.0
	fill.light_energy = 0.9 if not dark else 0.35
	fill.light_color = WARM_LIGHT
	add_child(fill)
	var dealer_key := SpotLight3D.new()
	dealer_key.position = Vector3(0, 3.2, 0.6)
	dealer_key.spot_range = 6.0
	dealer_key.spot_angle = 18.0
	dealer_key.light_energy = 1.6 if not dark else 0.8
	dealer_key.light_color = WARM_LIGHT
	add_child(dealer_key)
	dealer_key.transform = Transform3D(Basis.looking_at(Vector3(0, 1.5, DEALER_Z) - dealer_key.position, Vector3.UP), dealer_key.position)
	if dark:
		return
	for x: float in [-1.7, 1.7]:
		var sconce := OmniLight3D.new()
		sconce.position = Vector3(x, 2.3, -3.7)
		sconce.omni_range = 3.5
		sconce.light_energy = 1.2
		sconce.light_color = WARM_LIGHT
		add_child(sconce)


func _build_seat(pid: int, i: int, n: int) -> void:
	var pos: Vector3 = seat_position(i, n)
	var seat := Node3D.new()
	seat.name = "Seat%d" % pid
	seat.position = pos
	add_child(seat)
	# Face the table centre (a touch towards the dealer).
	var to_center: Vector3 = Vector3(0, 0, -0.2) - pos
	seat.rotation.y = atan2(to_center.x, to_center.z)
	# Chair: burgundy seat and back on brass legs (the back is behind the bean, away from the table).
	_cyl(seat, 0.03, 0.03, CHAIR_SEAT_H, Vector3(0, CHAIR_SEAT_H * 0.5, 0), Palette.WARM_GOLD.darkened(0.2), 0.6)
	_cyl(seat, 0.24, 0.26, 0.04, Vector3(0, 0.02, 0), Palette.WARM_GOLD.darkened(0.3), 0.6)
	_cyl(seat, 0.3, 0.28, 0.1, Vector3(0, CHAIR_SEAT_H, 0), Palette.VIP_BURGUNDY, 0.0, 16)
	_box(seat, Vector3(0.5, 0.55, 0.08), Vector3(0, CHAIR_SEAT_H + 0.33, -0.3), Palette.VIP_BURGUNDY.darkened(0.1))
	_box(seat, Vector3(0.54, 0.05, 0.1), Vector3(0, CHAIR_SEAT_H + 0.62, -0.3), Palette.WARM_GOLD, 0.7)
	var bean := AvatarVisuals.new()
	bean.name = "Bean"
	bean.scale = Vector3.ONE * BEAN_SCALE
	bean.position = Vector3(0, CHAIR_SEAT_H + 0.05, 0)
	bean.rotation.y = PI  # a bean's face is its -Z: face the table, the chair back behind it
	seat.add_child(bean)
	bean.set_color(_color(pid))
	if state != null:
		bean.set_skin(StringName(state.players.get(pid, {}).get("skin", "bean")))
	var puppet: BeanPuppet = BeanPuppet.attach(bean)
	puppet.cheer_height = 0.18
	var tag := Label3D.new()
	tag.name = "Tag"
	tag.text = _name(pid).left(12)
	tag.font_size = 30
	tag.pixel_size = 0.0058
	tag.outline_size = 8
	tag.outline_modulate = Palette.CASINO_BLACK
	tag.modulate = Palette.VIP_GOLD if pid == local_id else Palette.CREAM.darkened(0.05)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.position = Vector3(0, CHAIR_SEAT_H + 1.3 * BEAN_SCALE + 0.18, 0)
	seat.add_child(tag)
	# Their chip stack on the rail in front of them.
	var rail_pt: Vector3 = Vector3(pos.x * 0.72, TABLE_TOP + 0.05, pos.z * 0.68)
	var chips := ChipStack.make(25, _color(pid))
	chips.position = rail_pt
	add_child(chips)
	seats[pid] = {"root": seat, "bean": bean, "puppet": puppet, "tag": tag, "chips": chips}
	if pid == local_id:
		you_marker = Node3D.new()
		you_marker.name = "YourSeat"
		you_marker.position = pos + Vector3(0, 0.015, 0)
		add_child(you_marker)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.36
		tm.outer_radius = 0.45
		ring.mesh = tm
		ring.scale = Vector3(1, 0.3, 1)
		ring.material_override = _mat(Palette.VIP_GOLD, 0.0, true)
		you_marker.add_child(ring)


## A padded rail around an oval (half extents `rx`, `rz`): a rounded cushion `width` wide and
## `height` tall, starting at the felt's edge.
static func _oval_rail(rx: float, rz: float, width: float, height: float) -> ArrayMesh:
	var profile: Array[Vector2] = [Vector2(-0.01, 0.0), Vector2(0.0, height * 0.55), Vector2(width * 0.2, height * 0.95), Vector2(width * 0.5, height),
		Vector2(width * 0.8, height * 0.92), Vector2(width, height * 0.5), Vector2(width, -0.02)]
	var steps: int = 56
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array = []
	for i: int in steps:
		var a: float = TAU * float(i) / float(steps)
		var edge := Vector3(rx * cos(a), 0.0, rz * sin(a))
		var n := Vector3(cos(a) / rx, 0.0, sin(a) / rz).normalized()
		var ring: Array[Vector3] = []
		for pr: Vector2 in profile:
			ring.append(edge + n * pr.x + Vector3(0, pr.y, 0))
		rings.append(ring)
	for i: int in steps:
		var r0: Array = rings[i]
		var r1: Array = rings[(i + 1) % steps]
		for j: int in profile.size() - 1:
			var a0: Vector3 = r0[j]
			var a1: Vector3 = r0[j + 1]
			var b0: Vector3 = r1[j]
			var b1: Vector3 = r1[j + 1]
			st.add_vertex(a0)
			st.add_vertex(a1)
			st.add_vertex(b1)
			st.add_vertex(a0)
			st.add_vertex(b1)
			st.add_vertex(b0)
	st.generate_normals()
	return st.commit()


# --- Primitives --------------------------------------------------------------------------------

func _mat(c: Color, metallic: float = 0.0, emissive: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metallic
	m.roughness = 0.4 if metallic > 0.0 else 0.85
	if emissive:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 1.4
	return m


func _box(parent: Node, size_m: Vector3, pos: Vector3, c: Color, metallic: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size_m
	mi.mesh = bm
	mi.position = pos
	mi.material_override = _mat(c, metallic)
	parent.add_child(mi)
	return mi


func _cyl(parent: Node, top: float, bottom: float, height: float, pos: Vector3, c: Color, metallic: float = 0.0, segments: int = 16, emissive: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = top
	cm.bottom_radius = bottom
	cm.height = height
	cm.radial_segments = segments
	cm.rings = 1
	mi.mesh = cm
	mi.position = pos
	mi.material_override = _mat(c, metallic, emissive)
	parent.add_child(mi)
	return mi


func _sphere(parent: Node, radius: float, pos: Vector3, c: Color, emissive: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 12
	sm.rings = 6
	mi.mesh = sm
	mi.position = pos
	mi.material_override = _mat(c, 0.0, emissive)
	parent.add_child(mi)
	return mi
