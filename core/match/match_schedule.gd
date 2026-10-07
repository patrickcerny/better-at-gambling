class_name MatchSchedule
extends RefCounted
## Casino-time schedule (§2.1, Patrick's note #12): the host picks a number of minigames and the
## gambling time between them. Segments = minigames + 1 (a last gambling stretch follows the final
## minigame; Last Call is its final `last_call_seconds`), duration = gamble_s × (minigames + 1).

var duration_s: float
var minigames: int
var segment_s: float
var last_call_s: float


func _init(p_minigames: int, gamble_s: float, last_call_seconds: float = 60.0) -> void:
	minigames = maxi(p_minigames, 0)
	segment_s = maxf(gamble_s, 1.0)
	duration_s = segment_s * float(minigames + 1)
	last_call_s = last_call_seconds


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
