class_name CoinPack
extends Resource
## Coins for real money (Patrick 2026-11-14: "you can also buy coins"): a consumable Steam item;
## `SteamSvc` consumes it from the inventory and adds the Coins to the profile.

@export var id: StringName = &""
@export var coins: int = 0
## Reference price in euro cents.
@export var cents: int = 0
@export var steam_item: int = 0
