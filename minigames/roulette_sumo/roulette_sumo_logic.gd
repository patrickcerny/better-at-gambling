class_name RouletteSumoLogic
extends WalkableLogicBase
## "Roulette Sumo" (MINIGAME_IDEAS #9), a walkable minigame on the giant wheel of `WheelRoom`.
## Patrick 2026-10-11: no shove, no grab, no throw. Everyone carries a bat: a hit **freezes** the
## target for `FREEZE_SECONDS` (no knockdown). The wheel turns faster and faster, a giant roulette
## ball rolls round the deck and knocks beans down, and whoever leaves the wheel is out. The last
## bean on the wheel wins; after `GAME_SECONDS` the beans still on it rank by distance from the
## centre (nearest first). Ranking = order of falling off, decided from the server's positions.
##
## The wheel (deterministic, nothing to stream per tick):
## - The game clock starts at the first tick after the briefing. The wheel's angular speed is
##   `omega_at(clock)`: `OMEGA_START` rising linearly to `OMEGA_MAX` over `RAMP_SECONDS`, then
##   capped; its angle `wheel_angle(clock)` is the integral. A once-per-second
##   `roulette_sumo_wheel {clock, angle, omega}` event and the public state let clients re-sync.
## - Standing on the deck drags a bean along: per step `drift(pos, omega, dt)` turns it round the
##   centre by `omega * dt` and slides it outward by `SLIDE * omega^2 * r * dt` (the faster the
##   wheel, the harder it flings you to the rim). The CLIENT applies `drift` to its own bean every
##   physics frame, so its reported positions already carry the drift (well inside the move
##   sanity's 16 m/s); puppets get it from their owner's stream. The server does not move
##   reporting beans itself (one teleport event per bean per tick would flood the wire).
## - A frozen bean's moves are refused: the server keeps a pin per frozen bean and drifts it with
##   the same `drift` every tick. `clamp_position` accepts reports near the pin (lag slack) and
##   returns the pin otherwise, so a frozen bean slides with the wheel and nowhere else.
## - Falls: a bean whose flat distance from the centre is past `FALL_RADIUS`, or who is more than
##   `FALL_DEPTH` below the deck, is out (`eliminate`, a short ragdoll, then the gallery). Frozen
##   beans are judged at their pin.
##
## The ball (server path, client prediction):
## - One ball of radius `BALL_RADIUS` rolls on the deck in the room's frame (the wheel doesn't
##   carry it). Its path is segments from the seeded rng: each lasts `SEG_MIN`..`SEG_MAX` s with a
##   speed in `BALL_MIN_SPEED`..`BALL_MAX_SPEED` and a turn rate up to `BALL_MAX_TURN` (the
##   velocity rotates at that rate); it bounces off the rim and the turret (`step_ball`).
## - `roulette_sumo_ball {ball, clock}` goes out at every new segment and once per second; the
##   public state carries it too. Clients run the same `step_ball` from the last update.
## - A standing bean within `BALL_HIT` of the ball's centre (flat, at deck height) is knocked down
##   for `KNOCK_SECONDS` (`pending_knockdowns`, cause "ball"); `roulette_sumo_ball_hit` carries the
##   ball's direction, which the scene uses to throw the ragdoll (the push). A bean the ball hit
##   can't be hit again for `KNOCK_SECONDS + BALL_GRACE`.
##
## The bat: `minigame_action {kind: "swing", target?}` (cooldown `SWING_COOLDOWN`, a miss is fine)
## picks the bean in front within `BAT_REACH` from the server's own positions (the target is a
## hint). Frozen, downed and freshly thawed (`THAW_GRACE`) beans can't be hit.

enum State { PLAYING, DONE }

const GAME_SECONDS: float = 90.0
## Wheel speed (rad/s): start, cap, and the seconds of the linear ramp between them.
const OMEGA_START: float = 0.25
const OMEGA_MAX: float = 1.2
const RAMP_SECONDS: float = 60.0
## Outward slide per (rad/s)^2 per metre of radius per second.
const SLIDE: float = 0.12
## Out past this flat distance from the centre (the rim plus a foot over the edge), or this far
## below the deck.
const FALL_RADIUS: float = WheelRoom.RIM_RADIUS + 0.3
const FALL_DEPTH: float = 1.0
## The ball.
const BALL_RADIUS: float = 0.7
const BALL_HIT: float = BALL_RADIUS + 0.5
const BALL_MIN_SPEED: float = 4.0
const BALL_MAX_SPEED: float = 7.0
const BALL_MAX_TURN: float = 1.3
const SEG_MIN: float = 1.0
const SEG_MAX: float = 2.6
## The ball's centre stays between these flat radii (turret and rim, minus its own radius).
const BALL_MIN_R: float = WheelRoom.HUB_RADIUS + BALL_RADIUS + 0.05
const BALL_MAX_R: float = WheelRoom.RIM_RADIUS - BALL_RADIUS - 0.15
const KNOCK_SECONDS: float = 1.5
const BALL_GRACE: float = 1.0
## The bat.
const SWING_COOLDOWN: float = 1.2
const BAT_REACH: float = 2.0
const FREEZE_SECONDS: float = 1.5
const THAW_GRACE: float = 1.0
## A frozen bean's report may be this far from its pin, plus the wheel's speed there times this
## many seconds of lag.
const PIN_SLACK: float = 0.6
const PIN_LAG: float = 0.25
## Ragdoll when a bean goes over the edge, then the gallery.
const FALL_KNOCK: float = 1.2
## How often the wheel and the ball are re-sent.
const SYNC_INTERVAL: float = 1.0
const END_HOLD: float = 3.5

var state: State = State.PLAYING
var clock: float = 0.0
var wait_left: float = 0.0
## player → game clock until which they are frozen / down / safe from the ball / safe from bats.
var frozen_until: Dictionary[int, float] = {}
var frozen_pin: Dictionary[int, Vector3] = {}
var down_until: Dictionary[int, float] = {}
var ball_safe_until: Dictionary[int, float] = {}
var thaw_until: Dictionary[int, float] = {}
var last_swing: Dictionary[int, float] = {}
## Ball, flat and relative to the wheel centre (x, z): position, velocity, turn rate (rad/s).
var ball_pos: Vector2 = Vector2.ZERO
var ball_vel: Vector2 = Vector2.ZERO
var ball_turn: float = 0.0
var seg_left: float = 0.0
## Players still on the wheel at the time cap, nearest the centre first (the final order).
var time_order: Array[int] = []
var winner: int = -1
## Fun stats: freezes landed, ball hits taken.
var freezes: Dictionary[int, int] = {}
var _sync_left: float = 0.0
var _announced: bool = false


func room_layout() -> Dictionary:
	return WheelRoom.layout()


func _on_room_setup(_context: Dictionary) -> void:
	id = &"roulette_sumo"
	for p: int in players:
		freezes[p] = 0
	# The ball starts on the rim track, rolling round it one way or the other.
	var a: float = rng.unit() * TAU
	ball_pos = Vector2(sin(a), cos(a)) * BALL_MAX_R
	var tangent := Vector2(cos(a), -sin(a)) * (1.0 if rng.unit() < 0.5 else -1.0)
	ball_vel = tangent * rng.range_float(BALL_MIN_SPEED, BALL_MAX_SPEED)
	ball_turn = 0.0
	seg_left = rng.range_float(SEG_MIN, SEG_MAX)


## No shove, no grab (so no throw): only the bat and the ball move people.
func blocked_intents() -> Array[StringName]:
	return [&"shove", &"grab", &"release"]


# --- The wheel (shared with the client) --------------------------------------------------------

## Angular speed of the wheel at game clock `t` (rad/s).
static func omega_at(t: float) -> float:
	return lerpf(OMEGA_START, OMEGA_MAX, clampf(t / RAMP_SECONDS, 0.0, 1.0))


## Wheel angle at game clock `t` (radians, the integral of `omega_at`).
static func wheel_angle(t: float) -> float:
	var ramp: float = clampf(t, 0.0, RAMP_SECONDS)
	var a: float = OMEGA_START * ramp + 0.5 * (OMEGA_MAX - OMEGA_START) / RAMP_SECONDS * ramp * ramp
	return a + OMEGA_MAX * maxf(t - RAMP_SECONDS, 0.0)


## Speed as shown on the gauge: x1.0 at the start, x4.8 at the cap.
static func speed_factor(omega: float) -> float:
	return omega / OMEGA_START


## True if `pos` (world) stands on the deck, where the wheel drags it.
static func on_deck(pos: Vector3) -> bool:
	var c: Vector3 = WheelRoom.center()
	var flat := Vector2(pos.x - c.x, pos.z - c.z)
	return flat.length() <= FALL_RADIUS and pos.y >= c.y + WheelRoom.WHEEL_TOP - 0.6


## Where the wheel carries a bean at `pos` (world) in `dt` seconds at speed `omega`: round the
## centre (counter-clockwise from above, like the rotor) and a little outward. Off the deck: as is.
static func drift(pos: Vector3, omega: float, dt: float) -> Vector3:
	if not on_deck(pos) or omega == 0.0 or dt <= 0.0:
		return pos
	var c: Vector3 = WheelRoom.center()
	var rel := Vector3(pos.x - c.x, 0.0, pos.z - c.z)
	rel = rel.rotated(Vector3.UP, omega * dt)
	rel *= 1.0 + SLIDE * omega * omega * dt
	return Vector3(c.x + rel.x, pos.y, c.z + rel.z)


## Flat distance of `pos` (world) from the wheel's centre.
static func flat_radius(pos: Vector3) -> float:
	var c: Vector3 = WheelRoom.center()
	return Vector2(pos.x - c.x, pos.z - c.z).length()


## One step of the ball (flat, relative to the centre): the velocity turns at `turn`, the ball
## moves, and bounces off the rim and the turret. Returns [pos, vel].
static func step_ball(pos: Vector2, vel: Vector2, turn: float, dt: float) -> Array[Vector2]:
	var v: Vector2 = vel.rotated(turn * dt)
	var p: Vector2 = pos + v * dt
	var r: float = p.length()
	if r > BALL_MAX_R:
		var n: Vector2 = p / r
		p = n * BALL_MAX_R
		if v.dot(n) > 0.0:
			v -= 2.0 * v.dot(n) * n
	elif r < BALL_MIN_R:
		var n: Vector2 = p / r if r > 0.001 else Vector2.RIGHT
		p = n * BALL_MIN_R
		if v.dot(n) < 0.0:
			v -= 2.0 * v.dot(n) * n
	return [p, v]


## The ball's centre in world coordinates (resting on the deck).
func ball_world() -> Vector3:
	return WheelRoom.center() + Vector3(ball_pos.x, WheelRoom.WHEEL_TOP + BALL_RADIUS, ball_pos.y)


func ball_wire() -> Dictionary:
	return {"p": [snappedf(ball_pos.x, 0.001), snappedf(ball_pos.y, 0.001)], "v": [snappedf(ball_vel.x, 0.001), snappedf(ball_vel.y, 0.001)], "t": snappedf(ball_turn, 0.0001)}


# --- Tick --------------------------------------------------------------------------------------

func tick(delta: float, _now: float) -> void:
	if finished:
		return
	if not _announced:
		# The stage only exists after the curtain: say it from the first tick (and in the state).
		_announced = true
		events.append(GameEvents.make(&"roulette_sumo_begin", {"players": alive.duplicate(), "seconds": GAME_SECONDS}))
		_sync()
	if state == State.DONE:
		wait_left -= delta
		if wait_left <= 0.0:
			_finish()
		return
	clock = minf(clock + delta, GAME_SECONDS)
	var omega: float = omega_at(clock)
	for p: int in frozen_pin:
		frozen_pin[p] = drift(frozen_pin[p], omega, delta)
	for p: int in frozen_until.keys():
		if clock >= frozen_until[p]:
			_thaw(p)
	for p: int in down_until.keys():
		if clock >= down_until[p]:
			down_until.erase(p)
	_tick_ball(delta)
	_sync_left -= delta
	if _sync_left <= 0.0:
		_sync()
	_check_ball_hits()
	_check_falls()
	if alive.size() <= 1:
		_end_game(&"last_bean")
	elif clock >= GAME_SECONDS:
		_end_game(&"time")


func _sync() -> void:
	_sync_left = SYNC_INTERVAL
	events.append(GameEvents.make(&"roulette_sumo_wheel", {"clock": snappedf(clock, 0.001), "angle": snappedf(wheel_angle(clock), 0.0001), "omega": snappedf(omega_at(clock), 0.0001)}))
	events.append(GameEvents.make(&"roulette_sumo_ball", {"ball": ball_wire(), "clock": snappedf(clock, 0.001)}))


func _tick_ball(delta: float) -> void:
	seg_left -= delta
	if seg_left <= 0.0:
		seg_left = rng.range_float(SEG_MIN, SEG_MAX)
		var speed: float = rng.range_float(BALL_MIN_SPEED, BALL_MAX_SPEED)
		ball_turn = rng.range_float(-BALL_MAX_TURN, BALL_MAX_TURN)
		var dir: Vector2 = ball_vel.normalized() if ball_vel.length() > 0.01 else Vector2.RIGHT
		ball_vel = dir * speed
		events.append(GameEvents.make(&"roulette_sumo_ball", {"ball": ball_wire(), "clock": snappedf(clock, 0.001)}))
	var res: Array[Vector2] = step_ball(ball_pos, ball_vel, ball_turn, delta)
	ball_pos = res[0]
	ball_vel = res[1]


## The server's own position of `p`: the pin while frozen, else the last accepted report.
func server_position(p: int) -> Vector3:
	if frozen_pin.has(p):
		return frozen_pin[p]
	if world != null and world.positions.has(p):
		return world.get_position(p)
	return Vector3.INF


func _check_ball_hits() -> void:
	var b: Vector3 = ball_world()
	var deck_y: float = WheelRoom.center().y + WheelRoom.WHEEL_TOP
	for p: int in alive.duplicate():
		if is_down(p) or clock < float(ball_safe_until.get(p, -INF)):
			continue
		var at: Vector3 = server_position(p)
		if at == Vector3.INF or at.y < deck_y - 0.5 or at.y > deck_y + BALL_RADIUS * 2.0:
			continue
		if Vector2(at.x - b.x, at.z - b.z).length() <= BALL_HIT:
			_ball_hit(p)


func _ball_hit(p: int) -> void:
	_thaw(p)
	down_until[p] = clock + KNOCK_SECONDS
	ball_safe_until[p] = clock + KNOCK_SECONDS + BALL_GRACE
	var dir: Vector2 = ball_vel.normalized() if ball_vel.length() > 0.01 else Vector2.RIGHT
	pending_knockdowns.append({"player": p, "seconds": KNOCK_SECONDS, "cause": &"ball"})
	events.append(GameEvents.make(&"roulette_sumo_ball_hit", {"player": p, "dir": [snappedf(dir.x, 0.001), snappedf(dir.y, 0.001)], "seconds": KNOCK_SECONDS}))


func _check_falls() -> void:
	var deck_y: float = WheelRoom.center().y + WheelRoom.WHEEL_TOP
	var fell: Array[int] = []
	for p: int in alive:
		var at: Vector3 = server_position(p)
		if at == Vector3.INF:
			continue
		if flat_radius(at) > FALL_RADIUS or at.y < deck_y - FALL_DEPTH:
			fell.append(p)
	if fell.is_empty():
		return
	for p: int in fell:
		_thaw(p)
		down_until.erase(p)
	eliminate(fell, &"fell", FALL_KNOCK)


func is_frozen(p: int) -> bool:
	return frozen_until.has(p)


func is_down(p: int) -> bool:
	return down_until.has(p)


func _thaw(p: int) -> void:
	if not frozen_until.has(p):
		return
	frozen_until.erase(p)
	frozen_pin.erase(p)
	if state == State.PLAYING and p in alive:
		thaw_until[p] = clock + THAW_GRACE
		events.append(GameEvents.make(&"roulette_sumo_thawed", {"player": p}))


## A frozen bean stays at its drifting pin (a report near it is fine: the client drifts too).
func clamp_position(player: int, pos: Vector3) -> Vector3:
	if frozen_pin.has(player) and player in alive and player in players and not finished:
		var pin: Vector3 = frozen_pin[player]
		var slack: float = PIN_SLACK + omega_at(clock) * flat_radius(pin) * PIN_LAG
		var off := Vector2(pos.x - pin.x, pos.z - pin.z)
		return pos if off.length() <= slack and absf(pos.y - pin.y) <= 1.0 else pin
	return super.clamp_position(player, pos)


## The ragdoll stood up: the down ends now.
func on_player_got_up(player: int) -> void:
	down_until.erase(player)


# --- The bat ----------------------------------------------------------------------------------

func _on_action(player: int, kind: StringName, hint: int, _now: float) -> Dictionary:
	if state != State.PLAYING:
		return StationLogicBase.fail(&"game_over")
	if kind != &"swing":
		return StationLogicBase.fail(&"bad_value")
	if is_down(player):
		return StationLogicBase.fail(&"down")
	if is_frozen(player):
		return StationLogicBase.fail(&"frozen")
	if clock < float(last_swing.get(player, -INF)) + SWING_COOLDOWN:
		return StationLogicBase.fail(&"cooldown")
	last_swing[player] = clock
	var exclude: Array[int] = []
	for p: int in alive:
		if is_down(p) or is_frozen(p) or clock < float(thaw_until.get(p, -INF)):
			exclude.append(p)
	var target: int = pick_target(player, hint, BAT_REACH, exclude)
	var result: StringName = &"hit"
	if target < 0:
		var shielded: int = pick_target(player, hint, BAT_REACH)
		if shielded >= 0 and not is_down(shielded):
			target = shielded
			result = &"frozen" if is_frozen(shielded) else &"thawing"
		else:
			result = &"miss"
	events.append(GameEvents.make(&"roulette_sumo_swing", {"player": player, "target": target, "result": result}))
	if result == &"hit":
		_freeze(target, player)
	return {"ok": true, "error": &"", "target": target, "result": result}


func _freeze(target: int, by: int) -> void:
	var at: Vector3 = server_position(target)
	if at == Vector3.INF:
		at = spawn_for(target)
	frozen_until[target] = clock + FREEZE_SECONDS
	frozen_pin[target] = at
	thaw_until.erase(target)
	freezes[by] = freezes.get(by, 0) + 1
	events.append(GameEvents.make(&"roulette_sumo_frozen", {"player": by, "target": target, "seconds": FREEZE_SECONDS}))


# --- End ----------------------------------------------------------------------------------------

func remove_player(player: int) -> void:
	frozen_until.erase(player)
	frozen_pin.erase(player)
	down_until.erase(player)
	super.remove_player(player)
	if not finished and state == State.PLAYING and _announced and alive.size() <= 1:
		_end_game(&"last_bean")


func _end_game(reason: StringName) -> void:
	if state == State.DONE:
		return
	state = State.DONE
	for p: int in frozen_until.keys():
		_thaw(p)
	if reason == &"time" and alive.size() > 1:
		time_order = alive.duplicate()
		time_order.sort_custom(func(a: int, b: int) -> bool:
			var ra: float = _radius_of(a)
			var rb: float = _radius_of(b)
			return ra < rb if not is_equal_approx(ra, rb) else a < b)
	var rows: Array[Dictionary] = ranking()
	winner = int(rows[0]["player"]) if not rows.is_empty() and (rows.size() == 1 or int(rows[1]["rank"]) > 1) else -1
	wait_left = END_HOLD
	events.append(GameEvents.make(&"roulette_sumo_over", {"reason": reason, "winner": winner, "ranking": rows}))


func _radius_of(p: int) -> float:
	var at: Vector3 = server_position(p)
	return flat_radius(at) if at != Vector3.INF else INF


func _finish() -> void:
	finished = true
	events.append(GameEvents.make(&"roulette_sumo_finished", {"ranking": ranking()}))


## Last bean on the wheel first (at the time cap: the ones still on by distance from the centre,
## nearest first), then reverse order of falling off; a group that fell together shares a rank.
## `points` = players outlasted.
func ranking() -> Array[Dictionary]:
	if time_order.is_empty():
		return elimination_ranking()
	var groups: Array = []
	for p: int in time_order:
		if p in players:
			groups.append([p])
	for i: int in range(out_groups.size() - 1, -1, -1):
		var g: Array[int] = []
		for p: int in out_groups[i]:
			if p in players:
				g.append(p)
		if not g.is_empty():
			g.sort()
			groups.append(g)
	var out: Array[Dictionary] = []
	var rank: int = 1
	var below: int = players.size()
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
	st["angle"] = snappedf(wheel_angle(clock), 0.0001)
	st["omega"] = snappedf(omega_at(clock), 0.0001)
	st["ball"] = ball_wire()
	var fz: Dictionary = {}
	for p: int in frozen_until:
		fz[p] = snappedf(maxf(frozen_until[p] - clock, 0.0), 0.01)
	st["frozen"] = fz
	var dn: Dictionary = {}
	for p: int in down_until:
		dn[p] = snappedf(maxf(down_until[p] - clock, 0.0), 0.01)
	st["down"] = dn
	st["winner"] = winner
	if finished or state == State.DONE:
		st["ranking"] = ranking()
	return st


func private_state(player: int) -> Dictionary:
	return {"cooldown": snappedf(maxf(float(last_swing.get(player, -INF)) + SWING_COOLDOWN - clock, 0.0), 0.01)}
