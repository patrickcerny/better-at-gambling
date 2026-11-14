class_name CosmeticShop
extends Resource
## The cosmetics shop's stock (data/progression/cosmetics_shop.tres), in the order it shows them.

const PATH: String = "res://data/progression/cosmetics_shop.tres"

@export var items: Array[CosmeticDef] = []
## Full outfits sold together for real money (the PACKS tab).
@export var packs: Array[CosmeticPack] = []

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


func find_pack(id: StringName) -> CosmeticPack:
	for k: CosmeticPack in packs:
		if k.id == id:
			return k
	return null


## The item or pack granted by Steam item definition `def` (null when none).
func by_steam_item(def: int) -> Resource:
	if def <= 0:
		return null
	for d: CosmeticDef in items:
		if d.steam_item == def:
			return d
	for k: CosmeticPack in packs:
		if k.steam_item == def:
			return k
	return null


## The pieces' euro cents added up (what a pack would cost piece by piece).
func pieces_cents(pack: CosmeticPack) -> int:
	var sum: int = 0
	for id: StringName in pack.pieces:
		var d: CosmeticDef = find(id)
		if d != null:
			sum += d.cents
	return sum


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
