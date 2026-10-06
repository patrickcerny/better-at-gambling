class_name InteractionRules
extends RefCounted
## Pure rules for physical play (§2.4.1): shove → knockdown/knockout counting, immunities,
## shake-for-chips amounts and caps, guard sight. Physics only *requests*; these rules decide.
## Time is passed in (match seconds) so tests are deterministic.

## Per-player physical status.
class Status:
	extends RefCounted
	var shove_hits: Array[float] = []
	var last_shove_given: float = -INF
	var knocked_down_until: float = -INF
	var knocked_out_until: float = -INF
	var ko_immune_until: float = -INF
	var protected_until: float = -INF
	var seated: bool = false
	var away: bool = false
	## Money shaken out during the current knockout and the cap for it.
	var shaken_this_ko: int = 0
	var shake_cap_this_ko: int = 0
	## attacker → time they started shaking this player.
	var shake_sessions: Dictionary[int, float] = {}

## Reach for shoves and grabs, centre to centre on the floor plane (two bean radii are 0.84 m of it).
const REACH: float = 2.2
## Extra distance the server allows for a target the client picked (it saw the world ~100-200 ms
## ago); at a sprint that is about half a metre.
const LAG_SLACK: float = 0.5
## Reach cone: cos of the half angle (~67°). Closer than `TOUCH_RANGE` anything not behind counts.
const CONE_DOT: float = 0.4
const TOUCH_RANGE: float = 1.0

var cfg: BalanceConfig
var _status: Dictionary[int, Status] = {}


## How well `target_pos` sits in the reach of someone at `origin` facing `facing` (lower is better:
## distance plus a penalty for being off-centre), or INF when out of reach. Client and server use
## the same function, so the prompt, the swing and the server's verdict agree.
static func reach_score(origin: Vector3, facing: Vector3, target_pos: Vector3, range_m: float = REACH) -> float:
	var to: Vector3 = target_pos - origin
	if absf(to.y) > 1.6:
		return INF  # different floor (balcony above, pit below)
	to.y = 0.0
	var d: float = to.length()
	if d > range_m:
		return INF
	if d < 0.05:
		return 0.0
	var fwd: Vector3 = Vector3(facing.x, 0.0, facing.z)
	if fwd.length() < 0.01:
		return d
	var dot: float = fwd.normalized().dot(to / d)
	var min_dot: float = -0.2 if d <= TOUCH_RANGE else CONE_DOT
	if dot < min_dot:
		return INF
	return d + (1.0 - dot) * 1.2


## The best target in reach among `positions` (player id → position), or -1.
static func pick_in_reach(origin: Vector3, facing: Vector3, positions: Dictionary, exclude: int, range_m: float = REACH) -> int:
	var best: int = -1
	var best_s: float = INF
	for pid: int in positions:
		if pid == exclude:
			continue
		var s: float = reach_score(origin, facing, positions[pid], range_m)
		if s < best_s:
			best_s = s
			best = pid
	return best


func _init(p_cfg: BalanceConfig) -> void:
	cfg = p_cfg


## Status object for a player (created on demand).
func status(player: int) -> Status:
	if not _status.has(player):
		_status[player] = Status.new()
	return _status[player]


## Grants spawn protection (after respawn or a minigame).
func protect(player: int, now: float) -> void:
	status(player).protected_until = now + cfg.spawn_protection


func is_knocked_out(player: int, now: float) -> bool:
	return now < status(player).knocked_out_until


func is_knocked_down(player: int, now: float) -> bool:
	return now < status(player).knocked_down_until or is_knocked_out(player, now)


## Why `target` can't be touched right now (&"" if it can). `bypass_seat` for Bouncer/guards.
func immunity_reason(target: int, now: float, bypass_seat: bool = false) -> StringName:
	var s: Status = status(target)
	if s.away:
		return &"away"
	if now < s.protected_until:
		return &"spawn_protected"
	if s.seated and not bypass_seat:
		return &"seated"
	return &""


## Resolves a shove request. Returns {ok, error, knockdown, knockout}.
func shove(attacker: int, target: int, now: float, target_airborne: bool = false, spring_glove: bool = false) -> Dictionary:
	var res: Dictionary = {"ok": false, "error": &"", "knockdown": false, "knockout": false}
	if attacker == target:
		res["error"] = &"self"
		return res
	var a: Status = status(attacker)
	if now - a.last_shove_given < cfg.shove_cooldown:
		res["error"] = &"cooldown"
		return res
	var why: StringName = immunity_reason(target, now)
	if why != &"":
		res["error"] = why
		return res
	a.last_shove_given = now
	res["ok"] = true
	var t: Status = status(target)
	var recent_window: float = maxf(cfg.shove_knockdown_window, cfg.shove_knockout_window)
	var kept: Array[float] = []
	for h: float in t.shove_hits:
		if now - h <= recent_window:
			kept.append(h)
	t.shove_hits = kept
	t.shove_hits.append(now)
	if now < t.ko_immune_until or is_knocked_out(target, now):
		return res
	var in_ko_window: int = 0
	var in_kd_window: int = 0
	for h: float in t.shove_hits:
		if now - h <= cfg.shove_knockout_window:
			in_ko_window += 1
		if now - h <= cfg.shove_knockdown_window:
			in_kd_window += 1
	if in_ko_window >= cfg.shove_knockout_count:
		knock_out(target, now)
		res["knockout"] = true
	elif target_airborne or spring_glove or in_kd_window >= 2:
		t.knocked_down_until = now + cfg.knockdown_time
		res["knockdown"] = true
	return res


## Knocks a player down for `seconds` (shoved into a wall). Returns false if they're out already.
func knock_down(target: int, now: float, seconds: float = -1.0) -> bool:
	if is_knocked_out(target, now) or status(target).away:
		return false
	var t: Status = status(target)
	t.knocked_down_until = maxf(t.knocked_down_until, now + (cfg.knockdown_time if seconds < 0.0 else seconds))
	return true


## Knocks a player out (thrown into a wall, fell from the mezzanine, 3 shoves…). Returns false if immune.
func knock_out(target: int, now: float, money: int = -1, limits_multiplier: float = 1.0) -> bool:
	var t: Status = status(target)
	if now < t.ko_immune_until or t.away:
		return false
	t.knocked_out_until = now + cfg.knockout_time
	t.ko_immune_until = t.knocked_out_until + cfg.knockout_immunity
	t.shaken_this_ko = 0
	t.shake_cap_this_ko = -1 if money < 0 else shake_cap(money, limits_multiplier)
	t.shove_hits.clear()
	return true


## Turns a knockout that was just decided back into a knockdown (Bodyguard absorbed it).
func cancel_knockout(target: int, now: float) -> void:
	var t: Status = status(target)
	t.knocked_out_until = -INF
	t.ko_immune_until = -INF
	t.knocked_down_until = now + cfg.knockdown_time


## Maximum total that can be shaken out of one knockout.
func shake_cap(money: int, limits_multiplier: float) -> int:
	var cap_amount: int = int(floor(cfg.shake_cap_amount * limits_multiplier))
	return mini(int(floor(money * cfg.shake_cap_fraction)), cap_amount)


## Resolves one shake. `money` is the victim's current balance. Returns the dollars to drop as
## chip piles (0 if not allowed); the caller moves the money through the Economy.
func shake(attacker: int, target: int, now: float, money: int, limits_multiplier: float = 1.0) -> Dictionary:
	var res: Dictionary = {"ok": false, "error": &"", "amount": 0}
	if not is_knocked_out(target, now):
		res["error"] = &"not_knocked_out"
		return res
	var t: Status = status(target)
	if t.away:
		res["error"] = &"away"
		return res
	var started: float = t.shake_sessions.get(attacker, -INF)
	var this_ko_start: float = t.knocked_out_until - cfg.knockout_time
	if started < this_ko_start and now - started < cfg.shake_same_attacker_cooldown:
		res["error"] = &"same_attacker_cooldown"
		return res
	if started < this_ko_start:
		t.shake_sessions[attacker] = now
	if t.shake_cap_this_ko < 0:
		t.shake_cap_this_ko = shake_cap(money, limits_multiplier)
	var per_shake: int = maxi(int(floor(money * cfg.shake_fraction)), cfg.shake_min)
	var amount: int = mini(per_shake, t.shake_cap_this_ko - t.shaken_this_ko)
	amount = mini(amount, money)
	if amount <= 0:
		res["error"] = &"cap_reached"
		return res
	t.shaken_this_ko += amount
	res["ok"] = true
	res["amount"] = amount
	return res


## True if a guard at `guard_pos` looking along `guard_forward` sees `target_pos`
## (within range and the sight cone; `line_of_sight` comes from a physics raycast).
func guard_sees(guard_pos: Vector3, guard_forward: Vector3, target_pos: Vector3, line_of_sight: bool) -> bool:
	if not line_of_sight:
		return false
	var to_target: Vector3 = target_pos - guard_pos
	to_target.y = 0.0
	var dist: float = to_target.length()
	if dist > cfg.guard_sight_range:
		return false
	if dist < 0.001:
		return true
	var fwd: Vector3 = Vector3(guard_forward.x, 0.0, guard_forward.z).normalized()
	var angle: float = rad_to_deg(fwd.angle_to(to_target.normalized()))
	return angle <= cfg.guard_sight_half_angle_deg
