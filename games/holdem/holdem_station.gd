class_name HoldemStation
extends StationBase
## The Casino Hold'em table: an oval poker table in green felt with a padded leather rail on dark
## wood and brass, four stools along the players' (+z) side and the dealer standing on the far
## side by the deck. Each seat has its three printed betting spots (BONUS, ANTE, CALL) and its two
## hole cards in front of them; the five community cards lie across the middle, the dealer's two
## lean in a rack in front of the dealer, face down until the showdown. The hand each seat holds
## (and the dealer's at the showdown) floats over its cards; a seat still deciding is outlined in
## gold. Presentation only: every card and name comes from the server's public state.

## Felt height (cards lie on it) and the oval: a straight middle of 2·HALF_L with round ends.
const TABLE_TOP: float = 0.935
const HALF_L: float = 1.2
const FELT_R: float = 0.78
const RAIL_W: float = 0.14
const RAIL_OUTER: float = FELT_R + RAIL_W
const SEAT_XS: Array[float] = [-1.35, -0.45, 0.45, 1.35]
const SEAT_Z: float = 1.38
## A seat's spots on the felt (z): its hole cards, then its betting row (BONUS · ANTE · CALL).
const CARD_Z: float = 0.2
const BET_Z: float = 0.56
const BET_GAP: float = 0.25
const SPOT_R: float = 0.095
## The community cards: their first spot (middle row) and the step between them.
const BOARD_X: float = -0.5
const BOARD_Z: float = -0.2
const BOARD_STEP: float = 0.25
## Pile keys for `TableCards`: the board (seats are 0..3, the dealer −1).
const BOARD_KEY: int = 20
## The dealer's two cards in their rack, the deck in its tray and the house's chip rack.
const DEALER_SPOT: Vector3 = Vector3(-0.1, TABLE_TOP, -0.6)
const DECK_POS: Vector3 = Vector3(0.78, TABLE_TOP, -0.5)
const HOUSE_SPOT: Vector3 = Vector3(-0.8, TABLE_TOP + 0.05, -0.52)
## Each seat's view (0.9.14 rule, Patrick: "almost the whole screen should be the game"): high over
## the players' side of the felt and right of the middle, so the board, the dealer's cards, the
## seat's own cards and spots fill the left two thirds of the screen (the overlay is a column down
## the right third). Each seat's eye moves `SEAT_EYE_SHIFT` of its stool's x along.
const SEAT_EYE: Vector3 = Vector3(0.3, 1.9, 0.96)
const SEAT_AIM: Vector3 = Vector3(0.5, TABLE_TOP, -0.02)
const SEAT_EYE_SHIFT: float = 0.58
const FELT_COLOR: Color = Color("#1F5A43")
const PRINT_COLOR: Color = Color("#D6A84B")
const RAIL_COLOR: Color = Color("#2B1B16")
const WOOD_COLOR: Color = Color("#3A2A1E")
const ARC_SEGMENTS: int = 14
const HOT_CARD_LIGHT: float = 3.5
const LABEL_HEIGHT: float = 0.06

var cards: TableCards
## Per seat: the hand-name label over its cards (client only).
var hand_labels: Array[Label3D] = []
## The dealer's hand at the showdown ("Pair of Fours" / "DOES NOT QUALIFY").
var dealer_label: Label3D


func _build_visuals() -> void:
	game_id = &"holdem"
	seat_count = SEAT_XS.size()
	interact_radius = 2.8
	hot_center = Vector3(0, 0, 0.3)
	_rug(Vector2(5.8, 4.4), Palette.FELT_GREEN.darkened(0.55))
	# Collision: one box the size of the oval; the table you see is built from parts below.
	var body: Node3D = GreyboxKit.box(self, Vector3(2.0 * (HALF_L + RAIL_OUTER), TABLE_TOP, 2.0 * RAIL_OUTER), Vector3(0, TABLE_TOP * 0.5, 0), WOOD_COLOR, "Body")
	(body.get_node(^"Mesh") as Node3D).visible = false
	_build_table()
	cards = TableCards.new()
	cards.name = "Cards"
	cards.shoe = DECK_POS + Vector3(0, 0.08, 0)
	cards.spots[-1] = [DEALER_SPOT, 0.0]
	cards.spots[BOARD_KEY] = [Vector3(BOARD_X, TABLE_TOP, BOARD_Z), 0.0, BOARD_STEP]
	add_child(cards)
	for i: int in seat_count:
		var pos := Vector3(SEAT_XS[i], 0.0, SEAT_Z)
		_stool(pos, "Stool%d" % i)
		_add_seat(pos + Vector3(0, 0.5, 0), 0.0)
		cards.spots[i] = [card_spot(i), 0.0]
		_add_seat_camera(SEAT_EYE + Vector3(SEAT_XS[i] * SEAT_EYE_SHIFT, 0, 0), SEAT_AIM + Vector3(SEAT_XS[i] * SEAT_EYE_SHIFT, 0, 0))
	camera_anchor = Node3D.new()
	camera_anchor.name = "CameraAnchor"
	camera_anchor.position = SEAT_EYE  # the middle view: the whole felt, left of the overlay
	camera_anchor.rotation = look_rotation(SEAT_EYE, SEAT_AIM)
	add_child(camera_anchor)
	if Vfx.enabled():
		_build_print()
		_build_labels()


## A softer hot-table spotlight: the cards under it must stay readable (no bloom).
func hot_light_energy() -> float:
	return HOT_CARD_LIGHT


func prompt_text(min_bet: int) -> String:
	if out_of_order_left > 0.0:
		return super.prompt_text(min_bet)
	return "%s Play Casino Hold'em — Min $%d" % [InputGlyphs.hint(&"interact"), min_bet]


## Where seat `i`'s hole cards lie (local).
static func card_spot(i: int) -> Vector3:
	return Vector3(SEAT_XS[clampi(i, 0, SEAT_XS.size() - 1)] - 0.05, TABLE_TOP, CARD_Z)


## Where a bet goes on seat `i`'s row (local): the BONUS spot left, ANTE in the middle, CALL right.
static func bet_spot(i: int, type: StringName) -> Vector3:
	var x: float = SEAT_XS[clampi(i, 0, SEAT_XS.size() - 1)]
	match type:
		HoldemLogic.BONUS:
			x -= BET_GAP
		HoldemLogic.CALL_BET:
			x += BET_GAP
	return Vector3(x, TABLE_TOP, BET_Z)


## Where the `index`th community card lies (local).
static func board_spot(index: int) -> Vector3:
	return Vector3(BOARD_X + BOARD_STEP * index, TABLE_TOP, BOARD_Z + TableCards.FAN.z * index)


## Turns the dealer's cards towards the local player's seat (-1 = nobody local is seated here).
func set_viewer_seat(index: int) -> void:
	cards.set_viewer(seat_cameras[index].position if index >= 0 and index < seat_cameras.size() else Vector3.INF)


## A player's hand from the snapshot (keys may arrive as ints or strings).
static func hand_of(hands: Dictionary, pid: int) -> Dictionary:
	for k: Variant in hands:
		if int(k) == pid:
			return hands[k]
	return {}


## Mirrors the public state onto the felt: every seat's hole cards (a folded hand goes to the
## muck), the board, the dealer's two cards (backs until the showdown), the hand names and the
## gold outline round every hand still deciding.
func show_round(pub: Dictionary) -> void:
	var seat_ids: Array = pub.get("seats", [])
	var hands: Dictionary = pub.get("hands", {})
	var deciding: bool = int(pub.get("state", 0)) == HoldemLogic.State.DECIDING
	var by_seat: Dictionary = {}
	var outlined: Array[int] = []
	for i: int in seat_count:
		var pid: int = int(seat_ids[i]) if i < seat_ids.size() else -1
		var h: Dictionary = hand_of(hands, pid) if pid >= 0 else {}
		var folded: bool = StringName(h.get("decision", &"")) == HoldemLogic.FOLD
		if not h.is_empty() and not folded:
			by_seat[i] = h.get("hole", [])
			if deciding and StringName(h.get("decision", &"")) == &"":
				outlined.append(i)
		_show_hand_label(i, h)
	by_seat[BOARD_KEY] = pub.get("board", [])
	var dealer: Array = (pub.get("dealer", []) as Array).duplicate()
	for k: int in int(pub.get("dealer_down", 0)):
		dealer.append(TableCards.FACE_DOWN)
	cards.set_outlined(outlined)
	cards.show_cards(by_seat, dealer)
	_show_dealer_label(pub)


## The table was cleared for a minigame.
func reset_table() -> void:
	cards.show_cards({}, [])
	for i: int in seat_count:
		_show_hand_label(i, {})
	if dealer_label != null:
		dealer_label.visible = false


## "Pair of Kings" over a seat's cards while it plays, "FOLD" once folded, and at the showdown its
## hand with the result.
func _show_hand_label(i: int, h: Dictionary) -> void:
	if i >= hand_labels.size():
		return
	var l: Label3D = hand_labels[i]
	if h.is_empty() or (h.get("hole", []) as Array).is_empty():
		l.visible = false
		return
	l.visible = true
	var outcome: StringName = StringName(h.get("outcome", &""))
	if StringName(h.get("decision", &"")) == HoldemLogic.FOLD:
		outcome = &"fold"
	l.text = String(h.get("hand", ""))
	l.modulate = Palette.CREAM
	match outcome:
		&"fold":
			l.text = "FOLD"
			l.modulate = Color(Palette.CREAM, 0.6)
		&"win", &"no_qualify":
			l.modulate = Palette.MONEY_GREEN
		&"lose":
			l.modulate = Palette.LOSS_RED
		&"push":
			l.text += "  ·  PUSH"


func _show_dealer_label(pub: Dictionary) -> void:
	if dealer_label == null:
		return
	dealer_label.visible = pub.has("dealer_hand")
	if not dealer_label.visible:
		return
	var qualifies: bool = bool(pub.get("qualifies", false))
	dealer_label.text = String(pub["dealer_hand"]) + ("" if qualifies else "\nDOES NOT QUALIFY")
	dealer_label.modulate = Palette.CREAM if qualifies else Palette.WARM_GOLD


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
		var foot: Node3D = GreyboxKit.box(self, Vector3(2.0 * HALF_L, 0.04, 0.05), Vector3(0, 0.22, side * 0.66), Palette.WARM_GOLD, "FootRail%s" % ("N" if side < 0.0 else "S"), false)
		(foot.get_node(^"Mesh") as MeshInstance3D).material_override = GreyboxKit.gold()
	for end: float in [-1.0, 1.0]:
		var c := Vector3(end * HALF_L, 0.0, 0.0)
		for i: int in ARC_SEGMENTS:
			var a0: float = -PI * 0.5 + PI * i / ARC_SEGMENTS
			var a1: float = -PI * 0.5 + PI * (i + 1) / ARC_SEGMENTS
			_arc_piece(c, end, a0, a1, FELT_R + RAIL_W * 0.5, RAIL_W, 0.07, top + 0.015, RAIL_COLOR, "RailEnd%d" % i)
			_arc_piece(c, end, a0, a1, RAIL_OUTER - 0.02, 0.05, 0.14, top - 0.07, WOOD_COLOR, "ApronEnd%d" % i)
			_arc_piece(c, end, a0, a1, 0.66, 0.05, 0.04, 0.22, Palette.WARM_GOLD, "FootEnd%d" % i, true)
	# Four turned legs with brass collars and feet.
	var leg_h: float = top - 0.14
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var lp := Vector3(sx * (HALF_L + 0.25), leg_h * 0.5, sz * 0.45)
			var tag: String = "Leg%s%s" % ["L" if sx < 0.0 else "R", "N" if sz < 0.0 else "S"]
			GreyboxKit.cylinder(self, 0.07, leg_h, lp, WOOD_COLOR, tag, false)
			GreyboxKit.cylinder(self, 0.085, 0.04, Vector3(lp.x, 0.22, lp.z), Palette.WARM_GOLD, tag + "Brass", false, 0.8)
			GreyboxKit.cylinder(self, 0.1, 0.03, Vector3(lp.x, 0.015, lp.z), Palette.WARM_GOLD, tag + "Foot", false, 0.8)
	# The dealer's side: the deck in a wooden tray and the chip rack.
	GreyboxKit.box(self, Vector3(0.3, 0.04, 0.36), DECK_POS + Vector3(0, 0.02, 0), WOOD_COLOR, "DeckTray", false)
	GreyboxKit.box(self, Vector3(0.2, 0.06, 0.28), DECK_POS + Vector3(0, 0.07, 0), TableCards.BACK_TINT.darkened(0.15), "Deck", false)
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


## The gold print on the felt, read from the players' side: the game's name and the dealer's rule
## by the board, the five card frames, and every seat's three betting spots.
func _build_print() -> void:
	_felt_text("CASINO HOLD'EM", Vector3(0.0, TABLE_TOP + 0.002, -0.47), 64, 0.0019, "PrintName")
	_felt_text("DEALER QUALIFIES WITH A PAIR OF 4s OR BETTER  ·  AA BONUS PAYS ON THE FLOP", Vector3(0.0, TABLE_TOP + 0.002, 0.02), 30, 0.0016, "PrintRules")
	var frame_mat: StandardMaterial3D = GreyboxKit.material(Color(PRINT_COLOR, 1.0), 0.0, 0.8)
	for k: int in 5:
		var f := MeshInstance3D.new()
		f.name = "BoardFrame%d" % k
		var box := BoxMesh.new()
		box.size = Vector3(TableCards.CARD_SIZE.x + 0.02, 0.002, TableCards.CARD_SIZE.y * cos(TableCards.HAND_TILT) + 0.02)
		f.mesh = box
		f.material_override = GreyboxKit.material(FELT_COLOR.darkened(0.25), 0.0, 0.9)
		f.position = board_spot(k) + Vector3(0, 0.0008, 0)
		add_child(f)
	for i: int in seat_count:
		for type: StringName in [HoldemLogic.BONUS, HoldemLogic.ANTE, HoldemLogic.CALL_BET]:
			var spot: Vector3 = bet_spot(i, type)
			var ring := MeshInstance3D.new()
			ring.name = "Spot%d%s" % [i, String(type).capitalize()]
			var torus := TorusMesh.new()
			torus.inner_radius = SPOT_R - 0.012
			torus.outer_radius = SPOT_R
			torus.rings = 24
			ring.mesh = torus
			ring.material_override = frame_mat
			ring.scale = Vector3(1.0, 0.08, 1.0)
			ring.position = spot + Vector3(0, 0.002, 0)
			add_child(ring)
			var word: String = "AA BONUS" if type == HoldemLogic.BONUS else String(type).to_upper()
			_felt_text(word, spot + Vector3(0, 0.002, SPOT_R + 0.035), 26, 0.0013, "SpotLabel%d%s" % [i, String(type).capitalize()])


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


func _build_labels() -> void:
	for i: int in seat_count:
		var l := _float_label("HandName%d" % i, 40)
		l.position = card_spot(i) + Vector3(0.05, LABEL_HEIGHT, -0.12)  # the far edge of the cards, short of the board
		hand_labels.append(l)
	dealer_label = _float_label("DealerHand", 44)
	dealer_label.position = DEALER_SPOT + Vector3(0.1, 0.62, 0.0)


func _float_label(node_name: String, size: int) -> Label3D:
	var l := Label3D.new()
	l.name = node_name
	l.font = Vfx.font()
	l.font_size = size
	l.pixel_size = 0.0021
	l.outline_size = 14
	l.modulate = Palette.CREAM
	l.outline_modulate = Palette.CASINO_BLACK
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.visible = false
	add_child(l)
	return l
