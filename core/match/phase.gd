class_name Phase
extends RefCounted
## Match phases (§3.6). REGROUP: after the rewards everyone stands in the entrance hall for a few
## seconds before the doors open again (Patrick's note #10).

enum Id { LOBBY, INTRO, CASINO, PRE_MINIGAME, MINIGAME, REWARDS, REGROUP, RESULTS }


## Name for logs and wire.
static func name_of(id: Id) -> StringName:
	return StringName(Id.keys()[id].to_lower())
