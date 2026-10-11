class_name VaultArena
extends RefCounted
## The bank-vault arena of the walkable minigames (Pass the Bomb, Bat Heist): a steel-and-brass
## room with a round vault door on the far wall, a black marble floor with a gold circle inlay,
## four marble pillars and two stacks of gold-bar crates to run around, safe-deposit walls and
## warm brass pendant lamps. Behind a brass railing at the near end a raised gallery with velvet
## couches holds the players who are out.
##
## `layout()` is pure data for the server (arena and gallery bounds, spawns, gallery spots, world
## coordinates around `WalkableLogicBase.ROOM_ORIGIN`); `build(parent)` makes the nodes for the
## client stage (and the dedicated server, so ragdolls have a floor). Local axes: -z is the vault
## door, +z the gallery.
##
## Both take a size factor `k` (1 = the standard vault, Pass the Bomb): the floor, its props, lamps
## and spawn ring spread by `k` in x and z (floor area × k²); heights and the gallery's depth stay.

## Inner half width (x) of the room, the vault door wall (z) and the gallery's back wall (z).
const HALF_X: float = 9.0
const DOOR_Z: float = -7.5
const BACK_Z: float = 10.6
## The gallery: a platform from `GALLERY_Z` to the back wall, `GALLERY_H` high, railing on its lip.
const GALLERY_Z: float = 7.2
const GALLERY_H: float = 1.0
const WALL_H: float = 6.2
const WALL_T: float = 0.5
## Spawn ring around the gold circle and its radius.
const SPAWN_RADIUS: float = 4.0
const GOLD_RING_RADIUS: float = 4.9
const PILLARS: Array[Vector3] = [Vector3(-5.4, 0, -3.8), Vector3(5.4, 0, -3.8), Vector3(-5.4, 0, 3.6), Vector3(5.4, 0, 3.6)]
## Gold-bar crate stacks: [centre, size].
const CRATES: Array = [[Vector3(-7.6, 0, -0.1), Vector3(1.3, 1.1, 2.2)], [Vector3(7.6, 0, -0.1), Vector3(1.3, 1.1, 2.2)], [Vector3(0.0, 0, -6.2), Vector3(2.4, 0.7, 0.9)]]
const MAX_SPOTS: int = 8

const STEEL: Color = Color("#5D5955")
const STEEL_DARK: Color = Color("#3B3734")
const STEEL_LIGHT: Color = Color("#8A847C")
const MARBLE: Color = Color("#E6DFD2")
const WOOD: Color = Color("#5A3A26")
const LAMP: Color = Color(1.0, 0.82, 0.55)
const TEX_DIR: String = "res://assets/textures/"


static func half_x(k: float) -> float:
	return HALF_X * k


static func door_z(k: float) -> float:
	return DOOR_Z * k


static func gallery_z(k: float) -> float:
	return GALLERY_Z * k


static func back_z(k: float) -> float:
	return GALLERY_Z * k + (BACK_Z - GALLERY_Z)


## `v` spread by `k` on the floor plane (y stays).
static func flat(v: Vector3, k: float) -> Vector3:
	return Vector3(v.x * k, v.y, v.z * k)


## World-space description for the server (and the stage's overlay hints).
static func layout(k: float = 1.0) -> Dictionary:
	var hx: float = half_x(k)
	var dz: float = door_z(k)
	var gz: float = gallery_z(k)
	var bz: float = back_z(k)
	var o: Vector3 = WalkableLogicBase.ROOM_ORIGIN
	var spawns: Array[Vector3] = []
	var yaws: Array[float] = []
	for i: int in MAX_SPOTS:
		# Fill the ring evenly for any count: alternate across the circle (0, 4, 2, 6, 1, 5, 3, 7).
		var slot: int = [0, 4, 2, 6, 1, 5, 3, 7][i]
		var a: float = TAU * (float(slot) + 0.5) / float(MAX_SPOTS)
		var local := Vector3(sin(a), 0.0, cos(a)) * SPAWN_RADIUS * k
		spawns.append(o + local)
		yaws.append(atan2(local.x, local.z))  # facing the middle (yaw 0 faces -z)
	var spots: Array[Vector3] = []
	for i: int in MAX_SPOTS:
		var x: float = (-6.3 + 12.6 * float(i) / float(MAX_SPOTS - 1)) * k
		spots.append(o + Vector3(x, GALLERY_H, gz + 1.3 + (0.35 if i % 2 == 1 else 0.0)))
	# Bounds a little past where a bean's centre can physically go (walls stop the body first), so
	# only a real escape is clamped; y spans a jump and a ragdoll's bounce.
	var arena := AABB(o + Vector3(-hx + 0.2, -1.0, dz + 0.2), Vector3((hx - 0.2) * 2.0, 5.0, gz - dz - 0.2))
	var gallery := AABB(o + Vector3(-hx + 0.2, GALLERY_H - 0.6, gz + 0.2), Vector3((hx - 0.2) * 2.0, 4.5, bz - gz - 0.4))
	return {"arena": arena, "gallery": gallery, "spawns": spawns, "spawn_yaws": yaws, "gallery_spots": spots}


## Builds the vault under `parent` (placed at the world origin) at `WalkableLogicBase.ROOM_ORIGIN`;
## returns the room's root.
static func build(parent: Node3D, k: float = 1.0) -> Node3D:
	var root := Node3D.new()
	root.name = "VaultArena"
	parent.add_child(root)
	root.position = WalkableLogicBase.ROOM_ORIGIN  # the stage sits at the world origin
	var steel: StandardMaterial3D = _metal(STEEL, 0.75, 0.42)
	var steel_dark: StandardMaterial3D = _metal(STEEL_DARK, 0.7, 0.5)
	var brass: StandardMaterial3D = _tex("brass", 1.2, Color(1.0, 0.86, 0.6), 0.85, 0.32)
	var marble: StandardMaterial3D = _tex("black_marble", 2.2, Color(0.82, 0.78, 0.74), 0.25, 0.22)
	_shell(root, steel, steel_dark, brass, marble, k)
	_floor_inlay(root, brass, k)
	_vault_door(root, steel, steel_dark, brass, k)
	_deposit_walls(root, steel_dark, brass, k)
	_pillars(root, brass, k)
	_crates(root, brass, k)
	_gallery(root, brass, k)
	_lamps(root, brass, k)
	return root


# --- Shell ------------------------------------------------------------------------------------

static func _shell(root: Node3D, steel: Material, steel_dark: Material, brass: Material, marble: Material, k: float) -> void:
	var hx: float = half_x(k)
	var dz: float = door_z(k)
	var bz: float = back_z(k)
	var len_z: float = bz - dz
	var mid_z: float = (bz + dz) * 0.5
	# Floor slab (top at y = 0) and ceiling.
	_solid(root, Vector3(hx * 2.0 + 1.0, 0.4, len_z + 1.0), Vector3(0, -0.2, mid_z), marble, "Floor")
	_solid(root, Vector3(hx * 2.0 + 1.0, 0.4, len_z + 1.0), Vector3(0, WALL_H + 0.2, mid_z), steel_dark, "Ceiling")
	# Walls (inner faces at ±hx, dz, bz).
	_solid(root, Vector3(WALL_T, WALL_H, len_z + 1.0), Vector3(-hx - WALL_T * 0.5, WALL_H * 0.5, mid_z), steel, "WallW")
	_solid(root, Vector3(WALL_T, WALL_H, len_z + 1.0), Vector3(hx + WALL_T * 0.5, WALL_H * 0.5, mid_z), steel, "WallE")
	_solid(root, Vector3(hx * 2.0, WALL_H, WALL_T), Vector3(0, WALL_H * 0.5, dz - WALL_T * 0.5), steel, "WallDoor")
	_solid(root, Vector3(hx * 2.0, WALL_H, WALL_T), Vector3(0, WALL_H * 0.5, bz + WALL_T * 0.5), steel, "WallBack")
	# Riveted panel seams and two brass bands round the room, a dark steel skirting.
	for side: float in [-1.0, 1.0]:
		var x: float = side * (hx - 0.03)
		var z: float = dz + 1.5
		while z < bz:
			_vis(root, Vector3(0.06, WALL_H - 0.4, 0.08), Vector3(x, WALL_H * 0.5, z), steel_dark)
			z += 2.2
		for y: float in [1.05, 4.6]:
			_vis(root, Vector3(0.08, 0.12, bz - dz), Vector3(side * (hx - 0.04), y, mid_z), brass)
		_vis(root, Vector3(0.1, 0.3, bz - dz), Vector3(side * (hx - 0.05), 0.15, mid_z), steel_dark)
	for z_wall: float in [dz + 0.04, bz - 0.04]:
		for y: float in [1.05, 4.6]:
			_vis(root, Vector3(hx * 2.0, 0.12, 0.08), Vector3(0, y, z_wall), brass)
		_vis(root, Vector3(hx * 2.0, 0.3, 0.1), Vector3(0, 0.15, z_wall + (0.01 if z_wall < 0.0 else -0.01)), steel_dark)
	# Ceiling: steel girders across, brass bolts where they meet the walls.
	var z2: float = dz + 1.8
	while z2 < bz:
		_vis(root, Vector3(hx * 2.0, 0.35, 0.3), Vector3(0, WALL_H - 0.18, z2), steel_dark)
		z2 += 3.0


## A gold circle in the marble with a darker band inside and a brass star of eight rays.
static func _floor_inlay(root: Node3D, brass: Material, k: float) -> void:
	var gold: StandardMaterial3D = GreyboxKit.material(Palette.WARM_GOLD, 0.85, 0.3)
	_ring(root, GOLD_RING_RADIUS * k, 0.14, 0.012, gold)
	_ring(root, GOLD_RING_RADIUS * k - 0.35, 0.05, 0.012, gold)
	var inner := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = GOLD_RING_RADIUS * k - 0.42
	disc.bottom_radius = disc.top_radius
	disc.height = 0.01
	disc.radial_segments = 48
	inner.mesh = disc
	inner.material_override = GreyboxKit.material(Color("#2A1E1A"), 0.0, 0.3)
	inner.position = Vector3(0, 0.006, 0)
	root.add_child(inner)
	for i: int in 8:
		var a: float = TAU * float(i) / 8.0
		var ray := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(0.5, 2.6, 0.01)
		ray.mesh = pm
		ray.material_override = brass
		ray.rotation = Vector3(-PI * 0.5, a, 0)
		ray.position = Vector3(sin(a) * 1.3, 0.013, cos(a) * 1.3)
		root.add_child(ray)
	_ring(root, 0.45, 0.08, 0.016, gold)


# --- Vault door -------------------------------------------------------------------------------

static func _vault_door(root: Node3D, steel: Material, steel_dark: Material, brass: Material, k: float) -> void:
	var dz: float = door_z(k)
	var door := Node3D.new()
	door.name = "VaultDoor"
	door.position = Vector3(0, 2.9, dz)
	root.add_child(door)
	# Square brass-edged frame set into the wall, then the round door standing proud of it.
	_vis(door, Vector3(6.2, 5.6, 0.1), Vector3(0, -0.1, 0.05), steel_dark)
	_vis(door, Vector3(6.4, 0.18, 0.16), Vector3(0, 2.7, 0.08), brass)
	_vis(door, Vector3(6.4, 0.18, 0.16), Vector3(0, -2.88, 0.08), brass)
	for sx: float in [-1.0, 1.0]:
		_vis(door, Vector3(0.18, 5.8, 0.16), Vector3(sx * 3.1, -0.1, 0.08), brass)
	_disc(door, 2.55, 0.5, Vector3(0, 0, 0.3), steel, 40)
	_torus(door, 2.38, 2.62, Vector3(0, 0, 0.56), brass)
	_torus(door, 1.55, 1.68, Vector3(0, 0, 0.57), brass)
	_disc(door, 1.5, 0.12, Vector3(0, 0, 0.6), steel_dark, 32)
	# Locking bolts round the rim.
	for i: int in 16:
		var a: float = TAU * float(i) / 16.0
		_disc(door, 0.11, 0.12, Vector3(cos(a) * 2.05, sin(a) * 2.05, 0.6), brass, 10)
	# The hub and its three-spoke wheel handle.
	_disc(door, 0.42, 0.3, Vector3(0, 0, 0.75), brass, 20)
	for i: int in 3:
		var a: float = TAU * float(i) / 3.0 + 0.3
		var spoke := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.06
		cm.bottom_radius = 0.06
		cm.height = 2.2
		spoke.mesh = cm
		spoke.material_override = brass
		spoke.position = Vector3(0, 0, 0.92)
		spoke.rotation = Vector3(0, 0, a)
		door.add_child(spoke)
		_sphere(door, 0.12, Vector3(cos(a + PI * 0.5) * 1.1, sin(a + PI * 0.5) * 1.1, 0.92), brass)
		_sphere(door, 0.12, Vector3(-cos(a + PI * 0.5) * 1.1, -sin(a + PI * 0.5) * 1.1, 0.92), brass)
	# Hinge block on the right and a brass plaque over the door.
	_vis(door, Vector3(0.6, 2.4, 0.7), Vector3(2.75, 0, 0.35), steel_dark)
	for y: float in [-0.75, 0.75]:
		_disc(door, 0.2, 0.75, Vector3(2.75, y, 0.72), brass, 12)
	var plaque := Label3D.new()
	plaque.text = "LUCKY LOUNGE  ·  RESERVE"
	plaque.font = Vfx.font()
	plaque.font_size = 64
	plaque.pixel_size = 0.006
	plaque.modulate = Palette.VIP_GOLD
	plaque.outline_size = 0
	plaque.position = Vector3(0, 2.95, 0.12)
	plaque.shaded = true
	door.add_child(plaque)


## Rows of safe-deposit boxes on both long walls, between the door and the pillars.
static func _deposit_walls(root: Node3D, steel_dark: Material, brass: Material, k: float) -> void:
	var hx: float = half_x(k)
	var dz: float = door_z(k)
	var face: StandardMaterial3D = _metal(STEEL_LIGHT, 0.8, 0.35)
	for side: float in [-1.0, 1.0]:
		var x: float = side * (hx - 0.12)
		_vis(root, Vector3(0.16, 2.9, 5.0), Vector3(x + side * 0.02, 2.6, dz + 3.2), steel_dark)
		for row: int in 5:
			for col: int in 8:
				var z: float = dz + 1.0 + 0.58 * float(col)
				var y: float = 1.45 + 0.54 * float(row)
				_vis(root, Vector3(0.06, 0.46, 0.5), Vector3(x - side * 0.08, y, z), face)
				_vis(root, Vector3(0.05, 0.06, 0.14), Vector3(x - side * 0.13, y, z + 0.12), brass)


# --- Pillars, crates, gallery, lamps ------------------------------------------------------------

static func _pillars(root: Node3D, brass: Material, k: float) -> void:
	var marble: StandardMaterial3D = GreyboxKit.material(MARBLE.darkened(0.08), 0.0, 0.5)
	for p0: Vector3 in PILLARS:
		var p: Vector3 = flat(p0, k)
		var solid: Node3D = GreyboxKit.cylinder(root, 0.42, WALL_H, p + Vector3(0, WALL_H * 0.5, 0), MARBLE, "Pillar")
		(solid.get_node(^"Mesh") as MeshInstance3D).material_override = marble
		if PropModels.has(&"column"):
			(solid.get_node(^"Mesh") as Node3D).visible = false
			var col: Node3D = PropModels.make(&"column", WALL_H - 0.6)
			col.scale = Vector3(0.62, 1.0, 0.62)
			col.position.y = -WALL_H * 0.5 + 0.45
			for n: Node in col.find_children("*", "MeshInstance3D", true, false):
				(n as MeshInstance3D).material_override = marble
			solid.add_child(col)
		_vis(root, Vector3(1.2, 0.45, 1.2), p + Vector3(0, 0.225, 0), GreyboxKit.material(STEEL_DARK, 0.6, 0.45))
		_vis(root, Vector3(1.28, 0.06, 1.28), p + Vector3(0, 0.47, 0), brass)
		_vis(root, Vector3(1.0, 0.1, 1.0), p + Vector3(0, WALL_H - 0.45, 0), brass)


## Wooden crates banded in brass with gold bars stacked on top.
static func _crates(root: Node3D, brass: Material, k: float) -> void:
	var wood: StandardMaterial3D = GreyboxKit.material(WOOD, 0.0, 0.8)
	var bar: StandardMaterial3D = GreyboxKit.material(Color("#E8B84A"), 0.9, 0.25)
	for c: Array in CRATES:
		var at: Vector3 = flat(c[0], k)
		var size: Vector3 = c[1]
		var body: Node3D = GreyboxKit.box(root, size, at + Vector3(0, size.y * 0.5, 0), WOOD, "Crate")
		(body.get_node(^"Mesh") as MeshInstance3D).material_override = wood
		for t: float in [0.18, 0.82]:
			_vis(root, Vector3(size.x + 0.04, 0.08, size.z + 0.04), at + Vector3(0, size.y * t, 0), brass)
		# A neat pyramid of bars on the lid.
		var long_x: bool = size.x > size.z
		var n: int = 4 if maxf(size.x, size.z) > 2.0 else 3
		for layer: int in 2:
			for i: int in n - layer:
				var off: float = (float(i) - float(n - layer - 1) * 0.5) * 0.42
				var p: Vector3 = at + Vector3(off if long_x else 0.0, size.y + 0.07 + 0.13 * float(layer), 0.0 if long_x else off)
				var b := MeshInstance3D.new()
				var pm := PrismMesh.new()
				pm.left_to_right = 0.5
				pm.size = Vector3(0.36, 0.13, 0.7)
				b.mesh = pm
				b.material_override = bar
				b.position = p
				b.rotation.y = 0.0 if long_x else PI * 0.5
				root.add_child(b)


static func _gallery(root: Node3D, brass: Material, k: float) -> void:
	var hx: float = half_x(k)
	var bz: float = back_z(k)
	var gz: float = gallery_z(k)
	var depth: float = bz - gz
	var mid: float = gz + depth * 0.5
	var carpet: StandardMaterial3D = _tex("velvet", 1.5, Palette.VIP_BURGUNDY.lightened(0.15), 0.4, 0.9)
	_solid(root, Vector3(hx * 2.0, GALLERY_H, depth), Vector3(0, GALLERY_H * 0.5, mid), GreyboxKit.material(STEEL_DARK, 0.6, 0.45), "Gallery")
	var rug := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(hx * 2.0 - 0.6, depth - 0.5)
	rug.mesh = pm
	rug.material_override = carpet
	rug.position = Vector3(0, GALLERY_H + 0.012, mid + 0.1)
	root.add_child(rug)
	# Brass railing on the lip; an invisible wall up to head height keeps the two groups apart.
	_vis(root, Vector3(hx * 2.0, 0.08, 0.08), Vector3(0, GALLERY_H + 1.0, gz + 0.08), brass)
	_vis(root, Vector3(hx * 2.0, 0.05, 0.05), Vector3(0, GALLERY_H + 0.5, gz + 0.08), brass)
	var x: float = -hx + 0.4
	while x < hx:
		_vis(root, Vector3(0.06, 1.0, 0.06), Vector3(x, GALLERY_H + 0.5, gz + 0.08), brass)
		x += 0.8
	_vis(root, Vector3(hx * 2.0, 0.1, 0.12), Vector3(0, GALLERY_H - 0.05, gz + 0.02), brass)
	var wall := StaticBody3D.new()
	wall.name = "GalleryBarrier"
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(hx * 2.0, 3.6, 0.3)
	cs.shape = shape
	wall.add_child(cs)
	wall.position = Vector3(0, 1.8, gz)
	root.add_child(wall)
	# Velvet couches against the back wall for the ones who are out.
	if PropModels.has(&"couch"):
		for cx: float in [-5.0, 0.0, 5.0]:
			var couch: Node3D = PropModels.make(&"couch", 0.0, 2.4)
			couch.position = Vector3(cx * k, GALLERY_H, bz - 0.75)
			couch.rotation.y = PI
			root.add_child(couch)
	var sign := Label3D.new()
	sign.text = "OUT OF THE GAME"
	sign.font = Vfx.font()
	sign.font_size = 48
	sign.pixel_size = 0.006
	sign.modulate = Palette.CREAM
	sign.outline_size = 0
	sign.shaded = true
	sign.position = Vector3(0, GALLERY_H + 2.6, bz - 0.02)
	sign.rotation.y = PI
	root.add_child(sign)


## Warm brass pendant lamps over the floor and the gallery, sconces by the door.
static func _lamps(root: Node3D, brass: Material, k: float) -> void:
	var dz: float = door_z(k)
	var bz: float = back_z(k)
	var glow: StandardMaterial3D = Vfx.glow_material(Color(1.0, 0.85, 0.55))
	for p0: Vector3 in [Vector3(-4.0, 0, -3.0), Vector3(4.0, 0, -3.0), Vector3(-4.0, 0, 3.0), Vector3(4.0, 0, 3.0), Vector3(0, 0, 0)]:
		var p: Vector3 = flat(p0, k)
		var y: float = 4.4 if p != Vector3.ZERO else 4.9
		_vis(root, Vector3(0.03, WALL_H - y, 0.03), Vector3(p.x, (WALL_H + y) * 0.5, p.z), brass)
		var shade := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.12
		cm.bottom_radius = 0.55 if p != Vector3.ZERO else 0.8
		cm.height = 0.42
		cm.cap_bottom = false
		shade.mesh = cm
		shade.material_override = brass
		shade.position = Vector3(p.x, y, p.z)
		root.add_child(shade)
		var bulb := _sphere(root, 0.16, Vector3(p.x, y - 0.18, p.z), null)
		bulb.material_override = glow
		var l: OmniLight3D = GreyboxKit.lamp(root, Vector3(p.x, y - 0.5, p.z), 2.2 if p != Vector3.ZERO else 2.8, 11.0, LAMP)
		l.name = "VaultLamp"
	for sx: float in [-4.2, 4.2]:
		_vis(root, Vector3(0.3, 0.5, 0.15), Vector3(sx, 3.4, dz + 0.08), brass)
		var s := _sphere(root, 0.13, Vector3(sx, 3.75, dz + 0.2), null)
		s.material_override = glow
		GreyboxKit.lamp(root, Vector3(sx, 3.6, dz + 0.8), 1.0, 6.0, LAMP)
	for gx: float in [-5.0, 0.0, 5.0]:
		GreyboxKit.lamp(root, Vector3(gx, 4.2, bz - 1.5), 0.9, 7.0, LAMP)
	# A soft fill so the steel never goes black.
	var fill := OmniLight3D.new()
	fill.position = Vector3(0, 5.5, 1.5 * k)
	fill.light_color = Color(1.0, 0.9, 0.75)
	fill.light_energy = 0.8
	fill.omni_range = 20.0 * k
	root.add_child(fill)


# --- Helpers ----------------------------------------------------------------------------------

static func _solid(root: Node3D, size: Vector3, pos: Vector3, mat: Material, name: String) -> Node3D:
	var n: Node3D = GreyboxKit.box(root, size, pos, STEEL, name)
	(n.get_node(^"Mesh") as MeshInstance3D).material_override = mat
	return n


static func _vis(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


## A disc facing +z (a cylinder turned onto its side).
static func _disc(parent: Node3D, radius: float, depth: float, pos: Vector3, mat: Material, segments: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = depth
	cm.radial_segments = segments
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.rotation.x = PI * 0.5
	parent.add_child(mi)
	return mi


static func _torus(parent: Node3D, inner: float, outer: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = inner
	tm.outer_radius = outer
	tm.rings = 48
	tm.ring_segments = 8
	mi.mesh = tm
	mi.material_override = mat
	mi.position = pos
	mi.rotation.x = PI * 0.5
	parent.add_child(mi)
	return mi


## A flat ring on the floor (inlay).
static func _ring(root: Node3D, radius: float, width: float, y: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = radius - width * 0.5
	tm.outer_radius = radius + width * 0.5
	tm.rings = 64
	tm.ring_segments = 4
	mi.mesh = tm
	mi.material_override = mat
	mi.scale = Vector3(1.0, 0.06, 1.0)
	mi.position = Vector3(0, y, 0)
	root.add_child(mi)


static func _sphere(parent: Node3D, radius: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 12
	sm.rings = 6
	mi.mesh = sm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _metal(c: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metallic
	m.roughness = roughness
	return m


static func _tex(folder: String, metres: float, tint: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(TEX_DIR + folder + "/albedo.jpg") as Texture2D
	m.albedo_color = tint
	var normal_path: String = TEX_DIR + folder + "/normal.jpg"
	if ResourceLoader.exists(normal_path):
		m.normal_enabled = true
		m.normal_texture = load(normal_path) as Texture2D
		m.normal_scale = 0.4
	m.metallic = metallic
	m.roughness = roughness
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / metres
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m
