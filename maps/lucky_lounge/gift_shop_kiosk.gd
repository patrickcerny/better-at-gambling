class_name GiftShopKiosk
extends Node3D
## The Gift Shop booth in the Lucky Lounge (east wall, Patrick 2026-11-15: "fully rework the item
## shop, it looks horrible"). A small hotel-lobby boutique in the casino's own materials
## (docs/ART_DIRECTION.md): a mahogany counter with velvet panels in brass frames and a black
## marble top, a mahogany back wall with lit shelves of souvenirs, a red-and-cream scalloped awning
## on turned brass posts, and a burgundy "GIFT SHOP" board with marquee bulbs on top. The ATM
## stands at the booth's right end under the same awning: the shop's cash machine (decor).
##
## The four items on sale this round stand on velvet display stands on the counter as their real
## 3D models (`ItemModels`), turning slowly, each with a price card in its rarity's colour
## (`set_offers`, fed by the match scene from the server's stock). With no stock (lobby, between
## rounds) the stands hold wrapped gift boxes.
##
## Local frame: the floor under the counter's centre is the origin, the booth faces +z (the room)
## and runs along x. LuckyLounge turns it so +z points west. The counter and the posts collide
## (the counter keeps its old name, "ShopCounter", and its old footprint); everything else is
## visual. The lamps, the bulbs' glow and the souvenirs on the shelves come in `dress` (client only,
## from LoungeDecor), so the headless server builds only plain boxes.

## Counter size (x along the booth, y up, z depth) and where its top surface is.
const COUNTER: Vector3 = Vector3(2.2, 1.1, 1.0)
const TOP_Y: float = 1.14
## The booth's ends along x (the ATM stands at the right end, x ≈ 1.75) and the wall behind it.
const LEFT: float = -1.2
const RIGHT: float = 2.25
const BACK_Z: float = -0.84
## Front of the awning: where the posts stand and the valance hangs.
const FRONT_Z: float = 0.82
const AWNING_FRONT_Y: float = 2.55
const AWNING_BACK_Y: float = 3.02
## Where the ATM stands (local) and how tall it is.
const ATM_POS: Vector3 = Vector3(1.75, 0.0, -0.3)
const ATM_HEIGHT: float = 1.9
## The display stands' x positions and how high the items float over them.
const STANDS: Array[float] = [-0.78, -0.26, 0.26, 0.78]
const STAND_Z: float = 0.02
const ITEM_Y: float = 1.5
const ITEM_SIZE: float = 0.4
## Turning speed of the goods (rad/s), each a bit out of phase.
const SPIN: float = 0.6
## Width of one awning stripe.
const STRIPE_W: float = 0.345
## Heights of the two back shelves (above the goods on the counter) and the souvenirs on them
## (dressing only, not for sale).
const SHELVES: Array[float] = [1.86, 2.4]
const SHELF_GOODS: Array[StringName] = [
	&"lucky_clover", &"golden_chip", &"sunglasses", &"black_cat",
	&"energy_drink", &"wild_card", &"beer", &"vip_pass",
]

var counter: Node3D
## One per stand: the slot the item model hangs in, its price card label and the card.
var _slots: Array[Node3D] = []
var _price_labels: Array[Label3D] = []
var _name_labels: Array[Label3D] = []
var _cards: Array[Node3D] = []
var _card_trims: Array[MeshInstance3D] = []
var _gift_boxes: Array[Node3D] = []
## The item ids shown now (so an unchanged stock is not rebuilt).
var _shown: Array[StringName] = []
var _time: float = 0.0
var _dressed: bool = false
var _bulb_mat: StandardMaterial3D
var _bulbs: MultiMeshInstance3D
## Pieces `dress` retextures: [node, kind].
var _skins: Array = []


func _init() -> void:
	name = "GiftShop"
	_build()
	set_process(false)


# --- Build -------------------------------------------------------------------------------------

func _build() -> void:
	var wood := Color("#4A2B1C")
	var dark_wood := Color("#2E1B12")
	var brass := Palette.WARM_GOLD
	# Counter: the collider keeps the old name and footprint (tests and the nav bake use it).
	counter = GreyboxKit.box(self, Vector3(COUNTER.x, 1.05, COUNTER.z), Vector3(0, 0.525, 0), wood, "ShopCounter")
	_skin(counter, &"wood")
	var plinth := GreyboxKit.box(self, Vector3(COUNTER.x - 0.04, 0.12, 0.06), Vector3(0, 0.06, COUNTER.z * 0.5 + 0.01), Palette.CASINO_BLACK, "ShopPlinth", false)
	_skin(plinth, &"marble")
	# Marble top with a brass nosing along the front.
	var top := GreyboxKit.box(self, Vector3(COUNTER.x + 0.1, 0.07, COUNTER.z + 0.12), Vector3(0, 1.085, 0.02), Palette.CASINO_BLACK, "ShopCounterTop", false)
	_skin(top, &"marble")
	_brass(Vector3(COUNTER.x + 0.12, 0.03, 0.03), Vector3(0, 1.065, COUNTER.z * 0.5 + 0.085))
	_brass(Vector3(COUNTER.x + 0.02, 0.025, 0.025), Vector3(0, 0.135, COUNTER.z * 0.5 + 0.03))
	# Three velvet panels in brass frames on the front.
	var fz: float = COUNTER.z * 0.5 + 0.012
	for i: int in 3:
		var x: float = (i - 1) * 0.72
		var panel := GreyboxKit.box(self, Vector3(0.6, 0.66, 0.02), Vector3(x, 0.6, fz), Palette.VIP_BURGUNDY, "ShopPanel", false)
		_skin(panel, &"velvet")
		for y: float in [0.27, 0.93]:
			_brass(Vector3(0.64, 0.025, 0.03), Vector3(x, y, fz + 0.006))
		for dx: float in [-0.31, 0.31]:
			_brass(Vector3(0.025, 0.68, 0.03), Vector3(x + dx, 0.6, fz + 0.006))
		# A gold coin medallion in the middle of each panel.
		var medal := ItemArt.cyl(self, 0.07, 0.07, 0.02, Vector3(x, 0.6, fz + 0.02), GreyboxKit.gold(), Vector3(90, 0, 0), 12, "ShopMedal")
		medal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Back wall: mahogany panelling from the floor to the awning, with two lit shelves behind the
	# counter, a cornice and a brass rail.
	var back := GreyboxKit.box(self, Vector3(RIGHT - LEFT, AWNING_BACK_Y, 0.08), Vector3((LEFT + RIGHT) * 0.5, AWNING_BACK_Y * 0.5, BACK_Z + 0.04), dark_wood, "ShopBackWall", false)
	_skin(back, &"wood")
	var mirror := GreyboxKit.box(self, Vector3(COUNTER.x - 0.1, 1.3, 0.02), Vector3(0, 2.2, BACK_Z + 0.09), Palette.VIP_BURGUNDY.darkened(0.25), "ShopBackPanel", false)
	_skin(mirror, &"velvet")
	for y: float in SHELVES:
		var shelf := GreyboxKit.box(self, Vector3(COUNTER.x - 0.1, 0.04, 0.26), Vector3(0, y, BACK_Z + 0.21), dark_wood, "ShopShelf", false)
		_skin(shelf, &"wood")
		_brass(Vector3(COUNTER.x - 0.08, 0.025, 0.02), Vector3(0, y + 0.005, BACK_Z + 0.345))
	for dx: float in [-1.0, 1.0]:
		var side := GreyboxKit.box(self, Vector3(0.08, 1.4, 0.3), Vector3(dx * (COUNTER.x * 0.5 - 0.01), 2.2, BACK_Z + 0.19), dark_wood, "ShopShelfSide", false)
		_skin(side, &"wood")
	_brass(Vector3(RIGHT - LEFT + 0.04, 0.05, 0.05), Vector3((LEFT + RIGHT) * 0.5, AWNING_BACK_Y - 0.03, BACK_Z + 0.1))
	_build_posts()
	_build_awning()
	_build_sign()
	_build_stands()
	# The ATM at the right end, its screen to the room: the shop's cash machine.
	var atm: Node3D = ItemModels.make_kiosk(ATM_HEIGHT)
	atm.name = "ShopAtm"
	atm.position = ATM_POS
	add_child(atm)
	var py: float = ATM_HEIGHT + 0.32
	var pz: float = BACK_Z + 0.1
	var plaque := GreyboxKit.box(self, Vector3(0.56, 0.18, 0.03), Vector3(ATM_POS.x, py, pz), Palette.VIP_BURGUNDY, "ShopAtmPlaque", false)
	_skin(plaque, &"velvet")
	_brass(Vector3(0.6, 0.02, 0.035), Vector3(ATM_POS.x, py - 0.09, pz))
	_brass(Vector3(0.6, 0.02, 0.035), Vector3(ATM_POS.x, py + 0.09, pz))
	_label("ShopAtmText", Vector3(ATM_POS.x, py, pz + 0.02), "CASH", 34, Palette.VIP_GOLD)


func _build_posts() -> void:
	# Turned brass posts at the front corners: a square marble foot, a slim column with two collars
	# and a ball finial under the awning. The column collides (so beans bump off it).
	for x: float in [LEFT + 0.06, RIGHT - 0.06]:
		var foot := GreyboxKit.box(self, Vector3(0.16, 0.12, 0.16), Vector3(x, 0.06, FRONT_Z - 0.06), Palette.CASINO_BLACK, "ShopPostFoot", false)
		_skin(foot, &"marble")
		var post: Node3D = GreyboxKit.cylinder(self, 0.035, AWNING_FRONT_Y - 0.12, Vector3(x, 0.12 + (AWNING_FRONT_Y - 0.12) * 0.5, FRONT_Z - 0.06), Palette.WARM_GOLD, "ShopPost", true, 0.85)
		_skin(post, &"brass")
		for y: float in [0.3, 1.13]:
			ItemArt.cyl(self, 0.055, 0.055, 0.04, Vector3(x, y, FRONT_Z - 0.06), GreyboxKit.gold(), Vector3.ZERO, 12, "ShopPostCollar")
		ItemArt.ball(self, Vector3(0.06, 0.06, 0.06), Vector3(x, AWNING_FRONT_Y - 0.02, FRONT_Z - 0.06), GreyboxKit.gold(), Vector3.ZERO, 10, "ShopFinial")
		# A side rail from the post back to the wall, under the awning's edge.
		var rail_len: float = FRONT_Z - 0.06 - BACK_Z
		_brass(Vector3(0.03, 0.03, rail_len), Vector3(x, AWNING_FRONT_Y - 0.06, BACK_Z + rail_len * 0.5))


func _build_awning() -> void:
	# Red-and-cream stripes sloping from the back wall down to the front, a scalloped valance along
	# the front edge, and a brass rod holding it.
	var run: float = FRONT_Z + 0.08 - BACK_Z
	var drop: float = AWNING_BACK_Y - AWNING_FRONT_Y
	var length: float = sqrt(run * run + drop * drop)
	var tilt: float = atan2(drop, run)
	var count: int = int(round((RIGHT - LEFT + 0.1) / STRIPE_W))
	var width: float = (RIGHT - LEFT + 0.1) / count
	var red := ItemArt.mat(Palette.CASINO_RED.darkened(0.08), 0.0, 0.85)
	var cream := ItemArt.mat(Palette.CREAM.darkened(0.05), 0.0, 0.85)
	for i: int in count:
		var x: float = LEFT - 0.05 + width * (i + 0.5)
		var m: StandardMaterial3D = red if i % 2 == 0 else cream
		var stripe := ItemArt.box(self, Vector3(width + 0.002, 0.025, length), Vector3(x, (AWNING_BACK_Y + AWNING_FRONT_Y) * 0.5, (BACK_Z + FRONT_Z + 0.08) * 0.5), m, Vector3(rad_to_deg(tilt), 0, 0), "ShopAwning")
		stripe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		# Valance: a tab with a rounded bottom (a flat disc half under the tab).
		var vz: float = FRONT_Z + 0.09
		ItemArt.box(self, Vector3(width, 0.14, 0.02), Vector3(x, AWNING_FRONT_Y - 0.08, vz), m, Vector3.ZERO, "ShopValance")
		ItemArt.cyl(self, width * 0.5, width * 0.5, 0.02, Vector3(x, AWNING_FRONT_Y - 0.15, vz), m, Vector3(90, 0, 0), 10, "ShopScallop")
	_brass(Vector3(RIGHT - LEFT + 0.16, 0.035, 0.035), Vector3((LEFT + RIGHT) * 0.5, AWNING_FRONT_Y, FRONT_Z + 0.11))
	for x: float in [LEFT - 0.08, RIGHT + 0.08]:
		ItemArt.ball(self, Vector3(0.035, 0.035, 0.035), Vector3(x, AWNING_FRONT_Y, FRONT_Z + 0.11), GreyboxKit.gold(), Vector3.ZERO, 8, "ShopRodEnd")


func _build_sign() -> void:
	# A burgundy board standing on the awning's front edge, framed in gold, with marquee bulbs top
	# and bottom: "GIFT SHOP" in VIP gold and a small line under it.
	var cx: float = (LEFT + RIGHT) * 0.5
	var w: float = 2.3
	var h: float = 0.62
	var cy: float = AWNING_FRONT_Y + 0.08 + h * 0.5
	var z: float = FRONT_Z + 0.04
	var board := GreyboxKit.box(self, Vector3(w, h, 0.06), Vector3(cx, cy, z), Palette.VIP_BURGUNDY, "ShopSign", false)
	_skin(board, &"velvet")
	for dy: float in [-1.0, 1.0]:
		_brass(Vector3(w + 0.1, 0.05, 0.08), Vector3(cx, cy + dy * (h * 0.5 + 0.02), z))
	for dx: float in [-1.0, 1.0]:
		_brass(Vector3(0.05, h + 0.1, 0.08), Vector3(cx + dx * (w * 0.5 + 0.03), cy, z))
	# Crest on top: a gold chip.
	var crest := ItemArt.cyl(self, 0.16, 0.16, 0.05, Vector3(cx, cy + h * 0.5 + 0.17, z), GreyboxKit.gold(), Vector3(90, 0, 0), 16, "ShopCrest")
	crest.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ItemArt.cyl(self, 0.11, 0.11, 0.055, Vector3(cx, cy + h * 0.5 + 0.17, z), ItemArt.mat(Palette.CASINO_RED, 0.0, 0.6), Vector3(90, 0, 0), 16, "ShopCrestInlay")
	var title: Label3D = _label("ShopTitle", Vector3(cx, cy + 0.07, z + 0.035), "GIFT SHOP", 92, Palette.VIP_GOLD)
	title.outline_modulate = Palette.CASINO_BLACK.lerp(Palette.VIP_BURGUNDY, 0.3)
	_label("ShopSubtitle", Vector3(cx, cy - 0.19, z + 0.035), "SOUVENIRS  ·  ONE PER ROUND", 30, Palette.CREAM)
	# Marquee bulbs: one MultiMesh (they share a glowing material, lit up in `dress`).
	_bulb_mat = ItemArt.mat(Palette.CREAM, 0.0, 0.4).duplicate()  # lit in `dress`: not the shared one
	var bulb := SphereMesh.new()
	bulb.radius = 0.028
	bulb.height = 0.056
	bulb.radial_segments = 8
	bulb.rings = 4
	var spots: Array[Vector3] = []
	var n: int = 15
	for i: int in n:
		var x: float = cx - w * 0.5 + 0.05 + (w - 0.1) * float(i) / float(n - 1)
		spots.append(Vector3(x, cy + h * 0.5 + 0.02, z + 0.05))
		spots.append(Vector3(x, cy - h * 0.5 - 0.02, z + 0.05))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = bulb
	mm.instance_count = spots.size()
	for i: int in spots.size():
		mm.set_instance_transform(i, Transform3D(Basis(), spots[i]))
	_bulbs = MultiMeshInstance3D.new()
	_bulbs.name = "ShopBulbs"
	_bulbs.multimesh = mm
	_bulbs.material_override = _bulb_mat
	_bulbs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_bulbs)


func _build_stands() -> void:
	# One stand per offer: a brass drum with a velvet cushion, the item turning above it, and a
	# tented price card in front (cream / blue / gold edge by rarity).
	var cushion := ItemArt.mat(Palette.FELT_GREEN.darkened(0.15), 0.0, 0.95)
	var card := ItemArt.mat(Palette.CASINO_BLACK.lightened(0.04), 0.0, 0.7)
	for i: int in STANDS.size():
		var x: float = STANDS[i]
		ItemArt.cyl(self, 0.12, 0.14, 0.07, Vector3(x, TOP_Y + 0.035, STAND_Z), GreyboxKit.gold(), Vector3.ZERO, 16, "ShopStand")
		ItemArt.cyl(self, 0.11, 0.11, 0.03, Vector3(x, TOP_Y + 0.085, STAND_Z), cushion, Vector3.ZERO, 16, "ShopCushion")
		var slot := Node3D.new()
		slot.name = "ShopSlot%d" % i
		slot.position = Vector3(x, ITEM_Y, STAND_Z)
		add_child(slot)
		_slots.append(slot)
		# A wrapped gift box for when nothing is on sale.
		var gift: Node3D = _gift_box(Vector3(x, TOP_Y + 0.1, STAND_Z), i)
		_gift_boxes.append(gift)
		# Price card, leaning back on the counter: name over price, its top edge in the rarity colour.
		var c := Node3D.new()
		c.name = "ShopCard%d" % i
		c.position = Vector3(x, TOP_Y + 0.07, 0.4)
		c.rotation.x = deg_to_rad(-20.0)
		c.visible = false
		add_child(c)
		_cards.append(c)
		ItemArt.box(c, Vector3(0.3, 0.15, 0.012), Vector3.ZERO, card, Vector3.ZERO, "Card")
		_card_trims.append(ItemArt.box(c, Vector3(0.31, 0.014, 0.018), Vector3(0, 0.075, 0), GreyboxKit.gold(), Vector3.ZERO, "Trim"))
		var price: Label3D = _label("Price", Vector3(0, -0.022, 0.008), "", 24, Palette.MONEY_GREEN)
		price.reparent(c, false)
		_price_labels.append(price)
		var item_name: Label3D = _label("Name", Vector3(0, 0.038, 0.008), "", 11, Palette.CREAM)
		item_name.outline_size = 3
		item_name.reparent(c, false)
		_name_labels.append(item_name)


func _gift_box(pos: Vector3, i: int) -> Node3D:
	var root := Node3D.new()
	root.name = "ShopGift%d" % i
	root.position = pos
	root.rotation.y = 0.35 * (i - 1.5)
	add_child(root)
	var paper: Array[Color] = [Palette.CASINO_RED, Palette.CREAM, Palette.FELT_GREEN, Palette.VIP_BURGUNDY]
	var s: float = 0.2 - 0.02 * (i % 2)
	ItemArt.box(root, Vector3(s, s * 0.8, s), Vector3(0, s * 0.4, 0), ItemArt.mat(paper[i % paper.size()], 0.0, 0.7), Vector3.ZERO, "Paper")
	var ribbon: StandardMaterial3D = GreyboxKit.gold()
	ItemArt.box(root, Vector3(s + 0.006, s * 0.8 + 0.006, 0.03), Vector3(0, s * 0.4, 0), ribbon, Vector3.ZERO, "Ribbon")
	ItemArt.box(root, Vector3(0.03, s * 0.8 + 0.006, s + 0.006), Vector3(0, s * 0.4, 0), ribbon, Vector3.ZERO, "Ribbon")
	for side: float in [-1.0, 1.0]:
		ItemArt.ball(root, Vector3(0.045, 0.03, 0.025), Vector3(side * 0.035, s * 0.8 + 0.02, 0), ribbon, Vector3(0, 0, side * 30.0), 8, "Bow")
	return root


# --- Live stock --------------------------------------------------------------------------------

## Shows this round's stock ([{item, price, rarity}], the server's `GiftShop.wire()` offers) on the
## stands. An empty list puts the gift boxes back.
func set_offers(offers: Array) -> void:
	var ids: Array[StringName] = []
	for o: Variant in offers:
		if o is Dictionary:
			ids.append(StringName((o as Dictionary).get("item", &"")))
	var same: bool = ids == _shown
	_shown = ids
	for i: int in _slots.size():
		var has: bool = i < offers.size() and offers[i] is Dictionary
		_gift_boxes[i].visible = not has
		_cards[i].visible = has
		if not has:
			for c: Node in _slots[i].get_children():
				c.queue_free()
			continue
		var o: Dictionary = offers[i]
		var rarity: int = clampi(int(o.get("rarity", 0)), 0, RewardPanel.RARITY_COLORS.size() - 1)
		_price_labels[i].text = "$%s" % Hud._thousands(int(o.get("price", 0)))
		_name_labels[i].text = RewardPanel.item_name(ids[i]).to_upper()
		_name_labels[i].modulate = RewardPanel.RARITY_COLORS[rarity]
		_card_trims[i].material_override = ItemArt.mat(RewardPanel.RARITY_COLORS[rarity], 0.6, 0.35)
		if same and _slots[i].get_child_count() > 0:
			continue
		for c: Node in _slots[i].get_children():
			c.queue_free()
		var model: Node3D = ItemModels.make(ids[i], ITEM_SIZE)
		_slots[i].add_child(model)
	set_process(_dressed and not ids.is_empty())


func _process(delta: float) -> void:
	_time += delta
	for i: int in _slots.size():
		var s: Node3D = _slots[i]
		s.rotation.y = _time * SPIN + i * 1.3
		s.position.y = ITEM_Y + sin(_time * 1.6 + i) * 0.025


# --- Client dressing ---------------------------------------------------------------------------

## Client-only finish (LoungeDecor): the room's textured wood, marble, velvet and brass on the
## pieces, the marquee bulbs lit, a warm spot light under the awning on the goods, and souvenirs on
## the back shelves.
func dress(wood: Material, marble: Material, velvet: Material, brass: Material) -> void:
	_dressed = true
	var by_kind: Dictionary = {&"wood": wood, &"marble": marble, &"velvet": velvet, &"brass": brass}
	for pair: Array in _skins:
		var mi: MeshInstance3D = (pair[0] as Node).get_node_or_null(^"Mesh") as MeshInstance3D
		if mi != null and by_kind.get(pair[1]) != null:
			mi.material_override = by_kind[pair[1]]
	_bulb_mat.emission_enabled = true
	_bulb_mat.emission = LoungeDecor.BULB_COLOR
	_bulb_mat.emission_energy_multiplier = 2.2
	# Warm light on the counter from under the awning, and a soft fill on the shelves.
	var spot := SpotLight3D.new()
	spot.name = "ShopSpot"
	spot.light_color = Color(1.0, 0.82, 0.58)
	spot.light_energy = 3.0
	spot.spot_range = 3.2
	spot.spot_angle = 52.0
	spot.spot_attenuation = 0.8
	spot.shadow_enabled = false
	spot.position = Vector3(0, AWNING_FRONT_Y - 0.05, 0.55)
	spot.rotation = Vector3(-PI * 0.5 + 0.35, 0, 0)
	add_child(spot)
	var fill := OmniLight3D.new()
	fill.name = "ShopShelfGlow"
	fill.light_color = Color(1.0, 0.8, 0.55)
	fill.light_energy = 0.7
	fill.omni_range = 1.6
	fill.shadow_enabled = false
	fill.position = Vector3(0, 2.15, BACK_Z + 0.55)
	add_child(fill)
	var sign_light := OmniLight3D.new()
	sign_light.name = "ShopSignGlow"
	sign_light.light_color = LoungeDecor.BULB_COLOR
	sign_light.light_energy = 0.8
	sign_light.omni_range = 2.2
	sign_light.shadow_enabled = false
	sign_light.position = Vector3((LEFT + RIGHT) * 0.5, AWNING_FRONT_Y + 0.4, FRONT_Z + 0.6)
	add_child(sign_light)
	# Souvenirs: four on each shelf, plus a gift box at each end of the lower one.
	for i: int in SHELF_GOODS.size():
		var row: int = i / 4
		var col: int = i % 4
		var m: Node3D = ItemModels.make(SHELF_GOODS[i], 0.26)
		m.position = Vector3(-0.66 + col * 0.44, SHELVES[row] + 0.15, BACK_Z + 0.2)
		m.rotation.y = 0.4 * (col - 1.5)
		add_child(m)
	if not _shown.is_empty():
		set_process(true)


func _skin(node: Node3D, kind: StringName) -> void:
	_skins.append([node, kind])


func _brass(size: Vector3, pos: Vector3) -> void:
	var b: MeshInstance3D = ItemArt.box(self, size, pos, GreyboxKit.gold(), Vector3.ZERO, "ShopBrass")
	b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _label(n: String, pos: Vector3, text: String, size: int, color: Color) -> Label3D:
	var l := Label3D.new()
	l.name = n
	l.text = text
	l.font_size = size
	l.pixel_size = 0.004
	l.modulate = color
	l.outline_modulate = Palette.CASINO_BLACK
	l.outline_size = 8
	l.position = pos
	if Vfx.enabled():
		l.font = Vfx.font()
	add_child(l)
	return l
