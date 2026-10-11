class_name ClimbRoom
extends RefCounted
## The climb room: a tall, warm casino hall built for climbing (`ClimbKit`). Two layouts share the
## shell (carpeted start apron, the gallery balcony behind it, damask walls, chandeliers):
##
## - `"board"` (Dodge the Dice): a giant roulette betting layout tilted ~35° from the floor, 14 m
##   wide and ~41 m from the bottom edge to the top. Each of its 13 rows (1-2-3 at the bottom up
##   to 34-35-36, the green zero on top) is a felt tread on a walnut step: a 0.35 m ledge the bean
##   jumps, then a 2.6 m tread rising at ~30°. The dozens run up the west strip, the even-money
##   bets up the east strip, the columns' 2:1 are painted on the apron. Some fields are polished
##   brass slide chutes (`CHUTES`) that carry a bean back down a row. On top: a landing with a gold
##   WINNER rail, Lucky's podium and a brass gantry of hoppers that drop the hazards.
## - `"towers"` (Jackpot Climb): a staggered spiral of giant chip stacks (`ChipTowers`) winding
##   inward and upward round the central jackpot stack, whose gold pad (the finish box) waits at
##   `TOWER_TOP_Y` under the JACKPOT sign. A safety net covers the floor from the apron to the far
##   wall. The climb axis runs straight up the jackpot stack, so progress is height.
##
## `layout(variant)` is pure data for the server, `build(parent, variant)` makes the nodes, both
## around `WalkableLogicBase.ROOM_ORIGIN` (the centre of the board's bottom edge, on the floor).
## Local axes: -z climbs (the top is far north), +z is the apron and the gallery.

const HALF_W: float = 7.0
const ROWS: int = 13
const ROW_D: float = 2.6
const ROW_RISE: float = 1.82
const LIP: float = 0.35
## The flat start apron in front of the board, and the gallery balcony behind it.
const APRON_Z: float = 7.0
const GALLERY_Z: float = 7.4
const BACK_Z: float = 11.0
const GALLERY_H: float = 2.0
## The landing on top (from the board's top edge north).
const LANDING_D: float = 6.0
## The hall.
const HALL_HALF_X: float = 10.0
const WALL_T: float = 0.5
const SPAWN_Z: float = 3.4
const MAX_SPOTS: int = 8
## Number columns across the board (flat x, local): west strip, the three number columns, east
## strip.
const COL_X: Array[float] = [-7.0, -4.5, -1.5, 1.5, 4.5, 7.0]
## Slide chutes: [row, column] (columns index `COL_X` gaps, 0 = west strip .. 4 = east strip).
const CHUTES: Array = [[2, 2], [3, 4], [4, 1], [5, 3], [6, 0], [7, 2], [8, 4], [9, 1], [10, 3], [11, 2]]
## The hazard gantry: hoppers over the top row.
const HOPPER_X: Array[float] = [-5.6, -2.8, 0.0, 2.8, 5.6]
const HOPPER_DROP: float = 3.4
## Towers (Jackpot Climb): height of the finish pad on the jackpot stack.
const TOWER_TOP_Y: float = ChipTowers.TOP_Y

const WALNUT: Color = Color("#4A2E1D")
const WALNUT_DARK: Color = Color("#2B1A10")
const LAMP: Color = Color(1.0, 0.8, 0.52)

## variant → its layout (pure data, built once: the server reads it every tick). Read only.
static var _layouts: Dictionary = {}


# --- Pure data ------------------------------------------------------------------------------

## The board's flight in world coordinates (`local` true: in the room's frame).
static func flight(local: bool = false) -> Dictionary:
	var base: Vector3 = Vector3.ZERO if local else WalkableLogicBase.ROOM_ORIGIN
	return ClimbKit.flight(base, HALF_W, ROWS, ROW_D, ROW_RISE, LIP)


static func top_z(local: bool = false) -> float:
	return ClimbKit.top_z(flight(local))


## Height of the landing on top (world and local alike: the room sits on y = 0).
static func top_y() -> float:
	return ClimbKit.landing_y(flight(true)) + WalkableLogicBase.ROOM_ORIGIN.y


## Height of the walking surface under world `z`.
static func surface_y(z: float) -> float:
	return ClimbKit.surface_y(flight(), z)


## Lucky's podium (local): on the landing ("board"), in the apron's west corner ("towers").
static func lucky_spot(variant: String = "board") -> Vector3:
	if variant == "towers":
		return Vector3(-8.3, 0.3, 3.8)
	return Vector3(-5.4, top_y(), top_z(true) - LANDING_D + 1.6)


## World-space description for the server: {arena, gallery, spawns, spawn_yaws, gallery_spots,
## axis: [from, to], finish: AABB, finish_spots}. Cached: don't modify the result.
static func layout(variant: String = "board") -> Dictionary:
	if not _layouts.has(variant):
		_layouts[variant] = _make_layout(variant)
	return _layouts[variant]


static func _make_layout(variant: String) -> Dictionary:
	var o: Vector3 = WalkableLogicBase.ROOM_ORIGIN
	var spawns: Array[Vector3] = []
	var yaws: Array[float] = []
	for i: int in MAX_SPOTS:
		var slot: int = [3, 4, 2, 5, 1, 6, 0, 7][i]
		spawns.append(o + Vector3(-5.6 + 1.6 * float(slot), 0.0, SPAWN_Z))
		yaws.append(0.0)  # facing up the climb (-z)
	var spots: Array[Vector3] = []
	for i: int in MAX_SPOTS:
		spots.append(o + Vector3(-7.0 + 2.0 * float(i), GALLERY_H, GALLERY_Z + 1.6 + (0.5 if i % 2 == 1 else 0.0)))
	var gallery := AABB(o + Vector3(-HALL_HALF_X + 0.2, GALLERY_H - 0.6, GALLERY_Z + 0.2), Vector3((HALL_HALF_X - 0.2) * 2.0, 4.5, BACK_Z - GALLERY_Z - 0.4))
	if variant == "towers":
		var c: Vector3 = o + ChipTowers.pad_center()
		var far: float = o.z + ChipTowers.FAR_Z + 0.2
		var tower_arena := AABB(Vector3(o.x - HALL_HALF_X + 0.2, o.y - 1.0, far), Vector3((HALL_HALF_X - 0.2) * 2.0, TOWER_TOP_Y + 8.0, o.z + GALLERY_Z - 0.2 - far))
		var t_axis: Array[Vector3] = [Vector3(c.x, o.y, c.z), c]
		return {"arena": tower_arena, "gallery": gallery, "spawns": spawns, "spawn_yaws": yaws, "gallery_spots": spots,
			"axis": t_axis, "finish": ChipTowers.finish_box(o), "finish_spots": ChipTowers.finish_spots(o)}
	var tz: float = top_z(true)
	var ty: float = top_y()
	var arena := AABB(o + Vector3(-HALF_W + 0.1, -1.0, tz - LANDING_D + 0.2), Vector3((HALF_W - 0.1) * 2.0, ty + 7.0, APRON_Z - tz + LANDING_D - 0.2))
	var finish := AABB(o + Vector3(-HALF_W + 0.1, ty - 0.4, tz - LANDING_D + 0.2), Vector3((HALF_W - 0.1) * 2.0, 4.0, LANDING_D - 0.2))
	var fspots: Array[Vector3] = []
	for i: int in MAX_SPOTS:
		fspots.append(o + Vector3(-4.2 + 1.2 * float(i), ty, tz - LANDING_D + 1.6 + (0.6 if i % 2 == 1 else 0.0)))
	# The climb axis: the bottom edge on the floor to the landing's lip.
	var axis: Array[Vector3] = [o, o + Vector3(0, ty, tz)]
	return {"arena": arena, "gallery": gallery, "spawns": spawns, "spawn_yaws": yaws, "gallery_spots": spots, "axis": axis, "finish": finish, "finish_spots": fspots}


## Climb progress of world `pos` (0 at the bottom edge, 1 at the top).
static func progress(pos: Vector3, variant: String = "board") -> float:
	var ax: Array = layout(variant)["axis"]
	return ClimbKit.height_of(ax[0], ax[1], pos)


## True if world `pos` stands on top (the finish box: the landing).
static func on_top(pos: Vector3, variant: String = "board") -> bool:
	return (layout(variant)["finish"] as AABB).has_point(pos)


## Chute fields in world coordinates: [row, x0, x1].
static func chute_fields() -> Array:
	var ox: float = WalkableLogicBase.ROOM_ORIGIN.x
	var out: Array = []
	for c: Array in CHUTES:
		out.append([int(c[0]), ox + COL_X[int(c[1])], ox + COL_X[int(c[1]) + 1]])
	return out


## True if world `pos` stands in a slide chute.
static func in_chute(pos: Vector3) -> bool:
	return ClimbKit.in_field(flight(), chute_fields(), pos)


## Number printed on a field (row, column 1..3), 0 on the top row.
static func field_number(row: int, col: int) -> int:
	return 0 if row >= ROWS - 1 else row * 3 + col


# --- Build --------------------------------------------------------------------------------------

## Builds the room under `parent` (at the world origin) at `WalkableLogicBase.ROOM_ORIGIN`.
static func build(parent: Node3D, variant: String = "board") -> Node3D:
	var root := Node3D.new()
	root.name = "ClimbRoom"
	parent.add_child(root)
	root.position = WalkableLogicBase.ROOM_ORIGIN
	var brass: StandardMaterial3D = VaultArena._tex("brass", 1.2, Color(1.0, 0.86, 0.6), 0.85, 0.32)
	var wall_h: float = (top_y() if variant == "board" else TOWER_TOP_Y) + 9.0
	_shell(root, brass, wall_h, variant)
	_apron(root, brass, variant)
	_gallery(root, brass)
	if variant == "towers":
		ChipTowers.build(root, brass, wall_h)
		_tower_lucky_podium(root, brass)
	if variant == "board":
		_board(root, brass)
		_landing(root, brass)
		_gantry(root, brass)
		_board_lights(root, brass)
	_lights(root, brass)
	return root


static func _shell(root: Node3D, brass: Material, wall_h: float, variant: String) -> void:
	var far: float = top_z(true) - LANDING_D - 0.1 if variant == "board" else ChipTowers.FAR_Z - 0.1
	var len_z: float = BACK_Z - far
	var mid_z: float = (BACK_Z + far) * 0.5
	var carpet: Material = VaultArena._tex("casino_carpet", 2.5, Color(0.62, 0.42, 0.4), 0.0, 0.95)
	var paper: StandardMaterial3D = VaultArena._tex("damask_wallpaper", 1.8, Color(0.42, 0.2, 0.2), 0.0, 0.85)
	var panels: StandardMaterial3D = VaultArena._tex("wooden_panels", 1.4, Color(0.55, 0.38, 0.28), 0.0, 0.6)
	var ceiling: StandardMaterial3D = VaultArena._tex("coffered_ceiling", 3.0, Color(0.45, 0.36, 0.3), 0.0, 0.8)
	var wood: StandardMaterial3D = GreyboxKit.material(WALNUT_DARK, 0.0, 0.55)
	var w: float = HALL_HALF_X * 2.0
	VaultArena._solid(root, Vector3(w + 1.0, 0.4, len_z + 1.0), Vector3(0, -0.2, mid_z), carpet, "Floor")
	VaultArena._solid(root, Vector3(w + 1.0, 0.4, len_z + 1.0), Vector3(0, wall_h + 0.2, mid_z), ceiling, "Ceiling")
	VaultArena._solid(root, Vector3(WALL_T, wall_h, len_z + 1.0), Vector3(-HALL_HALF_X - WALL_T * 0.5, wall_h * 0.5, mid_z), paper, "WallW")
	VaultArena._solid(root, Vector3(WALL_T, wall_h, len_z + 1.0), Vector3(HALL_HALF_X + WALL_T * 0.5, wall_h * 0.5, mid_z), paper, "WallE")
	VaultArena._solid(root, Vector3(w, wall_h, WALL_T), Vector3(0, wall_h * 0.5, far - WALL_T * 0.5), paper, "WallFar")
	VaultArena._solid(root, Vector3(w, wall_h, WALL_T), Vector3(0, wall_h * 0.5, BACK_Z + WALL_T * 0.5), paper, "WallBack")
	for side: float in [-1.0, 1.0]:
		var x: float = side * (HALL_HALF_X - 0.04)
		VaultArena._vis(root, Vector3(0.08, 1.4, len_z), Vector3(x, 0.7, mid_z), panels)
		VaultArena._vis(root, Vector3(0.12, 0.06, len_z), Vector3(x - side * 0.02, 1.42, mid_z), brass)
		VaultArena._vis(root, Vector3(0.2, 0.3, len_z), Vector3(x - side * 0.06, wall_h - 0.15, mid_z), wood)
	VaultArena._vis(root, Vector3(w, 1.4, 0.08), Vector3(0, 0.7, BACK_Z - 0.04), panels)
	VaultArena._vis(root, Vector3(w, 0.06, 0.12), Vector3(0, 1.42, BACK_Z - 0.06), brass)
	# Full-height marble pilasters along the long walls, gilt frames climbing between them.
	var marble: StandardMaterial3D = GreyboxKit.material(VaultArena.MARBLE.darkened(0.12), 0.0, 0.45)
	var z: float = 6.0
	var i: int = 0
	while z > far + 2.0:
		for side: float in [-1.0, 1.0]:
			VaultArena._vis(root, Vector3(0.5, wall_h, 0.9), Vector3(side * (HALL_HALF_X - 0.25), wall_h * 0.5, z), marble)
			VaultArena._vis(root, Vector3(0.62, 0.3, 1.02), Vector3(side * (HALL_HALF_X - 0.25), 0.15, z), marble)
			if z > far + 6.0 and PropModels.has(&"picture"):
				var pic: Node3D = PropModels.make(&"picture", 0.0, 2.2)
				var fz: float = z - 3.5
				pic.position = Vector3(side * (HALL_HALF_X - 0.06), (ClimbKit.surface_y(flight(true), fz) if variant == "board" else 2.0) + 3.6, fz)
				pic.rotation = Vector3(0, -side * PI * 0.5, 0)
				root.add_child(pic)
		z -= 7.0
		i += 1


## The start apron: carpet with the columns' 2:1 boxes painted in front of the board and a brass
## gutter grate where the hazards drop out at the bottom edge.
static func _apron(root: Node3D, brass: Material, variant: String = "board") -> void:
	var felt: StandardMaterial3D = GreyboxKit.material(Palette.FELT_GREEN.lightened(0.04), 0.0, 0.95)
	var top := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(HALF_W * 2.0, 3.0)
	top.mesh = pm
	top.material_override = felt
	top.position = Vector3(0, 0.01, 2.6)
	root.add_child(top)
	if variant == "towers":
		# A gold start line at the net's edge and the climb's name on the felt.
		VaultArena._vis(root, Vector3(HALF_W * 2.0, 0.03, 0.14), Vector3(0, 0.015, 1.15), GreyboxKit.material(Palette.VIP_GOLD, 0.85, 0.25))
		_tile(root, Transform3D(Basis.IDENTITY, Vector3(0, 0.02, 2.5)), Vector2(6.0, 1.4), Palette.FELT_GREEN.darkened(0.25), "JACKPOT CLIMB", 90)
	else:
		_board_apron(root, brass)
	# Velvet ropes keep beans off the aisles beside the board.
	var velvet: StandardMaterial3D = VaultArena._tex("velvet", 1.0, Palette.VIP_BURGUNDY.lightened(0.1), 0.0, 0.9)
	for side: float in [-1.0, 1.0]:
		for px: float in [HALF_W + 0.3, HALL_HALF_X - 0.4]:
			var p := Vector3(side * px, 0.0, 0.6)
			ParlorRoom._cyl(root, 0.05, 0.95, p + Vector3(0, 0.475, 0), brass, 10)
			ParlorRoom._cyl(root, 0.2, 0.05, p + Vector3(0, 0.025, 0), brass, 14)
			VaultArena._sphere(root, 0.08, p + Vector3(0, 0.98, 0), brass)
		VaultArena._vis(root, Vector3(HALL_HALF_X - HALF_W - 0.7, 0.06, 0.06), Vector3(side * (HALF_W + HALL_HALF_X - 0.1) * 0.5, 0.8, 0.6), velvet)
		ClimbKit.guard(root, Vector3(HALL_HALF_X - HALF_W, 3.0, 0.4), Vector3(side * (HALF_W + HALL_HALF_X) * 0.5, 1.5, 0.6), "AisleGuard")


## Lucky's podium in the apron's west corner (towers): walnut with a brass cap.
static func _tower_lucky_podium(root: Node3D, brass: Material) -> void:
	var lp: Vector3 = lucky_spot("towers")
	VaultArena._solid(root, Vector3(1.4, 0.3, 1.3), Vector3(lp.x, 0.15, lp.z), GreyboxKit.material(WALNUT, 0.0, 0.45), "LuckyPodium")
	VaultArena._vis(root, Vector3(1.46, 0.04, 1.36), Vector3(lp.x, 0.3, lp.z), brass)


## The board's apron: the columns' 2:1 boxes and the gutter grate where the hazards drop out.
static func _board_apron(root: Node3D, brass: Material) -> void:
	for c: int in 3:
		var x0: float = COL_X[c + 1]
		var x1: float = COL_X[c + 2]
		_tile(root, Transform3D(Basis.IDENTITY, Vector3((x0 + x1) * 0.5, 0.02, 2.4)), Vector2(x1 - x0 - 0.2, 1.6), Palette.FELT_GREEN.darkened(0.25), "2:1", 110)
	# The gutter: a dark trough under a brass grate across the bottom edge.
	VaultArena._vis(root, Vector3(HALF_W * 2.0, 0.02, 1.0), Vector3(0, 0.012, 0.55), GreyboxKit.material(Palette.CASINO_BLACK, 0.0, 0.8))
	var x: float = -HALF_W + 0.1
	while x < HALF_W:
		VaultArena._vis(root, Vector3(0.06, 0.05, 1.0), Vector3(x, 0.035, 0.55), brass)
		x += 0.3
	VaultArena._vis(root, Vector3(HALF_W * 2.0, 0.06, 0.08), Vector3(0, 0.04, 1.06), brass)


static func _gallery(root: Node3D, brass: Material) -> void:
	var depth: float = BACK_Z - GALLERY_Z
	var mid: float = GALLERY_Z + depth * 0.5
	VaultArena._solid(root, Vector3(HALL_HALF_X * 2.0, GALLERY_H, depth), Vector3(0, GALLERY_H * 0.5, mid), GreyboxKit.material(WALNUT_DARK, 0.0, 0.5), "Gallery")
	var rug := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(HALL_HALF_X * 2.0 - 0.6, depth - 0.5)
	rug.mesh = pm
	rug.material_override = VaultArena._tex("velvet", 1.5, Palette.VIP_BURGUNDY.lightened(0.15), 0.0, 0.9)
	rug.position = Vector3(0, GALLERY_H + 0.012, mid + 0.1)
	root.add_child(rug)
	VaultArena._vis(root, Vector3(HALL_HALF_X * 2.0, 0.08, 0.08), Vector3(0, GALLERY_H + 1.0, GALLERY_Z + 0.08), brass)
	VaultArena._vis(root, Vector3(HALL_HALF_X * 2.0, 0.05, 0.05), Vector3(0, GALLERY_H + 0.5, GALLERY_Z + 0.08), brass)
	var x: float = -HALL_HALF_X + 0.4
	while x < HALL_HALF_X:
		VaultArena._vis(root, Vector3(0.06, 1.0, 0.06), Vector3(x, GALLERY_H + 0.5, GALLERY_Z + 0.08), brass)
		x += 0.8
	VaultArena._vis(root, Vector3(HALL_HALF_X * 2.0, 0.1, 0.12), Vector3(0, GALLERY_H - 0.05, GALLERY_Z + 0.02), brass)
	ClimbKit.guard(root, Vector3(HALL_HALF_X * 2.0, 3.6, 0.3), Vector3(0, GALLERY_H + 1.8, GALLERY_Z), "GalleryBarrier")
	if PropModels.has(&"couch"):
		for cx: float in [-6.0, 0.0, 6.0]:
			var couch: Node3D = PropModels.make(&"couch", 0.0, 2.4)
			couch.position = Vector3(cx, GALLERY_H, BACK_Z - 0.75)
			couch.rotation.y = PI
			root.add_child(couch)


# --- The board ----------------------------------------------------------------------------------

static func _board(root: Node3D, brass: Material) -> void:
	var f: Dictionary = flight(true)
	var walnut: StandardMaterial3D = VaultArena._tex("wooden_panels", 1.6, Color(0.62, 0.42, 0.3), 0.0, 0.55)
	ClimbKit.build_flight(root, f, walnut, brass)
	var felt: StandardMaterial3D = GreyboxKit.material(Palette.FELT_GREEN.lightened(0.04), 0.0, 0.95)
	var line: StandardMaterial3D = GreyboxKit.material(Palette.CREAM.darkened(0.08), 0.0, 0.8)
	var trough: StandardMaterial3D = GreyboxKit.material(Palette.WARM_GOLD.lightened(0.15), 0.9, 0.12)
	var chevron: StandardMaterial3D = GreyboxKit.material(Palette.VIP_BURGUNDY, 0.0, 0.6)
	var chutes: Dictionary = {}
	for c: Array in CHUTES:
		chutes[Vector2i(int(c[0]), int(c[1]))] = true
	var length: float = ClimbKit.tread_length(f)
	var print := Node3D.new()
	print.name = "Layout"
	root.add_child(print)
	for row: int in ROWS:
		var frame: Transform3D = ClimbKit.tread_frame(f, row)
		var up: Vector3 = frame.basis.y
		# The felt over the whole tread, a cream line round every field.
		_plane(print, frame.translated(up * 0.006), Vector2(HALF_W * 2.0 - 0.02, length - 0.02), felt)
		for col: int in 5:
			if chutes.has(Vector2i(row, col)):
				ClimbKit.build_chute(print, f, row, COL_X[col] + 0.06, COL_X[col + 1] - 0.06, trough, brass, chevron)
				continue
			var x0: float = COL_X[col]
			var x1: float = COL_X[col + 1]
			var at: Transform3D = Transform3D(frame.basis, frame.origin + frame.basis.x * ((x0 + x1) * 0.5))
			if row == ROWS - 1:
				continue  # the zero spans the number columns (below)
			_plane(print, at.translated(up * 0.01), Vector2(x1 - x0 - 0.1, length - 0.12), line)
			if col >= 1 and col <= 3:
				var n: int = field_number(row, col)
				var tint: Color = Palette.CASINO_RED.darkened(0.1) if n in RouletteLogic.RED else Palette.CASINO_BLACK.lightened(0.06)
				_tile(print, at.translated(up * 0.014), Vector2(x1 - x0 - 0.3, length - 0.32), tint, str(n), 150)
			else:
				_plane(print, at.translated(up * 0.014), Vector2(x1 - x0 - 0.3, length - 0.32), felt)
		if row == ROWS - 1:
			_plane(print, frame.translated(up * 0.01), Vector2(COL_X[4] - COL_X[1] - 0.1, length - 0.12), line)
			_tile(print, frame.translated(up * 0.014), Vector2(COL_X[4] - COL_X[1] - 0.3, length - 0.32), Palette.FELT_GREEN.lightened(0.18), "0", 190)
	# Outside bets up the strips: dozens west (4 rows each), even money east (2 rows each).
	var dozens: Array[String] = ["1st 12", "2nd 12", "3rd 12"]
	for d: int in 3:
		_strip_label(print, f, d * 4 + 1, -5.75, dozens[d], Palette.CREAM)
	var even: Array[String] = ["1-18", "EVEN", "RED", "BLACK", "ODD", "19-36"]
	for e: int in 6:
		var row: int = e * 2 + (1 if Vector2i(e * 2, 4) in chutes else 0)
		var c: Color = Palette.CREAM
		if even[e] == "RED":
			c = Palette.CASINO_RED.lightened(0.15)
		elif even[e] == "BLACK":
			c = Palette.CASINO_BLACK
		_strip_label(print, f, row, 5.75, even[e], c)
	# Cheek rails up both edges: walnut beams with a brass cap, invisible guards to the ceiling.
	var cheek: StandardMaterial3D = GreyboxKit.material(WALNUT, 0.0, 0.42)
	var tz: float = top_z(true)
	var ty: float = top_y()
	for side: float in [-1.0, 1.0]:
		var x: float = side * (HALF_W + 0.18)
		var from := Vector3(x, 1.1, 0.0)
		var to := Vector3(x, ty + 1.1, tz)
		_beam(root, from, to, Vector2(0.36, 0.5), cheek)
		_beam(root, from + Vector3(0, 0.28, 0), to + Vector3(0, 0.28, 0), Vector2(0.42, 0.08), brass)
		# A walnut skirt down to the floor under the rail.
		var skirt := MeshInstance3D.new()
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_smooth_group(0xFFFFFFFF)
		ClimbKit._quad(st, Vector3(x, 0, 0.0), Vector3(x, 0, tz), Vector3(x, ty + 0.9, tz), Vector3(x, 0.9, 0.0))
		st.generate_normals()
		skirt.mesh = st.commit()
		skirt.material_override = cheek
		root.add_child(skirt)
		ClimbKit.guard(root, Vector3(0.6, ty + 6.0, -tz + 0.2), Vector3(side * (HALF_W + 0.3), (ty + 6.0) * 0.5, tz * 0.5), "EdgeGuard")


## A big label lying up a side strip, reading uphill (rotated a quarter so it runs along the strip).
static func _strip_label(parent: Node3D, f: Dictionary, row: int, x: float, text: String, color: Color) -> void:
	var frame: Transform3D = ClimbKit.tread_frame(f, row)
	var l := Label3D.new()
	l.text = text
	l.font = Vfx.font()
	l.font_size = 120
	l.pixel_size = 0.0062
	l.modulate = color
	l.outline_size = 0
	l.shaded = true
	l.double_sided = false
	l.transform = Transform3D(frame.basis * Basis(Vector3.RIGHT, -PI * 0.5) * Basis(Vector3.BACK, PI * 0.5), frame.origin + frame.basis.x * x + frame.basis.y * 0.03)
	parent.add_child(l)


## The landing on top: a walnut block with a felt top, a gold finish line along its edge, the
## WINNER rail at the back, Lucky's podium and the room's sign on the far wall.
static func _landing(root: Node3D, brass: Material) -> void:
	var tz: float = top_z(true)
	var ty: float = top_y()
	var mid_z: float = tz - LANDING_D * 0.5
	VaultArena._solid(root, Vector3(HALL_HALF_X * 2.0, ty, LANDING_D), Vector3(0, ty * 0.5, mid_z), GreyboxKit.material(WALNUT_DARK, 0.0, 0.5), "Landing")
	var top := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(HALL_HALF_X * 2.0 - 0.4, LANDING_D - 0.3)
	top.mesh = pm
	top.material_override = VaultArena._tex("velvet", 1.2, Palette.VIP_BURGUNDY.lightened(0.1), 0.0, 0.9)
	top.position = Vector3(0, ty + 0.01, mid_z - 0.1)
	root.add_child(top)
	var gold: StandardMaterial3D = GreyboxKit.material(Palette.VIP_GOLD, 0.9, 0.2)
	VaultArena._vis(root, Vector3(HALF_W * 2.0, 0.03, 0.3), Vector3(0, ty + 0.02, tz - 0.3), gold)
	var nose := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.08
	cm.bottom_radius = 0.08
	cm.height = HALL_HALF_X * 2.0
	nose.mesh = cm
	nose.material_override = gold
	nose.rotation.z = PI * 0.5
	nose.position = Vector3(0, ty - 0.03, tz - 0.02)
	root.add_child(nose)
	# The WINNER rail: a gold balustrade at the back with a lit sign over it.
	var rz: float = tz - LANDING_D + 0.5
	VaultArena._vis(root, Vector3(HALF_W * 2.0, 0.12, 0.12), Vector3(0, ty + 1.05, rz), gold)
	VaultArena._vis(root, Vector3(HALF_W * 2.0, 0.08, 0.08), Vector3(0, ty + 0.5, rz), gold)
	var x: float = -HALF_W
	while x <= HALF_W + 0.01:
		VaultArena._vis(root, Vector3(0.07, 1.05, 0.07), Vector3(x, ty + 0.52, rz), gold)
		VaultArena._sphere(root, 0.09, Vector3(x, ty + 1.16, rz), gold)
		x += 0.7
	var sign := Label3D.new()
	sign.text = "WINNER"
	sign.font = Vfx.font()
	sign.font_size = 160
	sign.pixel_size = 0.016
	sign.modulate = Palette.VIP_GOLD
	sign.outline_modulate = Palette.CASINO_BLACK
	sign.outline_size = 10
	sign.shaded = false
	sign.position = Vector3(0, ty + 3.4, tz - LANDING_D + 0.12)
	root.add_child(sign)
	var under := Label3D.new()
	under.text = "FIRST TO THE TOP"
	under.font = Vfx.font()
	under.font_size = 64
	under.pixel_size = 0.012
	under.modulate = Palette.CREAM
	under.outline_size = 0
	under.shaded = true
	under.position = Vector3(0, ty + 2.0, tz - LANDING_D + 0.12)
	root.add_child(under)
	var title := Label3D.new()
	title.text = "DODGE THE DICE"
	title.font = Vfx.font()
	title.font_size = 128
	title.pixel_size = 0.02
	title.modulate = Palette.VIP_GOLD
	title.outline_size = 0
	title.shaded = true
	title.position = Vector3(0, ty + 6.6, tz - LANDING_D + 0.12)
	root.add_child(title)
	VaultArena._vis(root, Vector3(16.0, 0.08, 0.08), Vector3(0, ty + 5.4, tz - LANDING_D + 0.1), brass)
	# Lucky's podium.
	var lp: Vector3 = lucky_spot()
	VaultArena._vis(root, Vector3(1.6, 0.3, 1.4), Vector3(lp.x, ty + 0.15, lp.z), GreyboxKit.material(WALNUT, 0.0, 0.45))
	VaultArena._vis(root, Vector3(1.66, 0.04, 1.46), Vector3(lp.x, ty + 0.3, lp.z), brass)


## The hazard gantry over the top row: brass posts, a crossbeam and five hoppers.
static func _gantry(root: Node3D, brass: Material) -> void:
	var tz: float = top_z(true)
	var ty: float = top_y()
	var z: float = tz + 0.6
	var beam_y: float = ty + HOPPER_DROP + 2.4
	for side: float in [-1.0, 1.0]:
		ParlorRoom._cyl(root, 0.22, beam_y - ty + 0.4, Vector3(side * (HALF_W + 0.55), ty + (beam_y - ty) * 0.5 - 0.6, z), brass, 16)
		VaultArena._sphere(root, 0.3, Vector3(side * (HALF_W + 0.55), beam_y + 0.4, z), brass)
	VaultArena._vis(root, Vector3(HALF_W * 2.0 + 1.4, 0.36, 0.36), Vector3(0, beam_y, z), brass)
	var walnut: StandardMaterial3D = GreyboxKit.material(WALNUT, 0.0, 0.4)
	for hx: float in HOPPER_X:
		var h := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.95
		cone.bottom_radius = 0.38
		cone.height = 1.3
		cone.radial_segments = 20
		h.mesh = cone
		h.material_override = brass
		h.position = Vector3(hx, beam_y - 1.0, z)
		root.add_child(h)
		ParlorRoom._cyl(root, 0.4, 0.3, Vector3(hx, beam_y - 1.75, z), walnut, 20)
		VaultArena._vis(root, Vector3(0.1, 0.6, 0.1), Vector3(hx, beam_y - 0.2, z), brass)


static func _board_lights(root: Node3D, brass: Material) -> void:
	var f: Dictionary = flight(true)
	var glow: StandardMaterial3D = Vfx.glow_material(Color(1.0, 0.85, 0.55))
	for z: float in [-4.0, -12.5, -21.0, -29.5]:
		var y: float = ClimbKit.surface_y(f, z) + 7.5
		var ch := Node3D.new()
		ch.name = "Chandelier"
		ch.position = Vector3(0, y, z)
		root.add_child(ch)
		var ring := Node3D.new()
		ch.add_child(ring)
		VaultArena._ring(ring, 1.6, 0.08, 0.0, brass)
		ring.scale = Vector3(1.0, 10.0, 1.0)
		for i: int in 10:
			var a: float = TAU * float(i) / 10.0
			var p := Vector3(sin(a) * 1.6, 0.08, cos(a) * 1.6)
			var bulb: MeshInstance3D = VaultArena._sphere(ch, 0.07, p + Vector3(0, 0.1, 0), null)
			bulb.material_override = glow
		VaultArena._vis(ch, Vector3(0.04, 3.0, 0.04), Vector3(0, 1.5, 0), brass)
		GreyboxKit.lamp(root, Vector3(0, y - 0.6, z), 1.5, 13.0, LAMP)
	var spot := SpotLight3D.new()
	spot.name = "WinnerSpot"
	spot.light_color = Color(1.0, 0.86, 0.6)
	spot.light_energy = 3.0
	spot.spot_range = 14.0
	spot.spot_angle = 50.0
	spot.position = Vector3(0, top_y() + 9.0, top_z(true) - LANDING_D * 0.5)
	spot.rotation.x = -PI * 0.5
	root.add_child(spot)


static func _lights(root: Node3D, _brass: Material) -> void:
	GreyboxKit.lamp(root, Vector3(0, 5.5, 3.0), 1.3, 12.0, LAMP)
	for gx: float in [-6.0, 6.0]:
		GreyboxKit.lamp(root, Vector3(gx, 5.0, BACK_Z - 1.8), 0.7, 7.0, LAMP)
	var fill := OmniLight3D.new()
	fill.position = Vector3(0, 18.0, -16.0)
	fill.light_color = Color(1.0, 0.86, 0.7)
	fill.light_energy = 0.6
	fill.omni_range = 40.0
	root.add_child(fill)


# --- Helpers --------------------------------------------------------------------------------------

static func _plane(parent: Node3D, xf: Transform3D, size: Vector2, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size
	mi.mesh = pm
	mi.material_override = mat
	mi.transform = xf
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## A coloured field with its label lying on it, reading uphill.
static func _tile(parent: Node3D, xf: Transform3D, size: Vector2, color: Color, text: String, font_size: int) -> void:
	_plane(parent, xf, size, GreyboxKit.material(color, 0.0, 0.85))
	var l := Label3D.new()
	l.text = text
	l.font = Vfx.font()
	l.font_size = font_size
	l.pixel_size = 0.0075
	l.modulate = Palette.CREAM
	l.outline_size = 0
	l.shaded = true
	l.double_sided = false
	l.transform = Transform3D(xf.basis * Basis(Vector3.RIGHT, -PI * 0.5), xf.origin + xf.basis.y * 0.004)
	parent.add_child(l)


## A box from `from` to `to` (visual).
static func _beam(parent: Node3D, from: Vector3, to: Vector3, section: Vector2, mat: Material) -> MeshInstance3D:
	var d: Vector3 = to - from
	var mi: MeshInstance3D = VaultArena._vis(parent, Vector3(section.x, section.y, d.length()), (from + to) * 0.5, mat)
	mi.basis = Basis.looking_at(-d.normalized(), Vector3.UP)
	return mi
