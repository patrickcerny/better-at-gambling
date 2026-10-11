class_name LastSeatLogic
extends WalkableLogicBase
## "Last Seat at the Table" (MINIGAME_IDEAS #5), musical chairs in the parlor (`ParlorRoom`).
##
## Each round:
## 1. MUSIC: the floor music plays while the beans wander round the blackjack table. The stools are
##    tucked under the table and can't be claimed. The server picks when the music stops
##    (`MUSIC_MIN`..`MUSIC_MAX` s from the seeded rng) and never tells the clients in advance.
## 2. SCRAMBLE: the music stops and one stool fewer than beans still in shoots out from under the
##    table at server-picked spots round the table. Everyone runs for one. Shoving is allowed; a
##    seated bean can't be shoved (`is_untouchable`) or grabbed (grab is off in this game).
## 3. When every stool is taken, or after `GRACE` s, whoever is still standing is out together
##    (`eliminate`, a shared place) and goes to the gallery. RESULT holds the outcome for a moment,
##    then the seated get up and the next round starts with a stool fewer.
## The last bean seated wins (a 2-player game is one round with one stool). Ranking = elimination
## order (`elimination_ranking`).
##
## Claiming a seat is the server's call, from its own positions:
## - the action button: `minigame_action {kind: "sit", target?}` (target = stool index hint) claims
##   the free stool within `SIT_REACH` of the bean (the hint first, with lag slack, else the
##   nearest). Refused while the music plays (`music_playing`), when already seated, or when every
##   stool in reach is taken (`taken`) or none is near (`no_stool`);
## - touching: a standing bean whose centre comes within `SIT_TOUCH` of a free stool sits down
##   by itself (checked every tick, nearest first). Running onto a stool is how most seats are won;
##   E is the "I'm right next to it" shortcut.
## A seated bean is pinned: `clamp_position` returns the seat (the server snaps any move back), the
## stage poses the bean on the stool. First claim wins: a taken stool is never handed over.

enum State { MUSIC, SCRAMBLE, RESULT, DONE }

const MUSIC_MIN: float = 6.0
const MUSIC_MAX: float = 14.0
## Seconds after the stop before the ones still standing are out anyway.
const GRACE: float = 10.0
## Seconds the round's outcome stays up before the next round.
const RESULT_HOLD: float = 3.0
## Seconds the winner stays on the last stool before the ranking.
const END_HOLD: float = 3.5
## Action-button claim reach (bean centre to stool centre, flat), and the touch auto-claim.
const SIT_REACH: float = 1.5
const SIT_TOUCH: float = 0.6
## A seated bean's reported position may wander this far from the seat before it is snapped back.
const PIN_SLACK: float = 0.4

var state: State = State.MUSIC
var round_no: int = 0
## How long this round's music plays (server only) and how much is left.
var music_length: float = 0.0
var music_left: float = 0.0
var grace_left: float = 0.0
var wait_left: float = 0.0
## This round's stools (world floor positions), set when the music stops.
var stools: Array[Vector3] = []
## How many stools this round has (shown during the music before they come out).
var stool_count: int = 0
## player → stool index, stool index → player.
var seat_of: Dictionary[int, int] = {}
var sitter: Dictionary[int, int] = {}
var winner: int = -1
var _announced: bool = false


func room_layout() -> Dictionary:
	return ParlorRoom.layout()


func _on_room_setup(_context: Dictionary) -> void:
	id = &"last_seat"


## Grabbing is off: this is a shoving game, and a carried bean can't run for a stool.
func blocked_intents() -> Array[StringName]:
	return [&"grab"]


func tick(delta: float, _now: float) -> void:
	if finished:
		return
	if not _announced:
		# The stage only exists after the curtain: the first round starts (and says so) on the
		# first tick, and the state carries all of it for anyone later.
		_announced = true
		events.append(GameEvents.make(&"last_seat_begin", {"players": alive.duplicate()}))
		_start_round()
		return
	match state:
		State.MUSIC:
			music_left -= delta
			if music_left <= 0.0:
				_stop_music()
		State.SCRAMBLE:
			grace_left -= delta
			_touch_claims()
			if _all_taken() or grace_left <= 0.0:
				_end_round()
		State.RESULT:
			wait_left -= delta
			if wait_left <= 0.0:
				_start_round()
		State.DONE:
			wait_left -= delta
			if wait_left <= 0.0:
				_finish()


func is_seated(player: int) -> bool:
	return seat_of.has(player)


## Seated beans can't be shoved or grabbed (the server treats them like casino-seated players).
func is_untouchable(player: int) -> bool:
	return not finished and seat_of.has(player) and player in alive


## A seated bean stays on its seat (small drift allowed); everyone else as in every walkable room.
func clamp_position(player: int, pos: Vector3) -> Vector3:
	if is_untouchable(player) and player in players:
		var pin: Vector3 = seat_position(seat_of[player])
		return pos if pos.distance_to(pin) <= PIN_SLACK else pin
	return super.clamp_position(player, pos)


## Where a bean sits on stool `i` (the avatar's origin on the seat).
func seat_position(i: int) -> Vector3:
	return stools[i] + Vector3(0, ParlorRoom.SEAT_HEIGHT, 0) if i >= 0 and i < stools.size() else ROOM_ORIGIN


func free_stools() -> int:
	return stools.size() - sitter.size()


# --- Rounds -------------------------------------------------------------------------------------

func _start_round() -> void:
	_release_all()
	round_no += 1
	state = State.MUSIC
	stools.clear()
	sitter.clear()
	stool_count = maxi(alive.size() - 1, 1)
	music_length = rng.range_float(MUSIC_MIN, MUSIC_MAX)
	music_left = music_length
	events.append(GameEvents.make(&"last_seat_round", {"round": round_no, "stools": stool_count, "alive": alive.duplicate()}))


func _stop_music() -> void:
	state = State.SCRAMBLE
	grace_left = GRACE
	stool_count = maxi(alive.size() - 1, 1)  # somebody may have left during the music
	stools = ParlorRoom.stool_ring(stool_count, rng.unit() * TAU)
	events.append(GameEvents.make(&"last_seat_stop", {"round": round_no, "stools": _stools_wire(), "grace": GRACE}))


## Standing beans touching a free stool sit down, nearest first.
func _touch_claims() -> void:
	if world == null:
		return
	var hits: Array = []
	for p: int in alive:
		if seat_of.has(p) or not world.positions.has(p):
			continue
		for i: int in stools.size():
			if sitter.has(i):
				continue
			var d: float = _flat(world.get_position(p), stools[i])
			if d <= SIT_TOUCH:
				hits.append([d, p, i])
	hits.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for h: Array in hits:
		if not seat_of.has(int(h[1])) and not sitter.has(int(h[2])):
			_claim(int(h[1]), int(h[2]), &"touch")


func _all_taken() -> bool:
	return not stools.is_empty() and (sitter.size() >= stools.size() or sitter.size() >= alive.size())


func _end_round() -> void:
	var standing: Array[int] = []
	for p: int in alive:
		if not seat_of.has(p):
			standing.append(p)
	var seats: Dictionary = {}
	for p: int in seat_of:
		seats[p] = seat_of[p]
	events.append(GameEvents.make(&"last_seat_round_over", {"round": round_no, "out": standing, "seated": seats}))
	if not standing.is_empty():
		eliminate(standing, &"no_seat")
	if alive.size() <= 1:
		_end_game()
	else:
		state = State.RESULT
		wait_left = RESULT_HOLD


## The seated get up next to their stool (the server moves them; the stage stands them up).
func _release_all() -> void:
	for p: int in seat_of:
		if p in alive and p in players:
			pending_moves[p] = ParlorRoom.stand_spot(stools[seat_of[p]]) if seat_of[p] < stools.size() else spawn_for(p)
	seat_of.clear()
	sitter.clear()


# --- Claims -------------------------------------------------------------------------------------

func _on_action(player: int, kind: StringName, hint: int, _now: float) -> Dictionary:
	if kind != &"sit":
		return StationLogicBase.fail(&"bad_value")
	if state == State.MUSIC:
		return StationLogicBase.fail(&"music_playing")
	if state != State.SCRAMBLE:
		return StationLogicBase.fail(&"too_late")
	if seat_of.has(player):
		return StationLogicBase.fail(&"seated")
	if world == null or not world.positions.has(player):
		return StationLogicBase.fail(&"no_stool")
	var at: Vector3 = world.get_position(player)
	var taken_near: bool = false
	if hint >= 0 and hint < stools.size() and _flat(at, stools[hint]) <= SIT_REACH + InteractionRules.LAG_SLACK:
		if not sitter.has(hint):
			_claim(player, hint, &"action")
			return {"ok": true, "error": &"", "stool": hint}
		taken_near = true
	var best: int = -1
	var best_d: float = SIT_REACH
	for i: int in stools.size():
		var d: float = _flat(at, stools[i])
		if d > SIT_REACH:
			continue
		if sitter.has(i):
			taken_near = true
		elif d <= best_d:
			best_d = d
			best = i
	if best < 0:
		return StationLogicBase.fail(&"taken" if taken_near else &"no_stool")
	_claim(player, best, &"action")
	return {"ok": true, "error": &"", "stool": best}


func _claim(player: int, stool: int, how: StringName) -> void:
	seat_of[player] = stool
	sitter[stool] = player
	pending_moves.erase(player)
	events.append(GameEvents.make(&"last_seat_sat", {
		"player": player, "stool": stool, "pos": Serializer.vec3(seat_position(stool)),
		"yaw": snappedf(ParlorRoom.yaw_to_table(stools[stool]), 0.001), "free": free_stools(), "how": how,
	}))


# --- End ----------------------------------------------------------------------------------------

func remove_player(player: int) -> void:
	if seat_of.has(player):
		sitter.erase(seat_of[player])  # their stool is free again
		seat_of.erase(player)
	super.remove_player(player)
	if not finished and state != State.DONE and alive.size() <= 1:
		_end_game()


func _end_game() -> void:
	if state == State.DONE:
		return
	state = State.DONE
	wait_left = END_HOLD
	winner = alive[0] if alive.size() == 1 else -1
	events.append(GameEvents.make(&"last_seat_winner", {"player": winner, "ranking": ranking()}))


func _finish() -> void:
	finished = true
	events.append(GameEvents.make(&"last_seat_finished", {"ranking": ranking()}))


func get_public_state() -> Dictionary:
	var st: Dictionary = walkable_state()
	st["state"] = String(State.keys()[state]).to_lower()
	st["round"] = round_no
	st["music"] = state == State.MUSIC
	st["stool_count"] = stool_count
	st["stools"] = _stools_wire()
	var seats: Dictionary = {}
	for p: int in seat_of:
		seats[p] = seat_of[p]
	st["seated"] = seats
	st["grace"] = snappedf(maxf(grace_left, 0.0), 0.01) if state == State.SCRAMBLE else 0.0
	st["winner"] = winner
	if finished or state == State.DONE:
		st["ranking"] = ranking()
	return st


func _stools_wire() -> Array:
	var out: Array = []
	for s: Vector3 in stools:
		out.append(Serializer.vec3(s))
	return out


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
