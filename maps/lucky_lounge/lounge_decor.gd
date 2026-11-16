class_name LoungeDecor
extends Node3D
## Client-only dressing for the Lucky Lounge (docs/ART_DIRECTION.md): CC0 surface textures on the
## greybox (wine-red casino carpet, checker marble entrance, herringbone parquet in the VIP
## lounge, damask wallpaper over mahogany wainscoting with a brass rail (gold damask in
## the VIP lounge), black marble counters and pillar bases, red velvet, coffered wood ceiling),
## classical columns, arched windows with velvet curtains, double doors, a baroque mirror,
## paintings, a bust and a horse statue in the VIP lounge, crystal chandeliers, sconces, marquee
## bulbs and a warm haze + glow on the WorldEnvironment.
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
	Vector3(14, 6.0, -12), Vector3(16, 6.0, 4), Vector3(0, 5.8, -21), Vector3(-13, 6.0, 12),
	Vector3(13, 6.0, 12), Vector3(25.5, 6.0, -18.5), Vector3(32.5, 6.0, -18.5),
]
const BULB_COLOR: Color = Color(1.0, 0.82, 0.52)
const GLASS_GLOW: Color = Color(0.45, 0.42, 0.62)
## Arched windows: [centre on the wall, inward normal, height]. Two in the VIP lounge's back wall,
## two in the Race Hall's east wall (the casino's east wall is the archway there); the Plinko wall
## and the mirror/board walls stay free.
const WINDOWS: Array = [
	[Vector3(-21.75, 3.5, -11.0), Vector3(1, 0, 0), 3.2], [Vector3(-21.75, 3.5, -4.0), Vector3(1, 0, 0), 3.2], [Vector3(-21.75, 3.5, 3.0), Vector3(1, 0, 0), 3.2],
	[Vector3(35.75, 3.5, -22.5), Vector3(-1, 0, 0), 3.2], [Vector3(35.75, 3.5, -15.5), Vector3(-1, 0, 0), 3.2],
	[Vector3(-16.0, 3.9, 15.75), Vector3(0, 0, -1), 3.2], [Vector3(16.0, 3.9, 15.75), Vector3(0, 0, -1), 3.2],
	[Vector3(-19.0, 3.5, -15.75), Vector3(0, 0, 1), 3.2], [Vector3(-11.0, 3.5, -15.75), Vector3(0, 0, 1), 3.2],
	[Vector3(-3.2, 3.5, -25.75), Vector3(0, 0, 1), 3.2], [Vector3(3.2, 3.5, -25.75), Vector3(0, 0, 1), 3.2],
]
## Double doors: [centre on the wall, inward normal, height]: the staff door by the slots. (The
## middle of the north wall is the VIP lounge's open doorway now; the lobby doors and the waiting
## room's door in the entrance gap are the map's own.)
const DOORS: Array = [
	[Vector3(-13.75, 0.0, -15.75), Vector3(0, 0, 1), 2.7],
]
## Open doorways (floor centre): the VIP door and the lobby doors. No frames or sconces there.
const OPENINGS: Array[Vector3] = [Vector3(0.0, 0.0, -16.0), Vector3(0.0, 0.0, LuckyLounge.LOBBY_DOORS_Z)]

## Size of the entrance logo against the 13.9 x 11.2 m model (about 4.0 x 3.25 m in the room: the
## chip fills the wall between the door opening, 3.2 m, and the gold cornice under the ceiling).
const SIGN_SCALE: float = 0.29
## How far the wall panels keep from a column standing in the wall (its capital and plinth are
## about 1.5 m across).
const PILLAR_CLEAR: float = 0.9
## Half the width of the entrance hall's red runner (brass edges just outside it).
const RUNNER_HALF: float = 1.6
## Every column (0.9.65, Patrick: the capital ran through the crown moulding and the chair rail
## through the base) stands on a marble pedestal as tall as the wainscot, so the wainscot and the
## rail die into the pedestal's sides, and carries a mahogany head block from under the crown
## moulding to the ceiling, so the crown, the coffer beams and their gold frames run into the
## block instead of through the capital.
const PEDESTAL_HALF: float = 0.6
const PEDESTAL_TOP: float = 1.14
const HEAD_HALF: float = 0.65
const HEAD_BOTTOM: float = LuckyLounge.WALL_H - 0.42
## Doorway reveals get a mahogany lining this thick (0.9.65: the walls' end faces were bare
## wallpaper, from the doorway they read as a red column standing in the opening).
const LINING_T: float = 0.04
## Outer edge of the waiting room door's gold casing (x): the wainscot runs either side stop here,
## on both faces of the wall.
const WAIT_CASING_OUT: float = LuckyLounge.WAIT_DOOR_HALF + 0.16

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
## Each arched window with its curtains: [window, curtains]. Hidden while a tall game stands in front
## (a floor layout can put Plinko or a cabinet on a wall with windows; the velvet would cut through it).
var _window_sets: Array = []


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
	_vip_lounge()
	_furniture()
	_windows()
	_doors()
	_art()
	_chandeliers()
	_sconces()
	_signs()
	_waiting_room()
	_environment()
	_flush()
	_clear_windows()
	if not map.floor_changed.is_connected(_clear_windows):
		map.floor_changed.connect(_clear_windows)


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
	_retexture("AnnexCarpet", _tex("casino_carpet", 2.2, Color(0.92, 0.9, 0.9), 0.35, 0.95))
	# The VIP lounge stands on herringbone parquet.
	var parquet: StandardMaterial3D = _tex("herringbone_parquet", 1.6, Color(0.72, 0.56, 0.44), 0.45, 0.5)
	_retexture("VipCarpet", parquet)
	_lobby_floor()
	# The game-area rugs: patterned carpet in the area colour with a brass edge, instead of the
	# flat colour patches the greybox lays over the carpet.
	_area_rug("BlackjackRug", Palette.FELT_GREEN.darkened(0.45), Palette.FELT_GREEN.darkened(0.62))
	_area_rug("RouletteRug", Palette.CASINO_RED.darkened(0.3), Palette.CASINO_RED.darkened(0.5))
	_area_rug("SlotsRug", Palette.WARM_GOLD.darkened(0.5), Palette.WARM_GOLD.darkened(0.66))
	_area_rug("PlinkoRug", Palette.VIP_BURGUNDY.darkened(0.15), Palette.VIP_BURGUNDY.darkened(0.38))
	# The jail cell: cold grey stone floor and walls.
	_retexture("JailFloor", _tex("black_marble", 1.4, Color(0.62, 0.6, 0.58), 0.3, 0.6))
	_retexture_solid("JailWall", _tex("black_marble", 1.6, Color(0.55, 0.53, 0.5), 0.4, 0.8))


## The entrance hall (0.9.4, Patrick: "better floor"): polished black and cream checker marble
## framed by a black marble border with a brass inlay, and a red runner with brass edges all the
## way from the front door to the lobby doors. Layers 1 cm apart: checker 0.015, border 0.025,
## runner 0.035, brass on top.
func _lobby_floor() -> void:
	_retexture("LobbyCarpet", _tex("checker_marble", 1.8, Color(0.97, 0.95, 0.92), 0.3, 0.18))
	var x1: float = LuckyLounge.SIZE_X * 0.5 - 0.25
	var z0: float = LuckyLounge.LOBBY_DOORS_Z + LuckyLounge.LOBBY_WALL_T * 0.5
	var z1: float = LuckyLounge.SIZE_Z * 0.5 - 0.25
	var band: float = 0.7
	var border: StandardMaterial3D = _tex("black_marble", 1.6, Color(0.82, 0.8, 0.78), 0.3, 0.2)
	var y: float = 0.025
	for z: float in [z0 + band * 0.5, z1 - band * 0.5]:
		_plane(Vector2(x1 * 2.0, band), Vector3(0, y, z), border).name = "LobbyBorder"
	for x: float in [-x1 + band * 0.5, x1 - band * 0.5]:
		_plane(Vector2(band, z1 - z0 - band * 2.0), Vector3(x, y, (z0 + z1) * 0.5), border).name = "LobbyBorder"
	# Brass inlay along the inside edge of the border.
	var ix: float = x1 - band
	var iz0: float = z0 + band
	var iz1: float = z1 - band
	# The cross strips stop at the runner's brass edges (Patrick's "da clipped was": they ran
	# through the runner, their tops level with it, so a gold line flickered across the carpet).
	var rx: float = RUNNER_HALF + 0.08
	for z: float in [iz0, iz1]:
		for sx: float in [-1.0, 1.0]:
			_box(Vector3(ix - rx, 0.008, 0.06), Vector3(sx * (ix + rx) * 0.5, y + 0.006, z), _brass_mat, "brass")
	for x: float in [-ix, ix]:
		_box(Vector3(0.06, 0.008, iz1 - iz0), Vector3(x, y + 0.006, (iz0 + iz1) * 0.5), _brass_mat, "brass")
	# The red runner from the front door to the lobby doors.
	var run_len: float = z1 - z0
	var runner := _plane(Vector2(RUNNER_HALF * 2.0, run_len), Vector3(0, 0.035, (z0 + z1) * 0.5), _carpet(Palette.CASINO_RED.darkened(0.15), Palette.CASINO_RED.darkened(0.35), 0.8))
	runner.name = "Runner"
	for x: float in [-RUNNER_HALF - 0.06, RUNNER_HALF + 0.06]:
		_box(Vector3(0.12, 0.012, run_len), Vector3(x, 0.04, (z0 + z1) * 0.5), _brass_mat, "brass")


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
	# Damask wallpaper on every wall (wine on wine), gold on black in the VIP lounge.
	var damask: StandardMaterial3D = _tex("damask_wallpaper", 2.0, Color(0.95, 0.9, 0.9), 0.0, 0.85)
	for n: String in ["WallN", "WallW", "WallE", "WallS1", "WallS2", "WallSTop", "WallLobby", "WallAnnex"]:
		_retexture_solid(n, damask)
	var vip_damask: StandardMaterial3D = _tex("damask_wallpaper", 1.6, Color(0.95, 0.92, 0.85), 0.0, 0.8, 0.0, "albedo_gold.jpg")
	_retexture_solid("WallVip", vip_damask)
	# The VIP side of the casino's north wall (either side of the door and over it) in gold too.
	var vx: float = LuckyLounge.VIP_X
	var door: float = LuckyLounge.VIP_DOOR_HALF
	var back_z: float = -hz - 0.5 - 0.025
	for sx: float in [-1.0, 1.0]:
		_box(Vector3(vx - door, LuckyLounge.WALL_H, 0.04), Vector3(sx * (door + vx) * 0.5, LuckyLounge.WALL_H * 0.5, back_z), vip_damask, "vipwall")
	_box(Vector3(door * 2.0, LuckyLounge.WALL_H - LuckyLounge.VIP_DOOR_H, 0.04), Vector3(0, (LuckyLounge.WALL_H + LuckyLounge.VIP_DOOR_H) * 0.5, back_z), vip_damask, "vipwall")
	# The map's low gold trim strips sit where the chair rail goes now.
	for solid: Node3D in _solids("Trim"):
		solid.visible = false
	# Wainscot runs: [start, end, inward normal]. Doorways split the walls they are in.
	var lz: float = LuckyLounge.LOBBY_DOORS_Z
	var lt: float = LuckyLounge.LOBBY_WALL_T * 0.5
	var ld: float = LuckyLounge.LOBBY_DOOR_HALF + 0.2
	var vz: float = LuckyLounge.VIP_Z_FAR
	var ax0: float = LuckyLounge.SIZE_X * 0.5 + 0.25
	var ax1: float = LuckyLounge.ANNEX_X1 - 0.25
	var az0: float = LuckyLounge.ANNEX_Z0 + 0.25
	var az1: float = LuckyLounge.ANNEX_Z1 - 0.25
	var wd: float = WAIT_CASING_OUT
	var runs: Array = [
		[Vector3(-hx, 0, -hz), Vector3(-door - 0.2, 0, -hz), Vector3(0, 0, 1)],
		[Vector3(door + 0.2, 0, -hz), Vector3(hx, 0, -hz), Vector3(0, 0, 1)],
		[Vector3(-hx, 0, -hz), Vector3(-hx, 0, hz), Vector3(1, 0, 0)],
		# The east wall, split by the Race Hall archway and, further south, the jail cell's opening.
		[Vector3(hx, 0, -hz), Vector3(hx, 0, LuckyLounge.ARCH_Z0 - 0.2), Vector3(-1, 0, 0)],
		[Vector3(hx, 0, LuckyLounge.ARCH_Z1 + 0.2), Vector3(hx, 0, LuckyLounge.JAIL_AREA.position.z - 0.2), Vector3(-1, 0, 0)],
		[Vector3(hx, 0, LuckyLounge.JAIL_AREA.end.z + 0.2), Vector3(hx, 0, hz), Vector3(-1, 0, 0)],
		# The Race Hall: north, east and south walls, and its west wall beside the VIP lounge.
		[Vector3(ax0, 0, az0), Vector3(ax1, 0, az0), Vector3(0, 0, 1)],
		[Vector3(ax1, 0, az0), Vector3(ax1, 0, az1), Vector3(-1, 0, 0)],
		[Vector3(ax0, 0, az0), Vector3(ax0, 0, -hz - 0.5), Vector3(1, 0, 0)],
		[Vector3(ax0, 0, az1), Vector3(ax1, 0, az1), Vector3(0, 0, -1)],
		# The start room's south wall, either side of the waiting room door (up to its casing).
		[Vector3(-hx, 0, hz), Vector3(-wd, 0, hz), Vector3(0, 0, -1)],
		[Vector3(wd, 0, hz), Vector3(hx, 0, hz), Vector3(0, 0, -1)],
		# The start-room wall, casino face and start-room face.
		[Vector3(-hx, 0, lz - lt), Vector3(-ld, 0, lz - lt), Vector3(0, 0, -1)],
		[Vector3(ld, 0, lz - lt), Vector3(hx, 0, lz - lt), Vector3(0, 0, -1)],
		[Vector3(-hx, 0, lz + lt), Vector3(-ld, 0, lz + lt), Vector3(0, 0, 1)],
		[Vector3(ld, 0, lz + lt), Vector3(hx, 0, lz + lt), Vector3(0, 0, 1)],
		# The VIP lounge.
		[Vector3(-vx, 0, vz), Vector3(-vx, 0, -hz - 0.5), Vector3(1, 0, 0)],
		[Vector3(vx, 0, vz), Vector3(vx, 0, -hz - 0.5), Vector3(-1, 0, 0)],
		[Vector3(-vx, 0, vz), Vector3(vx, 0, vz), Vector3(0, 0, 1)],
		[Vector3(-vx, 0, -hz - 0.5), Vector3(-door - 0.2, 0, -hz - 0.5), Vector3(0, 0, -1)],
		[Vector3(door + 0.2, 0, -hz - 0.5), Vector3(vx, 0, -hz - 0.5), Vector3(0, 0, -1)],
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
		# A column standing in the wall breaks the wainscot and the rail: they stop at its
		# pedestal's sides (the crown runs on into its head block).
		var cuts: Array[Vector2] = []
		for pillar: Vector3 in LuckyLounge.PILLARS:
			var off: Vector3 = pillar - a
			if absf(off.dot(n)) < PEDESTAL_HALF:
				cuts.append(Vector2(off.dot(dir) - PEDESTAL_HALF, off.dot(dir) + PEDESTAL_HALF))
		for seg: Vector2 in _subtract(0.0, length, cuts):
			var seg_mid: Vector3 = a + dir * (seg.x + seg.y) * 0.5
			_box_b(Vector3(seg.y - seg.x, 1.05, 0.06), seg_mid + n * 0.03 + Vector3(0, 0.525, 0), basis, _wood_mat, "wood")
			_box_b(Vector3(seg.y - seg.x, 0.09, 0.1), seg_mid + n * 0.06 + Vector3(0, 1.08, 0), basis, _brass_mat, "brass")
		_box_b(Vector3(length, 0.22, 0.14), mid + n * 0.07 + Vector3(0, LuckyLounge.WALL_H - 0.2, 0), basis, _gold_mat, "gold")
		# Gold mouldings frame the wallpaper between the rail and the ceiling, except where a
		# window, door or doorway sits. A column standing in the wall (the doorway pair) cuts the
		# run short: the panels start past its capital instead of running behind it.
		var pa: Vector3 = a
		var pb: Vector3 = b
		for pillar: Vector3 in LuckyLounge.PILLARS:
			var off: Vector3 = pillar - a
			var t: float = off.dot(dir)
			if t < -PILLAR_CLEAR or t > length + PILLAR_CLEAR or absf(off.dot(n)) > PILLAR_CLEAR:
				continue
			if t < length * 0.5:
				pa = a + dir * maxf((pa - a).length(), t + PILLAR_CLEAR)
			else:
				pb = a + dir * minf((pb - a).length(), t - PILLAR_CLEAR)
		var panel_len: float = (pb - pa).length()
		var count: int = maxi(1, int(panel_len / 3.6))
		var step: float = panel_len / count
		for i: int in count:
			var c: Vector3 = pa + dir * (step * (i + 0.5))
			if step < 1.6 or _near_opening(c, 2.7):
				continue
			_box_b(Vector3(step - 0.7, 3.9, 0.04), c + n * 0.02 + Vector3(0, 3.6, 0), basis, _gold_mat, "gold")
			_box_b(Vector3(step - 0.86, 3.74, 0.05), c + n * 0.035 + Vector3(0, 3.6, 0), basis, _velvet_mat, "velvet")
	# The crown moulding carries on over the doorways, on both faces: the VIP door, the lobby doors
	# and the start room's face over the waiting room door. Each piece spans exactly the gap the
	# runs leave (over the VIP door it was 0.2 m short at each end).
	for spec: Array in [[-hz, door + 0.2, 1.0], [-hz - 0.5, door + 0.2, -1.0], [lz - lt, ld, -1.0], [lz + lt, ld, 1.0], [hz, wd, -1.0]]:
		var z: float = spec[0]
		var n_z: float = spec[2]
		_box(Vector3(float(spec[1]) * 2.0, 0.22, 0.14), Vector3(0, LuckyLounge.WALL_H - 0.2, z + n_z * 0.07), _gold_mat, "gold")
	_reveals()
	# And over the Race Hall archway, on both faces.
	var arch_len: float = LuckyLounge.ARCH_Z1 - LuckyLounge.ARCH_Z0 + 0.4
	var arch_mid: float = (LuckyLounge.ARCH_Z0 + LuckyLounge.ARCH_Z1) * 0.5
	for x: float in [hx - 0.07, hx + 0.5 + 0.07]:
		_box(Vector3(0.14, 0.22, arch_len), Vector3(x, LuckyLounge.WALL_H - 0.2, arch_mid), _gold_mat, "gold")


## Mahogany linings on the reveals of the doorways that go through a wall (both jambs and the
## soffit), so a doorway reads as a door frame between its gold casings: the VIP door, the lobby
## doors, the waiting room door and the Race Hall archway.
func _reveals() -> void:
	var hz: float = LuckyLounge.SIZE_Z * 0.5
	var t: float = 0.5
	_reveal(Vector3(0, 0, -hz), Vector3.RIGHT, LuckyLounge.VIP_DOOR_HALF, LuckyLounge.VIP_DOOR_H, t)
	_reveal(Vector3(0, 0, LuckyLounge.LOBBY_DOORS_Z), Vector3.RIGHT, LuckyLounge.LOBBY_DOOR_HALF, LuckyLounge.LOBBY_DOOR_H, LuckyLounge.LOBBY_WALL_T)
	_reveal(Vector3(0, 0, hz), Vector3.RIGHT, LuckyLounge.WAIT_DOOR_HALF, LuckyLounge.WAIT_DOOR_H, t)
	var arch_mid: float = (LuckyLounge.ARCH_Z0 + LuckyLounge.ARCH_Z1) * 0.5
	_reveal(Vector3(LuckyLounge.SIZE_X * 0.5, 0, arch_mid), Vector3.BACK, (LuckyLounge.ARCH_Z1 - LuckyLounge.ARCH_Z0) * 0.5, LuckyLounge.ARCH_H, t)


## One doorway's lining: `c` is the opening's floor centre in the middle of the wall, `along` the
## wall's direction, `thick` the wall's thickness. The lining stands 6 mm proud of each face (under
## the casings) so no face of it lies in a wall face.
func _reveal(c: Vector3, along: Vector3, half: float, h: float, thick: float) -> void:
	var basis := Basis(along, Vector3.UP, along.cross(Vector3.UP))
	var depth: float = thick + 0.012
	for side: float in [-1.0, 1.0]:
		_box_b(Vector3(LINING_T, h, depth), c + along * side * (half - LINING_T * 0.5) + Vector3(0, h * 0.5, 0), basis, _wood_mat, "wood")
	_box_b(Vector3((half - LINING_T) * 2.0, LINING_T, depth), c + Vector3(0, h - LINING_T * 0.5, 0), basis, _wood_mat, "wood")


func _near_opening(p: Vector3, radius: float) -> bool:
	for w: Array in WINDOWS:
		var c: Vector3 = w[0]
		if Vector2(c.x, c.z).distance_to(Vector2(p.x, p.z)) < radius and absf(c.y - 3.6) < 2.0:
			return true
	for d: Array in DOORS:
		var c: Vector3 = d[0]
		if Vector2(c.x, c.z).distance_to(Vector2(p.x, p.z)) < radius and absf(c.y - 1.0) < 2.0:
			return true
	for c: Vector3 in OPENINGS:
		if Vector2(c.x, c.z).distance_to(Vector2(p.x, p.z)) < radius + 1.0:
			return true
	# The Race Hall archway in the casino's east wall.
	if absf(p.x - LuckyLounge.SIZE_X * 0.5) < 1.0 and p.z > LuckyLounge.ARCH_Z0 - 1.0 and p.z < LuckyLounge.ARCH_Z1 + 1.0:
		return true
	return false


func _ceiling() -> void:
	# Real coffers instead of a flat slab (0.9.63, Patrick: "nicht so hässlich flach"): a grid of
	# mahogany beams with gold edge beads and gold bosses where they cross, and in each coffer a
	# wine-red damask panel framed in gold with a gold rosette. A chandelier gets a big gold
	# medallion instead. The lines are picked so every chandelier and pedestal spot hangs in a
	# coffer, never in a beam. All of it is batched (a handful of MultiMeshes) and never collides.
	_retexture_solid("Ceiling", _tex("damask_wallpaper", 1.8, Color(0.74, 0.4, 0.34), 0.25, 0.7))
	_retexture_solid("CeilingWaiting", _tex("coffered_ceiling", 2.6, Color(0.95, 0.88, 0.8), 0.5, 0.75))
	var hx: float = LuckyLounge.SIZE_X * 0.5 - 0.25
	var hz: float = LuckyLounge.SIZE_Z * 0.5 - 0.25
	var lobby_z0: float = LuckyLounge.LOBBY_DOORS_Z - LuckyLounge.LOBBY_WALL_T * 0.5
	var lobby_z1: float = LuckyLounge.LOBBY_DOORS_Z + LuckyLounge.LOBBY_WALL_T * 0.5
	# Casino floor.
	# The cross beam at z = −1 runs right over the two free-standing columns, their head blocks
	# carry it (at −1.55 it cut through the edge of their capitals).
	_coffers(Rect2(-hx, -hz, hx * 2.0, lobby_z0 + hz), _sym_lines(4.3, hx), [-13.0, -9.0, -5.0, -1.0, 3.0])
	# Start room (its own spacing: the ready pedestals' spotlights stay clear of the beams).
	_coffers(Rect2(-hx, lobby_z1, hx * 2.0, hz - lobby_z1), _sym_lines(4.6, hx), [13.3])
	# VIP lounge.
	var vx: float = LuckyLounge.VIP_X - 0.25
	var vz: float = LuckyLounge.VIP_Z_FAR + 0.25
	_coffers(Rect2(-vx, vz, vx * 2.0, -LuckyLounge.SIZE_Z * 0.5 - 0.25 - vz), _sym_lines(3.0, vx), [-23.5, -18.5])
	# Race Hall.
	var ax0: float = LuckyLounge.SIZE_X * 0.5 + 0.25
	var ax1: float = LuckyLounge.ANNEX_X1 - 0.25
	var az0: float = LuckyLounge.ANNEX_Z0 + 0.25
	var az1: float = LuckyLounge.ANNEX_Z1 - 0.25
	_coffers(Rect2(ax0, az0, ax1 - ax0, az1 - az0), [27.25, 30.75], [-22.5, -14.5])


## Beam lines at ±(k + ½)·`step` inside ±`half` (the room's middle is a coffer, not a beam).
static func _sym_lines(step: float, half: float) -> Array[float]:
	var out: Array[float] = []
	var x: float = step * 0.5
	while x < half - 0.6:
		out.append(-x)
		out.append(x)
		x += step
	out.sort()
	return out


## One coffered ceiling over `area` (x/z, under the slab at WALL_H): beams along `xs` (running
## along z) and `zs` (running along x), a gold-framed panel and rosette in every coffer.
func _coffers(area: Rect2, xs: Array[float], zs: Array[float]) -> void:
	const BEAM_W: float = 0.36
	const BEAM_D: float = 0.4
	var top: float = LuckyLounge.WALL_H
	var bottom: float = top - BEAM_D
	var x0: float = area.position.x
	var x1: float = area.end.x
	var z0: float = area.position.y
	var z1: float = area.end.y
	var cx: float = (x0 + x1) * 0.5
	var cz: float = (z0 + z1) * 0.5
	var beam_mat: StandardMaterial3D = _beam_mat()
	for x: float in xs:
		_box(Vector3(BEAM_W, BEAM_D, z1 - z0), Vector3(x, top - BEAM_D * 0.5, cz), beam_mat, "beam")
		for side: float in [-1.0, 1.0]:
			_box(Vector3(0.05, 0.05, z1 - z0), Vector3(x + side * (BEAM_W * 0.5 - 0.01), bottom + 0.02, cz), _gold_mat, "gold")
	for z: float in zs:
		_box(Vector3(x1 - x0, BEAM_D, BEAM_W), Vector3(cx, top - BEAM_D * 0.5, z), beam_mat, "beam")
		for side: float in [-1.0, 1.0]:
			_box(Vector3(x1 - x0, 0.05, 0.05), Vector3(cx, bottom + 0.02, z + side * (BEAM_W * 0.5 - 0.01)), _gold_mat, "gold")
	var boss := CylinderMesh.new()
	boss.top_radius = 0.26
	boss.bottom_radius = 0.2
	boss.height = 0.1
	boss.radial_segments = 8
	for x: float in xs:
		for z: float in zs:
			_add(&"boss", boss, _gold_mat, Transform3D(Basis(Vector3.UP, PI / 8.0), Vector3(x, bottom - 0.04, z)))
	# The coffers: walls and beams bound them.
	var bx: Array[float] = [x0]
	bx.append_array(xs)
	bx.append(x1)
	var bz: Array[float] = [z0]
	bz.append_array(zs)
	bz.append(z1)
	var rosette := CylinderMesh.new()
	rosette.top_radius = 0.22
	rosette.bottom_radius = 0.3
	rosette.height = 0.06
	rosette.radial_segments = 12
	var medallion := TorusMesh.new()
	medallion.inner_radius = 0.55
	medallion.outer_radius = 0.72
	medallion.rings = 20
	medallion.ring_segments = 4
	var disc := CylinderMesh.new()
	disc.top_radius = 0.5
	disc.bottom_radius = 0.6
	disc.height = 0.05
	disc.radial_segments = 16
	for i: int in bx.size() - 1:
		for j: int in bz.size() - 1:
			var a := Vector2(bx[i] + (0.0 if i == 0 else BEAM_W * 0.5), bz[j] + (0.0 if j == 0 else BEAM_W * 0.5))
			var b := Vector2(bx[i + 1] - (0.0 if i + 1 == bx.size() - 1 else BEAM_W * 0.5), bz[j + 1] - (0.0 if j + 1 == bz.size() - 1 else BEAM_W * 0.5))
			var inset: float = 0.32
			var w: float = b.x - a.x - inset * 2.0
			var d: float = b.y - a.y - inset * 2.0
			if w < 0.8 or d < 0.8:
				continue
			var mid := Vector3((a.x + b.x) * 0.5, top - 0.02, (a.y + b.y) * 0.5)
			# Gold frame inside the coffer (cut where a column's head block reaches into it).
			_ceiling_strip(Vector3(w, 0.04, 0.06), mid + Vector3(0, 0, -d * 0.5))
			_ceiling_strip(Vector3(w, 0.04, 0.06), mid + Vector3(0, 0, d * 0.5))
			_ceiling_strip(Vector3(0.06, 0.04, d), mid + Vector3(-w * 0.5, 0, 0))
			_ceiling_strip(Vector3(0.06, 0.04, d), mid + Vector3(w * 0.5, 0, 0))
			if not _chandelier_near(mid, 1.4) and not _under_head(mid, 0.35) and minf(w, d) > 1.4:
				_add(&"rosette", rosette, _gold_mat, Transform3D(Basis(), mid + Vector3(0, -0.01, 0)))
	for p: Vector3 in CHANDELIERS:
		if p.x < x0 or p.x > x1 or p.z < z0 or p.z > z1:
			continue
		_add(&"medallion", medallion, _gold_mat, Transform3D(Basis(), Vector3(p.x, top - 0.04, p.z)))
		_add(&"medallion_disc", disc, _gold_mat, Transform3D(Basis(), Vector3(p.x, top - 0.03, p.z)))


func _chandelier_near(p: Vector3, r: float) -> bool:
	for c: Vector3 in CHANDELIERS:
		if Vector2(c.x, c.z).distance_to(Vector2(p.x, p.z)) < r:
			return true
	return false


# --- Columns, VIP lounge ----------------------------------------------------------------------

func _pillars() -> void:
	# Classical round columns (Quaternius) replace the plain cylinders; the collision cylinder
	# underneath stays. Pedestal to the rail, column, head block to the ceiling (PEDESTAL_TOP).
	for solid: Node3D in _solids("Pillar"):
		(solid.get_node(^"Mesh") as Node3D).visible = false
		var base: Node3D = solid.get_node_or_null(^"Base")
		if base != null:
			base.visible = false
		var col: Node3D = PropModels.make(&"column", HEAD_BOTTOM - PEDESTAL_TOP)
		col.scale = Vector3(0.75, 1.0, 0.75)
		col.position.y = -LuckyLounge.WALL_H * 0.5 + PEDESTAL_TOP
		_recolor(col, {"Marble": GreyboxKit.material(Palette.CREAM.darkened(0.12), 0.0, 0.55)})
		solid.add_child(col)
		var foot: Vector3 = solid.position - Vector3(0, LuckyLounge.WALL_H * 0.5, 0)
		var ped: float = PEDESTAL_TOP - 0.1
		_box(Vector3(PEDESTAL_HALF * 2.0, ped, PEDESTAL_HALF * 2.0), foot + Vector3(0, ped * 0.5, 0), _marble_mat, "marble")
		_box(Vector3(PEDESTAL_HALF * 2.0 + 0.08, 0.1, PEDESTAL_HALF * 2.0 + 0.08), foot + Vector3(0, ped + 0.05, 0), _brass_mat, "brass")
		var head: float = LuckyLounge.WALL_H - HEAD_BOTTOM
		_box(Vector3(HEAD_HALF * 2.0, head, HEAD_HALF * 2.0), foot + Vector3(0, HEAD_BOTTOM + head * 0.5, 0), _beam_mat(), "beam")
		_box(Vector3(HEAD_HALF * 2.0 + 0.08, 0.06, HEAD_HALF * 2.0 + 0.08), foot + Vector3(0, HEAD_BOTTOM + 0.03, 0), _gold_mat, "gold")


## The mahogany of the ceiling beams and the column head blocks.
func _beam_mat() -> StandardMaterial3D:
	return _tex("wooden_panels", 2.1, Color(0.5, 0.36, 0.3), 0.4, 0.55)


## [lo, hi] minus every interval in `cuts` (x = from, y = to): the pieces left that are longer
## than 2 cm.
static func _subtract(lo: float, hi: float, cuts: Array[Vector2]) -> Array[Vector2]:
	var out: Array[Vector2] = [Vector2(lo, hi)]
	for cut: Vector2 in cuts:
		var next: Array[Vector2] = []
		for seg: Vector2 in out:
			if cut.y <= seg.x or cut.x >= seg.y:
				next.append(seg)
				continue
			if cut.x > seg.x:
				next.append(Vector2(seg.x, cut.x))
			if cut.y < seg.y:
				next.append(Vector2(cut.y, seg.y))
		out = next
	var long: Array[Vector2] = []
	for seg: Vector2 in out:
		if seg.y - seg.x > 0.02:
			long.append(seg)
	return long


## A gold strip under the ceiling (an axis-aligned box along x or z), cut where a column's head
## block stands, so it dies into the block instead of running through it.
func _ceiling_strip(size: Vector3, pos: Vector3) -> void:
	var along_x: bool = size.x >= size.z
	var length: float = size.x if along_x else size.z
	var start: float = (pos.x if along_x else pos.z) - length * 0.5
	var half_across: float = (size.z if along_x else size.x) * 0.5
	var reach: float = HEAD_HALF + 0.04
	var cuts: Array[Vector2] = []
	for p: Vector3 in LuckyLounge.PILLARS:
		if absf((p.z if along_x else p.x) - (pos.z if along_x else pos.x)) < reach + half_across:
			var c: float = p.x if along_x else p.z
			cuts.append(Vector2(c - reach, c + reach))
	for seg: Vector2 in _subtract(start, start + length, cuts):
		var mid: float = (seg.x + seg.y) * 0.5
		if along_x:
			_box(Vector3(seg.y - seg.x, size.y, size.z), Vector3(mid, pos.y, pos.z), _gold_mat, "gold")
		else:
			_box(Vector3(size.x, size.y, seg.y - seg.x), Vector3(pos.x, pos.y, mid), _gold_mat, "gold")


## Whether `p` (x/z) is under a column's head block, grown by `margin`.
static func _under_head(p: Vector3, margin: float) -> bool:
	for c: Vector3 in LuckyLounge.PILLARS:
		if absf(c.x - p.x) < HEAD_HALF + margin and absf(c.z - p.z) < HEAD_HALF + margin:
			return true
	return false


func _vip_lounge() -> void:
	# The VIP lounge gets its own lamps (the chandelier alone left its corners dim) and a red
	# carpet runner from the door down the aisle between the tables.
	for x: float in [-5.5, 5.5]:
		var l: OmniLight3D = GreyboxKit.lamp(self, Vector3(x, 4.8, -21.0), 1.4, 9.0)
		l.name = "VipLamp"
	var runner := _plane(Vector2(2.0, 6.4), Vector3(-0.4, 0.016, -19.4), _carpet(Palette.VIP_BURGUNDY.lightened(0.05), Palette.VIP_BURGUNDY.darkened(0.2), 0.8))
	runner.name = "VipRunner"
	for x: float in [-1.44, 0.64]:
		_box(Vector3(0.1, 0.008, 6.4), Vector3(x, 0.018, -19.4), _brass_mat, "brass")


# --- Furniture and props ----------------------------------------------------------------------

func _furniture() -> void:
	# The Gift Shop booth in the room's wood, marble, velvet and brass, its lamps on.
	if map.gift_shop != null:
		map.gift_shop.dress(_wood_mat, _marble_mat, _velvet_mat, _brass_mat)
	_retexture_solid("JailBench", _wood_mat)
	_retexture_solid("Plinth", _marble_mat)
	_retexture_solid("Rope", _velvet_mat)
	# Marble bust and horse statue on short columns against the VIP lounge's side walls.
	for spec: Array in [[Vector3(-8.2, 0.0, -21.0), &"bust", 0.9], [Vector3(8.2, 0.0, -21.0), &"horse", 1.0]]:
		var pedestal: Node3D = PropModels.make(&"pedestal", 1.0)
		pedestal.scale = Vector3(0.55, 1.0, 0.55)
		pedestal.position = spec[0]
		_recolor(pedestal, {"Marble": _marble_mat})
		add_child(pedestal)
		var statue: Node3D = PropModels.make(spec[1], spec[2])
		statue.position = spec[0] + Vector3(0, 1.0, 0)
		statue.rotation.y = PI * 0.5 * (1.0 if spec[0].x < 0.0 else -1.0)
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
		_window_sets.append([win, curtains])


## Hides every window (and its curtains) a game on the floor would clip: a game's colliders reach
## into the curtains' box and stand taller than their hem (a slot cabinet under the sill is fine).
func _clear_windows() -> void:
	var games: Array[AABB] = []
	for sid: StringName in map.stations:
		var st: StationBase = map.stations[sid]
		if is_instance_valid(st) and st.is_inside_tree():
			var b: AABB = _collider_box(st)
			if b.size != Vector3.ZERO:
				games.append(b)
	for pair: Array in _window_sets:
		var win: Node3D = pair[0]
		var curtains: Node3D = pair[1]
		var zone: AABB = _mesh_box(curtains).merge(_mesh_box(win)).grow(0.05)
		var blocked: bool = false
		for g: AABB in games:
			if g.end.y > zone.position.y + 0.25 and g.intersects(zone):
				blocked = true
				break
		win.visible = not blocked
		curtains.visible = not blocked


## World box round a node's meshes.
static func _mesh_box(root: Node3D) -> AABB:
	var out := AABB()
	var first: bool = true
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		var b: AABB = mi.global_transform * mi.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out


## World box round a station's solid colliders (its static bodies; not the interact areas).
static func _collider_box(st: Node3D) -> AABB:
	var out := AABB()
	var first: bool = true
	for body: Node in st.find_children("*", "StaticBody3D", true, false):
		for cs: Node in body.find_children("*", "CollisionShape3D", true, false):
			var shape: Shape3D = (cs as CollisionShape3D).shape
			if shape == null or (cs as CollisionShape3D).disabled:
				continue
			var b: AABB = (cs as CollisionShape3D).global_transform * shape.get_debug_mesh().get_aabb()
			out = b if first else out.merge(b)
			first = false
	return out


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
	# Paintings in the mouldings along the game floor. (The entrance hall's two mirrors left the
	# pedestal wall in 0.9.57: they hung between the name plates and crowded the pedestals.)
	for spec: Array in [
		[Vector3(-21.75, 3.5, -7.5), Vector3(1, 0, 0)], [Vector3(-21.75, 3.6, 9.8), Vector3(1, 0, 0)],
		[Vector3(21.75, 3.5, 11.0), Vector3(-1, 0, 0)], [Vector3(29.0, 3.5, LuckyLounge.ANNEX_Z1 - 0.25), Vector3(0, 0, -1)],
		[Vector3(-8.75, 3.6, -18.4), Vector3(1, 0, 0)], [Vector3(8.75, 3.6, -18.4), Vector3(-1, 0, 0)],
	]:
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
		spots.append([Vector3(x, y, LuckyLounge.ANNEX_Z0 + 0.3), Vector3(0, 0, 1)])
	for i: int in 4:
		var z: float = -hz + 3.0 + i * (2.0 * hz - 6.0) / 3.0
		spots.append([Vector3(-hx, y, z), Vector3(1, 0, 0)])
		spots.append([Vector3(hx, y, z), Vector3(-1, 0, 0)])
	# The Race Hall: either side of its windows, and its north and south walls.
	var ax: float = LuckyLounge.ANNEX_X1 - 0.3
	for z: float in [-25.0, -19.0, -12.5]:
		spots.append([Vector3(ax, y, z), Vector3(-1, 0, 0)])
	for x: float in [25.0, 33.0]:
		spots.append([Vector3(x, y, LuckyLounge.ANNEX_Z1 - 0.3), Vector3(0, 0, -1)])
		spots.append([Vector3(x, y, LuckyLounge.ANNEX_Z0 + 0.3), Vector3(0, 0, 1)])
	# The VIP lounge's side walls.
	for z: float in [-23.6, -18.4]:
		spots.append([Vector3(-LuckyLounge.VIP_X + 0.05, y, z), Vector3(1, 0, 0)])
		spots.append([Vector3(LuckyLounge.VIP_X - 0.05, y, z), Vector3(-1, 0, 0)])
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
	# The chip's back sits 1.7 m behind the model's origin at full size: flush with the wall.
	sign.position = Vector3(0.0, 4.95, LuckyLounge.SIZE_Z * 0.5 - 0.27 - 1.7 * SIGN_SCALE)
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


# --- The waiting room -------------------------------------------------------------------------

## The play-money room behind the entrance gap, dressed like the rest of the lounge but cosier:
## herringbone parquet, damask over mahogany wainscoting with a brass rail, gold crown moulding
## under its low coffered ceiling (the map's `CeilingWaiting` gets the coffers with the others), a
## small chandelier over the blackjack table, sconces either side of the sign and a red runner from
## the door.
func _waiting_room() -> void:
	if map.get_node_or_null(^"WaitFloor") == null:
		return
	var x: float = LuckyLounge.WAIT_X
	var z0: float = LuckyLounge.WAIT_Z0
	var z1: float = LuckyLounge.WAIT_Z1
	var h: float = LuckyLounge.WAIT_H
	_retexture("WaitFloor", _tex("herringbone_parquet", 1.6, Color(0.72, 0.56, 0.44), 0.45, 0.5))
	_retexture_solid("WaitWall", _tex("damask_wallpaper", 2.0, Color(0.95, 0.9, 0.9), 0.0, 0.85))
	var door: float = WAIT_CASING_OUT
	# The door's gold casing on this face too (the map builds the start-room one), the same
	# size, so the runs either side stop at it and the reveal doesn't end in bare wallpaper.
	var dh: float = LuckyLounge.WAIT_DOOR_H
	for sx: float in [-1.0, 1.0]:
		_box(Vector3(0.16, dh + 0.08, 0.06), Vector3(sx * (LuckyLounge.WAIT_DOOR_HALF + 0.08), (dh + 0.08) * 0.5, z0 + 0.03), _gold_mat, "gold")
	_box(Vector3(LuckyLounge.WAIT_DOOR_HALF * 2.0 + 0.32, 0.12, 0.07), Vector3(0, dh + 0.04, z0 + 0.035), _gold_mat, "gold")
	var runs: Array = [
		[Vector3(-x, 0, z0), Vector3(-x, 0, z1), Vector3(1, 0, 0)],
		[Vector3(x, 0, z0), Vector3(x, 0, z1), Vector3(-1, 0, 0)],
		[Vector3(-x, 0, z1), Vector3(x, 0, z1), Vector3(0, 0, -1)],
		[Vector3(-x, 0, z0), Vector3(-door, 0, z0), Vector3(0, 0, 1)],
		[Vector3(door, 0, z0), Vector3(x, 0, z0), Vector3(0, 0, 1)],
	]
	for run: Array in runs:
		var a: Vector3 = run[0]
		var b: Vector3 = run[1]
		var n: Vector3 = run[2]
		var mid: Vector3 = (a + b) * 0.5
		var length: float = (b - a).length()
		var basis := Basis.looking_at(-n, Vector3.UP)
		_box_b(Vector3(length, 1.05, 0.06), mid + n * 0.03 + Vector3(0, 0.525, 0), basis, _wood_mat, "wood")
		_box_b(Vector3(length, 0.09, 0.1), mid + n * 0.06 + Vector3(0, 1.08, 0), basis, _brass_mat, "brass")
		_box_b(Vector3(length, 0.18, 0.12), mid + n * 0.06 + Vector3(0, h - 0.09, 0), basis, _gold_mat, "gold")
	# The crown moulding carries on over the door, and a runner leads in from it.
	_box(Vector3(door * 2.0, 0.18, 0.12), Vector3(0, h - 0.09, z0 + 0.06), _gold_mat, "gold")
	var run_len: float = 2.0
	_plane(Vector2(2.4, run_len), Vector3(0, 0.03, z0 + run_len * 0.5), _carpet(Palette.CASINO_RED.darkened(0.15), Palette.CASINO_RED.darkened(0.35), 0.8)).name = "WaitRunner"
	# A small chandelier over the table: gold ring, bulbs and crystals.
	var ring := TorusMesh.new()
	ring.inner_radius = 0.42
	ring.outer_radius = 0.5
	ring.rings = 20
	ring.ring_segments = 6
	var bulb := SphereMesh.new()
	bulb.radius = 0.07
	bulb.height = 0.14
	bulb.radial_segments = 8
	bulb.rings = 4
	var crystal := PrismMesh.new()
	crystal.size = Vector3(0.06, 0.18, 0.06)
	var stem := CylinderMesh.new()
	stem.top_radius = 0.025
	stem.bottom_radius = 0.025
	stem.height = 1.0
	stem.radial_segments = 6
	var c := Vector3(0, h - 0.75, 20.3)
	_add(&"stem", stem, _gold_mat, Transform3D(Basis().scaled(Vector3(1, 0.75, 1)), c + Vector3(0, 0.375, 0)))
	_add(&"ring", ring, _gold_mat, Transform3D(Basis(), c))
	for i: int in 8:
		var o := Vector3(cos(TAU * i / 8.0), 0, sin(TAU * i / 8.0))
		_add(&"bulb", bulb, _bulb_mat, Transform3D(Basis(), c + o * 0.46 + Vector3(0, 0.1, 0)))
		_add(&"crystal", crystal, _crystal_mat, Transform3D(Basis(Vector3.RIGHT, PI), c + o * 0.46 + Vector3(0, -0.17, 0)))
	_add(&"bulb", bulb, _bulb_mat, Transform3D(Basis().scaled(Vector3.ONE * 1.5), c + Vector3(0, -0.3, 0)))
	# Sconces either side of the sign board, and a painting on each side wall between the slots.
	var plate := BoxMesh.new()
	plate.size = Vector3(0.2, 0.42, 0.05)
	var shade := CylinderMesh.new()
	shade.top_radius = 0.09
	shade.bottom_radius = 0.15
	shade.height = 0.22
	shade.radial_segments = 10
	var shade_mat := StandardMaterial3D.new()
	shade_mat.albedo_color = Palette.CREAM
	shade_mat.emission_enabled = true
	shade_mat.emission = Color(1.0, 0.78, 0.45)
	shade_mat.emission_energy_multiplier = 1.6
	for sx: float in [-3.3, 3.3]:
		var p := Vector3(sx, 2.6, z1)
		_add(&"plate", plate, _gold_mat, Transform3D(Basis(), p - Vector3(0, 0, 0.03)))
		_add(&"shade", shade, shade_mat, Transform3D(Basis(), p + Vector3(0, 0.18, -0.18)))
	for sx: float in [-1.0, 1.0]:
		var pic: Node3D = PropModels.make(&"picture", 0.0, 1.2)
		pic.position = Vector3(sx * (x - 0.1), 1.9, 19.3)
		pic.rotation.y = -sx * PI * 0.5
		add_child(pic)


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
