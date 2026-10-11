class_name ParlorRoom
extends RefCounted
## The card parlor of Last Seat at the Table: a warm, wood-panelled room with damask wallpaper, a
## herringbone parquet floor and a round blackjack table (green felt, padded burgundy rail, brass
## foot ring) under a brass chandelier in the middle. The stools of the game live around the table
## (the stage places them, `stool_ring` says where). At the far wall Lucky works a gramophone on a
## little dais; at the near end, behind a brass railing, a raised gallery with couches holds the
## beans who are out. Pictures, curtains, sconces and two marble columns dress the walls.
##
## Like `VaultArena`: `layout()` is pure data for the server (bounds, spawns, gallery spots in world
## coordinates around `WalkableLogicBase.ROOM_ORIGIN`), `build(parent)` makes the nodes. Local
## axes: -z is the gramophone wall, +z the gallery.

const HALF_X: float = 8.0
const FAR_Z: float = -8.0
const BACK_Z: float = 9.6
const GALLERY_Z: float = 6.4
const GALLERY_H: float = 1.0
const WALL_H: float = 5.2
const WALL_T: float = 0.5
## The round table: centre (local), felt radius, rail radius, height of the felt.
const TABLE_CENTER: Vector3 = Vector3(0, 0, -0.8)
const FELT_RADIUS: float = 1.45
const RAIL_RADIUS: float = 1.62
const TABLE_TOP: float = 0.93
## Stools stand on this ring round the table centre (seat top at `SEAT_HEIGHT`); while the music
## plays they hide under the table at `TUCK_RADIUS`.
const STOOL_RING: float = 2.6
const TUCK_RADIUS: float = 0.9
const SEAT_HEIGHT: float = 0.5
## Beans start on this ring, walking round the table (counter-clockwise from above).
const SPAWN_RADIUS: float = 4.0
## The gramophone dais by the far wall, Lucky's spot next to the gramophone.
const DAIS_Z: float = -7.2
const DAIS_H: float = 0.3
const GRAMOPHONE: Vector3 = Vector3(-0.8, DAIS_H, -7.25)
const LUCKY_SPOT: Vector3 = Vector3(0.9, DAIS_H, -7.1)
const MAX_SPOTS: int = 8

const FELT: Color = Color("#275E49")
const RAIL: Color = Color("#681F2C")
const WOOD: Color = Color("#3A2A1E")
const WOOD_WARM: Color = Color("#5A3A26")
const LAMP: Color = Color(1.0, 0.8, 0.52)


## World-space description for the server.
static func layout() -> Dictionary:
	var o: Vector3 = WalkableLogicBase.ROOM_ORIGIN
	var c: Vector3 = o + TABLE_CENTER
	var spawns: Array[Vector3] = []
	var yaws: Array[float] = []
	for i: int in MAX_SPOTS:
		var slot: int = [0, 4, 2, 6, 1, 5, 3, 7][i]
		var a: float = TAU * (float(slot) + 0.5) / float(MAX_SPOTS)
		var local := Vector3(sin(a) * SPAWN_RADIUS, 0.0, cos(a) * SPAWN_RADIUS)
		spawns.append(c + local)
		# Facing along the ring (counter-clockwise seen from above), ready to wander round the table.
		var tangent := Vector3(cos(a), 0.0, -sin(a))
		yaws.append(atan2(-tangent.x, -tangent.z))
	var spots: Array[Vector3] = []
	for i: int in MAX_SPOTS:
		var x: float = -5.6 + 11.2 * float(i) / float(MAX_SPOTS - 1)
		spots.append(o + Vector3(x, GALLERY_H, GALLERY_Z + 1.2 + (0.35 if i % 2 == 1 else 0.0)))
	var arena := AABB(o + Vector3(-HALF_X + 0.2, -1.0, FAR_Z + 0.2), Vector3((HALF_X - 0.2) * 2.0, 5.0, GALLERY_Z - FAR_Z - 0.2))
	var gallery := AABB(o + Vector3(-HALF_X + 0.2, GALLERY_H - 0.6, GALLERY_Z + 0.2), Vector3((HALF_X - 0.2) * 2.0, 4.5, BACK_Z - GALLERY_Z - 0.4))
	return {"arena": arena, "gallery": gallery, "spawns": spawns, "spawn_yaws": yaws, "gallery_spots": spots}


## World floor positions of `count` stools evenly round the table, the first at angle `offset`.
static func stool_ring(count: int, offset: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var c: Vector3 = table_center()
	for i: int in count:
		var a: float = offset + TAU * float(i) / float(maxi(count, 1))
		out.append(c + Vector3(sin(a), 0.0, cos(a)) * STOOL_RING)
	return out


static func table_center() -> Vector3:
	return WalkableLogicBase.ROOM_ORIGIN + TABLE_CENTER


## Yaw that faces the table from `at` (yaw 0 faces -z).
static func yaw_to_table(at: Vector3) -> float:
	var d: Vector3 = table_center() - at
	return atan2(-d.x, -d.z)


## Where a bean stands up next to the stool at `stool` (a step out, away from the table).
static func stand_spot(stool: Vector3) -> Vector3:
	var out: Vector3 = stool - table_center()
	out.y = 0.0
	out = out.normalized() if out.length() > 0.01 else Vector3.BACK
	return Vector3(stool.x, 0.0, stool.z) + out * 0.8


## Builds the parlor under `parent` (at the world origin) at `WalkableLogicBase.ROOM_ORIGIN`.
static func build(parent: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "ParlorRoom"
	parent.add_child(root)
	root.position = WalkableLogicBase.ROOM_ORIGIN
	var brass: StandardMaterial3D = VaultArena._tex("brass", 1.2, Color(1.0, 0.86, 0.6), 0.85, 0.32)
	var wood: StandardMaterial3D = GreyboxKit.material(WOOD, 0.0, 0.55)
	_shell(root, brass, wood)
	_table(root, brass)
	_dais(root, brass, wood)
	_decor(root, brass)
	_gallery(root, brass)
	_lights(root, brass)
	return root


## A stool for the stage (visual only, no collision: beans run onto it): Patrick's bar stool on a
## brass ring base. Origin on the floor.
static func make_stool() -> Node3D:
	var s := Node3D.new()
	s.name = "Stool"
	if PropModels.has(&"seat"):
		var m: Node3D = PropModels.shade(PropModels.make(&"seat", SEAT_HEIGHT), 0.75)
		m.name = "Model"
		s.add_child(m)
	else:
		var cyl: Node3D = GreyboxKit.cylinder(s, 0.22, SEAT_HEIGHT, Vector3(0, SEAT_HEIGHT * 0.5, 0), Palette.CASINO_RED.darkened(0.3), "Model", false)
		cyl.name = "Model"
	return s


# --- Shell ------------------------------------------------------------------------------------

static func _shell(root: Node3D, brass: Material, wood: Material) -> void:
	var len_z: float = BACK_Z - FAR_Z
	var mid_z: float = (BACK_Z + FAR_Z) * 0.5
	var parquet: StandardMaterial3D = VaultArena._tex("herringbone_parquet", 2.0, Color(0.85, 0.72, 0.6), 0.0, 0.55)
	var paper: StandardMaterial3D = VaultArena._tex("damask_wallpaper", 1.6, Color(0.78, 0.36, 0.32), 0.0, 0.85)
	var panels: StandardMaterial3D = VaultArena._tex("wooden_panels", 1.4, Color(0.72, 0.52, 0.4), 0.0, 0.6)
	var ceiling: StandardMaterial3D = VaultArena._tex("coffered_ceiling", 3.0, Color(0.7, 0.6, 0.5), 0.0, 0.8)
	VaultArena._solid(root, Vector3(HALF_X * 2.0 + 1.0, 0.4, len_z + 1.0), Vector3(0, -0.2, mid_z), parquet, "Floor")
	VaultArena._solid(root, Vector3(HALF_X * 2.0 + 1.0, 0.4, len_z + 1.0), Vector3(0, WALL_H + 0.2, mid_z), ceiling, "Ceiling")
	VaultArena._solid(root, Vector3(WALL_T, WALL_H, len_z + 1.0), Vector3(-HALF_X - WALL_T * 0.5, WALL_H * 0.5, mid_z), paper, "WallW")
	VaultArena._solid(root, Vector3(WALL_T, WALL_H, len_z + 1.0), Vector3(HALF_X + WALL_T * 0.5, WALL_H * 0.5, mid_z), paper, "WallE")
	VaultArena._solid(root, Vector3(HALF_X * 2.0, WALL_H, WALL_T), Vector3(0, WALL_H * 0.5, FAR_Z - WALL_T * 0.5), paper, "WallFar")
	VaultArena._solid(root, Vector3(HALF_X * 2.0, WALL_H, WALL_T), Vector3(0, WALL_H * 0.5, BACK_Z + WALL_T * 0.5), paper, "WallBack")
	# Wood wainscot to 1.25 m with a brass cap, a dark skirting and a crown moulding.
	for side: float in [-1.0, 1.0]:
		var x: float = side * (HALF_X - 0.04)
		VaultArena._vis(root, Vector3(0.08, 1.25, len_z), Vector3(x, 0.625, mid_z), panels)
		VaultArena._vis(root, Vector3(0.12, 0.06, len_z), Vector3(x - side * 0.02, 1.27, mid_z), brass)
		VaultArena._vis(root, Vector3(0.12, 0.2, len_z), Vector3(x - side * 0.02, 0.1, mid_z), wood)
		VaultArena._vis(root, Vector3(0.2, 0.22, len_z), Vector3(x - side * 0.06, WALL_H - 0.11, mid_z), wood)
	for z_wall: float in [FAR_Z + 0.04, BACK_Z - 0.04]:
		var inward: float = 1.0 if z_wall < 0.0 else -1.0
		VaultArena._vis(root, Vector3(HALF_X * 2.0, 1.25, 0.08), Vector3(0, 0.625, z_wall), panels)
		VaultArena._vis(root, Vector3(HALF_X * 2.0, 0.06, 0.12), Vector3(0, 1.27, z_wall + inward * 0.02), brass)
		VaultArena._vis(root, Vector3(HALF_X * 2.0, 0.2, 0.12), Vector3(0, 0.1, z_wall + inward * 0.02), wood)
		VaultArena._vis(root, Vector3(HALF_X * 2.0, 0.22, 0.2), Vector3(0, WALL_H - 0.11, z_wall + inward * 0.06), wood)
	# A round burgundy carpet under the table and its ring of stools.
	var carpet: Material = LoungeDecor._carpet(Palette.VIP_BURGUNDY, Palette.VIP_BURGUNDY.darkened(0.3), 1.0) if Vfx.enabled() else GreyboxKit.material(Palette.VIP_BURGUNDY)
	var rug := MeshInstance3D.new()
	rug.name = "TableRug"
	var cm := CylinderMesh.new()
	cm.top_radius = 3.6
	cm.bottom_radius = 3.6
	cm.height = 0.02
	cm.radial_segments = 48
	rug.mesh = cm
	rug.material_override = carpet
	rug.position = TABLE_CENTER + Vector3(0, 0.01, 0)
	root.add_child(rug)
	var gold: StandardMaterial3D = GreyboxKit.material(Palette.WARM_GOLD, 0.85, 0.3)
	var ring_root := Node3D.new()
	ring_root.position = TABLE_CENTER
	root.add_child(ring_root)
	VaultArena._ring(ring_root, 3.5, 0.1, 0.025, gold)
	VaultArena._ring(ring_root, STOOL_RING, 0.04, 0.024, gold)


# --- The table --------------------------------------------------------------------------------

static func _table(root: Node3D, brass: Material) -> void:
	var t := Node3D.new()
	t.name = "CardTable"
	t.position = TABLE_CENTER
	root.add_child(t)
	# Collision: one cylinder the size of the rail.
	var solid: Node3D = GreyboxKit.cylinder(t, RAIL_RADIUS + 0.05, TABLE_TOP, Vector3(0, TABLE_TOP * 0.5, 0), WOOD, "TableBody")
	(solid.get_node(^"Mesh") as Node3D).visible = false
	var felt: StandardMaterial3D = GreyboxKit.material(FELT, 0.0, 0.85)
	var wood: StandardMaterial3D = GreyboxKit.material(WOOD, 0.0, 0.5)
	var rail: StandardMaterial3D = GreyboxKit.material(RAIL, 0.0, 0.55)
	_cyl(t, FELT_RADIUS, 0.04, Vector3(0, TABLE_TOP - 0.02, 0), felt, 48)
	_cyl(t, RAIL_RADIUS - 0.02, 0.16, Vector3(0, TABLE_TOP - 0.11, 0), wood, 48)  # apron
	var r := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = FELT_RADIUS - 0.04
	tm.outer_radius = RAIL_RADIUS + 0.06
	tm.rings = 48
	tm.ring_segments = 10
	r.mesh = tm
	r.material_override = rail
	r.scale = Vector3(1.0, 0.75, 1.0)
	r.position.y = TABLE_TOP + 0.02
	t.add_child(r)
	# Pedestal: a fat turned wood column on a brass-ringed foot.
	_cyl(t, 0.32, TABLE_TOP - 0.2, Vector3(0, (TABLE_TOP - 0.2) * 0.5, 0), wood, 20)
	_cyl(t, 0.75, 0.12, Vector3(0, 0.06, 0), wood, 28)
	_cyl(t, 0.78, 0.04, Vector3(0, 0.13, 0), brass, 28)
	_cyl(t, 0.36, 0.05, Vector3(0, TABLE_TOP - 0.24, 0), brass, 20)
	var foot := Node3D.new()
	foot.position.y = 0.28
	t.add_child(foot)
	VaultArena._ring(foot, 1.15, 0.05, 0.0, GreyboxKit.gold())
	# Felt print: a gold ring and the house rules, written round the dealer's spot.
	var gold: StandardMaterial3D = GreyboxKit.material(Palette.WARM_GOLD, 0.6, 0.4)
	var print_root := Node3D.new()
	print_root.position.y = TABLE_TOP + 0.003
	t.add_child(print_root)
	VaultArena._ring(print_root, 1.05, 0.025, 0.0, gold)
	VaultArena._ring(print_root, 0.55, 0.02, 0.0, gold)
	for line: Array in [["BLACKJACK PAYS 3 TO 2", 0.82, 0.0], ["LAST SEAT AT THE TABLE", 0.82, PI]]:
		var l := Label3D.new()
		l.text = line[0]
		l.font = Vfx.font()
		l.font_size = 40
		l.pixel_size = 0.0025
		l.modulate = Palette.VIP_GOLD
		l.outline_size = 0
		l.shaded = true
		l.rotation = Vector3(-PI * 0.5, float(line[2]), 0)
		l.position = Vector3(sin(float(line[2])), 0.002, cos(float(line[2]))) * float(line[1]) + Vector3(0, 0.002, 0)
		print_root.add_child(l)
	# A chip rack, a card shoe and a few chip stacks so it reads as a working table.
	VaultArena._vis(t, Vector3(0.7, 0.07, 0.22), Vector3(0, TABLE_TOP + 0.035, -0.95), GreyboxKit.material(Color("#1E1B19"), 0.2, 0.5))
	for i: int in 6:
		var chip_col: Color = [Palette.CASINO_RED, Palette.CREAM, Palette.FELT_GREEN.lightened(0.2), Palette.CASINO_BLACK, Palette.VIP_GOLD, Palette.CASINO_RED][i]
		_cyl(t, 0.035, 0.06, Vector3(-0.27 + 0.108 * float(i), TABLE_TOP + 0.09, -0.95), GreyboxKit.material(chip_col, 0.0, 0.5), 12)
	VaultArena._vis(t, Vector3(0.18, 0.12, 0.28), Vector3(-0.7, TABLE_TOP + 0.06, -0.75), GreyboxKit.material(Color("#1E1B19"), 0.2, 0.5))
	for s: Array in [[Vector3(0.62, 0, 0.35), Palette.CASINO_RED, 5], [Vector3(-0.5, 0, 0.55), Palette.CREAM, 3], [Vector3(0.15, 0, 0.75), Palette.CASINO_BLACK, 4]]:
		for k: int in int(s[2]):
			_cyl(t, 0.045, 0.018, (s[0] as Vector3) + Vector3(0, TABLE_TOP + 0.01 + 0.019 * float(k), 0), GreyboxKit.material(s[1], 0.0, 0.5), 14)


# --- Gramophone dais --------------------------------------------------------------------------

static func _dais(root: Node3D, brass: Material, wood: Material) -> void:
	var depth: float = (DAIS_Z - FAR_Z) * 2.0
	var dais: Node3D = VaultArena._solid(root, Vector3(4.6, DAIS_H, depth), Vector3(0, DAIS_H * 0.5, FAR_Z + depth * 0.5), wood, "Dais")
	dais.name = "Dais"
	VaultArena._vis(root, Vector3(4.66, 0.05, 0.06), Vector3(0, DAIS_H - 0.02, FAR_Z + depth + 0.01), brass)
	var top := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(4.4, depth - 0.2)
	top.mesh = pm
	top.material_override = VaultArena._tex("velvet", 1.2, Palette.VIP_BURGUNDY.lightened(0.1), 0.0, 0.9)
	top.position = Vector3(0, DAIS_H + 0.005, FAR_Z + depth * 0.5)
	root.add_child(top)
	# The gramophone: a walnut cabinet, a turntable with a record, a tone arm and a brass horn.
	var g := Node3D.new()
	g.name = "Gramophone"
	g.position = GRAMOPHONE
	root.add_child(g)
	var walnut: StandardMaterial3D = GreyboxKit.material(WOOD_WARM, 0.0, 0.45)
	VaultArena._vis(g, Vector3(0.7, 0.75, 0.6), Vector3(0, 0.375, 0), walnut)
	VaultArena._vis(g, Vector3(0.74, 0.04, 0.64), Vector3(0, 0.77, 0), brass)
	VaultArena._vis(g, Vector3(0.5, 0.04, 0.02), Vector3(0, 0.45, 0.305), brass)
	var record := Node3D.new()
	record.name = "Record"
	record.position = Vector3(0, 0.8, 0)
	g.add_child(record)
	_cyl(record, 0.26, 0.02, Vector3.ZERO, GreyboxKit.material(Color("#141210"), 0.1, 0.25), 32)
	_cyl(record, 0.08, 0.025, Vector3.ZERO, GreyboxKit.material(Palette.CASINO_RED, 0.0, 0.6), 16)
	VaultArena._vis(record, Vector3(0.04, 0.03, 0.18), Vector3(0.12, 0.012, 0.0), GreyboxKit.material(Palette.CREAM, 0.0, 0.5))
	var arm := Node3D.new()
	arm.name = "ToneArm"
	arm.position = Vector3(0.28, 0.84, -0.2)
	g.add_child(arm)
	VaultArena._vis(arm, Vector3(0.03, 0.03, 0.34), Vector3(-0.06, 0, 0.15), brass)
	var horn := MeshInstance3D.new()
	horn.name = "Horn"
	var hm := CylinderMesh.new()
	hm.top_radius = 0.42
	hm.bottom_radius = 0.04
	hm.height = 0.75
	hm.radial_segments = 20
	hm.cap_top = false
	horn.mesh = hm
	var horn_mat: StandardMaterial3D = (brass as StandardMaterial3D).duplicate()
	horn_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	horn.material_override = horn_mat
	horn.position = Vector3(-0.15, 1.25, 0.15)
	horn.rotation = Vector3(0.7, 0.0, 0.35)
	g.add_child(horn)
	VaultArena._vis(g, Vector3(0.05, 0.4, 0.05), Vector3(-0.08, 0.95, 0.0), brass)
	# Music notes sign over the dais.
	var sign := Label3D.new()
	sign.text = "THE PARLOR"
	sign.font = Vfx.font()
	sign.font_size = 72
	sign.pixel_size = 0.006
	sign.modulate = Palette.VIP_GOLD
	sign.outline_size = 0
	sign.shaded = true
	sign.position = Vector3(0, 4.45, FAR_Z + 0.08)
	root.add_child(sign)


# --- Decor ------------------------------------------------------------------------------------

static func _decor(root: Node3D, brass: Material) -> void:
	# Two marble columns flanking the dais.
	var marble: StandardMaterial3D = GreyboxKit.material(VaultArena.MARBLE.darkened(0.05), 0.0, 0.45)
	for x: float in [-3.1, 3.1]:
		var p := Vector3(x, 0, FAR_Z + 0.7)
		var solid: Node3D = GreyboxKit.cylinder(root, 0.36, WALL_H, p + Vector3(0, WALL_H * 0.5, 0), VaultArena.MARBLE, "Column")
		(solid.get_node(^"Mesh") as MeshInstance3D).material_override = marble
		if PropModels.has(&"column"):
			(solid.get_node(^"Mesh") as Node3D).visible = false
			var col: Node3D = PropModels.make(&"column", WALL_H)
			col.scale = Vector3(0.55, 1.0, 0.55)
			col.position.y = -WALL_H * 0.5
			for n: Node in col.find_children("*", "MeshInstance3D", true, false):
				(n as MeshInstance3D).material_override = marble
			solid.add_child(col)
	# Curtained windows on the long walls, pictures between them.
	for side: float in [-1.0, 1.0]:
		var x: float = side * (HALF_X - 0.1)
		for z: float in [-4.2, 2.6]:
			var frame := Node3D.new()
			frame.position = Vector3(x, 1.55, z)
			frame.rotation.y = -side * PI * 0.5
			root.add_child(frame)
			VaultArena._vis(frame, Vector3(1.6, 2.2, 0.06), Vector3(0, 1.1, 0), GreyboxKit.material(Color("#1B2230"), 0.0, 0.3))
			for bar: Array in [[Vector3(1.7, 0.08, 0.1), Vector3(0, 0.0, 0.03)], [Vector3(1.7, 0.08, 0.1), Vector3(0, 2.2, 0.03)], [Vector3(0.06, 2.2, 0.08), Vector3(0, 1.1, 0.03)], [Vector3(1.6, 0.05, 0.08), Vector3(0, 1.3, 0.03)]]:
				VaultArena._vis(frame, bar[0], bar[1], GreyboxKit.material(WOOD, 0.0, 0.5))
			var curtain: StandardMaterial3D = VaultArena._tex("velvet", 1.0, Palette.VIP_BURGUNDY.lightened(0.05), 0.0, 0.9)
			for cx: float in [-1.05, 1.05]:
				VaultArena._vis(frame, Vector3(0.5, 2.9, 0.14), Vector3(cx, 1.15, 0.1), curtain)
			VaultArena._vis(frame, Vector3(2.8, 0.06, 0.06), Vector3(0, 2.65, 0.16), brass)
		var pic_z: float = -0.8
		if PropModels.has(&"picture"):
			var pic: Node3D = PropModels.make(&"picture", 0.0, 1.3)
			pic.position = Vector3(x - side * 0.02, 2.0, pic_z)
			pic.rotation = Vector3(0, -side * PI * 0.5, 0)
			root.add_child(pic)
		else:
			VaultArena._vis(root, Vector3(0.06, 1.0, 1.3), Vector3(x, 2.6, pic_z), brass)
	if PropModels.has(&"mirror"):
		for x: float in [-5.4, 5.4]:
			var m: Node3D = PropModels.make(&"mirror", 1.6)
			m.position = Vector3(x, 1.3, FAR_Z + 0.06)
			root.add_child(m)
	# Armchair couches in the four corners of the floor, well out of the ring.
	if PropModels.has(&"couch"):
		for c: Array in [[Vector3(-6.6, 0, -6.6), PI * 0.25], [Vector3(6.6, 0, -6.6), -PI * 0.25]]:
			var couch: Node3D = PropModels.shade(PropModels.make(&"couch", 0.0, 2.0), 0.85)
			couch.position = c[0]
			couch.rotation.y = c[1]
			root.add_child(couch)
			var body := StaticBody3D.new()
			var cs := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = Vector3(2.0, 0.9, 0.9)
			cs.shape = shape
			body.add_child(cs)
			body.position = (c[0] as Vector3) + Vector3(0, 0.45, 0)
			body.rotation.y = c[1]
			root.add_child(body)


static func _gallery(root: Node3D, brass: Material) -> void:
	var depth: float = BACK_Z - GALLERY_Z
	var mid: float = GALLERY_Z + depth * 0.5
	VaultArena._solid(root, Vector3(HALF_X * 2.0, GALLERY_H, depth), Vector3(0, GALLERY_H * 0.5, mid), GreyboxKit.material(WOOD, 0.0, 0.5), "Gallery")
	var rug := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(HALF_X * 2.0 - 0.6, depth - 0.5)
	rug.mesh = pm
	rug.material_override = VaultArena._tex("velvet", 1.5, Palette.VIP_BURGUNDY.lightened(0.15), 0.0, 0.9)
	rug.position = Vector3(0, GALLERY_H + 0.012, mid + 0.1)
	root.add_child(rug)
	VaultArena._vis(root, Vector3(HALF_X * 2.0, 0.08, 0.08), Vector3(0, GALLERY_H + 1.0, GALLERY_Z + 0.08), brass)
	VaultArena._vis(root, Vector3(HALF_X * 2.0, 0.05, 0.05), Vector3(0, GALLERY_H + 0.5, GALLERY_Z + 0.08), brass)
	var x: float = -HALF_X + 0.4
	while x < HALF_X:
		VaultArena._vis(root, Vector3(0.06, 1.0, 0.06), Vector3(x, GALLERY_H + 0.5, GALLERY_Z + 0.08), brass)
		x += 0.8
	VaultArena._vis(root, Vector3(HALF_X * 2.0, 0.1, 0.12), Vector3(0, GALLERY_H - 0.05, GALLERY_Z + 0.02), brass)
	var wall := StaticBody3D.new()
	wall.name = "GalleryBarrier"
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(HALF_X * 2.0, 3.6, 0.3)
	cs.shape = shape
	wall.add_child(cs)
	wall.position = Vector3(0, 1.8, GALLERY_Z)
	root.add_child(wall)
	if PropModels.has(&"couch"):
		for cx: float in [-4.6, 0.0, 4.6]:
			var couch: Node3D = PropModels.make(&"couch", 0.0, 2.4)
			couch.position = Vector3(cx, GALLERY_H, BACK_Z - 0.75)
			couch.rotation.y = PI
			root.add_child(couch)
	var sign := Label3D.new()
	sign.text = "NO SEAT, NO GAME"
	sign.font = Vfx.font()
	sign.font_size = 48
	sign.pixel_size = 0.006
	sign.modulate = Palette.CREAM
	sign.outline_size = 0
	sign.shaded = true
	sign.position = Vector3(0, GALLERY_H + 2.5, BACK_Z - 0.02)
	sign.rotation.y = PI
	root.add_child(sign)


static func _lights(root: Node3D, brass: Material) -> void:
	var glow: StandardMaterial3D = Vfx.glow_material(Color(1.0, 0.85, 0.55))
	# The chandelier over the table: a brass ring of candle bulbs on a chain.
	var ch := Node3D.new()
	ch.name = "Chandelier"
	ch.position = TABLE_CENTER + Vector3(0, 3.6, 0)
	root.add_child(ch)
	VaultArena._vis(ch, Vector3(0.03, WALL_H - 3.6, 0.03), Vector3(0, (WALL_H - 3.6) * 0.5, 0), brass)
	var ring := Node3D.new()
	ch.add_child(ring)
	VaultArena._ring(ring, 0.85, 0.06, 0.0, brass)
	ring.scale = Vector3(1.0, 12.0, 1.0)
	VaultArena._sphere(ch, 0.14, Vector3.ZERO, brass)
	for i: int in 8:
		var a: float = TAU * float(i) / 8.0
		var p := Vector3(sin(a) * 0.85, 0.08, cos(a) * 0.85)
		VaultArena._vis(ch, Vector3(0.05, 0.14, 0.05), p, GreyboxKit.material(Palette.CREAM, 0.0, 0.6))
		var bulb: MeshInstance3D = VaultArena._sphere(ch, 0.06, p + Vector3(0, 0.12, 0), null)
		bulb.material_override = glow
	var main: OmniLight3D = GreyboxKit.lamp(root, TABLE_CENTER + Vector3(0, 3.2, 0), 2.6, 9.0, LAMP)
	main.name = "ChandelierLight"
	var spot := SpotLight3D.new()
	spot.name = "TableSpot"
	spot.light_color = Color(1.0, 0.86, 0.62)
	spot.light_energy = 2.2
	spot.spot_range = 6.0
	spot.spot_angle = 32.0
	spot.position = TABLE_CENTER + Vector3(0, 3.4, 0)
	spot.rotation.x = -PI * 0.5
	root.add_child(spot)
	# Wall sconces between the windows and over the dais.
	for side: float in [-1.0, 1.0]:
		for z: float in [-6.4, -0.8, 4.4]:
			var at := Vector3(side * (HALF_X - 0.12), 2.5, z + (0.0 if z != -0.8 else 1.4))
			VaultArena._vis(root, Vector3(0.12, 0.35, 0.2), at, brass)
			var b: MeshInstance3D = VaultArena._sphere(root, 0.11, at + Vector3(-side * 0.15, 0.25, 0), null)
			b.material_override = glow
			GreyboxKit.lamp(root, at + Vector3(-side * 0.7, 0.3, 0), 0.8, 5.5, LAMP)
	for x: float in [-2.2, 2.2]:
		var at := Vector3(x, 2.8, FAR_Z + 0.1)
		VaultArena._vis(root, Vector3(0.3, 0.4, 0.14), at, brass)
		var b: MeshInstance3D = VaultArena._sphere(root, 0.12, at + Vector3(0, 0.3, 0.12), null)
		b.material_override = glow
		GreyboxKit.lamp(root, at + Vector3(0, 0.2, 0.8), 0.9, 6.0, LAMP)
	for gx: float in [-4.6, 0.0, 4.6]:
		GreyboxKit.lamp(root, Vector3(gx, 3.8, BACK_Z - 1.5), 0.8, 6.5, LAMP)
	var fill := OmniLight3D.new()
	fill.position = Vector3(0, 4.6, 0.5)
	fill.light_color = Color(1.0, 0.88, 0.72)
	fill.light_energy = 0.7
	fill.omni_range = 18.0
	root.add_child(fill)


static func _cyl(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material, segments: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = segments
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi
