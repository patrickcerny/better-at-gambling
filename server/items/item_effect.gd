class_name ItemEffect
extends RefCounted
## Behaviour of one item kind (§2.8). The `ItemSystem` validates cooldowns, targets and
## protections first; an effect only checks what is special to it and then changes the match
## through the context (economy, modifier stack, pickups, …). Effects never touch game code:
## luck, multipliers and refunds go through the ModifierStack.


## Item-specific reason it can't be used right now (&"" = fine).
func can_activate(_ctx: ItemContext) -> StringName:
	return &""


## Applies the item. Returns extra fields for the public `item_used` event.
func activate(_ctx: ItemContext) -> Dictionary:
	return {}


## A modifier this item added ran out or was used up.
func on_expire(_ctx: ItemContext, _reason: StringName) -> void:
	pass
