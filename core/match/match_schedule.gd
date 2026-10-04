class_name MatchSchedule
extends RefCounted
## Casino-time schedule for a match duration (§2.1): segment = duration / (minigames + 1),
## quizzes at each segment boundary, Last Call in the final `last_call_seconds`.

var duration_s: float
var minigames: int
var segment_s: float
var last_call_s: float


func _init(duration_minutes: int, presets: MatchPresets, last_call_seconds: float = 60.0) -> void:
	duration_s = duration_minutes * 60.0
	minigames = int(presets.minigames_by_duration.get(duration_minutes, 0))
	segment_s = duration_s / float(minigames + 1)
	last_call_s = last_call_seconds


## True if the preset table knows this duration.
static func is_valid_duration(duration_minutes: int, presets: MatchPresets) -> bool:
	return presets.minigames_by_duration.has(duration_minutes)


## Casino times (seconds) at which minigames start.
func minigame_times() -> Array[float]:
	var out: Array[float] = []
	for i: int in range(1, minigames + 1):
		out.append(segment_s * i)
	return out


## Number of casino segments.
func segments() -> int:
	return minigames + 1


## Segment index (0-based) for a casino time.
func segment_index(casino_time: float) -> int:
	return clampi(int(floor((casino_time + 0.0001) / segment_s)), 0, minigames)


## Casino time at which segment `i` ends.
func segment_end(i: int) -> float:
	return segment_s * (i + 1)


## True during the final Last Call window.
func is_last_call(casino_time: float) -> bool:
	return casino_time >= duration_s - last_call_s and casino_time < duration_s


## True once casino time is used up.
func is_over(casino_time: float) -> bool:
	return casino_time >= duration_s - 0.0001
