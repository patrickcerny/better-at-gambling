class_name FindTheLadyLogic
extends MinigameLogicBase
## "Find the Lady" minigame (three-card monte at Lucky's table). Five rounds, each faster: Lucky
## lays the cards out face up and shows the Queen (SHOW), turns them face down and shuffles them
## (SHUFFLE), then everyone picks the card they think is the Queen (PICK, ends early once every
## player picked), then the cards turn over (REVEAL). Rounds 1-3 use three cards, rounds 4-5 four.
##
## The server picks where the Queen starts and the whole swap sequence; clients only animate
## them. The sequence goes out when the shuffle starts (the start slot is public anyway: Lucky
## shows it). Picks stay secret until the reveal (`find_the_lady_picked` only says THAT someone
## picked). A right pick scores 500 plus up to 500 for speed, timed on the server from the moment
## the pick window opened and corrected by the player's half-RTT like the quiz; a wrong pick or
## no pick scores 0. Ranking: total points, then the lowest total time on right picks; still
## tied → shared rank. Players who drop out leave the ranking (they score nothing, §2.12).

enum Step { INTRO, SHOW, SHUFFLE, PICK, REVEAL, OUTRO, DONE }

const PHASE_NAMES: Array[String] = ["intro", "show", "shuffle", "pick", "reveal", "over", "over"]
const ROUNDS: int = 5
## Round index (0-based) from which a fourth card is on the table.
const FOURTH_CARD_ROUND: int = 3
## Lucky greets the table before the first round (the stage only exists once the curtain
## closed, so round 1 must not start in the same tick as setup).
const INTRO_TIME: float = 1.2
const SHOW_TIME: float = 2.4
## Turning the cards face down before the first swap.
const FLIP_TIME: float = 0.6
## A beat after the last swap before the pick window opens.
const SETTLE_TIME: float = 0.35
const REVEAL_TIME: float = 3.6
const OUTRO_TIME: float = 3.0
## Per round: number of swaps, seconds per swap and the pick window (all getting tighter).
const SWAP_COUNTS: Array[int] = [5, 7, 9, 11, 13]
const SWAP_TIMES: Array[float] = [0.5, 0.42, 0.34, 0.28, 0.23]
const PICK_TIMES: Array[float] = [7.0, 6.5, 6.0, 5.5, 5.0]
const BASE_POINTS: int = 500
const SPEED_POINTS: int = 500
## Share of swaps that move the Queen (the rest are decoys between the other cards).
const LADY_SWAP_CHANCE: float = 0.6

var phase: Step = Step.INTRO
var timer: float = 0.0
var round_index: int = 0
var card_count: int = 3
## Slot (left to right) the Queen starts the current round in, and where she ends up.
var lady_start: int = 0
var lady_slot: int = 0
## The current round's swaps: [[a, b], ...] slot pairs, applied in order.
var swaps: Array = []
## Server clock when the pick window opened.
var opened_at: float = 0.0
## Current round: player → picked slot, and → compensated seconds.
var picks: Dictionary[int, int] = {}
var elapsed: Dictionary[int, float] = {}
## Totals over the game.
var points: Dictionary[int, int] = {}
var correct_time: Dictionary[int, float] = {}
var last_reveal: Dictionary = {}
var _ranking: Array[Dictionary] = []


static func cards_in_round(r: int) -> int:
	return 4 if r >= FOURTH_CARD_ROUND else 3


static func swap_time(r: int) -> float:
	return SWAP_TIMES[clampi(r, 0, ROUNDS - 1)]


static func pick_time(r: int) -> float:
	return PICK_TIMES[clampi(r, 0, ROUNDS - 1)]


## How long the SHUFFLE phase of a sequence of `n` swaps lasts.
static func shuffle_duration(r: int, n: int) -> float:
	return FLIP_TIME + swap_time(r) * float(n) + SETTLE_TIME


## Where a card starting in `slot` ends up after `seq` ([[a, b], ...]).
static func follow(slot: int, seq: Array) -> int:
	var s: int = slot
	for pair: Variant in seq:
		var a: int = int(pair[0])
		var b: int = int(pair[1])
		if s == a:
			s = b
		elif s == b:
			s = a
	return s


## Points for one pick: right = 500 + up to 500 for the time left of `window`, wrong = 0.
static func pick_points(right: bool, seconds: float, window: float) -> int:
	if not right:
		return 0
	var remaining: float = clampf(window - maxf(seconds, 0.0), 0.0, window)
	return BASE_POINTS + int(roundf(float(SPEED_POINTS) * remaining / maxf(window, 0.01)))


func _on_setup(_context: Dictionary) -> void:
	for p: int in players:
		points[p] = 0
		correct_time[p] = 0.0
	phase = Step.INTRO
	timer = INTRO_TIME
	events.append(GameEvents.make(&"find_the_lady_started", {"players": players.duplicate(), "rounds": ROUNDS, "fourth_card_round": FOURTH_CARD_ROUND}))


func tick(delta: float, now: float) -> void:
	if phase == Step.DONE:
		return
	if players.is_empty() and phase != Step.OUTRO:
		_finish()
		return
	timer -= delta
	if phase == Step.PICK and _everyone_picked():
		timer = minf(timer, 0.0)
	if timer > 0.0:
		return
	match phase:
		Step.INTRO:
			_start_round(0)
		Step.SHOW:
			_shuffle()
		Step.SHUFFLE:
			_open_pick(now)
		Step.PICK:
			_reveal()
		Step.REVEAL:
			if round_index + 1 < ROUNDS:
				_start_round(round_index + 1)
			else:
				_finish()
		Step.OUTRO:
			phase = Step.DONE
			finished = true


## `intent` = {slot: 0..cards-1, round: optional round index (a pick for an old round is late)}.
func submit(player: int, intent: Dictionary, now: float) -> Dictionary:
	if not player in players:
		return StationLogicBase.fail(&"not_in_minigame")
	if phase != Step.PICK or int(intent.get("round", round_index)) != round_index:
		return StationLogicBase.fail(&"too_late")
	if picks.has(player):
		return StationLogicBase.fail(&"already_picked")
	var slot: int = int(intent.get("slot", -1))
	if slot < 0 or slot >= card_count:
		return StationLogicBase.fail(&"bad_value")
	picks[player] = slot
	elapsed[player] = minf(QuizScoring.compensated_elapsed(opened_at, now, float(half_rtt.call(player))), pick_time(round_index))
	events.append(GameEvents.make(&"find_the_lady_picked", {"player": player, "round": round_index, "count": picks.size()}))
	return StationLogicBase.OK_RESULT


func remove_player(player: int) -> void:
	super.remove_player(player)
	picks.erase(player)
	elapsed.erase(player)
	points.erase(player)
	correct_time.erase(player)


func ranking() -> Array[Dictionary]:
	return _ranking


func get_public_state() -> Dictionary:
	var st: Dictionary = {"minigame": &"find_the_lady", "phase": PHASE_NAMES[phase], "round": round_index, "rounds": ROUNDS,
		"cards": card_count, "timer": snappedf(maxf(timer, 0.0), 0.01), "phase_time": _phase_length(), "lady_start": lady_start,
		"players": players.duplicate(), "totals": points.duplicate(), "picked": picks.keys()}
	if phase in [Step.SHUFFLE, Step.PICK, Step.REVEAL]:
		st["swaps"] = swaps.duplicate(true)
		st["swap_time"] = swap_time(round_index)
	if phase in [Step.REVEAL, Step.OUTRO, Step.DONE] and not last_reveal.is_empty():
		st["reveal"] = last_reveal.duplicate(true)
	if phase in [Step.OUTRO, Step.DONE]:
		st["ranking"] = _ranking.duplicate(true)
	return st


func private_state(player: int) -> Dictionary:
	var out: Dictionary = {"round": round_index, "can_pick": phase == Step.PICK and player in players and not picks.has(player)}
	if picks.has(player):
		out["picked"] = picks[player]
	return out


func _phase_length() -> float:
	match phase:
		Step.INTRO:
			return INTRO_TIME
		Step.SHOW:
			return SHOW_TIME
		Step.SHUFFLE:
			return shuffle_duration(round_index, swaps.size())
		Step.PICK:
			return pick_time(round_index)
		Step.REVEAL:
			return REVEAL_TIME
	return OUTRO_TIME


func _start_round(r: int) -> void:
	round_index = r
	card_count = cards_in_round(r)
	picks.clear()
	elapsed.clear()
	swaps = []
	lady_start = rng.range_int(0, card_count - 1)
	lady_slot = lady_start
	phase = Step.SHOW
	timer = SHOW_TIME
	events.append(GameEvents.make(&"find_the_lady_round", {"round": r, "rounds": ROUNDS, "cards": card_count, "lady_start": lady_start, "seconds": SHOW_TIME}))


func _shuffle() -> void:
	swaps = _make_swaps(SWAP_COUNTS[round_index])
	lady_slot = follow(lady_start, swaps)
	phase = Step.SHUFFLE
	timer = shuffle_duration(round_index, swaps.size())
	events.append(GameEvents.make(&"find_the_lady_shuffle", {"round": round_index, "cards": card_count, "lady_start": lady_start,
		"swaps": swaps.duplicate(true), "swap_time": swap_time(round_index), "flip_time": FLIP_TIME, "seconds": timer}))


## `n` swaps of two different slots; most of them move the Queen, and no swap simply undoes the
## one before it.
func _make_swaps(n: int) -> Array:
	var out: Array = []
	var lady: int = lady_start
	var last: Array = []
	for i: int in n:
		var a: int = 0
		var b: int = 1
		for attempt: int in 8:
			a = lady if rng.chance(LADY_SWAP_CHANCE) else rng.range_int(0, card_count - 1)
			b = rng.range_int(0, card_count - 2)
			if b >= a:
				b += 1
			if last.is_empty() or not (mini(a, b) == int(last[0]) and maxi(a, b) == int(last[1])):
				break
		last = [mini(a, b), maxi(a, b)]
		out.append(last)
		lady = follow(lady, [last])
	return out


func _open_pick(now: float) -> void:
	phase = Step.PICK
	timer = pick_time(round_index)
	opened_at = now
	events.append(GameEvents.make(&"find_the_lady_pick", {"round": round_index, "cards": card_count, "seconds": timer}))


func _everyone_picked() -> bool:
	for p: int in players:
		if not picks.has(p):
			return false
	return not players.is_empty()


func _reveal() -> void:
	phase = Step.REVEAL
	timer = REVEAL_TIME
	var gained: Dictionary = {}
	for p: int in players:
		var right: bool = picks.has(p) and picks[p] == lady_slot
		var pts: int = pick_points(right, elapsed.get(p, 0.0), pick_time(round_index)) if picks.has(p) else 0
		points[p] = int(points.get(p, 0)) + pts
		if right:
			correct_time[p] = float(correct_time.get(p, 0.0)) + float(elapsed[p])
		gained[p] = pts
	var times: Dictionary = {}
	for p: int in elapsed:
		times[p] = snappedf(elapsed[p], 0.01)
	last_reveal = {"round": round_index, "cards": card_count, "lady": lady_slot, "lady_start": lady_start, "swaps": swaps.duplicate(true),
		"picks": picks.duplicate(), "times": times, "points": gained, "totals": points.duplicate()}
	events.append(GameEvents.make(&"find_the_lady_reveal", last_reveal.duplicate(true)))


func _finish() -> void:
	phase = Step.OUTRO
	timer = OUTRO_TIME
	var pts: Dictionary = {}
	var times: Dictionary = {}
	for p: int in players:
		pts[p] = points.get(p, 0)
		times[p] = correct_time.get(p, 0.0)
	_ranking = QuizScoring.rank(pts, times)
	events.append(GameEvents.make(&"find_the_lady_over", {"ranking": _ranking.duplicate(true), "totals": points.duplicate()}))
