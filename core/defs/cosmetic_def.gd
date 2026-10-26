class_name CosmeticDef
extends Resource
## One thing the cosmetics shop lists (docs/GDD.md "Cosmetics shop"): a bean colour for now. New
## kinds (a hat, a trail, ...) add a `KIND_*`, their own fields and a way to wear them; the shop,
## the profile's owned list and the prices already work by `id` for every kind.

const KIND_COLOR: StringName = &"color"
const KIND_HAT: StringName = &"hat"
const KINDS: Array[StringName] = [KIND_COLOR, KIND_HAT]

## Stable id saved in the profile ("color_mint").
@export var id: StringName = &""
@export var kind: StringName = KIND_COLOR
@export var display_name: String = ""
## Price in Coins; 0 = free and always owned.
@export var price: int = 0
## KIND_COLOR: the palette index (`Palette.player_color`, `Cosmetics.COLOR_COUNT`).
@export var color_index: int = -1


func is_free() -> bool:
	return price <= 0
