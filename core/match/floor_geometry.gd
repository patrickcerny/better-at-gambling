class_name FloorGeometry
extends RefCounted
## Room for the floor plan's games (docs/FLOOR_PLAN.md), on the ground plane (x, z): how much floor
## each game takes (its table, chairs and dealer, measured from its station by the map), where
## tables may stand, what they must keep clear of (walls, bar, shop, jail, doors, patrol routes),
## the gap between two tables, and a walkway check over the whole drawn floor (every chair and
## patrol point still reachable). Pure (the map fills it in; tests without a map have none).

## Walkway grid cell, metres.
const CELL: float = 0.25
## A chair counts as reachable when the open floor nearest it (within this) is reached from the
## entry (the physics test asks the navmesh the same), and a patrol point when it is this close.
const SEAT_REACH: float = 1.2
const POINT_REACH: float = 0.6
## Open islands smaller than this many cells don't count (the bake's region_min_size 2, squared).
const MIN_ISLAND: int = 4
## How much farther than the reachable floor a pocket next to a chair must be, metres.
const POCKET_MARGIN: float = 0.25
## A cut-off patrol point blames the nearest drawn game within this range.
const BLAME_RANGE: float = 3.0
## Grid margin round an area, metres (its walls are among the blockers).
const GRID_MARGIN: float = 1.0

## Game id → its floor in its own frame (Rect2 over local x, z).
var rects: Dictionary = {}
## Game id → its chairs in its own frame (Array of Vector2 x, z).
var seats: Dictionary = {}
## Game id → what of it the navmesh walks round (Rect2s, own frame); footprint → the same for a
## closed spot's dressing; everything else on the map the navmesh walks round (world Rect2s).
var obstacles: Dictionary = {}
var closed_obstacles: Dictionary = {}
var blockers: Array[Rect2] = []
## World rects tables may stand in (a game must lie wholly inside one) and rects they keep out of.
var areas: Array[Rect2] = []
var keep_out: Array[Rect2] = []
## Where people come into each area, and the points the guards and waiter walk to.
var entries: Array[Vector2] = []
var walk_points: Array[Vector2] = []
## Space between two tables (chair to chair), metres.
var gap: float = 0.35
## How far the navmesh keeps off walls and tables (its agent radius), metres.
var agent_radius: float = 0.5


## From a map definition (null when the map measured nothing).
static func of_map(def: MapDefinition, p_gap: float) -> FloorGeometry:
	if def == null or def.floor_rects.is_empty():
		return null
	var g := FloorGeometry.new()
	g.rects = def.floor_rects
	g.seats = def.floor_seats
	g.areas.assign(def.floor_areas)
	g.keep_out.assign(def.floor_keep_out)
	g.obstacles = def.floor_obstacles
	g.closed_obstacles = def.floor_closed_obstacles
	g.blockers.assign(def.floor_blockers)
	g.entries.assign(def.floor_entries)
	g.walk_points.assign(def.floor_walk_points)
	g.gap = p_gap
	return g


## A game's floor on a spot in world (x, z): its rect turned by the spot's yaw (the bounding box
## of the turned rect; spots face the four walls, so it is exact there).
func world_rect(anchor: Dictionary, game: StringName) -> Rect2:
	return _turned(anchor, rects.get(game, Rect2()))


## A rect in a spot's own frame, in world (x, z).
func _turned(anchor: Dictionary, r: Rect2) -> Rect2:
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


## Floor between two rects (0 when they touch or overlap).
static func separation(a: Rect2, b: Rect2) -> float:
	var dx: float = maxf(0.0, maxf(a.position.x - b.end.x, b.position.x - a.end.x))
	var dz: float = maxf(0.0, maxf(a.position.y - b.end.y, b.position.y - a.end.y))
	return Vector2(dx, dz).length()


## True when the game fits the spot on its own: inside a floor area, clear of every keep-out.
func fits(anchor: Dictionary, game: StringName) -> bool:
	return why_not(anchor, game) == ""


## Why the game does not fit the spot ("" when it does), for test messages.
func why_not(anchor: Dictionary, game: StringName) -> String:
	if not rects.has(game):
		return ""  # unmeasured: trust the size class
	var w: Rect2 = world_rect(anchor, game)
	var inside: bool = areas.is_empty()
	for a: Rect2 in areas:
		if a.encloses(w):
			inside = true
	if not inside:
		return "%s outside every area" % w
	for k: Rect2 in keep_out:
		if k.intersects(w):
			return "%s hits keep-out %s" % [w, k]
	return ""


## True when the game on `anchor` keeps `gap` to every game already on the other spots
## (`placed`: anchor id → game, CLOSED for none; `by_id`: anchor id → anchor).
func clear_of(anchor: Dictionary, game: StringName, placed: Dictionary, by_id: Dictionary) -> bool:
	if not rects.has(game):
		return true
	var w: Rect2 = world_rect(anchor, game)
	for id: Variant in placed:
		var other: StringName = StringName(placed[id])
		if other == FloorPlan.CLOSED or StringName(id) == StringName(anchor["id"]) or not rects.has(other):
			continue
		var o: Rect2 = world_rect(by_id[id], other)
		if w.intersects(o) or separation(w, o) < gap:
			return false
	return true


## The walkway check: can the guards and the waiter (and so anyone) still walk from an area's
## entry to every drawn chair and every patrol point? It redoes the navmesh's bake on a coarse
## grid (`CELL`, the bake's own cell): everything the navmesh walks round (the map's blockers, the
## drawn games' colliders, the closed spots' posts and pots) grown by its agent radius, flooded from
## the entries. True when the map gave what it needs (no check without).
func can_walk() -> bool:
	return not entries.is_empty() and not obstacles.is_empty()


## A game's chairs on a spot, world (x, z).
func world_seats(anchor: Dictionary, game: StringName) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var pos: Vector3 = anchor["pos"]
	for s: Vector2 in seats.get(game, []):
		var w: Vector3 = Vector3(s.x, 0.0, s.y).rotated(Vector3.UP, float(anchor["yaw"])) + pos
		out.append(Vector2(w.x, w.z))
	return out


## Spots of `plan` (anchor id → game) whose game can't be walked to: a chair whose nearest open
## floor nobody reaches from the entry (the navmesh's closest point would sit in a pocket), or the
## nearest game to a patrol point that was cut off. Empty when all is well.
func unreachable(plan: Dictionary, by_id: Dictionary) -> Array[StringName]:
	var out: Array[StringName] = []
	var placed: Dictionary = {}
	for id: Variant in plan:
		var g: StringName = StringName(plan[id])
		if g != FloorPlan.CLOSED and rects.has(g):
			placed[StringName(id)] = world_rect(by_id[id], g)
	for area: Rect2 in areas:
		var grid: WalkGrid = _walk_grid(area, plan, by_id)
		if grid == null:
			continue
		for id: StringName in placed:
			if not area.encloses(placed[id]):
				continue
			for s: Vector2 in world_seats(by_id[id], StringName(plan[id])):
				if not grid.reached_near(s, SEAT_REACH):
					out.append(id)
					break
		for p: Vector2 in walk_points:
			if not area.has_point(p) or grid.reached_near(p, POINT_REACH):
				continue
			var best: StringName = &""
			var best_d: float = BLAME_RANGE
			for id: StringName in placed:
				var d: float = separation(placed[id], Rect2(p, Vector2.ZERO))
				if d < best_d:
					best_d = d
					best = id
			if best != &"" and not out.has(best):
				out.append(best)
	return out


func _walk_grid(area: Rect2, plan: Dictionary, by_id: Dictionary) -> WalkGrid:
	var starts: Array[Vector2] = []
	for e: Vector2 in entries:
		if area.has_point(e):
			starts.append(e)
	if starts.is_empty():
		return null
	# A margin round the area: its walls are among the blockers.
	var grid := WalkGrid.new(area.grow(GRID_MARGIN))
	# The bake marks every cell an obstacle touches, then keeps the radius off: about half a cell
	# more than the radius from the obstacle itself.
	var r: float = agent_radius + CELL * 0.5
	var bounds: Rect2 = grid.area.grow(r)
	for b: Rect2 in blockers:
		if bounds.intersects(b, true):
			grid.block(b, r)
	for id: Variant in plan:
		var a: Dictionary = by_id[id]
		var g: StringName = StringName(plan[id])
		var local: Array = obstacles.get(g, []) if g != FloorPlan.CLOSED else closed_obstacles.get(StringName(a["footprint"]), [])
		for lr: Rect2 in local:
			var w: Rect2 = _turned(a, lr)
			if bounds.intersects(w, true):
				grid.block(w, r)
	grid.flood(starts)
	return grid


## A coarse occupancy grid over one floor area (cells `CELL` wide, x by z).
class WalkGrid:
	var area: Rect2
	var cols: int
	var rows: int
	var free: PackedByteArray = PackedByteArray()
	var reach: PackedByteArray = PackedByteArray()

	func _init(p_area: Rect2) -> void:
		area = p_area
		cols = maxi(1, ceili(area.size.x / CELL))
		rows = maxi(1, ceili(area.size.y / CELL))
		free.resize(cols * rows)
		free.fill(1)
		reach.resize(cols * rows)
		reach.fill(0)

	func center(i: int, j: int) -> Vector2:
		return area.position + Vector2((i + 0.5) * CELL, (j + 0.5) * CELL)

	## Closes every cell whose centre is within `radius` of `r`.
	func block(r: Rect2, radius: float) -> void:
		var g: Rect2 = r.grow(radius)
		var i0: int = maxi(0, ceili((g.position.x - area.position.x) / CELL - 0.5))
		var i1: int = mini(cols - 1, floori((g.end.x - area.position.x) / CELL - 0.5))
		var j0: int = maxi(0, ceili((g.position.y - area.position.y) / CELL - 0.5))
		var j1: int = mini(rows - 1, floori((g.end.y - area.position.y) / CELL - 0.5))
		for j: int in range(j0, j1 + 1):
			for i: int in range(i0, i1 + 1):
				var c: Vector2 = center(i, j)
				var dx: float = maxf(0.0, maxf(r.position.x - c.x, c.x - r.end.x))
				var dz: float = maxf(0.0, maxf(r.position.y - c.y, c.y - r.end.y))
				if dx * dx + dz * dz <= radius * radius:
					free[j * cols + i] = 0

	func flood(starts: Array[Vector2]) -> void:
		# Like the bake, close islands smaller than MIN_ISLAND cells first: they are no pockets.
		var seen := PackedByteArray()
		seen.resize(cols * rows)
		seen.fill(0)
		for k0: int in cols * rows:
			if free[k0] == 0 or seen[k0] == 1:
				continue
			seen[k0] = 1
			var island := PackedInt32Array([k0])
			var h: int = 0
			while h < island.size():
				var k: int = island[h]
				h += 1
				for n: int in _neighbours(k):
					if free[n] == 1 and seen[n] == 0:
						seen[n] = 1
						island.append(n)
			if island.size() < MIN_ISLAND:
				for k: int in island:
					free[k] = 0
		var qi := PackedInt32Array()
		var qj := PackedInt32Array()
		for s: Vector2 in starts:
			# The nearest open cell within a metre of the entry.
			var best: Vector2i = Vector2i(-1, -1)
			var best_d: float = 1.0
			for j: int in rows:
				for i: int in cols:
					if free[j * cols + i] == 0:
						continue
					var d: float = center(i, j).distance_to(s)
					if d <= best_d:
						best_d = d
						best = Vector2i(i, j)
			if best.x >= 0 and reach[best.y * cols + best.x] == 0:
				reach[best.y * cols + best.x] = 1
				qi.append(best.x)
				qj.append(best.y)
		var head: int = 0
		while head < qi.size():
			var i: int = qi[head]
			var j: int = qj[head]
			head += 1
			for n: Vector2i in [Vector2i(i + 1, j), Vector2i(i - 1, j), Vector2i(i, j + 1), Vector2i(i, j - 1)]:
				if n.x < 0 or n.y < 0 or n.x >= cols or n.y >= rows:
					continue
				var k: int = n.y * cols + n.x
				if free[k] == 1 and reach[k] == 0:
					reach[k] = 1
					qi.append(n.x)
					qj.append(n.y)

	## The cells next to cell `k` (4 ways, inside the grid).
	func _neighbours(k: int) -> Array[int]:
		var out: Array[int] = []
		var i: int = k % cols
		if i > 0:
			out.append(k - 1)
		if i < cols - 1:
			out.append(k + 1)
		if k >= cols:
			out.append(k - cols)
		if k + cols < cols * rows:
			out.append(k + cols)
		return out

	## True when the open floor nearest `p` (within `radius`) is reached from the entry: someone
	## walking to `p` heads for the nearest open floor, so a pocket nobody can get into counts as
	## cut off when it is about as close (within `POCKET_MARGIN`; this grid and the bake round
	## differently), like the navmesh's closest point would.
	func reached_near(p: Vector2, radius: float) -> bool:
		var i0: int = maxi(0, floori((p.x - radius - area.position.x) / CELL))
		var i1: int = mini(cols - 1, floori((p.x + radius - area.position.x) / CELL))
		var j0: int = maxi(0, floori((p.y - radius - area.position.y) / CELL))
		var j1: int = mini(rows - 1, floori((p.y + radius - area.position.y) / CELL))
		var near_pocket: float = INF
		var near_reached: float = INF
		for j: int in range(j0, j1 + 1):
			for i: int in range(i0, i1 + 1):
				var k: int = j * cols + i
				if free[k] == 0:
					continue
				var d: float = center(i, j).distance_to(p)
				if d > radius:
					continue
				if reach[k] == 1:
					near_reached = minf(near_reached, d)
				else:
					near_pocket = minf(near_pocket, d)
		return near_reached < INF and near_pocket > near_reached + POCKET_MARGIN
