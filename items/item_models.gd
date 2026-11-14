class_name ItemModels
extends RefCounted
## The 3D model of each item: what the bean holds in its hand, what pops up when someone uses an
## item and what flies at a target. Wiring a real model is one line in `MODELS` (item → model file)
## plus, if it needs it, one line in `SIZES` (longest side in metres) and `GRIPS` (how it sits in
## the hand). Items with no line get `DEFAULT_MODEL` (Patrick's coin placeholder). Props that
## PropModels already knows (PropModels.ITEM_PROPS) are used from there.
## `make` returns a model centred on its own origin, so the hand holds it by the middle unless a
## grip moves it.

const DEFAULT_MODEL: String = "res://assets/polypizza/coin_placeholder.glb"
const MODELS: Dictionary = {
	&"baseball_bat": "res://assets/polypizza/bat.glb",
	&"russian_roulette": "res://assets/polypizza/revolver.glb",
	&"beer": "res://assets/polypizza/beer_full.glb",
}
## The idle motion of model-file items (hand-built ones animate in `ItemArt`):
## [ItemIdle.Kind, amount, speed, axis].
const DEFAULT_SWAY: Array = [ItemIdle.Kind.SWING, 0.08, 1.6, Vector3.FORWARD]
const SWAYS: Dictionary = {
	&"baseball_bat": [ItemIdle.Kind.SWING, 0.06, 1.2, Vector3.RIGHT],
	&"russian_roulette": [ItemIdle.Kind.SWING, 0.1, 1.4, Vector3.UP],
	&"beer": [ItemIdle.Kind.SWING, 0.1, 1.5, Vector3.FORWARD],
	&"empty_bottle": [ItemIdle.Kind.SWING, 0.12, 1.5, Vector3.FORWARD],
}
## Longest side of the model in the hand, metres (DEFAULT_SIZE otherwise).
const DEFAULT_SIZE: float = 0.3
const SIZES: Dictionary = {
	&"baseball_bat": 0.95,
	&"dog_collar": 0.42,
	&"russian_roulette": 0.5,
	&"scratch_ticket": 0.36,
	&"beer": 0.34,
	&"empty_bottle": 0.32,
	&"bad_luck_monkey": 0.46, &"banana_peel": 0.38, &"black_cat": 0.46, &"bodyguard": 0.4,
	&"bouncer": 0.62, &"boxing_glove": 0.55, &"bribe": 0.4, &"credit_card": 0.36,
	&"double_down": 0.38, &"energy_drink": 0.36, &"fake_cash": 0.4, &"get_out_of_jail_free": 0.46,
	&"golden_chip": 0.3, &"grease": 0.4, &"hot_hands": 0.46, &"jackpot_magnet": 0.42,
	&"loaded_reels": 0.42, &"lucky_clover": 0.42, &"mirror": 0.5, &"out_of_order": 0.52,
	&"pickpocket": 0.5, &"robin_hood": 0.8, &"rock_paper_scissors": 0.52, &"scissors": 0.42,
	&"sunglasses": 0.38, &"vip_pass": 0.48, &"wild_card": 0.4,
}
## How a model sits in the hand, in upright space (y up, -z forward): [offset, rotation degrees].
## bat.glb has its barrel (thick end) at -y, so the bat is turned end over end (z ~180) to put the
## knob in the fist and the barrel up and forward.
const DEFAULT_GRIP: Array = [Vector3(0.0, 0.16, -0.2), Vector3.ZERO]
const GRIPS: Dictionary = {
	&"baseball_bat": [Vector3(0.0, 0.38, -0.12), Vector3(-25, 0, 160)],
	&"russian_roulette": [Vector3(0.0, 0.14, -0.12), Vector3(0, 180, 80)],
}
## In the hand and in first person only, scaled up around the fist on top of `SIZES` (the grip
## offset scales with it, so the knob stays in the fist). Patrick: the bat looked thin and small
## in hand.
const HAND_SCALE: Dictionary = {
	&"baseball_bat": 1.35,
}
## The arm pose while holding an item (`AvatarVisuals.hold_right_arm`: pitch, splay, roll): the
## forearm out in front, a bit below level, so the item is shown off instead of dangling at the hip.
const HOLD_ARM: Vector3 = Vector3(-0.55, -0.3, 0.0)
## Items that keep the arm hanging at rest instead (the bat rests along the arm, Patrick's pose).
const ARM_AT_REST: Array[StringName] = [&"baseball_bat"]
## AvatarVisuals.ARM_REST turned back (the hand hangs at -1.3 rad about x).
const HAND_UPRIGHT: float = 1.3

## Model-space bounds per file, measured once.
static var _bounds: Dictionary = {}


## The model file for an item (DEFAULT_MODEL when it has none of its own).
static func path_for(item: StringName) -> String:
	if MODELS.has(item):
		return str(MODELS[item])
	var prop: StringName = PropModels.ITEM_PROPS.get(item, &"")
	if prop != &"" and PropModels.PATHS.has(prop):
		return str(PropModels.PATHS[prop])
	return DEFAULT_MODEL


## True when the item has a model of its own (not the coin placeholder).
static func has_own(item: StringName) -> bool:
	return path_for(item) != DEFAULT_MODEL or (not MODELS.has(item) and ItemArt.has(item))


static func size_for(item: StringName) -> float:
	return float(SIZES.get(item, DEFAULT_SIZE))


## Extra uniform scale in the hand / first person (`HAND_SCALE`, 1 otherwise).
static func hand_scale(item: StringName) -> float:
	return float(HAND_SCALE.get(item, 1.0))


## A new instance of `item`'s model, its longest side scaled to `size` (the item's hand size when
## 0), centred on the origin. The holder node is named after the item.
static func make(item: StringName, size: float = 0.0) -> Node3D:
	var holder := Node3D.new()
	holder.name = "Item_" + String(item).to_pascal_case()
	holder.set_meta(&"item", item)
	var path: String = path_for(item)
	var model: Node3D = null
	var key: String = path
	if not MODELS.has(item) and ItemArt.has(item):
		model = ItemArt.build(item)  # hand-built and animated (ItemArt)
		key = "art:" + String(item)
	else:
		var ps: PackedScene = load(path) as PackedScene if ResourceLoader.exists(path) else null
		if ps == null:
			return holder
		model = ps.instantiate()
	if not _bounds.has(key):
		_bounds[key] = _measure(model)
	var b: AABB = _bounds[key]
	var longest: float = maxf(maxf(b.size.x, b.size.y), maxf(b.size.z, 0.0001))
	var s: float = (size if size > 0.0 else size_for(item)) / longest
	model.scale = model.scale * s
	model.position = -b.get_center() * s
	holder.set_meta(&"extent", b.size * s)
	for n: Node in model.find_children("*", "GeometryInstance3D", true, false):
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if key == path and path != DEFAULT_MODEL:
		# Model files have no animation of their own: they sway a little in the hand (`SWAYS`).
		var sway := Node3D.new()
		sway.name = "Sway"
		holder.add_child(sway)
		sway.add_child(model)
		var idle := ItemIdle.new()
		var sw: Array = SWAYS.get(item, DEFAULT_SWAY)
		idle.add(sway, sw[0], sw[1], sw[2], sw[3])
		holder.add_child(idle)
		return holder
	holder.add_child(model)
	return holder


## Hand-built items (`ItemArt`) without a line in `GRIPS`: they stand on top of the fist, a little
## in front of it, or hang from it by their string or strap (`HANGING`).
const HANGING: Array[StringName] = [&"vip_pass", &"out_of_order", &"get_out_of_jail_free", &"dog_collar", &"pickpocket"]
const FIST: float = 0.08
## Hand-built items turned in the hand (degrees), so the side worth seeing faces the others.
const ART_TURN: Dictionary = {&"robin_hood": Vector3(0, -90, 0)}
## Hand-built items held by a handle or stem: how high their centre sits above the fist, as a share
## of their height (the rest stand on the fist).
const ART_LIFT: Dictionary = {
	&"bouncer": 0.12, &"boxing_glove": 0.3, &"mirror": 0.3, &"lucky_clover": 0.3, &"robin_hood": 0.0,
}


static func art_grip(item: StringName, m: Node3D) -> Array:
	var ext: Vector3 = m.get_meta(&"extent", Vector3.ONE * size_for(item))
	if item in HANGING:
		return [Vector3(0.0, -ext.y * 0.5 + FIST * 0.6, -0.1), ART_TURN.get(item, Vector3.ZERO)]
	var up: float = ext.y * float(ART_LIFT[item]) if ART_LIFT.has(item) else ext.y * 0.5 + FIST
	return [Vector3(0.0, up, -0.12), ART_TURN.get(item, Vector3.ZERO)]


## How the right arm holds `item` (`AvatarVisuals.hold_right_arm`; Vector3.INF = hanging at rest).
static func arm_pose(item: StringName) -> Vector3:
	return Vector3.INF if item in ARM_AT_REST else HOLD_ARM


## The model posed for a hand: `make` plus the item's grip, inside a "Held" node that turns the
## bean's hand space (the arm points down its -z) back to upright, so grips read as y up, -z
## forward while the arm hangs at rest.
static func make_held(item: StringName) -> Node3D:
	var held := Node3D.new()
	held.name = "Held"
	held.set_meta(&"item", item)
	var pose: Vector3 = arm_pose(item)
	if pose == Vector3.INF:
		held.rotation.x = HAND_UPRIGHT
	else:
		# The right arm's basis is Rz(-splay) * Rx(pitch) (`AvatarVisuals._set_arm`); undo it.
		held.rotation = Vector3(-pose.x, 0.0, pose.y)
	var m: Node3D = make(item)
	var grip: Array = GRIPS.get(item, DEFAULT_GRIP) if GRIPS.has(item) or not ItemArt.has(item) else art_grip(item, m)
	var k: float = hand_scale(item)
	m.position = (grip[0] as Vector3) * k
	m.rotation_degrees = grip[1]
	m.scale = Vector3.ONE * k
	held.add_child(m)
	return held


## Where a held item goes on an avatar's visuals: a node named "HandR" if the model has one, else
## the bean's right hand ("ArmR/Hand"), else `null` (then the caller uses the root with
## `ROOT_HAND_OFFSET`).
const ROOT_HAND_OFFSET: Vector3 = Vector3(0.5, 0.85, -0.25)


static func hand_node(visuals: Node) -> Node3D:
	if visuals == null:
		return null
	# The bean exposes its right-hand slot.
	if visuals.has_method("hand_node"):
		var slot: Node3D = visuals.call("hand_node") as Node3D
		if slot != null:
			return slot
	var n: Node = visuals.find_child("HandR", true, false)
	if n == null:
		var arm: Node = visuals.find_child("ArmR", true, false)
		n = arm.get_node_or_null(^"Hand") if arm != null else null
	return n as Node3D


## Puts `model` (from `make_held`) into the avatar's right hand; returns the parent used.
static func attach_to_hand(visuals: Node3D, model: Node3D) -> Node3D:
	var hand: Node3D = hand_node(visuals)
	if hand == null:
		model.rotation = Vector3.ZERO
		model.position = ROOT_HAND_OFFSET
		visuals.add_child(model)
		return visuals
	hand.add_child(model)
	return hand


## Gift Shop kiosk prop (Patrick's ATM), standing on y = 0, `height` metres tall.
const SHOP_KIOSK_MODEL: String = "res://assets/polypizza/atm_shop.fbx"


static func make_kiosk(height: float = 1.9) -> Node3D:
	var holder := Node3D.new()
	holder.name = "ShopKiosk"
	var ps: PackedScene = load(SHOP_KIOSK_MODEL) as PackedScene if ResourceLoader.exists(SHOP_KIOSK_MODEL) else null
	if ps == null:
		return holder
	var model: Node3D = ps.instantiate()
	if not _bounds.has(SHOP_KIOSK_MODEL):
		_bounds[SHOP_KIOSK_MODEL] = _measure(model)
	var b: AABB = _bounds[SHOP_KIOSK_MODEL]
	var s: float = height / maxf(b.size.y, 0.0001)
	model.scale = model.scale * s
	model.position = Vector3(-b.get_center().x, -b.position.y, -b.get_center().z) * s
	holder.add_child(model)
	return holder


## First person: the held item at the bottom right of the view (a child of the camera), a bit
## smaller than in the hand so a bat doesn't fill the screen.
const VIEW_OFFSET: Vector3 = Vector3(0.3, -0.27, -0.6)
const VIEW_SCALE: float = 0.5
## Hand-built items in first person: turned so you see their front (180°), the bow at an angle
## with the arrow pointing ahead.
const ART_VIEW_TURN: Dictionary = {&"robin_hood": Vector3(0, -55, 0)}
## First-person poses where the hand pose would block the view: [offset, rotation degrees].
const VIEW_GRIPS: Dictionary = {
	&"baseball_bat": [Vector3(0.08, 0.02, -0.05), Vector3(-40, 0, 135)],
}


static func make_view(item: StringName) -> Node3D:
	var view := Node3D.new()
	view.name = "HeldView"
	view.set_meta(&"item", item)
	view.position = VIEW_OFFSET
	view.rotation_degrees = Vector3(0, -18, 0)
	var k: float = hand_scale(item)
	var m: Node3D = make(item, size_for(item) * VIEW_SCALE)
	var grip: Array = VIEW_GRIPS.get(item, GRIPS.get(item, DEFAULT_GRIP))
	if not VIEW_GRIPS.has(item) and not GRIPS.has(item) and ItemArt.has(item):
		grip = [Vector3.ZERO, ART_VIEW_TURN.get(item, Vector3(0, 180, 0))]  # their front toward you
	m.position = (grip[0] as Vector3) * k if VIEW_GRIPS.has(item) else Vector3.ZERO
	m.rotation_degrees = grip[1]
	m.scale = Vector3.ONE * k
	view.add_child(m)
	return view


static func _measure(model: Node3D) -> AABB:
	var acc: Array = []
	_collect(model, Transform3D.IDENTITY, acc)
	if acc.is_empty():
		return AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)
	var out: AABB = acc[0]
	for a: AABB in acc:
		out = out.merge(a)
	return out


static func _collect(n: Node, xf: Transform3D, acc: Array) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		acc.append(xf * (n as MeshInstance3D).get_aabb())
	for c: Node in n.get_children():
		_collect(c, xf * (c as Node3D).transform if c is Node3D else xf, acc)
