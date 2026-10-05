class_name PropModels
extends RefCounted
## Patrick's poly.pizza props (credited in CREDITS.md). `make` returns a model centred on x/z,
## resting on y = 0 and scaled to the size the caller asks for, so callers never deal with each
## file's own units and pivot.

const PATHS: Dictionary = {
	&"poker_chip": "res://assets/polypizza/poker_chip.glb",
	&"money_pile": "res://assets/polypizza/money_pile.glb",
	&"seat": "res://assets/polypizza/seat.glb",
	&"rug": "res://assets/polypizza/rug_blackjack.glb",
	&"couch": "res://assets/polypizza/couch.glb",
	&"plant_1": "res://assets/polypizza/flowers_01.glb",
	&"plant_2": "res://assets/polypizza/flowers_02.glb",
	&"plant_3": "res://assets/polypizza/flowers_03.glb",
	&"cone": "res://assets/polypizza/cone.glb",
	&"beer": "res://assets/polypizza/beer_empty.glb",
}
## Item → prop the user holds up when they use it. Items without their own model show nothing yet.
const ITEM_PROPS: Dictionary = {&"beer": &"beer"}

## Model-space bounds per prop, measured once.
static var _bounds: Dictionary = {}


static func has(id: StringName) -> bool:
	return PATHS.has(id)


## A new instance of prop `id`: its widest side scaled to `width` when given, else its height to
## `height` (else native size).
static func make(id: StringName, height: float = 0.0, width: float = 0.0) -> Node3D:
	var holder := Node3D.new()
	holder.name = String(id).to_pascal_case()
	var ps: PackedScene = load(str(PATHS.get(id, ""))) as PackedScene
	if ps == null:
		return holder
	var model: Node3D = ps.instantiate()
	if not _bounds.has(id):
		_bounds[id] = _measure(model)
	var b: AABB = _bounds[id]
	var s: float = 1.0
	if width > 0.0:
		s = width / maxf(maxf(b.size.x, b.size.z), 0.0001)
	elif height > 0.0:
		s = height / maxf(b.size.y, 0.0001)
	model.scale = model.scale * s
	model.position = Vector3(-b.get_center().x, -b.position.y, -b.get_center().z) * s
	holder.add_child(model)
	return holder


## Hides a greybox solid's own mesh (keeping its collision) and puts prop `id` in its place;
## the solid's origin is its centre, so the model is dropped by `half_height`.
static func dress(solid: Node3D, id: StringName, half_height: float, height: float = 0.0, width: float = 0.0) -> Node3D:
	var mesh: Node = solid.get_node_or_null(^"Mesh")
	if mesh != null:
		(mesh as Node3D).visible = false
	var m: Node3D = make(id, height, width)
	m.position.y = -half_height
	solid.add_child(m)
	return m


## Darkens a prop's colors by `factor` (0..1) so bright source palettes sit in the warm casino.
static func shade(prop: Node3D, factor: float) -> Node3D:
	for n: Node in prop.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		for i: int in mi.get_surface_override_material_count():
			var src: Material = mi.get_active_material(i)
			if src is BaseMaterial3D:
				var m: BaseMaterial3D = (src as BaseMaterial3D).duplicate()
				m.albedo_color = m.albedo_color.darkened(1.0 - factor)
				mi.set_surface_override_material(i, m)
	return prop


static func _measure(model: Node3D) -> AABB:
	var acc: Array = []
	_collect(model, Transform3D.IDENTITY, acc)
	if acc.is_empty():
		return AABB(Vector3.ZERO, Vector3.ONE)
	var out: AABB = acc[0]
	for a: AABB in acc:
		out = out.merge(a)
	return out


static func _collect(n: Node, xf: Transform3D, acc: Array) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		acc.append(xf * (n as MeshInstance3D).get_aabb())
	for c: Node in n.get_children():
		_collect(c, xf * (c as Node3D).transform if c is Node3D else xf, acc)
