class_name HiLoStation
extends StationBase
## The Hi-Lo table: an oval card table with burgundy felt, a padded leather rail on dark wood and
## brass, four stools along the players' (+z) side and the dealer standing on the far side by the
## deck. Each seat has its own spot on the felt where its hand's run of cards is dealt (the last
## card is the one up), a printed six-step ladder that lights up with every right call, and the
## pot on a little brass card behind the cards. "HI · LO" and the house rules are printed in gold.
## Presentation only: every card and number comes from the server's public state.

## Felt height (cards lie on it) and the oval: a straight middle of 2·HALF_L with round ends.
const TABLE_TOP: float = 0.935
const HALF_L: float = 1.2
const FELT_R: float = 0.72
const RAIL_W: float = 0.14
const RAIL_OUTER: float = FELT_R + RAIL_W
const SEAT_XS: Array[float] = [-1.35, -0.45, 0.45, 1.35]
const SEAT_Z: float = 1.32
## A seat's spots on the felt (z): its cards, its ladder, its ante.
const CARD_Z: float = 0.2
const LADDER_Z: float = 0.43
const BET_Z: float = 0.58
## The single deck in its tray on the dealer's side, the dealer's chip rack (lost antes go here);
## the name is printed between them.
const DECK_POS: Vector3 = Vector3(0.62, TABLE_TOP, -0.42)
const HOUSE_SPOT: Vector3 = Vector3(-0.62, TABLE_TOP + 0.05, -0.45)
const LADDER_STEPS: int = 6
const LADDER_GAP: float = 0.1
## Seated eye: how far it leans in from the stool, its height, its pitch, and where it looks.
const SEAT_EYE_LEAN: float = 0.45
const SEAT_EYE_HEIGHT: float = 1.5
const SEAT_EYE_PITCH: float = deg_to_rad(-30.0)
const SEAT_LOOK_Z: float = 0.05
const FELT_COLOR: Color = Color("#4E1622")
const PRINT_COLOR: Color = Color("#D6A84B")
const RAIL_COLOR: Color = Color("#2B1B16")
const WOOD_COLOR: Color = Color("#3A2A1E")
const ARC_SEGMENTS: int = 14
const HOT_CARD_LIGHT: float = 3.5

var cards: TableCards
## Per seat: the ladder's step lamps (client only) and the pot card's label.
var ladder_lamps: Array[Array] = []
var pot_labels: Array[Label3D] = []
## The deck in its tray; it thins as the deck is dealt (scale on y).
var deck_stack: Node3D
var _lamp_on: StandardMaterial3D
var _lamp_off: StandardMaterial3D


func _build_visuals() -> void:
	game_id = &"hilo"
	seat_count = SEAT_XS.size()
	interact_radius = 2.8
	hot_center = Vector3(0, 0, 0.3)
	_rug(Vector2(5.8, 4.2), Palette.VIP_BURGUNDY.darkened(0.5))
	# Collision: one box the size of the oval; the table you see is built from parts below.
	var body: Node3D = GreyboxKit.box(self, Vector3(2.0 * (HALF_L + RAIL_OUTER), TABLE_TOP, 2.0 * RAIL_OUTER), Vector3(0, TABLE_TOP * 0.5, 0), WOOD_COLOR, "Body")
	(body.get_node(^"Mesh") as Node3D).visible = false
	_build_table()
	cards = TableCards.new()
	cards.name = "Cards"
	cards.shoe = DECK_POS + Vector3(0, 0.08, 0)
	add_child(cards)
	cards.dealer_rack.visible = false  # no dealer hand at this table
	for i: int in seat_count:
		var pos := Vector3(SEAT_XS[i], 0.0, SEAT_Z)
		_stool(pos, "Stool%d" % i)
		_add_seat(pos + Vector3(0, 0.5, 0), 0.0)
		cards.spots[i] = [card_spot(i), 0.0]
		var eye := Node3D.new()
		eye.name = "SeatCamera%d" % i
		eye.position = Vector3(SEAT_XS[i], SEAT_EYE_HEIGHT, SEAT_Z - SEAT_EYE_LEAN)
		var look: Vector3 = Vector3(SEAT_XS[i] * 0.9, 0.0, SEAT_LOOK_Z) - eye.position
		eye.rotation = Vector3(SEAT_EYE_PITCH, atan2(-look.x, -look.z), 0.0)
		add_child(eye)
		seat_cameras.append(eye)
	camera_anchor = Node3D.new()
	camera_anchor.name = "CameraAnchor"
	camera_anchor.position = Vector3(0, 1.6, 2.5)
	camera_anchor.rotation.x = deg_to_rad(-27.0)
	add_child(camera_anchor)
	if Vfx.enabled():
		_build_print()
		_build_seat_marks()


## A softer hot-table spotlight: the cards under it must stay readable (no bloom).
func hot_light_energy() -> float:
	return HOT_CARD_LIGHT


func prompt_text(min_bet: int) -> String:
	if out_of_order_left > 0.0:
		return super.prompt_text(min_bet)
	return "%s Play Hi-Lo — Min $%d" % [InputGlyphs.hint(&"interact"), min_bet]


## Where seat `i`'s cards lie (local).
static func card_spot(i: int) -> Vector3:
	return Vector3(SEAT_XS[clampi(i, 0, SEAT_XS.size() - 1)] - 0.12, TABLE_TOP, CARD_Z)


## Where seat `i`'s ante goes (local).
static func bet_spot(i: int) -> Vector3:
	return Vector3(SEAT_XS[clampi(i, 0, SEAT_XS.size() - 1)], TABLE_TOP, BET_Z)


## Mirrors the public state onto the felt: every seated hand's run of cards, its ladder and pot,
## and how thick the deck still is.
func show_round(pub: Dictionary) -> void:
	var seat_ids: Array = pub.get("seats", [])
	var hands: Dictionary = pub.get("hands", {})
	var by_seat: Dictionary = {}
	for i: int in seat_ids.size():
		var pid: int = int(seat_ids[i])
		var h: Dictionary = hand_of(hands, pid) if pid >= 0 else {}
		if not h.is_empty():
			by_seat[i] = h.get("cards", [])
		_show_seat(i, h)
	cards.show_cards(by_seat, [])
	if deck_stack != null:
		deck_stack.scale.y = clampf(float(pub.get("deck_left", 52)) / 52.0, 0.05, 1.0)


## The table was cleared for a minigame.
func reset_table() -> void:
	cards.show_cards({}, [])
	for i: int in seat_count:
		_show_seat(i, {})


## A player's hand from the snapshot (keys may arrive as ints or strings).
static func hand_of(hands: Dictionary, pid: int) -> Dictionary:
	for k: Variant in hands:
		if int(k) == pid:
			return hands[k]
	return {}


## Lights `rung` steps of a seat's ladder and shows its pot (nothing while the seat has no hand).
func _show_seat(i: int, h: Dictionary) -> void:
	if i >= ladder_lamps.size():
		return
	var rung: int = int(h.get("rung", 0))
	var lamps: Array = ladder_lamps[i]
	for s: int in lamps.size():
		(lamps[s] as MeshInstance3D).material_override = _lamp_on if s < rung else _lamp_off
	var label: Label3D = pot_labels[i]
	if h.is_empty():
		label.text = ""
		return
	var outcome: StringName = StringName(h.get("outcome", &""))
	if outcome == &"lose":
		label.text = "LOST"
		label.modulate = Palette.LOSS_RED
	elif outcome == &"cashed":
		label.text = "+$%d" % int(h.get("pot", 0))
		label.modulate = Palette.MONEY_GREEN
	else:
		label.text = "$%d" % int(h.get("pot", h.get("stake", 0)))
		label.modulate = Palette.VIP_GOLD


# --- The table ----------------------------------------------------------------------------------


func _build_table() -> void:
	var top: float = TABLE_TOP
	_oval(self, FELT_R, top, GreyboxKit.material(FELT_COLOR, 0.0, 0.85), "Felt")
	_oval(self, RAIL_OUTER + 0.02, top - 0.14, GreyboxKit.material(WOOD_COLOR), "Underside")
	# The padded rail, the wooden apron under it and a brass foot ring, around the whole oval.
	for side: float in [-1.0, 1.0]:
		var z: float = side * (FELT_R + RAIL_W * 0.5)
		GreyboxKit.box(self, Vector3(2.0 * HALF_L, 0.07, RAIL_W), Vector3(0, top + 0.015, z), RAIL_COLOR, "Rail%s" % ("N" if side < 0.0 else "S"), false)
		GreyboxKit.box(self, Vector3(2.0 * HALF_L, 0.14, 0.05), Vector3(0, top - 0.07, side * (RAIL_OUTER - 0.02)), WOOD_COLOR, "Apron%s" % ("N" if side < 0.0 else "S"), false)
		var foot: Node3D = GreyboxKit.box(self, Vector3(2.0 * HALF_L, 0.04, 0.05), Vector3(0, 0.22, side * 0.62), Palette.WARM_GOLD, "FootRail%s" % ("N" if side < 0.0 else "S"), false)
		(foot.get_node(^"Mesh") as MeshInstance3D).material_override = GreyboxKit.gold()
	for end: float in [-1.0, 1.0]:
		var c := Vector3(end * HALF_L, 0.0, 0.0)
		for i: int in ARC_SEGMENTS:
			var a0: float = -PI * 0.5 + PI * i / ARC_SEGMENTS
			var a1: float = -PI * 0.5 + PI * (i + 1) / ARC_SEGMENTS
			_arc_piece(c, end, a0, a1, FELT_R + RAIL_W * 0.5, RAIL_W, 0.07, top + 0.015, RAIL_COLOR, "RailEnd%d" % i)
			_arc_piece(c, end, a0, a1, RAIL_OUTER - 0.02, 0.05, 0.14, top - 0.07, WOOD_COLOR, "ApronEnd%d" % i)
			_arc_piece(c, end, a0, a1, 0.62, 0.05, 0.04, 0.22, Palette.WARM_GOLD, "FootEnd%d" % i, true)
	# Four turned legs with brass collars and feet.
	var leg_h: float = top - 0.14
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var lp := Vector3(sx * (HALF_L + 0.25), leg_h * 0.5, sz * 0.42)
			var tag: String = "Leg%s%s" % ["L" if sx < 0.0 else "R", "N" if sz < 0.0 else "S"]
			GreyboxKit.cylinder(self, 0.07, leg_h, lp, WOOD_COLOR, tag, false)
			GreyboxKit.cylinder(self, 0.085, 0.04, Vector3(lp.x, 0.22, lp.z), Palette.WARM_GOLD, tag + "Brass", false, 0.8)
			GreyboxKit.cylinder(self, 0.1, 0.03, Vector3(lp.x, 0.015, lp.z), Palette.WARM_GOLD, tag + "Foot", false, 0.8)
	# The dealer's side: the deck in a wooden tray and the chip rack.
	GreyboxKit.box(self, Vector3(0.3, 0.04, 0.36), DECK_POS + Vector3(0, 0.02, 0), WOOD_COLOR, "DeckTray", false)
	deck_stack = Node3D.new()
	deck_stack.name = "Deck"
	deck_stack.position = DECK_POS + Vector3(0, 0.04, 0)
	add_child(deck_stack)
	GreyboxKit.box(deck_stack, Vector3(0.2, 0.06, 0.28), Vector3(0, 0.03, 0), TableCards.BACK_TINT.darkened(0.15), "Stack", false)
	GreyboxKit.box(self, Vector3(0.62, 0.08, 0.2), HOUSE_SPOT + Vector3(0, -0.01, 0), Color("#1E1B19"), "ChipRack", false)
	var chip_colors: Array[Color] = [Palette.CASINO_RED, Palette.CREAM, Palette.FELT_GREEN, Palette.WARM_GOLD, Palette.CASINO_BLACK]
	for k: int in chip_colors.size():
		var roll: Node3D = GreyboxKit.cylinder(self, 0.03, 0.16, HOUSE_SPOT + Vector3(-0.24 + k * 0.12, 0.05, 0), chip_colors[k], "RackChips%d" % k, false)
		roll.rotation.x = PI * 0.5  # a roll of chips lying in its slot, pointing at the players


## Flat oval (straight middle, round ends) at height `y`, double sided.
func _oval(parent: Node3D, radius: float, y: float, mat: StandardMaterial3D, node_name: String) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var ring: Array[Vector3] = []
	for end: float in [1.0, -1.0]:
		for i: int in ARC_SEGMENTS + 1:
			var a: float = -PI * 0.5 + PI * i / ARC_SEGMENTS
			ring.append(Vector3(end * (HALF_L + cos(a) * radius), y, end * sin(a) * radius))
	var centre := Vector3(0, y, 0)
	for i: int in ring.size():
		st.add_vertex(centre)
		st.add_vertex(ring[i])
		st.add_vertex(ring[(i + 1) % ring.size()])
	var m: StandardMaterial3D = mat.duplicate() as StandardMaterial3D
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = st.commit()
	mi.material_override = m
	parent.add_child(mi)


## One box on a round end (centre `c`, `end` −1 west / +1 east) between angles a0 and a1, at
## radius `r`, `thick` radially and `h` tall, centred at height `y`. Visual only.
func _arc_piece(c: Vector3, end: float, a0: float, a1: float, r: float, thick: float, h: float, y: float, color: Color, node_name: String, brass: bool = false) -> void:
	var am: float = (a0 + a1) * 0.5
	var length: float = 2.0 * r * sin((a1 - a0) * 0.5) * 1.04
	var dir := Vector3(end * cos(am), 0.0, end * sin(am))
	var node: Node3D = GreyboxKit.box(self, Vector3(thick, h, length), c + dir * r + Vector3(0, y, 0), color, node_name, false)
	node.rotation.y = atan2(-dir.z, dir.x)  # local +x points away from the centre
	if brass:
		(node.get_node(^"Mesh") as MeshInstance3D).material_override = GreyboxKit.gold()


## The gold print on the felt: the game's name and the house rules, read from the players' side.
func _build_print() -> void:
	_felt_text("HI · LO", Vector3(0.08, TABLE_TOP + 0.002, -0.42), 80, 0.002, "PrintName")
	_felt_text("ACES HIGH  ·  A TIE LOSES  ·  RIDE OR CASH OUT", Vector3(0.0, TABLE_TOP + 0.002, -0.17), 36, 0.0019, "PrintRules")


func _felt_text(text: String, pos: Vector3, size: int, pixel: float, node_name: String) -> Label3D:
	var l := Label3D.new()
	l.name = node_name
	l.text = text
	l.font = Vfx.font()
	l.font_size = size
	l.pixel_size = pixel
	l.outline_size = 0
	l.modulate = Color(PRINT_COLOR, 0.85)
	l.shaded = true
	l.double_sided = false
	l.position = pos
	l.rotation.x = -PI * 0.5  # flat on the felt, upright for the players
	add_child(l)
	return l


## Per seat: a gold ring for the ante, the six ladder steps and the pot card behind the cards.
func _build_seat_marks() -> void:
	_lamp_on = GreyboxKit.gold()
	_lamp_on.emission_enabled = true
	_lamp_on.emission = Palette.VIP_GOLD
	_lamp_on.emission_energy_multiplier = 0.6
	_lamp_off = GreyboxKit.material(FELT_COLOR.darkened(0.35), 0.0, 0.9)
	var ring_mat: StandardMaterial3D = GreyboxKit.material(PRINT_COLOR, 0.0, 0.8)
	for i: int in seat_count:
		var x: float = SEAT_XS[i]
		var ring := MeshInstance3D.new()
		ring.name = "AnteRing%d" % i
		var torus := TorusMesh.new()
		torus.inner_radius = 0.085
		torus.outer_radius = 0.1
		torus.rings = 24
		ring.mesh = torus
		ring.material_override = ring_mat
		ring.scale = Vector3(1.0, 0.08, 1.0)
		ring.position = Vector3(x, TABLE_TOP + 0.002, BET_Z)
		add_child(ring)
		var lamps: Array = []
		for s: int in LADDER_STEPS:
			var lamp := MeshInstance3D.new()
			lamp.name = "Ladder%d_%d" % [i, s]
			var disc := CylinderMesh.new()
			disc.top_radius = 0.03
			disc.bottom_radius = 0.03
			disc.height = 0.008
			disc.radial_segments = 12
			lamp.mesh = disc
			lamp.material_override = _lamp_off
			lamp.position = Vector3(x - LADDER_GAP * (LADDER_STEPS - 1) * 0.5 + LADDER_GAP * s, TABLE_TOP + 0.004, LADDER_Z)
			add_child(lamp)
			lamps.append(lamp)
		ladder_lamps.append(lamps)
		var pot := Label3D.new()
		pot.name = "Pot%d" % i
		pot.font = Vfx.font()
		pot.font_size = 56
		pot.pixel_size = 0.0017
		pot.outline_size = 12
		pot.modulate = Palette.VIP_GOLD
		pot.outline_modulate = Palette.CASINO_BLACK
		pot.position = Vector3(x + 0.2, TABLE_TOP + 0.36, CARD_Z - 0.05)
		pot.rotation.x = deg_to_rad(-20.0)
		add_child(pot)
		pot_labels.append(pot)
