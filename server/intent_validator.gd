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
	&"rps_pick": [Phase.Id.CASINO, Phase.Id.PRE_MINIGAME],
	&"shop_buy": [Phase.Id.CASINO, Phase.Id.PRE_MINIGAME],
	&"odd_jobs_press": [Phase.Id.CASINO, Phase.Id.PRE_MINIGAME],
	&"tip_dealer": [Phase.Id.CASINO, Phase.Id.PRE_MINIGAME],
	&"discard_item": [Phase.Id.CASINO, Phase.Id.PRE_MINIGAME, Phase.Id.MINIGAME, Phase.Id.REWARDS, Phase.Id.REGROUP],
	&"submit_answer": [Phase.Id.MINIGAME],
	&"bust_or_bank_action": [Phase.Id.MINIGAME],
	&"vote_race_vote": [Phase.Id.MINIGAME],
	&"find_the_lady_pick": [Phase.Id.MINIGAME],
	&"forehead_poker_action": [Phase.Id.MINIGAME],
	&"spy_clue": [Phase.Id.MINIGAME], &"spy_call_vote": [Phase.Id.MINIGAME], &"spy_vote": [Phase.Id.MINIGAME],
	&"split_or_steal_pick": [Phase.Id.MINIGAME],
	&"minigame_action": [Phase.Id.MINIGAME],
	&"set_ready": [Phase.Id.LOBBY, Phase.Id.RESULTS],
	&"lobby_setting": [Phase.Id.LOBBY, Phase.Id.RESULTS],
	&"set_skin": [Phase.Id.LOBBY, Phase.Id.RESULTS],
	&"return_to_lobby": [Phase.Id.RESULTS],
	&"megaphone": [Phase.Id.CASINO, Phase.Id.PRE_MINIGAME],
}

## Intents the limiter lets through at any rate: the Odd Jobs button is a clicking contest
## (Patrick: "as fast clicking as possible and no rate limit"); its bar events stay throttled.
const UNLIMITED: Array[StringName] = [&"odd_jobs_press"]

var limiter: RateLimiter


func _init(per_second: float = Protocol.MAX_INTENTS_PER_SECOND) -> void:
	limiter = RateLimiter.new(per_second)


## &"" if acceptable, else the rejection reason.
func check(player: int, intent: Dictionary, phase: Phase.Id, now: float, known_player: bool) -> StringName:
	if not known_player:
		return &"unknown_player"
	if not Intents.validate(intent).is_empty():
		return &"malformed"
	var type: StringName = StringName(intent["type"])
	if not type in UNLIMITED and not limiter.allow(player, now):
		return &"rate_limited"
	if PHASES.has(type) and not phase in PHASES[type]:
		return &"wrong_phase"
	return &""
