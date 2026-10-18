class_name ChipTowers
extends RefCounted
## The "towers" layout of the climb room (`ClimbRoom`, Jackpot Climb): a run up a wedding cake of
## giant casino chips. Three **tiers** (giant chip plateaus, each standing on the one below) and
## the **jackpot stack** on top, whose gold pad (the finish) waits under the JACKPOT sign at
## `TOP_Y`. Every tier top is a **checkpoint** with a flag.
##
## The climb is pure data (`lanes()`, local to the room's origin), computed once and the same for
## everyone (no randomness: every client builds the same cake the server judges):
## - Four **segments**: segment `s` climbs from level `s` (0 the floor, 1..3 the tiers) to level
##   `s + 1` (the next tier, or the pad) in the **ring** round level `s + 1`'s column: on top of
##   tier `s` (the floor for `s` = 0, `FLOOR_RING_W` wide), from that column out to tier `s`'s rim.
##   Every ring is filled with walkways (solid down to its tier: nothing to crawl under), so a bean
##   that falls off a ring lands on the ring below, which runs up to the flag it fell from (or far
##   enough below it that the server puts it back on that flag, `JackpotClimbLogic`).
## - Each segment starts at its flag (`flag_angle`) and forks into two **lanes** that wind round
##   the column in opposite directions and rejoin where both reach the next tier (its flag):
##   - **steady** (green felt): one smooth ramp, no step anywhere (`STEADY_TURNS` of a turn; you
##     never have to jump).
##   - **bold** (burgundy felt): the other way round, shorter and steeper, with one or two wide chip
##     tops `STEP_H` above the ramp to hop onto (`BOLD_STEPS`).
## - `BANDS`: on the two lower rings both lanes share the ring (each takes its part of the turn).
##   On the two upper rings (round tier 3 and round the jackpot stack) each lane has a band of its
##   own: the steady lane spirals round the inner band more than a full turn, its second turn a
##   slab over its first (`SLAB_T` thick, 3 m+ of headroom); the bold lane takes the outer band the
##   other way; where the outer band is free (between the flag and the arrival) the steady lane's
##   first turn is twice as wide (`wide`), and a slab over the inner band carries the bold lane's
##   arrival onto the next tier (`bridge`).
## - Every lane starts and ends on `FLAT` metres of level walkway (the flag landing, the arrival).
## - `guide(pos)` says where a bean anywhere on the course runs next to climb (the dev bot and the
##   no-trap test drive real beans with it).
##
## `build(root, brass, ceiling_y)` makes the nodes in the room's local frame: collision (convex
## prisms per walkway piece, `ClimbKit.column` for tiers and the jackpot stack), the walkways dressed
## as stacked chips (a chip-edge texture up their sides, felt on top, gold edge trim and chevrons
## pointing up the lane, a giant chip on every hop top), the tiers and the jackpot stack in chips
## (`chip_mesh`: flush edge spots, a bevelled rim, an inlay ring and spots on both faces; multimeshes
## per colour), the flags (`Flag1`..`Flag3`, each with a `Cloth` the stage lights up), the gold pad
## and its rail open to the south, the JACKPOT sign (warm marquee bulbs, `BulbsA`/`BulbsB` for the
## stage to chase, `NameFront`/`NameBack` labels it fills) and the safety net.

## Tower centre (local z) and the towers hall (wider and deeper than the board's).
const CENTER_Z: float = -16.0
const HALL_HALF_X: float = 16.3
const FAR_Z: float = -32.5
## The tiers bottom to top: column radius and top height. Tier k stands on tier k - 1.
const TIER_R: Array[float] = [12.2, 9.6, 6.0]
const TIER_Y: Array[float] = [8.5, 16.0, 21.5]
const PAD_R: float = 2.4
const TOP_Y: float = 26.0
const SEGMENTS: int = 4
## The first ring stands on the floor round tier 1: this wide (a 1.5 m aisle stays to the walls).
const FLOOR_RING_W: float = 2.6
## Per segment: 1 = both lanes share the ring, 2 = a band each (steady inner, bold outer).
const BANDS: Array[int] = [1, 1, 2, 2]
## Turns of the steady lane per segment (the bold lane winds the rest: 1 - t on a shared ring,
## 2 - t on a ring with two bands), and which way it winds (+1: increasing angle).
const STEADY_TURNS: Array[float] = [0.55, 0.55, 1.25, 1.25]
const STEADY_DIR: Array[int] = [1, -1, 1, -1]
## The bold lanes' hops: where (fraction along the lane) a chip top stands `STEP_H` above the ramp.
const BOLD_STEPS: Array = [[0.34, 0.68], [0.34, 0.68], [0.3, 0.64], [0.5]]
const STEP_H: float = 0.7
## Length of a hop's chip top along the lane line, and the level walkway at each end of a lane.
const STEP_TOP: float = 2.4
const FLAT: float = 1.6
## Thickness of a walkway over another one (the second turn of a spiral, the bridge).
const SLAB_T: float = 0.4
## Walkway pieces are at most this long on their outer edge (collision prisms, mesh quads).
const PIECE_LEN: float = 0.7
## The envelope the walkways must stay in (the layout test checks it): steepest ramp, the most a
## bean can walk up without jumping (seams), least headroom under a slab.
const MAX_SLOPE_DEG: float = 20.0
const WALK_LIP: float = 0.02
const MIN_HEADROOM: float = 2.8
## A walkway this far above a bean's feet is not under it (a hop top ahead, a slab overhead).
const FEET: float = 0.35
## `guide`: how far ahead along a lane a bean aims, and how close a hop's riser is when it jumps.
const LOOK: float = 2.2
const HOP_AT: float = 1.1
## Checkpoint reach: on a tier's top (this far past its rim, from this far below its top).
const CHECK_RIM: float = 0.25
const CHECK_BELOW: float = 0.35
## Half size of the finish box over the pad (inside the pad's disc).
const FINISH_HALF: float = 1.6
## Giant chips are `GIANT_T` of their radius thick; the jackpot stack's chips `PAD_CHIP_T`.
const CHIP_T: float = 0.12
const GIANT_T: float = 0.16
const PAD_CHIP_T: float = 0.46
const SIGN_Y: float = 4.6
const SIGN_W: float = 7.6
const SIGN_H: float = 2.7
## Top-chip denominations by chip colour (`ChipStack.TIER_COLORS` order).
const DENOMS: Array[String] = ["25", "100", "500", "1K", "5K"]
## Chip colours of the three tiers (giant chips) and their edge spots.
const TIER_COLORS: Array[Color] = [Color("#2F6B52"), Color("#2A2522"), Color("#8E2A33")]
## Height of one tile of the chip-edge texture up a walkway's side (four chips).
const EDGE_TILE: float = 0.48

## Every lane: {seg, kind (&"steady", &"bold", &"wide", &"bridge"), a0 (start angle), dir (+1 / -1:
## which way the angle runs), r0, r1 (its band), rc (its line), theta (how far it winds, radians),
## knots (Array[Vector2]: (theta, height above its tier), a riser is two knots at one theta),
## slab_from (pieces from this theta on are slabs over a walkway below; INF: none)}.
static var _lanes: Array[Dictionary] = []
static var _pieces: Array[Dictionary] = []
static var _checkpoints: Array[Dictionary] = []
## "colour html:spots" → chip mesh with the materials set.
static var _meshes: Dictionary[String, ArrayMesh] = {}


# --- Pure data ------------------------------------------------------------------------------

## Height of level `k`: 0 the floor, 1..3 the tiers' tops, 4 the pad.
static func level_y(k: int) -> float:
	if k <= 0:
		return 0.0
	if k > TIER_Y.size():
		return TOP_Y
	return TIER_Y[k - 1]


## Column radius of level `k` (1..3 a tier, 4 the jackpot stack).
static func level_r(k: int) -> float:
	if k > TIER_R.size():
		return PAD_R
	return TIER_R[maxi(k, 1) - 1]


## Ring of segment `seg`: from the column it winds round out to the rim of the tier it stands on.
static func ring_inner(seg: int) -> float:
	return level_r(seg + 1)


static func ring_outer(seg: int) -> float:
	return level_r(1) + FLOOR_RING_W if seg <= 0 else level_r(seg)


## Where segment `seg` starts (its flag; angle round the centre, 0 = +z toward the apron): the floor
## segment at the apron, every other one where the steady lane of the one below arrives.
static func flag_angle(seg: int) -> float:
	var a: float = 0.0
	for s: int in mini(seg, SEGMENTS):
		a += float(STEADY_DIR[s]) * TAU * STEADY_TURNS[s]
	return wrapf(a, -PI, PI)


## Old name of `flag_angle`.
static func start_angle(seg: int) -> float:
	return flag_angle(seg)


## Flat outward direction at angle `a` round the centre.
static func dir(a: float) -> Vector3:
	return Vector3(sin(a), 0.0, cos(a))


## Angle round the centre and flat distance from the tower's axis of local `pos`.
static func angle_of(pos: Vector3) -> float:
	return atan2(pos.x, pos.z - CENTER_Z)


static func flat_r(pos: Vector3) -> float:
	return Vector2(pos.x, pos.z - CENTER_Z).length()


## Every lane (see `_lanes`), segment by segment. Cached: don't modify.
static func lanes() -> Array[Dictionary]:
	if _lanes.is_empty():
		_make()
	return _lanes


## Index into `lanes()` of segment `seg`'s lane of `kind` (-1 if it has none).
static func lane_index(seg: int, kind: StringName) -> int:
	var all: Array[Dictionary] = lanes()
	for i: int in all.size():
		if int(all[i]["seg"]) == seg and all[i]["kind"] == kind:
			return i
	return -1


static func lane(seg: int, kind: StringName) -> Dictionary:
	var i: int = lane_index(seg, kind)
	return lanes()[i] if i >= 0 else {}


## Height (local y) of lane `l` at `t` radians along it (a riser counts as its top).
static func height(l: Dictionary, t: float) -> float:
	return level_y(int(l["seg"])) + _eval(l["knots"], t)


## Local point of lane `l` at `t` radians along it, `r` from the axis, on its walkway.
static func point(l: Dictionary, t: float, r: float) -> Vector3:
	var a: float = float(l["a0"]) + float(l["dir"]) * t
	var d: Vector3 = dir(a) * r
	return Vector3(d.x, height(l, t), CENTER_Z + d.z)


## Length of lane `l` along its line (metres).
static func lane_length(l: Dictionary) -> float:
	return float(l["theta"]) * float(l["rc"])


## The thetas of lane `l`'s risers (the hops), bottom to top.
static func risers(l: Dictionary) -> Array[float]:
	var out: Array[float] = []
	var kn: Array = l["knots"]
	for j: int in range(1, kn.size()):
		var a: Vector2 = kn[j - 1]
		var b: Vector2 = kn[j]
		if b.x - a.x < 1e-5 and b.y - a.y > 1e-4:
			out.append(b.x)
	return out


## Walkway pieces: {lane, t0, t1, y0, y1 (local heights at t0/t1), slab}. Cached: don't modify.
static func pieces() -> Array[Dictionary]:
	if _pieces.is_empty():
		var all: Array[Dictionary] = lanes()
		for i: int in all.size():
			var l: Dictionary = all[i]
			var kn: Array = l["knots"]
			var base: float = level_y(int(l["seg"]))
			for j: int in kn.size() - 1:
				var a: Vector2 = kn[j]
				var b: Vector2 = kn[j + 1]
				if b.x - a.x < 1e-5:
					continue
				var n: int = maxi(ceili((b.x - a.x) * float(l["r1"]) / PIECE_LEN), 1)
				for m: int in n:
					var f0: float = float(m) / float(n)
					var f1: float = float(m + 1) / float(n)
					var t0: float = lerpf(a.x, b.x, f0)
					_pieces.append({"lane": i, "t0": t0, "t1": lerpf(a.x, b.x, f1), "y0": base + lerpf(a.y, b.y, f0),
						"y1": base + lerpf(a.y, b.y, f1), "slab": t0 >= float(l["slab_from"]) - 1e-5})
	return _pieces


## Every walkway at local `pos`'s spot (flat): [{lane, theta, y}], one per layer.
static func surfaces_at(pos: Vector3) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var rho: float = flat_r(pos)
	var ang: float = angle_of(pos)
	var all: Array[Dictionary] = lanes()
	for i: int in all.size():
		var l: Dictionary = all[i]
		if rho < float(l["r0"]) - 0.02 or rho > float(l["r1"]) + 0.02:
			continue
		var t: float = fposmod(float(l["dir"]) * (ang - float(l["a0"])), TAU)
		# On a start landing the other lane's side is a hair below zero.
		if t > TAU - 0.02 / maxf(rho, 1.0):
			t -= TAU
		while t <= float(l["theta"]) + 1e-5:
			if t >= -0.03:
				out.append({"lane": i, "theta": clampf(t, 0.0, float(l["theta"])), "y": height(l, clampf(t, 0.0, float(l["theta"])))})
			t += TAU
	return out


## The walkway a bean at local `pos` stands on: the highest one at most `FEET` above its feet
## ({lane, theta, y}), {} on the floor, the pad or off the course.
static func lane_under(pos: Vector3) -> Dictionary:
	var best: Dictionary = {}
	for s: Dictionary in surfaces_at(pos):
		if float(s["y"]) <= pos.y + FEET and (best.is_empty() or float(s["y"]) > float(best["y"])):
			best = s
	return best


## Where a bean at local `pos` runs next to climb: {to (local point to run at; its height doesn't
## matter), lane (index, -1 off the walkways), hop (a hop's riser is right ahead: jump now)}.
## Along the lane it stands on (a widened first turn leads back onto its spiral), across onto the
## next tier at a lane's end, from the floor round the net to the start. At a fork (a flag landing)
## it takes the steady lane, or the bold one if `bold`.
static func guide(pos: Vector3, bold: bool = false) -> Dictionary:
	if flat_r(pos) < PAD_R and pos.y > TOP_Y - FEET:
		return {"to": pad_center(), "lane": -1, "hop": false}
	var on: Dictionary = lane_under(pos)
	if on.is_empty():
		return {"to": _floor_target(pos), "lane": -1, "hop": false}
	var idx: int = int(on["lane"])
	var l: Dictionary = lanes()[idx]
	var seg: int = int(l["seg"])
	var t: float = float(on["theta"])
	var kind: StringName = l["kind"]
	if kind == &"bridge":
		return {"to": _arrival_target(seg), "lane": idx, "hop": false}
	if _on_start(l, t):
		# A flag landing: pick the lane.
		var want: int = lane_index(seg, &"bold" if bold else &"steady")
		if want != idx:
			idx = want
			l = lanes()[idx]
			t = 0.0
			kind = l["kind"]
	if kind == &"wide":
		idx = lane_index(seg, &"steady")
		l = lanes()[idx]
	var rc: float = float(l["rc"])
	var end: float = float(l["theta"])
	if (end - t) * rc < FLAT * 0.6:
		return {"to": _arrival_target(seg), "lane": idx, "hop": false}
	var to: Vector3 = point(l, minf(t + LOOK / rc, end), rc)
	var hop: bool = false
	for rt: float in risers(l):
		var ahead: float = (rt - t) * rc
		if ahead > 0.05 and ahead < HOP_AT and pos.y < height(l, rt) - 0.3:
			hop = true
	return {"to": to, "lane": idx, "hop": hop}


## True if `t` on lane `l` is on its start landing (where the lanes fork at the flag).
static func _on_start(l: Dictionary, t: float) -> bool:
	return l["kind"] in [&"steady", &"bold", &"wide"] and t * float(l["rc"]) <= FLAT


## Where a lane of segment `seg` ends up: the next flag's landing, or the pad.
static func _arrival_target(seg: int) -> Vector3:
	if seg >= SEGMENTS - 1:
		return pad_center()
	return (checkpoints()[seg]["spots"] as Array)[0]


## From the floor: round the aisle outside the first ring to the start, then onto it.
static func _floor_target(pos: Vector3) -> Vector3:
	var a0: float = flag_angle(0)
	var start: Vector3 = Vector3(0.0, 0.0, CENTER_Z) + dir(a0) * ((ring_inner(0) + ring_outer(0)) * 0.5)
	var rho: float = flat_r(pos)
	var off: float = wrapf(angle_of(pos) - a0, -PI, PI)
	if absf(off) * rho < FLAT * 0.6 or rho > ring_outer(0) + 3.0 and absf(off) < 0.5:
		return start
	var cr: float = ring_outer(0) + 0.75
	var next: float = a0 + off - signf(off) * minf(LOOK / cr, absf(off))
	var d: Vector3 = dir(next) * cr
	return Vector3(d.x, 0.0, CENTER_Z + d.z)


## The pad's centre (top face), local.
static func pad_center() -> Vector3:
	return Vector3(0.0, TOP_Y, CENTER_Z)


## The checkpoints (the tiers' tops), bottom to top: {index (1..3), y, r (the tier's radius),
## angle, flag (local foot of the pole), spots (local respawn spots on the flag landing)}.
static func checkpoints() -> Array[Dictionary]:
	if _checkpoints.is_empty():
		for k: int in range(1, SEGMENTS):
			var a: float = flag_angle(k)
			var y: float = level_y(k)
			var outer: float = ring_outer(k)
			var inner: float = ring_inner(k)
			# The landing's open band: the whole ring, or its outer band (no slab overhead).
			var r0: float = inner if BANDS[k] == 1 else (inner + outer) * 0.5
			var rs: float = (r0 + outer) * 0.5
			var spots: Array[Vector3] = []
			for arc: float in [0.0, 0.9, -0.9]:
				var d: Vector3 = dir(a + arc / rs) * rs
				spots.append(Vector3(d.x, y, CENTER_Z + d.z))
			var fd: Vector3 = dir(a) * (outer - 0.3)
			_checkpoints.append({"index": k, "y": y, "r": level_r(k), "angle": a, "flag": Vector3(fd.x, y, CENTER_Z + fd.z),
				"spots": spots, "band": outer - r0})
	return _checkpoints


## The highest checkpoint whose tier top local `pos` stands on (or above), 0 for none.
static func checkpoint_at(pos: Vector3) -> int:
	var flat: float = Vector2(pos.x, pos.z - CENTER_Z).length()
	for k: int in range(SEGMENTS - 1, 0, -1):
		if pos.y >= level_y(k) - CHECK_BELOW and flat <= level_r(k) + CHECK_RIM:
			return k
	return 0


## The finish box over the pad (world when `o` is the room origin).
static func finish_box(o: Vector3) -> AABB:
	var c: Vector3 = o + pad_center()
	return AABB(c + Vector3(-FINISH_HALF, -0.4, -FINISH_HALF), Vector3(FINISH_HALF * 2.0, 3.4, FINISH_HALF * 2.0))


## Where finishers stand on the pad: a ring round its centre.
static func finish_spots(o: Vector3) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i: int in 8:
		var a: float = TAU * float(i) / 8.0
		out.append(o + pad_center() + Vector3(sin(a), 0.0, cos(a)) * 1.05)
	return out


## Direction (flat, local) from the pad's centre toward where both last lanes arrive: the rail's
## opening (south, toward the apron and the gallery).
static func entry_dir() -> Vector3:
	return dir(flag_angle(SEGMENTS))


static func _make() -> void:
	_lanes.clear()
	_pieces.clear()
	for seg: int in SEGMENTS:
		var a: float = flag_angle(seg)
		var ds: int = STEADY_DIR[seg]
		var h: float = level_y(seg + 1) - level_y(seg)
		var rin: float = ring_inner(seg)
		var rout: float = ring_outer(seg)
		var ts: float = TAU * STEADY_TURNS[seg]
		if BANDS[seg] == 1:
			var rc: float = (rin + rout) * 0.5
			_lanes.append(_lane(seg, &"steady", a, ds, rin, rout, ts, _profile(ts, rc, h, [])))
			_lanes.append(_lane(seg, &"bold", a, -ds, rin, rout, TAU - ts, _profile(TAU - ts, rc, h, BOLD_STEPS[seg])))
			continue
		var mid: float = (rin + rout) * 0.5
		var sk: Array[Vector2] = _profile(ts, (rin + mid) * 0.5, h, [])
		# Split the spiral where its second turn (a slab over the first) starts.
		var at: int = 0
		while at < sk.size() and sk[at].x < TAU:
			at += 1
		sk.insert(at, Vector2(TAU, _eval(sk, TAU)))
		var steady: Dictionary = _lane(seg, &"steady", a, ds, rin, mid, ts, sk)
		steady["slab_from"] = TAU
		_lanes.append(steady)
		var tb: float = 2.0 * TAU - ts
		var bold: Dictionary = _lane(seg, &"bold", a, -ds, mid, rout, tb, _profile(tb, (mid + rout) * 0.5, h, BOLD_STEPS[seg]))
		_lanes.append(bold)
		# The outer band between the flag and the arrival: the spiral's first turn, twice as wide.
		var arr: float = ts - TAU
		var wk: Array[Vector2] = []
		for k: Vector2 in sk:
			if k.x < arr - 1e-5:
				wk.append(k)
		wk.append(Vector2(arr, _eval(sk, arr)))
		_lanes.append(_lane(seg, &"wide", a, ds, mid, rout, arr, wk))
		# Over the inner band beside the bold lane's arrival: a slab across onto the next tier.
		var fb: float = minf(FLAT / float(bold["rc"]), tb * 0.15)
		var bridge: Dictionary = _lane(seg, &"bridge", a + float(ds) * arr, ds, rin, mid, fb, [Vector2(0.0, h), Vector2(fb, h)])
		bridge["slab_from"] = 0.0
		_lanes.append(bridge)


static func _lane(seg: int, kind: StringName, a0: float, d: int, r0: float, r1: float, theta: float, knots: Array[Vector2]) -> Dictionary:
	return {"seg": seg, "kind": kind, "a0": a0, "dir": d, "r0": r0, "r1": r1, "rc": (r0 + r1) * 0.5, "theta": theta,
		"knots": knots, "slab_from": INF}


## A lane's height profile: `FLAT` metres level at both ends, an even ramp between, and a riser of
## `STEP_H` onto a `STEP_TOP` chip top at each of `steps` (fractions along the lane).
static func _profile(span: float, rc: float, h: float, steps: Array) -> Array[Vector2]:
	var f: float = minf(FLAT / rc, span * 0.15)
	var top: float = STEP_TOP / rc
	var ramp: float = span - 2.0 * f - float(steps.size()) * top
	var rise: float = (h - STEP_H * float(steps.size())) / ramp
	var out: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(f, 0.0)]
	var t: float = f
	var y: float = 0.0
	for q: float in steps:
		var at: float = maxf(f + q * (span - 2.0 * f), t)
		y += (at - t) * rise
		out.append(Vector2(at, y))
		y += STEP_H
		out.append(Vector2(at, y))
		t = at + top
		out.append(Vector2(t, y))
	out.append(Vector2(span - f, h))
	out.append(Vector2(span, h))
	return out


## Piecewise linear through `knots` (a riser takes its top).
static func _eval(knots: Array, t: float) -> float:
	var y: float = (knots[0] as Vector2).y
	for j: int in range(1, knots.size()):
		var a: Vector2 = knots[j - 1]
		var b: Vector2 = knots[j]
		if t >= a.x - 1e-6:
			if b.x - a.x < 1e-6:
				y = b.y
			elif t <= b.x + 1e-6:
				y = lerpf(a.y, b.y, clampf((t - a.x) / (b.x - a.x), 0.0, 1.0))
			else:
				y = b.y
	return y


# --- Build --------------------------------------------------------------------------------------

## Builds the tiers, the walkways, the pad, the flags, the sign and the net under the room's `root`
## (local frame). `ceiling_y` is where the sign's chains hang from.
static func build(root: Node3D, brass: Material, ceiling_y: float) -> Node3D:
	var n := Node3D.new()
	n.name = "ChipTowers"
	root.add_child(n)
	var chips := _ChipBatch.new()
	for k: int in range(1, SEGMENTS):
		_tier(n, chips, k)
	_walkways(n, chips)
	_pad(n, chips, brass)
	chips.commit(n)
	for cp: Dictionary in checkpoints():
		_flag(n, cp, brass)
	_sign(n, brass, ceiling_y)
	_net(n, brass)
	_lights(n)
	return n


## Every lane: collision (two convex prisms per piece, solid down to its tier or a slab), one mesh
## (felt top, chip-edge sides, a dark underside under slabs, a gold trim along the outer edge),
## chevrons up the lane and a giant chip on every hop top.
static func _walkways(parent: Node3D, chips: _ChipBatch) -> void:
	var all: Array[Dictionary] = lanes()
	var by_lane: Dictionary[int, Array] = {}
	for p: Dictionary in pieces():
		var i: int = int(p["lane"])
		if not by_lane.has(i):
			by_lane[i] = []
		by_lane[i].append(p)
	var edge: StandardMaterial3D = edge_material()
	var steady_top: StandardMaterial3D = VaultArena._tex("velvet", 1.2, Palette.FELT_GREEN.lightened(0.12), 0.0, 0.92)
	var bold_top: StandardMaterial3D = VaultArena._tex("velvet", 1.2, Palette.VIP_BURGUNDY.lightened(0.2), 0.0, 0.92)
	var under: StandardMaterial3D = GreyboxKit.material(Palette.WARM_CHARCOAL.darkened(0.2), 0.0, 0.9)
	var gold: StandardMaterial3D = GreyboxKit.material(Palette.VIP_GOLD, 0.85, 0.25)
	var arrows: Array[Transform3D] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 7311
	for i: int in all.size():
		var l: Dictionary = all[i]
		var ps: Array = by_lane.get(i, [])
		var body := StaticBody3D.new()
		body.name = "Lane%d_%s" % [int(l["seg"]), String(l["kind"])]
		parent.add_child(body)
		var top := SurfaceTool.new()
		var side := SurfaceTool.new()
		var bottom := SurfaceTool.new()
		var trim := SurfaceTool.new()
		for st: SurfaceTool in [top, side, bottom, trim]:
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for j: int in ps.size():
			var p: Dictionary = ps[j]
			var prev: Dictionary = ps[j - 1] if j > 0 else {}
			var next: Dictionary = ps[j + 1] if j + 1 < ps.size() else {}
			_piece(body, l, p, prev, next, top, side, bottom, trim)
		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		var mesh := ArrayMesh.new()
		var mats: Array[Material] = [bold_top if l["kind"] == &"bold" else steady_top, edge, under, gold]
		var tools: Array[SurfaceTool] = [top, side, bottom, trim]
		for k: int in tools.size():
			var arrays: Array = tools[k].commit_to_arrays()
			if not (arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array) or (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
				continue
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_material(mesh.get_surface_count() - 1, mats[k])
		mi.mesh = mesh
		body.add_child(mi)
		if l["kind"] in [&"steady", &"bold"]:
			_lane_arrows(l, arrows)
		for rt: float in risers(l):
			# A giant chip lying on the hop's top, its denomination reading from below.
			var mid_t: float = rt + STEP_TOP * 0.5 / float(l["rc"])
			var c: Vector3 = point(l, mid_t, float(l["rc"]))
			var r: float = minf((float(l["r1"]) - float(l["r0"])) * 0.5, STEP_TOP * 0.5) - 0.06
			var ci: int = rng.randi_range(0, ChipStack.TIER_COLORS.size() - 1)
			chips.chip(c + Vector3(0, 0.012 - CHIP_T * 0.5, 0), r, CHIP_T, rng.randf() * TAU, ChipStack.TIER_COLORS[ci], 8)
			var lab := Label3D.new()
			lab.text = DENOMS[ci]
			lab.font = Vfx.font()
			lab.font_size = 96
			lab.pixel_size = 0.0052 * r / 0.7
			lab.modulate = ((ChipStack.materials_for(ChipStack.TIER_COLORS[ci])[2]) as StandardMaterial3D).albedo_color
			lab.outline_size = 0
			lab.shaded = true
			lab.double_sided = false
			var back: Vector3 = point(l, rt - 0.5 / float(l["rc"]), float(l["rc"])) - c
			lab.rotation = Vector3(-PI * 0.5, atan2(back.x, back.z), 0.0)
			lab.position = c + Vector3(0, 0.016, 0)
			parent.add_child(lab)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var pm := PrismMesh.new()
	pm.size = Vector3(0.7, 0.55, 0.025)
	mm.mesh = pm
	mm.instance_count = arrows.size()
	for i: int in arrows.size():
		mm.set_instance_transform(i, arrows[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "LaneArrows"
	mmi.multimesh = mm
	mmi.material_override = GreyboxKit.material(Palette.CREAM.darkened(0.05), 0.0, 0.7)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)


## One piece: its two prisms, its top, its outer (and, off a column, inner) side, the risers and
## ends of the lane, a slab's underside, the trim.
static func _piece(body: StaticBody3D, l: Dictionary, p: Dictionary, prev: Dictionary, next: Dictionary, top: SurfaceTool, side: SurfaceTool, bottom: SurfaceTool, trim: SurfaceTool) -> void:
	var seg: int = int(l["seg"])
	var on_column: bool = is_equal_approx(float(l["r0"]), ring_inner(seg))
	var r0: float = float(l["r0"]) - (0.05 if on_column else 0.02)
	var r1: float = float(l["r1"]) + (0.0 if is_equal_approx(float(l["r1"]), ring_outer(seg)) else 0.02)
	var t0: float = p["t0"]
	var t1: float = p["t1"]
	var y0: float = p["y0"]
	var y1: float = p["y1"]
	var slab: bool = p["slab"]
	var base: float = level_y(seg) - 0.05
	var a: Vector3 = _at(l, t0, r0, y0)
	var b: Vector3 = _at(l, t0, r1, y0)
	var c: Vector3 = _at(l, t1, r1, y1)
	var d: Vector3 = _at(l, t1, r0, y1)
	for tri: Array in [[a, b, c], [a, c, d]]:
		var pts := PackedVector3Array()
		for v: Vector3 in tri:
			pts.append(v)
		for v: Vector3 in tri:
			pts.append(Vector3(v.x, v.y - SLAB_T if slab else base, v.z))
		var cs := CollisionShape3D.new()
		var shape := ConvexPolygonShape3D.new()
		shape.points = pts
		cs.shape = shape
		body.add_child(cs)
	var a_lo: Vector3 = Vector3(a.x, y0 - SLAB_T if slab else base, a.z)
	var b_lo: Vector3 = Vector3(b.x, y0 - SLAB_T if slab else base, b.z)
	var c_lo: Vector3 = Vector3(c.x, y1 - SLAB_T if slab else base, c.z)
	var d_lo: Vector3 = Vector3(d.x, y1 - SLAB_T if slab else base, d.z)
	var up: Vector3 = (c - a).cross(b - a).normalized()
	if up.y < 0.0:
		up = -up
	_face(top, a, b, c, d, up, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
	var out_n: Vector3 = (b + c) * 0.5 - Vector3(0, 0, CENTER_Z)
	out_n.y = 0.0
	out_n = out_n.normalized()
	_side(side, b_lo, c_lo, c, b, out_n, t0 * r1, t1 * r1)
	if not on_column:
		_side(side, a_lo, d_lo, d, a, -out_n, t0 * r0, t1 * r0)
	if slab:
		_face(bottom, a_lo, b_lo, c_lo, d_lo, Vector3.DOWN, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
	# Ends: the lane's start (off the floor of its tier) and end, a riser (the next piece starts
	# higher), the solid first turn ending under the slab that carries on above it.
	var fwd: Vector3 = (d + c - a - b)
	fwd.y = 0.0
	fwd = fwd.normalized()
	if prev.is_empty() and y0 - a_lo.y > 0.06:
		_side(side, b_lo, a_lo, a, b, -fwd, r1, r0)
	if next.is_empty():
		_side(side, d_lo, c_lo, c, d, fwd, r0, r1)
	elif bool(next["slab"]) and not slab:
		var hi: float = float(next["y0"]) - SLAB_T
		_side(side, Vector3(d.x, base, d.z), Vector3(c.x, base, c.z), Vector3(c.x, hi, c.z), Vector3(d.x, hi, d.z), fwd, r0, r1)
	elif float(next["y0"]) > y1 + 1e-4:
		var rise_to: float = float(next["y0"])
		_side(side, d, c, Vector3(c.x, rise_to, c.z), Vector3(d.x, rise_to, d.z), -fwd, r0, r1)
	# Gold trim along the outer edge (a hair above the felt).
	var inw: float = 0.09
	var b_in: Vector3 = _at(l, t0, r1 - inw, y0)
	var c_in: Vector3 = _at(l, t1, r1 - inw, y1)
	var lift := Vector3(0, 0.012, 0)
	_face(trim, b_in + lift, b + lift, c + lift, c_in + lift, up, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)


## Local point of lane `l` at `t`, radius `r`, height `y`.
static func _at(l: Dictionary, t: float, r: float, y: float) -> Vector3:
	var dd: Vector3 = dir(float(l["a0"]) + float(l["dir"]) * t) * r
	return Vector3(dd.x, y, CENTER_Z + dd.z)


## A side face (bottom edge a-b, top edge c-d... given as lo0, lo1, hi1, hi0) facing `n`, the
## chip-edge texture running along it (`u0`..`u1` metres) and up it in world height.
static func _side(st: SurfaceTool, lo0: Vector3, lo1: Vector3, hi1: Vector3, hi0: Vector3, n: Vector3, u0: float, u1: float) -> void:
	if hi0.y - lo0.y < 0.005 and hi1.y - lo1.y < 0.005:
		return
	_face(st, lo0, lo1, hi1, hi0, n, Vector2(u0, -lo0.y / EDGE_TILE), Vector2(u1, -lo1.y / EDGE_TILE), Vector2(u1, -hi1.y / EDGE_TILE), Vector2(u0, -hi0.y / EDGE_TILE))


## Quad a-b-c-d facing `n` (both triangles wound for it), with UVs.
static func _face(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2) -> void:
	for tri: Array in [[a, b, c, ua, ub, uc], [a, c, d, ua, uc, ud]]:
		var p: Vector3 = tri[0]
		var q: Vector3 = tri[1]
		var r: Vector3 = tri[2]
		var order: Array[int] = [0, 1, 2]
		if (q - p).cross(r - p).dot(n) > 0.0:
			order = [0, 2, 1]  # Godot: clockwise seen from the front
		for k: int in order:
			st.set_normal(n)
			st.set_uv(tri[3 + k])
			st.add_vertex(tri[k])


## Chevrons lying on lane `l`, pointing up it, every ~4.5 m (not on the hop tops or risers).
static func _lane_arrows(l: Dictionary, out: Array[Transform3D]) -> void:
	var rc: float = float(l["rc"])
	var length: float = lane_length(l)
	var s: float = FLAT + 1.0
	var rs: Array[float] = risers(l)
	while s < length - FLAT:
		var t: float = s / rc
		var clear: bool = true
		for rt: float in rs:
			if t > rt - 0.9 / rc and t < rt + (STEP_TOP + 0.4) / rc:
				clear = false
		if clear:
			var p: Vector3 = point(l, t, rc)
			var q: Vector3 = point(l, t + 0.3 / rc, rc)
			var fwd: Vector3 = (q - p).normalized()
			var flat_side: Vector3 = fwd.cross(Vector3.UP).normalized()
			var up: Vector3 = flat_side.cross(fwd).normalized()
			if up.y < 0.0:
				up = -up
			var right: Vector3 = fwd.cross(up).normalized()
			out.append(Transform3D(Basis(right, fwd, up), p + up * 0.02))
		s += 4.5


## The chip-edge texture up every walkway's side: four chips per tile, each a colour with cream (or
## dark) edge spots staggered chip to chip and a dark seam between chips.
static func edge_material() -> StandardMaterial3D:
	var w: int = 128
	var hgt: int = 64
	var img := Image.create(w, hgt, false, Image.FORMAT_RGBA8)
	var order: Array[int] = [2, 1, 4, 3]
	var band: int = hgt / order.size()
	for k: int in order.size():
		var col: Color = ChipStack.TIER_COLORS[order[k]]
		var spot: Color = Palette.WARM_CHARCOAL if ChipStack.is_light(col) else Palette.CREAM
		var y0: int = k * band
		img.fill_rect(Rect2i(0, y0, w, band), col)
		for s: int in 4:
			var x: int = (s * w / 4 + (k % 2) * w / 8) % w
			img.fill_rect(Rect2i(x, y0 + 3, 12, band - 6), spot)
		img.fill_rect(Rect2i(0, y0 + band - 1, w, 1), col.darkened(0.55))
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.roughness = 0.55
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return m


## A tier: giant chips of its colour from the level below up to its top, the top chip's face is
## the checkpoint floor.
static func _tier(parent: Node3D, chips: _ChipBatch, k: int) -> void:
	var r: float = level_r(k)
	var y0: float = level_y(k - 1)
	var y1: float = level_y(k)
	ClimbKit.column(parent, r, y1 - y0, Vector3(0.0, y0, CENTER_Z), "Tier%d" % k)
	var count: int = maxi(roundi((y1 - y0) / (r * GIANT_T)), 2)
	var t: float = (y1 - y0) / float(count)
	var col: Color = TIER_COLORS[k - 1]
	for c: int in count:
		chips.chip(Vector3(0.0, y0 + t * (float(c) + 0.5), CENTER_Z), r, t, float(c) * 0.41 + float(k), col if c % 3 != 1 else col.lightened(0.12), 16, 0.24)
	chips.core(Vector3(0.0, y0, CENTER_Z), r * 0.985, y1 - y0 - t * 0.5)




## The jackpot stack on tier 3: big burgundy and gold chips up to the gold pad, a glowing rim,
## JACKPOT lettered round its top and a gold rail with an opening to the south.
static func _pad(parent: Node3D, chips: _ChipBatch, brass: Material) -> void:
	var c: Vector3 = pad_center()
	var y0: float = level_y(SEGMENTS - 1)
	ClimbKit.column(parent, PAD_R, TOP_Y - y0, Vector3(c.x, y0, c.z), "JackpotStack")
	var count: int = roundi((TOP_Y - y0) / PAD_CHIP_T)
	var t: float = (TOP_Y - y0) / float(count)
	for k: int in count:
		var col: Color = Palette.VIP_GOLD if k % 4 == 3 else Palette.VIP_BURGUNDY
		chips.chip(Vector3(c.x, y0 + t * (float(k) + 0.5), c.z), PAD_R, t, float(k) * 0.37, col, 10, 0.3)
	chips.core(Vector3(c.x, y0, c.z), PAD_R * 0.97, TOP_Y - y0 - t * 0.5)
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Palette.VIP_GOLD
	gold.metallic = 0.85
	gold.roughness = 0.25
	gold.emission_enabled = true
	gold.emission = Palette.WARM_GOLD
	gold.emission_energy_multiplier = 0.25
	var face: MeshInstance3D = ParlorRoom._cyl(parent, PAD_R - 0.1, 0.03, c + Vector3(0, 0.012, 0), gold, 40)
	face.name = "FinishPad"
	var cream: StandardMaterial3D = GreyboxKit.material(Palette.CREAM, 0.0, 0.5)
	var inlay := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.3
	tm.outer_radius = 1.45
	tm.rings = 40
	tm.ring_segments = 4
	inlay.mesh = tm
	inlay.material_override = cream
	inlay.scale = Vector3(1.0, 0.1, 1.0)
	inlay.position = c + Vector3(0, 0.03, 0)
	parent.add_child(inlay)
	# A warm glowing rim round the pad's edge.
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(1.0, 0.86, 0.55)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.78, 0.42)
	glow.emission_energy_multiplier = 1.6
	var rim := MeshInstance3D.new()
	var rm := TorusMesh.new()
	rm.inner_radius = PAD_R - 0.06
	rm.outer_radius = PAD_R + 0.06
	rm.rings = 48
	rm.ring_segments = 8
	rim.mesh = rm
	rim.material_override = glow
	rim.position = c + Vector3(0, -0.04, 0)
	parent.add_child(rim)
	# JACKPOT round the edge of the top chip, facing out.
	var letters: String = "JACKPOT  JACKPOT  "
	for i: int in letters.length():
		if letters[i] == " ":
			continue
		var a: float = TAU * float(i) / float(letters.length())
		var l := Label3D.new()
		l.text = letters[i]
		l.font = Vfx.font()
		l.font_size = 72
		l.pixel_size = 0.005
		l.modulate = Palette.VIP_GOLD
		l.outline_size = 0
		l.shaded = true
		l.double_sided = false
		l.position = c + Vector3(sin(a) * (PAD_R + 0.02), -t * 0.5, cos(a) * (PAD_R + 0.02))
		l.rotation.y = a
		parent.add_child(l)
	# The rail: gold posts and a top bar, open toward where the last lanes arrive.
	var entry: Vector3 = entry_dir()
	var entry_a: float = atan2(entry.x, entry.z)
	var rail_r: float = PAD_R - 0.12
	var steps: int = 24
	var prev: Vector3 = Vector3.INF
	for k: int in steps + 1:
		var a: float = TAU * float(k) / float(steps)
		if absf(wrapf(a - entry_a, -PI, PI)) < 0.62:
			prev = Vector3.INF
			continue
		var p: Vector3 = c + Vector3(sin(a) * rail_r, 0.0, cos(a) * rail_r)
		VaultArena._vis(parent, Vector3(0.06, 0.95, 0.06), p + Vector3(0, 0.475, 0), gold)
		VaultArena._sphere(parent, 0.07, p + Vector3(0, 0.98, 0), gold)
		if prev != Vector3.INF:
			var mid: Vector3 = (prev + p) * 0.5
			var d: Vector3 = p - prev
			var bar: MeshInstance3D = VaultArena._vis(parent, Vector3(0.07, 0.07, d.length() + 0.04), mid + Vector3(0, 0.95, 0), gold)
			bar.basis = Basis.looking_at(d.normalized(), Vector3.UP)
			var low: MeshInstance3D = VaultArena._vis(parent, Vector3(0.04, 0.04, d.length()), mid + Vector3(0, 0.45, 0), brass)
			low.basis = bar.basis
			var guard: StaticBody3D = ClimbKit.guard(parent, Vector3(0.12, 1.2, d.length() + 0.05), mid + Vector3(0, 0.6, 0), "PadRail")
			guard.basis = bar.basis
		prev = p


## A checkpoint flag on a tier's top: a brass pole with a gold chip finial, a burgundy cloth with
## the checkpoint's number (`Cloth`, the stage lights it when you reach it) and a gold ring on the
## floor round the respawn spot. No collision: it never blocks a landing.
static func _flag(parent: Node3D, cp: Dictionary, brass: Material) -> void:
	var k: int = int(cp["index"])
	var f := Node3D.new()
	f.name = "Flag%d" % k
	f.position = cp["flag"]
	f.rotation.y = float(cp["angle"])
	parent.add_child(f)
	var gold: StandardMaterial3D = GreyboxKit.material(Palette.VIP_GOLD, 0.85, 0.25)
	ParlorRoom._cyl(f, 0.22, 0.08, Vector3(0, 0.04, 0), brass, 16)
	ParlorRoom._cyl(f, 0.045, 2.7, Vector3(0, 1.35, 0), brass, 10)
	var finial := Node3D.new()
	finial.position = Vector3(0, 2.8, 0)
	finial.rotation.x = PI * 0.5
	f.add_child(finial)
	ParlorRoom._cyl(finial, 0.14, 0.05, Vector3.ZERO, gold, 20)
	# The cloth hangs off the pole sideways (along the tier's rim), facing outward.
	var cloth_mat := StandardMaterial3D.new()
	cloth_mat.albedo_color = Palette.VIP_BURGUNDY
	cloth_mat.roughness = 0.85
	var cloth: MeshInstance3D = VaultArena._vis(f, Vector3(1.2, 0.78, 0.04), Vector3(0.64, 2.25, 0), cloth_mat)
	cloth.name = "Cloth"
	VaultArena._vis(f, Vector3(1.24, 0.06, 0.06), Vector3(0.64, 2.66, 0), gold)
	VaultArena._vis(f, Vector3(1.24, 0.06, 0.06), Vector3(0.64, 1.84, 0), gold)
	for side: float in [1.0, -1.0]:
		for line: int in 2:
			var l := Label3D.new()
			l.text = "CHECKPOINT" if line == 0 else str(k)
			l.font = Vfx.font()
			l.font_size = 40 if line == 0 else 96
			l.pixel_size = 0.0042 if line == 0 else 0.0045
			l.modulate = Palette.CREAM if line == 0 else Palette.VIP_GOLD
			l.outline_size = 0
			l.shaded = true
			l.double_sided = false
			l.position = Vector3(0.64, 2.47 if line == 0 else 2.15, 0.03 * side)
			l.rotation.y = 0.0 if side > 0.0 else PI
			f.add_child(l)
	# The gold ring round the respawn spot (in the tier's frame, not the flag's).
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	var ring_r: float = minf(1.08, float(cp["band"]) * 0.5 - 0.08)
	tm.inner_radius = ring_r - 0.13
	tm.outer_radius = ring_r
	tm.rings = 32
	tm.ring_segments = 4
	ring.mesh = tm
	ring.material_override = gold
	ring.scale = Vector3(1.0, 0.12, 1.0)
	ring.position = (cp["spots"] as Array)[0] + Vector3(0, 0.01, 0)
	ring.name = "FlagRing%d" % k
	parent.add_child(ring)


## The JACKPOT sign over the pad: a walnut board with burgundy faces and a gold frame, JACKPOT on
## both faces under a marquee of warm bulbs (two alternating sets the stage chases), a name line
## below and brass chains to the ceiling.
static func _sign(parent: Node3D, brass: Material, ceiling_y: float) -> void:
	var c: Vector3 = pad_center() + Vector3(0, SIGN_Y, 0)
	var sign := Node3D.new()
	sign.name = "JackpotSign"
	sign.position = c
	parent.add_child(sign)
	var walnut: StandardMaterial3D = GreyboxKit.material(ClimbRoom.WALNUT_DARK, 0.0, 0.5)
	var velvet: StandardMaterial3D = VaultArena._tex("velvet", 1.2, Palette.VIP_BURGUNDY.lightened(0.05), 0.0, 0.9)
	var gold: StandardMaterial3D = GreyboxKit.material(Palette.VIP_GOLD, 0.85, 0.25)
	VaultArena._vis(sign, Vector3(SIGN_W, SIGN_H, 0.3), Vector3.ZERO, walnut)
	VaultArena._vis(sign, Vector3(SIGN_W - 0.5, SIGN_H - 0.5, 0.34), Vector3.ZERO, velvet)
	for y: float in [-1.0, 1.0]:
		VaultArena._vis(sign, Vector3(SIGN_W + 0.1, 0.1, 0.38), Vector3(0, y * SIGN_H * 0.5, 0), gold)
	for x: float in [-1.0, 1.0]:
		VaultArena._vis(sign, Vector3(0.1, SIGN_H + 0.1, 0.38), Vector3(x * SIGN_W * 0.5, 0, 0), gold)
	# A crest on top: a gold chip on edge.
	var crest := Node3D.new()
	crest.position = Vector3(0, SIGN_H * 0.5 + 0.55, 0)
	crest.rotation.x = PI * 0.5
	sign.add_child(crest)
	ParlorRoom._cyl(crest, 0.5, 0.16, Vector3.ZERO, gold, 32)
	for side: float in [-1.0, 1.0]:
		var face := Node3D.new()
		face.rotation.y = 0.0 if side > 0.0 else PI
		sign.add_child(face)
		var word := Label3D.new()
		word.name = "Word"
		word.text = "JACKPOT"
		word.font = Vfx.font()
		word.font_size = 200
		word.pixel_size = 0.0075
		word.modulate = Palette.VIP_GOLD
		word.outline_modulate = Palette.WARM_CHARCOAL
		word.outline_size = 12
		word.shaded = false
		word.double_sided = false
		word.position = Vector3(0, 0.3, 0.19)
		face.add_child(word)
		var name_l := Label3D.new()
		name_l.name = "NameFront" if side > 0.0 else "NameBack"
		name_l.text = "FIRST TO THE TOP"
		name_l.font = Vfx.font()
		name_l.font_size = 64
		name_l.pixel_size = 0.0085
		name_l.modulate = Palette.CREAM
		name_l.outline_size = 0
		name_l.shaded = false
		name_l.double_sided = false
		name_l.position = Vector3(0, -0.78, 0.19)
		face.add_child(name_l)
	# The marquee: warm bulbs round the frame on both faces, alternating sets A and B.
	var pts: Array[Vector3] = []
	var hw: float = SIGN_W * 0.5 - 0.12
	var hh: float = SIGN_H * 0.5 - 0.12
	var per: float = (hw + hh) * 4.0
	var n: int = roundi(per / 0.34)
	for i: int in n:
		var s: float = per * float(i) / float(n)
		var p: Vector2
		if s < hw * 2.0:
			p = Vector2(-hw + s, hh)
		elif s < hw * 2.0 + hh * 2.0:
			p = Vector2(hw, hh - (s - hw * 2.0))
		elif s < hw * 4.0 + hh * 2.0:
			p = Vector2(hw - (s - hw * 2.0 - hh * 2.0), -hh)
		else:
			p = Vector2(-hw, -hh + (s - hw * 4.0 - hh * 2.0))
		pts.append(Vector3(p.x, p.y, 0.0))
	for set_i: int in 2:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var bulb := SphereMesh.new()
		bulb.radius = 0.07
		bulb.height = 0.14
		bulb.radial_segments = 8
		bulb.rings = 4
		mm.mesh = bulb
		var mine: Array[Vector3] = []
		for i: int in pts.size():
			if i % 2 == set_i:
				mine.append(pts[i])
		mm.instance_count = mine.size() * 2
		var k: int = 0
		for p: Vector3 in mine:
			for z: float in [0.2, -0.2]:
				mm.set_instance_transform(k, Transform3D(Basis.IDENTITY, p + Vector3(0, 0, z)))
				k += 1
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "BulbsA" if set_i == 0 else "BulbsB"
		mmi.multimesh = mm
		mmi.material_override = bulb_material()
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sign.add_child(mmi)
	# Brass chains to the ceiling.
	for x: float in [-SIGN_W * 0.38, SIGN_W * 0.38]:
		var len_y: float = ceiling_y - c.y - SIGN_H * 0.5
		ParlorRoom._cyl(sign, 0.035, len_y, Vector3(x, SIGN_H * 0.5 + len_y * 0.5, 0), brass, 6)
		VaultArena._sphere(sign, 0.1, Vector3(x, SIGN_H * 0.5 + 0.05, 0), brass)
	var glow := OmniLight3D.new()
	glow.name = "SignGlow"
	glow.light_color = Color(1.0, 0.8, 0.5)
	glow.light_energy = 1.4
	glow.omni_range = 9.0
	glow.position = Vector3(0, -SIGN_H * 0.5 - 0.6, 0)
	sign.add_child(glow)


## A warm marquee bulb (the stage pulses its emission).
static func bulb_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.9, 0.7)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.76, 0.4)
	m.emission_energy_multiplier = 2.0
	m.roughness = 0.3
	return m


## The safety net: a dark pit floor under a red rope grid in a brass frame, from the apron's edge
## to the far wall.
static func _net(parent: Node3D, brass: Material) -> void:
	var x0: float = -HALL_HALF_X + 0.4
	var x1: float = HALL_HALF_X - 0.4
	var z0: float = FAR_Z + 0.4
	var z1: float = -0.4
	var pit := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(x1 - x0, z1 - z0)
	pit.mesh = pm
	pit.material_override = GreyboxKit.material(Palette.WARM_CHARCOAL, 0.0, 0.95)
	pit.position = Vector3((x0 + x1) * 0.5, 0.008, (z0 + z1) * 0.5)
	parent.add_child(pit)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	mm.mesh = bm
	var xf: Array[Transform3D] = []
	var step: float = 0.55
	var x: float = x0
	while x <= x1 + 0.001:
		xf.append(Transform3D(Basis.from_scale(Vector3(0.05, 0.03, z1 - z0)), Vector3(x, 0.03, (z0 + z1) * 0.5)))
		x += step
	var z: float = z0
	while z <= z1 + 0.001:
		xf.append(Transform3D(Basis.from_scale(Vector3(x1 - x0, 0.03, 0.05)), Vector3((x0 + x1) * 0.5, 0.032, z)))
		z += step
	mm.instance_count = xf.size()
	for i: int in xf.size():
		mm.set_instance_transform(i, xf[i])
	var ropes := MultiMeshInstance3D.new()
	ropes.name = "SafetyNet"
	ropes.multimesh = mm
	ropes.material_override = GreyboxKit.material(Palette.CASINO_RED.darkened(0.35), 0.0, 0.85)
	ropes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(ropes)
	VaultArena._vis(parent, Vector3(x1 - x0 + 0.2, 0.08, 0.12), Vector3((x0 + x1) * 0.5, 0.04, z1), brass)
	VaultArena._vis(parent, Vector3(x1 - x0 + 0.2, 0.08, 0.12), Vector3((x0 + x1) * 0.5, 0.04, z0), brass)
	for side: float in [x0, x1]:
		VaultArena._vis(parent, Vector3(0.12, 0.08, z1 - z0), Vector3(side, 0.04, (z0 + z1) * 0.5), brass)


## Warm lamps round the cake at every tier, and a spot on the pad.
static func _lights(parent: Node3D) -> void:
	var warm := Color(1.0, 0.82, 0.58)
	for k: int in SEGMENTS:
		var y: float = level_y(k) + 4.5
		var r: float = level_r(k + 1) + 3.2
		for a: float in [0.6, 2.4, 3.9, 5.5]:
			var p: Vector3 = Vector3(0.0, y, CENTER_Z) + dir(a + float(k) * 0.4) * r
			p.x = clampf(p.x, -HALL_HALF_X + 1.0, HALL_HALF_X - 1.0)
			GreyboxKit.lamp(parent, p, 0.9, 10.0, warm)
	var spot := SpotLight3D.new()
	spot.name = "PadSpot"
	spot.light_color = Color(1.0, 0.86, 0.6)
	spot.light_energy = 3.0
	spot.spot_range = 12.0
	spot.spot_angle = 30.0
	spot.position = pad_center() + Vector3(0, 8.0, 0)
	spot.rotation.x = -PI * 0.5
	parent.add_child(spot)


# --- The chip model -------------------------------------------------------------------------------

## A casino chip of radius 1 and thickness 1 (centred; scale it per chip) in `color`: a slightly
## bevelled rim with `spots` flush edge spots in the insert colour that carry over the bevel onto
## both faces as short dashes, and a printed ring round the centre of each face. Two surfaces
## (body, spots), cached per colour and pattern. `spot_frac`: a spot's share of its period; `bevel`:
## the rim's bevel as a share of the thickness (giant chips take less).
static func chip_mesh(color: Color, spots: int, spot_frac: float = 0.42, bevel: float = 0.12) -> ArrayMesh:
	var key: String = "%s:%d:%.2f:%.2f" % [color.to_html(false), spots, spot_frac, bevel]
	if _meshes.has(key):
		return _meshes[key]
	const H: float = 0.5
	var bevel_y: float = bevel
	const BEVEL_R: float = 0.03  # of the radius
	const DASH_IN: float = 0.8
	const RING_OUT: float = 0.64
	const RING_IN: float = 0.56
	var body := SurfaceTool.new()
	var spot := SurfaceTool.new()
	body.begin(Mesh.PRIMITIVE_TRIANGLES)
	spot.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Arcs round the rim: [from, to, is_spot], each spot a bit under half its period.
	var period: float = TAU / float(spots)
	var half_w: float = period * spot_frac * 0.5
	var arcs: Array = []
	for p: int in spots:
		var a0: float = float(p) * period
		arcs.append([a0 - half_w, a0 + half_w, true])
		arcs.append([a0 + half_w, a0 + period - half_w, false])
	var rim: float = 1.0 - BEVEL_R
	for arc: Array in arcs:
		var from: float = arc[0]
		var to: float = arc[1]
		var is_spot: bool = arc[2]
		var steps: int = maxi(ceili((to - from) / (TAU / 72.0)), 1)
		var st: SurfaceTool = spot if is_spot else body
		for k: int in steps:
			var a: float = lerpf(from, to, float(k) / float(steps))
			var b: float = lerpf(from, to, float(k + 1) / float(steps))
			var da := Vector3(sin(a), 0.0, cos(a))
			var db := Vector3(sin(b), 0.0, cos(b))
			var up := Vector3.UP
			# The rim and its bevels.
			_quad(st, da + up * (H - bevel_y), db + up * (H - bevel_y), db - up * (H - bevel_y), da - up * (H - bevel_y), da, db)
			var bn_a: Vector3 = (da * bevel_y + up * BEVEL_R).normalized()
			var bn_b: Vector3 = (db * bevel_y + up * BEVEL_R).normalized()
			_quad(st, da * rim + up * H, db * rim + up * H, db + up * (H - bevel_y), da + up * (H - bevel_y), bn_a, bn_b)
			var bd_a: Vector3 = (da * bevel_y - up * BEVEL_R).normalized()
			var bd_b: Vector3 = (db * bevel_y - up * BEVEL_R).normalized()
			_quad(st, da - up * (H - bevel_y), db - up * (H - bevel_y), db * rim - up * H, da * rim - up * H, bd_a, bd_b)
			# Both faces: dash (spot colour over the spots) or body out to the rim, body, the printed
			# ring, body to the centre.
			for s: float in [1.0, -1.0]:
				var n := Vector3(0.0, s, 0.0)
				var y := Vector3(0.0, H * s, 0.0)
				_ring(st, da, db, DASH_IN, rim, y, n)
				_ring(body, da, db, RING_OUT, DASH_IN, y, n)
				_ring(spot, da, db, RING_IN, RING_OUT, y, n)
				_tri(body, y, da * RING_IN + y, db * RING_IN + y, n, n, n)
	var mats: Array = ChipStack.materials_for(color)
	var mesh: ArrayMesh = body.commit()
	mesh = spot.commit(mesh)
	mesh.surface_set_material(0, mats[0])
	mesh.surface_set_material(1, mats[2])
	_meshes[key] = mesh
	return mesh


## A flat ring piece between radii `r0` and `r1` over the arc da..db at height `y`.
static func _ring(st: SurfaceTool, da: Vector3, db: Vector3, r0: float, r1: float, y: Vector3, n: Vector3) -> void:
	_quad(st, da * r1 + y, db * r1 + y, db * r0 + y, da * r0 + y, n, n)


## Quad a-b-c-d (a/d on the `na` edge, b/c on the `nb` edge), wound to face along its normals.
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, na: Vector3, nb: Vector3) -> void:
	_tri(st, a, b, c, na, nb, nb)
	_tri(st, a, c, d, na, nb, na)


## A triangle wound so its front faces along the normals (Godot: clockwise from the front).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3) -> void:
	if (b - a).cross(c - a).dot(na + nb + nc) > 0.0:
		_tri(st, a, c, b, na, nc, nb)
		return
	st.set_normal(na)
	st.add_vertex(a)
	st.set_normal(nb)
	st.add_vertex(b)
	st.set_normal(nc)
	st.add_vertex(c)


## Chips batched into multimeshes per colour and spot count, plus the dark cores showing in the
## hairline seams between chips.
class _ChipBatch:
	extends RefCounted
	var chips: Dictionary[String, Array] = {}
	var meshes: Dictionary[String, ArrayMesh] = {}
	var cores: Array[Transform3D] = []

	## A chip centred at `c`, radius `r`, `t` of the stack's height (a hairline seam shows the dark
	## core between chips), turned `yaw`.
	func chip(c: Vector3, r: float, t: float, yaw: float, color: Color, spots: int, spot_frac: float = 0.42) -> void:
		var bevel: float = clampf(0.015 / t, 0.03, 0.12)  # about 1.5 cm whatever the chip
		var key: String = "%s:%d:%.2f:%.2f" % [color.to_html(false), spots, spot_frac, bevel]
		if not chips.has(key):
			chips[key] = []
			meshes[key] = ChipTowers.chip_mesh(color, spots, spot_frac, bevel)
		var seam: float = clampf(t * 0.06, 0.006, 0.02)
		chips[key].append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(r, t - seam, r)), c))

	## A dark core from `base` up `h`, radius `r` (its top stays under the top chip's face).
	func core(base: Vector3, r: float, h: float) -> void:
		cores.append(Transform3D(Basis.from_scale(Vector3(r, h, r)), base + Vector3(0, h * 0.5, 0)))

	func commit(parent: Node3D) -> void:
		for key: String in chips:
			_add(parent, "Chips_" + key.replace(":", "_"), meshes[key], chips[key], null)
		var disc := CylinderMesh.new()
		disc.top_radius = 1.0
		disc.bottom_radius = 1.0
		disc.height = 1.0
		disc.radial_segments = 28
		disc.rings = 1
		_add(parent, "Cores", disc, cores, GreyboxKit.material(Palette.WARM_CHARCOAL.darkened(0.3), 0.0, 0.9))

	func _add(parent: Node3D, name: String, mesh: Mesh, xf: Array, mat: Material) -> void:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = xf.size()
		for i: int in xf.size():
			mm.set_instance_transform(i, xf[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = name
		mmi.multimesh = mm
		if mat != null:
			mmi.material_override = mat
		parent.add_child(mmi)
