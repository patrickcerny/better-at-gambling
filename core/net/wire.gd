class_name Wire
extends RefCounted
## Packet framing (§4.1): every message is `[type: int, payload]` encoded with `var_to_bytes`
## (objects are never encoded or decoded). Pure helpers, used by both ends.


## Encodes one message.
static func encode(type: int, payload: Variant = null) -> PackedByteArray:
	return var_to_bytes([type, payload])


## Decodes one message into `[type, payload]`, or `[]` when the bytes are not a valid message.
static func decode(bytes: PackedByteArray) -> Array:
	if bytes.size() < 8 or (bytes.decode_u32(0) & 0xFF) != TYPE_ARRAY:
		return []  # not an encoded Array: don't let the decoder complain about junk
	var v: Variant = bytes_to_var(bytes)
	if typeof(v) != TYPE_ARRAY:
		return []
	var a: Array = v
	if a.size() != 2 or typeof(a[0]) != TYPE_INT:
		return []
	if not Serializer.is_wire_safe(a[1]):
		return []
	return a
