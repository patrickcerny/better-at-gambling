class_name MusicMood
extends Node
## Keeps the music in step with the match: casino lounge jazz on the floor (and in the entrance
## lobby), the faster Last Call take once last call is announced, game-show jazz for the quiz and
## the round results, the warm results theme on the podium. Polls the client mirror so snapshots,
## late joins and "play again" land on the right mood without extra event wiring.

var state: ClientMatchState = null
## A minigame stage that plays its own music (Last Seat's floor music, which has to stop dead on
## cue) sets this while it is up: the mood music fades out during the minigame.
static var stage_music: bool = false


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
		var mood: StringName = mood_for(state.phase, state.last_call)
		Audio.set_mood(&"" if stage_music and state.phase == Phase.Id.MINIGAME else mood)
