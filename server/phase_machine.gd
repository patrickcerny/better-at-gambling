class_name PhaseMachine
extends RefCounted
## Drives LOBBY → INTRO → CASINO ⇄ (PRE_MINIGAME → MINIGAME → REWARDS) → RESULTS (§3.6).
## Casino time only advances in CASINO. Pure: the MatchServer feeds `advance(delta)` and reacts to
## the returned transitions.

signal phase_changed(from: Phase.Id, to: Phase.Id)

const INTRO_SECONDS: float = 3.0
const PRE_MINIGAME_SECONDS: float = 10.0

var phase: Phase.Id = Phase.Id.LOBBY
var schedule: MatchSchedule
var casino_time: float = 0.0
## Seconds left in the current timed phase (intro, warning).
var phase_timer: float = 0.0
var minigames_done: int = 0
var last_call_announced: bool = false
## Set by the server while a minigame or reward phase is running; the machine waits for it.
var waiting_external: bool = false


func _init(p_schedule: MatchSchedule) -> void:
	schedule = p_schedule


## Starts the match: LOBBY → INTRO.
func start() -> void:
	_go(Phase.Id.INTRO)
	phase_timer = INTRO_SECONDS


## Advances time. Returns a list of notifications: &"last_call", &"segment_ended", &"minigame_due",
## &"minigame_started", &"rewards_started", &"casino_resumed", &"match_over".
func advance(delta: float) -> Array[StringName]:
	var out: Array[StringName] = []
	match phase:
		Phase.Id.INTRO:
			phase_timer -= delta
			if phase_timer <= 0.0:
				_go(Phase.Id.CASINO)
		Phase.Id.CASINO:
			casino_time += delta
			if not last_call_announced and schedule.is_last_call(casino_time):
				last_call_announced = true
				out.append(&"last_call")
			if schedule.is_over(casino_time):
				casino_time = schedule.duration_s
				out.append(&"segment_ended")
				_go(Phase.Id.RESULTS)
				out.append(&"match_over")
			elif minigames_done < schedule.minigames and casino_time >= schedule.minigame_times()[minigames_done] - PRE_MINIGAME_SECONDS:
				_go(Phase.Id.PRE_MINIGAME)
				phase_timer = schedule.minigame_times()[minigames_done] - casino_time
				out.append(&"minigame_due")
		Phase.Id.PRE_MINIGAME:
			# Casino keeps running during the warning so the segment ends exactly on schedule.
			var step: float = minf(delta, phase_timer)
			casino_time += step
			phase_timer -= delta
			if phase_timer <= 0.0:
				out.append(&"segment_ended")
				_go(Phase.Id.MINIGAME)
				waiting_external = true
				out.append(&"minigame_started")
		Phase.Id.MINIGAME, Phase.Id.REWARDS:
			pass  # waits for minigame_finished / rewards_finished
	return out


## Called by the server when the minigame produced its ranking.
func minigame_finished() -> void:
	if phase != Phase.Id.MINIGAME:
		return
	minigames_done += 1
	_go(Phase.Id.REWARDS)


## Called by the server when the reward draft is over.
func rewards_finished() -> void:
	if phase != Phase.Id.REWARDS:
		return
	waiting_external = false
	_go(Phase.Id.CASINO)


## Current casino segment index.
func segment_index() -> int:
	return minigames_done


## Casino seconds remaining.
func time_left() -> float:
	return maxf(schedule.duration_s - casino_time, 0.0)


## Seconds until the next minigame (INF if none).
func next_minigame_in() -> float:
	if minigames_done >= schedule.minigames:
		return INF
	return maxf(schedule.minigame_times()[minigames_done] - casino_time, 0.0)


func _go(to: Phase.Id) -> void:
	var from: Phase.Id = phase
	phase = to
	phase_changed.emit(from, to)
