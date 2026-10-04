class_name LootTableConfig
extends Resource
## Rarity weights per draft placement (§2.10). Rarity order: common, rare, legendary.

@export var first_weights: PackedFloat32Array = PackedFloat32Array([0.0, 3.0, 1.0])
@export var second_weights: PackedFloat32Array = PackedFloat32Array([2.0, 1.0, 0.0])
@export var first_offer_count: int = 3
@export var second_offer_count: int = 3
@export var third_offer_count: int = 2
@export var underdog_min_players: int = 3
