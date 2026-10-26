class_name CosmeticShop
extends Resource
## The cosmetics shop's stock (data/progression/cosmetics_shop.tres), in the order it shows them.

const PATH: String = "res://data/progression/cosmetics_shop.tres"

@export var items: Array[CosmeticDef] = []

static var _default: CosmeticShop = null


## The shipped shop (loaded once).
static func default() -> CosmeticShop:
	if _default == null:
		_default = load(PATH) as CosmeticShop
		if _default == null:
			_default = CosmeticShop.new()
	return _default


func find(id: StringName) -> CosmeticDef:
	for d: CosmeticDef in items:
		if d.id == id:
			return d
	return null


## Every item of one kind, in shop order.
func of_kind(kind: StringName) -> Array[CosmeticDef]:
	var out: Array[CosmeticDef] = []
	for d: CosmeticDef in items:
		if d.kind == kind:
			out.append(d)
	return out


## The colour item for a palette index (null when the shop has none).
func color_item(index: int) -> CosmeticDef:
	for d: CosmeticDef in items:
		if d.kind == CosmeticDef.KIND_COLOR and d.color_index == index:
			return d
	return null
