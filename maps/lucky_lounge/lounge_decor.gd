class_name LoungeDecor
extends Node3D
## Client-only dressing for the Lucky Lounge (M7 art pass, docs/ART_DIRECTION.md): patterned
## carpet, a marble lobby with a red runner, dark wood wainscoting and framed wall panels, gold
## crown moulding, crystal chandeliers with glowing bulbs, wall sconces, marquee bulbs around the
## signs, and a warm haze + glow on the WorldEnvironment so only bulbs and signage bloom.
##
## Nothing here collides or touches gameplay. `LuckyLounge` adds it only when `Vfx.enabled()`
## (never on the headless dedicated server). Repeated pieces are MultiMeshes, so the whole
## pass costs a handful of draw calls on gl_compatibility.

const FLOOR_SHADER: Shader = preload("res://vfx/shaders/casino_floor.gdshader")
## Where the chandeliers hang (the map's room lamps sit at the same points).
const CHANDELIERS: Array[Vector3] = [
	Vector3(0, 6.0, 11), Vector3(0, 6.5, -3), Vector3(-13, 6.0, 4), Vector3(-13, 6.0, -11),
	Vector3(14, 6.0, -12), Vector3(16, 6.0, 4), Vector3(0, LuckyLounge.MEZZ_Y + 2.5, -5),
]
const BULB_COLOR: Color = Color(1.0, 0.82, 0.52)
const WOOD: Color = Color("#2A1A14")
const WALL_PANEL: Color = Color("#5A2A2A")

var map: LuckyLounge
## Batches filled while building, turned into MultiMeshes at the end: key → [mesh, material, transforms].
var _batches: Dictionary = {}
var _bulb_mat: StandardMaterial3D
var _crystal_mat: StandardMaterial3D
var _gold_mat: StandardMaterial3D


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
	_floors()
	_walls()
	_chandeliers()
	_sconces()
	_signs()
	_environment()
	_flush()


# --- Floors -----------------------------------------------------------------------------------

func _floors() -> void:
	_retexture("Carpet", _carpet(Palette.CASINO_RED.darkened(0.42), Palette.CASINO_RED.darkened(0.55), 1.4))
	_retexture("VipCarpet", _carpet(Palette.VIP_BURGUNDY, Palette.VIP_BURGUNDY.darkened(0.3), 1.0))
	# The entrance hall is marble (black and cream), with a red runner from the revolving door.
	_retexture("LobbyCarpet", _marble())
	# Runner from the revolving door up to the fountain.
	var runner := _plane(Vector2(3.2, 3.4), Vector3(0, 0.02, 14.4), _carpet(Palette.CASINO_RED.darkened(0.15), Palette.CASINO_RED.darkened(0.35), 0.8))
	runner.name = "Runner"
	for x: float in [-1.66, 1.66]:
		_box(Vector3(0.12, 0.012, 3.4), Vector3(x, 0.022, 14.4), _gold_mat, "edge")


func _retexture(node_name: String, mat: Material) -> void:
	var mi: MeshInstance3D = map.get_node_or_null(node_name) as MeshInstance3D
	if mi != null:
		mi.material_override = mat


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


static func _marble() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FLOOR_SHADER
	m.set_shader_parameter(&"mode", 1)
	m.set_shader_parameter(&"base_color", Color("#D6CCBA"))
	m.set_shader_parameter(&"alt_color", Color("#3A302B"))
	m.set_shader_parameter(&"accent_color", Palette.WARM_GOLD)
	m.set_shader_parameter(&"tile", 1.1)
	m.set_shader_parameter(&"roughness_value", 0.3)
	return m


# --- Walls ------------------------------------------------------------------------------------

func _walls() -> void:
	var hx: float = LuckyLounge.SIZE_X * 0.5 - 0.25
	var hz: float = LuckyLounge.SIZE_Z * 0.5 - 0.25
	var wood := GreyboxKit.material(WOOD)
	var panel_mat := GreyboxKit.material(WALL_PANEL)
	# North and east/west walls run full length; the south wall has the revolving-door gap.
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
		# Wainscot (dark wood to 1.05 m), gold chair rail, gold crown moulding under the ceiling.
		_box_b(Vector3(length, 1.05, 0.06), mid + n * 0.03 + Vector3(0, 0.525, 0), basis, wood, "wood")
		_box_b(Vector3(length, 0.09, 0.1), mid + n * 0.06 + Vector3(0, 1.08, 0), basis, _gold_mat, "gold")
		_box_b(Vector3(length, 0.22, 0.14), mid + n * 0.07 + Vector3(0, LuckyLounge.WALL_H - 0.2, 0), basis, _gold_mat, "gold")
		# Framed damask-coloured panels between the rail and the moulding.
		var count: int = maxi(1, int(length / 3.6))
		var step: float = length / count
		for i: int in count:
			var c: Vector3 = a + dir * (step * (i + 0.5)) + Vector3(0, 3.6, 0)
			_box_b(Vector3(step - 0.7, 3.9, 0.04), c + n * 0.02, basis, _gold_mat, "gold")
			_box_b(Vector3(step - 0.86, 3.74, 0.05), c + n * 0.035, basis, panel_mat, "panel")


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
		var basis := Basis.looking_at(-n, Vector3.UP)
		_add(&"plate", plate, _gold_mat, Transform3D(basis, p + n * 0.03))
		_add(&"shade", shade, shade_mat, Transform3D(Basis(), p + n * 0.2 + Vector3(0, 0.2, 0)))


func _signs() -> void:
	var bulb := SphereMesh.new()
	bulb.radius = 0.06
	bulb.height = 0.12
	bulb.radial_segments = 8
	bulb.rings = 4
	# Casino name over the inside of the entrance, ringed with marquee bulbs.
	var sign_c := Vector3(0, 5.0, LuckyLounge.SIZE_Z * 0.5 - 0.62)
	_marquee(bulb, sign_c, Vector2(7.0, 1.2), Vector3(0, 0, -1))
	var title := _label("THE LUCKY LOUNGE", 120, Palette.VIP_GOLD)
	title.position = sign_c + Vector3(0, 0, -0.02)
	title.rotation.y = PI
	add_child(title)
	# VIP sign on the mezzanine edge.
	var vip_c := Vector3(9.0, LuckyLounge.MEZZ_Y + 2.6, -1.0 + 0.07)
	_marquee(bulb, vip_c + Vector3(0, 0, 0.02), Vector2(2.6, 0.8), Vector3(0, 0, 1))
	var vip := _label("VIP LOUNGE", 72, Palette.VIP_BURGUNDY)
	vip.outline_modulate = Palette.VIP_GOLD
	vip.outline_size = 4
	vip.position = vip_c + Vector3(0, 0, 0.01)
	add_child(vip)


## Bulbs around a rectangular sign (centre `c`, size `s`, facing `n`).
func _marquee(bulb: Mesh, c: Vector3, s: Vector2, n: Vector3) -> void:
	var right: Vector3 = Vector3.UP.cross(n).normalized()
	var nx: int = int(s.x / 0.32)
	var ny: int = int(s.y / 0.32)
	for i: int in nx + 1:
		var x: float = -s.x * 0.5 + s.x * i / nx
		for y: float in [-s.y * 0.5, s.y * 0.5]:
			_add(&"marquee", bulb, _bulb_mat, Transform3D(Basis(), c + right * x + Vector3(0, y, 0) + n * 0.08))
	for j: int in range(1, ny):
		var y: float = -s.y * 0.5 + s.y * j / ny
		for x: float in [-s.x * 0.5, s.x * 0.5]:
			_add(&"marquee", bulb, _bulb_mat, Transform3D(Basis(), c + right * x + Vector3(0, y, 0) + n * 0.08))


func _label(text: String, size: int, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = Vfx.font()
	l.font_size = size
	l.pixel_size = 0.005
	l.modulate = color
	l.outline_modulate = Palette.CASINO_BLACK
	l.outline_size = 12
	return l


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
