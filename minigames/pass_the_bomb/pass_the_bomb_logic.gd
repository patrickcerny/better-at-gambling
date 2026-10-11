class_name PassTheBombLogic
extends WalkableLogicBase
## "Pass the Bomb" (MINIGAME_IDEAS #14), the first walkable minigame, in the vault arena. The
## server hands a lit bomb to a random player; the holder passes it by tagging (the action button)
## another player in reach in front of them. The bomb jumps at once, but the new holder can't hand
## it straight back for `NO_RETURN_SECONDS`. The fuse is hidden: a random 8-20 s per bomb that only
## lives here (never in a state or event). When it runs out the holder is blown out of the arena
## (knocked down, then to the gallery) and a new bomb starts with the rest after `NEXT_BOMB_DELAY`.
## Last one standing wins; the ranking is reverse elimination order. After `CAP_SECONDS` the
## survivors share first.
##
## The tick getting faster is public (it follows the bomb's age, which says nothing exact about the
## fuse), and `pass_the_bomb_hiss` warns that it is close at a random 1.5-3.5 s before the bang.

enum State { WAITING, LIVE, DONE }

const FUSE_MIN: float = 8.0
const FUSE_MAX: float = 20.0
## Centre-to-centre reach of a tag (two beans touching is 0.84 m), in front like a shove.
const TAG_REACH: float = 1.6
## The new holder can't tag the one who just passed it to them for this long.
const NO_RETURN_SECONDS: float = 0.5
## Seconds between a bang and the next bomb (and before the first one once the game goes).
const NEXT_BOMB_DELAY: float = 2.0
const FIRST_BOMB_DELAY: float = 1.0
## The whole game is capped: the survivors then share first place.
const CAP_SECONDS: float = 150.0
## Knockdown (ragdoll) of the blown-up holder before they walk to the gallery.
const BLAST_KNOCKDOWN: float = 2.0
## The hiss comes this long (random in the range) before the bang.
const HISS_MIN: float = 1.5
const HISS_MAX: float = 3.5
## Seconds the last bang stays on screen before the ranking.
const END_HOLD: float = 2.5

var state: State = State.WAITING
## Game clock since the start (after the briefing), capped at `CAP_SECONDS`.
var clock: float = 0.0
var holder: int = -1
## Counts bombs (ids for events).
var bomb: int = 0
## Seconds since the current bomb was lit (public: drives the tick speed).
var bomb_age: float = 0.0
## Who passed it last and until when (game clock) the holder can't give it back to them.
var passed_by: int = -1
var no_return_until: float = -INF
## Seconds until the next bomb (WAITING) or the end (DONE hold).
var wait_left: float = FIRST_BOMB_DELAY
## Passes per player (for the feed and fun stats).
var passes: Dictionary[int, int] = {}

## SECRET: seconds left on the fuse and when the hiss goes. Never in a state or an event.
var _fuse_left: float = 0.0
var _hiss_at: float = 0.0
var _hissed: bool = false


func room_layout() -> Dictionary:
	return VaultArena.layout()


func _on_room_setup(_context: Dictionary) -> void:
	id = &"pass_the_bomb"
	for p: int in players:
		passes[p] = 0


func tick(delta: float, _now: float) -> void:
	if finished:
		return
	if state == State.DONE:
		wait_left -= delta
		if wait_left <= 0.0:
			_finish()
		return
	clock += delta
	if clock >= CAP_SECONDS:
		clock = CAP_SECONDS
		_end_game(&"time")
		return
	match state:
		State.WAITING:
			wait_left -= delta
			if wait_left <= 0.0:
				_new_bomb()
		State.LIVE:
			bomb_age += delta
			_fuse_left -= delta
			if not _hissed and _fuse_left <= _hiss_at:
				_hissed = true
				events.append(GameEvents.make(&"pass_the_bomb_hiss", {"bomb": bomb, "holder": holder}))
			if _fuse_left <= 0.0:
				_explode()


## The action button: `kind` "tag" passes the bomb to the player in reach (the hint first).
func _on_action(player: int, kind: StringName, hint: int, _now: float) -> Dictionary:
	if kind != &"tag":
		return StationLogicBase.fail(&"bad_value")
	if state != State.LIVE:
		return StationLogicBase.fail(&"no_bomb")
	if player != holder:
		return StationLogicBase.fail(&"not_holder")
	# The one who just gave it to us is off limits for a moment: anyone else in reach is fair.
	var exclude: Array[int] = []
	if passed_by >= 0 and clock < no_return_until:
		exclude.append(passed_by)
	var target: int = pick_target(player, hint, TAG_REACH, exclude)
	if target < 0:
		return StationLogicBase.fail(&"no_return" if not exclude.is_empty() and pick_target(player, hint, TAG_REACH) >= 0 else &"no_target")
	_pass(player, target)
	return {"ok": true, "error": &"", "target": target}


func _pass(from: int, to: int) -> void:
	holder = to
	passed_by = from
	no_return_until = clock + NO_RETURN_SECONDS
	passes[from] = passes.get(from, 0) + 1
	events.append(GameEvents.make(&"pass_the_bomb_passed", {"bomb": bomb, "from": from, "to": to}))


func _new_bomb() -> void:
	if alive.size() < 2:
		_end_game(&"last_standing")
		return
	bomb += 1
	holder = alive[rng.range_int(0, alive.size() - 1)]
	passed_by = -1
	no_return_until = -INF
	bomb_age = 0.0
	_fuse_left = rng.range_float(FUSE_MIN, FUSE_MAX)
	_hiss_at = rng.range_float(HISS_MIN, HISS_MAX)
	_hissed = false
	state = State.LIVE
	events.append(GameEvents.make(&"pass_the_bomb_new", {"bomb": bomb, "holder": holder, "alive": alive.duplicate()}))


func _explode() -> void:
	var victim: int = holder
	var pos: Vector3 = world.get_position(victim) if world != null else Vector3.ZERO
	holder = -1
	state = State.WAITING
	wait_left = NEXT_BOMB_DELAY
	_fuse_left = 0.0
	events.append(GameEvents.make(&"pass_the_bomb_exploded", {"bomb": bomb, "player": victim, "pos": Serializer.vec3(pos), "age": snappedf(bomb_age, 0.01)}))
	eliminate([victim], &"bomb", BLAST_KNOCKDOWN)
	if alive.size() < 2:
		_end_game(&"last_standing")


## The holder left: their bomb goes with them (no bang); the rest get a new bomb shortly.
func remove_player(player: int) -> void:
	var was_holder: bool = player == holder and state == State.LIVE
	super.remove_player(player)
	passes.erase(player)
	if finished or state == State.DONE:
		return
	if was_holder:
		holder = -1
		state = State.WAITING
		wait_left = NEXT_BOMB_DELAY
		_fuse_left = 0.0
		events.append(GameEvents.make(&"pass_the_bomb_fizzled", {"bomb": bomb, "player": player}))
	if alive.size() < 2:
		_end_game(&"last_standing")


func _end_game(reason: StringName) -> void:
	if state == State.DONE:
		return
	state = State.DONE
	holder = -1
	_fuse_left = 0.0
	wait_left = END_HOLD
	events.append(GameEvents.make(&"pass_the_bomb_over", {"reason": reason, "winners": alive.duplicate(), "ranking": ranking()}))


func _finish() -> void:
	finished = true
	events.append(GameEvents.make(&"pass_the_bomb_finished", {"ranking": ranking()}))


func get_public_state() -> Dictionary:
	var st: Dictionary = walkable_state()
	st["state"] = String(State.keys()[state]).to_lower()
	st["holder"] = holder
	st["bomb"] = bomb
	st["bomb_age"] = snappedf(bomb_age, 0.1)
	st["clock"] = snappedf(clock, 0.01)
	st["cap"] = CAP_SECONDS
	st["passes"] = passes.duplicate()
	if finished or state == State.DONE:
		st["ranking"] = ranking()
	return st


func private_state(player: int) -> Dictionary:
	return {
		"holder": player == holder,
		"alive": player in alive,
		"no_return": passed_by if player == holder and clock < no_return_until else -1,
	}
