class_name WireGuard
extends RefCounted
## What a peer may put in a packet payload. `bytes_to_var` without objects still decodes every
## other Variant type (vectors, packed arrays, NaN, a megabyte of nested arrays), and one
## `int(payload["x"])` on an Array is a script error that aborts the handler half-way. So every
## payload a client sends passes `problem()` before any handler reads it: plain data only, of
## bounded size, with finite numbers of a sane magnitude. Handlers then only ever meet
## nil/bool/int/float/String/StringName/Array/Dictionary, and `Intents.validate` types the fields.

## Containers nested deeper than this are refused (an intent is a flat dictionary with at most a
## `bet`/`params` dictionary holding a list).
const MAX_DEPTH: int = 4
## Entries per Array or Dictionary.
const MAX_ITEMS: int = 64
## Values in the whole payload.
const MAX_NODES: int = 256
## Characters per String/StringName (a Spy clue is the longest thing a player types).
const MAX_TEXT: int = 512
## Characters per dictionary key.
const MAX_KEY: int = 48
## Largest magnitude of any number: far above every stake, id and coordinate, far below where
## `int(x)` or `amount * multiplier` would overflow (`int(1e30)` is the smallest int64).
const MAX_NUMBER: float = 1.0e12


## "" when `value` is acceptable, else a short reason (for the log).
static func problem(value: Variant) -> String:
	var budget: Array[int] = [MAX_NODES]
	return _walk(value, 0, budget)


## True if `value` is a Dictionary that passes `problem()`: what every keyed message must be.
static func is_clean_dictionary(value: Variant) -> bool:
	return typeof(value) == TYPE_DICTIONARY and problem(value) == ""


static func _walk(value: Variant, depth: int, budget: Array[int]) -> String:
	budget[0] -= 1
	if budget[0] < 0:
		return "too many values"
	match typeof(value):
		TYPE_NIL, TYPE_BOOL:
			return ""
		TYPE_INT:
			var i: int = value
			return "" if i >= -int(MAX_NUMBER) and i <= int(MAX_NUMBER) else "integer out of range"
		TYPE_FLOAT:
			var f: float = value
			if not is_finite(f):
				return "non-finite number"
			return "" if absf(f) <= MAX_NUMBER else "number out of range"
		TYPE_STRING:
			return "" if (value as String).length() <= MAX_TEXT else "text too long"
		TYPE_STRING_NAME:
			return "" if String(value as StringName).length() <= MAX_TEXT else "text too long"
		TYPE_ARRAY:
			var list: Array = value
			if depth >= MAX_DEPTH:
				return "nested too deep"
			if list.size() > MAX_ITEMS:
				return "list too long"
			for item: Variant in list:
				var why: String = _walk(item, depth + 1, budget)
				if why != "":
					return why
			return ""
		TYPE_DICTIONARY:
			var dict: Dictionary = value
			if depth >= MAX_DEPTH:
				return "nested too deep"
			if dict.size() > MAX_ITEMS:
				return "dictionary too big"
			for key: Variant in dict:
				match typeof(key):
					TYPE_STRING:
						if (key as String).length() > MAX_KEY:
							return "key too long"
					TYPE_STRING_NAME:
						if String(key as StringName).length() > MAX_KEY:
							return "key too long"
					TYPE_INT:
						pass
					_:
						return "key of type %s" % type_string(typeof(key))
				var why: String = _walk(dict[key], depth + 1, budget)
				if why != "":
					return why
			return ""
	return "value of type %s" % type_string(typeof(value))
