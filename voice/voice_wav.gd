class_name VoiceWav
extends RefCounted
## Minimal PCM WAV reader/writer for `--voice-test <wav>` and the headless voice tests: lets a
## recording (or a generated tone) stand in for the microphone.


## Reads a PCM 8/16-bit WAV as mono. Returns {rate: int, samples: PackedFloat32Array}, or {} when
## the file is missing or not plain PCM.
static func read(path: String) -> Dictionary:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.size() < 44 or bytes.slice(0, 4).get_string_from_ascii() != "RIFF" or bytes.slice(8, 12).get_string_from_ascii() != "WAVE":
		return {}
	var channels: int = 0
	var rate: int = 0
	var bits: int = 0
	var pos: int = 12
	while pos + 8 <= bytes.size():
		var id: String = bytes.slice(pos, pos + 4).get_string_from_ascii()
		var size: int = bytes.decode_u32(pos + 4)
		var body: int = pos + 8
		if id == "fmt " and size >= 16:
			if bytes.decode_u16(body) != 1:
				return {}  # not PCM
			channels = bytes.decode_u16(body + 2)
			rate = bytes.decode_u32(body + 4)
			bits = bytes.decode_u16(body + 14)
		elif id == "data" and channels > 0 and (bits == 8 or bits == 16):
			var step: int = (bits >> 3) * channels
			var n: int = floori(mini(size, bytes.size() - body) / float(step))
			var out := PackedFloat32Array()
			out.resize(n)
			for i: int in n:
				var sum: float = 0.0
				for c: int in channels:
					var at: int = body + i * step + c * (bits >> 3)
					sum += bytes.decode_s16(at) / 32768.0 if bits == 16 else (bytes[at] - 128) / 128.0
				out[i] = sum / channels
			return {"rate": rate, "samples": out}
		pos = body + size + (size & 1)
	return {}


## Writes mono 16-bit PCM.
static func write(path: String, samples: PackedFloat32Array, rate: int) -> Error:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i: int in samples.size():
		data.encode_s16(i * 2, clampi(roundi(samples[i] * 32767.0), -32768, 32767))
	var head := PackedByteArray()
	head.resize(44)
	head.encode_u32(0, 0x46464952)  # "RIFF"
	head.encode_u32(4, 36 + data.size())
	head.encode_u32(8, 0x45564157)  # "WAVE"
	head.encode_u32(12, 0x20746d66)  # "fmt "
	head.encode_u32(16, 16)
	head.encode_u16(20, 1)
	head.encode_u16(22, 1)
	head.encode_u32(24, rate)
	head.encode_u32(28, rate * 2)
	head.encode_u16(32, 2)
	head.encode_u16(34, 16)
	head.encode_u32(36, 0x61746164)  # "data"
	head.encode_u32(40, data.size())
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_buffer(head)
	f.store_buffer(data)
	f.close()
	return OK


## `seconds` of a sine tone at `hz`, amplitude `amp`.
static func tone(hz: float, seconds: float, rate: int, amp: float = 0.5) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(seconds * rate))
	for i: int in out.size():
		out[i] = sin(TAU * hz * i / rate) * amp
	return out
