class_name ItemDefinition
extends Resource
## Data for one item (§2.8). Behaviour lives in the `effect_script` (an ItemEffect).

enum Rarity { COMMON, RARE, LEGENDARY }
enum TargetMode { SELF, ANY_PLAYER, NEAR_PLAYER, SEATED_PLAYER, LEADER, PLACED, RANDOM }

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D
@export var rarity: Rarity = Rarity.COMMON
@export var target_mode: TargetMode = TargetMode.SELF
@export var requires_proximity: bool = false
@export var range_m: float = 0.0
@export var is_negative: bool = false
@export var duration: float = 0.0
@export var params: Dictionary = {}
@export var effect_script: Script
## False for items that only come from other items (Empty Bottle): never offered in drafts,
## scratch tickets or the shop.
@export var in_loot: bool = true
