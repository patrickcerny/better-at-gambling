class_name LootTableConfig
extends Resource
## Rarity weights for the item everyone gets after a minigame (§2.10, Patrick's note #11). Rarity
## order: common, rare, legendary. First place rolls with `best_weights`, last place with
## `worst_weights`, the places between blend linearly from one to the other.

@export var best_weights: PackedFloat32Array = PackedFloat32Array([0.0, 3.0, 1.0])
@export var worst_weights: PackedFloat32Array = PackedFloat32Array([4.0, 1.0, 0.0])
## Last place gets an extra Rare (Underdog) when at least this many players took part.
@export var underdog_min_players: int = 3
