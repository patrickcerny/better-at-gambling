class_name BlackjackStation
extends StationBase
## Half-moon blackjack table (Patrick's model, flat casino colors since its textures did not come
## along): green felt, padded rail, gold legs, 4 seats on the curved side, dealer on the straight one.


func _build_visuals() -> void:
	game_id = &"blackjack"
	seat_count = 4
	_round_rug(4.8)
	# Collision stays a simple cylinder; Patrick's half-moon table model is what you see.
	var rim: Node3D = GreyboxKit.cylinder(self, 1.7, 0.9, Vector3(0, 0.45, 0), Color("#3A2A1E"), "Rim")
	(rim.get_node(^"Mesh") as Node3D).visible = false
	_add_table_model()
	# Dealer spot (north side, the straight edge), chip rack.
	GreyboxKit.box(self, Vector3(0.7, 0.08, 0.22), Vector3(0.75, 0.96, -0.22), Color("#1E1B19"), "ChipRack", false)
	GreyboxKit.box(self, Vector3(0.2, 0.12, 0.3), Vector3(-0.8, 0.98, -0.2), Color("#1E1B19"), "Shoe", false)
	cards = TableCards.new()
	cards.name = "Cards"
	cards.shoe = Vector3(-0.8, 1.06, -0.2)
	cards.spots[-1] = [Vector3(-0.1, TABLE_TOP, 0.05), 0.0]
	add_child(cards)
	for i: int in seat_count:
		var angle: float = deg_to_rad(-45.0 + 30.0 * i)  # fan on the south side
		var pos: Vector3 = Vector3(sin(angle) * 2.2, 0.0, cos(angle) * 2.2)
		_stool(pos, "Stool%d" % i)
		_add_seat(pos + Vector3(0, 0.5, 0), angle)  # yaw = angle looks at the table centre
		# Your cards land on the felt in front of you; your camera sits at your own stool.
		var to_seat: Vector3 = (pos - ARC_CENTRE).normalized()
		var at: Vector3 = ARC_CENTRE + to_seat * CARD_RADIUS + Vector3(0, TABLE_TOP, 0)
		var side: Vector3 = Basis(Vector3.UP, angle) * Vector3(SPLIT_SPREAD, 0.0, 0.0)
		# One hand in the middle; after a split two hands side by side (first left, second right),
		# their fans a little tighter so they never run into each other.
		hand_spots.append([[at, angle], [at - side, angle, SPLIT_FAN], [at + side, angle, SPLIT_FAN]])
		cards.spots[i] = hand_spots[i][0]
		cards.spots[i + SPLIT_KEY] = hand_spots[i][2]
		var eye := Node3D.new()
		eye.name = "SeatCamera%d" % i
		# Leaning in over the rail: your own cards low in view, the dealer's rack above them.
		eye.position = pos - to_seat * SEAT_EYE_LEAN + Vector3(0, SEAT_EYE_HEIGHT, 0)
		var look: Vector3 = SEAT_LOOK_AT - eye.position
		eye.rotation = Vector3(SEAT_EYE_PITCH, atan2(-look.x, -look.z), 0.0)
		add_child(eye)
		seat_cameras.append(eye)
	camera_anchor = Node3D.new()
	camera_anchor.name = "CameraAnchor"
	camera_anchor.position = Vector3(0, 1.45, 2.3)
	camera_anchor.rotation.x = deg_to_rad(-25.0)
	add_child(camera_anchor)


## Card height on the felt and the centre of the half-moon's arc.
const TABLE_TOP: float = 0.935
const ARC_CENTRE: Vector3 = Vector3(0, 0, -0.4)
## Where a seat's cards and bet stack sit, measured from the arc centre: cards first, the chips
## in front of them, both clear of the felt edge (1.6). The chips used to sit at 1.6, right under
## the padded rail, so the bet showed inside it.
const CARD_RADIUS: float = 1.2
const BET_RADIUS: float = 1.45
## Card-spot key offset for a seat's second (split) hand. After a split the two hands sit
## SPLIT_SPREAD either side of the seat's card spot (seat-local x) with a tighter fan, and the
## bets sit in front of them.
const SPLIT_KEY: int = 10
const SPLIT_SPREAD: float = 0.16
const SPLIT_FAN: float = 0.06
## Seated eye: how far it leans in from the stool towards the table, its height and its pitch.
const SEAT_EYE_LEAN: float = 0.5
const SEAT_EYE_HEIGHT: float = 1.5
const SEAT_EYE_PITCH: float = deg_to_rad(-26.0)
## Every seat's view is turned towards this point (between the dealer's rack and the hands).
const SEAT_LOOK_AT: Vector3 = Vector3(0.0, 0.0, 0.2)

var cards: TableCards
## Per seat: the card spots [single hand, split hand 1, split hand 2] (TableCards spot arrays).
var hand_spots: Array[Array] = []
## After a split, per hand pile key: its value tag over the cards, and per seat the
## "HAND 1" / "HAND 2" marker over the hand being played (client only, built on first use).
var hand_tags: Dictionary[int, Label3D] = {}
var hand_markers: Dictionary[int, Label3D] = {}
const TAG_HEIGHT: float = 0.19
const MARKER_HEIGHT: float = 0.28
const HOT_CARD_LIGHT: float = 3.5
## The dealer's face-up total, floating over the dealer's cards (client only; built on first use).
var dealer_total_label: Label3D
## Where that number floats: above the dealer's card spot, under the dealer's head.
const DEALER_TOTAL_POS: Vector3 = Vector3(-0.1, TABLE_TOP + 0.5, 0.05)


## A softer hot-table spotlight: the cards under it must stay readable (no bloom).
func hot_light_energy() -> float:
	return HOT_CARD_LIGHT


## Turns the dealer's cards towards the local player's seat (-1 = nobody local is seated here).
func set_viewer_seat(index: int) -> void:
	cards.set_viewer(seat_cameras[index].position if index >= 0 and index < seat_cameras.size() else Vector3.INF)


## Mirrors the round onto the felt (see `TableCards`). After a split the seat shows two hands
## side by side, each with its value tag; the one being played (the server's `active`) is
## outlined in gold with a "HAND n" marker over it, for everyone at the table.
func show_round(pub: Dictionary) -> void:
	var seat_ids: Array = pub.get("seats", [])
	var hands: Dictionary = pub.get("hands", {})
	var acting: bool = int(pub.get("state", 0)) == BlackjackLogic.State.ACTING
	var by_seat: Dictionary = {}
	var outlined: Array[int] = []
	var split_seats: Dictionary[int, Dictionary] = {}
	for i: int in seat_ids.size():
		var pid: int = int(seat_ids[i])
		var h: Dictionary = {}
		if pid >= 0:
			for k: Variant in hands:
				if int(k) == pid:
					h = hands[k]
		var split: bool = h.has("split")
		if i < hand_spots.size():
			cards.move_pile(i, hand_spots[i][1] if split else hand_spots[i][0])
		if h.is_empty():
			continue
		by_seat[i] = h.get("cards", [])
		if split:
			var second: Array = (h["split"] as Dictionary).get("cards", [])
			if not second.is_empty():
				cards.split_pile(i, i + SPLIT_KEY, int(second[0]))
			by_seat[i + SPLIT_KEY] = second
			split_seats[i] = h
			if acting and not bool(h.get("done", true)):
				outlined.append(i + SPLIT_KEY if int(h.get("active", 0)) == 1 else i)
	var dealer: Array = (pub.get("dealer", []) as Array).duplicate()
	_show_dealer_total(dealer)
	if not bool(pub.get("dealer_revealed", false)) and dealer.size() == 1 and acting:
		dealer.append(TableCards.FACE_DOWN)
	cards.set_outlined(outlined)
	cards.show_cards(by_seat, dealer)
	_show_hand_tags(split_seats, outlined)


## Value tags over both hands of every split seat, and the "HAND n" marker over the one being
## played (`outlined` holds its pile key); everything else hidden.
func _show_hand_tags(split_seats: Dictionary[int, Dictionary], outlined: Array[int]) -> void:
	if not Vfx.enabled():
		return
	for i: int in hand_spots.size():
		var split: bool = split_seats.has(i)
		for hand: int in 2:
			var key: int = i + hand * SPLIT_KEY
			var tag: Label3D = hand_tags.get(key, null)
			if not split:
				if tag != null:
					tag.visible = false
				continue
			if tag == null:
				tag = _hand_label("HandTag%d" % key, 36, Palette.CREAM)
				hand_tags[key] = tag
			var h: Dictionary = split_seats[i] if hand == 0 else split_seats[i]["split"]
			var total: int = HandEval.total(_ints(h.get("cards", [])))
			tag.text = ("%d  BUST" % total) if total > 21 else str(total)
			tag.modulate = Palette.VIP_GOLD if outlined.has(key) else Palette.CREAM
			tag.position = _over_hand(key, TAG_HEIGHT)
			tag.visible = total > 0
		var playing: int = -1
		for hand: int in 2:
			if outlined.has(i + hand * SPLIT_KEY):
				playing = hand
		var marker: Label3D = hand_markers.get(i, null)
		if playing < 0:
			if marker != null:
				marker.visible = false
			continue
		if marker == null:
			marker = _hand_label("HandMarker%d" % i, 30, Palette.VIP_GOLD)
			hand_markers[i] = marker
		marker.text = "HAND %d" % (playing + 1)
		marker.position = _over_hand(i + playing * SPLIT_KEY, MARKER_HEIGHT)
		marker.visible = true


## A point `height` over the middle of a hand's first two cards (local to the table).
func _over_hand(key: int, height: float) -> Vector3:
	return cards.card_position(key, 0).lerp(cards.card_position(key, 1), 0.5) + Vector3(0, height, 0)


## Where a split hand's bet sits (local): in front of that hand (0 = first / left, 1 = second / right).
func hand_bet_spot(seat: int, hand: int) -> Vector3:
	var s: Node3D = seats[clampi(seat, 0, seats.size() - 1)]
	var to_seat: Vector3 = Vector3(s.position.x, 0, s.position.z) - ARC_CENTRE
	to_seat.y = 0.0
	var side: Vector3 = Basis(Vector3.UP, s.rotation.y) * Vector3(SPLIT_SPREAD * (1.0 if hand == 1 else -1.0), 0.0, 0.0)
	return ARC_CENTRE + to_seat.normalized() * BET_RADIUS + side + Vector3(0, TABLE_TOP, 0)


func _hand_label(node_name: String, size: int, color: Color) -> Label3D:
	var l := Label3D.new()
	l.name = node_name
	l.font = Vfx.font()
	l.font_size = size
	l.pixel_size = 0.0022
	l.outline_size = 14
	l.modulate = color
	l.outline_modulate = Palette.CASINO_BLACK
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	add_child(l)
	return l


static func _ints(cards_in: Array) -> Array[int]:
	var out: Array[int] = []
	for c: Variant in cards_in:
		out.append(int(c))
	return out


## Total of the dealer's face-up cards (the hole card never reaches the client before the reveal);
## hidden while the dealer has no cards.
func _show_dealer_total(dealer: Array) -> void:
	if not Vfx.enabled():
		return
	if dealer_total_label == null:
		dealer_total_label = Label3D.new()
		dealer_total_label.name = "DealerTotal"
		dealer_total_label.font = Vfx.font()
		dealer_total_label.font_size = 64
		dealer_total_label.pixel_size = 0.0028
		dealer_total_label.outline_size = 16
		dealer_total_label.modulate = Palette.CREAM
		dealer_total_label.outline_modulate = Palette.CASINO_BLACK
		dealer_total_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		dealer_total_label.position = DEALER_TOTAL_POS
		add_child(dealer_total_label)
	var shown: Array[int] = []
	for c: Variant in dealer:
		if int(c) != TableCards.FACE_DOWN:
			shown.append(int(c))
	dealer_total_label.visible = not shown.is_empty()
	dealer_total_label.text = str(HandEval.total(shown)) if not shown.is_empty() else ""


## Half-moon geometry, measured from the arc centre: the straight edge is on z = ARC_CENTRE.z and
## the curve bulges towards +z. Built in-engine so every part is mirrored by construction.
const FELT_RADIUS: float = 1.6
const RAIL_RADIUS: float = 1.78
const RAIL_WIDTH: float = 0.2
const ARC_SEGMENTS: int = 28
const FELT_COLOR: Color = Color("#275E49")
const RAIL_COLOR: Color = Color("#681F2C")
const WOOD_COLOR: Color = Color("#3A2A1E")


func _add_table_model() -> void:
	var table := Node3D.new()
	table.name = "Table"
	table.position = ARC_CENTRE
	add_child(table)
	var top: float = TABLE_TOP
	_half_disc(table, FELT_RADIUS, top, GreyboxKit.material(FELT_COLOR, 0.0, 0.8), "Felt")
	_half_disc(table, RAIL_RADIUS, top - 0.14, GreyboxKit.material(WOOD_COLOR), "Underside")
	for i: int in ARC_SEGMENTS:
		var a0: float = PI * i / ARC_SEGMENTS
		var a1: float = PI * (i + 1) / ARC_SEGMENTS
		# Padded rail with a wooden apron beneath it, and the brass foot ring near the floor.
		_arc_piece(table, a0, a1, RAIL_RADIUS - RAIL_WIDTH * 0.5, RAIL_WIDTH, 0.07, top + 0.015, RAIL_COLOR, "Rail%d" % i)
		_arc_piece(table, a0, a1, RAIL_RADIUS - 0.03, 0.06, 0.14, top - 0.07, WOOD_COLOR, "Apron%d" % i)
		_arc_piece(table, a0, a1, 1.3, 0.05, 0.04, 0.22, Palette.WARM_GOLD, "FootRing%d" % i, true)
	# Straight (dealer) side: rail, apron and brass foot bar.
	var w: float = RAIL_RADIUS * 2.0
	GreyboxKit.box(table, Vector3(w, 0.07, 0.14), Vector3(0, top + 0.015, -0.07), RAIL_COLOR, "RailStraight", false)
	GreyboxKit.box(table, Vector3(w, 0.14, 0.05), Vector3(0, top - 0.07, -0.025), WOOD_COLOR, "ApronStraight", false)
	var bar: Node3D = GreyboxKit.cylinder(table, 0.025, w - 0.5, Vector3(0, 0.22, 0.12), Palette.WARM_GOLD, "FootBar", false, 0.8)
	bar.rotation.z = PI / 2.0
	# Four legs, mirrored left/right: two at the straight corners, two under the curve.
	var leg_h: float = top - 0.14
	for sx: float in [-1.0, 1.0]:
		for leg: Vector2 in [Vector2(1.35, 0.14), Vector2(0.85, 1.1)]:
			var lp := Vector3(sx * leg.x, leg_h * 0.5, leg.y)
			var tag: String = "Leg%s%s" % ["L" if sx < 0.0 else "R", "Back" if leg.y < 0.5 else "Front"]
			GreyboxKit.cylinder(table, 0.07, leg_h, lp, WOOD_COLOR, tag, false)
			GreyboxKit.cylinder(table, 0.085, 0.04, Vector3(lp.x, 0.22, lp.z), Palette.WARM_GOLD, tag + "Brass", false, 0.8)
			GreyboxKit.cylinder(table, 0.1, 0.03, Vector3(lp.x, 0.015, lp.z), Palette.WARM_GOLD, tag + "Foot", false, 0.8)


## Flat half disc (curve towards +z) at height `y`, double sided.
func _half_disc(parent: Node3D, radius: float, y: float, mat: StandardMaterial3D, node_name: String) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for i: int in ARC_SEGMENTS:
		var a0: float = PI * i / ARC_SEGMENTS
		var a1: float = PI * (i + 1) / ARC_SEGMENTS
		st.add_vertex(Vector3(0, y, 0))
		st.add_vertex(Vector3(cos(a0) * radius, y, sin(a0) * radius))
		st.add_vertex(Vector3(cos(a1) * radius, y, sin(a1) * radius))
	var m: StandardMaterial3D = mat.duplicate() as StandardMaterial3D
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = st.commit()
	mi.material_override = m
	parent.add_child(mi)


## One box standing on the arc between angles a0 and a1 (radius `r`, `thick` radially, `h` tall,
## centred at height `y`). Visual only.
func _arc_piece(parent: Node3D, a0: float, a1: float, r: float, thick: float, h: float, y: float, color: Color, node_name: String, brass: bool = false) -> void:
	var am: float = (a0 + a1) * 0.5
	var length: float = 2.0 * r * sin((a1 - a0) * 0.5) * 1.04
	var node: Node3D = GreyboxKit.box(parent, Vector3(thick, h, length), Vector3(cos(am) * r, y, sin(am) * r), color, node_name, false)
	node.rotation.y = -am  # local +x points away from the centre
	if brass:
		(node.get_node("Mesh") as MeshInstance3D).material_override = GreyboxKit.gold()
