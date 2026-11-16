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
## Animated skins: a moving pattern over the whole bean (`vfx/shaders/bean_skin.gdshader`), worn
## like an outfit piece (its own slot) and drawn over the bean colour.
const KIND_SKIN: StringName = &"skin"
## The face: eyes (pupil shapes, lashes, glasses), mouths (teeth, tongue, lipstick) and beards.
const KIND_EYES: StringName = &"eyes"
const KIND_MOUTH: StringName = &"mouth"
const KIND_BEARD: StringName = &"beard"
## Shop tabs, in order.
const KINDS: Array[StringName] = [KIND_COLOR, KIND_SKIN, KIND_HAT, KIND_SHIRT, KIND_PANTS, KIND_CAPE, KIND_BOOTS, KIND_EYES, KIND_MOUTH, KIND_BEARD]
## The outfit slots, in wire order (`PlayerState.outfit`).
const OUTFIT_KINDS: Array[StringName] = [KIND_HAT, KIND_SHIRT, KIND_PANTS, KIND_CAPE, KIND_BOOTS, KIND_SKIN, KIND_EYES, KIND_MOUTH, KIND_BEARD]

## Stable id saved in the profile ("color_mint").
@export var id: StringName = &""
@export var kind: StringName = KIND_COLOR
@export var display_name: String = ""
## Price in (red) Coins, earned by playing; 0 = free and always owned (unless `gold` is set).
@export var price: int = 0
## Unlocked for free at this player level (0 = never): before that it can be bought (Patrick
## 2026-11-14: "some skins behind a level wall, or you can buy them").
@export var level: int = 0
## Premium: the price in Gold Coins (bought with real money only), 0 = a normal piece. A premium
## piece has no red Coin price (Patrick 2026-11-15: "Goldcoins nur für echtgeld, red coins durch
## spielen"; red for normal, gold for premium).
@export var gold: int = 0
## The Steam Inventory item definition that grants this piece (0 = none): premium pieces (exchanged
## for Gold Coins) and every piece of a set (granted by the set's bundle).
@export var steam_item: int = 0
## Outfit pieces: up to three colours for the shop tile's swatch.
@export var swatch: PackedColorArray = PackedColorArray()
## Developers only (Patrick 2026-11-15: "einen super mega hardcore giga krassen skin für developers
## only"): owned by and shown to `DevMode` accounts only, never sold or unlocked.
@export var dev_only: bool = false
## Only won on the Daily Spin (`DailyWheel.SKIN_ID`, Patrick 2026-11-16): never sold, never
## unlocked by level; owned when it is in the Steam inventory (`steam_item`).
@export var wheel_only: bool = false
## Only unlocked by this Steam achievement (`Achievements.DEFS`, Patrick 2026-11-16: "Each
## achievement should also unlock something"): never sold, not on the pass or the Daily Spin.
@export var achievement: StringName = &""
## KIND_COLOR: the palette index (`Palette.player_color`, `Cosmetics.COLOR_COUNT`).
@export var color_index: int = -1


func is_free() -> bool:
	return price <= 0 and gold <= 0 and level <= 0 and not dev_only and not wheel_only and achievement == &""


## Whether it can be bought with red Coins.
func coin_buyable() -> bool:
	return gold <= 0 and price > 0


## Premium: bought with Gold Coins through the Steam inventory.
func premium() -> bool:
	return gold > 0 and steam_item > 0
