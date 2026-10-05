class_name ItemContext
extends RefCounted
## Everything an `ItemEffect` may touch for one activation.

var system: ItemSystem
var def: ItemDefinition
## Who the item acts for (after a Mirror reflection: the mirror's owner).
var user: int = -1
## Who it acts on (self for self items; after a reflection: the original user).
var target: int = -1
var now: float = 0.0
## True when a Mirror turned this activation around.
var reflected: bool = false
## Extra choices sent with the intent (e.g. Pickpocket's greed tier `option`).
var options: Dictionary = {}


func _init(p_system: ItemSystem, p_def: ItemDefinition, p_user: int, p_target: int, p_now: float) -> void:
	system = p_system
	def = p_def
	user = p_user
	target = p_target
	now = p_now


## Number from the item's params (falls back to `default`).
func param(key: String, default: Variant) -> Variant:
	return def.params.get(key, default)
