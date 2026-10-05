class_name MulawCodec
extends VoiceCodec
## G.711 μ-law: one byte per sample, ~14-bit dynamic range, within ~3 % of the signal (the
## quantisation step grows with the amplitude). At 8 kHz that is 8 KB/s per active speaker.

const BIAS: int = 0x84
const CLIP: int = 32635

## μ-law byte → sample, built once per codec.
var _table: PackedFloat32Array = PackedFloat32Array()


func _init() -> void:
	_table.resize(256)
	for u: int in 256:
		_table[u] = decode_sample(u) / 32768.0


func encode(samples: PackedFloat32Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(samples.size())
	for i: int in samples.size():
		out[i] = encode_sample(roundi(clampf(samples[i], -1.0, 1.0) * 32767.0))
	return out


func decode(bytes: PackedByteArray) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(bytes.size())
	for i: int in bytes.size():
		out[i] = _table[bytes[i]]
	return out


## 16-bit linear sample → μ-law byte.
static func encode_sample(sample: int) -> int:
	var sign: int = 0
	var s: int = sample
	if s < 0:
		s = -s
		sign = 0x80
	s = mini(s, CLIP) + BIAS
	var exponent: int = 7
	var mask: int = 0x4000
	while exponent > 0 and (s & mask) == 0:
		exponent -= 1
		mask >>= 1
	var mantissa: int = (s >> (exponent + 3)) & 0x0F
	return ~(sign | (exponent << 4) | mantissa) & 0xFF


## μ-law byte → 16-bit linear sample (the middle of the quantisation step).
static func decode_sample(byte: int) -> int:
	var u: int = ~byte & 0xFF
	var exponent: int = (u >> 4) & 0x07
	var mantissa: int = u & 0x0F
	var s: int = (((mantissa << 3) + BIAS) << exponent) - BIAS
	return -s if (u & 0x80) != 0 else s
