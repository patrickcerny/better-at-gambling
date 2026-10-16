class_name JackpotClimbLogic
extends WalkableLogicBase
## "Jackpot Climb" (MINIGAME_IDEAS #11), a walkable jump-and-run in the climb room's "towers"
## layout (`ClimbRoom`, `ChipTowers`): everyone starts on the apron and hops from chip stack to chip
## stack up a cake of three giant-chip tiers to the gold pad on the jackpot stack under the JACKPOT
## sign. Each tier has two lanes round it (a steady one of short hops, a bold one with a few wide
## running jumps) and its top is a checkpoint flag. Everyone carries a baseball bat: a hit knocks
## the target off their ledge. Shove allowed, grab (and so throw) blocked. Order of reaching the top
## wins, then the rest by height.
##
## Everything is decided from the server's own positions (`world`):
## - Height: `ClimbRoom.progress(pos, "towers")`, the climb axis runs straight up the jackpot
##   stack (0 on the floor, 1 at the pad). Standing in the finish box over the pad
##   (`ClimbRoom.on_top`) **finishes** a bean, in order (same tick = shared place). Finishers are
##   held on the pad, safe from bats and shoves (`is_untouchable`).
## - Checkpoints: standing on a tier's top (`ChipTowers.checkpoint_at`) sets that bean's
##   checkpoint (only ever upward, `jackpot_climb_checkpoint`). A bean that drops `FALL_DROP` below
##   its checkpoint's top (fell off, knocked off) is put back on the checkpoint's flag
##   (`pending_moves`, `jackpot_climb_respawn`), then left alone for `RESPAWN_GRACE` while the
##   move lands. Before the first flag a fall is just physics: the net, and climb again. Nobody is
##   eliminated (only dropouts leave).
## - The bat: `minigame_action {kind: "swing", target?}`, `SWING_COOLDOWN` between swings (a miss
##   counts). The server picks the target in `BAT_REACH` in front of the swinger from its own
##   positions (the client's target is a hint, `pick_target`). A hit knocks the target down for
##   `KNOCK_SECONDS` (`pending_knockdowns`, cause "bat", attacker: the client throws the ragdoll
##   away from the attacker and up, off the ledge). The only immunity: `IMMUNE_SECONDS` after
##   getting up (`on_player_got_up`, or when the down runs out on the server's clock).
## - The game ends when everyone is up, at `GAME_SECONDS`, or `LAST_CALL` seconds after all but
##   one are up. Ranking: finishers in order, then the rest by their height at the end (snapped to
##   `TIE_STEP`; equal heights share a rank). A bean's height never counts below its checkpoint (a
##   fall at the buzzer doesn't cost the tier it reached). `points` = players ranked below.

enum State { PLAYING, DONE }

const VARIANT: String = "towers"
const GAME_SECONDS: float = 150.0
## After all but one are up, the last climber gets this long.
const LAST_CALL: float = 10.0
const SWING_COOLDOWN: float = 1.2
## Centre-to-centre reach of a swing (a bit longer than Bat Heist's: it reaches a bean standing
## on the near rim of the next stack).
const BAT_REACH: float = 2.4
const KNOCK_SECONDS: float = 1.2
const IMMUNE_SECONDS: float = 1.0
## Heights within this share a rank.
const TIE_STEP: float = 0.01
const SYNC_INTERVAL: float = 1.0
## A bean this far below its checkpoint's top goes back to the flag; then this long untouched.
const FALL_DROP: float = 2.5
const RESPAWN_GRACE: float = 1.5
const END_HOLD: float = 4.0

var state: State = State.PLAYING
var clock: float = 0.0
var wait_left: float = 0.0
## Finish groups in order ([[p], [q, r], ...]) and the clock each finished at.
var finish_groups: Array = []
var finish_time: Dictionary[int, float] = {}
## player → game clock until which they are down / immune.
var down_until: Dictionary[int, float] = {}
var immune_until: Dictionary[int, float] = {}
## player → game clock of their last swing.
var last_swing: Dictionary[int, float] = {}
## Clock when all but one were up (-1: not yet).
var last_call_at: float = -1.0
## Heights frozen at the end (the final ranking reads these).
var final_height: Dictionary[int, float] = {}
## Best height each bean reached (fun stat for the feed).
var best_height: Dictionary[int, float] = {}
var winner: int = -1
var end_reason: StringName = &""
## player → checkpoint reached (1..3; absent: none yet), and clock until which a respawn is in
## flight (no new one meanwhile).
var checkpoint: Dictionary[int, int] = {}
var respawn_until: Dictionary[int, float] = {}
## Fun stats: respawns, hits given and taken.
var respawns: Dictionary[int, int] = {}
var hits_given: Dictionary[int, int] = {}
var hits_taken: Dictionary[int, int] = {}
var _sync_left: float = 0.0
var _announced: bool = false


func room_layout() -> Dictionary:
	return ClimbRoom.layout(VARIANT)


func _on_room_setup(_context: Dictionary) -> void:
	id = &"jackpot_climb"
	for p: int in players:
		hits_given[p] = 0
		hits_taken[p] = 0
		best_height[p] = 0.0


## Shoving on narrow ledges is part of the brawl; grab (and so throw) is not.
func blocked_intents() -> Array[StringName]:
	return [&"grab", &"release"]


## Beans on the pad are safe from shoves.
func is_untouchable(player: int) -> bool:
	return is_up(player)


# --- Queries --------------------------------------------------------------------------------------

## The server's own position of `p` (Vector3.INF before its first report).
func server_position(p: int) -> Vector3:
	if world != null and world.positions.has(p):
		return world.get_position(p)
	return Vector3.INF


func height_of(p: int) -> float:
	if final_height.has(p):
		return final_height[p]
	if is_up(p):
		return 1.0
	var at: Vector3 = server_position(p)
	var h: float = ClimbRoom.progress(at, VARIANT) if at != Vector3.INF else 0.0
	return maxf(h, checkpoint_height(p))


## Progress of `p`'s checkpoint (0 without one).
func checkpoint_height(p: int) -> float:
	return ChipTowers.level_y(checkpoint[p]) / ClimbRoom.TOWER_TOP_Y if checkpoint.has(p) else 0.0


## World respawn spot of `p` at checkpoint `k` (spread round the flag by roster place).
func respawn_spot(p: int, k: int) -> Vector3:
	var spots: Array = ChipTowers.checkpoints()[k - 1]["spots"]
	return ROOM_ORIGIN + (spots[maxi(roster.find(p), 0) % spots.size()] as Vector3)


func is_up(p: int) -> bool:
	return finish_time.has(p)


func is_down(p: int) -> bool:
	return down_until.has(p)


func is_immune(p: int) -> bool:
	return immune_until.has(p) and clock < immune_until[p]


func finish_place(p: int) -> int:
	var place: int = 1
	for g: Array in finish_groups:
		if p in g:
			return place
		place += g.size()
	return 0


# --- Tick --------------------------------------------------------------------------------------

func tick(delta: float, _now: float) -> void:
	if finished:
		return
	if not _announced:
		# The stage only exists after the curtain: say it from the first tick (and in the state).
		_announced = true
		events.append(GameEvents.make(&"jackpot_climb_begin", {"players": alive.duplicate(), "seconds": GAME_SECONDS}))
		_sync()
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
	for p: int in alive:
		if not is_up(p):
			best_height[p] = maxf(float(best_height.get(p, 0.0)), height_of(p))
	_check_finishes()
	_check_checkpoints()
	_sync_left -= delta
	if _sync_left <= 0.0:
		_sync()
	_check_end()


func _sync() -> void:
	_sync_left = SYNC_INTERVAL
	events.append(GameEvents.make(&"jackpot_climb_clock", {"clock": snappedf(clock, 0.001)}))


func _check_finishes() -> void:
	var group: Array[int] = []
	for p: int in alive:
		if is_up(p) or is_down(p):
			continue
		var at: Vector3 = server_position(p)
		if at != Vector3.INF and ClimbRoom.on_top(at, VARIANT):
			group.append(p)
	if group.is_empty():
		return
	group.sort()
	var place: int = 1
	for g: Array in finish_groups:
		place += g.size()
	finish_groups.append(group)
	for p: int in group:
		finish_time[p] = clock
		best_height[p] = 1.0
		immune_until.erase(p)
	events.append(GameEvents.make(&"jackpot_climb_top", {"players": group, "place": place, "clock": snappedf(clock, 0.01)}))


## Flags reached (only upward) and falls below the last one (back to its flag).
func _check_checkpoints() -> void:
	for p: int in alive:
		if is_up(p) or is_down(p):
			continue
		if respawn_until.has(p):
			if clock < respawn_until[p]:
				continue
			respawn_until.erase(p)
		var at: Vector3 = server_position(p)
		if at == Vector3.INF:
			continue
		var k: int = ChipTowers.checkpoint_at(at - ROOM_ORIGIN)
		if k > int(checkpoint.get(p, 0)):
			checkpoint[p] = k
			events.append(GameEvents.make(&"jackpot_climb_checkpoint", {"player": p, "index": k, "clock": snappedf(clock, 0.01)}))
		elif checkpoint.has(p) and at.y < ROOM_ORIGIN.y + ChipTowers.level_y(checkpoint[p]) - FALL_DROP:
			var to: Vector3 = respawn_spot(p, checkpoint[p])
			pending_moves[p] = to
			respawn_until[p] = clock + RESPAWN_GRACE
			respawns[p] = respawns.get(p, 0) + 1
			events.append(GameEvents.make(&"jackpot_climb_respawn", {"player": p, "index": checkpoint[p], "pos": Serializer.vec3(to)}))


func _check_end() -> void:
	var up: int = finish_time.size()
	var n: int = alive.size()
	if n > 0 and up >= n:
		_end_game(&"all_up")
	elif clock >= GAME_SECONDS:
		_end_game(&"time")
	elif up >= 1 and up >= n - 1:
		if last_call_at < 0.0:
			last_call_at = clock
			events.append(GameEvents.make(&"jackpot_climb_last_call", {"seconds": LAST_CALL}))
		elif clock - last_call_at >= LAST_CALL:
			_end_game(&"last_call")


# --- The bat ------------------------------------------------------------------------------------

func _on_action(player: int, kind: StringName, hint: int, _now: float) -> Dictionary:
	if state != State.PLAYING:
		return StationLogicBase.fail(&"game_over")
	if kind != &"swing":
		return StationLogicBase.fail(&"bad_value")
	return _swing(player, hint)


func _swing(player: int, hint: int) -> Dictionary:
	if is_up(player):
		return StationLogicBase.fail(&"finished")
	if is_down(player):
		return StationLogicBase.fail(&"down")
	if clock < float(last_swing.get(player, -INF)) + SWING_COOLDOWN:
		return StationLogicBase.fail(&"cooldown")
	last_swing[player] = clock
	# Finishers, downed and just-got-up beans can't be hit: the swing finds one that can.
	var exclude: Array[int] = []
	for p: int in alive:
		if is_up(p) or is_down(p) or is_immune(p):
			exclude.append(p)
	var target: int = pick_target(player, hint, BAT_REACH, exclude)
	var result: StringName = &"hit"
	if target < 0:
		var shielded: int = pick_target(player, hint, BAT_REACH)
		if shielded >= 0 and is_immune(shielded):
			target = shielded
			result = &"immune"
		else:
			target = -1
			result = &"miss"
	events.append(GameEvents.make(&"jackpot_climb_swing", {"player": player, "target": target, "result": result}))
	if result == &"hit":
		_knock(target, player)
	return {"ok": true, "error": &"", "target": target, "result": result}


func _knock(target: int, by: int) -> void:
	down_until[target] = clock + KNOCK_SECONDS
	immune_until.erase(target)
	hits_given[by] = hits_given.get(by, 0) + 1
	hits_taken[target] = hits_taken.get(target, 0) + 1
	pending_knockdowns.append({"player": target, "seconds": KNOCK_SECONDS, "cause": &"bat", "attacker": by})
	events.append(GameEvents.make(&"jackpot_climb_hit", {"player": by, "target": target, "seconds": KNOCK_SECONDS, "height": snappedf(height_of(target), 0.001)}))


func _stand_up(player: int) -> void:
	down_until.erase(player)
	if state != State.PLAYING or player not in alive:
		return
	immune_until[player] = clock + IMMUNE_SECONDS
	events.append(GameEvents.make(&"jackpot_climb_up", {"player": player, "immune": IMMUNE_SECONDS}))


## The room saw the ragdoll stand up: the down ends now and the grace counts from this moment.
func on_player_got_up(player: int) -> void:
	if finished or state != State.PLAYING or player not in alive:
		return
	if is_down(player):
		_stand_up(player)
	elif is_immune(player) and immune_until[player] < clock + IMMUNE_SECONDS:
		immune_until[player] = clock + IMMUNE_SECONDS


## Finishers stay on the pad under the sign.
func clamp_position(player: int, pos: Vector3) -> Vector3:
	if is_up(player) and player in alive and player in players and not finished:
		var box: AABB = ClimbRoom.layout(VARIANT)["finish"]
		if box.has_point(pos):
			return pos
		var inside: Vector3 = pos.clamp(box.position, box.end)
		if inside.distance_to(pos) < SNAP_DISTANCE:
			return inside
		var spots: Array = ClimbRoom.layout(VARIANT)["finish_spots"]
		return spots[maxi(roster.find(player), 0) % spots.size()]
	return super.clamp_position(player, pos)


# --- End ----------------------------------------------------------------------------------------

func remove_player(player: int) -> void:
	down_until.erase(player)
	immune_until.erase(player)
	respawn_until.erase(player)
	super.remove_player(player)
	if not finished and state == State.PLAYING and _announced:
		_check_end()


func _end_game(reason: StringName) -> void:
	if state == State.DONE:
		return
	state = State.DONE
	end_reason = reason
	for p: int in players:
		final_height[p] = 1.0 if is_up(p) else snappedf(height_of(p), TIE_STEP)
	var rows: Array[Dictionary] = ranking()
	winner = int(rows[0]["player"]) if not rows.is_empty() and (rows.size() == 1 or int(rows[1]["rank"]) > 1) else -1
	wait_left = END_HOLD
	events.append(GameEvents.make(&"jackpot_climb_over", {"reason": reason, "winner": winner, "ranking": rows}))


func _finish() -> void:
	finished = true
	events.append(GameEvents.make(&"jackpot_climb_finished", {"ranking": ranking()}))


## Finishers in order (same tick = shared rank), then the rest by height (snapped to `TIE_STEP`,
## equal heights share). `points` = players ranked below.
func ranking() -> Array[Dictionary]:
	var groups: Array = []
	for g: Array in finish_groups:
		var kept: Array[int] = []
		for p: int in g:
			if p in players:
				kept.append(p)
		if not kept.is_empty():
			groups.append(kept)
	var rest: Array[int] = []
	for p: int in players:
		if not is_up(p):
			rest.append(p)
	var hs: Dictionary[int, float] = {}
	for p: int in rest:
		hs[p] = snappedf(height_of(p), TIE_STEP)
	rest.sort_custom(func(a: int, b: int) -> bool: return hs[a] > hs[b] if not is_equal_approx(hs[a], hs[b]) else a < b)
	var i: int = 0
	while i < rest.size():
		var g: Array[int] = [rest[i]]
		var j: int = i + 1
		while j < rest.size() and is_equal_approx(hs[rest[j]], hs[rest[i]]):
			g.append(rest[j])
			j += 1
		groups.append(g)
		i = j
	var out: Array[Dictionary] = []
	var rank: int = 1
	var below: int = 0
	for g: Array in groups:
		below += g.size()
	for g: Array in groups:
		below -= g.size()
		for p: int in g:
			out.append({"player": p, "points": below, "rank": rank})
		rank += g.size()
	return out


func get_public_state() -> Dictionary:
	var st: Dictionary = walkable_state()
	st["state"] = String(State.keys()[state]).to_lower()
	st["clock"] = snappedf(clock, 0.01)
	st["seconds"] = GAME_SECONDS
	var fin: Array = []
	for g: Array in finish_groups:
		fin.append(g.duplicate())
	st["finish"] = fin
	var hts: Dictionary = {}
	for p: int in players:
		hts[p] = snappedf(height_of(p), 0.001)
	st["heights"] = hts
	var dn: Dictionary = {}
	for p: int in down_until:
		dn[p] = snappedf(maxf(down_until[p] - clock, 0.0), 0.01)
	st["down"] = dn
	var im: Dictionary = {}
	for p: int in immune_until:
		im[p] = snappedf(maxf(immune_until[p] - clock, 0.0), 0.01)
	st["immune"] = im
	var cps: Dictionary = {}
	for p: int in checkpoint:
		cps[p] = checkpoint[p]
	st["checkpoints"] = cps
	st["last_call"] = snappedf(maxf(LAST_CALL - (clock - last_call_at), 0.0), 0.01) if last_call_at >= 0.0 else -1.0
	st["winner"] = winner
	if finished or state == State.DONE:
		st["ranking"] = ranking()
		st["reason"] = end_reason
	return st


func private_state(player: int) -> Dictionary:
	return {"cooldown": snappedf(maxf(float(last_swing.get(player, -INF)) + SWING_COOLDOWN - clock, 0.0), 0.01), "hits": hits_given.get(player, 0), "taken": hits_taken.get(player, 0), "checkpoint": checkpoint.get(player, 0), "respawns": respawns.get(player, 0)}
