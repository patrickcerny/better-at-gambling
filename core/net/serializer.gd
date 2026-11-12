class_name Serializer
extends RefCounted
## Wire format helpers (§4.1): only Dictionaries/Arrays of primitives travel over the network.


## True if `v` contains only wire-safe types (null, bool, int, float, String, StringName,
## Dictionary/Array of those, packed arrays).
static func is_wire_safe(v: Variant) -> bool:
	match typeof(v):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME:
			return true
		TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY:
			return true
		TYPE_ARRAY:
			for x: Variant in v:
				if not is_wire_safe(x):
					return false
			return true
		TYPE_DICTIONARY:
			var d: Dictionary = v
			for k: Variant in d:
				if not is_wire_safe(k) or not is_wire_safe(d[k]):
					return false
			return true
	return false


## Vector3 → [x, y, z] rounded to millimetres.
static func vec3(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]


## [x, y, z] → Vector3. Zero on anything else: not a list of three, an element that is not a
## number (`float([])` is a script error, `float("nan")` is NaN), or a non-finite result.
static func to_vec3(a: Variant) -> Vector3:
	if typeof(a) != TYPE_ARRAY or (a as Array).size() != 3:
		return Vector3.ZERO
	for x: Variant in a:
		if typeof(x) != TYPE_INT and typeof(x) != TYPE_FLOAT:
			return Vector3.ZERO
	var v := Vector3(float(a[0]), float(a[1]), float(a[2]))
	return v if v.is_finite() else Vector3.ZERO


## A number from the wire as a float; `default` for anything else (other types, NaN, infinity).
static func to_float(v: Variant, default: float = 0.0) -> float:
	if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
		return default
	var f: float = float(v)
	return f if is_finite(f) else default


## A whole number from the wire; `default` for anything else (an int, or a float with no fraction
## and a sane size: `int(1e30)` and `int(NAN)` are the smallest int64).
static func to_int(v: Variant, default: int = 0) -> int:
	if typeof(v) == TYPE_INT:
		return v
	if typeof(v) == TYPE_FLOAT:
		var f: float = v
		if is_finite(f) and absf(f) <= 9.0e15 and f == floorf(f):
			return int(f)
	return default


## A name from the wire (String or StringName); `default` for anything else.
static func to_name(v: Variant, default: StringName = &"") -> StringName:
	if typeof(v) == TYPE_STRING_NAME:
		return v
	if typeof(v) == TYPE_STRING:
		return StringName(v as String)
	return default


## A yes/no from the wire (bool, or a number as 0 / not 0); `default` for anything else.
static func to_bool(v: Variant, default: bool = false) -> bool:
	if typeof(v) == TYPE_BOOL:
		return v
	if typeof(v) == TYPE_INT:
		return (v as int) != 0
	return default


## Encoded byte size (for bandwidth accounting).
static func byte_size(v: Variant) -> int:
	return var_to_bytes(v).size()


## Stable hash of a wire value, used to compare client mirrors with the server.
static func state_hash(v: Variant) -> int:
	return _canonical(v).hash()


static func _canonical(v: Variant) -> String:
	match typeof(v):
		TYPE_DICTIONARY:
			var d: Dictionary = v
			var keys: Array = d.keys()
			keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
			var parts: PackedStringArray = []
			for k: Variant in keys:
				parts.append(str(k) + ":" + _canonical(d[k]))
			return "{" + ",".join(parts) + "}"
		TYPE_ARRAY:
			var parts: PackedStringArray = []
			for x: Variant in v:
				parts.append(_canonical(x))
			return "[" + ",".join(parts) + "]"
		TYPE_FLOAT:
			return str(snappedf(float(v), 0.001))
	return str(v)
