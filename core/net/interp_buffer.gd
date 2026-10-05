class_name InterpBuffer
extends RefCounted
## Snapshot interpolation for one replicated entity (§4.1: remote avatars render 100 ms in the
## past). Holds timestamped value vectors; `sample(t)` interpolates between the two around `t`,
## holds the newest value past the end (with a short extrapolation), and the oldest before it.
## Values listed in `angle_indices` are interpolated as angles (shortest way round).

const MAX_SAMPLES: int = 32
const MAX_EXTRAPOLATION: float = 0.1

var angle_indices: PackedInt32Array = []

var _times: PackedFloat64Array = []
var _values: Array[PackedFloat32Array] = []


func _init(p_angle_indices: PackedInt32Array = PackedInt32Array()) -> void:
	angle_indices = p_angle_indices


## Adds a sample. Out-of-order or duplicate timestamps are dropped.
func push(t: float, v: PackedFloat32Array) -> void:
	if not _times.is_empty() and t <= _times[_times.size() - 1]:
		return
	_times.append(t)
	_values.append(v)
	if _times.size() > MAX_SAMPLES:
		_times = _times.slice(_times.size() - MAX_SAMPLES)
		_values = _values.slice(_values.size() - MAX_SAMPLES)


func is_empty() -> bool:
	return _times.is_empty()


func size() -> int:
	return _times.size()


## Time of the newest sample (-INF when empty).
func newest_time() -> float:
	return _times[_times.size() - 1] if not _times.is_empty() else -INF


## Drops everything (after a teleport, so we don't slide across the map).
func clear() -> void:
	_times.clear()
	_values.clear()


## Interpolated value at time `t`.
func sample(t: float) -> PackedFloat32Array:
	var n: int = _times.size()
	if n == 0:
		return PackedFloat32Array()
	if n == 1 or t <= _times[0]:
		return _values[0] if t <= _times[0] else _values[n - 1]
	if t >= _times[n - 1]:
		if n >= 2:
			var dt: float = _times[n - 1] - _times[n - 2]
			var ahead: float = minf(t - _times[n - 1], MAX_EXTRAPOLATION)
			if dt > 0.0 and ahead > 0.0:
				return _mix(_values[n - 2], _values[n - 1], 1.0 + ahead / dt)
		return _values[n - 1]
	var i: int = n - 2
	while i > 0 and _times[i] > t:
		i -= 1
	var span: float = _times[i + 1] - _times[i]
	var w: float = (t - _times[i]) / span if span > 0.0 else 1.0
	return _mix(_values[i], _values[i + 1], w)


func _mix(a: PackedFloat32Array, b: PackedFloat32Array, w: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(mini(a.size(), b.size()))
	for k: int in out.size():
		if k in angle_indices:
			out[k] = a[k] + wrapf(b[k] - a[k], -PI, PI) * w
		else:
			out[k] = lerpf(a[k], b[k], w)
	return out
