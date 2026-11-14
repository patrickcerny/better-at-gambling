class_name Intents
extends RefCounted
## Client → server intent types and the fields each may carry. Everything a client may ask for.
##
## `validate` checks the whole shape, not only that the keys are there: a handler that reads
## `int(intent["target"])` can rely on a whole number being there (`int([])`, `StringName(5)` and
## `bool("x")` are script errors that would abort the handler half-way), and `WireGuard` has already
## refused NaN, infinities, absurd sizes and anything that is not plain data.

## Field kinds.
enum Kind {
	INT,  ## a whole number (ids, slots, indices): an int, or a float without a fraction
	NUMBER,  ## int or float
	BOOL,  ## true/false (or 0/1)
	NAME,  ## String/StringName of at most NAME_MAX characters (station, action, emote ids)
	TEXT,  ## String/StringName of any length WireGuard lets through (a Spy clue)
	VEC3,  ## [x, y, z], three numbers
	DICT,  ## Dictionary (a bet, an action's parameters: the game checks its own fields)
	ANY,  ## whatever WireGuard lets through (a lobby setting's value)
}

## Longest id a client may send.
const NAME_MAX: int = 64

## Required fields per intent type.
const SCHEMA: Dictionary = {
	&"sit": {"station": Kind.NAME},
	&"leave": {},
	&"place_bet": {"station": Kind.NAME, "bet": Kind.DICT},
	&"clear_bets": {"station": Kind.NAME},
	&"action": {"station": Kind.NAME, "action": Kind.NAME},
	&"use_item": {"slot": Kind.INT},
	&"discard_item": {"slot": Kind.INT},
	&"rps_pick": {"duel": Kind.INT, "pick": Kind.INT},
	&"shop_buy": {"index": Kind.INT},
	## One smash of the Odd Jobs button next to the Gift Shop (the server counts and pays).
	&"odd_jobs_press": {},
	&"submit_answer": {"question": Kind.INT, "index": Kind.INT},
	&"bust_or_bank_action": {"action": Kind.NAME},
	&"vote_race_vote": {"target": Kind.INT},
	&"find_the_lady_pick": {"slot": Kind.INT},
	&"forehead_poker_action": {"action": Kind.NAME},
	&"spy_clue": {"text": Kind.TEXT}, &"spy_call_vote": {}, &"spy_vote": {"target": Kind.INT},
	&"split_or_steal_pick": {"choice": Kind.NAME},
	&"lonely_number_pick": {"number": Kind.INT},
	## Walkable minigames' action button (E): {kind, target?}; the logic picks the real target.
	&"minigame_action": {"kind": Kind.NAME},
	&"minigame_ready": {},
	&"set_ready": {"ready": Kind.BOOL},
	&"lobby_setting": {"key": Kind.NAME, "value": Kind.ANY},
	## Bean colour (`Cosmetics`, the pedestal colour panel): {"color": palette index}.
	&"set_color": {"color": Kind.INT},
	## One outfit slot (`CosmeticDef.OUTFIT_KINDS`): the shop item to wear there, "" to take it off.
	&"set_outfit": {"kind": Kind.NAME, "item": Kind.NAME},
	&"return_to_lobby": {},
	&"kick_player": {"target": Kind.INT},
	&"emote": {"id": Kind.NAME},
	## Number-key emotes acted out by the bean (`Emotes.ANIMATED`): {"emote": StringName}.
	&"play_emote": {"emote": Kind.NAME},
	&"move": {"pos": Kind.VEC3, "yaw": Kind.NUMBER},
	&"grab": {"target": Kind.INT},
	&"release": {"throw": Kind.BOOL},
	&"shove": {"aim": Kind.VEC3},
	&"shake": {},
	&"break_free": {},
	&"megaphone": {},
}

## Fields an intent may carry on top: checked when present, never required.
const OPTIONAL: Dictionary = {
	&"action": {"params": Kind.DICT},
	&"use_item": {"target": Kind.INT, "option": Kind.INT},
	&"find_the_lady_pick": {"round": Kind.INT},
	&"forehead_poker_action": {"round": Kind.INT},
	&"minigame_action": {"target": Kind.INT},
	&"move": {"airborne": Kind.BOOL},
	&"release": {"aim": Kind.VEC3},
	&"shove": {"target": Kind.INT},
}


## Builds an intent dictionary.
static func make(type: StringName, payload: Dictionary = {}) -> Dictionary:
	var i: Dictionary = payload.duplicate()
	i["type"] = type
	return i


## The intent's type, or &"" when it has none or it is not a name (`intent.get("type") == &"x"`
## is itself a script error when a client sends a number there).
static func type_of(intent: Dictionary) -> StringName:
	var type: Variant = intent.get("type", null)
	if typeof(type) == TYPE_STRING_NAME:
		return type
	if typeof(type) == TYPE_STRING and (type as String).length() <= NAME_MAX:
		return StringName(type as String)
	return &""


## The keys that are missing or hold the wrong kind of value (empty = well-formed). Unknown types
## report ["type"]; a payload `WireGuard` refuses (NaN, a megabyte of nesting, a Vector3 ...)
## reports ["payload"].
static func validate(intent: Dictionary) -> Array[String]:
	var bad: Array[String] = []
	var type: StringName = type_of(intent)
	if type == &"" or not SCHEMA.has(type):
		bad.append("type")
		return bad
	if WireGuard.problem(intent) != "":
		bad.append("payload")
		return bad
	var required: Dictionary = SCHEMA[type]
	for key: String in required:
		if not intent.has(key) or not fits(intent[key], required[key]):
			bad.append(key)
	var optional: Dictionary = OPTIONAL.get(type, {})
	for key: String in optional:
		if intent.has(key) and not fits(intent[key], optional[key]):
			bad.append(key)
	return bad


## True if `value` is of field kind `kind`.
static func fits(value: Variant, kind: Kind) -> bool:
	var t: int = typeof(value)
	match kind:
		Kind.INT:
			if t == TYPE_FLOAT:
				var f: float = value
				return is_finite(f) and f == floorf(f)
			return t == TYPE_INT
		Kind.NUMBER:
			return t == TYPE_INT or (t == TYPE_FLOAT and is_finite(value as float))
		Kind.BOOL:
			return t == TYPE_BOOL or t == TYPE_INT
		Kind.NAME:
			if t == TYPE_STRING:
				return (value as String).length() <= NAME_MAX
			return t == TYPE_STRING_NAME and String(value as StringName).length() <= NAME_MAX
		Kind.TEXT:
			return t == TYPE_STRING or t == TYPE_STRING_NAME
		Kind.VEC3:
			if t != TYPE_ARRAY or (value as Array).size() != 3:
				return false
			for x: Variant in value:
				if typeof(x) != TYPE_INT and not (typeof(x) == TYPE_FLOAT and is_finite(x as float)):
					return false
			return true
		Kind.DICT:
			return t == TYPE_DICTIONARY
		Kind.ANY:
			return true
	return false
