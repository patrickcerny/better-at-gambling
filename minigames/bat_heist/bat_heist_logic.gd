class_name BatHeistLogic
extends WalkableLogicBase
## "Bat Heist" (MINIGAME_IDEAS #10), a walkable minigame in the vault arena. Every bean starts with
## `START_COINS` coins and holds a baseball bat the whole game. The action button swings it: a hit
## on the bean in front knocks them flat for `KNOCK_SECONDS` (the room's knockdown ragdoll). While a
## bean is down anyone standing over them can hold the button to steal one coin per
## `STEAL_INTERVAL`. Once up, a bean is immune (no hit, no steal) for `IMMUNE_SECONDS`. After
## `GAME_SECONDS` the most coins wins; equal coins share a rank. Coins are points only, never money.
##
## The server decides everything: hits come from its own positions and facings (`pick_target`, the
## client's target is only a hint), the clock, who is down and every coin.
##
## Stealing is a start/stop pair, not a stream of intents (one intent per coin would eat the
## 20/s intent budget and stall on lag):
## - `minigame_action {kind: "steal", target?}` (E pressed or still held over a downed bean) opens
##   a steal on a downed, non-immune bean within `STEAL_REACH` of the thief (the hint first).
## - Each tick the server adds the time the thief spent in reach (a step away pauses it) and moves
##   one coin per full `STEAL_INTERVAL`. The steal ends by itself when the victim gets up, the thief
##   is knocked down, swings, or either leaves; `{kind: "steal_stop"}` (E released) ends it at once.
## - `{kind: "swing", target?}` swings the bat (cooldown `SWING_COOLDOWN`, a miss is fine).
##
## Down and immunity follow the server's own clock (the knockdown it queued); the room's
## `on_player_got_up` (the scene's ragdoll actually standing up) ends a down early and restarts the
## immunity from that moment, so it never runs out while the bean is still on the floor.

enum State { PLAYING, DONE }

const START_COINS: int = 10
const GAME_SECONDS: float = 60.0
## Seconds between swings of one player (a miss counts).
const SWING_COOLDOWN: float = 1.2
## Centre-to-centre reach of a bat swing, in front of the swinger like a shove.
const BAT_REACH: float = 2.0
## How long a hit bean stays down (the ragdoll), and the steal window with it.
const KNOCK_SECONDS: float = 3.0
## One coin per this many seconds of holding the button over a downed bean.
const STEAL_INTERVAL: float = 0.4
## Distance (any direction: you stand over a ragdoll) within which a steal runs.
const STEAL_REACH: float = 2.2
## No knockdown and no steal for this long after getting up.
const IMMUNE_SECONDS: float = 3.0
## Seconds the final scores stay up before the ranking.
const END_HOLD: float = 3.0

var state: State = State.PLAYING
## Game clock since the start (after the briefing), capped at `GAME_SECONDS`.
var clock: float = 0.0
var coins: Dictionary[int, int] = {}
## player → game clock until which they are down (only players currently down).
var down_until: Dictionary[int, float] = {}
## player → game clock until which they are immune (after getting up).
var immune_until: Dictionary[int, float] = {}
## thief → {target, progress} for every steal running now.
var steals: Dictionary[int, Dictionary] = {}
## player → game clock of their last swing.
var last_swing: Dictionary[int, float] = {}
## Fun stats for the feed and the end card.
var hits: Dictionary[int, int] = {}
var stolen: Dictionary[int, int] = {}
var wait_left: float = 0.0
var _announced: bool = false


func room_layout() -> Dictionary:
	return VaultArena.layout()


func _on_room_setup(_context: Dictionary) -> void:
	id = &"bat_heist"
	for p: int in players:
		coins[p] = START_COINS
		hits[p] = 0
		stolen[p] = 0


func tick(delta: float, _now: float) -> void:
	if finished:
		return
	if not _announced:
		# The stage only exists after the curtain: say it from the first tick (and in the state).
		_announced = true
		events.append(GameEvents.make(&"bat_heist_begin", {"coins": coins.duplicate(), "seconds": GAME_SECONDS}))
	if state == State.DONE:
		wait_left -= delta
		if wait_left <= 0.0:
			_finish()
		return
	clock = minf(clock + delta, GAME_SECONDS)
	_tick_steals(delta)
	for p: int in down_until.keys():
		if clock >= down_until[p]:
			_stand_up(p)
	for p: int in immune_until.keys():
		if clock >= immune_until[p]:
			immune_until.erase(p)
	if clock >= GAME_SECONDS:
		_end_game()


func is_down(player: int) -> bool:
	return down_until.has(player)


func is_immune(player: int) -> bool:
	return immune_until.has(player) and clock < immune_until[player]


## The action button. Kinds: "swing", "steal", "steal_stop" (see the class notes).
func _on_action(player: int, kind: StringName, hint: int, _now: float) -> Dictionary:
	if state != State.PLAYING:
		return StationLogicBase.fail(&"game_over")
	match kind:
		&"swing":
			return _swing(player, hint)
		&"steal":
			return _start_steal(player, hint)
		&"steal_stop":
			_end_steal(player, &"released")
			return StationLogicBase.OK_RESULT
	return StationLogicBase.fail(&"bad_value")


func _swing(player: int, hint: int) -> Dictionary:
	if is_down(player):
		return StationLogicBase.fail(&"down")
	if clock < float(last_swing.get(player, -INF)) + SWING_COOLDOWN:
		return StationLogicBase.fail(&"cooldown")
	last_swing[player] = clock
	_end_steal(player, &"swung")
	# Downed and immune beans can't be hit: the swing finds the nearest one that can.
	var exclude: Array[int] = []
	for p: int in alive:
		if is_down(p) or is_immune(p):
			exclude.append(p)
	var target: int = pick_target(player, hint, BAT_REACH, exclude)
	var result: StringName = &"hit"
	if target < 0:
		var shielded: int = pick_target(player, hint, BAT_REACH)
		if shielded >= 0 and is_immune(shielded):
			target = shielded
			result = &"immune"
		else:
			result = &"miss"
	events.append(GameEvents.make(&"bat_heist_swing", {"player": player, "target": target, "result": result}))
	if result == &"hit":
		_knock(target, player)
	return {"ok": true, "error": &"", "target": target, "result": result}


func _knock(target: int, by: int) -> void:
	down_until[target] = clock + KNOCK_SECONDS
	immune_until.erase(target)
	hits[by] = hits.get(by, 0) + 1
	_end_steal(target, &"knocked")
	pending_knockdowns.append({"player": target, "seconds": KNOCK_SECONDS, "cause": &"bat", "attacker": by})
	events.append(GameEvents.make(&"bat_heist_hit", {"player": by, "target": target, "seconds": KNOCK_SECONDS}))


func _start_steal(player: int, hint: int) -> Dictionary:
	if is_down(player):
		return StationLogicBase.fail(&"down")
	var target: int = _steal_target(player, hint)
	if target < 0:
		return StationLogicBase.fail(&"no_target")
	if steals.has(player) and int(steals[player]["target"]) == target:
		return {"ok": true, "error": &"", "target": target}  # already at it (a repeat while held)
	_end_steal(player, &"switched")
	steals[player] = {"target": target, "progress": 0.0}
	events.append(GameEvents.make(&"bat_heist_steal_start", {"player": player, "target": target}))
	return {"ok": true, "error": &"", "target": target}


## The downed, non-immune bean within `STEAL_REACH` of `player` (the hint first), else the
## closest one, else -1. Uses the server's positions (a ragdoll's where the server simulates it).
func _steal_target(player: int, hint: int) -> int:
	if world == null or not world.positions.has(player):
		return -1
	if hint >= 0 and _can_steal_from(player, hint, STEAL_REACH + InteractionRules.LAG_SLACK):
		return hint
	var best: int = -1
	var best_d: float = INF
	for p: int in alive:
		if _can_steal_from(player, p, STEAL_REACH):
			var d: float = _flat_distance(player, p)
			if d < best_d:
				best_d = d
				best = p
	return best


func _can_steal_from(player: int, target: int, reach: float) -> bool:
	if target == player or target not in alive or not is_down(target) or is_immune(target):
		return false
	if world == null or not world.positions.has(target) or not world.positions.has(player):
		return false
	return _flat_distance(player, target) <= reach


func _flat_distance(a: int, b: int) -> float:
	var d: Vector3 = world.get_position(a) - world.get_position(b)
	d.y = 0.0
	return d.length()


func _tick_steals(delta: float) -> void:
	for thief: int in steals.keys():
		var s: Dictionary = steals[thief]
		var target: int = int(s["target"])
		if not is_down(target) or is_down(thief) or target not in alive or thief not in alive:
			_end_steal(thief, &"got_up")
			continue
		if _flat_distance(thief, target) > STEAL_REACH + InteractionRules.LAG_SLACK:
			continue  # stepped away: the hold pauses until they're back over the body
		var progress: float = float(s["progress"]) + delta
		while progress >= STEAL_INTERVAL - 0.0001:  # float steps (0.05 × 8) must count as 0.4
			progress -= STEAL_INTERVAL
			_take_coin(thief, target)
		s["progress"] = progress


func _take_coin(thief: int, target: int) -> void:
	if int(coins.get(target, 0)) <= 0:
		return  # nothing left to take: coins never go below 0
	coins[target] = int(coins[target]) - 1
	coins[thief] = int(coins.get(thief, 0)) + 1
	stolen[thief] = stolen.get(thief, 0) + 1
	events.append(GameEvents.make(&"bat_heist_stole", {"player": thief, "target": target, "coins": {thief: coins[thief], target: coins[target]}}))


func _end_steal(thief: int, reason: StringName) -> void:
	if not steals.has(thief):
		return
	var target: int = int(steals[thief]["target"])
	steals.erase(thief)
	events.append(GameEvents.make(&"bat_heist_steal_end", {"player": thief, "target": target, "reason": reason}))


## The bean is up: its steals end and the immunity starts now.
func _stand_up(player: int) -> void:
	down_until.erase(player)
	if state != State.PLAYING or player not in alive:
		return
	immune_until[player] = clock + IMMUNE_SECONDS
	events.append(GameEvents.make(&"bat_heist_up", {"player": player, "immune": IMMUNE_SECONDS}))


## The room tells us a ragdoll really stood up: end the down now (if it still runs) and make sure
## the immunity counts from this moment.
func on_player_got_up(player: int) -> void:
	if finished or state != State.PLAYING or player not in alive:
		return
	if is_down(player):
		_stand_up(player)
	elif is_immune(player) and immune_until[player] < clock + IMMUNE_SECONDS:
		immune_until[player] = clock + IMMUNE_SECONDS
		events.append(GameEvents.make(&"bat_heist_up", {"player": player, "immune": IMMUNE_SECONDS}))


func remove_player(player: int) -> void:
	_end_steal(player, &"left")
	for thief: int in steals.keys():
		if int(steals[thief]["target"]) == player:
			_end_steal(thief, &"left")
	super.remove_player(player)
	coins.erase(player)
	down_until.erase(player)
	immune_until.erase(player)
	if not finished and state == State.PLAYING and alive.size() < 2:
		_end_game()


func _end_game() -> void:
	if state == State.DONE:
		return
	state = State.DONE
	for thief: int in steals.keys():
		_end_steal(thief, &"time")
	wait_left = END_HOLD
	events.append(GameEvents.make(&"bat_heist_over", {"coins": coins.duplicate(), "ranking": ranking()}))


func _finish() -> void:
	finished = true
	events.append(GameEvents.make(&"bat_heist_finished", {"ranking": ranking()}))


## Most coins first; equal coins share a rank (1, 1, 3). `points` = coins.
func ranking() -> Array[Dictionary]:
	var order: Array[int] = []
	for p: int in players:
		order.append(p)
	order.sort_custom(func(a: int, b: int) -> bool:
		var ca: int = int(coins.get(a, 0))
		var cb: int = int(coins.get(b, 0))
		return ca > cb if ca != cb else a < b)
	var out: Array[Dictionary] = []
	var rank: int = 1
	for i: int in order.size():
		var p: int = order[i]
		var c: int = int(coins.get(p, 0))
		if i > 0 and c != int(coins.get(order[i - 1], 0)):
			rank = i + 1
		out.append({"player": p, "points": c, "coins": c, "rank": rank})
	return out


func get_public_state() -> Dictionary:
	var st: Dictionary = walkable_state()
	st["state"] = String(State.keys()[state]).to_lower()
	st["clock"] = snappedf(clock, 0.01)
	st["seconds"] = GAME_SECONDS
	st["coins"] = coins.duplicate()
	var down: Dictionary = {}
	for p: int in down_until:
		down[p] = snappedf(maxf(down_until[p] - clock, 0.0), 0.01)
	st["down"] = down
	var immune: Dictionary = {}
	for p: int in immune_until:
		immune[p] = snappedf(maxf(immune_until[p] - clock, 0.0), 0.01)
	st["immune"] = immune
	var thieves: Dictionary = {}
	for thief: int in steals:
		thieves[thief] = int(steals[thief]["target"])
	st["steals"] = thieves
	if finished or state == State.DONE:
		st["ranking"] = ranking()
	return st


func private_state(player: int) -> Dictionary:
	return {
		"coins": int(coins.get(player, 0)),
		"cooldown": snappedf(maxf(float(last_swing.get(player, -INF)) + SWING_COOLDOWN - clock, 0.0), 0.01),
		"stealing": int(steals[player]["target"]) if steals.has(player) else -1,
	}
