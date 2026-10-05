class_name MoveSanity
extends RefCounted
## Server-side checks on client-reported movement (§2.20): speed, teleports and leaving the map.
## A rejected move means "snap the client back to the last good position".

## Fastest legitimate horizontal speed (sprint + shove/door impulses), m/s.
var max_speed: float = 16.0
## Distance always allowed per report regardless of time (jitter, small corrections), m.
var slack: float = 1.5
## Playable volume (the casino, lobby and porch with some margin).
var bounds: AABB = AABB(Vector3(-23.5, -3.0, -17.0), Vector3(47.0, 13.0, 39.0))

var _last_pos: Dictionary[int, Vector3] = {}
var _last_time: Dictionary[int, float] = {}
var _grace_until: Dictionary[int, float] = {}


## Accepts or rejects a reported position at server time `now`. Returns true if accepted.
func check(player: int, pos: Vector3, now: float) -> bool:
	if not bounds.has_point(pos) or not pos.is_finite():
		return false
	if not _last_pos.has(player) or now < _grace_until.get(player, -INF):
		_accept(player, pos, now)
		return true
	var dt: float = maxf(now - _last_time[player], 0.0)
	var flat: Vector3 = pos - _last_pos[player]
	var vertical: float = absf(flat.y)
	flat.y = 0.0
	if flat.length() > max_speed * dt + slack or vertical > 12.0 * dt + slack * 2.0:
		return false
	_accept(player, pos, now)
	return true


## The server moved the player itself (respawn, seat, got up): accept anything for `seconds`.
func allow_teleport(player: int, pos: Vector3, now: float, seconds: float = 1.0) -> void:
	_accept(player, pos, now)
	_grace_until[player] = now + seconds


## Last accepted position (Vector3.INF if none).
func last_good(player: int) -> Vector3:
	return _last_pos.get(player, Vector3.INF)


func _accept(player: int, pos: Vector3, now: float) -> void:
	_last_pos[player] = pos
	_last_time[player] = now
