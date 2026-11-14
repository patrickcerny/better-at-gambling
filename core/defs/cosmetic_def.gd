class_name CosmeticDef
extends Resource
## One thing the cosmetics shop lists (docs/GDD.md "Cosmetics shop"): a bean colour, or an outfit
## piece (a hat, shirt, trousers, cape or boots) whose model is built in code (`OutfitMeshes`, by
## `id`, which starts with the kind: "hat_police"). The shop, the profile's owned list and the
## prices work by `id` for every kind. A bean wears one piece of each outfit kind.

const KIND_COLOR: StringName = &"color"
const KIND_HAT: StringName = &"hat"
const KIND_SHIRT: StringName = &"shirt"
const KIND_PANTS: StringName = &"pants"
const KIND_CAPE: StringName = &"cape"
const KIND_BOOTS: StringName = &"boots"
## Shop tabs, in order.
const KINDS: Array[StringName] = [KIND_COLOR, KIND_HAT, KIND_SHIRT, KIND_PANTS, KIND_CAPE, KIND_BOOTS]
## The outfit slots, in wire order (`PlayerState.outfit`).
const OUTFIT_KINDS: Array[StringName] = [KIND_HAT, KIND_SHIRT, KIND_PANTS, KIND_CAPE, KIND_BOOTS]

## Stable id saved in the profile ("color_mint").
@export var id: StringName = &""
@export var kind: StringName = KIND_COLOR
@export var display_name: String = ""
## Price in Coins; 0 = free and always owned.
@export var price: int = 0
## Only for real money through Steam (no Coin price; `price` is ignored).
@export var money_only: bool = false
## Real-money price in euro cents (0 = not sold for money). The price shown comes from Steam
## (the player's currency); this is the reference written into tools/steam/itemdefs.json.
@export var cents: int = 0
## The Steam Inventory item definition that grants this piece (0 = none).
@export var steam_item: int = 0
## Outfit pieces: up to three colours for the shop tile's swatch.
@export var swatch: PackedColorArray = PackedColorArray()
## KIND_COLOR: the palette index (`Palette.player_color`, `Cosmetics.COLOR_COUNT`).
@export var color_index: int = -1


func is_free() -> bool:
	return price <= 0 and not money_only


## Whether it can be bought with Coins.
func coin_buyable() -> bool:
	return not money_only and price > 0


## Whether it can be bought with real money through Steam.
func steam_buyable() -> bool:
	return steam_item > 0 and cents > 0
