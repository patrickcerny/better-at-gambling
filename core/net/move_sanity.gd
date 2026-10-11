class_name MoveSanity
extends RefCounted
## Server-side checks on client-reported movement (§2.20): speed, teleports and leaving the map.
## A rejected move means "snap the client back to the last good position".

## Fastest legitimate horizontal speed (sprint + shove/door impulses), m/s.
var max_speed: float = 16.0
## Distance always allowed per report regardless of time (jitter, small corrections), m.
var slack: float = 1.5
## Playable volume (the casino, the start room, the porch and the VIP lounge behind the north
## wall, with some margin).
var bounds: AABB = AABB(Vector3(-23.5, -3.0, -27.5), Vector3(47.0, 13.0, 49.5))
## Extra playable volumes while they are open: a walkable minigame room far from the casino
## (`WalkableLogicBase.ROOM_ORIGIN`). Without it every move in the room was "off the map" and the
## client snapped back to its spawn (0.9.2: stuck at the start of Pass the Bomb).
var extra_bounds: Array[AABB] = []

var _last_pos: Dictionary[int, Vector3] = {}
var _last_time: Dictionary[int, float] = {}
var _grace_until: Dictionary[int, float] = {}


## Accepts or rejects a reported position at server time `now`. Returns true if accepted.
func check(player: int, pos: Vector3, now: float) -> bool:
	if not pos.is_finite() or not in_bounds(pos):
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


## True if `pos` is inside the casino volume or an open extra volume (a minigame room).
func in_bounds(pos: Vector3) -> bool:
	if bounds.has_point(pos):
		return true
	for box: AABB in extra_bounds:
		if box.has_point(pos):
			return true
	return false


## A walkable minigame room opened: moves inside `box` are plausible until `close_room`.
func open_room(box: AABB) -> void:
	extra_bounds = [box]


func close_room() -> void:
	extra_bounds.clear()


## The server moved the player itself (respawn, seat, got up): accept anything for `seconds`.
func allow_teleport(player: int, pos: Vector3, now: float, seconds: float = 1.0) -> void:
	_accept(player, pos, now)
	_grace_until[player] = now + seconds


## True while a server move (`allow_teleport`) is fresh: a report from before the client saw it is
## expected, not a cheat (one round trip of lag), so the snap-back is logged quietly.
func in_teleport_grace(player: int, now: float) -> bool:
	return now < _grace_until.get(player, -INF)


## Last accepted position (Vector3.INF if none).
func last_good(player: int) -> Vector3:
	return _last_pos.get(player, Vector3.INF)


func _accept(player: int, pos: Vector3, now: float) -> void:
	_last_pos[player] = pos
	_last_time[player] = now
