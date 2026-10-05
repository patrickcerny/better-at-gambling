class_name MusicMood
extends Node
## Keeps the music in step with the match: casino lounge jazz on the floor (and in the entrance
## lobby), the faster Last Call take once last call is announced, game-show jazz for the quiz and
## the reward draft, the warm results theme on the podium. Polls the client mirror so snapshots,
## late joins and "play again" land on the right mood without extra event wiring.

var state: ClientMatchState = null


func setup(p_state: ClientMatchState) -> void:
	state = p_state
	_apply()


## The mood for a phase (pure, tested).
static func mood_for(phase: Phase.Id, last_call: bool) -> StringName:
	match phase:
		Phase.Id.MINIGAME, Phase.Id.REWARDS:
			return &"quiz"
		Phase.Id.RESULTS:
			return &"results"
		Phase.Id.CASINO, Phase.Id.PRE_MINIGAME:
			return &"last_call" if last_call else &"casino"
	return &"casino"


func _process(_delta: float) -> void:
	_apply()


func _apply() -> void:
	if state != null:
		Audio.set_mood(mood_for(state.phase, state.last_call))
