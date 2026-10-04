class_name MatchPresets
extends Resource
## Durations and their minigame counts (§2.1). The only place this table lives.

## Casino minutes → number of minigames.
@export var minigames_by_duration: Dictionary = {5: 2, 10: 3, 15: 4, 30: 7}
@export var default_duration: int = 10


## Allowed durations in minutes, ascending.
func durations() -> Array[int]:
	var out: Array[int] = []
	for d: int in minigames_by_duration.keys():
		out.append(d)
	out.sort()
	return out
