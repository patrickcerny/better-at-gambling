class_name PlinkoFlight
extends RefCounted
## Turns a `PlinkoSteering` peg path into a believable 2D chip flight on a `PlinkoStation` board:
## the chip falls out of the funnel, strikes one peg per row on the side that sends it the way the
## path goes, flies a real ballistic arc (gravity) to its contact on the next peg, drops between
## the slot dividers into the server's slot, hops twice and settles. Pure maths, no nodes.
##
## Every arc is checked against every peg, the side rails and the slot dividers, so the chip never
## passes through anything; contacts are picked from seeded candidates, so every client plays the
## same flight for the same drop. The money never depends on this: the slot is fixed before.

const GRAVITY: float = 9.8
## Contact distance tolerance (m) when checking for overlap.
const EPS: float = 0.001
## Samples per arc when checking for overlap.
const SAMPLES: int = 32

## One arc: starts at `p` with velocity `v` at natural time `t0`, lasts `dur`. `peg` is the
## (row, column) the arc ends on, or (-1, -1) for the slot floor / settling hops.
class Arc:
	var t0: float
	var dur: float
	var p: Vector2
	var v: Vector2
	var peg: Vector2i = Vector2i(-1, -1)
	var spin0: float
	var spin_rate: float

	func pos(dt: float) -> Vector2:
		return p + v * dt + Vector2(0.0, -0.5 * GRAVITY * dt * dt)

	func vel(dt: float) -> Vector2:
		return v + Vector2(0.0, -GRAVITY * dt)


var arcs: Array[Arc] = []
## Natural time (s) the chip first touches the slot floor.
var land_time: float = 0.0
## Natural time (s) the chip is at rest in the slot.
var rest_time: float = 0.0
var slot: int = 0
## Worst overlap (m) of the chip with any peg, rail or divider over the whole flight (0 = clean).
var worst_overlap: float = 0.0


## Builds the flight for `path` (rows + 1 positions in slot units, last one = the slot).
static func build(path: Array[float], rng: SeededRng) -> PlinkoFlight:
	var f := PlinkoFlight.new()
	f._build(path, rng)
	return f


## Position (board-local x, y) at natural time `t`.
func position_at(t: float) -> Vector2:
	var a: Arc = _arc_at(t)
	return a.pos(clampf(t - a.t0, 0.0, a.dur))


## Spin angle (radians, about the board normal) at natural time `t`.
func spin_at(t: float) -> float:
	var a: Arc = _arc_at(t)
	return a.spin0 + a.spin_rate * clampf(t - a.t0, 0.0, a.dur)


## Index of the arc playing at natural time `t`.
func arc_index(t: float) -> int:
	for i: int in arcs.size():
		if t < arcs[i].t0 + arcs[i].dur:
			return i
	return arcs.size() - 1


func _arc_at(t: float) -> Arc:
	return arcs[arc_index(t)]


func _build(path: Array[float], rng: SeededRng) -> void:
	var rows: int = path.size() - 1
	slot = int(round(path[rows]))
	var d: float = PlinkoStation.CHIP_R + PlinkoStation.PEG_RADIUS
	# Side each row's contact sits on = the way the path goes next.
	var sides: Array[float] = []
	for r: int in rows:
		sides.append(signf(path[r + 1] - path[r]))
	# 1. Out of the funnel straight down onto the first peg, a little off its crown.
	var peg0: Vector2 = PlinkoStation.peg_pos(0, PlinkoStation.peg_col(0, path[0]))
	var th0: float = deg_to_rad(rng.range_float(14.0, 30.0))
	var c: Vector2 = peg0 + d * Vector2(sin(th0) * sides[0], cos(th0))
	var start := Vector2(c.x, PlinkoStation.entry_y())
	var t: float = 0.0
	var spin: float = rng.range_float(0.0, TAU)
	var a0 := Arc.new()
	a0.t0 = 0.0
	a0.p = start
	a0.v = Vector2.ZERO
	a0.dur = sqrt(2.0 * (start.y - c.y) / GRAVITY)
	a0.peg = Vector2i(0, PlinkoStation.peg_col(0, path[0]))
	a0.spin0 = spin
	a0.spin_rate = rng.range_float(-2.0, 2.0)
	arcs.append(a0)
	t += a0.dur
	spin += a0.spin_rate * a0.dur
	var v_in: Vector2 = a0.vel(a0.dur)
	var from_peg: Vector2 = peg0
	# 2. Peg to peg, then the last peg into the slot.
	for r: int in rows:
		var s: float = sides[r]
		var last: bool = r == rows - 1
		var hops: Array[Dictionary] = []
		if not last:
			var target_peg := Vector2i(r + 1, PlinkoStation.peg_col(r + 1, path[r + 1]))
			var peg_c: Vector2 = PlinkoStation.peg_pos(r + 1, target_peg.y)
			var next_s: float = sides[r + 1]
			# The chip passes outside the peg it left and comes down on the next one's crown:
			# just past the top keeps it going the same way, just short of it turns it back.
			var lo: float = 4.0 if next_s == s else 1.5
			var hi: float = 34.0 if next_s == s else 13.0
			var to_peg: Callable = func(k: float) -> Vector2:
				var th: float = deg_to_rad(lerpf(lo, hi, k))
				return peg_c + d * Vector2(sin(th) * next_s, cos(th))
			hops.append(_search(c, from_peg, v_in, s, to_peg, 0.07, target_peg, false, rng))
			from_peg = peg_c
		else:
			var sx: float = PlinkoStation.slot_x(slot)
			var to_floor: Callable = func(k: float) -> Vector2:
				return Vector2(sx + (k - 0.5) * 0.05, PlinkoStation.FLOOR_Y + PlinkoStation.CHIP_R)
			var direct: Dictionary = _search(c, from_peg, v_in, s, to_floor, 0.09, Vector2i(-1, -1), true, rng)
			if float(direct["bad"]) <= EPS:
				hops.append(direct)
			else:
				# Too close to the crown to clear it: a little hop onto the peg's shoulder first,
				# then it rolls off into the slot.
				var pc: Vector2 = from_peg
				var to_shoulder: Callable = func(k: float) -> Vector2:
					var th: float = deg_to_rad(lerpf(52.0, 74.0, k))
					return pc + d * Vector2(sin(th) * s, cos(th))
				var a1: Dictionary = _search(c, from_peg, v_in, s, to_shoulder, 0.05, Vector2i(-1, -1), false, rng)
				var arc1: Arc = a1["arc"]
				var a2: Dictionary = _search(a1["end"], from_peg, arc1.vel(arc1.dur), s, to_floor, 0.03, Vector2i(-1, -1), true, rng)
				if maxf(a1["bad"], a2["bad"]) < float(direct["bad"]):
					hops.append(a1)
					hops.append(a2)
				else:
					hops.append(direct)
		for hop: Dictionary in hops:
			var arc_r: Arc = hop["arc"]
			worst_overlap = maxf(worst_overlap, maxf(float(hop["bad"]) - EPS, 0.0))
			arc_r.t0 = t
			arc_r.peg = hop["peg"]
			arc_r.spin0 = spin
			arc_r.spin_rate = -arc_r.v.x / PlinkoStation.CHIP_R * rng.range_float(0.35, 0.7)
			arcs.append(arc_r)
			t += arc_r.dur
			spin += arc_r.spin_rate * arc_r.dur
			v_in = arc_r.vel(arc_r.dur)
			c = hop["end"]
	land_time = t
	# 3. Two little hops in the slot, sliding to its middle, then rest.
	var sx2: float = PlinkoStation.slot_x(slot)
	var h0: float = clampf(v_in.y * v_in.y / (2.0 * GRAVITY) * 0.08, 0.015, 0.07)
	for k: int in 2:
		var hk: float = h0 * pow(0.35, k)
		var end2 := Vector2(lerpf(c.x, sx2, 0.6 if k == 0 else 1.0), c.y)
		var hop := _arc(c, end2, hk)
		hop.t0 = t
		hop.spin0 = spin
		hop.spin_rate = -hop.v.x / PlinkoStation.CHIP_R * 0.5
		arcs.append(hop)
		t += hop.dur
		spin += hop.spin_rate * hop.dur
		c = end2
	var rest := Arc.new()
	rest.t0 = t
	rest.dur = 0.001
	rest.p = c
	rest.v = Vector2.ZERO
	rest.spin0 = spin
	arcs.append(rest)
	rest_time = t


## Best arc from contact `c` (on `from_peg`) going toward side `s` to `end_fn(k)` (k in 0..1),
## peaking up to `h_max` above `c`: seeded tries first (variety), then a fixed grid so a clean
## arc is always found. Returns {arc, end, bad, peg}.
static func _search(c: Vector2, from_peg: Vector2, v_in: Vector2, s: float, end_fn: Callable, h_max: float, target: Vector2i, to_floor: bool, rng: SeededRng) -> Dictionary:
	var best: Dictionary = {}
	var best_bad: float = INF
	var tries: Array[Vector2] = []
	for i: int in 24:
		tries.append(Vector2(rng.range_float(0.0, 1.0), rng.range_float(0.0, 1.0)))
	for i: int in 7:
		for j: int in 7:
			tries.append(Vector2(i / 6.0, j / 6.0))
	for tr: Vector2 in tries:
		var end: Vector2 = end_fn.call(tr.x)
		var arc := _arc(c, end, lerpf(0.004, h_max, tr.y * tr.y))
		if arc == null or arc.v.x * s < 0.05:
			continue
		if (c - from_peg).dot(arc.v) <= 0.0:
			continue  # leaves the peg it is touching, never back into it
		var bad: float = _overlap(arc, target, from_peg, to_floor)
		var calm: bool = arc.v.length() <= maxf(v_in.length() * 0.8, 0.45)  # pegs soak up some speed
		if bad <= EPS and calm:
			return {"arc": arc, "end": end, "bad": bad, "peg": target}
		if bad < best_bad or best.is_empty():
			best_bad = bad
			best = {"arc": arc, "end": end, "bad": bad, "peg": target}
	if best.is_empty():  # nothing even leaves the peg cleanly: drop straight off it
		var e: Vector2 = end_fn.call(0.5)
		var arc0 := _arc(c, e, 0.004)
		best = {"arc": arc0, "end": e, "bad": _overlap(arc0, target, from_peg, to_floor), "peg": target}
	return best


## A ballistic arc from `a` to `b` peaking `h` metres above `a` (or at once if b is higher).
static func _arc(a: Vector2, b: Vector2, h: float) -> Arc:
	var dy: float = b.y - a.y
	var peak: float = maxf(h, dy + 0.002)
	var vy: float = sqrt(2.0 * GRAVITY * peak)
	var disc: float = vy * vy - 2.0 * GRAVITY * dy
	if disc < 0.0:
		return null
	var dur: float = (vy + sqrt(disc)) / GRAVITY
	if dur <= 0.0001:
		return null
	var arc := Arc.new()
	arc.p = a
	arc.v = Vector2((b.x - a.x) / dur, vy)
	arc.dur = dur
	return arc


## Worst overlap of `arc` with the board: every peg (the target only before the touch, the source
## only after leaving it), the rails and, low down, the slot dividers.
static func _overlap(arc: Arc, target: Vector2i, from_peg: Vector2, to_floor: bool) -> float:
	var d: float = PlinkoStation.CHIP_R + PlinkoStation.PEG_RADIUS
	var worst: float = 0.0
	var rail: float = PlinkoStation.BOARD_W * 0.5 - PlinkoStation.CHIP_R
	var half_w: float = PlinkoStation.slot_w() * 0.5
	for i: int in range(1, SAMPLES):
		var dt: float = arc.dur * float(i) / SAMPLES
		var q: Vector2 = arc.pos(dt)
		worst = maxf(worst, absf(q.x) - rail)
		var row_f: float = (PlinkoStation.top_y() - PlinkoStation.ROW_TOP_GAP - q.y) / PlinkoStation.row_h()
		for r: int in range(maxi(0, floori(row_f) - 1), mini(PlinkoStation.ROWS, ceili(row_f) + 2)):
			var n: int = PlinkoStation.peg_count(r)
			var c0: int = int(round(q.x / PlinkoStation.slot_w() + (n - 1) * 0.5))
			for col: int in range(maxi(c0 - 1, 0), mini(c0 + 2, n)):
				var pp: Vector2 = PlinkoStation.peg_pos(r, col)
				var lim: float = d
				if Vector2i(r, col) == target or pp.is_equal_approx(from_peg):
					lim = d - 0.002  # the touch itself: the arc ends / starts exactly at d
				worst = maxf(worst, lim - q.distance_to(pp))
		# Slot dividers: thin walls at the slot edges up to DIV_TOP.
		if q.y < PlinkoStation.DIV_TOP + PlinkoStation.CHIP_R:
			var s: int = clampi(int(round(q.x / PlinkoStation.slot_w() + (PlinkoStation.SLOTS - 1) * 0.5)), 0, PlinkoStation.SLOTS - 1)
			for e: float in [PlinkoStation.slot_x(s) - half_w, PlinkoStation.slot_x(s) + half_w]:
				var dx: float = absf(q.x - e) - PlinkoStation.DIV_T * 0.5
				var dyy: float = q.y - PlinkoStation.DIV_TOP
				var dist: float = dx if dyy <= 0.0 else Vector2(maxf(dx, 0.0), dyy).length()
				worst = maxf(worst, PlinkoStation.CHIP_R - dist)
	if to_floor:
		var e2: Vector2 = arc.pos(arc.dur)
		worst = maxf(worst, absf(e2.x) - rail)
	return worst
