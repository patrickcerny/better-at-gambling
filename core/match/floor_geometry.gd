class_name FloorGeometry
extends RefCounted
## Room for the floor plan's games (docs/FLOOR_PLAN.md), on the ground plane (x, z): how much floor
## each game takes (its table, chairs and dealer, measured from its station by the map), where
## tables may stand, what they must keep clear of (walls, bar, shop, jail, doors, patrol routes) and
## the walkway left between two tables. A game only goes on a spot where it fits and keeps the gap
## to the games already drawn round it. Pure (the map fills it in; tests without a map have none).

## Game id → its floor in its own frame (Rect2 over local x, z).
var rects: Dictionary = {}
## World rects tables may stand in (a game must lie wholly inside one) and rects they keep out of.
var areas: Array[Rect2] = []
var keep_out: Array[Rect2] = []
## Walkway between two tables, metres.
var gap: float = 0.6


## From a map definition (null when the map measured nothing).
static func of_map(def: MapDefinition, p_gap: float) -> FloorGeometry:
	if def == null or def.floor_rects.is_empty():
		return null
	var g := FloorGeometry.new()
	g.rects = def.floor_rects
	g.areas.assign(def.floor_areas)
	g.keep_out.assign(def.floor_keep_out)
	g.gap = p_gap
	return g


## A game's floor on a spot in world (x, z): its rect turned by the spot's yaw (the bounding box
## of the turned rect; spots face the four walls, so it is exact there).
func world_rect(anchor: Dictionary, game: StringName) -> Rect2:
	var r: Rect2 = rects.get(game, Rect2())
	var pos: Vector3 = anchor["pos"]
	var yaw: float = float(anchor["yaw"])
	var out := Rect2()
	var first: bool = true
	for c: Vector2 in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		# Node3D yaw turns local (x, z) the way Basis(Vector3.UP, yaw) does.
		var w: Vector3 = Vector3(c.x, 0.0, c.y).rotated(Vector3.UP, yaw) + pos
		var p := Vector2(w.x, w.z)
		if first:
			out = Rect2(p, Vector2.ZERO)
			first = false
		else:
			out = out.expand(p)
	return out


## True when the game fits the spot on its own: inside a floor area, clear of every keep-out.
func fits(anchor: Dictionary, game: StringName) -> bool:
	if not rects.has(game):
		return true  # unmeasured: trust the size class
	var w: Rect2 = world_rect(anchor, game)
	var inside: bool = false
	for a: Rect2 in areas:
		if a.encloses(w):
			inside = true
	if not inside and not areas.is_empty():
		return false
	for k: Rect2 in keep_out:
		if k.intersects(w):
			return false
	return true


## Why the game does not fit the spot ("" when it does), for test messages.
func why_not(anchor: Dictionary, game: StringName) -> String:
	if fits(anchor, game):
		return ""
	var w: Rect2 = world_rect(anchor, game)
	for k: Rect2 in keep_out:
		if k.intersects(w):
			return "%s hits keep-out %s" % [w, k]
	return "%s outside every area" % w


## True when the game on `anchor` keeps the walkway to every game already on the other spots
## (`placed`: anchor id → game, CLOSED for none; `by_id`: anchor id → anchor).
func clear_of(anchor: Dictionary, game: StringName, placed: Dictionary, by_id: Dictionary) -> bool:
	if not rects.has(game):
		return true
	var w: Rect2 = world_rect(anchor, game).grow(gap * 0.5)
	for id: Variant in placed:
		var other: StringName = StringName(placed[id])
		if other == FloorPlan.CLOSED or StringName(id) == StringName(anchor["id"]) or not rects.has(other):
			continue
		if w.intersects(world_rect(by_id[id], other).grow(gap * 0.5)):
			return false
	return true
