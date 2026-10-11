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
	&"rps_pick": ["duel", "pick"],
	&"shop_buy": ["index"],
	## One smash of the Odd Jobs button next to the Gift Shop (the server counts and pays).
	&"odd_jobs_press": [],
	&"tip_dealer": ["station"],
	&"submit_answer": ["question", "index"],
	&"bust_or_bank_action": ["action"],
	&"vote_race_vote": ["target"],
	&"find_the_lady_pick": ["slot"],
	&"forehead_poker_action": ["action"],
	&"spy_clue": ["text"], &"spy_call_vote": [], &"spy_vote": ["target"],
	&"split_or_steal_pick": ["choice"],
	&"lonely_number_pick": ["number"],
	## Walkable minigames' action button (E): {kind, target?}; the logic picks the real target.
	&"minigame_action": ["kind"],
	&"minigame_ready": [],
	&"set_ready": ["ready"],
	&"lobby_setting": ["key", "value"],
	&"set_skin": ["skin"],
	&"return_to_lobby": [],
	&"kick_player": ["target"],
	&"emote": ["id"],
	## Number-key emotes acted out by the bean (`Emotes.ANIMATED`): {"emote": StringName}.
	&"play_emote": ["emote"],
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
