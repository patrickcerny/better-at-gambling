class_name WalkableLogicBase
extends MinigameLogicBase
## Server rules of a walkable minigame ("W"): the real avatars play in a room built far from the
## casino instead of on a stage with puppets. Still pure logic (no nodes); the MatchServer glues it
## to the world:
## - `room_layout()` (subclass): the room's arena AABB, per-player spawn points and the spectator
##   gallery eliminated players watch from. All in world coordinates (rooms sit at `ROOM_ORIGIN`).
## - At the start the server puts every participant on `spawn_for(player)` and sends the room in
##   `minigame_started.room`; while the game (and its rewards) run it keeps every reported position
##   inside `clamp_position(player, pos)` (alive: the arena, out: the gallery), like the jail cell.
## - `world` is the server's `WorldQuery` (set before the first tick): decisions come from its
##   positions and facings, never from client claims. `pick_target` is the shove-style reach pick.
## - The action button (E) arrives as `minigame_action {kind, target?}` → `_on_action`.
## - `eliminate(players, cause)` takes players out (the server knocks them down if `knockdown_s`
##   > 0, then moves them to the gallery); `elimination_ranking()` ranks by reverse elimination.
## - `BLOCKED_INTENTS` plus `blocked_intents()` are refused with `minigame` while the room runs.

## Where walkable rooms are built: far east of the casino floor (and away from the stage origin).
const ROOM_ORIGIN: Vector3 = Vector3(200, 0, 0)
## A clamped position further than this from the allowed box is a teleport to the player's spot
## (a small step against the bound is just held at the bound), as in the jail cell.
const SNAP_DISTANCE: float = 1.5
## Casino intents no walkable game allows (stations, items, the shop, tips, the megaphone).
const BLOCKED_INTENTS: Array[StringName] = [&"sit", &"use_item", &"shop_buy", &"megaphone", &"place_bet", &"action", &"rps_pick"]

## Server world view (positions, facings). Null in pure unit tests that never pick targets.
var world: WorldQuery = null
## Arena (alive players) and gallery (eliminated players), world coordinates.
var arena: AABB = AABB()
var gallery: AABB = AABB()
var spawns: Array[Vector3] = []
var spawn_yaws: Array[float] = []
var gallery_spots: Array[Vector3] = []
## Players still in play, and the elimination groups in order ([[p], [q, r], ...]).
var alive: Array[int] = []
var out_groups: Array = []
## Server-side requests drained by the MatchServer each tick:
## player → position to teleport to (the gallery after an elimination).
var pending_moves: Dictionary[int, Vector3] = {}
## [{player, seconds, cause, attacker?}] knockdowns (ragdolls) the server applies (`attacker`
## only steers which way the body flies).
var pending_knockdowns: Array[Dictionary] = []
## Who started (spawn index is their place in this list).
var roster: Array[int] = []
## The game's registry id (for the snapshot's `minigame` key).
var id: StringName = &""


func _on_setup(context: Dictionary) -> void:
	roster = players.duplicate()
	alive = players.duplicate()
	var layout: Dictionary = room_layout()
	arena = layout.get("arena", AABB())
	gallery = layout.get("gallery", AABB())
	spawns.assign(layout.get("spawns", []))
	spawn_yaws.assign(layout.get("spawn_yaws", []))
	gallery_spots.assign(layout.get("gallery_spots", []))
	_on_room_setup(context)


## Subclass: {arena: AABB, gallery: AABB, spawns: Array[Vector3], spawn_yaws: Array[float],
## gallery_spots: Array[Vector3]} in world coordinates.
func room_layout() -> Dictionary:
	return {}


## Subclass hook after the room is known (instead of `_on_setup`).
func _on_room_setup(_context: Dictionary) -> void:
	pass


## Subclass: intents this game also refuses (e.g. Roulette Sumo: shove, grab).
func blocked_intents() -> Array[StringName]:
	return []


## Subclass: true while `player` can't be shoved or grabbed (Last Seat: seated on a stool). The
## server treats them like a casino-seated player for those intents.
func is_untouchable(_player: int) -> bool:
	return false


func blocks_intent(type: StringName) -> bool:
	return type in BLOCKED_INTENTS or type in blocked_intents()


## The room as sent in `minigame_started.room` and the snapshot: spawn per player, the bounds.
func room_wire() -> Dictionary:
	var sp: Dictionary = {}
	var yaws: Dictionary = {}
	for p: int in roster:
		sp[p] = Serializer.vec3(spawn_for(p))
		yaws[p] = snappedf(spawn_yaw_for(p), 0.001)
	return {"id": id, "spawns": sp, "yaws": yaws, "arena": _aabb_wire(arena), "gallery": _aabb_wire(gallery)}


func spawn_for(player: int) -> Vector3:
	var i: int = maxi(roster.find(player), 0)
	return spawns[i % spawns.size()] if not spawns.is_empty() else ROOM_ORIGIN


func spawn_yaw_for(player: int) -> float:
	var i: int = maxi(roster.find(player), 0)
	return spawn_yaws[i % spawn_yaws.size()] if not spawn_yaws.is_empty() else 0.0


func gallery_spot_for(player: int) -> Vector3:
	var i: int = maxi(roster.find(player), 0)
	return gallery_spots[i % gallery_spots.size()] if not gallery_spots.is_empty() else spawn_for(player)


func is_alive(player: int) -> bool:
	return player in alive


## Where `player` may be: alive in the arena, out in the gallery. A step past the bound is held at
## it; anything further (a glitch, a thrown body, the casino) is their spot. Non-participants
## (late joiners, dropouts) are left alone.
func clamp_position(player: int, pos: Vector3) -> Vector3:
	if player not in roster or player not in players:
		return pos
	var box: AABB = arena if player in alive else gallery
	if box.size == Vector3.ZERO or box.has_point(pos):
		return pos
	var inside: Vector3 = pos.clamp(box.position, box.end)
	if inside.distance_to(pos) < SNAP_DISTANCE:
		return inside
	return spawn_for(player) if player in alive else gallery_spot_for(player)


## The action button: `minigame_action {kind, target?}`. Validates the sender, then `_on_action`.
func submit(player: int, intent: Dictionary, now: float) -> Dictionary:
	if StringName(intent.get("type", &"")) != &"minigame_action":
		return StationLogicBase.fail(&"not_implemented")
	if finished:
		return StationLogicBase.fail(&"game_over")
	if player not in players:
		return StationLogicBase.fail(&"unknown_player")
	if player not in alive:
		return StationLogicBase.fail(&"eliminated")
	var kind: Variant = intent.get("kind", "")
	if not (kind is String or kind is StringName):
		return StationLogicBase.fail(&"bad_value")
	var raw: Variant = intent.get("target", -1)
	var hint: int = int(raw) if typeof(raw) in [TYPE_INT, TYPE_FLOAT] else -1
	return _on_action(player, StringName(kind), hint, now)


## The server saw `player`'s ragdoll stand up again (`MatchServer.report_got_up`). Subclass hook.
func on_player_got_up(_player: int) -> void:
	pass


## A shove by `attacker` landed on `target` (`MatchServer` calls this once the shove resolves,
## from its own positions). Subclass hook (Grab Your Hand: the target drops a card).
func on_shoved(_target: int, _attacker: int) -> void:
	pass


## A throw by `attacker` launched `target` (the casino's grab and throw, `MatchServer` calls this
## once the release resolves). Subclass hook (Bat Heist: the thrown bean is knocked down).
func on_thrown(_target: int, _attacker: int) -> void:
	pass


## Subclass: the action button. {ok, error} (StationLogicBase.OK_RESULT / fail).
func _on_action(_player: int, _kind: StringName, _hint: int, _now: float) -> Dictionary:
	return StationLogicBase.fail(&"not_implemented")


## The alive player `player` reaches (shove-style: in front of them within `range_m`, the client's
## `hint` first with lag slack), or -1, never one of `exclude`. Uses the server's own positions
## and facing.
func pick_target(player: int, hint: int, range_m: float, exclude: Array[int] = []) -> int:
	if world == null or not world.positions.has(player):
		return -1
	var origin: Vector3 = world.get_position(player)
	var facing: Vector3 = world.get_facing(player)
	if hint >= 0 and hint != player and hint in alive and hint not in exclude and world.positions.has(hint):
		if InteractionRules.reach_score(origin, facing, world.get_position(hint), range_m + InteractionRules.LAG_SLACK) < INF:
			return hint
	var candidates: Dictionary = {}
	for p: int in alive:
		if p != player and p not in exclude and world.positions.has(p):
			candidates[p] = world.get_position(p)
	return InteractionRules.pick_in_reach(origin, facing, candidates, player, range_m)


## Takes `who` out together (they share a place). They are knocked down for `knockdown_s` seconds
## (0 = no ragdoll) and then moved to the gallery. Emits `minigame_eliminated`.
func eliminate(who: Array[int], cause: StringName, knockdown_s: float = 0.0) -> void:
	var group: Array[int] = []
	for p: int in who:
		if p in alive:
			alive.erase(p)
			group.append(p)
	if group.is_empty():
		return
	out_groups.append(group)
	var place: int = alive.size() + 1
	for p: int in group:
		if p in players:
			pending_moves[p] = gallery_spot_for(p)
			if knockdown_s > 0.0:
				pending_knockdowns.append({"player": p, "seconds": knockdown_s, "cause": cause})
	events.append(GameEvents.make(&"minigame_eliminated", {"players": group, "cause": cause, "place": place, "alive": alive.duplicate()}))


## A dropout is out at that moment (and leaves the ranking like in every minigame).
func remove_player(player: int) -> void:
	if player in alive:
		eliminate([player], &"dropout")
	pending_moves.erase(player)
	super.remove_player(player)


## Reverse elimination order: whoever is still alive shares 1st, then the last group out, and so
## on; a group out at the same moment shares its rank. `points` = players outlasted.
func elimination_ranking() -> Array[Dictionary]:
	var groups: Array = []
	var survivors: Array[int] = []
	for p: int in alive:
		if p in players:
			survivors.append(p)
	if not survivors.is_empty():
		groups.append(survivors)
	for i: int in range(out_groups.size() - 1, -1, -1):
		var g: Array[int] = []
		for p: int in out_groups[i]:
			if p in players:
				g.append(p)
		if not g.is_empty():
			groups.append(g)
	var out: Array[Dictionary] = []
	var rank: int = 1
	var below: int = players.size()
	for g: Array in groups:
		g.sort()
		below -= g.size()
		for p: int in g:
			out.append({"player": p, "points": below, "rank": rank})
		rank += g.size()
	return out


func ranking() -> Array[Dictionary]:
	return elimination_ranking()


## The public state every walkable game shares (subclasses add theirs on top).
func walkable_state() -> Dictionary:
	var groups: Array = []
	for g: Array in out_groups:
		groups.append(g.duplicate())
	return {"minigame": id, "players": players.duplicate(), "alive": alive.duplicate(), "out": groups, "room": room_wire(), "finished": finished}


static func _aabb_wire(box: AABB) -> Array:
	return [Serializer.vec3(box.position), Serializer.vec3(box.size)]


static func aabb_from_wire(v: Variant) -> AABB:
	if not (v is Array) or (v as Array).size() < 2:
		return AABB()
	return AABB(Serializer.to_vec3(v[0]), Serializer.to_vec3(v[1]))
