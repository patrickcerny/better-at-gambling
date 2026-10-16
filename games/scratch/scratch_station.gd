class_name ScratchStation
extends StationBase
## Scratch-card kiosk: a dark-wood counter with brass trim and panelled front, a card dispenser on
## the counter (three card faces behind glass, one per price, and the slot the cards come out of),
## a brass desk lamp, an attendant bean behind the counter and a "SCRATCH CARDS" board on brass
## posts above them. One stool in front. Local +z faces the player.
##
## The card itself is scratched in the station panel (`ScratchUi`); here a bought card slides out
## of the dispenser onto the counter mat and lies there until it has paid.

## Counter body (the collision footprint).
const COUNTER_SIZE: Vector3 = Vector3(1.6, 1.02, 0.62)
## Height of the counter's top surface.
const TOP_Y: float = 1.06
## Front face of the counter.
const FRONT_Z: float = 0.31
## Dispenser on the counter (centre of its base) and its size.
const DISPENSER_POS: Vector3 = Vector3(-0.38, TOP_Y, -0.06)
const DISPENSER_SIZE: Vector3 = Vector3(0.66, 0.46, 0.3)
## Where a bought card lies on the counter mat (in front of the player).
const CARD_SPOT: Vector3 = Vector3(0.18, TOP_Y + 0.006, 0.1)
const CARD_SIZE: Vector3 = Vector3(0.15, 0.004, 0.21)
## Attendant behind the counter (feet on the floor) and the board's posts behind them.
const ATTENDANT_POS: Vector3 = Vector3(0.3, 0.0, -0.74)
const BOARD_Z: float = -1.22
const BOARD_Y: float = 2.45
## The three cards, cheapest first: name and colour, as printed on the card in the panel too.
const TIER_NAMES: Array[String] = ["LUCKY CHERRY", "RED HOT 7s", "DIAMOND DELUXE"]
const TIER_COLORS: Array[Color] = [Color("#275E49"), Color("#C83D3D"), Color("#681F2C")]
## Seated view: behind the stool, the attendant and the dispenser framed above the panel.
const CAMERA_POS: Vector3 = Vector3(0.0, 1.62, 1.8)
const CAMERA_PITCH: float = -12.0
## Seconds the card takes to slide out of the dispenser onto the mat.
const DISPENSE_TIME: float = 0.45

## The card on the counter mat (client only; null on a headless server).
var card_mesh: MeshInstance3D
var attendant: AvatarVisuals
var _card_tween: Tween
## Tier of the card on the mat (−1 = none).
var shown_tier: int = -1


func _build_visuals() -> void:
	game_id = &"scratch"
	seat_count = 1
	interact_radius = 1.8
	hot_center = Vector3(0, 0, 0.3)
	var wood: Color = Color("#3A2A1E")
	GreyboxKit.box(self, COUNTER_SIZE, Vector3(0, COUNTER_SIZE.y * 0.5, 0), wood, "Counter")
	# The attendant's spot is solid (a body behind the counter, not a gap to walk through).
	var body := StaticBody3D.new()
	body.name = "AttendantBody"
	body.add_to_group(&"navsource")
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.36
	cyl.height = 1.6
	cs.shape = cyl
	cs.position = Vector3(0, 0.8, 0)
	body.add_child(cs)
	body.position = ATTENDANT_POS
	add_child(body)
	for side: int in [-1, 1]:  # the board's brass posts, solid
		GreyboxKit.cylinder(self, 0.035, BOARD_Y + 0.3, Vector3(side * 0.72, (BOARD_Y + 0.3) * 0.5, BOARD_Z), Palette.WARM_GOLD, "BoardPost", true, 0.8)
	_stool(Vector3(0, 0, 0.88))
	_add_seat(Vector3(0, 0.5, 0.88), 0.0)  # faces the counter (−z)
	camera_anchor = Node3D.new()
	camera_anchor.name = "CameraAnchor"
	camera_anchor.position = CAMERA_POS
	camera_anchor.rotation.x = deg_to_rad(CAMERA_PITCH)
	add_child(camera_anchor)
	if not Vfx.enabled():
		return
	var brass: StandardMaterial3D = GreyboxKit.material(Palette.WARM_GOLD, 0.8, 0.35)
	_round_rug(2.6)
	_build_counter(wood, brass)
	_build_dispenser(brass)
	_build_lamp(brass)
	_build_board(brass)
	_build_attendant()
	card_mesh = _part(CARD_SIZE, CARD_SPOT, GreyboxKit.material(Palette.CREAM), "Card")
	card_mesh.visible = false


## Brass top rail and kick strip, a leather writing inset on the top, two framed front panels.
func _build_counter(wood: Color, brass: Material) -> void:
	var w: float = COUNTER_SIZE.x
	_part(Vector3(w + 0.08, 0.04, COUNTER_SIZE.z + 0.08), Vector3(0, TOP_Y - 0.02, 0), GreyboxKit.material(Palette.WARM_CHARCOAL, 0.0, 0.5), "Top")
	_part(Vector3(w + 0.1, 0.025, 0.03), Vector3(0, TOP_Y - 0.03, FRONT_Z + 0.045), brass, "TopRail")
	_part(Vector3(w + 0.02, 0.08, 0.02), Vector3(0, 0.04, FRONT_Z + 0.01), brass, "Kick")
	_part(Vector3(0.62, 0.006, 0.36), Vector3(0.18, TOP_Y + 0.003, 0.08), GreyboxKit.material(Palette.FELT_GREEN.darkened(0.35)), "Mat")
	var panel_mat: StandardMaterial3D = GreyboxKit.material(wood.lightened(0.18), 0.0, 0.7)
	for side: int in [-1, 1]:
		var cx: float = side * 0.39
		_part(Vector3(0.66, 0.66, 0.012), Vector3(cx, 0.55, FRONT_Z + 0.006), brass, "PanelFrame")
		_part(Vector3(0.6, 0.6, 0.012), Vector3(cx, 0.55, FRONT_Z + 0.012), panel_mat, "Panel")
	var badge := _label("$", 160, 0.0018, Palette.WARM_GOLD)
	badge.position = Vector3(0, 0.56, FRONT_Z + 0.02)
	add_child(badge)
	for side: int in [-1, 1]:  # brass corner strips
		_part(Vector3(0.03, COUNTER_SIZE.y, 0.03), Vector3(side * (w * 0.5 + 0.005), COUNTER_SIZE.y * 0.5, FRONT_Z + 0.005), brass, "CornerTrim")


## The dispenser: a wood box with a brass frame, three card faces behind glass (the three prices)
## and the brass slot at the bottom front where a bought card comes out.
func _build_dispenser(brass: Material) -> void:
	var d: Vector3 = DISPENSER_SIZE
	var base: Vector3 = DISPENSER_POS
	_part(d, base + Vector3(0, d.y * 0.5, 0), GreyboxKit.material(Color("#2C1F16"), 0.0, 0.6), "Dispenser")
	_part(Vector3(d.x + 0.03, 0.03, d.z + 0.03), base + Vector3(0, d.y + 0.015, 0), brass, "DispenserCap")
	_part(Vector3(d.x + 0.03, 0.03, d.z + 0.03), base + Vector3(0, 0.015, 0), brass, "DispenserFoot")
	var face_z: float = base.z + d.z * 0.5
	_part(Vector3(d.x - 0.04, d.y - 0.12, 0.01), base + Vector3(0, d.y * 0.56, d.z * 0.5 + 0.004), GreyboxKit.material(Palette.CASINO_BLACK), "Window")
	for i: int in 3:
		var x: float = base.x + (i - 1) * 0.2
		var face: MeshInstance3D = _part(Vector3(0.15, 0.21, 0.006), Vector3(x, base.y + d.y * 0.58, face_z + 0.01), GreyboxKit.material(TIER_COLORS[i]), "CardFace%d" % i)
		face.rotation.x = deg_to_rad(-4.0)
		_part(Vector3(0.11, 0.1, 0.004), Vector3(x, base.y + d.y * 0.55, face_z + 0.015), GreyboxKit.material(ScratchCardView.FOIL_B, 0.35, 0.4), "Foil%d" % i)
		var price := _label("$%d" % Registry.balance.scratch_prices[i], 64, 0.0016, Palette.VIP_GOLD)
		price.position = Vector3(x, base.y + d.y * 0.58 + 0.08, face_z + 0.02)
		add_child(price)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.9, 0.85, 0.7, 0.12)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.1
	glass.metallic = 0.3
	_part(Vector3(d.x - 0.04, d.y - 0.12, 0.006), base + Vector3(0, d.y * 0.56, d.z * 0.5 + 0.03), glass, "Glass")
	_part(Vector3(0.24, 0.03, 0.04), base + Vector3(0.12, 0.06, d.z * 0.5 + 0.02), brass, "Slot")
	_part(Vector3(0.18, 0.008, 0.02), base + Vector3(0.12, 0.06, d.z * 0.5 + 0.041), GreyboxKit.material(Palette.CASINO_BLACK), "SlotMouth")


## A small brass desk lamp on the right end of the counter, its bulb glowing warm.
func _build_lamp(brass: Material) -> void:
	var x: float = 0.62
	var z: float = -0.14
	_part_mesh(_rod(0.07, 0.02), Vector3(x, TOP_Y + 0.01, z), brass, "LampFoot")
	_part_mesh(_rod(0.012, 0.32), Vector3(x, TOP_Y + 0.17, z), brass, "LampStem")
	var shade := CylinderMesh.new()
	shade.top_radius = 0.05
	shade.bottom_radius = 0.1
	shade.height = 0.09
	shade.radial_segments = 14
	_part_mesh(shade, Vector3(x, TOP_Y + 0.34, z), GreyboxKit.material(Palette.FELT_GREEN, 0.0, 0.5), "LampShade")
	var bulb := SphereMesh.new()
	bulb.radius = 0.03
	bulb.height = 0.06
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Palette.CREAM
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.45)
	mat.emission_energy_multiplier = 1.6
	_part_mesh(bulb, Vector3(x, TOP_Y + 0.29, z), mat, "LampBulb")
	var light := OmniLight3D.new()
	light.name = "LampLight"
	light.light_color = Color(1.0, 0.82, 0.55)
	light.light_energy = 0.8
	light.omni_range = 1.6
	light.position = Vector3(x, TOP_Y + 0.25, z)
	add_child(light)


## The board above the attendant: a dark-wood frame with a cream face, "SCRATCH CARDS" in casino
## red and "INSTANT WINNERS" in gold.
func _build_board(brass: Material) -> void:
	var c := Vector3(0, BOARD_Y, BOARD_Z)
	_part(Vector3(1.7, 0.62, 0.06), c, GreyboxKit.material(Color("#2C1F16")), "Board")
	_part(Vector3(1.58, 0.5, 0.02), c + Vector3(0, 0, 0.035), GreyboxKit.material(Palette.CREAM), "BoardFace")
	_part(Vector3(1.74, 0.03, 0.07), c + Vector3(0, 0.325, 0), brass, "BoardTrim")
	_part(Vector3(1.74, 0.03, 0.07), c + Vector3(0, -0.325, 0), brass, "BoardTrim")
	var title := _label("SCRATCH CARDS", 120, 0.0019, Palette.CASINO_RED)
	title.position = c + Vector3(0, 0.07, 0.05)
	title.outline_size = 0
	add_child(title)
	var sub := _label("— INSTANT WINNERS —", 56, 0.0016, Palette.WARM_GOLD.darkened(0.25))
	sub.position = c + Vector3(0, -0.15, 0.05)
	add_child(sub)


## The attendant: a bean in a green waistcoat and gold bow tie, standing behind the counter.
func _build_attendant() -> void:
	attendant = AvatarVisuals.new()
	attendant.name = "Attendant"
	attendant.position = ATTENDANT_POS
	attendant.rotation.y = PI  # the bean's front is −z: turn it to the customer
	add_child(attendant)
	attendant.set_color(Color("#E9C9A0"))
	GreyboxKit.box(attendant.body, Vector3(0.3, 0.22, 0.05), Vector3(0, -0.4, -0.4), Palette.FELT_GREEN, "Vest", false)
	GreyboxKit.box(attendant.body, Vector3(0.11, 0.08, 0.05), Vector3(-0.065, -0.2, -0.43), Palette.WARM_GOLD, "BowL", false)
	GreyboxKit.box(attendant.body, Vector3(0.11, 0.08, 0.05), Vector3(0.065, -0.2, -0.43), Palette.WARM_GOLD, "BowR", false)


## Prompt at the counter.
func prompt_text(min_bet: int) -> String:
	if out_of_order_left > 0.0:
		return "OUT OF ORDER (%ds)" % ceili(out_of_order_left)
	return "%s Buy a scratch card — from $%d" % [InputGlyphs.hint(&"interact"), min_bet]


## A card was bought: it slides out of the dispenser's slot onto the mat (card sound for the
## buyer at full volume, from the kiosk for everyone else).
func dispense(tier: int, own: bool = false) -> void:
	if card_mesh == null:
		return
	if own:
		Audio.play(&"card_deal", &"SFX", -4.0)
	else:
		Audio.play_at(&"card_deal", self, -6.0)
	_show_card(tier)
	if _card_tween != null and _card_tween.is_valid():
		_card_tween.kill()
	var mouth: Vector3 = DISPENSER_POS + Vector3(0.12, 0.06, DISPENSER_SIZE.z * 0.5)
	card_mesh.position = mouth
	card_mesh.rotation = Vector3(deg_to_rad(-70.0), 0, 0)
	if not is_inside_tree():
		card_mesh.position = CARD_SPOT
		card_mesh.rotation = Vector3.ZERO
		return
	_card_tween = create_tween().set_parallel()
	_card_tween.tween_property(card_mesh, "position", CARD_SPOT, DISPENSE_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_card_tween.tween_property(card_mesh, "rotation", Vector3.ZERO, DISPENSE_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Mirrors the server state: the card lies on the mat while one is open.
func show_state(pub: Dictionary) -> void:
	var c: Array = pub.get("card", [])
	if c.is_empty():
		reset_table()
	elif shown_tier < 0:
		_show_card(int(pub.get("tier", 0)))


## The card has paid or was refunded: it is gone from the counter.
func reset_table() -> void:
	shown_tier = -1
	if card_mesh != null:
		if _card_tween != null and _card_tween.is_valid():
			_card_tween.kill()
		card_mesh.visible = false


func _show_card(tier: int) -> void:
	shown_tier = clampi(tier, 0, TIER_COLORS.size() - 1)
	if card_mesh == null:
		return
	card_mesh.material_override = GreyboxKit.material(TIER_COLORS[shown_tier])
	card_mesh.position = CARD_SPOT
	card_mesh.rotation = Vector3.ZERO
	card_mesh.visible = true


## Visual-only box (the counter body carries the collision).
func _part(size: Vector3, pos: Vector3, mat: Material, node_name: String) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _part_mesh(b, pos, mat, node_name)


func _part_mesh(mesh: Mesh, pos: Vector3, mat: Material, node_name: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi


func _rod(radius: float, length: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = length
	c.radial_segments = 12
	return c


func _label(text: String, size: int, pixel: float, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = Vfx.font()
	l.font_size = size
	l.pixel_size = pixel
	l.modulate = color
	l.outline_size = 0
	return l
