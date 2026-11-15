class_name AdpcmCodec
extends VoiceCodec
## IMA ADPCM, 4 bits per sample (0.9.32). At 16 kHz that is the same 8 KB/s per speaker the old
## 8 kHz μ-law took, but with twice the audio band (up to 8 kHz instead of 4: "s", "f" and "th"
## come through, voices stop sounding like a phone line).
##
## Every frame stands alone: a 4-byte header (first sample, step index) and then one nibble per
## sample, so a lost packet never garbles the frames after it. The starting step is chosen from the
## frame's first samples, so a loud frame does not have to ramp up from a tiny step.

const HEADER: int = 4

const STEPS: PackedInt32Array = [
	7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45, 50, 55, 60, 66, 73,
	80, 88, 97, 107, 118, 130, 143, 157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449,
	494, 544, 598, 658, 724, 796, 876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066, 2272,
	2499, 2749, 3024, 3327, 3660, 4026, 4428, 4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493,
	10442, 11487, 12635, 13899, 15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767,
]
const INDEX_STEP: PackedInt32Array = [-1, -1, -1, -1, 2, 4, 6, 8]
## Samples looked at to pick a frame's starting step.
const LOOKAHEAD: int = 8


## Bytes one frame of `samples` samples encodes to.
static func encoded_size(samples: int) -> int:
	return HEADER + (samples + 1) / 2


func encode(samples: PackedFloat32Array) -> PackedByteArray:
	var n: int = samples.size()
	var out := PackedByteArray()
	out.resize(encoded_size(n))
	if n == 0:
		return out
	var pcm := PackedInt32Array()
	pcm.resize(n)
	for i: int in n:
		pcm[i] = clampi(roundi(samples[i] * 32767.0), -32768, 32767)
	var predictor: int = pcm[0]
	var index: int = start_index(pcm)
	out.encode_s16(0, predictor)
	out[2] = index
	out[3] = 0
	var byte: int = 0
	for i: int in n:
		var step: int = STEPS[index]
		var diff: int = pcm[i] - predictor
		var code: int = 0
		if diff < 0:
			code = 8
			diff = -diff
		var vpdiff: int = step >> 3
		if diff >= step:
			code |= 4
			diff -= step
			vpdiff += step
		step >>= 1
		if diff >= step:
			code |= 2
			diff -= step
			vpdiff += step
		step >>= 1
		if diff >= step:
			code |= 1
			vpdiff += step
		predictor = clampi(predictor - vpdiff if (code & 8) != 0 else predictor + vpdiff, -32768, 32767)
		index = clampi(index + INDEX_STEP[code & 7], 0, 88)
		if (i & 1) == 0:
			byte = code
		else:
			out[HEADER + (i >> 1)] = byte | (code << 4)
	if (n & 1) == 1:
		out[HEADER + (n >> 1)] = byte
	return out


func decode(bytes: PackedByteArray) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if bytes.size() < HEADER:
		return out
	var n: int = (bytes.size() - HEADER) * 2
	out.resize(n)
	var predictor: int = bytes.decode_s16(0)
	var index: int = clampi(bytes[2], 0, 88)
	for i: int in n:
		var b: int = bytes[HEADER + (i >> 1)]
		var code: int = (b & 0x0F) if (i & 1) == 0 else (b >> 4)
		var step: int = STEPS[index]
		var vpdiff: int = step >> 3
		if (code & 4) != 0:
			vpdiff += step
		if (code & 2) != 0:
			vpdiff += step >> 1
		if (code & 1) != 0:
			vpdiff += step >> 2
		predictor = clampi(predictor - vpdiff if (code & 8) != 0 else predictor + vpdiff, -32768, 32767)
		index = clampi(index + INDEX_STEP[code & 7], 0, 88)
		out[i] = predictor / 32768.0
	return out


## The step index a frame starts at: the smallest step at least as large as the mean change
## between its first `LOOKAHEAD` samples.
static func start_index(pcm: PackedInt32Array) -> int:
	var count: int = mini(LOOKAHEAD, pcm.size() - 1)
	if count <= 0:
		return 0
	var sum: int = 0
	for i: int in count:
		sum += absi(pcm[i + 1] - pcm[i])
	var mean: int = sum / count
	for i: int in STEPS.size():
		if STEPS[i] >= mean:
			return i
	return 88
