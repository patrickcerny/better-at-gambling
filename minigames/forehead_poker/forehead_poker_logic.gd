class_name ForeheadPokerLogic
extends MinigameLogicBase
## "Forehead Poker" (Indian poker in Lucky's dark card room). Five rounds. Each round Lucky deals
## every player one card from a fresh deck onto their forehead, facing out (DEAL): you see every
## other card, never your own. Then the table talks it over on voice (TALK, 15 s), then everyone
## secretly picks STAY or FOLD (DECIDE, ends early once all decided; no answer = FOLD). At the
## SHOWDOWN the highest card among the stayers (by rank only, aces high, suits don't matter) wins
## the pot: +1 point per staying player (the winner included), every other stayer loses 1, folders
## score 0. Equal highest cards share the pot evenly, rounded down. Nobody stayed: nobody scores.
##
## Keeping your own card secret on the wire: the dealt cards are never in an event or in the
## public state before the showdown. Each player gets the OTHER players' cards through their own
## `private_state` (sent only to them), which leaves their own card out; the `_showdown` event and
## the public state of the showdown carry every card once the round is decided. Decisions are
## secret too: `forehead_poker_decided` only says THAT someone decided.
##
## Ranking: total points; equal totals share a rank. Players who drop out leave the ranking.

enum Step { INTRO, DEAL, TALK, DECIDE, SHOWDOWN, OUTRO, DONE }

const PHASE_NAMES: Array[String] = ["intro", "deal", "talk", "decide", "showdown", "over", "over"]
const ROUNDS: int = 5
const INTRO_TIME: float = 1.5
## Lucky deals one card after the other onto the foreheads.
const DEAL_TIME: float = 2.6
const TALK_TIME: float = 15.0
const DECIDE_TIME: float = 8.0
const SHOWDOWN_TIME: float = 6.0
const OUTRO_TIME: float = 3.5
const STAY: String = "stay"
const FOLD: String = "fold"

var phase: Step = Step.INTRO
var timer: float = 0.0
var round_index: int = 0
## Current round: player → card (Card int), and → "stay" / "fold".
var cards: Dictionary[int, int] = {}
var choices: Dictionary[int, String] = {}
## Totals over the game.
var points: Dictionary[int, int] = {}
var last_showdown: Dictionary = {}
var _ranking: Array[Dictionary] = []


## Card strength for the showdown: rank only, aces high (2 = 2 … K = 13, A = 14).
static func strength(card: int) -> int:
	var r: int = Card.rank(card)
	return 14 if r == 1 else r


## Scores one showdown. `hand` = player → card, `picks` = player → "stay"/"fold" (missing = fold).
## Returns {points: {player: delta}, winners: [player], stayers: [player], pot, share}.
static func score(hand: Dictionary, picks: Dictionary) -> Dictionary:
	var stayers: Array[int] = []
	for k: Variant in hand:
		if String(picks.get(int(k), FOLD)) == STAY:
			stayers.append(int(k))
	stayers.sort()
	var best: int = -1
	for p: int in stayers:
		best = maxi(best, strength(int(hand[p])))
	var winners: Array[int] = []
	for p: int in stayers:
		if strength(int(hand[p])) == best:
			winners.append(p)
	var pot: int = stayers.size()
	var share: int = pot / maxi(winners.size(), 1)
	var pts: Dictionary = {}
	for k: Variant in hand:
		var p: int = int(k)
		if not p in stayers:
			pts[p] = 0
		elif p in winners:
			pts[p] = share
		else:
			pts[p] = -1
	return {"points": pts, "winners": winners, "stayers": stayers, "pot": pot, "share": share}


func _on_setup(_context: Dictionary) -> void:
	for p: int in players:
		points[p] = 0
	phase = Step.INTRO
	timer = INTRO_TIME
	events.append(GameEvents.make(&"forehead_poker_started", {"players": players.duplicate(), "rounds": ROUNDS, "talk_time": TALK_TIME, "decide_time": DECIDE_TIME}))


func tick(delta: float, _now: float) -> void:
	if phase == Step.DONE:
		return
	if players.is_empty() and phase != Step.OUTRO:
		_finish()
		return
	timer -= delta
	if phase == Step.DECIDE and _everyone_decided():
		timer = minf(timer, 0.0)
	if timer > 0.0:
		return
	match phase:
		Step.INTRO:
			_deal(0)
		Step.DEAL:
			_talk()
		Step.TALK:
			_open_decide()
		Step.DECIDE:
			_showdown()
		Step.SHOWDOWN:
			if round_index + 1 < ROUNDS:
				_deal(round_index + 1)
			else:
				_finish()
		Step.OUTRO:
			phase = Step.DONE
			finished = true


## `intent` = {action: "stay" | "fold", round: optional round index (an answer for an old round is late)}.
func submit(player: int, intent: Dictionary, _now: float) -> Dictionary:
	if not player in players:
		return StationLogicBase.fail(&"not_in_minigame")
	if phase != Step.DECIDE or int(intent.get("round", round_index)) != round_index:
		return StationLogicBase.fail(&"too_late")
	if choices.has(player):
		return StationLogicBase.fail(&"already_picked")
	var action: String = String(intent.get("action", ""))
	if action != STAY and action != FOLD:
		return StationLogicBase.fail(&"bad_value")
	choices[player] = action
	events.append(GameEvents.make(&"forehead_poker_decided", {"player": player, "round": round_index, "count": choices.size()}))
	return StationLogicBase.OK_RESULT


func remove_player(player: int) -> void:
	super.remove_player(player)
	if phase != Step.SHOWDOWN:
		cards.erase(player)  # an open round goes on without their card
	choices.erase(player)
	points.erase(player)


func ranking() -> Array[Dictionary]:
	return _ranking


## No card of the open round is in here: those go out privately (see the class comment).
func get_public_state() -> Dictionary:
	var st: Dictionary = {"minigame": &"forehead_poker", "phase": PHASE_NAMES[phase], "round": round_index, "rounds": ROUNDS,
		"timer": snappedf(maxf(timer, 0.0), 0.01), "phase_time": _phase_length(), "players": players.duplicate(),
		"dealt": cards.keys(), "totals": points.duplicate(), "decided": choices.keys()}
	if phase in [Step.SHOWDOWN, Step.OUTRO, Step.DONE] and not last_showdown.is_empty():
		st["showdown"] = last_showdown.duplicate(true)
	if phase in [Step.OUTRO, Step.DONE]:
		st["ranking"] = _ranking.duplicate(true)
	return st


## Everyone's card but `player`'s own, their own answer, and whether they may still answer.
func private_state(player: int) -> Dictionary:
	var seen: Dictionary = {}
	for p: int in cards:
		if p != player:
			seen[p] = cards[p]
	var out: Dictionary = {"round": round_index, "cards": seen, "can_act": phase == Step.DECIDE and player in players and not choices.has(player)}
	if choices.has(player):
		out["choice"] = choices[player]
	return out


func _phase_length() -> float:
	match phase:
		Step.INTRO:
			return INTRO_TIME
		Step.DEAL:
			return DEAL_TIME
		Step.TALK:
			return TALK_TIME
		Step.DECIDE:
			return DECIDE_TIME
		Step.SHOWDOWN:
			return SHOWDOWN_TIME
	return OUTRO_TIME


func _deal(r: int) -> void:
	round_index = r
	choices.clear()
	cards.clear()
	var deck: Array = []
	for c: int in 52:
		deck.append(c)
	rng.shuffle(deck)
	var order: Array[int] = players.duplicate()
	for i: int in order.size():
		cards[order[i]] = int(deck[i])
	phase = Step.DEAL
	timer = DEAL_TIME
	events.append(GameEvents.make(&"forehead_poker_deal", {"round": r, "rounds": ROUNDS, "order": order, "seconds": DEAL_TIME}))


func _talk() -> void:
	phase = Step.TALK
	timer = TALK_TIME
	events.append(GameEvents.make(&"forehead_poker_talk", {"round": round_index, "seconds": TALK_TIME}))


func _open_decide() -> void:
	phase = Step.DECIDE
	timer = DECIDE_TIME
	events.append(GameEvents.make(&"forehead_poker_decide", {"round": round_index, "seconds": DECIDE_TIME}))


func _everyone_decided() -> bool:
	for p: int in players:
		if not choices.has(p):
			return false
	return not players.is_empty()


func _showdown() -> void:
	phase = Step.SHOWDOWN
	timer = SHOWDOWN_TIME
	var hand: Dictionary = {}
	var picks: Dictionary = {}
	for p: int in players:
		if cards.has(p):
			hand[p] = cards[p]
			picks[p] = choices.get(p, FOLD)  # no answer = fold
	var res: Dictionary = score(hand, picks)
	var gained: Dictionary = res["points"]
	for k: Variant in gained:
		points[int(k)] = int(points.get(int(k), 0)) + int(gained[k])
	last_showdown = {"round": round_index, "cards": hand, "choices": picks, "points": gained, "winners": res["winners"],
		"pot": res["pot"], "share": res["share"], "totals": points.duplicate()}
	events.append(GameEvents.make(&"forehead_poker_showdown", last_showdown.duplicate(true)))


func _finish() -> void:
	phase = Step.OUTRO
	timer = OUTRO_TIME
	var pts: Dictionary = {}
	for p: int in players:
		pts[p] = points.get(p, 0)
	_ranking = QuizScoring.rank(pts, {})
	events.append(GameEvents.make(&"forehead_poker_over", {"ranking": _ranking.duplicate(true), "totals": points.duplicate()}))
