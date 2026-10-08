class_name LoungeDecor
extends Node3D
## Client-only dressing for the Lucky Lounge (docs/ART_DIRECTION.md): CC0 surface textures on the
## greybox (wine-red casino carpet, checker marble entrance, herringbone parquet in the bar and
## the VIP lounge, damask wallpaper over mahogany wainscoting with a brass rail, black marble
## counters and pillar bases, red velvet, coffered wood ceiling), classical columns, arched
## windows with velvet curtains, double doors, a baroque mirror, paintings, a bust and a horse
## statue in the VIP lounge, balusters on every railing, brass stair nosings, crystal chandeliers,
## sconces, marquee bulbs and a warm haze + glow on the WorldEnvironment.
##
## Nothing here collides or touches gameplay. `LuckyLounge` adds it only when `Vfx.enabled()`
## (never on the headless server). Big surfaces use world-space triplanar materials (one material
## per surface type, no UV work), repeated pieces are MultiMeshes, so the pass stays a few dozen
## draw calls on gl_compatibility.

const FLOOR_SHADER: Shader = preload("res://vfx/shaders/casino_floor.gdshader")
const TEX_DIR: String = "res://assets/textures/"
## Where the chandeliers hang (the map's room lamps sit at the same points).
const CHANDELIERS: Array[Vector3] = [
	Vector3(0, 6.0, 11), Vector3(0, 6.5, -3), Vector3(-13, 6.0, 4), Vector3(-13, 6.0, -11),
	Vector3(14, 6.0, -12), Vector3(16, 6.0, 4), Vector3(0, LuckyLounge.MEZZ_Y + 2.5, -5),
]
const BULB_COLOR: Color = Color(1.0, 0.82, 0.52)
const GLASS_GLOW: Color = Color(0.45, 0.42, 0.62)
## Arched windows: [centre on the wall, inward normal, height]. The VIP back wall gets shorter
## ones above the mezzanine floor; the Plinko wall and the mirror/board walls stay free.
const WINDOWS: Array = [
	[Vector3(-21.75, 3.5, -11.0), Vector3(1, 0, 0), 3.2], [Vector3(-21.75, 3.5, -4.0), Vector3(1, 0, 0), 3.2], [Vector3(-21.75, 3.5, 3.0), Vector3(1, 0, 0), 3.2],
	[Vector3(21.75, 3.5, -11.0), Vector3(-1, 0, 0), 3.2], [Vector3(21.75, 3.5, -4.0), Vector3(-1, 0, 0), 3.2], [Vector3(21.75, 3.5, 3.0), Vector3(-1, 0, 0), 3.2],
	[Vector3(-16.0, 3.9, 15.75), Vector3(0, 0, -1), 3.2], [Vector3(16.0, 3.9, 15.75), Vector3(0, 0, -1), 3.2],
	[Vector3(-19.0, 3.5, -15.75), Vector3(0, 0, 1), 3.2], [Vector3(-11.0, 3.5, -15.75), Vector3(0, 0, 1), 3.2],
	[Vector3(-6.0, 5.4, -15.75), Vector3(0, 0, 1), 2.3], [Vector3(6.0, 5.4, -15.75), Vector3(0, 0, 1), 2.3],
]
## Double doors: [centre on the wall, inward normal, height]: staff door by the slots, a closed
## back door in the middle of the north wall (it used to be the VIP lounge's private door at
## mezzanine height, floating 4 m up over the pit since the balcony ends 6 m short of that wall),
## the street door seen through the entrance.
const DOORS: Array = [
	[Vector3(-13.75, 0.0, -15.75), Vector3(0, 0, 1), 2.7], [Vector3(0.0, 0.0, -15.75), Vector3(0, 0, 1), 2.7],
	[Vector3(0.0, 0.0, 20.75), Vector3(0, 0, -1), 2.9],
]

## Size of the entrance logo against the 13.6 m model (about 6.8 m wide in the room).
const SIGN_SCALE: float = 0.5

var map: LuckyLounge
## Batches filled while building, turned into MultiMeshes at the end: key → [mesh, material, transforms].
var _batches: Dictionary = {}
var _bulb_mat: StandardMaterial3D
var _crystal_mat: StandardMaterial3D
var _gold_mat: StandardMaterial3D
var _brass_mat: StandardMaterial3D
var _velvet_mat: StandardMaterial3D
var _marble_mat: StandardMaterial3D
var _wood_mat: StandardMaterial3D
var _mats: Dictionary = {}


func _init(p_map: LuckyLounge = null) -> void:
	map = p_map
	name = "Decor"


func _ready() -> void:
	if map == null:
		map = get_parent() as LuckyLounge
	if map == null:
		return
	_bulb_mat = StandardMaterial3D.new()
	_bulb_mat.albedo_color = BULB_COLOR
	_bulb_mat.emission_enabled = true
	_bulb_mat.emission = BULB_COLOR
	_bulb_mat.emission_energy_multiplier = 3.2
	_bulb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_crystal_mat = StandardMaterial3D.new()
	_crystal_mat.albedo_color = Color(1.0, 0.95, 0.85)
	_crystal_mat.emission_enabled = true
	_crystal_mat.emission = Color(1.0, 0.86, 0.62)
	_crystal_mat.emission_energy_multiplier = 0.9
	_crystal_mat.roughness = 0.1
	_crystal_mat.metallic_specular = 1.0
	_gold_mat = GreyboxKit.gold()
	_brass_mat = _tex("brass", 0.6, Palette.WARM_GOLD.lightened(0.05), 0.3, 0.35, 0.85)
	_velvet_mat = _tex("velvet", 0.8, Palette.VIP_BURGUNDY.lightened(0.08), 0.4, 0.95)
	_marble_mat = _tex("black_marble", 2.0, Color(0.9, 0.88, 0.86), 0.3, 0.25)
	_wood_mat = _tex("wooden_panels", 2.1, Color(0.78, 0.66, 0.56), 0.5, 0.6)
	_floors()
	_walls()
	_ceiling()
	_pillars()
	_mezzanine()
	_stairs()
	_furniture()
	_windows()
	_doors()
	_art()
	_chandeliers()
	_sconces()
	_signs()
	_environment()
	_flush()


# --- Materials --------------------------------------------------------------------------------

## A textured material from assets/textures/<folder>/ (albedo + optional normal), projected in
## world space (triplanar) so every box and plane shares it with no UV work. `metres` is the
## texture's tile size in the world; photo detail stays subtle (normal strength 0.3–0.5, tinted
## towards the palette) so it sits with the toon beans.
func _tex(folder: String, metres: float, tint: Color = Color.WHITE, normal_strength: float = 0.4, roughness: float = 0.9, metallic: float = 0.0, albedo_file: String = "albedo.jpg") -> StandardMaterial3D:
	var key: String = "%s/%s/%.2f/%s/%.2f/%.2f/%.2f" % [folder, albedo_file, metres, tint.to_html(), normal_strength, roughness, metallic]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(TEX_DIR + folder + "/" + albedo_file) as Texture2D
	m.albedo_color = tint
	var normal_path: String = TEX_DIR + folder + "/normal.jpg"
	if ResourceLoader.exists(normal_path):
		m.normal_enabled = true
		m.normal_texture = load(normal_path) as Texture2D
		m.normal_scale = normal_strength
	m.roughness = roughness
	m.metallic = metallic
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / metres
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mats[key] = m
	return m


# --- Floors -----------------------------------------------------------------------------------

func _floors() -> void:
	# Wine-red casino carpet (gold lattice, in the palette) with the carpet-fibre normal.
	_retexture("Carpet", _tex("casino_carpet", 2.2, Color(0.92, 0.9, 0.9), 0.35, 0.95))
	# The VIP lounge and the bar stand on herringbone parquet.
	var parquet: StandardMaterial3D = _tex("herringbone_parquet", 1.6, Color(0.72, 0.56, 0.44), 0.45, 0.5)
	_retexture("VipCarpet", parquet)
	var bar_floor := _plane(Vector2(8.6, 5.6), Vector3(LuckyLounge.BAR_X, 0.014, 4.6), parquet)
	bar_floor.name = "BarFloor"
	# Black and cream checker marble in the entrance hall, with a red runner from the door.
	_retexture("LobbyCarpet", _tex("checker_marble", 2.4, Color(0.95, 0.93, 0.9), 0.3, 0.25))
	var runner := _plane(Vector2(3.2, 3.4), Vector3(0, 0.02, 14.4), _carpet(Palette.CASINO_RED.darkened(0.15), Palette.CASINO_RED.darkened(0.35), 0.8))
	runner.name = "Runner"
	for x: float in [-1.66, 1.66]:
		_box(Vector3(0.12, 0.012, 3.4), Vector3(x, 0.022, 14.4), _brass_mat, "brass")
	# The game-area rugs: patterned carpet in the area colour with a brass edge, instead of the
	# flat colour patches the greybox lays over the carpet.
	_area_rug("BlackjackRug", Palette.FELT_GREEN.darkened(0.45), Palette.FELT_GREEN.darkened(0.62))
	_area_rug("RouletteRug", Palette.CASINO_RED.darkened(0.3), Palette.CASINO_RED.darkened(0.5))
	_area_rug("SlotsRug", Palette.WARM_GOLD.darkened(0.5), Palette.WARM_GOLD.darkened(0.66))
	_area_rug("PlinkoRug", Palette.VIP_BURGUNDY.darkened(0.15), Palette.VIP_BURGUNDY.darkened(0.38))
	# The stair treads are red carpet, the landing blocks too.
	var stair_carpet: StandardMaterial3D = _tex("casino_carpet", 1.1, Palette.CASINO_RED.darkened(0.1), 0.3, 0.95)
	for n: String in ["Stairs1", "Stairs2", "Landing"]:
		_retexture_solid(n, stair_carpet)


## Patterned carpet on the greybox area rug `node_name`, with a brass strip around its edge.
func _area_rug(node_name: String, base: Color, alt: Color) -> void:
	var mi: MeshInstance3D = map.get_node_or_null(node_name) as MeshInstance3D
	if mi == null or not (mi.mesh is PlaneMesh):
		return
	mi.material_override = _carpet(base, alt, 1.0)
	var size: Vector2 = (mi.mesh as PlaneMesh).size
	var c: Vector3 = mi.position + Vector3(0, 0.002, 0)
	var w: float = 0.1
	for sx: float in [-1.0, 1.0]:
		_box(Vector3(w, 0.008, size.y), c + Vector3(sx * (size.x - w) * 0.5, 0, 0), _brass_mat, "brass")
		_box(Vector3(size.x, 0.008, w), c + Vector3(0, 0, sx * (size.y - w) * 0.5), _brass_mat, "brass")


func _retexture(node_name: String, mat: Material) -> void:
	var mi: MeshInstance3D = map.get_node_or_null(node_name) as MeshInstance3D
	if mi != null:
		mi.material_override = mat


## Swaps the material of every GreyboxKit solid built under `name` (its mesh is the "Mesh" child).
func _retexture_solid(node_name: String, mat: Material) -> void:
	for solid: Node3D in _solids(node_name):
		var mi: MeshInstance3D = solid.get_node_or_null(^"Mesh") as MeshInstance3D
		if mi != null:
			mi.material_override = mat


## Every GreyboxKit piece whose build name starts with `prefix`. Pieces built in loops share a
## name and get auto-renamed by the tree, so the kit tags them with a "greybox" meta instead.
func _solids(prefix: String) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for c: Node in map.get_children():
		if c is Node3D and c.has_meta(&"greybox") and String(c.get_meta(&"greybox")).begins_with(prefix):
			out.append(c)
	return out


static func _kit_name(n: Node) -> String:
	return String(n.get_meta(&"greybox", n.name))


static func _carpet(base: Color, alt: Color, tile: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FLOOR_SHADER
	m.set_shader_parameter(&"mode", 0)
	m.set_shader_parameter(&"base_color", base)
	m.set_shader_parameter(&"alt_color", alt)
	m.set_shader_parameter(&"accent_color", Palette.WARM_GOLD)
	m.set_shader_parameter(&"tile", tile)
	m.set_shader_parameter(&"roughness_value", 0.95)
	return m


# --- Walls and ceiling ------------------------------------------------------------------------

func _walls() -> void:
	var hx: float = LuckyLounge.SIZE_X * 0.5 - 0.25
	var hz: float = LuckyLounge.SIZE_Z * 0.5 - 0.25
	# Damask wallpaper on every wall (wine on wine), gold on black behind the VIP lounge.
	var damask: StandardMaterial3D = _tex("damask_wallpaper", 2.0, Color(0.95, 0.9, 0.9), 0.0, 0.85)
	for n: String in ["WallN", "WallW", "WallE", "WallS1", "WallS2", "WallSTop", "PorchWall", "PorchSide"]:
		_retexture_solid(n, damask)
	var vip_damask: StandardMaterial3D = _tex("damask_wallpaper", 1.6, Color(0.95, 0.92, 0.85), 0.0, 0.8, 0.0, "albedo_gold.jpg")
	_box(Vector3(22.0, LuckyLounge.WALL_H - LuckyLounge.MEZZ_Y - 0.3, 0.04), Vector3(2.0, (LuckyLounge.WALL_H + LuckyLounge.MEZZ_Y) * 0.5 - 0.1, -hz + 0.025), vip_damask, "vipwall")
	# The map's low gold trim strips sit where the chair rail goes now.
	for solid: Node3D in _solids("Trim"):
		solid.visible = false
	# North and east/west walls run full length; the south wall has the entrance gap.
	var runs: Array = [  # [start, end, inward normal]
		[Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(0, 0, 1)],
		[Vector3(-hx, 0, -hz), Vector3(-hx, 0, hz), Vector3(1, 0, 0)],
		[Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-1, 0, 0)],
		[Vector3(-hx, 0, hz), Vector3(-2.3, 0, hz), Vector3(0, 0, -1)],
		[Vector3(2.3, 0, hz), Vector3(hx, 0, hz), Vector3(0, 0, -1)],
	]
	for run: Array in runs:
		var a: Vector3 = run[0]
		var b: Vector3 = run[1]
		var n: Vector3 = run[2]
		var along: Vector3 = (b - a)
		var length: float = along.length()
		var dir: Vector3 = along / length
		var mid: Vector3 = (a + b) * 0.5
		var basis := Basis.looking_at(-n, Vector3.UP)  # local x runs along the wall, +z into the room
		# Mahogany wainscot to 1.05 m, brass chair rail, gold crown moulding under the ceiling.
		_box_b(Vector3(length, 1.05, 0.06), mid + n * 0.03 + Vector3(0, 0.525, 0), basis, _wood_mat, "wood")
		_box_b(Vector3(length, 0.09, 0.1), mid + n * 0.06 + Vector3(0, 1.08, 0), basis, _brass_mat, "brass")
		_box_b(Vector3(length, 0.22, 0.14), mid + n * 0.07 + Vector3(0, LuckyLounge.WALL_H - 0.2, 0), basis, _gold_mat, "gold")
		# Gold mouldings frame the wallpaper between the rail and the ceiling, except where a
		# window or door sits; the VIP back wall (behind the mezzanine) is handled on its own.
		var count: int = maxi(1, int(length / 3.6))
		var step: float = length / count
		for i: int in count:
			var c: Vector3 = a + dir * (step * (i + 0.5))
			if _near_opening(c, 2.7) or (n.z > 0.5 and absf(c.x) < 10.0):
				continue
			_box_b(Vector3(step - 0.7, 3.9, 0.04), c + n * 0.02 + Vector3(0, 3.6, 0), basis, _gold_mat, "gold")
			_box_b(Vector3(step - 0.86, 3.74, 0.05), c + n * 0.035 + Vector3(0, 3.6, 0), basis, _velvet_mat, "velvet")
	# VIP back wall: mouldings between the windows, above the mezzanine floor.
	for x: float in [-9.0, 0.0, 9.0]:
		if x == 0.0:
			continue
		_box(Vector3(2.4, 2.4, 0.04), Vector3(x, 5.4, -hz + 0.065), _gold_mat, "gold")
		_box(Vector3(2.24, 2.24, 0.05), Vector3(x, 5.4, -hz + 0.08), _velvet_mat, "velvet")


func _near_opening(p: Vector3, radius: float) -> bool:
	for w: Array in WINDOWS:
		var c: Vector3 = w[0]
		if Vector2(c.x, c.z).distance_to(Vector2(p.x, p.z)) < radius and absf(c.y - 3.6) < 2.0:
			return true
	for d: Array in DOORS:
		var c: Vector3 = d[0]
		if Vector2(c.x, c.z).distance_to(Vector2(p.x, p.z)) < radius and absf(c.y - 1.0) < 2.0:
			return true
	return false


func _ceiling() -> void:
	# Coffered dark wood; the chandeliers hang against it.
	_retexture_solid("Ceiling", _tex("coffered_ceiling", 2.6, Color(0.95, 0.88, 0.8), 0.5, 0.75))


# --- Columns, mezzanine, stairs ---------------------------------------------------------------

func _pillars() -> void:
	# Classical round columns (Quaternius) on black marble plinths replace the plain cylinders;
	# the collision cylinder underneath stays.
	for solid: Node3D in _solids("Pillar"):
		(solid.get_node(^"Mesh") as Node3D).visible = false
		var base: Node3D = solid.get_node_or_null(^"Base")
		if base != null:
			base.visible = false
		var col: Node3D = PropModels.make(&"column", LuckyLounge.WALL_H - 0.5)
		col.scale = Vector3(0.75, 1.0, 0.75)
		col.position.y = -LuckyLounge.WALL_H * 0.5 + 0.5
		_recolor(col, {"Marble": GreyboxKit.material(Palette.CREAM.darkened(0.12), 0.0, 0.55)})
		solid.add_child(col)
		var foot: Vector3 = solid.position - Vector3(0, LuckyLounge.WALL_H * 0.5, 0)
		_box(Vector3(1.5, 0.5, 1.5), foot + Vector3(0, 0.25, 0), _marble_mat, "marble")
		_box(Vector3(1.6, 0.06, 1.6), foot + Vector3(0, 0.53, 0), _brass_mat, "brass")


func _mezzanine() -> void:
	# Soffit and brass edge under the VIP floor, so the slab reads as a built balcony from the pit.
	var y: float = LuckyLounge.MEZZ_Y
	_box(Vector3(17.9, 0.02, 9.9), Vector3(0, y - 0.41, -5.0), _tex("coffered_ceiling", 2.0, Color(0.9, 0.84, 0.78), 0.4, 0.8), "soffit")
	_box(Vector3(4.5, 0.02, 2.9), Vector3(11.0, y - 0.41, -3.0), _wood_mat, "wood")
	_box(Vector3(18.1, 0.44, 0.06), Vector3(0, y - 0.2, 0.03), _wood_mat, "wood")
	_box(Vector3(18.1, 0.1, 0.1), Vector3(0, y - 0.02, 0.05), _brass_mat, "brass")
	_box(Vector3(0.06, 0.44, 3.1), Vector3(13.33, y - 0.2, -3.0), _wood_mat, "wood")
	_box(Vector3(0.06, 0.44, 10.1), Vector3(-9.03, y - 0.2, -5.0), _wood_mat, "wood")
	_box(Vector3(0.06, 0.44, 5.6), Vector3(9.03, y - 0.2, -7.25), _wood_mat, "wood")
	_box(Vector3(0.06, 0.44, 1.6), Vector3(9.03, y - 0.2, -0.75), _wood_mat, "wood")
	# Balusters under every handrail (the map's rails are an invisible guard + a gold bar).
	var baluster := CylinderMesh.new()
	baluster.top_radius = 0.025
	baluster.bottom_radius = 0.025
	baluster.height = 1.0
	baluster.radial_segments = 6
	for rail: Node3D in _solids("MezzRail") + _solids("LandingRail") + _solids("StairGuard"):
		if not _kit_name(rail).ends_with("Bar"):
			_balusters(rail, baluster)
	# The VIP floor gets its own lamps: the single ceiling lamp left it dim.
	for x: float in [-6.0, 6.0]:
		var l: OmniLight3D = GreyboxKit.lamp(self, Vector3(x, y + 2.6, -5.0), 1.4, 8.0)
		l.name = "VipLamp"
	# Velvet rope across the two gate posts is not wanted (the bouncer handles entry); a red
	# carpet runner leads from the gate to the tables instead.
	var runner := _plane(Vector2(2.4, 7.0), Vector3(5.6, y + 0.013, -4.0), _carpet(Palette.VIP_BURGUNDY.lightened(0.05), Palette.VIP_BURGUNDY.darkened(0.2), 0.8))
	runner.name = "VipRunner"
	runner.rotation.y = PI * 0.5


## Vertical balusters every 0.3 m along a GreyboxKit beam (its local z runs along the rail).
func _balusters(rail: Node3D, mesh: Mesh) -> void:
	var shape: CollisionShape3D = null
	for c: Node in rail.get_children():
		if c is CollisionShape3D:
			shape = c
	if shape == null or not (shape.shape is BoxShape3D):
		return
	var size: Vector3 = (shape.shape as BoxShape3D).size
	var count: int = maxi(1, int(size.z / 0.3))
	for i: int in count + 1:
		var local := Vector3(0, 0, -size.z * 0.5 + size.z * i / count)
		var world: Vector3 = rail.to_global(local)
		var bottom: float = world.y - size.y * 0.5
		# Stair guards slope: drop the baluster to the step under it.
		var height: float = size.y - 0.08
		_add(&"baluster", mesh, _brass_mat, Transform3D(Basis().scaled(Vector3(1, height, 1)), Vector3(world.x, bottom + height * 0.5, world.z)))


func _stairs() -> void:
	# Brass nosings every 25 cm of rise read as steps on the carpeted slopes.
	for flight: Array in LuckyLounge.STAIR_FLIGHTS:
		var a: Vector3 = flight[0]
		var b: Vector3 = flight[1]
		var steps: int = int(round((b.y - a.y) / 0.25))
		for i: int in range(1, steps + 1):
			var p: Vector3 = a.lerp(b, float(i) / steps)
			_box(Vector3(LuckyLounge.STAIRS_W, 0.03, 0.08), p + Vector3(0, 0.012, 0), _brass_mat, "brass")


# --- Furniture and props ----------------------------------------------------------------------

func _furniture() -> void:
	# Cashier desk and the shop counter in black marble, bar front in velvet, back bar in wood.
	_retexture_solid("Reception", _marble_mat)
	_retexture_solid("ShopCounter", _marble_mat)
	_retexture_solid("Bar", _velvet_mat)
	_retexture_solid("BackBar", _wood_mat)
	_retexture_solid("MezzFloor", _wood_mat)
	_retexture_solid("MezzLanding", _wood_mat)
	_retexture_solid("Plinth", _marble_mat)
	_retexture_solid("Rope", _velvet_mat)
	# Marble bust and horse statue on short columns in the VIP corners.
	var y: float = LuckyLounge.MEZZ_Y
	for spec: Array in [[Vector3(-8.0, y, -9.0), &"bust", 0.9], [Vector3(8.0, y, -9.0), &"horse", 1.0]]:
		var pedestal: Node3D = PropModels.make(&"pedestal", 1.0)
		pedestal.scale = Vector3(0.55, 1.0, 0.55)
		pedestal.position = spec[0]
		_recolor(pedestal, {"Marble": _marble_mat})
		add_child(pedestal)
		var statue: Node3D = PropModels.make(spec[1], spec[2])
		statue.position = spec[0] + Vector3(0, 1.0, 0)
		statue.rotation.y = PI * 0.25 * (1.0 if spec[0].x < 0.0 else -1.0)
		add_child(statue)


func _windows() -> void:
	var white := GreyboxKit.material(Palette.CREAM.darkened(0.08), 0.0, 0.7)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.06, 0.07, 0.12)
	glass.emission_enabled = true
	glass.emission = GLASS_GLOW
	glass.emission_energy_multiplier = 0.35
	glass.roughness = 0.1
	glass.metallic = 0.3
	var curtain_red := _tex("velvet", 0.9, Palette.CASINO_RED.darkened(0.25), 0.5, 0.95)
	for w: Array in WINDOWS:
		var c: Vector3 = w[0]
		var n: Vector3 = w[1]
		var h: float = w[2]
		var win: Node3D = PropModels.make(&"window_arch", h)
		win.position = c + n * 0.12 - Vector3(0, h * 0.5, 0)
		win.rotation.y = atan2(n.x, n.z)
		_recolor(win, {"White": white, "Glass": glass})
		add_child(win)
		var curtains: Node3D = PropModels.make(&"curtains", 0.0, h * 0.58 + 0.9)
		curtains.position = c + n * 0.32 - Vector3(0, h * 0.5 + 0.2, 0)
		curtains.rotation.y = atan2(n.x, n.z)
		_recolor(curtains, {"Couch_Blue": curtain_red, "LightMetal": _gold_mat})
		add_child(curtains)


func _doors() -> void:
	var wood := GreyboxKit.material(Color("#3A2318"), 0.0, 0.6)
	for d: Array in DOORS:
		var c: Vector3 = d[0]
		var n: Vector3 = d[1]
		var door: Node3D = PropModels.make(&"door_double", d[2])
		door.position = c + n * 0.2
		door.rotation.y = atan2(n.x, n.z)
		_recolor(door, {"Wood": wood, "Gold": _gold_mat})
		add_child(door)
		# Gold casing (two jambs and a lintel) so each door reads as built into the wall.
		var h: float = d[2]
		var w: float = PropModels.scaled_size(&"door_double", h).x
		if w <= 0.0:
			continue
		var basis := Basis.looking_at(-n, Vector3.UP)
		var side: Vector3 = basis.x
		for sgn: float in [-1.0, 1.0]:
			_box_b(Vector3(0.16, h + 0.12, 0.08), c + n * 0.04 + side * sgn * (w * 0.5 + 0.08) + Vector3(0, (h + 0.12) * 0.5, 0), basis, _gold_mat, "gold")
		_box_b(Vector3(w + 0.32, 0.18, 0.1), c + n * 0.05 + Vector3(0, h + 0.09, 0), basis, _gold_mat, "gold")


func _art() -> void:
	# Baroque mirror in the entrance hall; paintings in the mouldings along the game floor.
	for x: float in [-6.0, 6.0]:
		var mirror: Node3D = PropModels.make(&"mirror", 2.2)
		mirror.position = Vector3(x, 1.4, 15.62)
		mirror.rotation.y = PI
		add_child(mirror)
	for spec: Array in [[Vector3(-21.75, 3.5, -7.5), Vector3(1, 0, 0)], [Vector3(-21.75, 3.5, 7.0), Vector3(1, 0, 0)], [Vector3(21.75, 3.5, -7.5), Vector3(-1, 0, 0)], [Vector3(21.75, 3.5, 11.0), Vector3(-1, 0, 0)]]:
		var n: Vector3 = spec[1]
		var pic: Node3D = PropModels.make(&"picture", 0.0, 1.6)
		pic.position = spec[0] + n * 0.1 - Vector3(0, 0.6, 0)
		pic.rotation.y = atan2(n.x, n.z)
		add_child(pic)


## Replaces a prop's materials by their source name (Quaternius models use flat named colours).
func _recolor(prop: Node3D, by_name: Dictionary) -> void:
	for n: Node in prop.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		for i: int in mi.mesh.get_surface_count():
			var src: Material = mi.get_active_material(i)
			if src != null and by_name.has(src.resource_name):
				mi.set_surface_override_material(i, by_name[src.resource_name])


# --- Lights -----------------------------------------------------------------------------------

func _chandeliers() -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.62
	torus.outer_radius = 0.74
	torus.rings = 24
	torus.ring_segments = 6
	var small_torus := TorusMesh.new()
	small_torus.inner_radius = 0.32
	small_torus.outer_radius = 0.4
	small_torus.rings = 16
	small_torus.ring_segments = 6
	var bulb := SphereMesh.new()
	bulb.radius = 0.08
	bulb.height = 0.16
	bulb.radial_segments = 8
	bulb.rings = 4
	var crystal := PrismMesh.new()
	crystal.size = Vector3(0.07, 0.22, 0.07)
	var stem := CylinderMesh.new()
	stem.top_radius = 0.03
	stem.bottom_radius = 0.03
	stem.height = 1.0
	stem.radial_segments = 6
	var cap := CylinderMesh.new()
	cap.top_radius = 0.18
	cap.bottom_radius = 0.42
	cap.height = 0.22
	cap.radial_segments = 12
	for p: Vector3 in CHANDELIERS:
		var drop: float = LuckyLounge.WALL_H - (p.y + 0.35)
		_add(&"stem", stem, _gold_mat, Transform3D(Basis().scaled(Vector3(1, drop, 1)), p + Vector3(0, 0.35 + drop * 0.5, 0)))
		_add(&"cap", cap, _gold_mat, Transform3D(Basis(), p + Vector3(0, 0.25, 0)))
		_add(&"ring", torus, _gold_mat, Transform3D(Basis(), p))
		_add(&"ring2", small_torus, _gold_mat, Transform3D(Basis(), p + Vector3(0, -0.32, 0)))
		for i: int in 10:
			var a: float = TAU * i / 10.0
			var o := Vector3(cos(a), 0, sin(a))
			_add(&"bulb", bulb, _bulb_mat, Transform3D(Basis(), p + o * 0.68 + Vector3(0, 0.12, 0)))
			_add(&"crystal", crystal, _crystal_mat, Transform3D(Basis(Vector3.RIGHT, PI), p + o * 0.68 + Vector3(0, -0.2, 0)))
			if i % 2 == 0:
				_add(&"crystal", crystal, _crystal_mat, Transform3D(Basis(Vector3.RIGHT, PI).scaled(Vector3(1, 1.4, 1)), p + o * 0.36 + Vector3(0, -0.52, 0)))
		_add(&"bulb", bulb, _bulb_mat, Transform3D(Basis().scaled(Vector3.ONE * 1.6), p + Vector3(0, -0.45, 0)))


func _sconces() -> void:
	var plate := BoxMesh.new()
	plate.size = Vector3(0.24, 0.5, 0.05)
	var shade := CylinderMesh.new()
	shade.top_radius = 0.1
	shade.bottom_radius = 0.17
	shade.height = 0.24
	shade.radial_segments = 10
	var shade_mat := StandardMaterial3D.new()
	shade_mat.albedo_color = Palette.CREAM
	shade_mat.emission_enabled = true
	shade_mat.emission = Color(1.0, 0.78, 0.45)
	shade_mat.emission_energy_multiplier = 1.6
	var hx: float = LuckyLounge.SIZE_X * 0.5 - 0.3
	var hz: float = LuckyLounge.SIZE_Z * 0.5 - 0.3
	var y: float = 2.4
	var spots: Array = []
	for i: int in 6:
		var x: float = -hx + 3.0 + i * (2.0 * hx - 6.0) / 5.0
		spots.append([Vector3(x, y, -hz), Vector3(0, 0, 1)])
	for i: int in 4:
		var z: float = -hz + 3.0 + i * (2.0 * hz - 6.0) / 3.0
		spots.append([Vector3(-hx, y, z), Vector3(1, 0, 0)])
		spots.append([Vector3(hx, y, z), Vector3(-1, 0, 0)])
	for s: Array in spots:
		var p: Vector3 = s[0]
		var n: Vector3 = s[1]
		if _near_opening(p, 1.6):
			continue
		var basis := Basis.looking_at(-n, Vector3.UP)
		_add(&"plate", plate, _gold_mat, Transform3D(basis, p + n * 0.03))
		_add(&"shade", shade, shade_mat, Transform3D(Basis(), p + n * 0.2 + Vector3(0, 0.2, 0)))


## The 3D title logo (`Logo3D`), once, above the entrance on the south wall, facing the room.
func _signs() -> void:
	var sign: Node3D = Logo3D.build_model()
	sign.scale = Vector3.ONE * SIGN_SCALE
	sign.rotation.y = PI
	# The sign bends back towards the wall at its ends (~1.7 m deep at full size).
	sign.position = Vector3(0.0, 4.95, LuckyLounge.SIZE_Z * 0.5 - 0.25 - 1.8 * SIGN_SCALE)
	add_child(sign)


## Warm haze in the distance and glow that only catches bright things (bulbs, signs, emissive VFX).
func _environment() -> void:
	for c: Node in map.get_children():
		if c is WorldEnvironment and (c as WorldEnvironment).environment != null:
			var e: Environment = (c as WorldEnvironment).environment
			e.glow_enabled = true
			e.glow_intensity = 0.9
			e.glow_strength = 1.0
			e.glow_bloom = 0.02
			e.glow_hdr_threshold = 1.1
			e.glow_hdr_scale = 2.0
			e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
			e.set_glow_level(0, 0.0)
			e.set_glow_level(1, 1.0)
			e.set_glow_level(2, 1.0)
			e.set_glow_level(3, 0.6)
			e.set_glow_level(4, 0.3)
			e.fog_enabled = true
			e.fog_light_color = Color(0.16, 0.1, 0.07)
			e.fog_density = 0.012
			e.fog_sky_affect = 0.0
			e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
			e.tonemap_exposure = 1.08
			e.tonemap_white = 6.0


# --- Batching ---------------------------------------------------------------------------------

func _plane(size: Vector2, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := PlaneMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi


func _box(size: Vector3, pos: Vector3, mat: Material, key: String) -> void:
	_box_b(size, pos, Basis(), mat, key)


## A unit box scaled to `size`, batched by `key` (one MultiMesh per key/material).
func _box_b(size: Vector3, pos: Vector3, basis: Basis, mat: Material, key: String) -> void:
	var unit: BoxMesh = _batches.get(&"_unit_box", [null])[0]
	if unit == null:
		unit = BoxMesh.new()
		_batches[&"_unit_box"] = [unit]
	_add(StringName("box_" + key), unit, mat, Transform3D(basis * Basis().scaled(size), pos))


func _add(key: StringName, mesh: Mesh, mat: Material, xf: Transform3D) -> void:
	if not _batches.has(key):
		_batches[key] = [mesh, mat, []]
	(_batches[key][2] as Array).append(xf)


func _flush() -> void:
	for key: StringName in _batches:
		var b: Array = _batches[key]
		if b.size() < 3:
			continue
		var xfs: Array = b[2]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = b[0]
		mm.instance_count = xfs.size()
		for i: int in xfs.size():
			mm.set_instance_transform(i, xfs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = String(key)
		mmi.multimesh = mm
		mmi.material_override = b[1]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
	_batches.clear()
