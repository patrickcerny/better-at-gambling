class_name ItemArt
extends RefCounted
## Hand-built 3D models for the items that have no model file (`ItemModels.MODELS`): each one a
## little low-poly figure out of primitive parts in the warm casino palette (gold, cream, burgundy,
## felt green; no neon, see docs/ART_DIRECTION.md), with an `ItemIdle` animation so it lives in the
## hand: the monkey's tail sways, the reels spin, the flames flicker.
##
## Models are built about one unit tall, y up and -z forward (the side others see when the bean
## holds it out); `ItemModels.make` scales them to the item's hand size and centres them. The
## parts that move sit under pivot nodes, never the root.

const RECIPES: Array[StringName] = [
	&"bad_luck_monkey", &"banana_peel", &"black_cat", &"bodyguard", &"bouncer", &"boxing_glove",
	&"bribe", &"credit_card", &"double_down", &"energy_drink", &"fake_cash", &"get_out_of_jail_free",
	&"golden_chip", &"grease", &"hot_hands", &"jackpot_magnet", &"loaded_reels", &"lucky_clover",
	&"mirror", &"out_of_order", &"pickpocket", &"robin_hood", &"rock_paper_scissors", &"scissors",
	&"sunglasses", &"vip_pass", &"wild_card",
]

const FUR := Color(0.42, 0.26, 0.15)
const SKIN := Color(0.86, 0.69, 0.52)
const CAT := Color(0.09, 0.08, 0.09)
const SILVER := Color(0.78, 0.78, 0.8)
const BANANA := Color(0.96, 0.8, 0.28)
const BILL := Color(0.47, 0.63, 0.43)
const LEATHER := Color(0.36, 0.2, 0.12)
const WOOD := Color(0.5, 0.31, 0.16)
const BUTTER := Color(0.98, 0.86, 0.45)
const NAVY := Color(0.13, 0.17, 0.3)
const LEAF := Color(0.25, 0.58, 0.28)
const FLAME_RED := Color(0.95, 0.3, 0.1)
const FLAME_ORANGE := Color(1.0, 0.58, 0.15)
const FLAME_YELLOW := Color(1.0, 0.85, 0.35)

static var _mats: Dictionary = {}
static var _meshes: Dictionary = {}


static func has(item: StringName) -> bool:
	return item in RECIPES


## A new model of `item` (null when there is no recipe), its `ItemIdle` already running.
static func build(item: StringName) -> Node3D:
	if not has(item):
		return null
	var root := Node3D.new()
	root.name = "Art_" + String(item).to_pascal_case()
	var idle := ItemIdle.new()
	var fn: StringName = StringName("_" + String(item))
	ItemArt.new().call(fn, root, idle)
	root.add_child(idle)
	for n: Node in root.find_children("*", "GeometryInstance3D", true, false):
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


# --- Materials and parts ------------------------------------------------------------------------

static func mat(c: Color, metal: float = 0.0, rough: float = 0.7, glow: float = 0.0, alpha: float = 1.0) -> StandardMaterial3D:
	var key: String = "%s|%.2f|%.2f|%.2f|%.2f" % [c.to_html(), metal, rough, glow, alpha]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c, alpha)
	m.metallic = metal
	m.roughness = rough
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = glow
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats[key] = m
	return m


static func gold() -> StandardMaterial3D:
	return mat(Palette.WARM_GOLD, 0.55, 0.32)


static func _mesh(key: String, make: Callable) -> Mesh:
	if not _meshes.has(key):
		_meshes[key] = make.call()
	return _meshes[key]


static func _put(p: Node3D, mesh: Mesh, pos: Vector3, m: Material, rot: Vector3 = Vector3.ZERO, scale: Vector3 = Vector3.ONE, name: String = "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	if name != "":
		mi.name = name
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation_degrees = rot
	mi.scale = scale
	p.add_child(mi)
	return mi


static func box(p: Node3D, size: Vector3, pos: Vector3, m: Material, rot: Vector3 = Vector3.ZERO, name: String = "") -> MeshInstance3D:
	var mesh: Mesh = _mesh("box", func() -> Mesh: return BoxMesh.new())
	return _put(p, mesh, pos, m, rot, size, name)


## An ellipsoid with radii `r`.
static func ball(p: Node3D, r: Vector3, pos: Vector3, m: Material, rot: Vector3 = Vector3.ZERO, segs: int = 14, name: String = "") -> MeshInstance3D:
	var mesh: Mesh = _mesh("ball%d" % segs, func() -> Mesh:
		var s := SphereMesh.new()
		s.radius = 1.0
		s.height = 2.0
		s.radial_segments = segs
		s.rings = maxi(4, segs / 2)
		return s)
	return _put(p, mesh, pos, m, rot, r, name)


## A cylinder (a cone when `top` is 0) along y, `h` tall, centred on `pos`.
static func cyl(p: Node3D, top: float, bottom: float, h: float, pos: Vector3, m: Material, rot: Vector3 = Vector3.ZERO, segs: int = 16, name: String = "") -> MeshInstance3D:
	var key: String = "cyl%.3f|%.3f|%d" % [top, bottom, segs]
	var mesh: Mesh = _mesh(key, func() -> Mesh:
		var c := CylinderMesh.new()
		c.top_radius = top
		c.bottom_radius = bottom
		c.height = 1.0
		c.radial_segments = segs
		c.rings = 1
		return c)
	return _put(p, mesh, pos, m, rot, Vector3(1.0, h, 1.0), name)


## A ring about y (`TorusMesh`), the tube from `inner` to `outer` radius.
static func ring(p: Node3D, inner: float, outer: float, pos: Vector3, m: Material, rot: Vector3 = Vector3.ZERO, scale: Vector3 = Vector3.ONE, name: String = "") -> MeshInstance3D:
	var key: String = "ring%.3f|%.3f" % [inner, outer]
	var mesh: Mesh = _mesh(key, func() -> Mesh:
		var t := TorusMesh.new()
		t.inner_radius = inner
		t.outer_radius = outer
		t.rings = 24
		t.ring_segments = 8
		return t)
	return _put(p, mesh, pos, m, rot, scale, name)


## Raised letters facing -z.
static func text(p: Node3D, s: String, px: float, pos: Vector3, m: Material, rot: Vector3 = Vector3.ZERO, depth: float = 0.02) -> MeshInstance3D:
	var key: String = "text%s|%.3f|%.3f" % [s, px, depth]
	var mesh: Mesh = _mesh(key, func() -> Mesh:
		var t := TextMesh.new()
		t.text = s
		t.font_size = 64
		t.pixel_size = px
		t.depth = depth
		t.curve_step = 2.0
		return t)
	# TextMesh faces +z; turn it to face -z.
	return _put(p, mesh, pos, m, rot + Vector3(0, 180, 0))


static func pivot(p: Node3D, name: String, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.name = name
	n.position = pos
	n.rotation_degrees = rot
	p.add_child(n)
	return n


## A chain of balls from `from` along `dirs` (one step per entry), radius tapering to `r_end`.
static func chain(p: Node3D, from: Vector3, dirs: Array[Vector3], r: float, r_end: float, m: Material) -> void:
	var at: Vector3 = from
	var n: int = dirs.size()
	for i: int in n:
		at += dirs[i]
		var rr: float = lerpf(r, r_end, float(i) / maxf(1.0, n - 1))
		ball(p, Vector3.ONE * rr, at, m, Vector3.ZERO, 10)


## A five-pointed star in the x-y plane, facing -z.
static func star(p: Node3D, pos: Vector3, size: float, m: Material) -> Node3D:
	var s: Node3D = pivot(p, "Star", pos)
	cyl(s, size * 0.42, size * 0.42, size * 0.18, Vector3.ZERO, m, Vector3(90, 0, 0), 5)
	for i: int in 5:
		var a: float = TAU * i / 5.0
		var dir := Vector3(sin(a), cos(a), 0.0)
		cyl(s, 0.0, size * 0.22, size * 0.62, dir * size * 0.55, m, Vector3(0, 0, -rad_to_deg(a)), 4)
	return s


# --- Recipes ------------------------------------------------------------------------------------
# Each builds into `r` (about one unit tall) and adds its animation tracks to `idle`.

func _bad_luck_monkey(r: Node3D, idle: ItemIdle) -> void:
	var fur: Material = mat(FUR, 0.0, 0.85)
	var skin: Material = mat(SKIN, 0.0, 0.7)
	var dark: Material = mat(Palette.CASINO_BLACK, 0.0, 0.3)
	var body: Node3D = pivot(r, "Body", Vector3(0, 0.0, 0))
	ball(body, Vector3(0.27, 0.3, 0.24), Vector3(0, 0.32, 0), fur)
	ball(body, Vector3(0.17, 0.2, 0.08), Vector3(0, 0.3, -0.18), skin)
	for sx: float in [-1.0, 1.0]:
		ball(body, Vector3(0.07, 0.2, 0.07), Vector3(sx * 0.27, 0.3, -0.06), fur, Vector3(0, 0, sx * 15))
		ball(body, Vector3(0.07, 0.06, 0.07), Vector3(sx * 0.3, 0.1, -0.1), skin)
		ball(body, Vector3(0.1, 0.07, 0.13), Vector3(sx * 0.14, 0.05, -0.1), fur)
	var head: Node3D = pivot(r, "Head", Vector3(0, 0.6, 0))
	ball(head, Vector3(0.24, 0.22, 0.22), Vector3(0, 0.15, 0), fur)
	ball(head, Vector3(0.17, 0.13, 0.1), Vector3(0, 0.1, -0.16), skin)
	for sx: float in [-1.0, 1.0]:
		ball(head, Vector3(0.09, 0.09, 0.04), Vector3(sx * 0.25, 0.17, 0), fur)
		ball(head, Vector3(0.06, 0.06, 0.03), Vector3(sx * 0.25, 0.17, -0.02), skin)
		var eye: MeshInstance3D = ball(head, Vector3(0.035, 0.04, 0.02), Vector3(sx * 0.07, 0.2, -0.2), dark)
		idle.add(eye, ItemIdle.Kind.BLINK, 0.0, 3.7, Vector3.UP, 0.0)
	box(head, Vector3(0.08, 0.012, 0.01), Vector3(0, 0.06, -0.255), dark)  # mouth
	# A little red fez with a gold tassel: the bad luck sits in style.
	cyl(head, 0.075, 0.095, 0.12, Vector3(0.03, 0.39, 0), mat(Palette.CASINO_RED, 0.0, 0.6), Vector3(0, 0, -10))
	var tassel: Node3D = pivot(head, "Tassel", Vector3(0.04, 0.45, 0))
	cyl(tassel, 0.008, 0.008, 0.1, Vector3(0.04, -0.05, 0), gold(), Vector3(0, 0, 50))
	ball(tassel, Vector3.ONE * 0.025, Vector3(0.08, -0.09, 0), gold())
	idle.add(tassel, ItemIdle.Kind.SWING, 0.5, 4.0, Vector3.FORWARD)
	idle.add(head, ItemIdle.Kind.SWING, 0.18, 1.6, Vector3.FORWARD)
	var tail: Node3D = pivot(r, "Tail", Vector3(0, 0.18, 0.22))
	chain(tail, Vector3.ZERO, [Vector3(0, -0.02, 0.07), Vector3(0, 0.03, 0.07), Vector3(0, 0.08, 0.04), Vector3(0, 0.08, 0.0), Vector3(0, 0.06, -0.04), Vector3(0, 0.02, -0.06)], 0.035, 0.025, fur)
	idle.add(tail, ItemIdle.Kind.SWING, 0.45, 2.2, Vector3.UP)
	idle.add(body, ItemIdle.Kind.PULSE, 0.03, 3.0, Vector3(0.6, 1.0, 0.6))


func _banana_peel(r: Node3D, idle: ItemIdle) -> void:
	var peel: Material = mat(BANANA, 0.0, 0.55)
	var inner: Material = mat(Color(0.98, 0.94, 0.78), 0.0, 0.7)
	var brown: Material = mat(Color(0.35, 0.24, 0.12), 0.0, 0.8)
	cyl(r, 0.06, 0.1, 0.35, Vector3(0, 0.75, 0), peel)
	cyl(r, 0.035, 0.06, 0.1, Vector3(0, 0.97, 0), brown)
	ball(r, Vector3(0.1, 0.1, 0.1), Vector3(0, 0.56, 0), inner)
	for i: int in 4:
		var flap: Node3D = pivot(r, "Flap%d" % i, Vector3(0, 0.56, 0), Vector3(0, 45 + i * 90, 0))
		var tilt: Node3D = pivot(flap, "Tilt", Vector3.ZERO, Vector3(-145, 0, 0))
		ball(tilt, Vector3(0.11, 0.32, 0.035), Vector3(0, 0.3, 0.0), peel, Vector3.ZERO, 12)
		ball(tilt, Vector3(0.085, 0.28, 0.02), Vector3(0, 0.29, 0.022), inner, Vector3.ZERO, 12)
		ball(tilt, Vector3(0.045, 0.045, 0.03), Vector3(0, 0.6, 0.0), brown)
		idle.add(tilt, ItemIdle.Kind.SWING, 0.12, 2.6, Vector3.RIGHT, i * 1.4)


func _black_cat(r: Node3D, idle: ItemIdle) -> void:
	var fur: Material = mat(CAT, 0.1, 0.45)
	var pink: Material = mat(Color(0.86, 0.5, 0.55), 0.0, 0.6)
	var eye: Material = mat(Palette.COIN_GOLD, 0.0, 0.3, 0.6)
	var pupil: Material = mat(Palette.CASINO_BLACK, 0.0, 0.2)
	ball(r, Vector3(0.22, 0.27, 0.27), Vector3(0, 0.28, 0.06), fur)
	for sx: float in [-1.0, 1.0]:
		ball(r, Vector3(0.07, 0.17, 0.07), Vector3(sx * 0.11, 0.17, -0.15), fur)
		ball(r, Vector3(0.075, 0.05, 0.09), Vector3(sx * 0.11, 0.03, -0.19), fur)
	var head: Node3D = pivot(r, "Head", Vector3(0, 0.6, -0.12))
	ball(head, Vector3(0.21, 0.18, 0.18), Vector3(0, 0.05, 0), fur)
	for sx: float in [-1.0, 1.0]:
		cyl(head, 0.0, 0.075, 0.15, Vector3(sx * 0.12, 0.24, 0.02), fur, Vector3(0, 0, -sx * 18), 4)
		cyl(head, 0.0, 0.045, 0.1, Vector3(sx * 0.115, 0.22, -0.01), pink, Vector3(0, 0, -sx * 18), 4)
		var e: Node3D = pivot(head, "Eye", Vector3(sx * 0.08, 0.08, -0.155))
		ball(e, Vector3(0.05, 0.055, 0.025), Vector3.ZERO, eye)
		ball(e, Vector3(0.014, 0.045, 0.02), Vector3(0, 0, -0.012), pupil)
		idle.add(e, ItemIdle.Kind.BLINK, 0.0, 4.3, Vector3.UP)
		for wy: float in [-0.012, 0.012]:
			box(head, Vector3(0.16, 0.006, 0.006), Vector3(sx * 0.17, wy, -0.13), mat(Palette.CREAM), Vector3(0, sx * 10, sx * wy * 600))
	ball(head, Vector3(0.025, 0.02, 0.02), Vector3(0, 0.0, -0.18), pink)
	# Gold collar with a bell.
	ring(r, 0.13, 0.155, Vector3(0, 0.47, -0.09), gold(), Vector3(-15, 0, 0))
	ball(r, Vector3.ONE * 0.035, Vector3(0, 0.42, -0.24), gold())
	idle.add(head, ItemIdle.Kind.SWING, 0.12, 1.3, Vector3.FORWARD, 0.5)
	var tail: Node3D = pivot(r, "Tail", Vector3(0, 0.1, 0.3))
	chain(tail, Vector3.ZERO, [Vector3(0, 0.02, 0.06), Vector3(0, 0.08, 0.04), Vector3(0, 0.09, 0.0), Vector3(0, 0.09, -0.01), Vector3(0.02, 0.08, -0.02), Vector3(0.04, 0.06, -0.03), Vector3(0.05, 0.03, -0.02)], 0.04, 0.03, fur)
	idle.add(tail, ItemIdle.Kind.SWING, 0.4, 1.8, Vector3.FORWARD)


func _bodyguard(r: Node3D, idle: ItemIdle) -> void:
	# A security badge: a navy shield, a gold rim and a gold star.
	var badge: Node3D = pivot(r, "Badge", Vector3(0, 0.5, 0))
	var navy: Material = mat(NAVY, 0.2, 0.45)
	box(badge, Vector3(0.66, 0.5, 0.1), Vector3(0, 0.15, 0.02), gold())
	box(badge, Vector3(0.48, 0.48, 0.1), Vector3(0, -0.17, 0.02), gold(), Vector3(0, 0, 45))
	box(badge, Vector3(0.58, 0.44, 0.1), Vector3(0, 0.15, 0.0), navy)
	box(badge, Vector3(0.41, 0.41, 0.1), Vector3(0, -0.16, 0.0), navy, Vector3(0, 0, 45))
	var st: Node3D = star(badge, Vector3(0, 0.02, -0.06), 0.3, gold())
	text(badge, "SECURITY", 0.0016, Vector3(0, 0.31, -0.055), mat(Palette.CREAM, 0.0, 0.5), Vector3.ZERO, 0.01)
	idle.add(st, ItemIdle.Kind.PULSE, 0.08, 3.0, Vector3.ONE)
	idle.add(badge, ItemIdle.Kind.SWING, 0.25, 1.4, Vector3.UP)


func _bouncer(r: Node3D, idle: ItemIdle) -> void:
	# A velvet-rope stanchion: brass post, the rope swinging from its top.
	cyl(r, 0.2, 0.22, 0.05, Vector3(0, 0.025, 0), gold())
	cyl(r, 0.05, 0.1, 0.06, Vector3(0, 0.08, 0), gold())
	cyl(r, 0.035, 0.035, 0.78, Vector3(0, 0.48, 0), gold())
	ball(r, Vector3.ONE * 0.075, Vector3(0, 0.9, 0), gold())
	ring(r, 0.035, 0.05, Vector3(0, 0.82, 0), gold(), Vector3(90, 0, 0))
	var rope: Node3D = pivot(r, "Rope", Vector3(0.0, 0.82, 0))
	var velvet: Material = mat(Palette.VIP_BURGUNDY, 0.0, 0.9)
	var pts: Array[Vector3] = []
	for i: int in 9:
		var f: float = i / 8.0
		pts.append(Vector3(0.06 + f * 0.48, -0.36 * sin(f * PI * 0.9) - f * 0.08, 0.0))
	for i: int in pts.size():
		ball(rope, Vector3.ONE * 0.045, pts[i], velvet, Vector3.ZERO, 10)
		if i > 0:
			var mid: Vector3 = (pts[i] + pts[i - 1]) * 0.5
			ball(rope, Vector3.ONE * 0.045, mid, velvet, Vector3.ZERO, 10)
	box(rope, Vector3(0.05, 0.1, 0.05), pts[pts.size() - 1] + Vector3(0.03, 0.03, 0), gold())
	idle.add(rope, ItemIdle.Kind.SWING, 0.3, 2.0, Vector3.RIGHT)


func _boxing_glove(r: Node3D, idle: ItemIdle) -> void:
	# A boxing glove on a spring, bouncing on a wooden handle.
	cyl(r, 0.07, 0.07, 0.28, Vector3(0, 0.14, 0), mat(WOOD, 0.0, 0.6))
	cyl(r, 0.09, 0.09, 0.04, Vector3(0, 0.29, 0), gold())
	var spring: Node3D = pivot(r, "Spring", Vector3(0, 0.3, 0))
	for i: int in 6:
		ring(spring, 0.055, 0.075, Vector3(0, 0.03 + i * 0.05, 0), mat(SILVER, 0.6, 0.3), Vector3(8, 0, 0))
	var top: Node3D = pivot(r, "Glove", Vector3(0, 0.62, 0))
	var red: Material = mat(Palette.CASINO_RED, 0.1, 0.35)
	cyl(top, 0.12, 0.11, 0.12, Vector3(0, 0.02, 0), mat(Palette.CREAM, 0.0, 0.6))
	ball(top, Vector3(0.19, 0.2, 0.21), Vector3(0, 0.22, -0.02), red)
	ball(top, Vector3(0.08, 0.12, 0.08), Vector3(0.17, 0.17, -0.06), red, Vector3(0, 0, -25))
	box(top, Vector3(0.2, 0.012, 0.02), Vector3(0, 0.1, -0.2), mat(Palette.CREAM), Vector3(-30, 0, 0))
	idle.add(spring, ItemIdle.Kind.PULSE, 0.22, 5.0, Vector3.UP)
	idle.add(top, ItemIdle.Kind.BOB, 0.065, 5.0, Vector3.UP)


func _bribe(r: Node3D, idle: ItemIdle) -> void:
	# A fat envelope with cash peeking out and a red wax seal.
	var paper: Material = mat(Color(0.93, 0.87, 0.72), 0.0, 0.8)
	var cash: Node3D = pivot(r, "Cash", Vector3(0, 0.55, 0.0))
	for i: int in 3:
		box(cash, Vector3(0.62, 0.32, 0.012), Vector3((i - 1) * 0.03, 0.0 + i * 0.015, 0.02 - i * 0.015), mat(BILL, 0.0, 0.8), Vector3(0, 0, (i - 1) * 4))
	box(cash, Vector3(0.12, 0.33, 0.06), Vector3(0, 0.0, 0.0), mat(Palette.WARM_GOLD, 0.3, 0.5))
	text(cash, "$", 0.006, Vector3(0.18, 0.08, -0.03), mat(Color(0.2, 0.35, 0.2)), Vector3.ZERO, 0.01)
	box(r, Vector3(0.78, 0.5, 0.08), Vector3(0, 0.3, 0), paper)
	box(r, Vector3(0.4, 0.4, 0.02), Vector3(0, 0.38, -0.045), paper, Vector3(0, 0, 45))
	cyl(r, 0.06, 0.06, 0.03, Vector3(0, 0.25, -0.06), mat(Palette.CASINO_RED, 0.1, 0.4), Vector3(90, 0, 0))
	idle.add(cash, ItemIdle.Kind.BOB, 0.06, 2.5, Vector3.UP)


func _credit_card(r: Node3D, idle: ItemIdle) -> void:
	var card: Node3D = pivot(r, "Card", Vector3(0, 0.5, 0))
	box(card, Vector3(0.86, 0.54, 0.03), Vector3.ZERO, mat(Palette.VIP_GOLD, 0.5, 0.3))
	box(card, Vector3(0.86, 0.11, 0.005), Vector3(0, 0.13, 0.017), mat(Palette.CASINO_BLACK, 0.2, 0.4))
	box(card, Vector3(0.13, 0.1, 0.008), Vector3(-0.26, 0.04, -0.018), mat(Color(0.85, 0.75, 0.55), 0.95, 0.2))
	text(card, "4000 1234 5678", 0.0019, Vector3(0.0, -0.09, -0.018), mat(Palette.WARM_CHARCOAL, 0.3, 0.5), Vector3.ZERO, 0.006)
	text(card, "GOLD", 0.0022, Vector3(0.28, 0.17, -0.018), mat(Palette.VIP_BURGUNDY), Vector3.ZERO, 0.006)
	var glint: MeshInstance3D = box(card, Vector3(0.05, 0.6, 0.004), Vector3(0, 0, -0.019), mat(Color(1, 0.97, 0.85), 0.0, 0.2, 0.8, 0.55), Vector3(0, 0, -25))
	idle.add(glint, ItemIdle.Kind.SLIDE, 0.33, 0.45, Vector3.RIGHT)
	idle.add(card, ItemIdle.Kind.SWING, 0.3, 1.2, Vector3.UP)


func _die(p: Node3D, pos: Vector3, name: String) -> Node3D:
	var d: Node3D = pivot(p, name, pos)
	box(d, Vector3.ONE * 0.3, Vector3.ZERO, mat(Palette.CASINO_RED, 0.1, 0.25))
	var pip: Material = mat(Palette.CREAM, 0.0, 0.5)
	# Faces: 1 front, 6 back, 2 right, 5 left, 3 top, 4 bottom.
	var faces: Array = [
		[Vector3(0, 0, -1), [Vector2.ZERO]],
		[Vector3(0, 0, 1), [Vector2(-1, -1), Vector2(-1, 0), Vector2(-1, 1), Vector2(1, -1), Vector2(1, 0), Vector2(1, 1)]],
		[Vector3(1, 0, 0), [Vector2(-1, -1), Vector2(1, 1)]],
		[Vector3(-1, 0, 0), [Vector2(-1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2.ZERO]],
		[Vector3(0, 1, 0), [Vector2(-1, -1), Vector2.ZERO, Vector2(1, 1)]],
		[Vector3(0, -1, 0), [Vector2(-1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1)]],
	]
	for f: Array in faces:
		var nrm: Vector3 = f[0]
		var u: Vector3 = Vector3.UP if absf(nrm.y) < 0.5 else Vector3.RIGHT
		var v: Vector3 = nrm.cross(u)
		for q: Vector2 in f[1]:
			ball(d, Vector3(0.032, 0.032, 0.032), nrm * 0.15 + (u * q.x + v * q.y) * 0.085, pip, Vector3.ZERO, 8)
	return d


func _double_down(r: Node3D, idle: ItemIdle) -> void:
	var orbit: Node3D = pivot(r, "Orbit", Vector3(0, 0.45, 0))
	var a: Node3D = _die(orbit, Vector3(-0.2, 0.08, 0), "DieA")
	var b: Node3D = _die(orbit, Vector3(0.2, -0.08, 0), "DieB")
	a.rotation_degrees = Vector3(20, 30, 10)
	b.rotation_degrees = Vector3(-15, -40, 25)
	idle.add(orbit, ItemIdle.Kind.SPIN, 0.0, 1.2, Vector3.UP)
	idle.add(a, ItemIdle.Kind.SPIN, 0.0, 2.1, Vector3(1, 1, 0))
	idle.add(b, ItemIdle.Kind.SPIN, 0.0, -1.7, Vector3(0, 1, 1))


func _energy_drink(r: Node3D, idle: ItemIdle) -> void:
	var can: Node3D = pivot(r, "Can", Vector3(0, 0.0, 0))
	var body: Material = mat(Palette.FELT_GREEN, 0.6, 0.3)
	cyl(can, 0.26, 0.26, 0.82, Vector3(0, 0.45, 0), body, Vector3.ZERO, 20)
	cyl(can, 0.22, 0.26, 0.05, Vector3(0, 0.885, 0), mat(SILVER, 0.6, 0.28), Vector3.ZERO, 20)
	cyl(can, 0.26, 0.22, 0.05, Vector3(0, 0.015, 0), mat(SILVER, 0.6, 0.28), Vector3.ZERO, 20)
	cyl(can, 0.265, 0.265, 0.16, Vector3(0, 0.66, 0), mat(Palette.CREAM, 0.2, 0.5), Vector3.ZERO, 20)
	text(can, "VOLT", 0.0042, Vector3(0, 0.66, -0.262), mat(Palette.CASINO_RED, 0.0, 0.5), Vector3.ZERO, 0.02)
	# Lightning bolt.
	var bolt: Node3D = pivot(can, "Bolt", Vector3(0, 0.38, -0.27))
	var g: Material = mat(Palette.COIN_GOLD, 0.6, 0.3, 0.3)
	box(bolt, Vector3(0.07, 0.2, 0.02), Vector3(0.03, 0.08, 0), g, Vector3(0, 0, -25))
	box(bolt, Vector3(0.12, 0.05, 0.02), Vector3(0, 0, 0), g, Vector3(0, 0, 10))
	box(bolt, Vector3(0.07, 0.2, 0.02), Vector3(-0.03, -0.08, 0), g, Vector3(0, 0, -25))
	ring(can, 0.03, 0.045, Vector3(0.05, 0.92, 0), mat(SILVER, 0.6, 0.3), Vector3(0, 0, 0), Vector3(1, 0.4, 1.4))
	var bubble: Material = mat(Color(0.85, 1.0, 0.85), 0.0, 0.1, 0.4, 0.6)
	for i: int in 4:
		var b: MeshInstance3D = ball(can, Vector3.ONE * (0.035 + 0.01 * (i % 2)), Vector3(-0.06 + i * 0.04, 0.93, -0.05 + (i % 2) * 0.08), bubble, Vector3.ZERO, 8)
		idle.add(b, ItemIdle.Kind.RISE, 0.35, 0.8, Vector3.UP, i * 0.27)
	idle.add(can, ItemIdle.Kind.SWING, 0.035, 22.0, Vector3.FORWARD)


func _fake_cash(r: Node3D, idle: ItemIdle) -> void:
	# A wad of bills that are a shade too purple, a "?" on the band.
	var bill: Material = mat(Color(0.52, 0.55, 0.62), 0.0, 0.8)
	var bill2: Material = mat(Color(0.58, 0.5, 0.64), 0.0, 0.8)
	for i: int in 6:
		box(r, Vector3(0.8, 0.04, 0.42), Vector3(0, 0.05 + i * 0.045, 0), bill if i % 2 == 0 else bill2, Vector3(0, (i % 3 - 1) * 4, 0))
	box(r, Vector3(0.16, 0.3, 0.44), Vector3(0, 0.17, 0), mat(Palette.CREAM, 0.0, 0.7))
	text(r, "?", 0.006, Vector3(0, 0.17, -0.23), mat(Palette.CASINO_RED), Vector3.ZERO, 0.01)
	var top: Node3D = pivot(r, "TopBill", Vector3(-0.4, 0.32, 0))
	box(top, Vector3(0.8, 0.015, 0.42), Vector3(0.4, 0, 0), bill2)
	text(top, "$", 0.006, Vector3(0.62, 0.01, 0), mat(Color(0.3, 0.3, 0.4)), Vector3(-90, 0, 0), 0.005)
	idle.add(top, ItemIdle.Kind.SWING, 0.18, 3.5, Vector3.FORWARD)


func _get_out_of_jail_free(r: Node3D, idle: ItemIdle) -> void:
	# A big gold key on a ring, a cream tag that says FREE.
	ring(r, 0.09, 0.12, Vector3(0, 0.92, 0), gold(), Vector3(90, 0, 0))
	var key: Node3D = pivot(r, "Key", Vector3(0, 0.82, 0))
	ring(key, 0.07, 0.11, Vector3(0, -0.06, 0), gold(), Vector3(90, 0, 0))
	cyl(key, 0.03, 0.03, 0.5, Vector3(0, -0.4, 0), gold(), Vector3.ZERO, 10)
	box(key, Vector3(0.12, 0.05, 0.035), Vector3(0.07, -0.58, 0), gold())
	box(key, Vector3(0.08, 0.05, 0.035), Vector3(0.05, -0.5, 0), gold())
	box(key, Vector3(0.1, 0.03, 0.04), Vector3(0, -0.18, 0), gold())
	var tag: Node3D = pivot(r, "Tag", Vector3(-0.05, 0.85, 0))
	cyl(tag, 0.006, 0.006, 0.18, Vector3(-0.06, -0.07, 0), mat(Palette.CASINO_RED), Vector3(0, 0, -40))
	box(tag, Vector3(0.24, 0.14, 0.012), Vector3(-0.15, -0.2, 0), mat(Palette.CREAM, 0.0, 0.7), Vector3(0, 0, -10))
	text(tag, "FREE", 0.0022, Vector3(-0.15, -0.2, -0.008), mat(Palette.CASINO_RED), Vector3(0, 0, -10), 0.005)
	idle.add(key, ItemIdle.Kind.SWING, 0.22, 1.9, Vector3.FORWARD)
	idle.add(tag, ItemIdle.Kind.SWING, 0.3, 2.3, Vector3.FORWARD, 1.0)


func _golden_chip(r: Node3D, idle: ItemIdle) -> void:
	var chip: Node3D = pivot(r, "Chip", Vector3(0, 0.5, 0))
	var face: Node3D = pivot(chip, "Face", Vector3.ZERO, Vector3(90, 0, 0))
	cyl(face, 0.5, 0.5, 0.12, Vector3.ZERO, mat(Palette.COIN_GOLD, 0.55, 0.28), Vector3.ZERO, 28)
	var cream: Material = mat(Palette.CREAM, 0.0, 0.5)
	for i: int in 8:
		var a: float = TAU * i / 8.0
		box(face, Vector3(0.1, 0.125, 0.1), Vector3(sin(a), 0, cos(a)) * 0.455, cream, Vector3(0, rad_to_deg(a), 0))
	ring(face, 0.3, 0.34, Vector3(0, 0.06, 0), cream)
	ring(face, 0.3, 0.34, Vector3(0, -0.06, 0), cream)
	text(chip, "$", 0.008, Vector3(0, 0, -0.065), mat(Palette.VIP_BURGUNDY, 0.2, 0.4), Vector3.ZERO, 0.02)
	text(chip, "$", 0.008, Vector3(0, 0, 0.065), mat(Palette.VIP_BURGUNDY, 0.2, 0.4), Vector3(0, 180, 0), 0.02)
	idle.add(chip, ItemIdle.Kind.SPIN, 0.0, 1.8, Vector3.UP)


func _grease(r: Node3D, idle: ItemIdle) -> void:
	# A stick of butter on a little dish, a drip running off it.
	cyl(r, 0.46, 0.4, 0.06, Vector3(0, 0.03, 0), mat(Palette.CREAM, 0.1, 0.35), Vector3.ZERO, 24)
	ring(r, 0.42, 0.47, Vector3(0, 0.06, 0), gold())
	var butter: Material = mat(BUTTER, 0.1, 0.25)
	box(r, Vector3(0.62, 0.26, 0.3), Vector3(0, 0.2, 0), butter, Vector3(0, -12, 0))
	box(r, Vector3(0.3, 0.27, 0.31), Vector3(0.18, 0.2, 0.04), mat(Palette.WARM_GOLD, 0.7, 0.35), Vector3(0, -12, 0))
	text(r, "BUTTER", 0.0018, Vector3(-0.1, 0.22, -0.172), mat(Palette.VIP_BURGUNDY), Vector3(0, -12, 0), 0.005)
	ball(r, Vector3(0.05, 0.03, 0.05), Vector3(-0.3, 0.335, -0.02), butter)
	var drip: MeshInstance3D = ball(r, Vector3(0.04, 0.055, 0.04), Vector3(-0.32, 0.26, -0.12), butter, Vector3.ZERO, 10)
	idle.add(drip, ItemIdle.Kind.RISE, -0.22, 0.6, Vector3.UP)
	var shine: MeshInstance3D = box(r, Vector3(0.04, 0.005, 0.26), Vector3(0, 0.335, 0), mat(Color(1, 1, 0.9), 0.0, 0.1, 0.7, 0.6), Vector3(0, -12, 0))
	idle.add(shine, ItemIdle.Kind.SLIDE, 0.22, 0.5, Vector3(cos(deg_to_rad(12)), 0, sin(deg_to_rad(12))))


func _hot_hands(r: Node3D, idle: ItemIdle) -> void:
	# A fanned hand of three aces, on fire.
	var hand: Node3D = pivot(r, "Cards", Vector3(0, 0.0, 0))
	var paper: Material = mat(Palette.CREAM, 0.0, 0.6)
	var red: Material = mat(Palette.CASINO_RED, 0.0, 0.5)
	for i: int in 3:
		var c: Node3D = pivot(hand, "Card%d" % i, Vector3(0, 0.1, 0), Vector3(0, 0, (1 - i) * 20))
		box(c, Vector3(0.38, 0.55, 0.012), Vector3(0, 0.3, i * -0.015), paper)
		box(c, Vector3(0.12, 0.12, 0.014), Vector3(0, 0.3, i * -0.015 - 0.003), red, Vector3(0, 0, 45))
		text(c, "A", 0.0025, Vector3(-0.12, 0.5, i * -0.015 - 0.008), red, Vector3.ZERO, 0.004)
	var fire: Node3D = pivot(r, "Fire", Vector3(0, 0.62, 0.0))
	var cols: Array[Color] = [FLAME_RED, FLAME_ORANGE, FLAME_YELLOW, FLAME_ORANGE, FLAME_RED]
	for i: int in 5:
		var fx: float = (i - 2) * 0.12
		var h: float = 0.32 - absf(i - 2) * 0.06
		var f: Node3D = pivot(fire, "Flame%d" % i, Vector3(fx, -0.05, 0.01 - (i % 2) * 0.03))
		cyl(f, 0.0, 0.08 - absf(i - 2) * 0.01, h, Vector3(0, h * 0.5, 0), mat(cols[i], 0.0, 0.5, 1.4, 0.92), Vector3.ZERO, 7)
		ball(f, Vector3(0.075, 0.06, 0.075) * (1.0 - absf(i - 2) * 0.12), Vector3(0, 0.02, 0), mat(cols[i], 0.0, 0.5, 1.4, 0.92), Vector3.ZERO, 8)
		idle.add(f, ItemIdle.Kind.FLICKER, 0.3, 9.0 + i, Vector3.UP, i * 1.3)
	idle.add(hand, ItemIdle.Kind.SWING, 0.08, 1.5, Vector3.FORWARD)


func _jackpot_magnet(r: Node3D, idle: ItemIdle) -> void:
	var red: Material = mat(Palette.CASINO_RED, 0.2, 0.35)
	var tip: Material = mat(SILVER, 0.6, 0.3)
	var mag: Node3D = pivot(r, "Magnet", Vector3(0, 0.0, 0))
	var n: int = 9
	for i: int in n:
		var a: float = PI * i / (n - 1)
		box(mag, Vector3(0.16, 0.13, 0.18), Vector3(cos(a) * 0.24, 0.62 + sin(a) * 0.24, 0), red, Vector3(0, 0, rad_to_deg(a) + 90))
	for sx: float in [-1.0, 1.0]:
		box(mag, Vector3(0.16, 0.3, 0.18), Vector3(sx * 0.24, 0.47, 0), red)
		box(mag, Vector3(0.165, 0.12, 0.185), Vector3(sx * 0.24, 0.27, 0), tip)
	var orbit: Node3D = pivot(r, "Coins", Vector3(0, 0.15, 0))
	var coin: Material = mat(Palette.COIN_GOLD, 0.55, 0.28)
	for i: int in 3:
		var a2: float = TAU * i / 3.0
		var c: Node3D = pivot(orbit, "Coin%d" % i, Vector3(cos(a2) * 0.32, (i - 1) * 0.04, sin(a2) * 0.32))
		cyl(c, 0.08, 0.08, 0.025, Vector3.ZERO, coin, Vector3(70, rad_to_deg(a2), 0), 14)
		idle.add(c, ItemIdle.Kind.BOB, 0.04, 4.0, Vector3.UP, i * 2.0)
	idle.add(orbit, ItemIdle.Kind.SPIN, 0.0, 2.2, Vector3.UP)
	idle.add(mag, ItemIdle.Kind.SWING, 0.08, 1.4, Vector3.FORWARD)


func _loaded_reels(r: Node3D, idle: ItemIdle) -> void:
	# A tiny slot machine: burgundy cabinet, gold trim, three reels spinning, a lever.
	var cab: Material = mat(Palette.VIP_BURGUNDY, 0.2, 0.4)
	box(r, Vector3(0.8, 0.62, 0.42), Vector3(0, 0.36, 0), cab)
	box(r, Vector3(0.86, 0.06, 0.46), Vector3(0, 0.04, 0), gold())
	box(r, Vector3(0.86, 0.06, 0.46), Vector3(0, 0.69, 0), gold())
	cyl(r, 0.21, 0.21, 0.86, Vector3(0, 0.72, 0.03), cab, Vector3(0, 0, 90), 16)
	text(r, "777", 0.003, Vector3(0, 0.79, -0.19), mat(Palette.COIN_GOLD, 0.8, 0.3, 0.3), Vector3(-20, 0, 0), 0.02)
	box(r, Vector3(0.68, 0.24, 0.02), Vector3(0, 0.38, -0.205), mat(Palette.CASINO_BLACK, 0.0, 0.3))
	var syms: Array[Color] = [Palette.CASINO_RED, Palette.COIN_GOLD, Palette.FELT_GREEN, Palette.CASINO_BLACK]
	for i: int in 3:
		var reel: Node3D = pivot(r, "Reel%d" % i, Vector3((i - 1) * 0.21, 0.38, -0.12))
		cyl(reel, 0.14, 0.14, 0.17, Vector3.ZERO, mat(Palette.CREAM, 0.0, 0.5), Vector3(0, 0, 90), 12)
		for k: int in 6:
			var a: float = TAU * k / 6.0
			box(reel, Vector3(0.09, 0.07, 0.03), Vector3(0, sin(a), -cos(a)) * 0.14, mat(syms[(k + i) % 4], 0.2, 0.4), Vector3(rad_to_deg(a), 0, 0))
		idle.add(reel, ItemIdle.Kind.SPIN, 0.0, 6.0 + i * 2.5, Vector3.RIGHT)
	var lever: Node3D = pivot(r, "Lever", Vector3(0.43, 0.35, 0))
	cyl(lever, 0.025, 0.025, 0.4, Vector3(0.0, 0.2, 0), gold(), Vector3.ZERO, 8)
	ball(lever, Vector3.ONE * 0.06, Vector3(0.0, 0.42, 0), mat(Palette.CASINO_RED, 0.2, 0.3))
	idle.add(lever, ItemIdle.Kind.SWING, 0.35, 2.0, Vector3.RIGHT)


func _lucky_clover(r: Node3D, idle: ItemIdle) -> void:
	var leaf: Material = mat(LEAF, 0.0, 0.5)
	var dark: Material = mat(LEAF.darkened(0.3), 0.0, 0.6)
	cyl(r, 0.022, 0.03, 0.42, Vector3(0.03, 0.21, 0), dark, Vector3(0, 0, -8), 8)
	var top: Node3D = pivot(r, "Leaves", Vector3(0.05, 0.62, 0), Vector3(-15, 0, 0))
	for i: int in 4:
		var lp: Node3D = pivot(top, "Leaf%d" % i, Vector3.ZERO, Vector3(0, 0, 45 + i * 90))
		# A heart: two lobes and a point toward the middle.
		ball(lp, Vector3(0.1, 0.13, 0.025), Vector3(-0.07, 0.2, 0), leaf, Vector3(0, 0, 25))
		ball(lp, Vector3(0.1, 0.13, 0.025), Vector3(0.07, 0.2, 0), leaf, Vector3(0, 0, -25))
		ball(lp, Vector3(0.08, 0.1, 0.022), Vector3(0, 0.1, 0), leaf)
		box(lp, Vector3(0.012, 0.22, 0.03), Vector3(0, 0.15, -0.01), dark)
	ball(top, Vector3.ONE * 0.04, Vector3(0, 0, -0.01), dark)
	# A ladybug for luck.
	var bug: Node3D = pivot(top, "Ladybug", Vector3(0.18, 0.18, -0.03))
	ball(bug, Vector3(0.045, 0.045, 0.03), Vector3.ZERO, mat(Palette.CASINO_RED, 0.1, 0.3))
	ball(bug, Vector3(0.022, 0.022, 0.02), Vector3(0, 0.04, -0.005), mat(Palette.CASINO_BLACK))
	idle.add(top, ItemIdle.Kind.SWING, 0.35, 1.2, Vector3.UP)
	idle.add(bug, ItemIdle.Kind.BOB, 0.02, 3.0, Vector3.UP)


func _mirror(r: Node3D, idle: ItemIdle) -> void:
	# A gold hand mirror.
	cyl(r, 0.045, 0.06, 0.4, Vector3(0, 0.2, 0), gold(), Vector3.ZERO, 10)
	ball(r, Vector3.ONE * 0.06, Vector3(0, 0.0, 0), gold())
	var head: Node3D = pivot(r, "Head", Vector3(0, 0.66, 0))
	ring(head, 0.25, 0.3, Vector3.ZERO, gold(), Vector3(90, 0, 0), Vector3(1, 1, 1.25))
	cyl(head, 0.26, 0.26, 0.04, Vector3(0, 0, 0.012), mat(Palette.VIP_BURGUNDY, 0.1, 0.4), Vector3(90, 0, 0), 24).scale = Vector3(1, 0.04, 1.25)
	var glass: MeshInstance3D = cyl(head, 0.25, 0.25, 0.02, Vector3(0, 0, -0.012), mat(Color(0.72, 0.82, 0.9), 0.35, 0.05, 0.25), Vector3(90, 0, 0), 24)
	glass.scale = Vector3(1, 0.02, 1.25)
	ball(head, Vector3.ONE * 0.05, Vector3(0, 0.36, 0), gold())
	var glint: MeshInstance3D = box(head, Vector3(0.05, 0.36, 0.004), Vector3(0, 0, -0.024), mat(Color.WHITE, 0.0, 0.1, 1.0, 0.5), Vector3(0, 0, -30))
	idle.add(glint, ItemIdle.Kind.SLIDE, 0.14, 0.5, Vector3.RIGHT)
	idle.add(head, ItemIdle.Kind.SWING, 0.25, 1.1, Vector3.UP)


func _out_of_order(r: Node3D, idle: ItemIdle) -> void:
	var sign: Node3D = pivot(r, "Sign", Vector3(0, 0.95, 0))
	ball(r, Vector3.ONE * 0.03, Vector3(0, 0.95, 0), gold())
	var string_m: Material = mat(Palette.CASINO_BLACK, 0.0, 0.8)
	for sx: float in [-1.0, 1.0]:
		cyl(sign, 0.008, 0.008, 0.36, Vector3(sx * 0.16, -0.14, 0), string_m, Vector3(0, 0, sx * 52), 6)
	var board: Material = mat(Color(0.98, 0.84, 0.36), 0.0, 0.6)
	box(sign, Vector3(0.84, 0.48, 0.04), Vector3(0, -0.5, 0), board)
	var red: Material = mat(Palette.CASINO_RED, 0.0, 0.5)
	box(sign, Vector3(0.84, 0.04, 0.045), Vector3(0, -0.28, 0), red)
	box(sign, Vector3(0.84, 0.04, 0.045), Vector3(0, -0.72, 0), red)
	text(sign, "OUT OF", 0.0042, Vector3(0, -0.42, -0.025), mat(Palette.CASINO_BLACK), Vector3.ZERO, 0.01)
	text(sign, "ORDER", 0.0052, Vector3(0, -0.58, -0.025), red, Vector3.ZERO, 0.01)
	text(sign, "SORRY", 0.004, Vector3(0, -0.5, 0.025), red, Vector3(0, 180, 0), 0.01)
	idle.add(sign, ItemIdle.Kind.SWING, 0.16, 1.8, Vector3.FORWARD)


func _pickpocket(r: Node3D, idle: ItemIdle) -> void:
	# A fat leather wallet, half open, cash sticking out and a gold clasp.
	var leather: Material = mat(LEATHER, 0.1, 0.55)
	var cash: Node3D = pivot(r, "Cash", Vector3(0, 0.55, 0))
	for i: int in 3:
		box(cash, Vector3(0.6, 0.3, 0.012), Vector3((i - 1) * 0.04, i * 0.02, (i - 1) * 0.02), mat(BILL, 0.0, 0.8), Vector3(0, 0, (i - 1) * 6))
	text(cash, "$", 0.005, Vector3(-0.2, 0.05, -0.04), mat(Color(0.2, 0.35, 0.2)), Vector3.ZERO, 0.01)
	box(r, Vector3(0.7, 0.5, 0.05), Vector3(0, 0.3, 0.04), leather, Vector3(-8, 0, 0))
	box(r, Vector3(0.7, 0.44, 0.05), Vector3(0, 0.28, -0.06), leather, Vector3(8, 0, 0))
	box(r, Vector3(0.71, 0.03, 0.12), Vector3(0, 0.05, -0.01), mat(LEATHER.darkened(0.25), 0.1, 0.6))
	box(r, Vector3(0.08, 0.06, 0.02), Vector3(0, 0.44, -0.095), gold(), Vector3(8, 0, 0))
	for k: int in 7:
		box(r, Vector3(0.03, 0.006, 0.004), Vector3(-0.3 + k * 0.1, 0.48, -0.09), mat(Palette.CREAM), Vector3(8, 0, 0))
	idle.add(cash, ItemIdle.Kind.BOB, 0.05, 3.0, Vector3.UP)


func _robin_hood(r: Node3D, idle: ItemIdle) -> void:
	# A longbow with an arrow on the string, the arrow drawing back and forth. Bow in the y-z plane.
	var wood: Material = mat(WOOD, 0.0, 0.55)
	var bow: Node3D = pivot(r, "Bow", Vector3(0, 0.5, 0))
	var n: int = 11
	var tips: Array[Vector3] = []
	for i: int in n:
		var a: float = lerpf(-1.1, 1.1, float(i) / (n - 1))
		var pos := Vector3(0, sin(a) * 0.5, -cos(a) * 0.22 + 0.1)
		cyl(bow, 0.028, 0.028, 0.12, pos, wood, Vector3(rad_to_deg(-a) * 0.6, 0, 0), 8)
		if i == 0 or i == n - 1:
			tips.append(pos)
	box(bow, Vector3(0.07, 0.14, 0.07), Vector3(0, 0, -0.12), mat(Palette.FELT_GREEN, 0.0, 0.8))
	for t: Vector3 in tips:
		ball(bow, Vector3.ONE * 0.035, t, gold())
	var str_m: Material = mat(Palette.CREAM, 0.0, 0.6)
	var nock := Vector3(0, 0, 0.12)
	for t: Vector3 in tips:
		var d: Vector3 = nock - t
		var mid: Vector3 = (nock + t) * 0.5
		var mi: MeshInstance3D = cyl(bow, 0.006, 0.006, d.length(), mid, str_m, Vector3.ZERO, 5)
		mi.basis = Basis(Quaternion(Vector3.UP, d.normalized())) * Basis.from_scale(Vector3(1, d.length(), 1))
	var arrow: Node3D = pivot(bow, "Arrow", Vector3(0, 0, 0.12))
	cyl(arrow, 0.012, 0.012, 0.72, Vector3(0, 0, -0.36), wood, Vector3(90, 0, 0), 6)
	cyl(arrow, 0.0, 0.04, 0.1, Vector3(0, 0, -0.76), gold(), Vector3(-90, 0, 0), 6)
	for k: int in 3:
		box(arrow, Vector3(0.005, 0.07, 0.12), Vector3(0, 0, 0.0), mat(Palette.CASINO_RED, 0.0, 0.7), Vector3(0, 0, k * 120)).position = Vector3(0, 0, -0.04)
	idle.add(arrow, ItemIdle.Kind.BOB, 0.05, 2.0, Vector3.BACK)
	idle.add(bow, ItemIdle.Kind.SWING, 0.08, 1.3, Vector3.RIGHT)


func _rock_paper_scissors(r: Node3D, idle: ItemIdle) -> void:
	var orbit: Node3D = pivot(r, "Orbit", Vector3(0, 0.45, 0))
	var rock: Node3D = pivot(orbit, "Rock", Vector3(0, 0, -0.28))
	ball(rock, Vector3(0.17, 0.14, 0.15), Vector3.ZERO, mat(Color(0.5, 0.48, 0.46), 0.0, 0.95), Vector3(10, 20, 0), 6)
	ball(rock, Vector3(0.09, 0.08, 0.08), Vector3(0.08, 0.06, -0.05), mat(Color(0.56, 0.53, 0.5), 0.0, 0.95), Vector3.ZERO, 6)
	var paper: Node3D = pivot(orbit, "Paper", Vector3(cos(PI / 6.0) * 0.28, 0, sin(PI / 6.0) * 0.28))
	box(paper, Vector3(0.24, 0.3, 0.01), Vector3.ZERO, mat(Palette.CREAM, 0.0, 0.8), Vector3(0, 0, 8))
	for k: int in 4:
		box(paper, Vector3(0.16, 0.008, 0.012), Vector3(0, 0.08 - k * 0.05, 0), mat(Color(0.6, 0.65, 0.8)), Vector3(0, 0, 8))
	var sc: Node3D = pivot(orbit, "Scissors", Vector3(-cos(PI / 6.0) * 0.28, 0, sin(PI / 6.0) * 0.28))
	sc.scale = Vector3.ONE * 0.38
	_scissors(sc, idle)
	for n: Node3D in [rock, paper, sc]:
		idle.add(n, ItemIdle.Kind.BOB, 0.05, 3.0, Vector3.UP, n.get_index() * 2.1)
	idle.add(orbit, ItemIdle.Kind.SPIN, 0.0, 1.0, Vector3.UP)


func _scissors(r: Node3D, idle: ItemIdle) -> void:
	var steel: Material = mat(SILVER, 0.6, 0.22)
	var handle: Material = mat(Palette.CASINO_RED, 0.1, 0.35)
	for side: float in [-1.0, 1.0]:
		var half: Node3D = pivot(r, "Half" + ("L" if side < 0.0 else "R"), Vector3(0, 0.45, 0))
		var blade: MeshInstance3D = cyl(half, 0.008, 0.06, 0.55, Vector3(side * 0.015, 0.27, 0), steel, Vector3(0, 0, 0), 4)
		blade.scale = Vector3(1.7, 0.55, 0.3)
		ring(half, 0.06, 0.1, Vector3(-side * 0.11, -0.3, 0), handle, Vector3(90, 0, 0), Vector3(1, 1, 1.3))
		cyl(half, 0.03, 0.03, 0.22, Vector3(-side * 0.05, -0.12, 0), handle, Vector3(0, 0, side * 25), 8)
		half.rotation_degrees = Vector3(0, 0, side * -12)
		idle.add(half, ItemIdle.Kind.SWING, 0.2, 5.0, Vector3.FORWARD * side)
	cyl(r, 0.03, 0.03, 0.06, Vector3(0, 0.45, 0), gold(), Vector3(90, 0, 0), 10)


func _sunglasses(r: Node3D, idle: ItemIdle) -> void:
	var g: Node3D = pivot(r, "Glasses", Vector3(0, 0.5, 0))
	var lens: Material = mat(Palette.CASINO_BLACK, 0.6, 0.08)
	for sx: float in [-1.0, 1.0]:
		var c := Vector3(sx * 0.26, 0, 0)
		cyl(g, 0.2, 0.2, 0.03, c, lens, Vector3(90, 0, 0), 20).scale = Vector3(1.1, 0.03, 0.85)
		ring(g, 0.19, 0.23, c, gold(), Vector3(90, 0, 0), Vector3(1.1, 1, 0.85))
		box(g, Vector3(0.03, 0.03, 0.62), Vector3(sx * 0.5, 0.06, 0.3), gold())
		box(g, Vector3(0.03, 0.06, 0.08), Vector3(sx * 0.5, 0.0, 0.62), gold(), Vector3(30, 0, 0))
		var glint: MeshInstance3D = box(g, Vector3(0.035, 0.26, 0.004), c + Vector3(0, 0, -0.02), mat(Color.WHITE, 0.0, 0.1, 1.0, 0.45), Vector3(0, 0, -30))
		idle.add(glint, ItemIdle.Kind.SLIDE, 0.12, 0.4, Vector3.RIGHT, sx * 0.1)
	box(g, Vector3(0.14, 0.03, 0.03), Vector3(0, 0.08, 0), gold())
	idle.add(g, ItemIdle.Kind.SWING, 0.12, 1.3, Vector3.FORWARD)


func _vip_pass(r: Node3D, idle: ItemIdle) -> void:
	var pass_: Node3D = pivot(r, "Pass", Vector3(0, 1.0, 0))
	var strap: Material = mat(Palette.VIP_BURGUNDY, 0.0, 0.8)
	for sx: float in [-1.0, 1.0]:
		box(pass_, Vector3(0.05, 0.3, 0.01), Vector3(sx * 0.08, -0.12, 0), strap, Vector3(0, 0, sx * 28))
	ring(pass_, 0.02, 0.035, Vector3(0, -0.27, 0), gold(), Vector3(90, 0, 0))
	box(pass_, Vector3(0.08, 0.06, 0.02), Vector3(0, -0.31, 0), gold())
	box(pass_, Vector3(0.52, 0.72, 0.025), Vector3(0, -0.7, 0), gold())
	box(pass_, Vector3(0.46, 0.66, 0.03), Vector3(0, -0.7, 0), mat(Palette.VIP_BURGUNDY, 0.1, 0.4))
	text(pass_, "VIP", 0.0065, Vector3(0, -0.62, -0.02), gold(), Vector3.ZERO, 0.02)
	star(pass_, Vector3(0, -0.88, -0.02), 0.09, gold())
	text(pass_, "ALL ACCESS", 0.0016, Vector3(0, -0.78, -0.017), mat(Palette.CREAM), Vector3.ZERO, 0.005)
	idle.add(pass_, ItemIdle.Kind.SWING, 0.18, 1.7, Vector3.FORWARD)


func _wild_card(r: Node3D, idle: ItemIdle) -> void:
	var card: Node3D = pivot(r, "Card", Vector3(0, 0.5, 0))
	box(card, Vector3(0.64, 0.92, 0.02), Vector3.ZERO, gold())
	box(card, Vector3(0.58, 0.86, 0.025), Vector3.ZERO, mat(Palette.CREAM, 0.0, 0.6))
	var burg: Material = mat(Palette.VIP_BURGUNDY, 0.1, 0.45)
	ball(card, Vector3(0.2, 0.28, 0.01), Vector3(0, 0, -0.012), burg, Vector3.ZERO, 16)
	text(card, "?", 0.009, Vector3(0, 0, -0.02), mat(Palette.COIN_GOLD, 0.8, 0.3, 0.25), Vector3.ZERO, 0.015)
	text(card, "W", 0.0024, Vector3(-0.22, 0.36, -0.014), burg, Vector3.ZERO, 0.004)
	text(card, "W", 0.0024, Vector3(0.22, -0.36, -0.014), burg, Vector3(0, 0, 180), 0.004)
	# The back: burgundy with a gold diamond.
	box(card, Vector3(0.56, 0.84, 0.004), Vector3(0, 0, 0.013), burg)
	box(card, Vector3(0.3, 0.3, 0.006), Vector3(0, 0, 0.015), gold(), Vector3(0, 0, 45))
	idle.add(card, ItemIdle.Kind.SPIN, 0.0, 1.6, Vector3.UP)
