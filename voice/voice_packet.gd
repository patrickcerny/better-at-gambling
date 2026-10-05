class_name VoicePacket
extends RefCounted
## Voice packet framing on `Protocol.CHANNEL_VOICE` (unreliable). Raw bytes, not `Wire` arrays:
## a 40 ms frame is 320 bytes and `var_to_bytes` would add ~20 more to each. The first byte is
## never `TYPE_ARRAY`, so a stray voice packet is ignored by `Wire.decode`.
##
## Up (client → server):   [MAGIC, flags, seq lo, seq hi, payload…]
## Down (server → client): [MAGIC, flags, seq lo, seq hi, speaker lo, speaker hi, payload…]
## `seq` counts frames per speaker (wraps at 65536); `payload` is one `VoiceCodec` frame.

const MAGIC: int = 0x56  # "V"
const UP_HEADER: int = 4
const DOWN_HEADER: int = 6
## Last frame of a talk spurt (client sets it).
const FLAG_END: int = 1
## Listener sits at the speaker's table: full volume regardless of distance (server sets it).
const FLAG_TABLE: int = 2
## Global voice phase (quiz, rewards, results): everyone hears everyone (server sets it).
const FLAG_GLOBAL: int = 4
## Largest payload accepted (one 40 ms frame at 16 kHz, so a richer codec still fits).
const MAX_PAYLOAD: int = 640


static func make_up(seq: int, flags: int, payload: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray([MAGIC, flags & 0xFF, seq & 0xFF, (seq >> 8) & 0xFF])
	out.append_array(payload)
	return out


## {seq, flags, payload} or {} when malformed.
static func parse_up(data: PackedByteArray) -> Dictionary:
	if data.size() < UP_HEADER or data.size() > UP_HEADER + MAX_PAYLOAD or data[0] != MAGIC:
		return {}
	return {"seq": data[2] | (data[3] << 8), "flags": data[1], "payload": data.slice(UP_HEADER)}


static func make_down(speaker: int, seq: int, flags: int, payload: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray([MAGIC, flags & 0xFF, seq & 0xFF, (seq >> 8) & 0xFF, speaker & 0xFF, (speaker >> 8) & 0xFF])
	out.append_array(payload)
	return out


## {speaker, seq, flags, payload} or {} when malformed.
static func parse_down(data: PackedByteArray) -> Dictionary:
	if data.size() < DOWN_HEADER or data.size() > DOWN_HEADER + MAX_PAYLOAD or data[0] != MAGIC:
		return {}
	return {"seq": data[2] | (data[3] << 8), "flags": data[1], "speaker": data[4] | (data[5] << 8), "payload": data.slice(DOWN_HEADER)}


## Signed distance from sequence number `b` to `a`, with 16-bit wrap-around.
static func seq_diff(a: int, b: int) -> int:
	return ((a - b + 32768) & 0xFFFF) - 32768
