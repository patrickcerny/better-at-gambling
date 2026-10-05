class_name VoiceResampler
extends RefCounted
## Streaming rate converter for the capture path (mix rate → `VoiceCodec.SAMPLE_RATE`). Box-filter
## decimation: each output sample is the mean of the input samples it covers, which also takes
## the edge off aliasing. Works for any ratio, including 44.1 kHz; upsampling repeats samples.

var from_rate: float
var to_rate: float
var _phase: float = 0.0
var _acc: float = 0.0
var _count: int = 0
var _last: float = 0.0


func _init(p_from: float, p_to: float = 8000.0) -> void:
	from_rate = maxf(p_from, 1.0)
	to_rate = maxf(p_to, 1.0)


func process(input: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(ceil(input.size() * to_rate / from_rate)) + 2)
	var n: int = 0
	for x: float in input:
		_acc += x
		_count += 1
		_phase += to_rate
		while _phase >= from_rate:
			_phase -= from_rate
			if _count > 0:
				_last = _acc / _count
				_acc = 0.0
				_count = 0
			if n >= out.size():
				out.resize(n + 16)
			out[n] = _last
			n += 1
	out.resize(n)
	return out
