class_name FloorPlan
extends RefCounted
## The casino floor of one round (docs/FLOOR_PLAN.md). The map has fixed spots ("anchors"): a
## place, a facing and a size class (`table`, `cabinet`, `big`), in two areas (the casino floor and
## the VIP lounge). A plan says which game stands on each spot tonight, or that it is closed.
## Pure: the server draws it from the match's seeded RNG, every client builds the same floor from
## the wire form `{station id: [game, anchor id]}`.
##
## Anchors are Dictionaries {id: StringName, footprint: StringName, vip: bool, default: StringName
## (the game of the full floor)}, in map order (that order numbers the station ids).

const CLOSED: StringName = &""


## Draw pool from game id → footprint (`GameDefinition.floor_footprint`): footprint → {game:
## weight}. `fixed` games and games with weight 0 stay out.
static func pool_of(footprints: Dictionary, cfg: FloorPlanConfig) -> Dictionary:
	var pool: Dictionary = {}
	var ids: Array = footprints.keys()
	ids.sort()
	for g: Variant in ids:
		var fp: StringName = StringName(footprints[g])
		var w: float = cfg.weight_of(StringName(g))
		if fp == &"fixed" or w <= 0.0:
			continue
		if not pool.has(fp):
			pool[fp] = {}
		(pool[fp] as Dictionary)[StringName(g)] = w
	return pool


## The full floor: every spot with its usual game (Practice, the menu panorama).
static func full(anchors: Array) -> Dictionary:
	var out: Dictionary = {}
	for a: Dictionary in anchors:
		out[a["id"]] = StringName(a.get("default", CLOSED))
	return out


## A random floor: anchor id → game (CLOSED for a closed spot). Every spot is drawn afresh. Per
## area (casino floor, VIP lounge): each spot is closed with `empty_chance`, else gets a game of
## its size by weight, at most `max_per_type` of one game on `capped_footprints` spots; then
## closed spots reopen until `min_filled` of the area has a game (the cap gives way last). With
## `geo` (the map's measurements) a game only goes where it fits and keeps the walkway to the
## games already drawn next to it; the minimum fill never overrides that.
static func draw(anchors: Array, pool: Dictionary, cfg: FloorPlanConfig, rng: SeededRng, geo: FloorGeometry = null) -> Dictionary:
	var out: Dictionary = {}
	var by_id: Dictionary = {}
	for a: Dictionary in anchors:
		by_id[a["id"]] = a
		out[a["id"]] = CLOSED
	for vip: bool in [false, true]:
		var area: Array[Dictionary] = []
		for a: Dictionary in anchors:
			if bool(a.get("vip", false)) == vip:
				area.append(a)
		_draw_area(area, pool, cfg, rng, out, geo, by_id)
	return out


static func _draw_area(area: Array[Dictionary], pool: Dictionary, cfg: FloorPlanConfig, rng: SeededRng, out: Dictionary, geo: FloorGeometry, by_id: Dictionary) -> void:
	if area.is_empty():
		return
	var order: Array = range(area.size())
	rng.shuffle(order)
	var counts: Dictionary = {}
	for i: Variant in order:
		var a: Dictionary = area[int(i)]
		var game: StringName = CLOSED
		if not rng.chance(cfg.empty_chance):
			game = _pick(a, pool, cfg, counts, true, rng, geo, out, by_id)
		out[a["id"]] = game
		if game != CLOSED:
			counts[game] = int(counts.get(game, 0)) + 1
	var need: int = ceili(area.size() * cfg.min_filled) - filled(area, out)
	for capped: bool in [true, false]:
		for i: Variant in order:
			if need <= 0:
				return
			var a: Dictionary = area[int(i)]
			if out[a["id"]] != CLOSED:
				continue
			var game: StringName = _pick(a, pool, cfg, counts, capped, rng, geo, out, by_id)
			if game != CLOSED:
				out[a["id"]] = game
				counts[game] = int(counts.get(game, 0)) + 1
				need -= 1


## A game for the spot by weight (CLOSED when none fits).
static func _pick(a: Dictionary, pool: Dictionary, cfg: FloorPlanConfig, counts: Dictionary, capped: bool, rng: SeededRng, geo: FloorGeometry, placed: Dictionary, by_id: Dictionary) -> StringName:
	var fp: StringName = StringName(a["footprint"])
	var games: Dictionary = pool.get(fp, {})
	var cap: bool = capped and cfg.max_per_type > 0 and fp in cfg.capped_footprints
	var ids: Array[StringName] = []
	var weights: Array = []
	for g: StringName in games:
		if cap and int(counts.get(g, 0)) >= cfg.max_per_type:
			continue
		if geo != null and not (geo.fits(a, g) and geo.clear_of(a, g, placed, by_id)):
			continue
		ids.append(g)
		weights.append(games[g])
	var i: int = rng.weighted_index(weights)
	return ids[i] if i >= 0 else CLOSED


## Number of spots of `area` with a game in `plan`.
static func filled(area: Array, plan: Dictionary) -> int:
	var n: int = 0
	for a: Dictionary in area:
		if StringName(plan.get(a["id"], CLOSED)) != CLOSED:
			n += 1
	return n


## Station ids for a plan, numbered per game in map order: `blackjack_1`, `slot_3`, and
## `vip_roulette_1` in the VIP lounge (`prefixes`: game id → id stem, e.g. slots → slot; default the
## game id). Returns station id → [game, anchor id], the wire form.
static func station_ids(anchors: Array, plan: Dictionary, prefixes: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var counter: Dictionary = {}
	for a: Dictionary in anchors:
		var game: StringName = StringName(plan.get(a["id"], CLOSED))
		if game == CLOSED:
			continue
		var stem: String = ("vip_" if bool(a.get("vip", false)) else "") + String(prefixes.get(game, game))
		counter[stem] = int(counter.get(stem, 0)) + 1
		out[StringName("%s_%d" % [stem, counter[stem]])] = [game, a["id"]]
	return out


## Anchor id → game from the wire form (spots not in it are closed).
static func assignment_of(stations: Dictionary, anchors: Array) -> Dictionary:
	var out: Dictionary = {}
	for a: Dictionary in anchors:
		out[a["id"]] = CLOSED
	for sid: Variant in stations:
		var entry: Array = stations[sid]
		out[StringName(entry[1])] = StringName(entry[0])
	return out
