class_name CosmeticPack
extends Resource
## A full outfit for Gold Coins (a Steam Inventory "bundle" item definition that grants every piece
## in it, exchanged for Gold Coins), cheaper than its premium pieces one by one (Patrick 2026-11-14:
## full packs cheaper than everything single; 2026-11-15: sets are paid in Gold).

## What a pack saves against its pieces bought one by one, in Gold Coins.
const DISCOUNT: int = 50

@export var id: StringName = &""
@export var display_name: String = ""
## The pieces (outfit `CosmeticDef` ids), one per slot at most.
@export var pieces: Array[StringName] = []
## Price in Gold Coins.
@export var gold: int = 0
## The Steam bundle item definition.
@export var steam_item: int = 0
