class_name Cosmetics
extends RefCounted
## Lobby cosmetics (§2.2): 8 colorblind-safe player colors (see `Palette.player_color`) and
## 6 placeholder hats. Purely visual; validated by the server.

const COLOR_COUNT: int = 8
const HATS: Array[StringName] = [&"none", &"top_hat", &"cowboy", &"party", &"beanie", &"bowler"]
const HAT_NAMES: Dictionary = {
	&"none": "No hat", &"top_hat": "Top hat", &"cowboy": "Cowboy", &"party": "Party cone",
	&"beanie": "Beanie", &"bowler": "Bowler",
}


static func is_valid_hat(hat: StringName) -> bool:
	return hat in HATS


static func is_valid_color(index: int) -> bool:
	return index >= 0 and index < COLOR_COUNT
