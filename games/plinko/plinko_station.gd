class_name PlinkoStation
extends StationBase
## Wall-mounted Plinko machine: 4 m tall board, 12 peg rows, 13 slots, 2 standing spots.
## Collision (cabinet, rails, glass, tray) exists everywhere; the dressing (gold-trimmed face,
## funnel, peg field, payout-coloured buckets with their multipliers written on them, marquee)
## is client only. The board geometry is static so `PlinkoFlight` can plan chips without nodes.

const ROWS: int = 12
const SLOTS: int = 13
const BOARD_W: float = 3.6
const BOARD_H: float = 4.0
const PEG_RADIUS: float = 0.03
## Visual chip radius (fits between two pegs of a row with room to spare).
const CHIP_R: float = 0.075
## Local y of the tray the chips land on (bottom of the board face).
const FLOOR_Y: float = 0.6
## Top of the slot dividers, and their thickness.
const DIV_TOP: float = 0.95
const DIV_T: float = 0.03
## Gap between the release height and the first peg row.
const ROW_TOP_GAP: float = 0.4
## Payout colours from the losing middle to the big edges (charcoal → cream → gold → red).
const LOW_COLOR: Color = Color("#3A3330")

## World x of each slot centre (local), left to right.
var slot_xs: Array[float] = []
## Local y of the top of the board where chips are released.
var drop_y: float = 0.0
## Risk row whose multipliers the buckets show.
var risk: StringName = &"medium"
## Client-only dressing; null on a headless server.
var pegs_parent: Node3D
var slot_labels: Array[Label3D] = []
var jackpot_tags: Array[Label3D] = []
var risk_sign: Label3D
var _bucket_mats: Array[StandardMaterial3D] = []
var _buckets: Array[MeshInstance3D] = []
## Money piles beside the board, shown once the jackpot has grown (Patrick: "next to plinko when
## jackpot big"). Left pile from 3x the seed, right one from 6x; both grow up to 10x.
var _money_piles: Array[Node3D] = []
var _flash_mesh: SphereMesh
var _flash_mat: StandardMaterial3D


# --- Static board geometry (local metres; x across, y up, the board face at z = 0) --------------

static func slot_w() -> float:
	return BOARD_W / SLOTS


static func slot_x(s: int) -> float:
	return (s - (SLOTS - 1) * 0.5) * slot_w()


static func top_y() -> float:
	return FLOOR_Y + BOARD_H - 0.3


static func row_h() -> float:
	return (BOARD_H - 1.2) / ROWS


static func row_y(r: int) -> float:
	return top_y() - ROW_TOP_GAP - r * row_h()


## Pegs in a row: even rows sit over the slot centres, odd rows over the slot edges.
static func peg_count(r: int) -> int:
	return SLOTS if r % 2 == 0 else SLOTS + 1


static func peg_pos(r: int, c: int) -> Vector2:
	return Vector2((c - (peg_count(r) - 1) * 0.5) * slot_w(), row_y(r))


## Column of the peg under a `PlinkoSteering` path position (slot units) on row `r`.
static func peg_col(r: int, path_pos: float) -> int:
	return int(round(path_pos)) if r % 2 == 0 else int(round(path_pos + 0.5))


## Where chips leave the funnel.
static func entry_y() -> float:
	return top_y() + 0.32


## Colour of a bucket paying `mult`, relative to the row's best `top`.
static func bucket_color(mult: float, top: float) -> Color:
	if mult < 1.0:
		return LOW_COLOR.lerp(Palette.WARM_CHARCOAL, 0.3)
	var k: float = clampf(log(mult) / log(maxf(top, 1.01)), 0.0, 1.0)
	if k < 0.5:
		return Palette.CREAM.darkened(0.25).lerp(Palette.WARM_GOLD, k * 2.0)
	return Palette.WARM_GOLD.lerp(Palette.CASINO_RED, (k - 0.5) * 2.0)


## "×13", "×0.5".
static func mult_text(m: float) -> String:
	return "×" + (("%d" % int(m)) if is_equal_approx(m, floor(m)) else ("%.1f" % m))


func _build_visuals() -> void:
	game_id = &"plinko"
	seat_count = 2
	interact_radius = 3.0
	_rug(Vector2(5.0, 4.0), Palette.VIP_BURGUNDY.darkened(0.3))
	var mid_y: float = FLOOR_Y + BOARD_H * 0.5
	# Collision: cabinet, side rails, tray and the glass that keeps hands off the pegs.
	GreyboxKit.box(self, Vector3(BOARD_W + 0.5, BOARD_H + 1.1, 0.2), Vector3(0, mid_y + 0.3, -0.25), Color("#2E2018"), "Backboard")
	for side: float in [-1.0, 1.0]:
		var rail: Node3D = GreyboxKit.box(self, Vector3(0.1, BOARD_H, 0.3), Vector3(side * (BOARD_W * 0.5 + 0.05), mid_y, 0.0), Palette.WARM_GOLD, "RailL" if side < 0.0 else "RailR")
		(rail.get_node("Mesh") as MeshInstance3D).material_override = GreyboxKit.gold()
	GreyboxKit.box(self, Vector3(BOARD_W + 0.3, FLOOR_Y, 0.5), Vector3(0, FLOOR_Y * 0.5, 0.0), Color("#2E2018"), "Tray")
	GreyboxKit.box(self, Vector3(BOARD_W + 0.2, BOARD_H + 0.2, 0.02), Vector3(0, mid_y, 0.16), Color(1, 1, 1, 0.0), "Glass")
	(get_node("Glass/Mesh") as MeshInstance3D).visible = false
	drop_y = top_y()
	for s: int in SLOTS:
		slot_xs.append(slot_x(s))
	for x: float in [-0.8, 0.8]:
		_stool(Vector3(x, 0, 2.2), "Stool%d" % seats.size())
		_add_seat(Vector3(x, 0.5, 2.2), 0.0)
	# Seated view: the whole board from funnel to buckets, set a little right so the panel docked
	# at the right edge of the screen never covers it.
	camera_anchor = Node3D.new()
	camera_anchor.name = "CameraAnchor"
	camera_anchor.position = Vector3(0.55, 2.85, 3.5)
	camera_anchor.rotation.x = deg_to_rad(-2.0)
	add_child(camera_anchor)
	if Vfx.enabled():
		_build_dressing()
		set_risk(risk)


func _build_dressing() -> void:
	var mid_y: float = FLOOR_Y + BOARD_H * 0.5
	var wood: StandardMaterial3D = GreyboxKit.material(Color("#3A2A1E"))
	var gold: StandardMaterial3D = GreyboxKit.gold()
	# Face: deep burgundy so gold pegs and cream labels read; a darker inset band for the buckets.
	_mesh(_box(Vector3(BOARD_W, BOARD_H, 0.02)), Vector3(0, mid_y, -0.14), GreyboxKit.material(Palette.VIP_BURGUNDY.darkened(0.15)), "Face")
	# Gold trim frame round the face, and a cap on the cabinet.
	for side: float in [-1.0, 1.0]:
		_mesh(_box(Vector3(0.06, BOARD_H + 0.12, 0.06)), Vector3(side * (BOARD_W * 0.5 + 0.13), mid_y, -0.1), gold, "Trim")
	_mesh(_box(Vector3(BOARD_W + 0.32, 0.06, 0.06)), Vector3(0, FLOOR_Y + BOARD_H + 0.03, -0.1), gold, "TrimTop")
	_mesh(_box(Vector3(BOARD_W + 0.32, 0.05, 0.06)), Vector3(0, FLOOR_Y + 0.02, 0.24), gold, "TrimLip")
	# Marquee over the board.
	_mesh(_box(Vector3(BOARD_W * 0.62, 0.72, 0.14)), Vector3(0, FLOOR_Y + BOARD_H + 0.46, -0.08), wood, "Marquee")
	_mesh(_box(Vector3(BOARD_W * 0.62 + 0.08, 0.04, 0.16)), Vector3(0, FLOOR_Y + BOARD_H + 0.84, -0.08), gold, "MarqueeTrim")
	var title := _label("PLINKO", 120, 0.0036, Palette.VIP_GOLD)
	title.position = Vector3(0, FLOOR_Y + BOARD_H + 0.56, 0.0)
	add_child(title)
	risk_sign = _label("", 48, 0.0026, Palette.CREAM)
	risk_sign.position = Vector3(0, FLOOR_Y + BOARD_H + 0.27, 0.0)
	add_child(risk_sign)
	_marquee_bulbs()
	# Funnel the chip drops from: two slanted gold bars and a small hopper mouth.
	for side: float in [-1.0, 1.0]:
		var bar: MeshInstance3D = _mesh(_box(Vector3(0.42, 0.04, 0.18)), Vector3(side * 0.37, top_y() + 0.27, 0.0), gold, "Funnel")
		bar.rotation.z = side * deg_to_rad(28.0)
	# Peg field: one MultiMesh for the shafts, one for the cream caps.
	pegs_parent = Node3D.new()
	pegs_parent.name = "Pegs"
	add_child(pegs_parent)
	var shaft := CylinderMesh.new()
	shaft.top_radius = PEG_RADIUS
	shaft.bottom_radius = PEG_RADIUS
	shaft.height = 0.18
	shaft.radial_segments = 10
	shaft.rings = 1
	var cap := SphereMesh.new()
	cap.radius = PEG_RADIUS * 1.25
	cap.height = PEG_RADIUS * 1.6
	cap.radial_segments = 10
	cap.rings = 4
	var count: int = 0
	for r: int in ROWS:
		count += peg_count(r)
	var shafts := _multimesh(shaft, count, gold, "PegShafts")
	var caps := _multimesh(cap, count, GreyboxKit.material(Palette.CREAM, 0.3, 0.4), "PegCaps")
	var i: int = 0
	for r: int in ROWS:
		for c: int in peg_count(r):
			var p: Vector2 = peg_pos(r, c)
			shafts.multimesh.set_instance_transform(i, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(p.x, p.y, -0.045)))
			caps.multimesh.set_instance_transform(i, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(p.x, p.y, 0.045)))
			i += 1
	# Slot buckets (coloured by payout), gold dividers, multiplier plates.
	var w: float = slot_w()
	for s: int in SLOTS:
		var mat := StandardMaterial3D.new()
		mat.roughness = 0.6
		_bucket_mats.append(mat)
		_buckets.append(_mesh(_box(Vector3(w - DIV_T, DIV_TOP - FLOOR_Y, 0.02)), Vector3(slot_x(s), (FLOOR_Y + DIV_TOP) * 0.5, -0.12), mat, "Bucket%d" % s))
		var l := _label("", 64, 0.0024, Palette.CREAM)
		l.position = Vector3(slot_x(s), FLOOR_Y - 0.17, 0.27)
		l.name = "SlotLabel%d" % s
		add_child(l)
		slot_labels.append(l)
	for s: int in SLOTS + 1:
		_mesh(_box(Vector3(DIV_T, DIV_TOP - FLOOR_Y, 0.26)), Vector3((s - SLOTS * 0.5) * w, (FLOOR_Y + DIV_TOP) * 0.5, -0.01), gold, "Divider")
	# Label plate along the tray front.
	_mesh(_box(Vector3(BOARD_W + 0.1, 0.28, 0.02)), Vector3(0, FLOOR_Y - 0.17, 0.255), GreyboxKit.material(Palette.CASINO_BLACK), "LabelPlate")
	for s: int in [0, SLOTS - 1]:
		var tag := _label("JACKPOT\nCHANCE", 30, 0.0016, Palette.VIP_GOLD)
		tag.position = Vector3(slot_x(s), DIV_TOP + 0.1, 0.2)
		tag.name = "JackpotTag%d" % s
		add_child(tag)
		jackpot_tags.append(tag)
	_flash_mesh = SphereMesh.new()
	_flash_mesh.radius = 0.07
	_flash_mesh.height = 0.14
	_flash_mesh.radial_segments = 8
	_flash_mesh.rings = 4
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.albedo_color = Color(1.0, 0.9, 0.55, 0.85)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.85, 0.6)
	lamp.light_energy = 1.2
	lamp.omni_range = 5.0
	lamp.position = Vector3(0, mid_y + 0.4, 2.2)
	lamp.shadow_enabled = false
	add_child(lamp)


## Shows `p_risk`'s multipliers on the buckets (and the jackpot tags on High).
func set_risk(p_risk: StringName) -> void:
	risk = p_risk
	if slot_labels.is_empty():
		return
	var mults: PackedFloat32Array = Registry.balance.plinko_multipliers(risk)
	var top: float = 1.0
	for m: float in mults:
		top = maxf(top, m)
	for s: int in SLOTS:
		var m: float = mults[s]
		slot_labels[s].text = mult_text(m)
		slot_labels[s].modulate = Palette.LOSS_RED if m < 1.0 else (Palette.VIP_GOLD if m >= top * 0.5 else Palette.CREAM)
		var col: Color = bucket_color(m, top)
		_bucket_mats[s].albedo_color = col
		_bucket_mats[s].emission_enabled = m >= top * 0.5
		_bucket_mats[s].emission = col * 0.35
	for t: Label3D in jackpot_tags:
		t.visible = risk == &"high"
	risk_sign.text = "%s RISK" % String(risk).to_upper()


## Drops a visual chip that lands in `p_slot`, touching down `seconds` from now; `p_risk` is the
## row it was bet on (its multiplier pops over the slot on landing). Client only.
func drop_chip(p_slot: int, drop_id: int, color: Color, seconds: float, p_risk: StringName = &"") -> PlinkoChip:
	if not Vfx.enabled():
		return null
	var rng := SeededRng.new(drop_id * 7919 + p_slot)
	var path: Array[float] = PlinkoSteering.path_to_slot(ROWS, SLOTS, p_slot, rng)
	var chip := PlinkoChip.new()
	chip.color = color
	chip.board = self
	var mults: PackedFloat32Array = Registry.balance.plinko_multipliers(p_risk if p_risk != &"" else risk)
	chip.mult = mults[clampi(p_slot, 0, mults.size() - 1)]
	add_child(chip)
	chip.play(PlinkoFlight.build(path, rng), seconds)
	return chip


## Chips still falling vanish (their drops were refunded for a minigame). Client only.
func reset_table() -> void:
	for c: Node in get_children():
		if c is PlinkoChip:
			c.queue_free()


## A peg the chip just struck lights up for a moment.
func flash_peg(row: int, col: int) -> void:
	if _flash_mesh == null or row < 0:
		return
	var p: Vector2 = peg_pos(row, col)
	var mi := MeshInstance3D.new()
	mi.mesh = _flash_mesh
	mi.material_override = _flash_mat
	mi.position = Vector3(p.x, p.y, 0.06)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var tw: Tween = mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * 0.2, 0.22).from(Vector3.ONE * 1.1)
	tw.tween_callback(mi.queue_free)


## The bucket a chip landed in pulses, its plate pops and the multiplier that chip actually won
## (its own risk row, which may differ from the one on the plates) floats up out of the slot.
func flash_slot(s: int, mult: float = -1.0) -> void:
	if s < 0 or s >= _buckets.size():
		return
	if mult >= 0.0:
		var pop := _label(mult_text(mult), 72, 0.0026, Palette.LOSS_RED if mult < 1.0 else Palette.VIP_GOLD)
		pop.name = "SlotPop"
		pop.no_depth_test = true
		pop.render_priority = 5
		pop.position = Vector3(slot_x(s), DIV_TOP + 0.05, 0.2)
		add_child(pop)
		var pt: Tween = pop.create_tween()
		pt.set_parallel(true)
		pt.tween_property(pop, "position:y", DIV_TOP + 0.5, 1.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		pt.tween_property(pop, "modulate:a", 0.0, 0.5).set_delay(0.9)
		pt.chain().tween_callback(pop.queue_free)
	var mat: StandardMaterial3D = _bucket_mats[s]
	var was: bool = mat.emission_enabled
	var col: Color = mat.albedo_color
	mat.emission_enabled = true
	var tw: Tween = create_tween()
	tw.tween_property(mat, "emission", col * 1.4, 0.08)
	tw.tween_property(mat, "emission", col * (0.35 if was else 0.0), 0.6)
	tw.tween_callback(func() -> void: mat.emission_enabled = was)
	var l: Label3D = slot_labels[s]
	var lt: Tween = l.create_tween()
	lt.tween_property(l, "scale", Vector3.ONE * 1.35, 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	lt.tween_property(l, "scale", Vector3.ONE, 0.35)


## Grows the money piles with the jackpot (`seed` = the jackpot's starting value).
func set_jackpot(amount: int, seed: int) -> void:
	if _money_piles.is_empty():
		for side: float in [-1.0, 1.0]:
			var pile: Node3D = PropModels.make(&"money_pile", 0.0, 1.0)
			pile.position = Vector3(side * (BOARD_W * 0.5 + 0.8), 0.0, 0.5)
			pile.rotation.y = side * 0.4
			pile.visible = false
			add_child(pile)
			_money_piles.append(pile)
	var ratio: float = float(amount) / float(maxi(seed, 1))
	for i: int in _money_piles.size():
		var from: float = 3.0 if i == 0 else 6.0
		_money_piles[i].visible = ratio >= from
		_money_piles[i].scale = Vector3.ONE * lerpf(0.8, 1.6, clampf((ratio - from) / (10.0 - from), 0.0, 1.0))


func _marquee_bulbs() -> void:
	var bulb := SphereMesh.new()
	bulb.radius = 0.035
	bulb.height = 0.07
	bulb.radial_segments = 8
	bulb.rings = 4
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Palette.CREAM
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.45)
	mat.emission_energy_multiplier = 1.6
	var n: int = 14
	var mm := _multimesh(bulb, n, mat, "MarqueeBulbs")
	var half: float = BOARD_W * 0.31 - 0.06
	for i: int in n:
		var x: float = lerpf(-half, half, i / float(n - 1))
		mm.multimesh.set_instance_transform(i, Transform3D(Basis(), Vector3(x, FLOOR_Y + BOARD_H + 0.76, 0.0)))


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _mesh(mesh: Mesh, pos: Vector3, mat: Material, node_name: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi


func _multimesh(mesh: Mesh, count: int, mat: Material, node_name: String) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = mat
	(pegs_parent if pegs_parent != null else self).add_child(mmi)
	return mmi


func _label(text: String, size: int, pixel: float, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = Vfx.font()
	l.font_size = size
	l.pixel_size = pixel
	l.modulate = color
	l.outline_modulate = Palette.CASINO_BLACK
	l.outline_size = maxi(size / 6, 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.double_sided = false
	return l
