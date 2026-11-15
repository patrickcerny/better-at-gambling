class_name CoinPack
extends Resource
## Gold Coins for real money (Patrick 2026-11-15: "Goldcoins nur für echtgeld"): a Steam bundle
## that grants `gold` Gold Coin items (`GOLD_ITEM`). They stay in the Steam inventory and are spent
## by exchanging them for premium pieces and sets (`SteamSvc.buy_with_gold`).

## The Steam item definition of one Gold Coin (a stack in the inventory is the balance).
const GOLD_ITEM: int = 3100

@export var id: StringName = &""
## Gold Coins in the pack.
@export var gold: int = 0
## Reference price in euro cents.
@export var cents: int = 0
@export var steam_item: int = 0
