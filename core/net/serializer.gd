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


## [x, y, z] → Vector3 (zero on malformed input).
static func to_vec3(a: Variant) -> Vector3:
	if typeof(a) != TYPE_ARRAY or (a as Array).size() != 3:
		return Vector3.ZERO
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


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
