class_name ChipTowers
extends RefCounted
## The "towers" layout of the climb room (`ClimbRoom`, Jackpot Climb): a jump-and-run up a wedding
## cake of giant casino chips. Three **tiers** (giant chip plateaus, each standing on the one below)
## and the **jackpot stack** on top, whose gold pad (the finish) waits under the JACKPOT sign at
## `TOP_Y`. Every tier top is a **checkpoint** with a flag.
##
## The climb is pure data (`stacks()`, local to the room's origin), computed once and the same for
## everyone (no randomness: every client builds the same tower the server judges):
## - Four **segments**: segment `s` climbs from level `s` (0 the floor, 1..3 the tiers) to level
##   `s + 1` (the next tier, or the pad) on chip stacks standing on level `s`, winding round level
##   `s + 1`'s column at `LANE_OFF` outside it. It starts on the side of the previous flag and ends
##   half a turn round on the opposite side, where the next flag stands (north, south, north; the
##   pad is entered from the south, facing the gallery).
## - Two **lanes** per segment, one round each side of the column (`side` -1 / +1): they fork at
##   the flag and rejoin on the next tier. One lane is **steady** (short hops, `GAPS`, smaller
##   rises, narrower stacks higher up), the other is **bold** (`BOLD_SIDE`: fewer stacks and
##   `WIDE_COUNT` wide gaps from `WIDE_GAPS` that need a running jump, so it is shorter). The last
##   segment round the jackpot stack is two steady lanes of narrow stacks.
## - Gaps are air between rims; each lane's hop pattern is scaled so the lane exactly fills its
##   half turn. Rises (the floor/tier to the first stack, stack to stack, the last stack onto the
##   next tier) follow `RISES` scaled so each lane climbs exactly its segment; a wide jump only
##   rises `WIDE_RISE`.
## - Falling off a stack lands on the tier it stands on (the checkpoint) or further down; the
##   server sends anyone who drops below their last checkpoint back to its flag
##   (`JackpotClimbLogic`).
##
## `build(root, brass, ceiling_y)` makes the nodes in the room's local frame: collision cylinders
## (`ClimbKit.column`) for tiers, stacks and the jackpot stack, all dressed in chips (`chip_mesh`:
## flush edge spots, a bevelled rim, an inlay ring and spots on both faces; multimeshes per colour),
## the flags (`Flag1`..`Flag3`, each with a `Cloth` the stage lights up), the gold pad and its rail
## open to the south, the JACKPOT sign (warm marquee bulbs, `BulbsA`/`BulbsB` for the stage to chase,
## `NameFront`/`NameBack` labels it fills) and the safety net.

## Tower centre (local z) and the towers hall (wider and deeper than the board's).
const CENTER_Z: float = -12.5
const HALL_HALF_X: float = 12.0
const FAR_Z: float = -25.0
## The tiers bottom to top: column radius and top height. Tier k stands on tier k - 1.
const TIER_R: Array[float] = [9.2, 6.9, 4.6]
const TIER_Y: Array[float] = [8.5, 16.0, 21.5]
const PAD_R: float = 2.3
const TOP_Y: float = 26.0
const SEGMENTS: int = 4
## Lane centre line: this far outside the column it winds round (0.5 m of air for a full stack).
const LANE_OFF: float = 1.2
const CHIP_R: float = 0.7
const NARROW_R: float = 0.58
## Air between rims on the steady hops (cycled, then scaled to fill the lane: about 0.6-1.3 m).
const GAPS: Array[float] = [0.75, 0.95, 0.6, 1.05, 0.8, 1.15, 0.7, 0.9]
## The wide gaps of the bold lanes (a running jump; a walking jump reaches ~3.5 m).
const WIDE_GAPS: Array[float] = [2.7, 2.9, 2.6, 2.8]
## Rise weights per jump (cycled), and the rise of a wide jump.
const RISES: Array[float] = [1.0, 0.85, 1.12, 0.94, 1.08, 0.9]
const WIDE_RISE: float = 0.3
## Per segment: the bold lane's side (0: none) and how many wide gaps it has.
const BOLD_SIDE: Array[int] = [-1, 1, -1, 0]
const WIDE_COUNT: Array[int] = [2, 1, 1, 0]
## Radial wobble of the stacks off the lane line (cycled; the first and last stay on it).
const WOBBLE: Array[float] = [0.0, 0.1, -0.08, 0.05, -0.1, 0.08, -0.04]
## Air kept free on each side of a flag before a lane's first stack (the respawn spot), at the
## apron's end of the floor segment, and between the two lanes' last stacks.
const START_FREE: float = 1.3
const FLOOR_FREE: float = 0.6
const END_AIR: float = 0.6
## Gaps up to this are a normal hop; wider ones need a running jump (the layout test counts them).
const NORMAL_JUMP: float = 1.5
## The jump envelope the route must stay inside (the bean jumps 1.1 m).
const MAX_GAP: float = 3.0
const MAX_RISE: float = 0.9
## Checkpoint reach: on a tier's top (this far past its rim, from this far below its top).
const CHECK_RIM: float = 0.25
const CHECK_BELOW: float = 0.35
## Half size of the finish box over the pad (inside the pad's disc).
const FINISH_HALF: float = 1.6
## Chip thickness the stacks are built from (rounded per stack to fit its height); giant chips are
## `GIANT_T` of their radius thick.
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

static var _stacks: Array[Dictionary] = []
## Vector2i(segment, side) → stack indices up that lane.
static var _lanes: Dictionary = {}
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


## Where segment `seg` starts (its flag; angle round the centre, 0 = +z toward the apron). It ends
## half a turn round, where the next segment starts.
static func start_angle(seg: int) -> float:
	return 0.0 if seg % 2 == 0 else PI


## Flat outward direction at angle `a` round the centre.
static func dir(a: float) -> Vector3:
	return Vector3(sin(a), 0.0, cos(a))


## Every stack, local: {pos: centre of the top face, r, base_y, seg, side, i (index up its lane),
## wide (the gap before it is a wide one)}. Cached: don't modify.
static func stacks() -> Array[Dictionary]:
	if _stacks.is_empty():
		_make()
	return _stacks


## Stack indices up one lane, bottom to top (`side` -1 or +1).
static func lane(seg: int, side: int) -> Array[int]:
	stacks()
	var out: Array[int] = []
	out.assign(_lanes.get(Vector2i(seg, side), []))
	return out


## The ledges of one way up, in order: for each segment the lane on `sides[seg]` then the level it
## climbs onto ({pos, r, kind: "stack" / "tier" / "pad", index (stack) or level}). A tier's `pos` is
## the centre of its top.
static func route(sides: Array[int] = [-1, -1, -1, -1]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var all: Array[Dictionary] = stacks()
	for seg: int in SEGMENTS:
		for i: int in lane(seg, sides[seg] if seg < sides.size() else -1):
			out.append({"pos": all[i]["pos"], "r": all[i]["r"], "kind": "stack", "index": i})
		var k: int = seg + 1
		out.append({"pos": Vector3(0.0, level_y(k), CENTER_Z), "r": level_r(k), "kind": "pad" if k == SEGMENTS else "tier", "level": k})
	return out


## The pad's centre (top face), local.
static func pad_center() -> Vector3:
	return Vector3(0.0, TOP_Y, CENTER_Z)


## The checkpoints (the tiers' tops), bottom to top: {index (1..3), y, r (the tier's radius),
## angle, flag (local foot of the pole), spots (local respawn spots round the flag)}.
static func checkpoints() -> Array[Dictionary]:
	if _checkpoints.is_empty():
		for k: int in range(1, SEGMENTS):
			var a: float = start_angle(k)
			var inner: float = level_r(k + 1)
			var y: float = level_y(k)
			var c := Vector3(0.0, y, CENTER_Z)
			var spots: Array[Vector3] = []
			var rs: float = inner + LANE_OFF + 0.1
			for arc: float in [0.0, -0.8, 0.8]:
				spots.append(c + dir(a + arc / rs) * rs)
			_checkpoints.append({"index": k, "y": y, "r": level_r(k), "angle": a, "flag": c + dir(a) * (inner + 0.5), "spots": spots})
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
	return dir(start_angle(SEGMENTS))


static func _make() -> void:
	_stacks.clear()
	_lanes.clear()
	for seg: int in SEGMENTS:
		for side: int in [-1, 1]:
			_make_lane(seg, side)


## One lane: picks the stack count whose hop pattern fits the half turn best, places the stacks by
## arc length and sets their heights.
static func _make_lane(seg: int, side: int) -> void:
	var rho: float = level_r(seg + 1) + LANE_OFF
	var y0: float = level_y(seg)
	var y1: float = level_y(seg + 1)
	var bold: bool = BOLD_SIDE[seg] == side
	var free0: float = FLOOR_FREE if seg == 0 else START_FREE
	var best_n: int = -1
	var best_k: float = INF
	for n: int in range(3, 48):
		var k: float = _fit(seg, side, bold, n, rho, free0)
		if k > 0.0 and absf(k - 1.0) < absf(best_k - 1.0):
			best_k = k
			best_n = n
	var n: int = best_n
	var radii: Array[float] = _radii(seg, bold, n)
	var wide_at: Array[int] = _wide_slots(n, WIDE_COUNT[seg] if bold else 0)
	# Heights: jump j lands on stack j (j = n: onto the next level).
	var weights: Array[float] = []
	var total_w: float = 0.0
	for j: int in n + 1:
		var w: float = 0.0 if j in wide_at else RISES[(j + seg * 2 + (side + 1)) % RISES.size()]
		weights.append(w)
		total_w += w
	var scale: float = (y1 - y0 - WIDE_RISE * float(wide_at.size())) / total_w
	var s: float = (free0 + radii[0])
	var y: float = y0
	var idx: Array[int] = []
	for i: int in n:
		if i > 0:
			var gap: float = WIDE_GAPS[(seg + i) % WIDE_GAPS.size()] if i in wide_at else GAPS[(i + seg * 3 + (side + 1)) % GAPS.size()] * best_k
			s += radii[i - 1] + gap + radii[i]
		y += WIDE_RISE if i in wide_at else weights[i] * scale
		var wob: float = 0.0 if i == 0 or i == n - 1 else WOBBLE[(i + seg) % WOBBLE.size()]
		var a: float = start_angle(seg) + float(side) * s / rho
		var p: Vector3 = dir(a) * (rho + wob)
		idx.append(_stacks.size())
		_stacks.append({"pos": Vector3(p.x, y, CENTER_Z + p.z), "r": radii[i], "base_y": y0, "seg": seg, "side": side, "i": i, "wide": i in wide_at})
	_lanes[Vector2i(seg, side)] = idx


## The scale of the steady hops that makes `n` stacks fill the lane exactly (<= 0: they don't fit).
static func _fit(seg: int, side: int, bold: bool, n: int, rho: float, free0: float) -> float:
	var radii: Array[float] = _radii(seg, bold, n)
	var wide_at: Array[int] = _wide_slots(n, WIDE_COUNT[seg] if bold else 0)
	var arc: float = rho * PI - (free0 + radii[0]) - (radii[n - 1] + END_AIR * 0.5)
	var fixed: float = 0.0
	var hops: float = 0.0
	for i: int in range(1, n):
		fixed += radii[i - 1] + radii[i]
		if i in wide_at:
			fixed += WIDE_GAPS[(seg + i) % WIDE_GAPS.size()]
		else:
			hops += GAPS[(i + seg * 3 + (side + 1)) % GAPS.size()]
	if hops <= 0.0 or arc <= fixed:
		return -1.0
	return (arc - fixed) / hops


## Stack radii up a lane: narrow round the jackpot stack, every third narrow on the steady lanes
## above the floor, full size on the bold lanes (they land the wide jumps).
static func _radii(seg: int, bold: bool, n: int) -> Array[float]:
	var out: Array[float] = []
	for i: int in n:
		var narrow: bool = seg == SEGMENTS - 1 or (not bold and seg >= 1 and i % 3 == 2)
		out.append(NARROW_R if narrow else CHIP_R)
	return out


## Which stacks of `n` are reached by a wide jump (spread evenly, never the first).
static func _wide_slots(n: int, count: int) -> Array[int]:
	var out: Array[int] = []
	for j: int in count:
		var i: int = clampi(roundi(float(n) * float(j + 1) / float(count + 1)), 1, n - 1)
		if i not in out:
			out.append(i)
	return out


# --- Build --------------------------------------------------------------------------------------

## Builds the tiers, the stacks, the pad, the flags, the sign and the net under the room's `root`
## (local frame). `ceiling_y` is where the sign's chains hang from.
static func build(root: Node3D, brass: Material, ceiling_y: float) -> Node3D:
	var n := Node3D.new()
	n.name = "ChipTowers"
	root.add_child(n)
	var chips := _ChipBatch.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7311
	for k: int in range(1, SEGMENTS):
		_tier(n, chips, k)
	var i: int = 0
	for s: Dictionary in stacks():
		var top: Vector3 = s["pos"]
		var r: float = s["r"]
		var base: float = s["base_y"]
		ClimbKit.column(n, r, top.y - base, Vector3(top.x, base, top.z), "Stack%d" % i)
		var seg: int = int(s["seg"])
		var from: Vector3 = Vector3(0.0, base, CENTER_Z) + dir(start_angle(seg)) * (level_r(seg + 1) + LANE_OFF)
		if int(s["i"]) > 0:
			from = stacks()[i - 1]["pos"]
		_dress_stack(n, chips, rng, top, r, base, from)
		i += 1
	_pad(n, chips, brass)
	chips.commit(n)
	for cp: Dictionary in checkpoints():
		_flag(n, cp, brass)
	_sign(n, brass, ceiling_y)
	_net(n, brass)
	_lights(n)
	return n


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


## Chips up a stack: runs of 3-7 chips of a colour with a hair of jitter, the top chip's
## denomination lying on its face, reading from the stack you jump from.
static func _dress_stack(parent: Node3D, chips: _ChipBatch, rng: RandomNumberGenerator, top: Vector3, r: float, base: float, from: Vector3) -> void:
	var h: float = top.y - base
	var count: int = maxi(roundi(h / CHIP_T), 2)
	var t: float = h / float(count)
	var colors: Array[Color] = ChipStack.TIER_COLORS
	var ci: int = rng.randi_range(0, colors.size() - 1)
	var run: int = rng.randi_range(3, 7)
	for k: int in count:
		run -= 1
		if run < 0 or k == count - 1:
			ci = (ci + rng.randi_range(1, colors.size() - 1)) % colors.size()
			run = rng.randi_range(3, 7)
		var off := Vector2(rng.randf_range(-0.012, 0.012), rng.randf_range(-0.012, 0.012)) if k < count - 1 else Vector2.ZERO
		chips.chip(Vector3(top.x + off.x, base + t * (float(k) + 0.5), top.z + off.y), r, t, rng.randf() * TAU, colors[ci], 6)
	chips.core(Vector3(top.x, base, top.z), r * 0.97, h - t * 0.5)
	var mats: Array = ChipStack.materials_for(colors[ci])
	var l := Label3D.new()
	l.text = DENOMS[ci]
	l.font = Vfx.font()
	l.font_size = 96
	l.pixel_size = (0.0042 if DENOMS[ci].length() > 2 else 0.0052) * r / CHIP_R
	l.modulate = (mats[2] as StandardMaterial3D).albedo_color
	l.outline_size = 0
	l.shaded = true
	l.double_sided = false
	var d: Vector3 = top - from
	l.rotation = Vector3(-PI * 0.5, atan2(-d.x, -d.z), 0.0)
	l.position = top + Vector3(0, 0.006, 0)
	parent.add_child(l)


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
	tm.inner_radius = 0.95
	tm.outer_radius = 1.08
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
