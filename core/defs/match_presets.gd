class_name MatchPresets
extends Resource
## Match length defaults and bounds (§2.1, Patrick's note #12): the host sets how many minigames a
## match has and how many minutes of gambling come before each one (and after the last).

@export var default_minigames: int = 5
@export var min_minigames: int = 1
@export var max_minigames: int = 10
@export var default_gamble_minutes: int = 3
@export var min_gamble_minutes: int = 1
@export var max_gamble_minutes: int = 6


## True if a lobby may pick this many minigames.
func is_valid_minigames(n: int) -> bool:
	return n >= min_minigames and n <= max_minigames


## True if a lobby may pick this many gambling minutes between minigames.
func is_valid_gamble_minutes(m: int) -> bool:
	return m >= min_gamble_minutes and m <= max_gamble_minutes
