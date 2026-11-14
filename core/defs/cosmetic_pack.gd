class_name CosmeticPack
extends Resource
## A full outfit sold as one Steam purchase (a Steam Inventory "bundle" item definition that
## grants every piece in it), always 50 cents cheaper than the pieces bought one by one
## (Patrick 2026-11-14: pieces 0,50 to 1 euro, full packs 50 cents cheaper than everything single).

## What a pack saves against its pieces bought one by one, in euro cents.
const DISCOUNT_CENTS: int = 50

@export var id: StringName = &""
@export var display_name: String = ""
## The pieces (outfit `CosmeticDef` ids), one per slot at most.
@export var pieces: Array[StringName] = []
## Reference price in euro cents (`DISCOUNT_CENTS` under the pieces' sum).
@export var cents: int = 0
## The Steam bundle item definition.
@export var steam_item: int = 0
