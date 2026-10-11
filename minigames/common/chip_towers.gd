class_name ChipTowers
extends RefCounted
## The "towers" layout of the climb room (`ClimbRoom`, Jackpot Climb): a staggered spiral of giant
## casino-chip stacks winding inward and upward round the central **jackpot stack**, whose golden
## top (the finish pad) waits under the JACKPOT sign at `TOP_Y`.
##
## The route is pure data (`stacks()`, local to the room's origin), computed once:
## - Stack centres sit on an inward Archimedean spiral round (0, `CENTER_Z`): radius `R0` at the
##   start (the stack nearest the apron) shrinking by `DROP` per turn. Consecutive stacks are a
##   chord apart that leaves exactly `GAPS[i]` metres of air between their rims (1.6–2.1 m), so
##   every jump is a real jump; the spiral stops once the next stack would crowd the pad.
## - Each step up (from the floor onto stack 0, stack to stack, the last stack onto the pad) is a
##   `RISES[i]` pattern value scaled so the steps add up to exactly `TOP_Y` (0.66–0.81 m each,
##   under the bean's 1.1 m jump). Turns lie `DROP` metres apart (about 1 m of air between rims)
##   and one turn higher is metres higher, so nothing short-cuts the spiral, while a bean knocked
##   off usually lands on the turn below instead of the floor.
## - From stack `FIRST_NARROW` on every third stack is narrower (`NARROW_R`), and a few stacks are
##   built crooked (`CROOKED`, a visual lean: the collision stays a straight cylinder).
##
## `build(root, brass)` makes the nodes in the room's local frame: a collision cylinder per stack
## (`ClimbKit.column`) dressed in chips (multimeshes: faces by colour, the cream or charcoal edge
## inserts, a dark core showing between chips), the jackpot stack and its gold pad with a rail
## open toward the last stack, the JACKPOT sign (warm marquee bulbs, `BulbsA`/`BulbsB` for the
## stage to chase, `NameFront`/`NameBack` labels it fills) hung from the ceiling, and the safety
## net over the floor.

const CENTER_Z: float = -12.0
const R0: float = 8.2
const DROP: float = 2.5
const CHIP_R: float = 0.75
const NARROW_R: float = 0.6
const FIRST_NARROW: int = 11
const PAD_R: float = 2.0
const TOP_Y: float = 16.0
## Air between consecutive rims (m) and the rise of each step, cycled along the route.
const GAPS: Array[float] = [1.7, 1.9, 1.6, 2.0, 1.8, 2.1, 1.7, 1.9]
const RISES: Array[float] = [0.72, 0.8, 0.68, 0.84, 0.76, 0.7, 0.82, 0.74]
## The spiral ends when the next stack would leave less air than this to the pad.
const MIN_PAD_GAP: float = 1.0
## The jump envelope the route must stay inside (the layout test checks it).
const MAX_GAP: float = 2.2
const MAX_RISE: float = 0.9
const CROOKED: Array[int] = [7, 13, 18]
## The far wall (local z).
const FAR_Z: float = CENTER_Z - R0 - 3.2
## Half size of the finish box over the pad (inside the pad's disc).
const FINISH_HALF: float = 1.45
## Chip thickness the stacks are built from (rounded per stack to fit its height).
const CHIP_T: float = 0.24
const PAD_CHIP_T: float = 0.5
const SIGN_Y: float = 4.6
const SIGN_W: float = 7.6
const SIGN_H: float = 2.7
## Top-chip denominations by chip colour (`ChipStack.TIER_COLORS` order).
const DENOMS: Array[String] = ["25", "100", "500", "1K", "5K"]

static var _stacks: Array[Dictionary] = []


# --- Pure data ------------------------------------------------------------------------------

## The route's stacks, bottom to top, local: {pos: centre of the top face, r: radius, crooked}.
## Cached: don't modify.
static func stacks() -> Array[Dictionary]:
	if _stacks.is_empty():
		_stacks = _make()
	return _stacks


## The pad's centre (top face), local.
static func pad_center() -> Vector3:
	return Vector3(0.0, TOP_Y, CENTER_Z)


## Every ledge of the climb in order, local: the stacks, then the pad ({pos, r}).
static func route() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s: Dictionary in stacks():
		out.append({"pos": s["pos"], "r": s["r"]})
	out.append({"pos": pad_center(), "r": PAD_R})
	return out


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


## Direction (flat, local) from the pad's centre toward the last stack: the rail's opening.
static func entry_dir() -> Vector3:
	var last: Vector3 = stacks()[stacks().size() - 1]["pos"]
	var d: Vector3 = last - pad_center()
	d.y = 0.0
	return d.normalized()


static func _spiral(t: float) -> Vector3:
	var r: float = R0 - DROP * t / TAU
	return Vector3(r * sin(t), 0.0, CENTER_Z + r * cos(t))


static func _make() -> Array[Dictionary]:
	var ts: Array[float] = [0.0]
	var rs: Array[float] = [CHIP_R]
	while ts.size() < 64:
		var n: int = ts.size()
		var rad: float = NARROW_R if n >= FIRST_NARROW and n % 3 == 0 else CHIP_R
		var chord: float = GAPS[n % GAPS.size()] + rs[n - 1] + rad
		var from: Vector3 = _spiral(ts[n - 1])
		var a: float = ts[n - 1]
		var b: float = a + 3.0
		for _k: int in 48:
			var m: float = (a + b) * 0.5
			if _spiral(m).distance_to(from) < chord:
				a = m
			else:
				b = m
		var t: float = (a + b) * 0.5
		if R0 - DROP * t / TAU - rad - PAD_R < MIN_PAD_GAP:
			break
		ts.append(t)
		rs.append(rad)
	var total: float = 0.0
	for i: int in ts.size() + 1:
		total += RISES[i % RISES.size()]
	var k: float = TOP_Y / total
	var out: Array[Dictionary] = []
	var y: float = 0.0
	for i: int in ts.size():
		y += RISES[i % RISES.size()] * k
		var p: Vector3 = _spiral(ts[i])
		out.append({"pos": Vector3(p.x, y, p.z), "r": rs[i], "crooked": i in CROOKED})
	return out


# --- Build --------------------------------------------------------------------------------------

## Builds the towers, the pad, the sign and the net under the room's `root` (local frame).
## `ceiling_y` is where the sign's chains hang from.
static func build(root: Node3D, brass: Material, ceiling_y: float) -> Node3D:
	var n := Node3D.new()
	n.name = "ChipTowers"
	root.add_child(n)
	var chips := _ChipBatch.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7311
	var i: int = 0
	for s: Dictionary in stacks():
		var top: Vector3 = s["pos"]
		var r: float = s["r"]
		ClimbKit.column(n, r, top.y, Vector3(top.x, 0.0, top.z), "Stack%d" % i)
		_dress_stack(n, chips, rng, top, r, bool(s["crooked"]))
		i += 1
	_pad(n, chips, brass)
	chips.commit(n)
	_sign(n, brass, ceiling_y)
	_net(n, brass)
	_lights(n)
	return n


## Chips up a stack: runs of 3–7 chips of a colour, a little jitter (a lean when crooked), the
## top chip with an inlay ring and its denomination lying on it.
static func _dress_stack(parent: Node3D, chips: _ChipBatch, rng: RandomNumberGenerator, top: Vector3, r: float, crooked: bool) -> void:
	var count: int = maxi(roundi(top.y / CHIP_T), 2)
	var t: float = top.y / float(count)
	var colors: Array[Color] = ChipStack.TIER_COLORS
	var ci: int = rng.randi_range(0, colors.size() - 1)
	var run: int = rng.randi_range(3, 7)
	var lean := Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
	for k: int in count:
		run -= 1
		if run < 0 or k == count - 1:
			ci = (ci + rng.randi_range(1, colors.size() - 1)) % colors.size()
			run = rng.randi_range(3, 7)
		var f: float = float(k) / float(count)
		var off := Vector2(rng.randf_range(-0.02, 0.02), rng.randf_range(-0.02, 0.02))
		if crooked:
			off += lean * 0.07 * sin(f * PI * 1.5)
		var c := Vector3(top.x + off.x, t * (float(k) + 0.5), top.z + off.y)
		chips.chip(c, r, t, rng.randf() * TAU, colors[ci], 6 if r >= CHIP_R else 5)
	chips.core(Vector3(top.x, top.y * 0.5, top.z), r * 0.96, top.y)
	var top_color: Color = colors[ci]
	var mats: Array = ChipStack.materials_for(top_color)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = r * 0.56
	tm.outer_radius = r * 0.66
	tm.rings = 28
	tm.ring_segments = 4
	ring.mesh = tm
	ring.material_override = mats[2]
	ring.scale = Vector3(1.0, 0.08, 1.0)
	ring.position = top + Vector3(0, 0.002, 0)
	parent.add_child(ring)
	var l := Label3D.new()
	l.text = DENOMS[ci]
	l.font = Vfx.font()
	l.font_size = 96
	l.pixel_size = 0.0055 * r / CHIP_R
	l.modulate = mats[2].albedo_color
	l.outline_size = 0
	l.shaded = true
	l.double_sided = false
	l.rotation = Vector3(-PI * 0.5, atan2(-top.x, -(top.z - CENTER_Z)), 0.0)
	l.position = top + Vector3(0, 0.012, 0)
	parent.add_child(l)


## The jackpot stack: big burgundy and gold chips up to the gold pad, a glowing rim, JACKPOT
## lettered round its top and a gold rail with an opening toward the last stack.
static func _pad(parent: Node3D, chips: _ChipBatch, brass: Material) -> void:
	var c: Vector3 = pad_center()
	ClimbKit.column(parent, PAD_R, TOP_Y, Vector3(c.x, 0.0, c.z), "JackpotStack")
	var count: int = roundi(TOP_Y / PAD_CHIP_T)
	var t: float = TOP_Y / float(count)
	for k: int in count:
		var col: Color = Palette.VIP_GOLD if k % 4 == 3 else Palette.VIP_BURGUNDY
		chips.chip(Vector3(c.x, t * (float(k) + 0.5), c.z), PAD_R, t, float(k) * 0.37, col, 12)
	chips.core(Vector3(c.x, TOP_Y * 0.5, c.z), PAD_R * 0.97, TOP_Y)
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Palette.VIP_GOLD
	gold.metallic = 0.85
	gold.roughness = 0.25
	gold.emission_enabled = true
	gold.emission = Palette.WARM_GOLD
	gold.emission_energy_multiplier = 0.25
	var face: MeshInstance3D = ParlorRoom._cyl(parent, PAD_R - 0.04, 0.04, c + Vector3(0, 0.0, 0), gold, 40)
	face.name = "FinishPad"
	var cream: StandardMaterial3D = GreyboxKit.material(Palette.CREAM, 0.0, 0.5)
	var inlay := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.25
	tm.outer_radius = 1.4
	tm.rings = 40
	tm.ring_segments = 4
	inlay.mesh = tm
	inlay.material_override = cream
	inlay.scale = Vector3(1.0, 0.1, 1.0)
	inlay.position = c + Vector3(0, 0.025, 0)
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
		l.position = c + Vector3(sin(a) * (PAD_R + 0.07), -t * 0.5, cos(a) * (PAD_R + 0.07))
		l.rotation.y = a
		parent.add_child(l)
	# The rail: gold posts and a top bar, open toward the last stack.
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
	var x0: float = -ClimbRoom.HALL_HALF_X + 0.4
	var x1: float = ClimbRoom.HALL_HALF_X - 0.4
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


static func _lights(parent: Node3D) -> void:
	var warm := Color(1.0, 0.82, 0.58)
	for p: Vector3 in [Vector3(-7.5, 5.0, -6.0), Vector3(7.5, 5.0, -6.0), Vector3(-7.5, 10.0, -18.0), Vector3(7.5, 10.0, -18.0), Vector3(0.0, 8.0, -22.0)]:
		GreyboxKit.lamp(parent, p, 1.1, 11.0, warm)
	var spot := SpotLight3D.new()
	spot.name = "PadSpot"
	spot.light_color = Color(1.0, 0.86, 0.6)
	spot.light_energy = 3.0
	spot.spot_range = 12.0
	spot.spot_angle = 30.0
	spot.position = pad_center() + Vector3(0, 8.5, 0)
	spot.rotation.x = -PI * 0.5
	parent.add_child(spot)


## Chips batched into multimeshes: faces by colour, edge inserts by insert colour, dark cores.
class _ChipBatch:
	extends RefCounted
	var faces: Dictionary[String, Array] = {}
	var inserts: Dictionary[String, Array] = {}
	var cores: Array[Transform3D] = []
	var _mat: Dictionary[String, Material] = {}

	func chip(c: Vector3, r: float, t: float, yaw: float, color: Color, n_inserts: int) -> void:
		var mats: Array = ChipStack.materials_for(color)
		var key: String = color.to_html(false)
		_mat[key] = mats[0]
		if not faces.has(key):
			faces[key] = []
		faces[key].append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(r, t * 0.9, r)), c))
		var ik: String = (mats[2] as StandardMaterial3D).albedo_color.to_html(false)
		_mat["i" + ik] = mats[2]
		if not inserts.has(ik):
			inserts[ik] = []
		var w: float = 0.42 * r / ChipTowers.CHIP_R if r < 1.5 else 0.5
		for k: int in n_inserts:
			var a: float = yaw + TAU * float(k) / float(n_inserts)
			var b := Basis(Vector3.UP, a)
			inserts[ik].append(Transform3D(b.scaled(Vector3(w, t * 0.62, 0.05)), c + b.z * (r - 0.005)))

	func core(c: Vector3, r: float, h: float) -> void:
		cores.append(Transform3D(Basis.from_scale(Vector3(r, h, r)), c))

	func commit(parent: Node3D) -> void:
		var disc := CylinderMesh.new()
		disc.top_radius = 1.0
		disc.bottom_radius = 1.0
		disc.height = 1.0
		disc.radial_segments = 28
		disc.rings = 1
		var box := BoxMesh.new()
		box.size = Vector3.ONE
		for key: String in faces:
			_add(parent, "Chips_" + key, disc, faces[key], _mat[key])
		for key: String in inserts:
			_add(parent, "Inserts_" + key, box, inserts[key], _mat["i" + key])
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
		mmi.material_override = mat
		parent.add_child(mmi)
