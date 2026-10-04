class_name IntentValidator
extends RefCounted
## Checks an intent is well-formed, allowed in the current phase, and within the rate limit.
## Game-specific checks (money, seat, limits) happen in the station logic.

## Intent type → phases in which it is allowed (absent = any phase).
const PHASES: Dictionary = {
	&"sit": [Phase.Id.CASINO, Phase.Id.PRE_MINIGAME, Phase.Id.LOBBY, Phase.Id.RESULTS],
	&"place_bet": [Phase.Id.CASINO, Phase.Id.PRE_MINIGAME],
	&"clear_bets": [Phase.Id.CASINO, Phase.Id.PRE_MINIGAME],
	&"action": [Phase.Id.CASINO, Phase.Id.PRE_MINIGAME],
	&"use_item": [Phase.Id.CASINO, Phase.Id.PRE_MINIGAME],
	&"submit_answer": [Phase.Id.MINIGAME],
	&"draft_pick": [Phase.Id.REWARDS],
	&"set_ready": [Phase.Id.LOBBY, Phase.Id.RESULTS],
	&"lobby_setting": [Phase.Id.LOBBY, Phase.Id.RESULTS],
}

var limiter: RateLimiter


func _init(per_second: float = Protocol.MAX_INTENTS_PER_SECOND) -> void:
	limiter = RateLimiter.new(per_second)


## &"" if acceptable, else the rejection reason.
func check(player: int, intent: Dictionary, phase: Phase.Id, now: float, known_player: bool) -> StringName:
	if not known_player:
		return &"unknown_player"
	if not Intents.validate(intent).is_empty():
		return &"malformed"
	if not limiter.allow(player, now):
		return &"rate_limited"
	var type: StringName = StringName(intent["type"])
	if PHASES.has(type) and not phase in PHASES[type]:
		return &"wrong_phase"
	return &""
