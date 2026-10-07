class_name RouletteRoyaleLogic
extends MinigameLogicBase
## "Roulette Royale" minigame: a last-bean-standing elimination on the casino's roulette wheel.
##
## Every bean starts with 3 hearts. Each spin, everyone still in secretly picks RED, BLACK or GREEN
## (green is the lone zero: rare). The ball lands on a real European wheel (0-36) after the casino
## wheel's 3.4 s spin (`balance.roulette_spin_time`). A wrong pick, or no pick at all, costs a
## heart; a correct GREEN call gives one back (never above the starting 3). Beans at 0 hearts are
## out. Ranking is the order they ran out: last bean with hearts wins; beans knocked out on the
## same spin share a place. The spin count is capped so a round lasts 45-75 s; if several beans
## survive the last spin they are ranked by hearts left.
##
## Flow: INTRO → (PICK → SPIN → RESULT)× → OUTRO → DONE. The pick window closes early once every
## bean still in has picked. Picks stay secret until the result: `roulette_royale_picked` only
## says *that* someone picked.
##
## Intent: `submit_answer` {question: spin index, index: 0 red / 1 black / 2 green}.

enum State { INTRO, PICK, SPIN, RESULT, OUTRO, DONE }

const COLORS: Array[StringName] = [&"red", &"black", &"green"]
const INITIAL_HEARTS: int = 3
const MAX_HEARTS: int = 3
## 3 + 6 × (5 + 3.4 + 3) + 3 = 74.4 s worst case; most games end in 4-6 spins.
const MAX_SPINS: int = 6
const INTRO_TIME: float = 3.0
const PICK_TIME: float = 5.0
## A short beat after the last pick so the lock-in registers before the ball flies.
const ALL_PICKED_GRACE: float = 0.4
## Ball drop (`RouletteWheelFx.DROP_TIME`, 2 s) plus a moment to read the hearts.
const RESULT_TIME: float = 3.0
const OUTRO_TIME: float = 3.0
## Ranking points (added to the match's minigame points): per spin survived and per heart left.
const POINTS_PER_SPIN: int = 100
const POINTS_PER_HEART: int = 50

var state: State = State.INTRO
var timer: float = 0.0
## Spin index (0-based) of the current / last pick window; -1 before the first.
var spin: int = -1
var spin_time: float = 3.4
var hearts: Dictionary[int, int] = {}
## Beans still in (hearts > 0), in join order.
var alive: Array[int] = []
## This spin's secret picks: player → color.
var picks: Dictionary[int, StringName] = {}
## Spin index each bean was knocked out on (absent while alive).
var out_on_spin: Dictionary[int, int] = {}
var last_result: Dictionary = {}
## Tests / dev: numbers the next spins land on, used up front to back, before the rng.
var forced_numbers: Array[int] = []
var _ranking: Array[Dictionary] = []


func _on_setup(_context: Dictionary) -> void:
	if balance != null:
		spin_time = balance.roulette_spin_time
	for p: int in players:
		hearts[p] = INITIAL_HEARTS
	alive = players.duplicate()
	state = State.INTRO
	timer = INTRO_TIME
	events.append(GameEvents.make(&"roulette_royale_started", {
		"players": players.duplicate(), "hearts": hearts.duplicate(), "max_spins": MAX_SPINS,
		"pick_time": PICK_TIME, "spin_time": spin_time, "seconds": INTRO_TIME,
	}))


func tick(delta: float, _now: float) -> void:
	if state == State.DONE:
		return
	timer -= delta
	if state == State.PICK and _everyone_picked():
		timer = minf(timer, ALL_PICKED_GRACE)
	if timer > 0.0:
		return
	match state:
		State.INTRO:
			_open_picks()
		State.PICK:
			_spin()
		State.SPIN:
			_resolve()
		State.RESULT:
			if alive.size() <= 1 or spin + 1 >= MAX_SPINS:
				_outro()
			else:
				_open_picks()
		State.OUTRO:
			state = State.DONE
			finished = true


func submit(player: int, intent: Dictionary, _now: float) -> Dictionary:
	if not player in players:
		return StationLogicBase.fail(&"not_in_minigame")
	if not player in alive:
		return StationLogicBase.fail(&"knocked_out")
	if state != State.PICK or int(intent.get("question", -1)) != spin:
		return StationLogicBase.fail(&"too_late")
	if picks.has(player):
		return StationLogicBase.fail(&"already_picked")
	var i: int = int(intent.get("index", -1))
	if i < 0 or i >= COLORS.size():
		return StationLogicBase.fail(&"bad_value")
	picks[player] = COLORS[i]
	events.append(GameEvents.make(&"roulette_royale_picked", {"player": player, "spin": spin}))
	return StationLogicBase.OK_RESULT


## A bean left mid-game: they are out of this minigame and its ranking.
func remove_player(player: int) -> void:
	super.remove_player(player)
	alive.erase(player)
	picks.erase(player)
	hearts.erase(player)
	out_on_spin.erase(player)
	_ranking.clear()
	# Nobody left to beat: wrap up now instead of spinning for one bean. A spin already in the
	# air still lands (RESULT then goes straight to the outro).
	if alive.size() <= 1 and state in [State.INTRO, State.PICK]:
		_outro()


func ranking() -> Array[Dictionary]:
	if _ranking.is_empty():
		_ranking = _compute_ranking()
	return _ranking


func get_public_state() -> Dictionary:
	var st: Dictionary = {
		"minigame": &"roulette_royale", "state": state, "timer": snappedf(maxf(timer, 0.0), 0.01),
		"spin": spin, "max_spins": MAX_SPINS, "spin_time": spin_time, "players": players.duplicate(),
		"hearts": hearts.duplicate(), "alive": alive.duplicate(), "picked": picks.keys(),
	}
	if not last_result.is_empty():
		st["last_result"] = last_result.duplicate(true)
	if state == State.OUTRO or state == State.DONE:
		st["ranking"] = ranking().duplicate(true)
	return st


func private_state(player: int) -> Dictionary:
	var out: Dictionary = {"spin": spin, "alive": player in alive, "can_pick": state == State.PICK and player in alive and not picks.has(player)}
	if picks.has(player):
		out["pick"] = COLORS.find(picks[player])
	return out


## Color of a pocket on the wheel.
static func color_of(number: int) -> StringName:
	return RouletteLogic.color_of(number)


## Heart change for one pick against the landed color (before the cap).
static func heart_delta(pick: StringName, landed: StringName) -> int:
	if pick != landed:
		return -1
	return 1 if landed == &"green" else 0


# --- Flow --------------------------------------------------------------------------------------

func _everyone_picked() -> bool:
	for p: int in alive:
		if not picks.has(p):
			return false
	return not alive.is_empty()


func _open_picks() -> void:
	spin += 1
	picks.clear()
	state = State.PICK
	timer = PICK_TIME
	events.append(GameEvents.make(&"roulette_royale_pick_open", {
		"spin": spin, "max_spins": MAX_SPINS, "seconds": PICK_TIME, "alive": alive.duplicate(), "hearts": hearts.duplicate(),
	}))


func _spin() -> void:
	state = State.SPIN
	timer = spin_time
	events.append(GameEvents.make(&"roulette_royale_spin", {"spin": spin, "seconds": spin_time}))


## The ball lands: hearts change, beans at zero are out.
func _resolve() -> void:
	var number: int = forced_numbers.pop_front() if not forced_numbers.is_empty() else rng.range_int(0, RouletteLogic.WHEEL_ORDER.size() - 1)  # 0-36, one green pocket
	var landed: StringName = color_of(number)
	var shown_picks: Dictionary = {}
	var deltas: Dictionary = {}
	var eliminated: Array[int] = []
	for p: int in alive:
		var pick: StringName = picks.get(p, &"")
		shown_picks[p] = pick
		var before: int = hearts[p]
		hearts[p] = clampi(before + heart_delta(pick, landed), 0, MAX_HEARTS)
		deltas[p] = hearts[p] - before
		if hearts[p] <= 0:
			eliminated.append(p)
	for p: int in eliminated:
		alive.erase(p)
		out_on_spin[p] = spin
	state = State.RESULT
	timer = RESULT_TIME
	last_result = {
		"spin": spin, "number": number, "color": landed, "picks": shown_picks, "deltas": deltas,
		"hearts": hearts.duplicate(), "eliminated": eliminated.duplicate(), "alive": alive.duplicate(),
	}
	events.append(GameEvents.make(&"roulette_royale_result", last_result.duplicate(true)))


func _outro() -> void:
	state = State.OUTRO
	timer = OUTRO_TIME
	_ranking = _compute_ranking()
	events.append(GameEvents.make(&"roulette_royale_finished", {"ranking": _ranking.duplicate(true)}))


## Survivors first (by hearts), then beans by how late they went out. Equal keys share a rank.
func _compute_ranking() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for p: int in players:
		var out: int = int(out_on_spin.get(p, MAX_SPINS))  # survivors outlast every spin
		var h: int = int(hearts.get(p, 0))
		var survived: int = out if out_on_spin.has(p) else spin + 1
		rows.append({"player": p, "hearts": h, "out_spin": out, "alive": not out_on_spin.has(p),
			"points": maxi(survived, 0) * POINTS_PER_SPIN + h * POINTS_PER_HEART})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["out_spin"] != b["out_spin"]:
			return a["out_spin"] > b["out_spin"]
		if a["hearts"] != b["hearts"]:
			return a["hearts"] > b["hearts"]
		return a["player"] < b["player"])
	for i: int in rows.size():
		var tied: bool = i > 0 and rows[i]["out_spin"] == rows[i - 1]["out_spin"] and rows[i]["hearts"] == rows[i - 1]["hearts"]
		rows[i]["rank"] = rows[i - 1]["rank"] if tied else i + 1
	return rows
