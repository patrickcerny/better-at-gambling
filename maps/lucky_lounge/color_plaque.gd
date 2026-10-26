class_name ColorPlaque
extends Node3D
## The colour panel at the foot of a ready pedestal (Patrick: "under the podest should be a color
## panel you can click (choose color). If you choose that, your bean is in that color."): a brass
## lectern beside the bottom step with a tilted plaque of colour swatches, 4 × 4. On your own
## pedestal it shows the colours you own (`PlayerProfile.owned_colors`), the one you wear framed in
## gold and the ones other beans wear dimmed; look at one and click (or E) to wear it
## (`ColorPanelController`). Other players' plaques show the free colours, dimmed, with the colour
## their bean wears framed. Visual only: no collision, the server never sees it.

const COLUMNS: int = 4
const ROWS: int = 4
## Swatch size and pitch on the plaque (m).
const SWATCH: float = 0.085
const PITCH: float = 0.105
## Where the lectern stands relative to its pedestal's centre: beside the lowest step, room side.
const OFFSET: Vector3 = Vector3(0.8, 0, -1.95)
## Height of the plaque's centre and how far it tips back (its face looks up at whoever stands
## in front, on the room side −z).
const HEIGHT: float = 0.82
const TILT_DEG: float = 50.0
## Half the plaque face (m) and the front face's z in the plaque's space.
const HALF: Vector2 = Vector2(0.25, 0.25)
const FACE_Z: float = -0.016
## How far away the swatches can be pointed at (m from the camera).
const REACH: float = 3.2

## The plaque itself; swatches are its children. Its −Z is the face normal.
var face: Node3D
## Colour index → its swatch mesh (only the ones shown).
var swatches: Dictionary[int, MeshInstance3D] = {}
## The colours in grid order (row-major, top-left first as seen from the front).
var colors: Array[int] = []
## The swatch that is framed (worn) and the one under the crosshair (-1 = none).
var worn: int = -1
var hovered: int = -1
## Whether this is the local player's own panel (lit and clickable).
var interactive: bool = false
var title: Label3D
var _frame: MeshInstance3D
var _key: Array = []


func _init() -> void:
	name = "ColorPlaque"


func _ready() -> void:
	var brass: StandardMaterial3D = GreyboxKit.material(Palette.WARM_GOLD, 0.85, 0.3)
	_box(self, Vector3(0.3, 0.03, 0.22), Vector3(0, 0.015, 0), brass).name = "Foot"
	_box(self, Vector3(0.05, HEIGHT - 0.12, 0.05), Vector3(0, (HEIGHT - 0.12) * 0.5, 0.02), brass).name = "Post"
	face = Node3D.new()
	face.name = "Face"
	face.position = Vector3(0, HEIGHT, 0)
	face.rotation.x = deg_to_rad(TILT_DEG)
	add_child(face)
	_box(face, Vector3(HALF.x * 2.0 + 0.04, HALF.y * 2.0 + 0.04, 0.03), Vector3.ZERO, brass).name = "Plate"
	_box(face, Vector3(HALF.x * 2.0, HALF.y * 2.0, 0.006), Vector3(0, 0, -0.013), GreyboxKit.material(Palette.CASINO_BLACK.lightened(0.05), 0.2, 0.6)).name = "Inset"
	_frame = _box(face, Vector3(SWATCH + 0.024, SWATCH + 0.024, 0.006), Vector3.ZERO, _glow_mat(Palette.VIP_GOLD))
	_frame.name = "WornFrame"
	_frame.visible = false
	title = Label3D.new()
	title.name = "Title"
	title.text = "COLOUR"
	title.font_size = 30
	title.pixel_size = 0.0028
	title.modulate = Palette.VIP_GOLD
	title.outline_modulate = Palette.CASINO_BLACK
	title.outline_size = 6
	title.position = Vector3(0, HALF.y + 0.045, -0.02)
	title.rotation.y = PI  # read from the room side
	face.add_child(title)


## Shows `p_colors` (grid order, at most 16) with `p_worn` framed and `dimmed` greyed out.
## Rebuilt only when something changed.
func show_colors(p_colors: Array[int], p_worn: int, dimmed: Array[int], p_interactive: bool) -> void:
	var key: Array = [p_colors.duplicate(), p_worn, dimmed.duplicate(), p_interactive]
	if key == _key or face == null:
		return
	_key = key
	colors = p_colors.slice(0, COLUMNS * ROWS)
	worn = p_worn
	interactive = p_interactive
	for s: MeshInstance3D in swatches.values():
		s.queue_free()
	swatches.clear()
	hovered = -1
	for i: int in colors.size():
		var c: int = colors[i]
		var col: Color = Palette.player_color(c)
		if c in dimmed or not interactive and c != worn:
			col = col.darkened(0.6)
		var m: MeshInstance3D = _box(face, Vector3(SWATCH, SWATCH, 0.014), _cell(i) + Vector3(0, 0, -0.02), _glow_mat(col, 0.25 if interactive else 0.08))
		m.name = "Swatch%d" % c
		swatches[c] = m
	_frame.visible = swatches.has(worn)
	if _frame.visible:
		_frame.position = swatches[worn].position + Vector3(0, 0, 0.004)
	title.text = "YOUR COLOUR" if interactive else "COLOUR"


## Centre of grid cell `i` on the plaque (row-major, top-left first as seen from the room side).
func _cell(i: int) -> Vector3:
	@warning_ignore("integer_division")
	var row: int = i / COLUMNS
	var col: int = i % COLUMNS
	# Seen from −z, the plaque's +x is on the viewer's left.
	return Vector3((float(COLUMNS - 1) * 0.5 - col) * PITCH, (float(ROWS - 1) * 0.5 - row) * PITCH, 0)


## The colour whose swatch the ray from `origin` along `dir` (world) points at, or -1.
func swatch_at(origin: Vector3, dir: Vector3) -> int:
	if face == null or not face.is_inside_tree() or colors.is_empty():
		return -1
	var inv: Transform3D = face.global_transform.affine_inverse()
	var o: Vector3 = inv * origin
	var d: Vector3 = inv.basis * dir
	if d.z <= 0.0001 or o.z >= FACE_Z:
		return -1  # behind the plaque or looking away from it
	var t: float = (FACE_Z - o.z) / d.z
	var hit: Vector3 = o + d * t
	if (hit - o).length() > REACH:
		return -1
	for i: int in colors.size():
		var cell: Vector3 = _cell(i)
		if absf(hit.x - cell.x) <= PITCH * 0.5 and absf(hit.y - cell.y) <= PITCH * 0.5:
			return colors[i]
	return -1


## World position of the swatch for colour `c` (tests aim at it), or `Vector3.INF`.
func swatch_position(c: int) -> Vector3:
	return swatches[c].global_position if swatches.has(c) and swatches[c].is_inside_tree() else Vector3.INF


## Lifts the swatch under the crosshair.
func set_hovered(c: int) -> void:
	if c == hovered:
		return
	if swatches.has(hovered):
		swatches[hovered].scale = Vector3.ONE
	hovered = c
	if swatches.has(c):
		swatches[c].scale = Vector3(1.25, 1.25, 2.0)


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _glow_mat(c: Color, glow: float = 0.4) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.4
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = glow
	return m
