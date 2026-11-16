class_name BaccaratStation
extends StationBase
## The baccarat table: a long table with round corners in deep blue felt, a padded leather rail on
## dark wood and brass, five stools along the players' (+z) side and the dealer on the far side by
## the shoe. Every seat has its own printed spots: PLAYER and BANKER in front, P PAIR · TIE · B PAIR
## behind them. Across the middle lie the two hands, PLAYER on the left and BANKER on the right, in
## gold frames; their totals float over the cards and the winning hand is outlined in gold. A small
## brass-framed scoreboard by the dealer shows the last rounds (the "road"). Presentation only:
## every card comes from the server's public state.

## Felt height and the table: a rectangle of 2·HALF_X × 2·HALF_Z with corners rounded by CORNER_R.
const TABLE_TOP: float = 0.935
const HALF_X: float = 1.8
const HALF_Z: float = 0.85
const CORNER_R: float = 0.4
const RAIL_W: float = 0.13
const RAIL_OUTER: float = HALF_Z + RAIL_W
const SEAT_XS: Array[float] = [-1.44, -0.72, 0.0, 0.72, 1.44]
const SEAT_Z: float = 1.42
## A seat's betting spots: the front row (PLAYER · BANKER) and the back row (P PAIR · TIE · B PAIR).
const FRONT_Z: float = 0.63
const BACK_Z: float = 0.39
const FRONT_GAP: float = 0.16
const BACK_GAP: float = 0.23
## Each seat's betting panel: a darker plate in a gold line round its five spots.
const PANEL_W: float = 0.64
const PANEL_Z0: float = 0.27
const PANEL_Z1: float = 0.81
const MAIN_R: float = 0.085
const SIDE_R: float = 0.062
## The two hands: where each one's first card lies and the step to the next (left to right).
const HAND_Z: float = -0.3
const PLAYER_X: float = -0.79
const BANKER_X: float = 0.33
const CARD_STEP: float = 0.23
## Pile keys for `TableCards`.
const PLAYER_KEY: int = 0
const BANKER_KEY: int = 1
const SHOE_POS: Vector3 = Vector3(1.42, TABLE_TOP, -0.5)
const HOUSE_SPOT: Vector3 = Vector3(0.0, TABLE_TOP + 0.05, -0.66)
const ROAD_POS: Vector3 = Vector3(-1.38, TABLE_TOP, -0.56)
## Each seat's view: high over the players' side, right of the middle, so the two hands, the
## seat's own spots and the scoreboard fill the left two thirds (the overlay is a column down the
## right third). Each seat's eye moves `SEAT_EYE_SHIFT` of its stool's x along.
const SEAT_EYE: Vector3 = Vector3(0.3, 1.95, 1.12)
const SEAT_AIM: Vector3 = Vector3(0.45, TABLE_TOP, -0.08)
const SEAT_EYE_SHIFT: float = 0.55
const FELT_COLOR: Color = Color("#10254A")
const PRINT_COLOR: Color = Color("#D6A84B")
const RAIL_COLOR: Color = Color("#2B1B16")
const WOOD_COLOR: Color = Color("#3A2A1E")
## Scoreboard colours: Player blue, Banker red, Tie green (the usual road colours, kept warm).
const PLAYER_COLOR: Color = Color("#4F7FC0")
const BANKER_COLOR: Color = Color("#C83D3D")
const TIE_COLOR: Color = Color("#4FA36A")
const CORNER_SEGMENTS: int = 6
const HOT_CARD_LIGHT: float = 3.5

var cards: TableCards
var player_label: Label3D
var banker_label: Label3D
## The scoreboard's dots, oldest first (client only).
var road_dots: Array[MeshInstance3D] = []


func _build_visuals() -> void:
	game_id = &"baccarat"
	seat_count = SEAT_XS.size()
	interact_radius = 3.0
	hot_center = Vector3(0, 0, 0.2)
	# Collision: one box the size of the table; what you see is built from parts below.
	var body: Node3D = GreyboxKit.box(self, Vector3(2.0 * (HALF_X + RAIL_W), TABLE_TOP, 2.0 * RAIL_OUTER), Vector3(0, TABLE_TOP * 0.5, 0), WOOD_COLOR, "Body")
	(body.get_node(^"Mesh") as Node3D).visible = false
	_build_table()
	cards = TableCards.new()
	cards.name = "Cards"
	cards.shoe = SHOE_POS + Vector3(0, 0.1, 0)
	cards.spots[PLAYER_KEY] = [Vector3(PLAYER_X, TABLE_TOP, HAND_Z), 0.0, CARD_STEP]
	cards.spots[BANKER_KEY] = [Vector3(BANKER_X, TABLE_TOP, HAND_Z), 0.0, CARD_STEP]
	add_child(cards)
	for i: int in seat_count:
		var pos := Vector3(SEAT_XS[i], 0.0, SEAT_Z)
		_stool(pos, "Stool%d" % i)
		_add_seat(pos + Vector3(0, 0.5, 0), 0.0)
		_add_seat_camera(SEAT_EYE + Vector3(SEAT_XS[i] * SEAT_EYE_SHIFT, 0, 0), SEAT_AIM + Vector3(SEAT_XS[i] * SEAT_EYE_SHIFT, 0, 0))
	camera_anchor = Node3D.new()
	camera_anchor.name = "CameraAnchor"
	camera_anchor.position = SEAT_EYE
	camera_anchor.rotation = look_rotation(SEAT_EYE, SEAT_AIM)
	add_child(camera_anchor)
	if Vfx.enabled():
		_build_print()
		_build_road()
		player_label = _float_label("PlayerTotal")
		player_label.position = Vector3(PLAYER_X + CARD_STEP, TABLE_TOP + 0.36, HAND_Z - 0.05)
		banker_label = _float_label("BankerTotal")
		banker_label.position = Vector3(BANKER_X + CARD_STEP, TABLE_TOP + 0.36, HAND_Z - 0.05)


## A softer hot-table spotlight: the cards under it must stay readable (no bloom).
func hot_light_energy() -> float:
	return HOT_CARD_LIGHT


func prompt_text(min_bet: int) -> String:
	if out_of_order_left > 0.0:
		return super.prompt_text(min_bet)
	return "%s Play Baccarat — Min $%d" % [InputGlyphs.hint(&"interact"), min_bet]


## Where a bet of `type` goes on seat `i`'s spots (local).
static func bet_spot(i: int, type: StringName) -> Vector3:
	var x: float = SEAT_XS[clampi(i, 0, SEAT_XS.size() - 1)]
	match type:
		BaccaratLogic.BANKER:
			return Vector3(x + FRONT_GAP, TABLE_TOP, FRONT_Z)
		BaccaratLogic.TIE:
			return Vector3(x, TABLE_TOP, BACK_Z)
		BaccaratLogic.PLAYER_PAIR:
			return Vector3(x - BACK_GAP, TABLE_TOP, BACK_Z)
		BaccaratLogic.BANKER_PAIR:
			return Vector3(x + BACK_GAP, TABLE_TOP, BACK_Z)
	return Vector3(x - FRONT_GAP, TABLE_TOP, FRONT_Z)


## Radius of the printed ring of a bet type.
static func spot_radius(type: StringName) -> float:
	return MAIN_R if type == BaccaratLogic.PLAYER or type == BaccaratLogic.BANKER else SIDE_R


## Mirrors the public state onto the felt: both hands as far as they are turned, their totals,
## the gold outline round the winning hand (both on a tie) and the scoreboard.
func show_round(pub: Dictionary) -> void:
	var pc: Array = pub.get("player_cards", [])
	var bc: Array = pub.get("banker_cards", [])
	var win: StringName = StringName(pub.get("winner", &""))
	var outlined: Array[int] = []
	if win == BaccaratLogic.PLAYER or win == BaccaratLogic.TIE:
		outlined.append(PLAYER_KEY)
	if win == BaccaratLogic.BANKER or win == BaccaratLogic.TIE:
		outlined.append(BANKER_KEY)
	cards.set_outlined(outlined)
	cards.show_cards({PLAYER_KEY: pc, BANKER_KEY: bc}, [])
	_show_total(player_label, "PLAYER", pc, int(pub.get("player_total", 0)), win, BaccaratLogic.PLAYER)
	_show_total(banker_label, "BANKER", bc, int(pub.get("banker_total", 0)), win, BaccaratLogic.BANKER)
	show_road(pub.get("history", []))


## The table was cleared for a minigame.
func reset_table() -> void:
	cards.set_outlined([])
	cards.show_cards({}, [])
	for l: Label3D in [player_label, banker_label]:
		if l != null:
			l.visible = false


## "PLAYER 7" over a hand while it is dealt; "PLAYER 9 · WINS" in green once it won.
func _show_total(l: Label3D, word: String, hand: Array, total: int, win: StringName, side: StringName) -> void:
	if l == null:
		return
	l.visible = not hand.is_empty()
	if not l.visible:
		return
	l.text = "%s  %d" % [word, total]
	l.modulate = Palette.CREAM
	if win == side:
		l.text += "  ·  WINS"
		l.modulate = Palette.MONEY_GREEN
	elif win == BaccaratLogic.TIE:
		l.text += "  ·  TIE"
		l.modulate = Palette.WARM_GOLD
	elif win != &"":
		l.modulate = Color(Palette.CREAM, 0.6)


## Lights the scoreboard: one dot per round, oldest on the left, in its winner's colour.
func show_road(history: Array) -> void:
	var start: int = maxi(history.size() - road_dots.size(), 0)
	for i: int in road_dots.size():
		var k: int = start + i
		var dot: MeshInstance3D = road_dots[i]
		dot.visible = k < history.size()
		if dot.visible:
			var w: StringName = StringName(history[k])
			var c: Color = PLAYER_COLOR if w == BaccaratLogic.PLAYER else (BANKER_COLOR if w == BaccaratLogic.BANKER else TIE_COLOR)
			(dot.material_override as StandardMaterial3D).albedo_color = c


# --- The table ----------------------------------------------------------------------------------


func _build_table() -> void:
	var top: float = TABLE_TOP
	_rounded_slab(HALF_X, HALF_Z, CORNER_R, top, GreyboxKit.material(FELT_COLOR, 0.0, 0.85), "Felt")
	_rounded_slab(HALF_X + RAIL_W + 0.02, RAIL_OUTER + 0.02, CORNER_R + RAIL_W + 0.02, top - 0.14, GreyboxKit.material(WOOD_COLOR), "Underside")
	# The padded rail, the wooden apron under it and a brass foot ring, all the way round.
	var straight_x: float = 2.0 * (HALF_X - CORNER_R)
	var straight_z: float = 2.0 * (HALF_Z - CORNER_R)
	for side: float in [-1.0, 1.0]:
		var tag: String = "N" if side < 0.0 else "S"
		GreyboxKit.box(self, Vector3(straight_x, 0.07, RAIL_W), Vector3(0, top + 0.015, side * (HALF_Z + RAIL_W * 0.5)), RAIL_COLOR, "Rail" + tag, false)
		GreyboxKit.box(self, Vector3(straight_x, 0.14, 0.05), Vector3(0, top - 0.07, side * (RAIL_OUTER - 0.02)), WOOD_COLOR, "Apron" + tag, false)
		var foot: Node3D = GreyboxKit.box(self, Vector3(straight_x, 0.04, 0.05), Vector3(0, 0.22, side * (HALF_Z - 0.15)), Palette.WARM_GOLD, "FootRail" + tag, false)
		(foot.get_node(^"Mesh") as MeshInstance3D).material_override = GreyboxKit.gold()
		var etag: String = "W" if side < 0.0 else "E"
		GreyboxKit.box(self, Vector3(RAIL_W, 0.07, straight_z), Vector3(side * (HALF_X + RAIL_W * 0.5), top + 0.015, 0), RAIL_COLOR, "Rail" + etag, false)
		GreyboxKit.box(self, Vector3(0.05, 0.14, straight_z), Vector3(side * (HALF_X + RAIL_W - 0.02), top - 0.07, 0), WOOD_COLOR, "Apron" + etag, false)
	var k: int = 0
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var c := Vector3(sx * (HALF_X - CORNER_R), 0.0, sz * (HALF_Z - CORNER_R))
			var a_from: float = atan2(sz, sx) - PI * 0.25
			for i: int in CORNER_SEGMENTS:
				var a0: float = a_from + PI * 0.5 * i / CORNER_SEGMENTS
				var a1: float = a_from + PI * 0.5 * (i + 1) / CORNER_SEGMENTS
				_arc_piece(c, a0, a1, CORNER_R + RAIL_W * 0.5, RAIL_W, 0.07, top + 0.015, RAIL_COLOR, "RailCorner%d" % k)
				_arc_piece(c, a0, a1, CORNER_R + RAIL_W - 0.02, 0.05, 0.14, top - 0.07, WOOD_COLOR, "ApronCorner%d" % k)
				k += 1
	# Six turned legs with brass collars and feet.
	var leg_h: float = top - 0.14
	for lx: float in [-1.3, 0.0, 1.3]:
		for sz: float in [-1.0, 1.0]:
			var lp := Vector3(lx, leg_h * 0.5, sz * 0.5)
			var tag: String = "Leg%d%s" % [int(lx * 10), "N" if sz < 0.0 else "S"]
			GreyboxKit.cylinder(self, 0.07, leg_h, lp, WOOD_COLOR, tag, false)
			GreyboxKit.cylinder(self, 0.085, 0.04, Vector3(lp.x, 0.22, lp.z), Palette.WARM_GOLD, tag + "Brass", false, 0.8)
			GreyboxKit.cylinder(self, 0.1, 0.03, Vector3(lp.x, 0.015, lp.z), Palette.WARM_GOLD, tag + "Foot", false, 0.8)
	# The dealer's side: the shoe (dark wood with a brass lip, leaning towards the dealer) and the
	# chip rack.
	var shoe: Node3D = GreyboxKit.box(self, Vector3(0.22, 0.12, 0.36), SHOE_POS + Vector3(0, 0.06, 0), WOOD_COLOR.darkened(0.2), "Shoe", false)
	shoe.rotation.x = deg_to_rad(-8.0)
	var lip: Node3D = GreyboxKit.box(self, Vector3(0.23, 0.03, 0.04), SHOE_POS + Vector3(0, 0.1, 0.19), Palette.WARM_GOLD, "ShoeLip", false)
	(lip.get_node(^"Mesh") as MeshInstance3D).material_override = GreyboxKit.gold()
	GreyboxKit.box(self, Vector3(0.2, 0.05, 0.28), SHOE_POS + Vector3(0, 0.14, -0.02), TableCards.BACK_TINT.darkened(0.15), "ShoeCards", false)
	GreyboxKit.box(self, Vector3(0.72, 0.08, 0.2), HOUSE_SPOT + Vector3(0, -0.01, 0), Color("#1E1B19"), "ChipRack", false)
	var chip_colors: Array[Color] = [Palette.CASINO_RED, Palette.CREAM, Palette.FELT_GREEN, Palette.WARM_GOLD, Palette.CASINO_BLACK, Palette.CASINO_RED]
	for j: int in chip_colors.size():
		var roll: Node3D = GreyboxKit.cylinder(self, 0.03, 0.16, HOUSE_SPOT + Vector3(-0.29 + j * 0.116, 0.05, 0), chip_colors[j], "RackChips%d" % j, false)
		roll.rotation.x = PI * 0.5


## Flat rounded rectangle (half sizes `hx`, `hz`, corner radius `r`) at height `y`, double sided.
func _rounded_slab(hx: float, hz: float, r: float, y: float, mat: StandardMaterial3D, node_name: String, at: Vector2 = Vector2.ZERO) -> void:
	var ring: Array[Vector3] = []
	var corners: Array[Vector2] = [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
	for q: int in 4:
		var c := Vector2(corners[q].x * (hx - r), corners[q].y * (hz - r))
		for i: int in CORNER_SEGMENTS + 1:
			var a: float = PI * 0.5 * q + PI * 0.5 * i / CORNER_SEGMENTS
			ring.append(Vector3(at.x + c.x + cos(a) * r, y, at.y + c.y + sin(a) * r))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var centre := Vector3(at.x, y, at.y)
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
	add_child(mi)


## One box on a round corner (centre `c`) between angles a0 and a1 (from +x towards +z), at radius
## `r`, `thick` radially and `h` tall, centred at height `y`. Visual only.
func _arc_piece(c: Vector3, a0: float, a1: float, r: float, thick: float, h: float, y: float, color: Color, node_name: String) -> void:
	var am: float = (a0 + a1) * 0.5
	var length: float = 2.0 * r * sin((a1 - a0) * 0.5) * 1.06
	var dir := Vector3(cos(am), 0.0, sin(am))
	var node: Node3D = GreyboxKit.box(self, Vector3(thick, h, length), c + dir * r + Vector3(0, y, 0), color, node_name, false)
	node.rotation.y = atan2(-dir.z, dir.x)  # local +x points away from the centre


## The gold print on the felt, read from the players' side: the name and the pays across the
## middle, the two hands' frames with their names, and every seat's five betting spots.
func _build_print() -> void:
	_felt_text("BACCARAT", Vector3(0.0, TABLE_TOP + 0.002, 0.075), 60, 0.0019, "PrintName")
	_felt_text("BANKER PAYS 1 TO 1 LESS 5%%  ·  TIE PAYS %d TO 1  ·  PAIRS PAY %d TO 1" % [Registry.balance.baccarat_tie_pays, Registry.balance.baccarat_pair_pays] if Registry.balance != null else "", Vector3(0.0, TABLE_TOP + 0.002, 0.18), 26, 0.0015, "PrintRules")
	var frame_w: float = CARD_STEP * 2.0 + TableCards.CARD_SIZE.x + 0.08
	var frame_d: float = TableCards.CARD_SIZE.y * cos(TableCards.HAND_TILT) + 0.1
	for spec: Array in [["PLAYER", PLAYER_X, PLAYER_COLOR], ["BANKER", BANKER_X, BANKER_COLOR]]:
		var cx: float = float(spec[1]) + CARD_STEP
		var f := MeshInstance3D.new()
		f.name = "Frame" + String(spec[0]).capitalize()
		var box := BoxMesh.new()
		box.size = Vector3(frame_w, 0.002, frame_d)
		f.mesh = box
		f.material_override = GreyboxKit.material(FELT_COLOR.darkened(0.3), 0.0, 0.9)
		f.position = Vector3(cx, TABLE_TOP + 0.0008, HAND_Z + 0.02)
		add_child(f)
		_ring_outline(Vector3(cx, TABLE_TOP + 0.0012, HAND_Z + 0.02), Vector2(frame_w, frame_d), "FrameEdge" + String(spec[0]).capitalize())
		var word: Label3D = _felt_text(String(spec[0]), Vector3(cx, TABLE_TOP + 0.002, HAND_Z + 0.02 + frame_d * 0.5 + 0.06), 36, 0.0018, "Word" + String(spec[0]).capitalize())
		word.modulate = Color(spec[2] as Color, 0.95).lightened(0.15)
	var frame_mat: StandardMaterial3D = GreyboxKit.material(PRINT_COLOR, 0.0, 0.8)
	var words: Dictionary = {
		BaccaratLogic.PLAYER: "PLAYER", BaccaratLogic.BANKER: "BANKER", BaccaratLogic.TIE: "TIE",
		BaccaratLogic.PLAYER_PAIR: "P PAIR", BaccaratLogic.BANKER_PAIR: "B PAIR",
	}
	var fills: Dictionary = {
		BaccaratLogic.PLAYER: PLAYER_COLOR.darkened(0.5), BaccaratLogic.BANKER: BANKER_COLOR.darkened(0.6),
		BaccaratLogic.TIE: TIE_COLOR.darkened(0.6), BaccaratLogic.PLAYER_PAIR: FELT_COLOR.lightened(0.08), BaccaratLogic.BANKER_PAIR: FELT_COLOR.lightened(0.08),
	}
	for i: int in seat_count:
		var px: float = SEAT_XS[i]
		var pz: float = (PANEL_Z0 + PANEL_Z1) * 0.5
		_rounded_slab(PANEL_W * 0.5, (PANEL_Z1 - PANEL_Z0) * 0.5, 0.06, TABLE_TOP + 0.0006, GreyboxKit.material(FELT_COLOR.darkened(0.35), 0.0, 0.9), "SeatPanel%d" % i, Vector2(px, pz))
		_ring_outline(Vector3(px, TABLE_TOP + 0.001, pz), Vector2(PANEL_W, PANEL_Z1 - PANEL_Z0), "SeatPanelEdge%d" % i)
		for type: StringName in BaccaratLogic.BET_TYPES:
			var disc := MeshInstance3D.new()
			disc.name = "Fill%d%s" % [i, String(type).capitalize().replace(" ", "")]
			var cyl := CylinderMesh.new()
			cyl.top_radius = spot_radius(type) - 0.004
			cyl.bottom_radius = cyl.top_radius
			cyl.height = 0.001
			cyl.radial_segments = 24
			disc.mesh = cyl
			disc.material_override = GreyboxKit.material(fills[type], 0.0, 0.85)
			disc.position = bet_spot(i, type) + Vector3(0, 0.0012, 0)
			disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(disc)
			var spot: Vector3 = bet_spot(i, type)
			var r: float = spot_radius(type)
			var ring := MeshInstance3D.new()
			ring.name = "Spot%d%s" % [i, String(type).capitalize().replace(" ", "")]
			var torus := TorusMesh.new()
			torus.inner_radius = r - 0.011
			torus.outer_radius = r
			torus.rings = 24
			ring.mesh = torus
			var m: StandardMaterial3D = frame_mat
			if type == BaccaratLogic.PLAYER:
				m = GreyboxKit.material(PLAYER_COLOR.lightened(0.2), 0.0, 0.8)
			elif type == BaccaratLogic.BANKER:
				m = GreyboxKit.material(BANKER_COLOR.lightened(0.1), 0.0, 0.8)
			ring.material_override = m
			ring.scale = Vector3(1.0, 0.08, 1.0)
			ring.position = spot + Vector3(0, 0.002, 0)
			add_child(ring)
			var size: int = 30 if r == MAIN_R else 22
			_felt_text(String(words[type]), spot + Vector3(0, 0.002, r + 0.028), size, 0.0013, "SpotLabel%d%s" % [i, String(type).capitalize().replace(" ", "")])


## A thin gold frame round a rectangle on the felt.
func _ring_outline(centre: Vector3, size: Vector2, node_name: String) -> void:
	var t: float = 0.01
	var mat: StandardMaterial3D = GreyboxKit.material(PRINT_COLOR.darkened(0.2), 0.0, 0.8)
	var parts: Array = [
		[Vector3(size.x, 0.002, t), Vector3(0, 0, -size.y * 0.5)], [Vector3(size.x, 0.002, t), Vector3(0, 0, size.y * 0.5)],
		[Vector3(t, 0.002, size.y), Vector3(-size.x * 0.5, 0, 0)], [Vector3(t, 0.002, size.y), Vector3(size.x * 0.5, 0, 0)],
	]
	for j: int in parts.size():
		var mi := MeshInstance3D.new()
		mi.name = "%s%d" % [node_name, j]
		var box := BoxMesh.new()
		box.size = parts[j][0]
		mi.mesh = box
		mi.material_override = mat
		mi.position = centre + (parts[j][1] as Vector3)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


## The scoreboard by the dealer: a small dark panel in a brass frame leaning towards the players,
## with a row of dots for the last rounds.
func _build_road() -> void:
	var root := Node3D.new()
	root.name = "Road"
	root.position = ROAD_POS
	add_child(root)
	var stand: Node3D = GreyboxKit.box(root, Vector3(0.5, 0.03, 0.12), Vector3(0, 0.015, 0), Palette.WARM_GOLD, "Stand", false)
	(stand.get_node(^"Mesh") as MeshInstance3D).material_override = GreyboxKit.gold()
	var board := Node3D.new()
	board.name = "Board"
	board.position = Vector3(0, 0.14, 0)
	board.rotation.x = deg_to_rad(-15.0)
	root.add_child(board)
	var frame: Node3D = GreyboxKit.box(board, Vector3(0.5, 0.22, 0.02), Vector3.ZERO, Palette.WARM_GOLD, "Frame", false)
	(frame.get_node(^"Mesh") as MeshInstance3D).material_override = GreyboxKit.gold()
	GreyboxKit.box(board, Vector3(0.46, 0.18, 0.01), Vector3(0, 0, 0.011), Palette.CASINO_BLACK, "Panel", false)
	var title := Label3D.new()
	title.name = "RoadTitle"
	title.text = "LAST ROUNDS"
	title.font = Vfx.font()
	title.font_size = 22
	title.pixel_size = 0.0012
	title.outline_size = 0
	title.modulate = Color(PRINT_COLOR, 0.9)
	title.position = Vector3(0, 0.055, 0.018)
	board.add_child(title)
	var dot_mesh := CylinderMesh.new()
	dot_mesh.top_radius = 0.014
	dot_mesh.bottom_radius = 0.014
	dot_mesh.height = 0.004
	for i: int in BaccaratLogic.HISTORY_SIZE:
		var dot := MeshInstance3D.new()
		dot.name = "Dot%d" % i
		dot.mesh = dot_mesh
		dot.rotation.x = PI * 0.5
		dot.position = Vector3(-0.198 + i * 0.036, -0.02, 0.018)
		var m: StandardMaterial3D = GreyboxKit.material(TIE_COLOR, 0.0, 0.5).duplicate() as StandardMaterial3D
		m.emission_enabled = true
		m.emission = Color(0.1, 0.1, 0.1)
		dot.material_override = m
		dot.visible = false
		board.add_child(dot)
		road_dots.append(dot)


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


func _float_label(node_name: String) -> Label3D:
	var l := Label3D.new()
	l.name = node_name
	l.font = Vfx.font()
	l.font_size = 44
	l.pixel_size = 0.0021
	l.outline_size = 14
	l.modulate = Palette.CREAM
	l.outline_modulate = Palette.CASINO_BLACK
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.visible = false
	add_child(l)
	return l
