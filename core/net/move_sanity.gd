class_name MoveSanity
extends RefCounted
## Server-side checks on client-reported movement (§2.20): speed, teleports and leaving the map.
## A rejected move means "snap the client back to the last good position".

## Fastest legitimate horizontal speed (sprint + shove/door impulses), m/s.
var max_speed: float = 16.0
## Distance always allowed per report regardless of time (jitter, small corrections), m.
var slack: float = 1.5
## Playable volume (the casino, the start room, the waiting room behind it, the VIP lounge behind
## the north wall and the Race Hall east of the casino, with some margin).
var bounds: AABB = AABB(Vector3(-23.5, -3.0, -27.5), Vector3(61.0, 13.0, 52.0))
## Volumes inside `bounds` that are shut right now: the waiting room once the match started (its
## door is locked). A move into one is off the map.
var closed_bounds: Array[AABB] = []
## Extra playable volumes while they are open: a walkable minigame room far from the casino
## (`WalkableLogicBase.ROOM_ORIGIN`). Without it every move in the room was "off the map" and the
## client snapped back to its spawn (0.9.2: stuck at the start of Pass the Bomb).
var extra_bounds: Array[AABB] = []

## Fastest legitimate vertical speed (a jump, a fall from the mezzanine), m/s.
var max_vertical_speed: float = 12.0
## How long the point a player's moves are measured from stays put, seconds. The allowance is
## `max_speed × time since the anchor + slack`, so sending more reports buys no extra distance
## (it used to be `slack` per report: N reports in one server frame moved N × 1.5 m).
var anchor_seconds: float = 0.5
## After a server move: how far from where the server put the player, or from where they stood
## before it, a report may be (an honest client is at one of the two until it has seen the move).
var grace_radius: float = 3.0

var _last_pos: Dictionary[int, Vector3] = {}
var _last_time: Dictionary[int, float] = {}
var _anchor_pos: Dictionary[int, Vector3] = {}
var _anchor_time: Dictionary[int, float] = {}
var _grace_until: Dictionary[int, float] = {}
var _grace_from: Dictionary[int, Vector3] = {}
var _grace_to: Dictionary[int, Vector3] = {}


## Accepts or rejects a reported position at server time `now`. Returns true if accepted.
func check(player: int, pos: Vector3, now: float) -> bool:
	if not pos.is_finite() or not in_bounds(pos):
		return false
	if not _last_pos.has(player):
		_accept(player, pos, now)
		_anchor(player, pos, now)
		return true
	if now < _grace_until.get(player, -INF):
		# The server just moved this player: until the client has seen that, its reports still
		# come from around the old spot; afterwards from around the new one. Nowhere else.
		var reach: float = grace_radius + max_speed * maxf(now - _anchor_time.get(player, now), 0.0)
		if not _near(pos, _grace_to.get(player, pos), reach) and not _near(pos, _grace_from.get(player, pos), reach):
			return false
		_accept(player, pos, now)
		return true
	if _grace_to.has(player):
		# The grace just ran out: measure from wherever the reports had got to by then.
		_grace_to.erase(player)
		_grace_from.erase(player)
		_anchor(player, _last_pos[player], _last_time[player])
	var dt: float = maxf(now - _anchor_time[player], 0.0)
	var flat: Vector3 = pos - _anchor_pos[player]
	var vertical: float = absf(flat.y)
	flat.y = 0.0
	if flat.length() > max_speed * dt + slack or vertical > max_vertical_speed * dt + slack * 2.0:
		return false
	_accept(player, pos, now)
	if dt >= anchor_seconds:
		_anchor(player, pos, now)
	return true


## Drops everything known about a player who left (the dictionaries would only grow).
func forget(player: int) -> void:
	for d: Dictionary in [_last_pos, _last_time, _anchor_pos, _anchor_time, _grace_until, _grace_from, _grace_to]:
		d.erase(player)


## True if `pos` is inside the casino volume (outside a shut room) or an open extra volume (a
## minigame room).
func in_bounds(pos: Vector3) -> bool:
	for shut: AABB in closed_bounds:
		if shut.has_point(pos):
			return false
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


## The server moved the player itself (respawn, seat, got up, a minigame room): for `seconds`
## reports from around the old spot (not seen yet) and around the new one are both plausible.
func allow_teleport(player: int, pos: Vector3, now: float, seconds: float = 1.0) -> void:
	var was_in_grace: bool = now < _grace_until.get(player, -INF)
	if not was_in_grace:
		_grace_from[player] = _last_pos.get(player, pos)
	_grace_to[player] = pos
	_accept(player, pos, now)
	_anchor(player, pos, now)
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


func _anchor(player: int, pos: Vector3, now: float) -> void:
	_anchor_pos[player] = pos
	_anchor_time[player] = now


static func _near(a: Vector3, b: Vector3, radius: float) -> bool:
	return Vector2(a.x - b.x, a.z - b.z).length() <= radius and absf(a.y - b.y) <= radius * 2.0
