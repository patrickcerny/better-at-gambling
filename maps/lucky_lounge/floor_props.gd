class_name FloorProps
extends RefCounted
## What the per-round floor plan (docs/FLOOR_PLAN.md) puts on the Lucky Lounge besides the games:
## closed spots (a velvet rope round the empty table spot with a CLOSED TONIGHT sign, a potted
## palm where a slot machine stood) and the TONIGHT'S FLOOR board in the entrance hall.

## The board on the start room's side of the lobby wall, east of the doors (centre, facing the
## hall: +z), and its size.
const BOARD_POS: Vector3 = Vector3(9.2, 2.45, LuckyLounge.LOBBY_DOORS_Z + LuckyLounge.LOBBY_WALL_T * 0.5 + 0.05)
const BOARD_SIZE: Vector2 = Vector2(3.6, 2.7)
## The roped-off rectangle of a closed spot (local to the spot: centre and size) per footprint: a
## table's own spread, a Plinko wall's area in front of its board. Other sizes get a potted plant.
const ROPE_AREAS: Dictionary = {&"table": [Vector3(0, 0, 0.2), Vector2(3.2, 2.6)], &"big": [Vector3(0, 0, 0.9), Vector2(3.4, 2.2)]}
const CLOSED_SIGN: String = "CLOSED\nTONIGHT"
const PLANTS: Array[StringName] = [&"plant_1", &"plant_2", &"plant_3"]


## A closed spot at `anchor` ({id, footprint, pos, yaw}) under `parent`. Solid parts (posts, pot)
## are static colliders in the navmesh like the tables, so nobody walks through a rope post.
static func closed_spot(parent: Node3D, anchor: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Closed_%s" % String(anchor["id"])
	root.position = anchor["pos"]
	root.rotation.y = float(anchor["yaw"])
	root.set_meta(&"anchor", anchor["id"])
	parent.add_child(root)
	var fp: StringName = StringName(anchor["footprint"])
	var p: Vector3 = anchor["pos"]
	if not ROPE_AREAS.has(fp):
		var pot: Node3D = GreyboxKit.cylinder(root, 0.35, 0.6, Vector3(0, 0.3, 0), Color("#5A3A22"), "Pot")
		var plant: Node3D = PropModels.dress(pot, PLANTS[absi(int(p.x * 3.0 + p.z)) % PLANTS.size()], 0.3, 1.7)
		plant.rotation.y = p.x * 0.7
		return root
	var centre: Vector3 = ROPE_AREAS[fp][0]
	var half: Vector2 = (ROPE_AREAS[fp][1] as Vector2) * 0.5
	var corners: Array[Vector3] = [centre + Vector3(-half.x, 0, -half.y), centre + Vector3(half.x, 0, -half.y), centre + Vector3(half.x, 0, half.y), centre + Vector3(-half.x, 0, half.y)]
	for c: Vector3 in corners:
		var post: Node3D = GreyboxKit.cylinder(root, 0.06, 1.0, c + Vector3(0, 0.5, 0), Palette.WARM_GOLD, "RopePost", true, 0.8)
		GreyboxKit.sphere(post, 0.1, Vector3(0, 0.55, 0), Palette.WARM_GOLD, "Knob")
		GreyboxKit.cylinder(root, 0.16, 0.04, c + Vector3(0, 0.02, 0), Palette.WARM_GOLD, "RopeFoot", false, 0.8)
	for i: int in corners.size():
		var a: Vector3 = corners[i] + Vector3(0, 0.85, 0)
		var b: Vector3 = corners[(i + 1) % corners.size()] + Vector3(0, 0.85, 0)
		GreyboxKit.beam(root, a, b, Vector2(0.05, 0.05), Palette.VIP_BURGUNDY, "Rope", false)
	# The sign on its stand in the middle, readable from both sides.
	GreyboxKit.cylinder(root, 0.04, 1.3, centre + Vector3(0, 0.65, 0), Palette.WARM_GOLD, "SignPole", false, 0.8)
	GreyboxKit.box(root, Vector3(1.3, 0.62, 0.05), centre + Vector3(0, 1.55, 0), Palette.CASINO_BLACK, "SignBoard", false)
	for side: float in [1.0, -1.0]:
		var l := Label3D.new()
		l.name = "ClosedSign"
		l.text = CLOSED_SIGN
		l.font_size = 64
		l.pixel_size = 0.0045
		l.double_sided = false
		l.modulate = Palette.VIP_GOLD
		l.outline_modulate = Palette.CASINO_BLACK
		l.outline_size = 8
		l.position = centre + Vector3(0, 1.55, 0.035 * side)
		l.rotation.y = 0.0 if side > 0.0 else PI
		root.add_child(l)
	return root


## The TONIGHT'S FLOOR board: a dark panel in a gold frame with a title; returns the label that
## lists the games (`board_text`).
static func board(parent: Node3D) -> Label3D:
	var root := Node3D.new()
	root.name = "TonightsFloor"
	root.position = BOARD_POS
	parent.add_child(root)
	GreyboxKit.box(root, Vector3(BOARD_SIZE.x, BOARD_SIZE.y, 0.06), Vector3.ZERO, Palette.CASINO_BLACK, "BoardPanel", false)
	for y: float in [-1.0, 1.0]:
		GreyboxKit.box(root, Vector3(BOARD_SIZE.x + 0.12, 0.08, 0.09), Vector3(0, y * BOARD_SIZE.y * 0.5, 0.01), Palette.WARM_GOLD, "BoardTrim", false)
	for x: float in [-1.0, 1.0]:
		GreyboxKit.box(root, Vector3(0.08, BOARD_SIZE.y, 0.09), Vector3(x * BOARD_SIZE.x * 0.5, 0, 0.01), Palette.WARM_GOLD, "BoardTrim", false)
	var title := Label3D.new()
	title.name = "BoardTitle"
	title.text = "TONIGHT'S FLOOR"
	title.font_size = 96
	title.pixel_size = 0.0035
	title.modulate = Palette.VIP_GOLD
	title.outline_modulate = Palette.CASINO_BLACK
	title.outline_size = 10
	title.position = Vector3(0, BOARD_SIZE.y * 0.5 - 0.3, 0.05)
	root.add_child(title)
	var body := Label3D.new()
	body.name = "BoardList"
	body.font_size = 48
	body.pixel_size = 0.0035
	body.line_spacing = 4.0
	body.modulate = Palette.CREAM
	body.outline_modulate = Palette.CASINO_BLACK
	body.outline_size = 6
	body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	body.position = Vector3(0, BOARD_SIZE.y * 0.5 - 0.6, 0.05)
	root.add_child(body)
	return body


## The board's list for a plan (wire form {station id: [game, anchor id]}) and the fixed games
## (game ids, e.g. the horse race): one line per game on the casino floor with its count, the VIP
## lounge's games, the fixed ones and how many spots are closed tonight.
static func board_text(plan: Dictionary, anchors: Array, fixed_games: Array) -> String:
	var vip_of: Dictionary = {}
	for a: Dictionary in anchors:
		vip_of[a["id"]] = bool(a.get("vip", false))
	var floor_counts: Dictionary = {}
	var vip_counts: Dictionary = {}
	for sid: Variant in plan:
		var entry: Array = plan[sid]
		var g: StringName = StringName(entry[0])
		var counts: Dictionary = vip_counts if bool(vip_of.get(StringName(entry[1]), false)) else floor_counts
		counts[g] = int(counts.get(g, 0)) + 1
	var lines: PackedStringArray = []
	for g: StringName in _sorted(floor_counts):
		lines.append(_counted(g, int(floor_counts[g])))
	if floor_counts.is_empty():
		lines.append("(the floor is closed)")
	if not vip_counts.is_empty():
		var vip: PackedStringArray = []
		for g: StringName in _sorted(vip_counts):
			vip.append(_counted(g, int(vip_counts[g])))
		lines.append("VIP: " + " · ".join(vip))
	for g: Variant in fixed_games:
		lines.append(("RACE HALL: %s" if StringName(g) == &"horse_race" else "%s") % game_name(StringName(g)))
	var closed: int = anchors.size() - plan.size()
	if closed > 0:
		lines.append("Closed tonight: %d spot%s" % [closed, "" if closed == 1 else "s"])
	return "\n".join(lines)


## Display name of a game in capitals ("BLACKJACK").
static func game_name(g: StringName) -> String:
	var def: GameDefinition = Registry.games.get(g, null)
	return (def.display_name if def != null and def.display_name != "" else String(g).capitalize()).to_upper()


static func _counted(g: StringName, n: int) -> String:
	return "%s  ×%d" % [game_name(g), n] if n > 1 else game_name(g)


static func _sorted(counts: Dictionary) -> Array[StringName]:
	var out: Array[StringName] = []
	for g: Variant in counts:
		out.append(StringName(g))
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return int(counts[a]) > int(counts[b]) or (int(counts[a]) == int(counts[b]) and String(a) < String(b)))
	return out
