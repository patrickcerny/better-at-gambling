class_name BatHeistLogic
extends WalkableLogicBase
## "Bat Heist" (MINIGAME_IDEAS #10), a walkable minigame in a big vault arena (`ARENA_SCALE` ×
## the standard vault). Every bean starts with `START_COINS` coins and holds a baseball bat the
## whole game. Left click swings it: a hit on the bean in front knocks them flat for
## `KNOCK_SECONDS` (the room's knockdown ragdoll). The casino's grab and throw work here too: a
## thrown bean lands knocked down just the same (`on_thrown`). While a bean is down, every click of
## a bean standing over them steals one coin (at most `STEAL_RATE` per second). Once up, a bean is
## immune (no hit, no grab, no steal) for `IMMUNE_SECONDS`. After `GAME_SECONDS` the most coins
## wins; equal coins share a rank. Coins are points only, never money.
##
## The server decides everything: hits come from its own positions and facings (`pick_target`, the
## client's target is only a hint), the clock, who is down and every coin.
## - `minigame_action {kind: "swing", target?}` swings the bat (cooldown `SWING_COOLDOWN`, a miss
##   is fine).
## - `{kind: "steal", target?}` is one click over a downed bean: one coin from a downed,
##   non-immune bean within `STEAL_REACH` of the thief (the hint first), refused past `STEAL_RATE`
##   clicks in the last second (`too_fast`).
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
## Most steal clicks (one coin each) a thief gets per second.
const STEAL_RATE: int = 6
## A thrown bean stays down this long from the throw (the flight, then the knockdown).
const THROWN_SECONDS: float = KNOCK_SECONDS + 1.0
## The vault is this much bigger than Pass the Bomb's in x and z (floor area × 1.5).
const ARENA_SCALE: float = 1.225
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
## thief → game clock of their steal clicks in the last second (the rate limit).
var steal_clicks: Dictionary[int, Array] = {}
## player → game clock of their last swing.
var last_swing: Dictionary[int, float] = {}
## Fun stats for the feed and the end card.
var hits: Dictionary[int, int] = {}
var stolen: Dictionary[int, int] = {}
var wait_left: float = 0.0
var _announced: bool = false


func room_layout() -> Dictionary:
	return VaultArena.layout(ARENA_SCALE)


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


## The action button. Kinds: "swing", "steal" (see the class notes).
func _on_action(player: int, kind: StringName, hint: int, _now: float) -> Dictionary:
	if state != State.PLAYING:
		return StationLogicBase.fail(&"game_over")
	match kind:
		&"swing":
			return _swing(player, hint)
		&"steal":
			return _steal(player, hint)
	return StationLogicBase.fail(&"bad_value")


func _swing(player: int, hint: int) -> Dictionary:
	if is_down(player):
		return StationLogicBase.fail(&"down")
	if clock < float(last_swing.get(player, -INF)) + SWING_COOLDOWN:
		return StationLogicBase.fail(&"cooldown")
	last_swing[player] = clock
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
		_knock(target, player, &"bat", KNOCK_SECONDS)
	return {"ok": true, "error": &"", "target": target, "result": result}


func _knock(target: int, by: int, cause: StringName, seconds: float) -> void:
	down_until[target] = clock + seconds
	immune_until.erase(target)
	hits[by] = hits.get(by, 0) + 1
	pending_knockdowns.append({"player": target, "seconds": seconds, "cause": cause, "attacker": by})
	events.append(GameEvents.make(&"bat_heist_hit", {"player": by, "target": target, "seconds": seconds, "cause": cause}))


## The casino's throw landed a bean in the room: it goes down like a bat hit (an immune or already
## downed bean can't be grabbed or stays down as it is).
func on_thrown(target: int, attacker: int) -> void:
	if finished or state != State.PLAYING or target not in alive or is_down(target) or is_immune(target):
		return
	_knock(target, attacker, &"throw", THROWN_SECONDS)


## Grab, throw and shove stay on (throwing is half the game); shaking chips out of a bean a wall
## throw knocked out would take real money in a points-only game.
func blocked_intents() -> Array[StringName]:
	return [&"shake"]


## Immune beans can't be grabbed or shoved (the server treats them like a seated player).
func is_untouchable(player: int) -> bool:
	return is_immune(player)


## One steal click: one coin from the downed bean in reach, if the thief isn't clicking too fast.
func _steal(player: int, hint: int) -> Dictionary:
	if is_down(player):
		return StationLogicBase.fail(&"down")
	var target: int = _steal_target(player, hint)
	if target < 0:
		return StationLogicBase.fail(&"no_target")
	var recent: Array = []
	for t: Variant in steal_clicks.get(player, []):
		if float(t) > clock - 1.0:
			recent.append(t)
	if recent.size() >= STEAL_RATE:
		steal_clicks[player] = recent
		return StationLogicBase.fail(&"too_fast")
	recent.append(clock)
	steal_clicks[player] = recent
	var took: bool = _take_coin(player, target)
	return {"ok": true, "error": &"", "target": target, "stolen": 1 if took else 0}


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


func _take_coin(thief: int, target: int) -> bool:
	if int(coins.get(target, 0)) <= 0:
		return false  # nothing left to take: coins never go below 0
	coins[target] = int(coins[target]) - 1
	coins[thief] = int(coins.get(thief, 0)) + 1
	stolen[thief] = stolen.get(thief, 0) + 1
	events.append(GameEvents.make(&"bat_heist_stole", {"player": thief, "target": target, "coins": {thief: coins[thief], target: coins[target]}}))
	return true


## The bean is up: the immunity starts now.
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
	steal_clicks.erase(player)
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
	if finished or state == State.DONE:
		st["ranking"] = ranking()
	return st


func private_state(player: int) -> Dictionary:
	return {
		"coins": int(coins.get(player, 0)),
		"cooldown": snappedf(maxf(float(last_swing.get(player, -INF)) + SWING_COOLDOWN - clock, 0.0), 0.01),
	}
