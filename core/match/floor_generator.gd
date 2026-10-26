class_name FloorGenerator
extends RefCounted
## Builds the casino floor of a round from a seed (docs/FLOOR_PLAN.md). Patrick (0.9.16): "Group
## the tablegames and make random layouts." The room tells where things may stand (`FloorSite`):
##
## - the table games (footprint `table`, whatever is registered) stand grouped in the pit: blocks
##   of two rows back to back, the dealers on the inside round a lane, the players on the outside,
##   aisles between the blocks and round the pit;
## - the slot banks (`cabinet`), Plinko (`big`) and the kiosks (`kiosk`: the scratch counter, the
##   Sword Tapper's pair of pedestals) stand with their backs to a wall run or on an island;
## - everything else (the horse race, the VIP lounge, the shop, the jail) keeps its own place.
##
## A draw picks the pit's block style, which table stands in which row (every table game once,
## then a few extra copies by weight) and where along its row, how many slot machines in banks of
## what size, and which wall run or island each group takes and where along it. The canonical draw
## (`full`) throws no dice: every game, the first pit style, the extra tables the config names, every
## group at its first place, evenly spread. That is the full floor (Practice, the menu, the map as
## built) and the fallback when the round's draws all fail the checks (`FloorPlan.problems`).
## Pure and deterministic: the same seed, games and sizes give the same floor.

## Each game's floor in its own frame when the map has measured nothing (the full floor is built
## before any map exists): the station's colliders, chairs (±0.3 m) and dealer (±0.35 m), as
## `LuckyLounge.measure_floor` measures them (tests/physics/test_floor_walkability.gd checks they
## still match).
const NOMINAL: Dictionary = {
	&"blackjack": Rect2(-1.86, -1.7, 3.72, 4.13),
	&"roulette": Rect2(-2.5, -1.8, 5.2, 3.6),
	&"wheel": Rect2(-1.7, -1.9, 3.8, 3.5),
	&"hilo": Rect2(-2.06, -1.85, 4.12, 3.47),
	&"craps": Rect2(-2.15, -2.1, 4.3, 3.9),
	&"slots": Rect2(-0.45, -0.35, 0.9, 1.55),
	&"plinko": Rect2(-2.05, -0.35, 4.1, 2.85),
	&"scratch": Rect2(-0.8, -1.255, 1.6, 2.435),
	&"sword_tapper": Rect2(-0.7, -0.7, 1.4, 2.15),
}
## A game nobody measured yet, by footprint: the biggest of its kind and some.
const UNKNOWN: Dictionary = {
	&"table": Rect2(-2.6, -2.1, 5.2, 4.55),
	&"cabinet": Rect2(-0.5, -0.4, 1.0, 1.7),
	&"big": Rect2(-2.1, -0.4, 4.2, 3.0),
	&"kiosk": Rect2(-0.8, -1.3, 1.6, 2.5),
}
## Games that stand as a group of several stations side by side, and how far apart: the Sword
## Tapper's two pedestals (docs/SWORD_TAPPER.md). A bank of slot machines stands BANK_PITCH apart.
const GROUP: Dictionary = {&"sword_tapper": 2}
const GROUP_PITCH: Dictionary = {&"sword_tapper": 1.8}
const BANK_PITCH: float = 1.3
## Station id prefixes; the others are named after their game (`blackjack_1`, `slot_14`, `sword_2`).
const PREFIX: Dictionary = {&"slots": &"slot", &"sword_tapper": &"sword"}
## A little more than the config's gap between neighbours, and off the walls, so rounding the
## positions to the centimetre never brings two of them closer than the checks allow.
const SLACK: float = 0.02
## How a generated layout's id spells its seed (`floor_123`; `--floor floor_123` puts it in).
const ID_PREFIX: String = "floor_"

var site: FloorSite
var cfg: FloorPlanConfig
## Game id → footprint (the games on tonight's floor) and game id → its floor in its own frame.
var games: Dictionary = {}
var sizes: Dictionary = {}
## Null for the canonical draw.
var rng: SeededRng
## Station id → [game, position, yaw degrees], and the next number per prefix.
var stations: Dictionary = {}
var _numbers: Dictionary = {}
var _gap: float = 0.35


## A round's floor from `seed_value` (null when this draw can't seat every game). `games`: game id →
## footprint (`GameDefinition.floor_footprint`; fixed ones are ignored); `sizes`: game id → its
## measured floor (`FloorGeometry.rects`; empty = `NOMINAL`).
static func draw(p_site: FloorSite, p_games: Dictionary, p_sizes: Dictionary, p_cfg: FloorPlanConfig, seed_value: int) -> FloorLayout:
	var g := FloorGenerator.new(p_site, p_games, p_sizes, p_cfg, SeededRng.new(seed_value))
	if not g._build():
		return null
	return g._layout(StringName(ID_PREFIX + str(seed_value)), "Floor %d" % seed_value)


## The canonical draw (no dice): the full floor when `games` are all the games.
static func full(p_site: FloorSite, p_games: Dictionary, p_sizes: Dictionary, p_cfg: FloorPlanConfig) -> FloorLayout:
	var g := FloorGenerator.new(p_site, p_games, p_sizes, p_cfg, null)
	if not g._build():
		return null
	return g._layout(p_site.full_id, p_site.full_title)


## The seed in a generated layout's id (-1 when it is not one: `floor_123` → 123).
static func seed_of(layout_id: String) -> int:
	var s: String = layout_id.trim_prefix(ID_PREFIX)
	return int(s) if s.is_valid_int() and int(s) >= 0 else -1


func _init(p_site: FloorSite, p_games: Dictionary, p_sizes: Dictionary, p_cfg: FloorPlanConfig, p_rng: SeededRng) -> void:
	site = p_site
	cfg = p_cfg if p_cfg != null else FloorPlanConfig.new()
	for g: Variant in p_games:
		if StringName(p_games[g]) != &"fixed":
			games[StringName(g)] = StringName(p_games[g])
	sizes = p_sizes
	rng = p_rng
	_gap = cfg.gap + SLACK


func _layout(id: StringName, title: String) -> FloorLayout:
	var l := FloorLayout.new()
	l.id = id
	l.title = title
	l.stations = stations
	return l


## A game's floor in its own frame.
func size_of(game: StringName) -> Rect2:
	if sizes.has(game):
		return sizes[game]
	if NOMINAL.has(game):
		return NOMINAL[game]
	return UNKNOWN.get(games.get(game, &"table"), UNKNOWN[&"table"])


## The games of a footprint, sorted.
func _of(footprint: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for g: StringName in games:
		if games[g] == footprint:
			out.append(g)
	out.sort()
	return out


func _shuffle(arr: Array) -> void:
	if rng != null:
		rng.shuffle(arr)


## A rect in a station's own frame, turned by `yaw` degrees about its origin (world x, z offsets).
static func turned(r: Rect2, yaw: float) -> Rect2:
	var out := Rect2()
	var first: bool = true
	for c: Vector2 in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var w: Vector3 = Vector3(c.x, 0.0, c.y).rotated(Vector3.UP, deg_to_rad(yaw))
		var p := Vector2(snappedf(w.x, 0.0001), snappedf(w.z, 0.0001))
		if first:
			out = Rect2(p, Vector2.ZERO)
			first = false
		else:
			out = out.expand(p)
	return out


## A station's own +x axis in world (x, z) for `yaw` degrees.
static func side_of(yaw: float) -> Vector2:
	var w: Vector3 = Vector3.RIGHT.rotated(Vector3.UP, deg_to_rad(yaw))
	return Vector2(snappedf(w.x, 0.0001), snappedf(w.z, 0.0001))


func _add(game: StringName, pos: Vector2, yaw: float) -> void:
	var prefix: StringName = PREFIX.get(game, game)
	var n: int = int(_numbers.get(prefix, 0)) + 1
	_numbers[prefix] = n
	var y: float = wrapf(snappedf(yaw, 0.01), -180.0, 180.0)
	stations[StringName("%s_%d" % [prefix, n])] = [game, Vector3(snappedf(pos.x, 0.01), 0.0, snappedf(pos.y, 0.01)), 180.0 if is_equal_approx(y, -180.0) else y]


func _build() -> bool:
	if site == null:
		return false
	return _build_pit() and _build_groups()


# --- The pit ---------------------------------------------------------------------------------

## One row of a pit block: its x interval, which way its players face, its tables in order.
class Row:
	var x0: float
	var x1: float
	var yaw: float
	var tables: Array[StringName] = []
	var used: float = 0.0

	func _init(p_x0: float, p_x1: float, p_yaw: float) -> void:
		x0 = p_x0
		x1 = p_x1
		yaw = p_yaw

	func free_length() -> float:
		return (x1 - x0) - used


func _build_pit() -> bool:
	var tables: Array[StringName] = _of(&"table")
	if tables.is_empty():
		return true
	if site.pit_styles.is_empty():
		return false
	var style: Array = site.pit_styles[0] if rng == null else site.pit_styles[rng.range_int(0, site.pit_styles.size() - 1)]
	var rows: Array[Row] = []
	for b: Variant in style:
		var iv: Vector2 = b
		rows.append(Row.new(iv.x, iv.y, 180.0))  # the north row: players north, dealers south
		rows.append(Row.new(iv.x, iv.y, 0.0))
	# Every table game once, then the extra copies.
	var once: Array[StringName] = tables.duplicate()
	_shuffle(once)
	for g: StringName in once:
		if not _seat_table(rows, g):
			return false  # a draw that can't put every table game in the pit is no draw
	for g: StringName in _extra_tables(tables):
		_seat_table(rows, g)
	for row: Row in rows:
		_lay_row(row)
	return true


## Extra copies of the table games: the config's list for the canonical draw; a few by weight
## otherwise.
func _extra_tables(tables: Array[StringName]) -> Array[StringName]:
	var out: Array[StringName] = []
	if rng == null:
		for g: StringName in cfg.full_extras:
			if g in tables:
				out.append(g)
		return out
	var weights: Array = []
	for g: StringName in tables:
		weights.append(cfg.weight_of(g))
	var n: int = rng.range_int(cfg.extra_tables.x, maxi(cfg.extra_tables.x, cfg.extra_tables.y))
	for i: int in n:
		var k: int = rng.weighted_index(weights)
		if k >= 0:
			out.append(tables[k])
	return out


## Puts a table in a row where it fits: the freest row for the canonical draw, any for a draw.
## False when no row has room.
func _seat_table(rows: Array[Row], game: StringName) -> bool:
	var fits: Array[Row] = []
	for row: Row in rows:
		var w: Rect2 = turned(size_of(game), row.yaw)
		var need: float = w.size.x + (_gap if not row.tables.is_empty() else 0.0)
		if need > row.free_length() + 0.0001:
			continue
		var z: float = _row_z(row, w)
		if (row.yaw == 180.0 and z + w.position.y < site.pit_north - 0.0001) or (row.yaw == 0.0 and z + w.end.y > site.pit_south + 0.0001):
			continue
		fits.append(row)
	if fits.is_empty():
		return false
	var pick: Row = fits[0]
	if rng == null:
		for row: Row in fits:
			if row.free_length() > pick.free_length() + 0.0001:
				pick = row
	else:
		pick = fits[rng.range_int(0, fits.size() - 1)]
	pick.used += turned(size_of(game), pick.yaw).size.x + (_gap if not pick.tables.is_empty() else 0.0)
	pick.tables.append(game)
	return true


## Where a table of world rect `w` (at its origin) stands in z: its dealer's edge on the lane.
func _row_z(row: Row, w: Rect2) -> float:
	if row.yaw == 180.0:
		return site.lane_z - site.lane * 0.5 - w.end.y
	return site.lane_z + site.lane * 0.5 - w.position.y


func _lay_row(row: Row) -> void:
	if row.tables.is_empty():
		return
	_shuffle(row.tables)
	var slack: float = maxf(row.free_length(), 0.0)
	var x: float = row.x0 + (slack * 0.5 if rng == null else rng.range_float(0.0, slack))
	for g: StringName in row.tables:
		var w: Rect2 = turned(size_of(g), row.yaw)
		_add(g, Vector2(x - w.position.x, _row_z(row, w)), row.yaw)
		x += w.size.x + _gap


# --- Wall runs and islands -------------------------------------------------------------------

## A group of stations that stands together: `count` of `game` side by side `pitch` apart, or a
## slot island (`back_to_back`: two banks of `count`, their backs together).
class Group:
	var game: StringName
	var footprint: StringName
	var count: int = 1
	var pitch: float = 0.0
	var back_to_back: bool = false

	func _init(p_game: StringName, p_footprint: StringName, p_count: int, p_pitch: float) -> void:
		game = p_game
		footprint = p_footprint
		count = p_count
		pitch = p_pitch


## The groups tonight: every big game `bigs` times, every kiosk game once (in its group), every
## cabinet game `cabinets` machines in banks of `bank`.
func _groups() -> Array[Group]:
	var out: Array[Group] = []
	for g: StringName in _of(&"big"):
		var n: int = cfg.bigs.y if rng == null else rng.range_int(cfg.bigs.x, maxi(cfg.bigs.x, cfg.bigs.y))
		for i: int in maxi(n, 1):
			out.append(Group.new(g, &"big", 1, 0.0))
	for g: StringName in _of(&"kiosk"):
		out.append(Group.new(g, &"kiosk", int(GROUP.get(g, 1)), float(GROUP_PITCH.get(g, 0.0))))
	for g: StringName in _of(&"cabinet"):
		var left: int = cfg.cabinets.y if rng == null else rng.range_int(cfg.cabinets.x, maxi(cfg.cabinets.x, cfg.cabinets.y))
		left = maxi(left, 1)
		var lo: int = maxi(cfg.bank.x, 1)
		var hi: int = maxi(cfg.bank.y, lo)
		while left > 0:
			var n: int = (lo + hi) / 2 if rng == null else rng.range_int(lo, hi)
			if left - n < lo:
				n = left if left <= hi else left - lo
			n = mini(n, left)
			out.append(Group.new(g, &"cabinet", n, BANK_PITCH))
			left -= n
	return out


## How long a group is along its back line and how deep it reaches out (world, at yaw 0 frame).
func _group_rect(grp: Group, yaw: float) -> Rect2:
	var r: Rect2 = Rect2()
	var first: bool = true
	for p: Array in _members(grp, yaw):
		var w: Rect2 = turned(size_of(grp.game), float(p[1]))
		w.position += p[0] as Vector2
		r = w if first else r.merge(w)
		first = false
	return r


## A group's stations round its origin: [offset (world x, z), yaw] each.
func _members(grp: Group, yaw: float) -> Array:
	var out: Array = []
	var side: Vector2 = side_of(yaw)
	for i: int in grp.count:
		out.append([side * ((i - (grp.count - 1) * 0.5) * grp.pitch), yaw])
	if grp.back_to_back:
		# The second bank: turned round, its back to the first one's back (`gap` between them).
		var r: Rect2 = size_of(grp.game)
		var behind: float = -r.position.y * 2.0 + _gap
		var back: Vector2 = Vector2(-sin(deg_to_rad(yaw)), -cos(deg_to_rad(yaw))) * behind
		for i: int in grp.count:
			out.append([back + side * ((i - (grp.count - 1) * 0.5) * grp.pitch), yaw + 180.0])
	return out


func _build_groups() -> bool:
	var groups: Array[Group] = _groups()
	if groups.is_empty():
		return true
	if rng != null:
		rng.shuffle(groups)
	# The hardest to place first: the big ones, then by length.
	groups.sort_custom(func(a: Group, b: Group) -> bool:
		var ka: int = 0 if a.footprint == &"big" else 1
		var kb: int = 0 if b.footprint == &"big" else 1
		if ka != kb:
			return ka < kb
		return a.count * maxf(a.pitch, 1.0) > b.count * maxf(b.pitch, 1.0))
	var runs: Array = []  # per wall run: the groups on it
	var used: Array[float] = []
	for w: Variant in site.walls:
		runs.append([])
		used.append(0.0)
	var island_taken: Array[bool] = []
	var island_group: Array = []
	for i: Variant in site.islands:
		island_taken.append(false)
		island_group.append(null)
	var placed_games: Dictionary = {}
	for grp: Group in groups:
		# Where it can go: [kind (0 wall, 1 island), index, preferred].
		var spots: Array = []
		for k: int in site.walls.size():
			var w: Dictionary = site.walls[k]
			if not grp.footprint in (w["kinds"] as Array):
				continue
			var length: float = _run_length(w)
			var glen: float = _along(_group_rect(grp, float(w["yaw"])), w)
			if used[k] + glen + (_gap if not (runs[k] as Array).is_empty() else 0.0) > length + 0.0001:
				continue
			spots.append([0, k, grp.game in (w.get("full", []) as Array)])
		for k: int in site.islands.size():
			var isl: Dictionary = site.islands[k]
			if island_taken[k] or not grp.footprint in (isl["kinds"] as Array) or not _fits_island(isl, grp):
				continue
			spots.append([1, k, grp.game in (isl.get("full", []) as Array)])
		if spots.is_empty():
			if not placed_games.has(grp.game):
				return false  # every game stands somewhere, at least once
			continue
		var pick: Array = spots[0]
		if rng == null:
			for s: Array in spots:
				if bool(s[2]):
					pick = s
					break
		else:
			pick = spots[rng.range_int(0, spots.size() - 1)]
		var k2: int = int(pick[1])
		if int(pick[0]) == 0:
			var w2: Dictionary = site.walls[k2]
			used[k2] += _along(_group_rect(grp, float(w2["yaw"])), w2) + (_gap if not (runs[k2] as Array).is_empty() else 0.0)
			(runs[k2] as Array).append(grp)
		else:
			island_taken[k2] = true
			island_group[k2] = grp
		placed_games[grp.game] = true
	for k: int in site.walls.size():
		_lay_run(site.walls[k], runs[k])
	for k: int in site.islands.size():
		if island_group[k] != null:
			if not _lay_island(site.islands[k], island_group[k]):
				return false
	return true


static func _run_length(w: Dictionary) -> float:
	return (w["from"] as Vector2).distance_to(w["to"] as Vector2)


## True when a run goes along x (its back line is a z), false along z.
static func _along_x(w: Dictionary) -> bool:
	return is_equal_approx((w["from"] as Vector2).y, (w["to"] as Vector2).y)


## A world rect's length along a run.
static func _along(r: Rect2, w: Dictionary) -> float:
	return r.size.x if _along_x(w) else r.size.y


## Lays a wall run's groups out from one end to the other, the spare length spread between them
## (evenly for the canonical draw, at random otherwise), their backs on the run's line.
func _lay_run(w: Dictionary, groups: Array) -> void:
	if groups.is_empty():
		return
	if rng != null:
		rng.shuffle(groups)
	var yaw: float = float(w["yaw"])
	var a: Vector2 = w["from"]
	var b: Vector2 = w["to"]
	var along_x: bool = _along_x(w)
	var lo: float = minf(a.x, b.x) if along_x else minf(a.y, b.y)
	var line: float = a.y if along_x else a.x
	var total: float = _gap * (groups.size() - 1)
	for grp: Group in groups:
		total += _along(_group_rect(grp, yaw), w)
	var spare: float = maxf(_run_length(w) - total, 0.0)
	# Spare length before each group and after the last.
	var parts: Array[float] = []
	var sum: float = 0.0
	for i: int in groups.size() + 1:
		var p: float = 1.0 if rng == null else rng.unit() + 0.05
		parts.append(p)
		sum += p
	var cursor: float = lo
	for i: int in groups.size():
		var grp: Group = groups[i]
		cursor += spare * parts[i] / sum
		var r: Rect2 = _group_rect(grp, yaw)
		var origin: Vector2
		var face: Vector2 = Vector2(sin(deg_to_rad(yaw)), cos(deg_to_rad(yaw)))
		if along_x:
			# The back on the line: facing +z the rect's north edge, facing -z its south edge.
			var oz: float = line - r.position.y if face.y > 0.0 else line - r.end.y
			origin = Vector2(cursor - r.position.x, oz)
		else:
			var ox: float = line - r.position.x if face.x > 0.0 else line - r.end.x
			origin = Vector2(ox, cursor - r.position.y)
		origin += face.snapped(Vector2.ONE * 0.0001) * SLACK
		for m: Array in _members(grp, yaw):
			_add(grp.game, origin + (m[0] as Vector2), float(m[1]))
		cursor += _along(r, w) + _gap


## True when the group fits the island in every yaw it may face there.
func _fits_island(isl: Dictionary, grp: Group) -> bool:
	var area: Rect2 = isl["rect"]
	var was: bool = grp.back_to_back
	grp.back_to_back = grp.footprint == &"cabinet"
	var ok: bool = true
	for y: Variant in isl.get("yaws", [0.0]):
		var r: Rect2 = _group_rect(grp, float(y))
		if r.size.x > area.size.x + 0.0001 or r.size.y > area.size.y + 0.0001:
			ok = false
	grp.back_to_back = was
	return ok


## Stands a group on an island: a bank becomes a slot island (two banks back to back), the others
## face one of the island's yaws; centred for the canonical draw, anywhere it fits otherwise.
func _lay_island(isl: Dictionary, grp: Group) -> bool:
	var area: Rect2 = isl["rect"]
	var yaws: Array = isl.get("yaws", [0.0])
	var yaw: float = float(yaws[0] if rng == null else yaws[rng.range_int(0, yaws.size() - 1)])
	if grp.footprint == &"cabinet":
		grp.back_to_back = true
	var r: Rect2 = _group_rect(grp, yaw)
	var slack: Vector2 = area.size - r.size
	if slack.x < -0.0001 or slack.y < -0.0001:
		return false
	slack = slack.max(Vector2.ZERO)
	var at: Vector2 = slack * 0.5 if rng == null else Vector2(rng.range_float(0.0, slack.x), rng.range_float(0.0, slack.y))
	var origin: Vector2 = area.position + at - r.position
	for m: Array in _members(grp, yaw):
		_add(grp.game, origin + (m[0] as Vector2), float(m[1]))
	return true
