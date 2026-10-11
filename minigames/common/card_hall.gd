class_name CardHall
extends RefCounted
## The card hall of Grab Your Hand: a grand, warm hall with a checker-marble floor framed by a
## brass inlay, gold-and-cream damask walls over a wood wainscot and a coffered ceiling with two
## brass chandeliers. In the middle, on a round felt dais, a giant fanned royal flush (A K Q J 10
## of spades) turns slowly on a brass stand. Giant framed playing cards hang along the long walls
## (a royal flush in hearts on one side, in diamonds on the other). Lucky deals from a half-moon
## dealer's table at the far wall under "THE CARD HALL"; behind a brass railing at the near end a
## raised gallery with couches holds anyone who drops out. The open floor round the dais is the
## card field where the server drops the giant cards (`random_spot`, `clamp_to_field`).
##
## Like `ParlorRoom`: `layout()` is pure data for the server (bounds, spawns, gallery spots in
## world coordinates around `WalkableLogicBase.ROOM_ORIGIN`), `build(parent)` makes the nodes.
## Local axes: -z is the dealer wall, +z the gallery.

const HALF_X: float = 9.0
const FAR_Z: float = -8.5
const BACK_Z: float = 10.2
const GALLERY_Z: float = 7.0
const GALLERY_H: float = 1.0
const WALL_H: float = 6.0
const WALL_T: float = 0.5
## The centre dais with the giant fan of cards (local), and its radius; nothing spawns closer than
## `CLEAR_RADIUS` to its centre.
const CENTER: Vector3 = Vector3(0, 0, -0.6)
const DAIS_RADIUS: float = 1.8
const DAIS_H: float = 0.3
const CLEAR_RADIUS: float = 2.6
## The card field (local x/z rectangle) where cards lie.
const FIELD_MIN: Vector2 = Vector2(-7.4, -6.0)
const FIELD_MAX: Vector2 = Vector2(7.4, 5.9)
## Beans start on this ring round the dais, facing it.
const SPAWN_RADIUS: float = 4.4
## The dealer's table at the far wall; Lucky stands behind it.
const DEALER_Z: float = -7.0
const LUCKY_SPOT: Vector3 = Vector3(0.0, 0.0, -7.75)
const MAX_SPOTS: int = 8
## The size of the giant cards on the floor (and the fan on the dais is bigger still).
const FAN_CARD: Vector2 = Vector2(1.15, 1.6)

const WOOD: Color = Color("#3A2A1E")
const FELT: Color = Color("#275E49")
const LAMP: Color = Color(1.0, 0.82, 0.55)


## World-space description for the server.
static func layout() -> Dictionary:
	var o: Vector3 = WalkableLogicBase.ROOM_ORIGIN
	var c: Vector3 = o + CENTER
	var spawns: Array[Vector3] = []
	var yaws: Array[float] = []
	for i: int in MAX_SPOTS:
		var slot: int = [0, 4, 2, 6, 1, 5, 3, 7][i]
		var a: float = TAU * (float(slot) + 0.5) / float(MAX_SPOTS)
		var local := Vector3(sin(a) * SPAWN_RADIUS, 0.0, cos(a) * SPAWN_RADIUS)
		spawns.append(c + local)
		yaws.append(atan2(local.x, local.z))  # facing the dais (yaw 0 faces -z)
	var spots: Array[Vector3] = []
	for i: int in MAX_SPOTS:
		var x: float = -6.0 + 12.0 * float(i) / float(MAX_SPOTS - 1)
		spots.append(o + Vector3(x, GALLERY_H, GALLERY_Z + 1.2 + (0.35 if i % 2 == 1 else 0.0)))
	var arena := AABB(o + Vector3(-HALF_X + 0.2, -1.0, FAR_Z + 0.2), Vector3((HALF_X - 0.2) * 2.0, 5.0, GALLERY_Z - FAR_Z - 0.2))
	var gallery := AABB(o + Vector3(-HALF_X + 0.2, GALLERY_H - 0.6, GALLERY_Z + 0.2), Vector3((HALF_X - 0.2) * 2.0, 4.5, BACK_Z - GALLERY_Z - 0.4))
	return {"arena": arena, "gallery": gallery, "spawns": spawns, "spawn_yaws": yaws, "gallery_spots": spots}


static func center() -> Vector3:
	return WalkableLogicBase.ROOM_ORIGIN + CENTER


## A random floor spot in the card field (world, y = 0), clear of the dais.
static func random_spot(rng: SeededRng) -> Vector3:
	var o: Vector3 = WalkableLogicBase.ROOM_ORIGIN
	for _i: int in 24:
		var p := Vector3(rng.range_float(FIELD_MIN.x, FIELD_MAX.x), 0.0, rng.range_float(FIELD_MIN.y, FIELD_MAX.y))
		if Vector2(p.x - CENTER.x, p.z - CENTER.z).length() >= CLEAR_RADIUS:
			return o + p
	return o + CENTER + Vector3(0, 0, CLEAR_RADIUS + 1.0)


## `pos` (world) moved into the card field: inside the rectangle, out of the dais circle, y = 0.
static func clamp_to_field(pos: Vector3) -> Vector3:
	var o: Vector3 = WalkableLogicBase.ROOM_ORIGIN
	var l: Vector3 = pos - o
	l.x = clampf(l.x, FIELD_MIN.x, FIELD_MAX.x)
	l.z = clampf(l.z, FIELD_MIN.y, FIELD_MAX.y)
	var d := Vector2(l.x - CENTER.x, l.z - CENTER.z)
	if d.length() < CLEAR_RADIUS:
		d = d.normalized() if d.length() > 0.01 else Vector2(0, 1)
		l.x = CENTER.x + d.x * CLEAR_RADIUS
		l.z = CENTER.z + d.y * CLEAR_RADIUS
	return o + Vector3(l.x, 0.0, l.z)


static func in_field(pos: Vector3) -> bool:
	return clamp_to_field(pos).distance_to(Vector3(pos.x, 0.0, pos.z)) < 0.01


## Builds the hall under `parent` (at the world origin) at `WalkableLogicBase.ROOM_ORIGIN`.
static func build(parent: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "CardHall"
	parent.add_child(root)
	root.position = WalkableLogicBase.ROOM_ORIGIN
	var brass: StandardMaterial3D = VaultArena._tex("brass", 1.2, Color(1.0, 0.86, 0.6), 0.85, 0.32)
	var wood: StandardMaterial3D = GreyboxKit.material(WOOD, 0.0, 0.55)
	_shell(root, brass, wood)
	_centerpiece(root, brass, wood)
	_wall_cards(root, brass)
	_dealer(root, brass, wood)
	_decor(root, brass)
	_gallery(root, brass, wood)
	_lights(root, brass)
	return root


## A giant card standing upright facing +z, its bottom edge at the node origin (two-sided: the
## face on the front, the red back behind).
static func standing_card(card: int, size: Vector2) -> Node3D:
	var n := Node3D.new()
	var c: TableCard3D = TableCard3D.make(card, size, true)
	c.rotation.x = PI * 0.5
	c.position.y = size.y * 0.5
	n.add_child(c)
	return n


# --- Shell ------------------------------------------------------------------------------------

static func _shell(root: Node3D, brass: Material, wood: Material) -> void:
	var len_z: float = BACK_Z - FAR_Z
	var mid_z: float = (BACK_Z + FAR_Z) * 0.5
	var marble: StandardMaterial3D = VaultArena._tex("checker_marble", 2.4, Color(0.9, 0.84, 0.76), 0.1, 0.3)
	var paper: StandardMaterial3D = VaultArena._tex("damask_wallpaper", 1.8, Color(0.86, 0.66, 0.42), 0.0, 0.85)
	var panels: StandardMaterial3D = VaultArena._tex("wooden_panels", 1.4, Color(0.72, 0.52, 0.4), 0.0, 0.6)
	var ceiling: StandardMaterial3D = VaultArena._tex("coffered_ceiling", 3.0, Color(0.72, 0.6, 0.48), 0.0, 0.8)
	VaultArena._solid(root, Vector3(HALF_X * 2.0 + 1.0, 0.4, len_z + 1.0), Vector3(0, -0.2, mid_z), marble, "Floor")
	VaultArena._solid(root, Vector3(HALF_X * 2.0 + 1.0, 0.4, len_z + 1.0), Vector3(0, WALL_H + 0.2, mid_z), ceiling, "Ceiling")
	VaultArena._solid(root, Vector3(WALL_T, WALL_H, len_z + 1.0), Vector3(-HALF_X - WALL_T * 0.5, WALL_H * 0.5, mid_z), paper, "WallW")
	VaultArena._solid(root, Vector3(WALL_T, WALL_H, len_z + 1.0), Vector3(HALF_X + WALL_T * 0.5, WALL_H * 0.5, mid_z), paper, "WallE")
	VaultArena._solid(root, Vector3(HALF_X * 2.0, WALL_H, WALL_T), Vector3(0, WALL_H * 0.5, FAR_Z - WALL_T * 0.5), paper, "WallFar")
	VaultArena._solid(root, Vector3(HALF_X * 2.0, WALL_H, WALL_T), Vector3(0, WALL_H * 0.5, BACK_Z + WALL_T * 0.5), paper, "WallBack")
	for side: float in [-1.0, 1.0]:
		var x: float = side * (HALF_X - 0.04)
		VaultArena._vis(root, Vector3(0.08, 1.3, len_z), Vector3(x, 0.65, mid_z), panels)
		VaultArena._vis(root, Vector3(0.12, 0.06, len_z), Vector3(x - side * 0.02, 1.32, mid_z), brass)
		VaultArena._vis(root, Vector3(0.12, 0.2, len_z), Vector3(x - side * 0.02, 0.1, mid_z), wood)
		VaultArena._vis(root, Vector3(0.22, 0.26, len_z), Vector3(x - side * 0.07, WALL_H - 0.13, mid_z), wood)
	for z_wall: float in [FAR_Z + 0.04, BACK_Z - 0.04]:
		var inward: float = 1.0 if z_wall < 0.0 else -1.0
		VaultArena._vis(root, Vector3(HALF_X * 2.0, 1.3, 0.08), Vector3(0, 0.65, z_wall), panels)
		VaultArena._vis(root, Vector3(HALF_X * 2.0, 0.06, 0.12), Vector3(0, 1.32, z_wall + inward * 0.02), brass)
		VaultArena._vis(root, Vector3(HALF_X * 2.0, 0.2, 0.12), Vector3(0, 0.1, z_wall + inward * 0.02), wood)
		VaultArena._vis(root, Vector3(HALF_X * 2.0, 0.26, 0.22), Vector3(0, WALL_H - 0.13, z_wall + inward * 0.07), wood)
	# A brass inlay frames the card field; a burgundy runner leads from the gallery to the dais.
	var w: float = FIELD_MAX.x - FIELD_MIN.x + 0.6
	var d: float = FIELD_MAX.y - FIELD_MIN.y + 0.6
	var cz: float = (FIELD_MAX.y + FIELD_MIN.y) * 0.5
	for e: Array in [[Vector3(w, 0.012, 0.08), Vector3(0, 0.006, FIELD_MIN.y - 0.3)], [Vector3(w, 0.012, 0.08), Vector3(0, 0.006, FIELD_MAX.y + 0.3)], [Vector3(0.08, 0.012, d), Vector3(FIELD_MIN.x - 0.3, 0.006, cz)], [Vector3(0.08, 0.012, d), Vector3(FIELD_MAX.x + 0.3, 0.006, cz)]]:
		VaultArena._vis(root, e[0], e[1], brass)
	# Corner suit medallions: a brass disc with a big suit pip in each corner of the field.
	var pips: Array[String] = ["♠", "♥", "♦", "♣"]
	var corners: Array[Vector2] = [Vector2(FIELD_MIN.x + 0.9, FIELD_MIN.y + 0.9), Vector2(FIELD_MAX.x - 0.9, FIELD_MIN.y + 0.9), Vector2(FIELD_MIN.x + 0.9, FIELD_MAX.y - 0.9), Vector2(FIELD_MAX.x - 0.9, FIELD_MAX.y - 0.9)]
	for i: int in 4:
		var at := Vector3(corners[i].x, 0.0, corners[i].y)
		var disc: MeshInstance3D = ParlorRoom._cyl(root, 0.62, 0.012, at + Vector3(0, 0.006, 0), GreyboxKit.material(Palette.CREAM, 0.0, 0.5), 32)
		disc.name = "Medallion%d" % i
		var ring := Node3D.new()
		ring.position = at
		root.add_child(ring)
		VaultArena._ring(ring, 0.64, 0.06, 0.012, brass)
		var pip := Label3D.new()
		pip.text = pips[i]
		pip.font_size = 160
		pip.pixel_size = 0.006
		pip.modulate = Palette.CASINO_RED if i == 1 or i == 2 else Palette.CASINO_BLACK
		pip.outline_size = 0
		pip.shaded = true
		pip.rotation = Vector3(-PI * 0.5, 0, 0)
		pip.position = at + Vector3(0, 0.016, 0)
		root.add_child(pip)


# --- The giant fan on the dais ----------------------------------------------------------------

static func _centerpiece(root: Node3D, brass: Material, wood: Material) -> void:
	var c := Node3D.new()
	c.name = "Centerpiece"
	c.position = CENTER
	root.add_child(c)
	# Collision: a 1.2 m cylinder, so nobody climbs onto the dais (everyone runs round it).
	var solid: Node3D = GreyboxKit.cylinder(c, DAIS_RADIUS + 0.05, 1.2, Vector3(0, 0.6, 0), WOOD, "DaisBody")
	(solid.get_node(^"Mesh") as Node3D).visible = false
	ParlorRoom._cyl(c, DAIS_RADIUS, DAIS_H, Vector3(0, DAIS_H * 0.5, 0), wood, 48)
	ParlorRoom._cyl(c, DAIS_RADIUS - 0.12, 0.02, Vector3(0, DAIS_H + 0.01, 0), GreyboxKit.material(FELT, 0.0, 0.85), 48)
	var rim := Node3D.new()
	rim.position.y = DAIS_H
	c.add_child(rim)
	VaultArena._ring(rim, DAIS_RADIUS - 0.03, 0.08, 0.0, brass)
	var base := Node3D.new()
	base.position.y = 0.04
	c.add_child(base)
	VaultArena._ring(base, DAIS_RADIUS + 0.02, 0.06, 0.0, brass)
	# A gold felt ring round the dais on the floor.
	var floor_ring := Node3D.new()
	c.add_child(floor_ring)
	VaultArena._ring(floor_ring, CLEAR_RADIUS - 0.3, 0.06, 0.008, GreyboxKit.material(Palette.WARM_GOLD, 0.8, 0.3))
	# Brass stand and the slowly turning fan (the stage spins "Centerpiece/Spin").
	ParlorRoom._cyl(c, 0.12, 0.7, Vector3(0, DAIS_H + 0.35, 0), brass, 16)
	ParlorRoom._cyl(c, 0.4, 0.06, Vector3(0, DAIS_H + 0.03, 0), brass, 24)
	var spin := Node3D.new()
	spin.name = "Spin"
	spin.position.y = DAIS_H + 0.65
	c.add_child(spin)
	var fan: Array[int] = [Card.make(10, 0), Card.make(11, 0), Card.make(12, 0), Card.make(13, 0), Card.make(1, 0)]
	for i: int in fan.size():
		var pivot := Node3D.new()
		pivot.rotation.z = deg_to_rad(28.0 - 14.0 * float(i))
		pivot.position.z = 0.02 * float(i)
		spin.add_child(pivot)
		var card: Node3D = standing_card(fan[i], FAN_CARD)
		card.position.y = -0.25
		pivot.add_child(card)
	var gem: MeshInstance3D = VaultArena._sphere(spin, 0.09, Vector3(0, 0.0, 0.12), GreyboxKit.gold())
	gem.name = "FanRivet"


# --- Giant framed cards on the walls ------------------------------------------------------------

static func _wall_cards(root: Node3D, brass: Material) -> void:
	var size := Vector2(1.25, 1.75)
	var frame_mat: StandardMaterial3D = GreyboxKit.material(WOOD, 0.0, 0.5)
	# A royal flush on each long wall: hearts on the west wall, diamonds on the east.
	for side: float in [-1.0, 1.0]:
		var suit: int = 1 if side < 0.0 else 2
		var ranks: Array[int] = [10, 11, 12, 13, 1]
		for i: int in ranks.size():
			var z: float = -5.6 + 2.6 * float(i)
			var holder := Node3D.new()
			holder.name = "WallCard%s%d" % ["W" if side < 0.0 else "E", i]
			holder.position = Vector3(side * (HALF_X - 0.12), 1.75, z)
			holder.rotation.y = -side * PI * 0.5  # facing into the hall
			root.add_child(holder)
			# Dark backing, a wood frame and a brass slip round the card.
			VaultArena._vis(holder, Vector3(size.x + 0.3, size.y + 0.3, 0.05), Vector3(0, size.y * 0.5, -0.02), GreyboxKit.material(Palette.CASINO_BLACK.lightened(0.08), 0.0, 0.6))
			for bar: Array in [[Vector3(size.x + 0.42, 0.1, 0.1), Vector3(0, -0.15, 0)], [Vector3(size.x + 0.42, 0.1, 0.1), Vector3(0, size.y + 0.15, 0)], [Vector3(0.1, size.y + 0.4, 0.1), Vector3(-(size.x + 0.32) * 0.5, size.y * 0.5, 0)], [Vector3(0.1, size.y + 0.4, 0.1), Vector3((size.x + 0.32) * 0.5, size.y * 0.5, 0)]]:
				VaultArena._vis(holder, bar[0], bar[1], frame_mat)
			VaultArena._vis(holder, Vector3(size.x + 0.18, 0.03, 0.03), Vector3(0, -0.08, 0.05), brass)
			VaultArena._vis(holder, Vector3(size.x + 0.18, 0.03, 0.03), Vector3(0, size.y + 0.08, 0.05), brass)
			var card: Node3D = standing_card(Card.make(ranks[i], suit), size)
			card.position.z = 0.02
			holder.add_child(card)
			# A brass picture light over each card.
			VaultArena._vis(holder, Vector3(0.5, 0.06, 0.12), Vector3(0, size.y + 0.4, 0.16), brass)


# --- The dealer's table -------------------------------------------------------------------------

static func _dealer(root: Node3D, brass: Material, wood: Material) -> void:
	var t := Node3D.new()
	t.name = "DealerTable"
	t.position = Vector3(0, 0, DEALER_Z)
	root.add_child(t)
	var solid: Node3D = GreyboxKit.box(t, Vector3(3.0, 1.0, 0.9), Vector3(0, 0.5, 0.1), WOOD, "DealerBody")
	(solid.get_node(^"Mesh") as Node3D).visible = false
	# A half-moon table: a wood body with a felt top and a padded burgundy rail on the player side.
	var body := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.5
	cm.bottom_radius = 1.5
	cm.height = 0.82
	cm.radial_segments = 32
	body.mesh = cm
	body.material_override = wood
	body.scale = Vector3(1.0, 1.0, 0.4)
	body.position = Vector3(0, 0.41, 0.0)
	t.add_child(body)
	var top := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 1.42
	tm.bottom_radius = 1.42
	tm.height = 0.04
	tm.radial_segments = 32
	top.mesh = tm
	top.material_override = GreyboxKit.material(FELT, 0.0, 0.85)
	top.scale = Vector3(1.0, 1.0, 0.38)
	top.position = Vector3(0, 0.84, 0.0)
	t.add_child(top)
	var rail := MeshInstance3D.new()
	var rm := TorusMesh.new()
	rm.inner_radius = 1.38
	rm.outer_radius = 1.56
	rm.rings = 40
	rm.ring_segments = 8
	rail.mesh = rm
	rail.material_override = GreyboxKit.material(Color("#681F2C"), 0.0, 0.55)
	rail.scale = Vector3(1.0, 0.7, 0.4)
	rail.position = Vector3(0, 0.86, 0.0)
	t.add_child(rail)
	VaultArena._vis(t, Vector3(3.0, 0.05, 0.05), Vector3(0, 0.1, 0.62), brass)
	# A card shoe, a discard tray and a fanned spread of cards on the felt.
	VaultArena._vis(t, Vector3(0.22, 0.14, 0.36), Vector3(-0.85, 0.93, -0.1), GreyboxKit.material(Color("#1E1B19"), 0.2, 0.5))
	VaultArena._vis(t, Vector3(0.2, 0.06, 0.3), Vector3(0.85, 0.89, -0.1), GreyboxKit.material(Color("#1E1B19"), 0.2, 0.5))
	for i: int in 7:
		var card: TableCard3D = TableCard3D.make(TableCard3D.FACE_DOWN, Vector2(0.14, 0.2), false)
		card.position = Vector3(-0.42 + 0.12 * float(i), 0.87 + 0.001 * float(i), 0.05)
		card.rotation.y = 0.35 - 0.1 * float(i)
		t.add_child(card)


# --- Decor --------------------------------------------------------------------------------------

static func _decor(root: Node3D, brass: Material) -> void:
	# Marble columns along the long walls, between the framed cards.
	var marble: StandardMaterial3D = GreyboxKit.material(VaultArena.MARBLE.darkened(0.05), 0.0, 0.45)
	for side: float in [-1.0, 1.0]:
		for z: float in [-7.4, 6.4]:
			var p := Vector3(side * (HALF_X - 0.55), 0, z)
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
	# Big standing cards leaning in the far corners, like a deck spilled by a giant.
	for c: Array in [[Vector3(-7.2, 0, -7.6), 0.5, Card.make(1, 3), -0.2], [Vector3(7.2, 0, -7.6), -0.5, Card.make(13, 1), 0.2]]:
		var lean: Node3D = standing_card(int(c[2]), Vector2(1.5, 2.1))
		lean.position = c[0]
		lean.rotation = Vector3(-0.18, float(c[1]), float(c[3]))
		root.add_child(lean)
	# Mirrors flanking the dealer, plants by the gallery steps.
	if PropModels.has(&"mirror"):
		for x: float in [-4.6, 4.6]:
			var m: Node3D = PropModels.make(&"mirror", 1.6)
			m.position = Vector3(x, 1.4, FAR_Z + 0.06)
			root.add_child(m)
	for x: float in [-HALF_X + 0.7, HALF_X - 0.7]:
		if PropModels.has(&"plant_2"):
			var plant: Node3D = PropModels.make(&"plant_2", 1.2)
			plant.position = Vector3(x, 0, GALLERY_Z - 0.5)
			root.add_child(plant)
	var sign := Label3D.new()
	sign.text = "THE CARD HALL"
	sign.font = Vfx.font()
	sign.font_size = 80
	sign.pixel_size = 0.0065
	sign.modulate = Palette.VIP_GOLD
	sign.outline_size = 0
	sign.shaded = true
	sign.position = Vector3(0, 4.55, FAR_Z + 0.08)
	root.add_child(sign)
	var sub := Label3D.new()
	sub.text = "BEST HAND TAKES THE HOUSE"
	sub.font = Vfx.font()
	sub.font_size = 40
	sub.pixel_size = 0.006
	sub.modulate = Palette.CREAM
	sub.outline_size = 0
	sub.shaded = true
	sub.position = Vector3(0, 3.95, FAR_Z + 0.08)
	root.add_child(sub)


static func _gallery(root: Node3D, brass: Material, wood: Material) -> void:
	var depth: float = BACK_Z - GALLERY_Z
	var mid: float = GALLERY_Z + depth * 0.5
	VaultArena._solid(root, Vector3(HALF_X * 2.0, GALLERY_H, depth), Vector3(0, GALLERY_H * 0.5, mid), wood, "Gallery")
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
	sign.text = "FOLDED"
	sign.font = Vfx.font()
	sign.font_size = 56
	sign.pixel_size = 0.006
	sign.modulate = Palette.CREAM
	sign.outline_size = 0
	sign.shaded = true
	sign.position = Vector3(0, GALLERY_H + 2.6, BACK_Z - 0.02)
	sign.rotation.y = PI
	root.add_child(sign)


static func _lights(root: Node3D, brass: Material) -> void:
	var glow: StandardMaterial3D = Vfx.glow_material(Color(1.0, 0.85, 0.55))
	for cx: float in [-4.2, 4.2]:
		var ch := Node3D.new()
		ch.name = "Chandelier"
		ch.position = Vector3(cx, 4.3, CENTER.z)
		root.add_child(ch)
		VaultArena._vis(ch, Vector3(0.03, WALL_H - 4.3, 0.03), Vector3(0, (WALL_H - 4.3) * 0.5, 0), brass)
		var ring := Node3D.new()
		ch.add_child(ring)
		VaultArena._ring(ring, 0.8, 0.06, 0.0, brass)
		ring.scale = Vector3(1.0, 12.0, 1.0)
		VaultArena._sphere(ch, 0.14, Vector3.ZERO, brass)
		for i: int in 8:
			var a: float = TAU * float(i) / 8.0
			var p := Vector3(sin(a) * 0.8, 0.08, cos(a) * 0.8)
			VaultArena._vis(ch, Vector3(0.05, 0.14, 0.05), p, GreyboxKit.material(Palette.CREAM, 0.0, 0.6))
			var bulb: MeshInstance3D = VaultArena._sphere(ch, 0.06, p + Vector3(0, 0.12, 0), null)
			bulb.material_override = glow
		GreyboxKit.lamp(root, Vector3(cx, 3.9, CENTER.z), 2.4, 10.0, LAMP)
	# A warm spot on the fan.
	var spot := SpotLight3D.new()
	spot.name = "FanSpot"
	spot.light_color = Color(1.0, 0.86, 0.62)
	spot.light_energy = 2.6
	spot.spot_range = 7.0
	spot.spot_angle = 26.0
	spot.position = CENTER + Vector3(0, 5.4, 1.6)
	spot.rotation.x = -PI * 0.5 + 0.3
	root.add_child(spot)
	for side: float in [-1.0, 1.0]:
		for z: float in [-4.3, -1.7, 0.9, 3.5]:
			var at := Vector3(side * (HALF_X - 0.12), 4.25, z)
			VaultArena._vis(root, Vector3(0.12, 0.3, 0.18), at, brass)
			var b: MeshInstance3D = VaultArena._sphere(root, 0.1, at + Vector3(-side * 0.14, 0.22, 0), null)
			b.material_override = glow
		GreyboxKit.lamp(root, Vector3(side * (HALF_X - 1.2), 3.2, -0.6), 1.0, 9.0, LAMP)
	GreyboxKit.lamp(root, Vector3(0, 3.0, DEALER_Z + 1.2), 1.1, 6.5, LAMP)
	for gx: float in [-4.6, 0.0, 4.6]:
		GreyboxKit.lamp(root, Vector3(gx, 4.2, BACK_Z - 1.5), 0.8, 6.5, LAMP)
	var fill := OmniLight3D.new()
	fill.position = Vector3(0, 5.4, 0.0)
	fill.light_color = Color(1.0, 0.88, 0.72)
	fill.light_energy = 0.75
	fill.omni_range = 20.0
	root.add_child(fill)
