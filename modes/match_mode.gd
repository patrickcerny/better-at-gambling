class_name MatchMode
extends RefCounted
## Party modes (Patrick: "Play minigames button so you can only play minigames with friends (also
## good for testing for me)"). The leader picks one in the lobby (`lobby_setting` key `mode`);
## Practice from the main menu is always CASINO (`SceneRouter.practice_settings`); `--mode` on the
## command line picks one for `--practice` and `--server`.
## - CASINO: the normal match, gambling segments with a minigame between each.
## - MINIGAMES: no casino at all: the chosen number of minigames back to back, each with its
##   briefing and its results (rewards), then the podium. Items are off (there is nowhere to use
##   them), so the placement cash is doubled like any items-off match.

const CASINO: StringName = &"casino"
const MINIGAMES: StringName = &"minigames"
const ALL: Array[StringName] = [CASINO, MINIGAMES]
const LABELS: Dictionary = {CASINO: "CASINO", MINIGAMES: "MINIGAMES ONLY"}


## A known mode, or CASINO for anything else.
static func normalize(mode: Variant) -> StringName:
	if typeof(mode) != TYPE_STRING and typeof(mode) != TYPE_STRING_NAME:
		return CASINO
	var m: StringName = StringName(mode)
	return m if m in ALL else CASINO


static func is_valid(mode: Variant) -> bool:
	return (typeof(mode) == TYPE_STRING or typeof(mode) == TYPE_STRING_NAME) and StringName(mode) in ALL


## True if these match/lobby settings ask for minigames only.
static func is_minigames_only(settings: Dictionary) -> bool:
	return normalize(settings.get("mode", CASINO)) == MINIGAMES


## Player-facing name.
static func label(mode: Variant) -> String:
	return str(LABELS.get(normalize(mode), "CASINO"))


## The registered minigames that `player_count` players are too few for (Practice shows a note).
static func needs_more_players(defs: Array, player_count: int) -> Array[MinigameDefinition]:
	var out: Array[MinigameDefinition] = []
	for d: Variant in defs:
		if d is MinigameDefinition and (d as MinigameDefinition).min_players > player_count:
			out.append(d)
	return out
