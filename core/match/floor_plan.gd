class_name FloorPlan
extends RefCounted
## The casino floor of one round (docs/FLOOR_PLAN.md): one of the hand-made layouts
## (`FloorLayout`), in wire form {station id: [game, [x, y, z], yaw degrees]}. Pure helpers: the
## server picks the layout (`FloorRotation`), every client builds the stations straight from the
## wire form, and `problems` says whether a layout fits the map (`FloorGeometry`).


## One station of a plan in wire form.
static func entry(game: StringName, pos: Vector3, yaw_degrees: float) -> Array:
	return [game, Serializer.vec3(pos), yaw_degrees]


## The game of a wire entry.
static func game_of(e: Array) -> StringName:
	return StringName(e[0])


## Where a wire entry stands (floor level).
static func pos_of(e: Array) -> Vector3:
	var p: Variant = e[1]
	if p is Vector3:
		return p
	var a: Array = p
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


## Which way a wire entry faces, radians.
static func yaw_of(e: Array) -> float:
	return deg_to_rad(float(e[2]))


## The spots of a plan for `FloorGeometry`: station id → {id, pos, yaw (radians)}.
static func spots(plan: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for sid: Variant in plan:
		var e: Array = plan[sid]
		out[StringName(sid)] = {"id": StringName(sid), "pos": pos_of(e), "yaw": yaw_of(e)}
	return out


## Station id → game of a plan.
static func games_of(plan: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for sid: Variant in plan:
		out[StringName(sid)] = game_of(plan[sid])
	return out


## Why a layout can't be used tonight (empty when it can): a game it needs is not registered or
## has weight 0 (`FloorPlanConfig.weights`), or, with `geo` (the map's measurements), a game stands
## outside the floor or on a keep-out, two games come closer than the gap, or the walkway check
## finds a chair or patrol point nobody can walk to.
static func problems(layout: FloorLayout, cfg: FloorPlanConfig, known_games: Dictionary, geo: FloorGeometry = null) -> Array[String]:
	var out: Array[String] = []
	if layout == null or layout.stations.is_empty():
		out.append("empty layout")
		return out
	for g: StringName in layout.games():
		if not known_games.has(g):
			out.append("%s: no such game" % g)
		elif cfg != null and cfg.weight_of(g) <= 0.0:
			out.append("%s is off (weight 0)" % g)
	if geo != null:
		out.append_array(fit_problems(layout.wire_stations(), geo))
	return out


## The geometry half of `problems` for a plan in wire form.
static func fit_problems(plan: Dictionary, geo: FloorGeometry) -> Array[String]:
	var out: Array[String] = []
	var by_id: Dictionary = spots(plan)
	var games: Dictionary = games_of(plan)
	var ids: Array = plan.keys()
	ids.sort()
	for sid: Variant in ids:
		var why: String = geo.why_not(by_id[sid], games[sid])
		if why != "":
			out.append("%s (%s): %s" % [sid, games[sid], why])
	for i: int in ids.size():
		for j: int in range(i + 1, ids.size()):
			var a: Rect2 = geo.world_rect(by_id[ids[i]], games[ids[i]])
			var b: Rect2 = geo.world_rect(by_id[ids[j]], games[ids[j]])
			if not geo.rects.has(games[ids[i]]) or not geo.rects.has(games[ids[j]]):
				continue
			if a.intersects(b) or FloorGeometry.separation(a, b) < geo.gap:
				out.append("%s and %s are %.2f m apart (gap %.2f)" % [ids[i], ids[j], FloorGeometry.separation(a, b), geo.gap])
	if geo.can_walk():
		for sid: StringName in geo.unreachable(games, by_id):
			out.append("%s (%s): cut off from the walkways" % [sid, games[sid]])
	return out
