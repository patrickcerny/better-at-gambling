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
	&"dog_collar": "res://assets/polypizza/dog_leash.glb",
	&"russian_roulette": "res://assets/polypizza/revolver.glb",
	&"scratch_ticket": "res://assets/polypizza/scratch_ticket.glb",
	&"beer": "res://assets/polypizza/beer_full.glb",
}
## Longest side of the model in the hand, metres (DEFAULT_SIZE otherwise).
const DEFAULT_SIZE: float = 0.3
const SIZES: Dictionary = {
	&"baseball_bat": 0.95,
	&"dog_collar": 0.42,
	&"russian_roulette": 0.4,
	&"scratch_ticket": 0.32,
	&"beer": 0.34,
	&"empty_bottle": 0.32,
}
## How a model sits in the hand, in upright space (y up, -z forward): [offset, rotation degrees].
const DEFAULT_GRIP: Array = [Vector3(0.0, 0.16, -0.2), Vector3.ZERO]
const GRIPS: Dictionary = {
	&"baseball_bat": [Vector3(0.0, 0.38, -0.12), Vector3(-25, 0, 0)],
	&"russian_roulette": [Vector3(0.0, 0.12, -0.24), Vector3(0, 90, 0)],
	&"scratch_ticket": [Vector3(0.0, 0.2, -0.2), Vector3(75, 0, 0)],
	&"dog_collar": [Vector3(0.0, 0.18, -0.22), Vector3(60, 0, 0)],
}
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
	return path_for(item) != DEFAULT_MODEL


static func size_for(item: StringName) -> float:
	return float(SIZES.get(item, DEFAULT_SIZE))


## A new instance of `item`'s model, its longest side scaled to `size` (the item's hand size when
## 0), centred on the origin. The holder node is named after the item.
static func make(item: StringName, size: float = 0.0) -> Node3D:
	var holder := Node3D.new()
	holder.name = "Item_" + String(item).to_pascal_case()
	holder.set_meta(&"item", item)
	var path: String = path_for(item)
	var ps: PackedScene = load(path) as PackedScene if ResourceLoader.exists(path) else null
	if ps == null:
		return holder
	var model: Node3D = ps.instantiate()
	if not _bounds.has(path):
		_bounds[path] = _measure(model)
	var b: AABB = _bounds[path]
	var longest: float = maxf(maxf(b.size.x, b.size.y), maxf(b.size.z, 0.0001))
	var s: float = (size if size > 0.0 else size_for(item)) / longest
	model.scale = model.scale * s
	model.position = -b.get_center() * s
	for n: Node in model.find_children("*", "GeometryInstance3D", true, false):
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(model)
	return holder


## The model posed for a hand: `make` plus the item's grip, inside a "Held" node that turns the
## bean's hand space (the arm points down its -z) back to upright, so grips read as y up, -z
## forward while the arm hangs at rest.
static func make_held(item: StringName) -> Node3D:
	var held := Node3D.new()
	held.name = "Held"
	held.set_meta(&"item", item)
	held.rotation.x = HAND_UPRIGHT
	var m: Node3D = make(item)
	var grip: Array = GRIPS.get(item, DEFAULT_GRIP)
	m.position = grip[0]
	m.rotation_degrees = grip[1]
	held.add_child(m)
	return held


## Where a held item goes on an avatar's visuals: a node named "HandR" if the model has one, else
## the bean's right hand ("ArmR/Hand"), else `null` (then the caller uses the root with
## `ROOT_HAND_OFFSET`).
const ROOT_HAND_OFFSET: Vector3 = Vector3(0.5, 0.85, -0.25)


static func hand_node(visuals: Node) -> Node3D:
	if visuals == null:
		return null
	# The bean exposes its right-hand slot (also moves onto a skin's wrist bone).
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
## First-person poses where the hand pose would block the view: [offset, rotation degrees].
const VIEW_GRIPS: Dictionary = {
	&"baseball_bat": [Vector3(0.08, 0.02, -0.05), Vector3(-40, 0, -45)],
}


static func make_view(item: StringName) -> Node3D:
	var view := Node3D.new()
	view.name = "HeldView"
	view.set_meta(&"item", item)
	view.position = VIEW_OFFSET
	view.rotation_degrees = Vector3(0, -18, 0)
	var m: Node3D = make(item, size_for(item) * VIEW_SCALE)
	var grip: Array = VIEW_GRIPS.get(item, GRIPS.get(item, DEFAULT_GRIP))
	m.position = grip[0] if VIEW_GRIPS.has(item) else Vector3.ZERO
	m.rotation_degrees = grip[1]
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
