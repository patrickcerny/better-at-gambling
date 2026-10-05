class_name Cosmetics
extends RefCounted
## Player looks (§2.2): 8 fixed, colorblind-safe player colors (see `Palette.player_color`;
## assigned by the server, no picker) and character skins. Purely visual; validated by the server.
## The skin models themselves live client-side in `SkinLibrary`.

const COLOR_COUNT: int = 8
const SKINS: Array[StringName] = [&"bean", &"wizard", &"business", &"warrior", &"king", &"regular", &"swat"]
const SKIN_NAMES: Dictionary = {
	&"bean": "Bean", &"wizard": "Wizard", &"business": "Businessman", &"warrior": "Warrior",
	&"king": "King", &"regular": "Regular Guy", &"swat": "SWAT",
}


static func is_valid_skin(skin: StringName) -> bool:
	return skin in SKINS


static func is_valid_color(index: int) -> bool:
	return index >= 0 and index < COLOR_COUNT
