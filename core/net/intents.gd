class_name Intents
extends RefCounted
## Client → server intent types and their required keys. Everything a client may ask for.

const SCHEMA: Dictionary = {
	&"sit": ["station"],
	&"leave": [],
	&"place_bet": ["station", "bet"],
	&"clear_bets": ["station"],
	&"action": ["station", "action"],
	&"use_item": ["slot"],
	&"discard_item": ["slot"],
	&"rps_answer": ["duel", "accept"],
	&"rps_pick": ["duel", "pick"],
	&"shop_buy": ["index"],
	&"submit_answer": ["question", "index"],
	&"set_ready": ["ready"],
	&"lobby_setting": ["key", "value"],
	&"set_skin": ["skin"],
	&"return_to_lobby": [],
	&"emote": ["id"],
	&"move": ["pos", "yaw"],
	&"grab": ["target"],
	&"release": ["throw"],
	&"shove": ["aim"],
	&"shake": [],
	&"break_free": [],
	&"megaphone": [],
}


## Builds an intent dictionary.
static func make(type: StringName, payload: Dictionary = {}) -> Dictionary:
	var i: Dictionary = payload.duplicate()
	i["type"] = type
	return i


## Missing required keys (empty = well-formed). Unknown types report ["type"].
static func validate(intent: Dictionary) -> Array[String]:
	var missing: Array[String] = []
	var type: Variant = intent.get("type", null)
	if typeof(type) != TYPE_STRING_NAME and typeof(type) != TYPE_STRING:
		missing.append("type")
		return missing
	if not SCHEMA.has(StringName(type)):
		missing.append("type")
		return missing
	for key: String in SCHEMA[StringName(type)]:
		if not intent.has(key):
			missing.append(key)
	return missing
