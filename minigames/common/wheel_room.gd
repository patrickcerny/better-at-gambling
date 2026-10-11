class_name WheelRoom
extends RefCounted
## The wheel room of Roulette Sumo: a dark, warm casino hall around a giant roulette wheel. The
## wheel (radius `RIM_RADIUS`, its deck `WHEEL_TOP` over the floor) stands on a walnut drum in a
## carpeted pit ringed by brass stanchions and velvet rope. The deck turns as one rotor: a polished
## walnut cone round a brass turret, the 37 red, black and green pockets of the casino's European
## wheel (`RouletteLogic.WHEEL_ORDER`, brass frets between them), a ring of numbered plates and a
## brass rim. Lucky watches from a croupier dais at the far wall under the room's sign; at the near
## end, behind a brass railing, a raised gallery with couches holds the beans who fell off.
##
## The deck's collision is a static cylinder (it is round, so it never has to turn with the
## rotor); the turret is a static pillar beans walk round. The stage turns `Rotor` to the server's
## wheel angle. `layout()` is pure data for the server, `build(parent)` makes the nodes, both
## around `WalkableLogicBase.ROOM_ORIGIN`. Local axes: -z is Lucky's dais, +z the gallery.

const HALF_X: float = 12.0
const FAR_Z: float = -13.0
const BACK_Z: float = 13.6
const GALLERY_Z: float = 9.4
const GALLERY_H: float = 2.0
const WALL_H: float = 8.0
const WALL_T: float = 0.5
## The wheel: centre (local, on the floor), deck height, rim radius, turret radius.
const CENTER: Vector3 = Vector3(0, 0, -1.6)
const WHEEL_TOP: float = 1.5
const RIM_RADIUS: float = 7.0
const HUB_RADIUS: float = 1.0
## Deck rings from the centre out: walnut cone, the pockets, the number plates, the rim track.
const CONE_R: float = 2.3
const POCKET_IN: float = 2.45
const POCKET_OUT: float = 5.6
const NUMBER_OUT: float = 6.45
## Beans start on this ring of the deck.
const SPAWN_RADIUS: float = 4.4
## Velvet-rope stanchions round the pit.
const ROPE_RADIUS: float = 9.6
## Lucky's croupier dais by the far wall.
const DAIS_H: float = 0.45
const LUCKY_SPOT: Vector3 = Vector3(0.0, DAIS_H, -11.6)
const MAX_SPOTS: int = 8

const WALNUT: Color = Color("#4A2E1D")
const WALNUT_DARK: Color = Color("#2B1A10")
const POCKET_BLACK: Color = Color("#1C1A19")
const LAMP: Color = Color(1.0, 0.8, 0.52)


## World-space description for the server.
static func layout() -> Dictionary:
	var o: Vector3 = WalkableLogicBase.ROOM_ORIGIN
	var c: Vector3 = center()
	var spawns: Array[Vector3] = []
	var yaws: Array[float] = []
	for i: int in MAX_SPOTS:
		var slot: int = [0, 4, 2, 6, 1, 5, 3, 7][i]
		var a: float = TAU * (float(slot) + 0.5) / float(MAX_SPOTS)
		var at: Vector3 = c + Vector3(sin(a) * SPAWN_RADIUS, WHEEL_TOP, cos(a) * SPAWN_RADIUS)
		spawns.append(at)
		var d: Vector3 = c - at
		yaws.append(atan2(-d.x, -d.z))  # facing the turret
	var spots: Array[Vector3] = []
	for i: int in MAX_SPOTS:
		var x: float = -8.4 + 16.8 * float(i) / float(MAX_SPOTS - 1)
		spots.append(o + Vector3(x, GALLERY_H, GALLERY_Z + 1.4 + (0.4 if i % 2 == 1 else 0.0)))
	# The arena holds the deck and the pit below it: a bean that fell is still in the room until
	# the server takes it out.
	var arena := AABB(o + Vector3(-HALF_X + 0.2, -1.0, FAR_Z + 0.2), Vector3((HALF_X - 0.2) * 2.0, WHEEL_TOP + 6.0, GALLERY_Z - FAR_Z - 0.4))
	var gallery := AABB(o + Vector3(-HALF_X + 0.2, GALLERY_H - 0.6, GALLERY_Z + 0.2), Vector3((HALF_X - 0.2) * 2.0, 4.5, BACK_Z - GALLERY_Z - 0.4))
	return {"arena": arena, "gallery": gallery, "spawns": spawns, "spawn_yaws": yaws, "gallery_spots": spots}


## The wheel's centre in world coordinates (on the floor; the deck is `WHEEL_TOP` above).
static func center() -> Vector3:
	return WalkableLogicBase.ROOM_ORIGIN + CENTER


## Builds the room under `parent` (at the world origin) at `WalkableLogicBase.ROOM_ORIGIN`.
static func build(parent: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "WheelRoom"
	parent.add_child(root)
	root.position = WalkableLogicBase.ROOM_ORIGIN
	var brass: StandardMaterial3D = VaultArena._tex("brass", 1.2, Color(1.0, 0.86, 0.6), 0.85, 0.32)
	_shell(root, brass)
	_wheel(root, brass)
	_pit(root, brass)
	_dais(root, brass)
	_gallery(root, brass)
	_lights(root, brass)
	return root


# --- Shell ------------------------------------------------------------------------------------

static func _shell(root: Node3D, brass: Material) -> void:
	var len_z: float = BACK_Z - FAR_Z
	var mid_z: float = (BACK_Z + FAR_Z) * 0.5
	var carpet: Material = VaultArena._tex("casino_carpet", 2.5, Color(0.62, 0.42, 0.4), 0.0, 0.95)
	var paper: StandardMaterial3D = VaultArena._tex("damask_wallpaper", 1.8, Color(0.42, 0.2, 0.2), 0.0, 0.85)
	var panels: StandardMaterial3D = VaultArena._tex("wooden_panels", 1.4, Color(0.55, 0.38, 0.28), 0.0, 0.6)
	var ceiling: StandardMaterial3D = VaultArena._tex("coffered_ceiling", 3.0, Color(0.45, 0.36, 0.3), 0.0, 0.8)
	var wood: StandardMaterial3D = GreyboxKit.material(WALNUT_DARK, 0.0, 0.55)
	VaultArena._solid(root, Vector3(HALF_X * 2.0 + 1.0, 0.4, len_z + 1.0), Vector3(0, -0.2, mid_z), carpet, "Floor")
	VaultArena._solid(root, Vector3(HALF_X * 2.0 + 1.0, 0.4, len_z + 1.0), Vector3(0, WALL_H + 0.2, mid_z), ceiling, "Ceiling")
	VaultArena._solid(root, Vector3(WALL_T, WALL_H, len_z + 1.0), Vector3(-HALF_X - WALL_T * 0.5, WALL_H * 0.5, mid_z), paper, "WallW")
	VaultArena._solid(root, Vector3(WALL_T, WALL_H, len_z + 1.0), Vector3(HALF_X + WALL_T * 0.5, WALL_H * 0.5, mid_z), paper, "WallE")
	VaultArena._solid(root, Vector3(HALF_X * 2.0, WALL_H, WALL_T), Vector3(0, WALL_H * 0.5, FAR_Z - WALL_T * 0.5), paper, "WallFar")
	VaultArena._solid(root, Vector3(HALF_X * 2.0, WALL_H, WALL_T), Vector3(0, WALL_H * 0.5, BACK_Z + WALL_T * 0.5), paper, "WallBack")
	# Wainscot to 1.4 m with a brass cap, skirting and a crown moulding.
	for side: float in [-1.0, 1.0]:
		var x: float = side * (HALF_X - 0.04)
		VaultArena._vis(root, Vector3(0.08, 1.4, len_z), Vector3(x, 0.7, mid_z), panels)
		VaultArena._vis(root, Vector3(0.12, 0.06, len_z), Vector3(x - side * 0.02, 1.42, mid_z), brass)
		VaultArena._vis(root, Vector3(0.2, 0.26, len_z), Vector3(x - side * 0.06, WALL_H - 0.13, mid_z), wood)
	for z_wall: float in [FAR_Z + 0.04, BACK_Z - 0.04]:
		var inward: float = 1.0 if z_wall < 0.0 else -1.0
		VaultArena._vis(root, Vector3(HALF_X * 2.0, 1.4, 0.08), Vector3(0, 0.7, z_wall), panels)
		VaultArena._vis(root, Vector3(HALF_X * 2.0, 0.06, 0.12), Vector3(0, 1.42, z_wall + inward * 0.02), brass)
		VaultArena._vis(root, Vector3(HALF_X * 2.0, 0.26, 0.2), Vector3(0, WALL_H - 0.13, z_wall + inward * 0.06), wood)
	# Marble columns in the corners and along the long walls.
	var marble: StandardMaterial3D = GreyboxKit.material(VaultArena.MARBLE.darkened(0.12), 0.0, 0.45)
	for p: Vector3 in [Vector3(-10.6, 0, -11.6), Vector3(10.6, 0, -11.6), Vector3(-10.6, 0, -1.6), Vector3(10.6, 0, -1.6), Vector3(-10.6, 0, 7.8), Vector3(10.6, 0, 7.8)]:
		var solid: Node3D = GreyboxKit.cylinder(root, 0.42, WALL_H, p + Vector3(0, WALL_H * 0.5, 0), VaultArena.MARBLE, "Column")
		(solid.get_node(^"Mesh") as MeshInstance3D).material_override = marble
		if PropModels.has(&"column"):
			(solid.get_node(^"Mesh") as Node3D).visible = false
			var col: Node3D = PropModels.make(&"column", WALL_H)
			col.scale = Vector3(0.65, 1.0, 0.65)
			col.position.y = -WALL_H * 0.5
			for n: Node in col.find_children("*", "MeshInstance3D", true, false):
				(n as MeshInstance3D).material_override = marble
			solid.add_child(col)
	# Gilt frames between the columns.
	for side: float in [-1.0, 1.0]:
		for z: float in [-6.6, 3.2]:
			if PropModels.has(&"picture"):
				var pic: Node3D = PropModels.make(&"picture", 0.0, 1.6)
				pic.position = Vector3(side * (HALF_X - 0.06), 2.9, z)
				pic.rotation = Vector3(0, -side * PI * 0.5, 0)
				root.add_child(pic)
			else:
				VaultArena._vis(root, Vector3(0.06, 1.2, 1.6), Vector3(side * (HALF_X - 0.06), 2.9, z), brass)


# --- The wheel --------------------------------------------------------------------------------

static func _wheel(root: Node3D, brass: Material) -> void:
	var w := Node3D.new()
	w.name = "Wheel"
	w.position = CENTER
	root.add_child(w)
	# Collision: the deck (a round drum) and the turret pillar. Neither turns.
	var body := StaticBody3D.new()
	body.name = "WheelBody"
	w.add_child(body)
	var deck := CollisionShape3D.new()
	var dshape := CylinderShape3D.new()
	dshape.radius = RIM_RADIUS
	dshape.height = WHEEL_TOP
	deck.shape = dshape
	deck.position.y = WHEEL_TOP * 0.5
	body.add_child(deck)
	var hub := CollisionShape3D.new()
	var hshape := CylinderShape3D.new()
	hshape.radius = HUB_RADIUS
	hshape.height = 2.4
	hub.shape = hshape
	hub.position.y = WHEEL_TOP + 1.2
	body.add_child(hub)
	# The drum the wheel rests on: walnut staves with brass bands (static).
	var walnut: StandardMaterial3D = GreyboxKit.material(WALNUT, 0.0, 0.42)
	var walnut_dark: StandardMaterial3D = GreyboxKit.material(WALNUT_DARK, 0.0, 0.5)
	ParlorRoom._cyl(w, RIM_RADIUS - 0.25, WHEEL_TOP - 0.2, Vector3(0, (WHEEL_TOP - 0.2) * 0.5, 0), walnut_dark, 64)
	ParlorRoom._cyl(w, RIM_RADIUS - 0.1, 0.12, Vector3(0, 0.12, 0), brass, 64)
	ParlorRoom._cyl(w, RIM_RADIUS - 0.18, 0.06, Vector3(0, WHEEL_TOP * 0.55, 0), brass, 64)
	for i: int in 24:
		var a: float = TAU * float(i) / 24.0
		var stave: MeshInstance3D = VaultArena._vis(w, Vector3(0.08, WHEEL_TOP - 0.35, 0.05), Vector3(sin(a), 0.0, cos(a)) * (RIM_RADIUS - 0.22) + Vector3(0, (WHEEL_TOP - 0.2) * 0.5, 0), brass)
		stave.rotation.y = a
	# The rotor: everything on the deck turns with the server's wheel angle.
	var rotor := Node3D.new()
	rotor.name = "Rotor"
	rotor.position.y = WHEEL_TOP
	w.add_child(rotor)
	ParlorRoom._cyl(rotor, RIM_RADIUS, 0.2, Vector3(0, -0.1, 0), walnut, 72)  # deck slab and rim track
	_cone(rotor, walnut)
	rotor.add_child(_pocket_ring())
	_frets(rotor, brass)
	_number_ring(rotor)
	var rim_ring := Node3D.new()
	rim_ring.position.y = 0.02
	rotor.add_child(rim_ring)
	VaultArena._ring(rim_ring, POCKET_IN - 0.06, 0.08, 0.0, brass)
	VaultArena._ring(rim_ring, POCKET_OUT + 0.02, 0.06, 0.0, brass)
	VaultArena._ring(rim_ring, NUMBER_OUT + 0.04, 0.06, 0.0, brass)
	var lip := MeshInstance3D.new()
	lip.name = "BrassRim"
	var tm := TorusMesh.new()
	tm.inner_radius = RIM_RADIUS - 0.12
	tm.outer_radius = RIM_RADIUS + 0.06
	tm.rings = 96
	tm.ring_segments = 8
	lip.mesh = tm
	lip.material_override = brass
	lip.scale = Vector3(1.0, 0.7, 1.0)
	lip.position.y = 0.0
	rotor.add_child(lip)
	_turret(rotor, brass)


## The polished walnut centre round the turret, with brass inlay spokes.
static func _cone(rotor: Node3D, walnut: Material) -> void:
	var c := MeshInstance3D.new()
	c.name = "Cone"
	var cm := CylinderMesh.new()
	cm.top_radius = HUB_RADIUS + 0.2
	cm.bottom_radius = CONE_R
	cm.height = 0.12
	cm.radial_segments = 48
	c.mesh = cm
	var m: StandardMaterial3D = (walnut as StandardMaterial3D).duplicate()
	m.albedo_color = WALNUT.lightened(0.12)
	m.roughness = 0.28
	c.material_override = m
	c.position.y = 0.06
	rotor.add_child(c)
	var inlay: StandardMaterial3D = GreyboxKit.material(Palette.WARM_GOLD, 0.8, 0.35)
	for i: int in 8:
		var a: float = TAU * float(i) / 8.0
		var mid: float = (HUB_RADIUS + CONE_R) * 0.5 + 0.1
		var s: MeshInstance3D = VaultArena._vis(rotor, Vector3(0.06, 0.02, CONE_R - HUB_RADIUS - 0.2), Vector3(sin(a), 0.0, cos(a)) * mid + Vector3(0, 0.1, 0), inlay)
		s.rotation.y = a


## The 37 pockets as one mesh: a wedge per number in the casino wheel's order and colours.
static func _pocket_ring() -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n: int = RouletteLogic.WHEEL_ORDER.size()
	var y: float = 0.025
	for i: int in n:
		var num: int = RouletteLogic.WHEEL_ORDER[i]
		var col: Color = pocket_color(num)
		var a0: float = TAU * float(i) / float(n)
		var a1: float = TAU * float(i + 1) / float(n)
		var steps: int = 3
		for k: int in steps:
			var b0: float = lerpf(a0, a1, float(k) / float(steps))
			var b1: float = lerpf(a0, a1, float(k + 1) / float(steps))
			var p0 := Vector3(sin(b0) * POCKET_IN, y, cos(b0) * POCKET_IN)
			var p1 := Vector3(sin(b0) * POCKET_OUT, y, cos(b0) * POCKET_OUT)
			var p2 := Vector3(sin(b1) * POCKET_OUT, y, cos(b1) * POCKET_OUT)
			var p3 := Vector3(sin(b1) * POCKET_IN, y, cos(b1) * POCKET_IN)
			for v: Vector3 in [p0, p2, p1, p0, p3, p2]:
				st.set_color(col)
				st.set_normal(Vector3.UP)
				st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.name = "Pockets"
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.5
	m.metallic_specular = 0.6
	mi.material_override = m
	return mi


## Felt-like pocket colour of a number (the casino table's red, black and green).
static func pocket_color(num: int) -> Color:
	if num == 0:
		return Palette.FELT_GREEN.lightened(0.08)
	return Palette.CASINO_RED.darkened(0.12) if num in RouletteLogic.RED else POCKET_BLACK


## Low brass frets between the pockets, and a diamond deflector every few pockets.
static func _frets(rotor: Node3D, brass: Material) -> void:
	var n: int = RouletteLogic.WHEEL_ORDER.size()
	var length: float = POCKET_OUT - POCKET_IN
	for i: int in n:
		var a: float = TAU * float(i) / float(n)
		var f: MeshInstance3D = VaultArena._vis(rotor, Vector3(0.07, 0.05, length), Vector3(sin(a), 0.0, cos(a)) * (POCKET_IN + length * 0.5) + Vector3(0, 0.05, 0), brass)
		f.rotation.y = a
	for i: int in 8:
		var a: float = TAU * (float(i) + 0.5) / 8.0
		var d: MeshInstance3D = VaultArena._vis(rotor, Vector3(0.24, 0.05, 0.42), Vector3(sin(a), 0.0, cos(a)) * (RIM_RADIUS - 0.28) + Vector3(0, 0.03, 0), brass)
		d.rotation = Vector3(0, a + PI * 0.25, 0)


## The number plates: a coloured plate per pocket with its number, read from outside the wheel.
static func _number_ring(rotor: Node3D) -> void:
	var n: int = RouletteLogic.WHEEL_ORDER.size()
	var mid: float = (POCKET_OUT + NUMBER_OUT) * 0.5
	var plate_w: float = TAU * mid / float(n) - 0.08
	for i: int in n:
		var num: int = RouletteLogic.WHEEL_ORDER[i]
		var a: float = TAU * (float(i) + 0.5) / float(n)
		var p: MeshInstance3D = VaultArena._vis(rotor, Vector3(plate_w, 0.03, NUMBER_OUT - POCKET_OUT - 0.12), Vector3(sin(a), 0.0, cos(a)) * mid + Vector3(0, 0.02, 0), GreyboxKit.material(pocket_color(num).lightened(0.05), 0.0, 0.55))
		p.rotation.y = a
		var l := Label3D.new()
		l.text = str(num)
		l.font = Vfx.font()
		l.font_size = 96
		l.pixel_size = 0.0042
		l.modulate = Palette.CREAM
		l.outline_size = 0
		l.shaded = true
		l.double_sided = false
		l.position = Vector3(sin(a), 0.0, cos(a)) * mid + Vector3(0, 0.045, 0)
		l.rotation = Vector3(-PI * 0.5, a, 0)
		rotor.add_child(l)


## The turret: a brass cone and spindle with a four-armed cross of ball knobs on top.
static func _turret(rotor: Node3D, brass: Material) -> void:
	var t := Node3D.new()
	t.name = "Turret"
	rotor.add_child(t)
	var cone := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.32
	cm.bottom_radius = HUB_RADIUS
	cm.height = 0.9
	cm.radial_segments = 32
	cone.mesh = cm
	cone.material_override = brass
	cone.position.y = 0.45
	t.add_child(cone)
	ParlorRoom._cyl(t, HUB_RADIUS + 0.06, 0.1, Vector3(0, 0.05, 0), GreyboxKit.material(WALNUT_DARK, 0.0, 0.4), 32)
	ParlorRoom._cyl(t, 0.14, 1.5, Vector3(0, 1.6, 0), brass, 16)
	VaultArena._sphere(t, 0.3, Vector3(0, 1.0, 0), brass)
	var cross := Node3D.new()
	cross.name = "Cross"
	cross.position.y = 2.3
	t.add_child(cross)
	for i: int in 4:
		var a: float = TAU * float(i) / 4.0
		var arm: MeshInstance3D = VaultArena._vis(cross, Vector3(0.12, 0.12, 1.0), Vector3(sin(a), 0.0, cos(a)) * 0.5, brass)
		arm.rotation.y = a
		VaultArena._sphere(cross, 0.17, Vector3(sin(a), 0.0, cos(a)) * 1.02, brass)
	VaultArena._sphere(cross, 0.22, Vector3(0, 0.18, 0), brass)


# --- Pit, dais, gallery -----------------------------------------------------------------------

## The pit round the wheel: a darker carpet ring with a rope net on it, and brass stanchions with
## velvet rope at `ROPE_RADIUS` (visual: whoever lands here is already out).
static func _pit(root: Node3D, brass: Material) -> void:
	var pit := Node3D.new()
	pit.name = "Pit"
	pit.position = CENTER
	root.add_child(pit)
	var carpet: Material = LoungeDecor._carpet(Palette.VIP_BURGUNDY.darkened(0.25), Palette.VIP_BURGUNDY.darkened(0.55), 1.0) if Vfx.enabled() else GreyboxKit.material(Palette.VIP_BURGUNDY.darkened(0.3))
	ParlorRoom._cyl(pit, ROPE_RADIUS, 0.02, Vector3(0, 0.01, 0), carpet, 64)
	var rope: StandardMaterial3D = GreyboxKit.material(Palette.CREAM.darkened(0.45), 0.0, 0.9)
	# The safety net: rope rings and spokes on the pit floor.
	for r: float in [RIM_RADIUS + 0.4, RIM_RADIUS + 1.1, RIM_RADIUS + 1.8]:
		var ring := Node3D.new()
		ring.position.y = 0.06
		pit.add_child(ring)
		VaultArena._ring(ring, r, 0.05, 0.0, rope)
		ring.scale.y = 3.0
	for i: int in 48:
		var a: float = TAU * float(i) / 48.0
		var span: float = ROPE_RADIUS - RIM_RADIUS
		var s: MeshInstance3D = VaultArena._vis(pit, Vector3(0.04, 0.03, span), Vector3(sin(a), 0.0, cos(a)) * (RIM_RADIUS + span * 0.5) + Vector3(0, 0.05, 0), rope)
		s.rotation.y = a
	var velvet: StandardMaterial3D = VaultArena._tex("velvet", 1.0, Palette.VIP_BURGUNDY.lightened(0.1), 0.0, 0.9)
	var posts: int = 20
	for i: int in posts:
		var a: float = TAU * float(i) / float(posts)
		var p := Vector3(sin(a), 0.0, cos(a)) * ROPE_RADIUS
		if (CENTER + p).z > GALLERY_Z - 0.6:
			continue
		ParlorRoom._cyl(pit, 0.05, 0.95, p + Vector3(0, 0.475, 0), brass, 10)
		ParlorRoom._cyl(pit, 0.2, 0.05, p + Vector3(0, 0.025, 0), brass, 14)
		VaultArena._sphere(pit, 0.08, p + Vector3(0, 0.98, 0), brass)
		var b: float = TAU * float(i + 1) / float(posts)
		var q := Vector3(sin(b), 0.0, cos(b)) * ROPE_RADIUS
		if (CENTER + q).z > GALLERY_Z - 0.6:
			continue
		var mid: Vector3 = (p + q) * 0.5 + Vector3(0, 0.78, 0)
		var seg: MeshInstance3D = VaultArena._vis(pit, Vector3(0.06, 0.06, p.distance_to(q)), mid, velvet)
		seg.rotation.y = atan2(q.x - p.x, q.z - p.z)


static func _dais(root: Node3D, brass: Material) -> void:
	var depth: float = 3.0
	var wood: StandardMaterial3D = GreyboxKit.material(WALNUT_DARK, 0.0, 0.5)
	VaultArena._solid(root, Vector3(6.0, DAIS_H, depth), Vector3(0, DAIS_H * 0.5, FAR_Z + depth * 0.5), wood, "Dais")
	VaultArena._vis(root, Vector3(6.06, 0.05, 0.06), Vector3(0, DAIS_H - 0.02, FAR_Z + depth + 0.01), brass)
	var top := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(5.8, depth - 0.2)
	top.mesh = pm
	top.material_override = VaultArena._tex("velvet", 1.2, Palette.VIP_BURGUNDY.lightened(0.1), 0.0, 0.9)
	top.position = Vector3(0, DAIS_H + 0.005, FAR_Z + depth * 0.5)
	root.add_child(top)
	# A croupier's lectern next to Lucky, with a little roulette rake on it.
	var lectern := Node3D.new()
	lectern.name = "Lectern"
	lectern.position = Vector3(-1.4, DAIS_H, FAR_Z + 1.6)
	root.add_child(lectern)
	VaultArena._vis(lectern, Vector3(0.7, 1.05, 0.5), Vector3(0, 0.525, 0), GreyboxKit.material(WALNUT, 0.0, 0.45))
	VaultArena._vis(lectern, Vector3(0.8, 0.05, 0.6), Vector3(0, 1.07, 0), brass)
	VaultArena._vis(lectern, Vector3(0.04, 0.03, 0.9), Vector3(0.1, 1.12, 0.05), GreyboxKit.material(WALNUT_DARK, 0.0, 0.4))
	VaultArena._vis(lectern, Vector3(0.24, 0.05, 0.05), Vector3(0.1, 1.12, 0.48), GreyboxKit.material(WALNUT_DARK, 0.0, 0.4))
	var sign := Label3D.new()
	sign.text = "ROULETTE SUMO"
	sign.font = Vfx.font()
	sign.font_size = 96
	sign.pixel_size = 0.008
	sign.modulate = Palette.VIP_GOLD
	sign.outline_size = 0
	sign.shaded = true
	sign.position = Vector3(0, 5.6, FAR_Z + 0.08)
	root.add_child(sign)
	var sub := Label3D.new()
	sub.text = "LAST BEAN ON THE WHEEL WINS"
	sub.font = Vfx.font()
	sub.font_size = 48
	sub.pixel_size = 0.006
	sub.modulate = Palette.CREAM
	sub.outline_size = 0
	sub.shaded = true
	sub.position = Vector3(0, 4.7, FAR_Z + 0.08)
	root.add_child(sub)
	VaultArena._vis(root, Vector3(9.0, 0.06, 0.08), Vector3(0, 4.25, FAR_Z + 0.06), brass)


static func _gallery(root: Node3D, brass: Material) -> void:
	var depth: float = BACK_Z - GALLERY_Z
	var mid: float = GALLERY_Z + depth * 0.5
	VaultArena._solid(root, Vector3(HALF_X * 2.0, GALLERY_H, depth), Vector3(0, GALLERY_H * 0.5, mid), GreyboxKit.material(WALNUT_DARK, 0.0, 0.5), "Gallery")
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
	wall.position = Vector3(0, GALLERY_H + 1.8, GALLERY_Z)
	root.add_child(wall)
	if PropModels.has(&"couch"):
		for cx: float in [-6.0, 0.0, 6.0]:
			var couch: Node3D = PropModels.make(&"couch", 0.0, 2.4)
			couch.position = Vector3(cx, GALLERY_H, BACK_Z - 0.75)
			couch.rotation.y = PI
			root.add_child(couch)
	var sign := Label3D.new()
	sign.text = "OFF THE WHEEL"
	sign.font = Vfx.font()
	sign.font_size = 48
	sign.pixel_size = 0.006
	sign.modulate = Palette.CREAM
	sign.outline_size = 0
	sign.shaded = true
	sign.position = Vector3(0, GALLERY_H + 2.8, BACK_Z - 0.02)
	sign.rotation.y = PI
	root.add_child(sign)


static func _lights(root: Node3D, brass: Material) -> void:
	var glow: StandardMaterial3D = Vfx.glow_material(Color(1.0, 0.85, 0.55))
	# A great brass chandelier ring over the wheel.
	var ch := Node3D.new()
	ch.name = "Chandelier"
	ch.position = CENTER + Vector3(0, 6.6, 0)
	root.add_child(ch)
	VaultArena._vis(ch, Vector3(0.04, WALL_H - 6.6, 0.04), Vector3(0, (WALL_H - 6.6) * 0.5, 0), brass)
	var ring := Node3D.new()
	ch.add_child(ring)
	VaultArena._ring(ring, 2.4, 0.1, 0.0, brass)
	ring.scale = Vector3(1.0, 10.0, 1.0)
	for i: int in 16:
		var a: float = TAU * float(i) / 16.0
		var p := Vector3(sin(a) * 2.4, 0.08, cos(a) * 2.4)
		VaultArena._vis(ch, Vector3(0.06, 0.16, 0.06), p, GreyboxKit.material(Palette.CREAM, 0.0, 0.6))
		var bulb: MeshInstance3D = VaultArena._sphere(ch, 0.07, p + Vector3(0, 0.14, 0), null)
		bulb.material_override = glow
		if i % 4 == 0:
			var spoke: MeshInstance3D = VaultArena._vis(ch, Vector3(0.03, 0.03, 2.4), Vector3(sin(a), 0, cos(a)) * 1.2, brass)
			spoke.rotation.y = a
	var spot := SpotLight3D.new()
	spot.name = "WheelSpot"
	spot.light_color = Color(1.0, 0.86, 0.62)
	spot.light_energy = 3.2
	spot.spot_range = 10.0
	spot.spot_angle = 48.0
	spot.position = CENTER + Vector3(0, 7.4, 0)
	spot.rotation.x = -PI * 0.5
	root.add_child(spot)
	var main: OmniLight3D = GreyboxKit.lamp(root, CENTER + Vector3(0, 6.0, 0), 1.6, 14.0, LAMP)
	main.name = "ChandelierLight"
	# Sconces on the long walls, lamps over the dais and the gallery.
	for side: float in [-1.0, 1.0]:
		for z: float in [-9.0, -4.2, 0.8, 5.6]:
			var at := Vector3(side * (HALF_X - 0.12), 3.0, z)
			VaultArena._vis(root, Vector3(0.12, 0.4, 0.22), at, brass)
			var b: MeshInstance3D = VaultArena._sphere(root, 0.12, at + Vector3(-side * 0.16, 0.28, 0), null)
			b.material_override = glow
			GreyboxKit.lamp(root, at + Vector3(-side * 0.8, 0.3, 0), 0.9, 6.5, LAMP)
	GreyboxKit.lamp(root, LUCKY_SPOT + Vector3(0, 3.2, 1.4), 1.2, 7.0, LAMP)
	for gx: float in [-6.0, 0.0, 6.0]:
		GreyboxKit.lamp(root, Vector3(gx, 4.6, BACK_Z - 1.8), 0.8, 7.0, LAMP)
	var fill := OmniLight3D.new()
	fill.position = Vector3(0, 7.0, 0.0)
	fill.light_color = Color(1.0, 0.86, 0.7)
	fill.light_energy = 0.55
	fill.omni_range = 26.0
	root.add_child(fill)
