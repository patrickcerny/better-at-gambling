class_name Cosmetics
extends RefCounted
## Player looks (§2.2, docs/GDD.md "Cosmetics shop"). The bean is the only body (the character
## skins were removed in 0.9.16); what players choose is its colour.
## - The slot colour (`PlayerState.color_index`, 0 .. SLOT_COLORS-1): one of the 8 colourblind-safe
##   colours, handed out by the server (first free), unique per player. It marks the player on the
##   HUD, the name tags and their ready pedestal.
## - The bean colour (`PlayerState.bean_color`, 0 .. COLOR_COUNT-1, `Palette.player_color`): what
##   the bean wears. The player's preferred colour from their profile (sent in the hello, changed
##   with the `set_color` intent from the pedestal's colour panel). Rule (`bean_color_for`): the
##   wish wins when no other bean wears it; else the slot colour; if even that is worn, the first
##   colour nobody wears. Two beans never share a colour.
## The server checks the index only: which colours a player owns lives in their local profile
## (`PlayerProfile`, no accounts), so the client offers owned colours only.

## Every bean colour: the 8 free ones, then the ones bought with Coins.
const COLOR_COUNT: int = 16
## The free colours the server hands out as slot colours.
const SLOT_COLORS: int = 8


static func is_valid_color(index: int) -> bool:
	return index >= 0 and index < COLOR_COUNT


static func is_slot_color(index: int) -> bool:
	return index >= 0 and index < SLOT_COLORS


## The first slot colour not in `taken` (0 when all are).
static func free_slot(taken: Array[int]) -> int:
	for c: int in SLOT_COLORS:
		if not c in taken:
			return c
	return 0


## The bean colour a player gets: `wanted` when valid and no other bean wears it (`worn`), else
## their `slot` colour when free, else the first colour nobody wears.
static func bean_color_for(wanted: int, slot: int, worn: Array[int]) -> int:
	if is_valid_color(wanted) and not wanted in worn:
		return wanted
	if is_valid_color(slot) and not slot in worn:
		return slot
	for c: int in COLOR_COUNT:
		if not c in worn:
			return c
	return slot
