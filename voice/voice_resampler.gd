class_name VoiceResampler
extends RefCounted
## Streaming rate converter for both voice directions. Down (capture: mix rate →
## `VoiceCodec.SAMPLE_RATE`): box-filter decimation, each output sample is the mean of the input
## samples it covers, which also takes the edge off aliasing; works for any ratio, including
## 44.1 kHz. Up (playback: 8 kHz → the output mix rate): linear interpolation between neighbouring
## input samples. Both keep their phase across calls, so a stream cut into frames of any size
## comes out the same as in one piece (no clicks at frame boundaries).

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
	if to_rate > from_rate:
		return _upsample(input)
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


## Output samples between the previous input sample (`_last`) and each new one, at positions
## `_phase / to_rate` of the way across (the phase is in units of `1 / to_rate` input samples, so
## 8 kHz → 48 kHz is exactly 6 outputs per input with no drift). Lags the input by one sample.
func _upsample(input: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(ceil(input.size() * to_rate / from_rate)) + 2)
	var n: int = 0
	for x: float in input:
		while _phase < to_rate:
			if n >= out.size():
				out.resize(n + 16)
			out[n] = _last + (x - _last) * (_phase / to_rate)
			n += 1
			_phase += from_rate
		_phase -= to_rate
		_last = x
	out.resize(n)
	return out
