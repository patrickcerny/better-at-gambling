class_name DodgeTheDiceLogic
extends WalkableLogicBase
## "Dodge the Dice" (MINIGAME_IDEAS #15), a walkable climb on the giant tilted roulette board of
## `ClimbRoom` ("board"). Everyone starts on the apron at the bottom and climbs row by row (jump
## each ledge, keep out of the brass slide chutes) while roulette balls, coins and dice tumble
## down. A hit knocks the bean down and slides it back. First to the top wins, then the rest by
## height. Shove allowed, grab (and so throw) blocked.
##
## Everything is decided from the server's own positions (`world`):
## - Height: `ClimbRoom.progress(pos)`, the fraction of the climb axis covered (0 at the bottom
##   edge, 1 at the landing's lip). Standing on the landing (`ClimbRoom.on_top`) with progress 1
##   is **finished**, in order (beans finishing on the same tick share the place). Finishers are
##   held on the landing (the safe zone, no hazards there) and can't be shoved.
## - The game ends when everyone is up, at `GAME_SECONDS`, or `LAST_CALL` seconds after all but
##   one are up. Ranking: finishers in order, then the rest by their height at the end (snapped to
##   `TIE_STEP`; equal heights share a rank). `points` = players ranked below.
##
## Hazards (server path, deterministic, nothing streamed per tick):
## - From `FIRST_SPAWN` on the server drops one every `spawn_interval(clock)` seconds (1.6 s
##   falling linearly to 0.7 s at 60 s): a roulette **ball** (small, fast, straight down), a
##   **coin** (big, rolls slower, wobbles sideways) or a **die** (hops every row and picks a new
##   lane each hop). 35% of them aim at a climbing bean's lane.
## - Each is announced once as `dodge_the_dice_hazard {id, kind, lane, speed, t0, seed}` (also in
##   the public state while it rolls). Server and clients run the same `path_at(hazard, clock)`:
##   a drop from the gantry, then `speed` m/s (flat) down the board with the kind's sideways path
##   from the seed, on the board's surface. It ends past the bottom edge (`end_time`).
## - A standing bean within the hazard's radius + `HIT_SLACK` (flat), not over its top (a bean can
##   jump a ball, mostly not a coin), is knocked down for `KNOCK_SECONDS` (`pending_knockdowns`,
##   cause = kind) and slid back `SLIDE_MIN`..`SLIDE_MAX` m downhill (`pending_moves`, applied by
##   the server when the ragdoll is up; skipped if the ragdoll already slid further). Safe for
##   `IMMUNE_SECONDS` after getting up (`on_player_got_up`).
##
## Slide chutes (`ClimbRoom.CHUTES`) are client-side: the stage pushes its own bean down while it
## stands in one, so the reported positions already carry the slide (like Roulette Sumo's drift).

enum State { PLAYING, DONE }

const GAME_SECONDS: float = 90.0
## After all but one are up, the last climber gets this long.
const LAST_CALL: float = 10.0
## Hazard rate: seconds between drops, from the start to `SPAWN_RAMP` seconds in.
const SPAWN_START: float = 1.6
const SPAWN_END: float = 0.7
const SPAWN_RAMP: float = 60.0
const FIRST_SPAWN: float = 1.0
const KINDS: Array[StringName] = [&"ball", &"coin", &"dice"]
const KIND_WEIGHTS: Array[float] = [0.45, 0.25, 0.3]
const RADIUS: Dictionary = {&"ball": 0.3, &"coin": 0.7, &"dice": 0.45}
## Flat speed down the board (m/s): [min, max] per kind.
const SPEED: Dictionary = {&"ball": [8.5, 11.0], &"coin": [4.5, 6.0], &"dice": [5.5, 7.0]}
const AIM_CHANCE: float = 0.35
## Seconds a hazard falls from the gantry onto the top row, and where on the top row it lands
## (metres below the top edge).
const DROP_TIME: float = 0.45
const START_DZ: float = 0.8
## Hazards end this far past the board's bottom edge (into the gutter).
const END_DZ: float = 0.6
## Coin: sideways wobble amplitude range (m) and rate (radians per metre rolled).
const COIN_WOBBLE: Array[float] = [0.7, 1.6]
const COIN_RATE: float = 0.55
## Dice: lane change per hop (± m) and hop height (m); a hop per row.
const DICE_SHIFT: float = 1.8
const DICE_HOP: float = 0.55
const HIT_SLACK: float = 0.4
const KNOCK_SECONDS: float = 1.5
const IMMUNE_SECONDS: float = 1.5
const SLIDE_MIN: float = 3.0
const SLIDE_MAX: float = 5.0
## Heights within this share a rank.
const TIE_STEP: float = 0.01
const SYNC_INTERVAL: float = 1.0
const END_HOLD: float = 4.0

var state: State = State.PLAYING
var clock: float = 0.0
var wait_left: float = 0.0
## Hazards rolling now (wire dicts, see `path_at`).
var hazards: Array[Dictionary] = []
var next_spawn: float = FIRST_SPAWN
var _next_id: int = 1
## Finish groups in order ([[p], [q, r], ...]) and the clock each finished at.
var finish_groups: Array = []
var finish_time: Dictionary[int, float] = {}
## player → game clock until which they are down / safe from hazards.
var down_until: Dictionary[int, float] = {}
var safe_until: Dictionary[int, float] = {}
## player → where the slide-back puts them (until they are up).
var planned_slide: Dictionary[int, Vector3] = {}
## Clock when all but one were up (-1: not yet).
var last_call_at: float = -1.0
## Heights frozen at the end (the final ranking reads these).
var final_height: Dictionary[int, float] = {}
var winner: int = -1
var end_reason: StringName = &""
## Fun stats: hits taken.
var hits: Dictionary[int, int] = {}
var _sync_left: float = 0.0
var _announced: bool = false


func room_layout() -> Dictionary:
	return ClimbRoom.layout("board")


func _on_room_setup(_context: Dictionary) -> void:
	id = &"dodge_the_dice"
	for p: int in players:
		hits[p] = 0


## Shove is part of the fun; grab (and so throw) is not.
func blocked_intents() -> Array[StringName]:
	return [&"grab", &"release"]


## Beans on top are safe from shoves.
func is_untouchable(player: int) -> bool:
	return is_up(player)


# --- Shared maths (server and client) -----------------------------------------------------------

## Seconds between hazard drops at game clock `t`.
static func spawn_interval(t: float) -> float:
	return lerpf(SPAWN_START, SPAWN_END, clampf(t / SPAWN_RAMP, 0.0, 1.0))


static func radius_of(kind: StringName) -> float:
	return float(RADIUS.get(kind, 0.4))


## A deterministic 0..1 from a hazard's seed and an index (integer hash, same on every machine).
static func rand01(seed_value: int, k: int) -> float:
	var h: int = (seed_value * 374761393 + k * 668265263) & 0x7FFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7FFFFFFF
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 65535.0


## World z where hazards land on the top row, and where they end past the bottom edge.
static func start_z() -> float:
	return ClimbRoom.top_z() + START_DZ


static func end_z() -> float:
	return WalkableLogicBase.ROOM_ORIGIN.z + END_DZ


## Game clock at which `h` has rolled off the bottom.
static func end_time(h: Dictionary) -> float:
	return float(h["t0"]) + DROP_TIME + (end_z() - start_z()) / maxf(float(h["speed"]), 0.1)


## Sideways position (local x) of `h` after rolling `s` metres (flat) down the board.
static func lane_x(h: Dictionary, s: float) -> float:
	var kind: StringName = StringName(h["kind"])
	var lane: float = float(h["lane"])
	var sd: int = int(h["seed"])
	var x: float = lane
	if kind == &"coin":
		var amp: float = lerpf(COIN_WOBBLE[0], COIN_WOBBLE[1], rand01(sd, 1))
		x = lane + amp * sin(s * COIN_RATE + rand01(sd, 2) * TAU)
	elif kind == &"dice":
		var hop: float = s / ClimbRoom.ROW_D
		var k: int = floori(hop)
		var a: float = lane if k <= 0 else lane + (rand01(sd, 10 + k) * 2.0 - 1.0) * DICE_SHIFT
		var b: float = lane + (rand01(sd, 11 + k) * 2.0 - 1.0) * DICE_SHIFT
		x = lerpf(a, b, smoothstep(0.0, 0.7, hop - float(k)))
	var lim: float = ClimbRoom.HALF_W - radius_of(kind) - 0.15
	return clampf(x, -lim, lim)


## World centre of hazard `h` at game clock `t`: a drop from the gantry onto the top row, then
## down the board on its surface (dice hop once a row).
static func path_at(h: Dictionary, t: float) -> Vector3:
	var kind: StringName = StringName(h["kind"])
	var r: float = radius_of(kind)
	var tau: float = maxf(t - float(h["t0"]), 0.0)
	var ox: float = WalkableLogicBase.ROOM_ORIGIN.x
	var z0: float = start_z()
	if tau < DROP_TIME:
		var k: float = tau / DROP_TIME
		var y: float = lerpf(ClimbRoom.top_y() + ClimbRoom.HOPPER_DROP, ClimbRoom.surface_y(z0) + r, k * k)
		return Vector3(ox + lane_x(h, 0.0), y, z0)
	var s: float = (tau - DROP_TIME) * float(h["speed"])
	var z: float = z0 + s
	var y2: float = ClimbRoom.surface_y(z) + r
	if kind == &"dice":
		var hop: float = s / ClimbRoom.ROW_D
		y2 += DICE_HOP * sin(PI * (hop - floorf(hop)))
	return Vector3(ox + lane_x(h, s), y2, z)


# --- Tick --------------------------------------------------------------------------------------

func tick(delta: float, _now: float) -> void:
	if finished:
		return
	if not _announced:
		# The stage only exists after the curtain: say it from the first tick (and in the state).
		_announced = true
		events.append(GameEvents.make(&"dodge_the_dice_begin", {"players": alive.duplicate(), "seconds": GAME_SECONDS}))
		_sync()
	if state == State.DONE:
		wait_left -= delta
		if wait_left <= 0.0:
			_finish()
		return
	clock = minf(clock + delta, GAME_SECONDS)
	for p: int in down_until.keys():
		if clock >= down_until[p]:
			down_until.erase(p)
	while clock >= next_spawn:
		_spawn(next_spawn)
		next_spawn += spawn_interval(next_spawn)
	hazards = hazards.filter(func(h: Dictionary) -> bool: return clock < end_time(h))
	_check_hits()
	_check_finishes()
	_sync_left -= delta
	if _sync_left <= 0.0:
		_sync()
	_check_end()


func _sync() -> void:
	_sync_left = SYNC_INTERVAL
	events.append(GameEvents.make(&"dodge_the_dice_clock", {"clock": snappedf(clock, 0.001)}))


func _spawn(t0: float) -> void:
	var roll: float = rng.unit()
	var kind: StringName = KINDS[KINDS.size() - 1]
	var acc: float = 0.0
	for i: int in KINDS.size():
		acc += KIND_WEIGHTS[i]
		if roll < acc:
			kind = KINDS[i]
			break
	var lim: float = ClimbRoom.HALF_W - radius_of(kind) - 0.3
	var lane: float = rng.range_float(-lim, lim)
	if rng.unit() < AIM_CHANCE:
		var climbers: Array[int] = []
		for p: int in alive:
			if not is_up(p) and server_position(p) != Vector3.INF:
				climbers.append(p)
		if not climbers.is_empty():
			var target: int = climbers[rng.range_int(0, climbers.size() - 1)]
			lane = clampf(server_position(target).x - WalkableLogicBase.ROOM_ORIGIN.x, -lim, lim)
	var sp: Array = SPEED[kind]
	var h: Dictionary = {
		"id": _next_id, "kind": String(kind), "lane": snappedf(lane, 0.001),
		"speed": snappedf(rng.range_float(float(sp[0]), float(sp[1])), 0.001),
		"t0": snappedf(t0, 0.001), "seed": rng.range_int(1, 1 << 30),
	}
	_next_id += 1
	hazards.append(h)
	events.append(GameEvents.make(&"dodge_the_dice_hazard", h.duplicate()))


## The server's own position of `p` (Vector3.INF before its first report).
func server_position(p: int) -> Vector3:
	if world != null and world.positions.has(p):
		return world.get_position(p)
	return Vector3.INF


func height_of(p: int) -> float:
	if final_height.has(p):
		return final_height[p]
	var at: Vector3 = server_position(p)
	return ClimbRoom.progress(at) if at != Vector3.INF else 0.0


func is_up(p: int) -> bool:
	return finish_time.has(p)


func is_down(p: int) -> bool:
	return down_until.has(p)


func _check_hits() -> void:
	for h: Dictionary in hazards:
		var hp: Vector3 = path_at(h, clock)
		var r: float = radius_of(StringName(h["kind"]))
		for p: int in alive:
			if is_up(p) or is_down(p) or clock < float(safe_until.get(p, -INF)):
				continue
			var at: Vector3 = server_position(p)
			if at == Vector3.INF or ClimbRoom.on_top(at) or ClimbRoom.progress(at) >= 1.0:
				continue  # the landing is the safe zone
			if Vector2(at.x - hp.x, at.z - hp.z).length() > r + HIT_SLACK:
				continue
			if at.y > hp.y + r + 0.1 or at.y < hp.y - r - 1.7:
				continue  # jumped over it, or far below it
			_hit(p, h, at)


func _hit(p: int, h: Dictionary, at: Vector3) -> void:
	var kind: StringName = StringName(h["kind"])
	down_until[p] = clock + KNOCK_SECONDS
	safe_until[p] = clock + KNOCK_SECONDS + IMMUNE_SECONDS  # until the got-up report resets it
	var floor_z: float = WalkableLogicBase.ROOM_ORIGIN.z + ClimbRoom.APRON_Z - 1.2
	var to: Vector3 = ClimbKit.downhill(ClimbRoom.flight(), at, rng.range_float(SLIDE_MIN, SLIDE_MAX), floor_z)
	planned_slide[p] = to
	pending_moves[p] = to
	hits[p] = hits.get(p, 0) + 1
	pending_knockdowns.append({"player": p, "seconds": KNOCK_SECONDS, "cause": kind})
	var ahead: Vector3 = path_at(h, clock + 0.1) - path_at(h, clock)
	events.append(GameEvents.make(&"dodge_the_dice_hit", {"player": p, "kind": String(kind), "hazard": int(h["id"]), "to": Serializer.vec3(to), "dir": [snappedf(ahead.x, 0.001), snappedf(ahead.z, 0.001)], "seconds": KNOCK_SECONDS}))


## The ragdoll stood up: immunity starts now; the slide-back move stays unless the tumble already
## carried the bean further down.
func on_player_got_up(player: int) -> void:
	down_until.erase(player)
	safe_until[player] = clock + IMMUNE_SECONDS
	if planned_slide.has(player):
		var at: Vector3 = server_position(player)
		if at != Vector3.INF and at.z >= planned_slide[player].z - 0.3:
			pending_moves.erase(player)
		planned_slide.erase(player)


func _check_finishes() -> void:
	var group: Array[int] = []
	for p: int in alive:
		if is_up(p) or is_down(p):
			continue
		var at: Vector3 = server_position(p)
		if at != Vector3.INF and ClimbRoom.on_top(at) and ClimbRoom.progress(at) >= 1.0 - 0.0001:
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
		planned_slide.erase(p)
		pending_moves.erase(p)
	events.append(GameEvents.make(&"dodge_the_dice_top", {"players": group, "place": place, "clock": snappedf(clock, 0.01)}))


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
			events.append(GameEvents.make(&"dodge_the_dice_last_call", {"seconds": LAST_CALL}))
		elif clock - last_call_at >= LAST_CALL:
			_end_game(&"last_call")


## Finishers stay on the landing (the winners' circle).
func clamp_position(player: int, pos: Vector3) -> Vector3:
	if is_up(player) and player in alive and player in players and not finished:
		var box: AABB = ClimbRoom.layout("board")["finish"]
		if box.has_point(pos):
			return pos
		var inside: Vector3 = pos.clamp(box.position, box.end)
		if inside.distance_to(pos) < SNAP_DISTANCE:
			return inside
		var spots: Array = ClimbRoom.layout("board")["finish_spots"]
		return spots[maxi(roster.find(player), 0) % spots.size()]
	return super.clamp_position(player, pos)


# --- End ----------------------------------------------------------------------------------------

func remove_player(player: int) -> void:
	down_until.erase(player)
	planned_slide.erase(player)
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
	events.append(GameEvents.make(&"dodge_the_dice_over", {"reason": reason, "winner": winner, "ranking": rows}))


func _finish() -> void:
	finished = true
	events.append(GameEvents.make(&"dodge_the_dice_finished", {"ranking": ranking()}))


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
	var hz: Array = []
	for h: Dictionary in hazards:
		hz.append(h.duplicate())
	st["hazards"] = hz
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
	st["last_call"] = snappedf(maxf(LAST_CALL - (clock - last_call_at), 0.0), 0.01) if last_call_at >= 0.0 else -1.0
	st["winner"] = winner
	if finished or state == State.DONE:
		st["ranking"] = ranking()
		st["reason"] = end_reason
	return st


func private_state(player: int) -> Dictionary:
	return {"safe": snappedf(maxf(float(safe_until.get(player, -INF)) - clock, 0.0), 0.01), "hits": hits.get(player, 0)}
