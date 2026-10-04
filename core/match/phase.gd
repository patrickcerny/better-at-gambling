class_name Phase
extends RefCounted
## Match phases (§3.6).

enum Id { LOBBY, INTRO, CASINO, PRE_MINIGAME, MINIGAME, REWARDS, RESULTS }


## Name for logs and wire.
static func name_of(id: Id) -> StringName:
	return StringName(Id.keys()[id].to_lower())
