class_name PropRecipes
extends RefCounted
## Our own prop models, built from code with `ModelKit` (see docs/MODELS.md). Each recipe builds
## one model in metres, y up, standing on y = 0 unless noted, front facing +z. They replaced the
## third-party files the game used to ship (poly.pizza, Quaternius, Poly Haven, the roulette wheel)
## and keep those files' roles, proportions and orientation so the scenes place them the same way,
## but every shape here is modelled fresh in the game's warm low-poly casino style.
##
## `tools/models/build_models.gd` writes them to `assets/models/own/<id>.glb`.

const IDS: Array[String] = [
	"poker_chip", "coin", "money_pile", "bar_stool", "couch", "plant_palm", "plant_bush", "plant_spiky", "cone",
	"beer_mug_empty", "beer_mug_full", "column", "pedestal", "window_arch", "curtains", "door_double",
	"picture", "mirror", "bust", "horse", "bat", "revolver", "roulette_wheel",
]

const TEX_DIR: String = "res://assets/models/own/textures/"


static func build(id: String) -> Node3D:
	var k := ModelKit.new()
	var r := PropRecipes.new()
	r.call("_" + id, k)
	return k.build(id.to_pascal_case())


static func _pts(arr: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in arr:
		out.append(p)
	return out


static func _circle(r: float, n: int, start: float = 0.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i: int in n:
		var a: float = start + TAU * i / n
		out.append(Vector2(cos(a), sin(a)) * r)
	return out


## A band of an arch (or ring) in the xy plane at `centre`, between radii, from angle a0 to a1
## (radians, counter-clockwise from +x), `depth` along z: front, back, inner and outer faces.
static func arch_band(k: ModelKit, centre: Vector3, r_in: float, r_out: float, depth: float, a0: float, a1: float, segs: int, mat: String, inner: bool = true) -> void:
	var hz: float = depth * 0.5
	for i: int in segs:
		var t0: float = lerpf(a0, a1, float(i) / segs)
		var t1: float = lerpf(a0, a1, float(i + 1) / segs)
		var d0 := Vector3(cos(t0), sin(t0), 0)
		var d1 := Vector3(cos(t1), sin(t1), 0)
		var o0: Vector3 = centre + d0 * r_out
		var o1: Vector3 = centre + d1 * r_out
		var i0: Vector3 = centre + d0 * r_in
		var i1: Vector3 = centre + d1 * r_in
		var f := Vector3(0, 0, hz)
		# Front (+z): seen from the front, going counter-clockwise (a0 -> a1) the outer edge is on
		# the left of... order o1, o0, i0, i1 is clockwise for the viewer.
		k.quad(o1 + f, o0 + f, i0 + f, i1 + f, mat)
		k.quad(o0 - f, o1 - f, i1 - f, i0 - f, mat)
		k.quad(o0 + f, o1 + f, o1 - f, o0 - f, mat)
		if inner:
			k.quad(i1 + f, i0 + f, i0 - f, i1 - f, mat)


## An arch outline (rectangle of `w` with a half circle on top, springing at `spring` height),
## counter-clockwise, bottom at y = 0.
static func arch_shape(w: float, spring: float, segs: int = 16) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.append(Vector2(-w * 0.5, 0))
	out.append(Vector2(w * 0.5, 0))
	for i: int in segs + 1:
		var a: float = PI * float(i) / segs
		out.append(Vector2(cos(a) * w * 0.5, spring + sin(a) * w * 0.5))
	out.append(Vector2(-w * 0.5, 0))
	out.remove_at(out.size() - 1)
	return out


# --- Chips and coins ----------------------------------------------------------------------------

## Casino chip, 40 mm, 4 mm thick: red body, six cream edge spots, cream inlay ring and a gold heart.
func _poker_chip(k: ModelKit) -> void:
	var r: float = 0.02
	var h: float = 0.0042
	k.lathe(_pts([Vector2(0, 0), Vector2(r - 0.0006, 0), Vector2(r, 0.0006), Vector2(r, h - 0.0006), Vector2(r - 0.0006, h), Vector2(0, h)]), "ChipInlay", Transform3D.IDENTITY, 36, 50.0)
	for i: int in 6:
		var a: float = TAU * i / 6.0
		var p := Vector3(cos(a), 0, sin(a)) * (r - 0.0006)
		k.box(Vector3(0.0016, h * 0.86, 0.0074), p + Vector3(0, h * 0.5, 0), "ChipStripe", Vector3(0, -rad_to_deg(a), 0))
	for y: float in [h + 0.0001, -0.0001]:
		var flip: Vector3 = Vector3(0, 0, 0) if y > 0.0 else Vector3(180, 0, 0)
		k.lathe(_pts([Vector2(0.0125, 0), Vector2(0.0142, 0), Vector2(0.0142, 0.0002), Vector2(0.0125, 0.0002), Vector2(0.0125, 0)]), "ChipStripe", ModelKit.T(Vector3(0, y, 0), flip), 36, 10.0)
		k.cyl(0.0085, 0.0085, 0.0003, Vector3(0, y, 0), "Gold", flip, 24)


## Placeholder coin (items without a model): a thick gold coin standing up, facing +z, with a
## raised rim and a star on each face.
func _coin(k: ModelKit) -> void:
	var r: float = 0.37
	var h: float = 0.09
	var prof := _pts([Vector2(0, -h), Vector2(r - 0.03, -h), Vector2(r, -h + 0.03), Vector2(r, h - 0.03),
		Vector2(r - 0.03, h), Vector2(r - 0.07, h), Vector2(r - 0.09, h - 0.03), Vector2(0, h - 0.03)])
	k.lathe(prof, "Coin", ModelKit.T(Vector3.ZERO, Vector3(90, 0, 0)), 28, 40.0)
	k.lathe(_pts([Vector2(0, -h + 0.03), Vector2(r - 0.09, -h + 0.03), Vector2(r - 0.07, -h), Vector2(r - 0.03, -h)]), "Coin", ModelKit.T(Vector3.ZERO, Vector3(-90, 0, 0)), 28, 40.0)
	var star := PackedVector2Array()
	for i: int in 10:
		var a: float = PI * 0.5 + TAU * i / 10.0
		star.append(Vector2(cos(a), sin(a)) * (0.17 if i % 2 == 0 else 0.075))
	k.extrude(star, 0.03, "Coin", ModelKit.T(Vector3(0, 0, h - 0.02)), 0.01)
	k.extrude(star, 0.03, "Coin", ModelKit.T(Vector3(0, 0, -h + 0.02), Vector3(0, 180, 0)), 0.01)


## Heap of cash next to Peg Drop when the jackpot is big, about 1 m wide: banded bundles of bills
## stacked in a loose pyramid with a few gold coins spilled around.
func _money_pile(k: ModelKit) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var bw := Vector3(0.16, 0.035, 0.07)
	var layers: Array = [[0.5, 30], [0.36, 18], [0.22, 9], [0.1, 3]]
	var y: float = bw.y * 0.5
	for layer: Array in layers:
		var r: float = layer[0]
		for i: int in layer[1]:
			var a: float = rng.randf() * TAU
			var d: float = sqrt(rng.randf()) * r
			var p := Vector3(cos(a) * d, y + rng.randf_range(-0.004, 0.004), sin(a) * d * 0.8)
			var yaw: float = rng.randf_range(0, 180)
			var tilt := Vector3(rng.randf_range(-6, 6), yaw, rng.randf_range(-6, 6))
			k.bbox(bw, 0.006, p, "Bill", tilt)
			k.box(Vector3(0.03, bw.y + 0.004, bw.z + 0.004), p, "Cream", tilt)
		y += bw.y * 0.92
	for i: int in 14:
		var a: float = rng.randf() * TAU
		var d: float = rng.randf_range(0.45, 0.62)
		k.cyl(0.025, 0.025, 0.006, Vector3(cos(a) * d, 0.003 + (i % 3) * 0.006, sin(a) * d * 0.8), "Coin", Vector3(rng.randf_range(-4, 4), 0, rng.randf_range(-4, 4)), 12)


# --- Furniture ----------------------------------------------------------------------------------

## Bar stool, 0.44 m: tufted round leather seat on a gold ring, four splayed dark wood legs and a
## gold foot ring.
func _bar_stool(k: ModelKit) -> void:
	var top: float = 0.435
	k.lathe(_pts([Vector2(0, top - 0.05), Vector2(0.118, top - 0.05), Vector2(0.13, top - 0.035), Vector2(0.132, top - 0.018),
		Vector2(0.122, top - 0.004), Vector2(0.09, top), Vector2(0, top + 0.003)]), "Leather", Transform3D.IDENTITY, 20, 50.0)
	k.ball(Vector3(0.012, 0.004, 0.012), Vector3(0, top + 0.002, 0), "Gold", Vector3.ZERO, 8)
	k.torus(0.112, 0.124, Vector3(0, top - 0.054, 0), "Gold", Vector3.ZERO, 24, 6)
	k.cyl(0.11, 0.11, 0.022, Vector3(0, top - 0.068, 0), "WoodDark", Vector3.ZERO, 20)
	for i: int in 4:
		var a: float = TAU * (i + 0.5) / 4.0
		var d := Vector3(cos(a), 0, sin(a))
		var p0: Vector3 = d * 0.075 + Vector3(0, top - 0.075, 0)
		var p1: Vector3 = d * 0.112 + Vector3(0, 0.0, 0)
		k.tube(PackedVector3Array([p1, p0]), [0.011, 0.014], "WoodDark", Transform3D.IDENTITY, 6)
		k.cyl(0.013, 0.014, 0.012, p1 + Vector3(0, 0.006, 0), "Gold", Vector3.ZERO, 8)
	k.torus(0.093, 0.101, Vector3(0, 0.14, 0), "Gold", Vector3.ZERO, 24, 6)


## Chesterfield-style sofa, about 2.3 m wide: burgundy velvet, rolled arms, a buttoned back,
## two seat cushions and turned wooden feet with gold caps. Faces +z.
func _couch(k: ModelKit) -> void:
	var w: float = 2.3
	var d: float = 1.0
	var seat_y: float = 0.44
	# Base frame and plinth.
	k.bbox(Vector3(w - 0.1, 0.22, d - 0.08), 0.03, Vector3(0, 0.25, 0), "Fabric")
	k.bbox(Vector3(w - 0.06, 0.04, d - 0.04), 0.012, Vector3(0, 0.14, 0), "WoodDark")
	# Seat cushions.
	for sx: float in [-1.0, 1.0]:
		k.bbox(Vector3((w - 0.62) * 0.5 - 0.02, 0.13, d - 0.32), 0.05, Vector3(sx * ((w - 0.62) * 0.25 + 0.0), seat_y - 0.02, 0.1), "Fabric")
	# Back: a tall rounded slab with button tufting and a rolled top.
	var back_z: float = -d * 0.5 + 0.13
	k.bbox(Vector3(w - 0.3, 0.46, 0.2), 0.06, Vector3(0, seat_y + 0.23, back_z), "Fabric")
	k.tube(PackedVector3Array([Vector3(-w * 0.5 + 0.15, seat_y + 0.46, back_z), Vector3(w * 0.5 - 0.15, seat_y + 0.46, back_z)]), 0.11, "Fabric", Transform3D.IDENTITY, 12)
	for row: int in 2:
		for i: int in 7:
			var x: float = lerpf(-w * 0.5 + 0.35, w * 0.5 - 0.35, float(i) / 6.0) + (0.0 if row == 0 else (w - 0.7) / 12.0)
			if row == 1 and i == 6:
				continue
			k.ball(Vector3(0.018, 0.018, 0.012), Vector3(x, seat_y + 0.16 + row * 0.15, back_z + 0.1), "Gold", Vector3.ZERO, 6)
	# Rolled arms.
	for sx: float in [-1.0, 1.0]:
		var ax: float = sx * (w * 0.5 - 0.12)
		k.bbox(Vector3(0.22, 0.34, d - 0.06), 0.04, Vector3(ax, 0.43, 0), "Fabric")
		k.tube(PackedVector3Array([Vector3(ax + sx * 0.02, 0.62, -d * 0.5 + 0.04), Vector3(ax + sx * 0.02, 0.62, d * 0.5 - 0.02)]), 0.13, "Fabric", Transform3D.IDENTITY, 12)
		k.cyl(0.07, 0.07, 0.012, Vector3(ax + sx * 0.02, 0.62, d * 0.5 - 0.02 + 0.006), "Gold", Vector3(90, 0, 0), 12)
	# Feet.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var p := Vector3(sx * (w * 0.5 - 0.12), 0, sz * (d * 0.5 - 0.1))
			k.lathe(_pts([Vector2(0, 0), Vector2(0.03, 0), Vector2(0.034, 0.03), Vector2(0.045, 0.07), Vector2(0.05, 0.11), Vector2(0.04, 0.14), Vector2(0, 0.14)]), "WoodDark", ModelKit.T(p), 10, 60.0)
			k.cyl(0.032, 0.032, 0.02, p + Vector3(0, 0.01, 0), "Gold", Vector3.ZERO, 10)


# --- Plants -------------------------------------------------------------------------------------

## A flat leaf: pointed oval in the xy plane (stem at the origin, tip at +y `length`), thin.
static func leaf_shape(length: float, width: float, n: int = 6) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.append(Vector2(0, 0))
	for i: int in range(1, n):
		var t: float = float(i) / n
		out.append(Vector2(sin(t * PI) * width * 0.5 * (1.0 - t * 0.25), t * length))
	out.append(Vector2(0, length))
	for i: int in range(n - 1, 0, -1):
		var t: float = float(i) / n
		out.append(Vector2(-sin(t * PI) * width * 0.5 * (1.0 - t * 0.25), t * length))
	return out


## Leaf bent in two pieces: base part rising, tip part drooping by `droop` degrees.
static func bent_leaf(k: ModelKit, base: Vector3, yaw: float, tilt: float, length: float, width: float, droop: float, mat: String) -> void:
	var cut: float = length * 0.55
	var wcut: float = sin(0.55 * PI) * width * 0.5 * (1.0 - 0.55 * 0.25)
	var low := PackedVector2Array([Vector2(0, 0)])
	for i: int in range(1, 6):
		var t: float = 0.55 * float(i) / 5.0
		low.append(Vector2(sin(t * PI) * width * 0.5 * (1.0 - t * 0.25), t * length))
	for i: int in range(5, 0, -1):
		var t: float = 0.55 * float(i) / 5.0
		low.append(Vector2(-sin(t * PI) * width * 0.5 * (1.0 - t * 0.25), t * length))
	# Tip half: right base, up the right side, tip, down the left side.
	var loop := PackedVector2Array([Vector2(wcut, 0)])
	for i: int in range(1, 5):
		var t: float = 0.55 + 0.45 * float(i) / 5.0
		loop.append(Vector2(sin(t * PI) * width * 0.5 * (1.0 - t * 0.25), (t - 0.55) * length))
	loop.append(Vector2(0, 0.45 * length))
	for i: int in range(4, 0, -1):
		var t: float = 0.55 + 0.45 * float(i) / 5.0
		loop.append(Vector2(-sin(t * PI) * width * 0.5 * (1.0 - t * 0.25), (t - 0.55) * length))
	loop.append(Vector2(-wcut, 0))
	var b := Basis.from_euler(Vector3(deg_to_rad(tilt), deg_to_rad(yaw), 0), EULER_ORDER_YXZ)
	var x1 := Transform3D(b, base)
	k.extrude(low, 0.008, mat, x1)
	var tip_base: Vector3 = base + b * Vector3(0, cut, 0)
	var b2 := Basis.from_euler(Vector3(deg_to_rad(tilt + droop), deg_to_rad(yaw), 0), EULER_ORDER_YXZ)
	k.extrude(loop, 0.008, mat, Transform3D(b2, tip_base))
	# Midrib.
	k.tube(PackedVector3Array([base, tip_base, tip_base + b2 * Vector3(0, length * 0.42, 0.004)]), [0.007, 0.005, 0.002], "LeafLight", Transform3D.IDENTITY, 4)


## Tall palm-leaf plant (about 1.85 m) in an octagonal cream urn with a gold band.
func _plant_palm(k: ModelKit) -> void:
	var pot := _pts([Vector2(0, 0), Vector2(0.17, 0), Vector2(0.19, 0.03), Vector2(0.16, 0.08), Vector2(0.2, 0.3),
		Vector2(0.24, 0.42), Vector2(0.26, 0.46), Vector2(0.235, 0.47)])
	k.lathe(pot, "Cream", Transform3D.IDENTITY, 8, 25.0)
	k.lathe(_pts([Vector2(0.2, 0.29), Vector2(0.215, 0.31), Vector2(0.222, 0.345), Vector2(0.207, 0.36)]), "Gold", Transform3D.IDENTITY, 8, 70.0)
	k.cyl(0.235, 0.235, 0.01, Vector3(0, 0.455, 0), "Soil", Vector3.ZERO, 8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i: int in 9:
		var yaw: float = 360.0 * i / 9.0 + rng.randf_range(-12, 12)
		var stem_h: float = rng.randf_range(0.6, 1.0)
		var lean: float = rng.randf_range(8, 22)
		var b := Basis.from_euler(Vector3(deg_to_rad(lean), deg_to_rad(yaw), 0), EULER_ORDER_YXZ)
		var base := Vector3(0, 0.46, 0)
		var top: Vector3 = base + b * Vector3(0, stem_h, 0)
		k.tube(PackedVector3Array([base, top]), [0.014, 0.01], "LeafDark", Transform3D.IDENTITY, 5, false)
		bent_leaf(k, top, yaw, lean + rng.randf_range(5, 20), rng.randf_range(0.55, 0.8), rng.randf_range(0.2, 0.26), rng.randf_range(25, 50), "Leaf" if i % 3 else "LeafLight")


## Low bushy plant (about 0.9 m tall, wide) with broad split leaves in a dark bowl with gold lip.
func _plant_bush(k: ModelKit) -> void:
	k.lathe(_pts([Vector2(0, 0), Vector2(0.13, 0), Vector2(0.16, 0.04), Vector2(0.2, 0.2), Vector2(0.21, 0.27)]), "Charcoal", Transform3D.IDENTITY, 14, 30.0)
	k.torus(0.2, 0.225, Vector3(0, 0.27, 0), "Gold", Vector3.ZERO, 18, 6)
	k.cyl(0.2, 0.2, 0.01, Vector3(0, 0.26, 0), "Soil", Vector3.ZERO, 14)
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	for i: int in 11:
		var yaw: float = 360.0 * i / 11.0 * 1.0 + rng.randf_range(-15, 15)
		var lean: float = rng.randf_range(30, 62)
		var b := Basis.from_euler(Vector3(deg_to_rad(lean), deg_to_rad(yaw), 0), EULER_ORDER_YXZ)
		var base := Vector3(0, 0.27, 0)
		var len: float = rng.randf_range(0.25, 0.42)
		var top: Vector3 = base + b * Vector3(0, len, 0)
		k.tube(PackedVector3Array([base, top]), [0.012, 0.008], "LeafDark", Transform3D.IDENTITY, 5, false)
		# Broad heart-ish leaf with two notches per side, lying out flat-ish.
		var lw: float = rng.randf_range(0.28, 0.38)
		var shape := PackedVector2Array()
		for j: int in 15:
			var t: float = float(j) / 14.0
			var a: float = lerpf(-PI * 0.5, PI * 1.5, t)
			var r: float = lw * 0.5 * (1.0 + 0.15 * sin(a))
			if j in [3, 5, 9, 11]:
				r *= 0.62
			shape.append(Vector2(cos(a) * r, sin(a) * r + lw * 0.5))
		var lb := Basis.from_euler(Vector3(deg_to_rad(lean + rng.randf_range(10, 30)), deg_to_rad(yaw), 0), EULER_ORDER_YXZ)
		k.extrude(shape, 0.008, "Leaf" if i % 3 else "LeafDark", Transform3D(lb, top), 0.0, "LeafDark")
		# Centre vein.
		k.tube(PackedVector3Array([top, top + lb * Vector3(0, lw * 0.95, 0.005)]), [0.005, 0.002], "LeafLight", Transform3D.IDENTITY, 4, false)


## Snake plant (about 0.93 m): tall upright blade leaves in a tall black pot with a gold foot.
func _plant_spiky(k: ModelKit) -> void:
	k.lathe(_pts([Vector2(0, 0), Vector2(0.11, 0), Vector2(0.12, 0.025), Vector2(0.135, 0.03), Vector2(0.165, 0.32), Vector2(0.17, 0.34)]), "Black", Transform3D.IDENTITY, 12, 30.0)
	k.torus(0.112, 0.128, Vector3(0, 0.02, 0), "Gold", Vector3.ZERO, 16, 5)
	k.cyl(0.165, 0.165, 0.01, Vector3(0, 0.33, 0), "Soil", Vector3.ZERO, 12)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i: int in 9:
		var yaw: float = 360.0 * i / 9.0 + rng.randf_range(-20, 20)
		var off := Vector3(cos(deg_to_rad(yaw)), 0, sin(deg_to_rad(yaw))) * rng.randf_range(0.02, 0.09)
		var len: float = rng.randf_range(0.42, 0.62)
		var blade := _pts([Vector2(-0.032, 0), Vector2(0.032, 0), Vector2(0.04, len * 0.4), Vector2(0.03, len * 0.8), Vector2(0, len), Vector2(-0.03, len * 0.8), Vector2(-0.04, len * 0.4)])
		var lean: float = rng.randf_range(-12, 12)
		var b := Basis.from_euler(Vector3(deg_to_rad(lean), deg_to_rad(yaw + 90), deg_to_rad(rng.randf_range(-6, 6))), EULER_ORDER_YXZ)
		k.extrude(blade, 0.012, "LeafDark" if i % 2 else "Leaf", Transform3D(b, Vector3(0, 0.33, 0) + off), 0.004, "LeafLight")


# --- Small things -------------------------------------------------------------------------------

## Out-of-order cone, 0.9 m: orange with two cream reflective bands on a square charcoal foot.
func _cone(k: ModelKit) -> void:
	k.bbox(Vector3(0.6, 0.05, 0.6), 0.02, Vector3(0, 0.025, 0), "Charcoal")
	k.bbox(Vector3(0.5, 0.03, 0.5), 0.015, Vector3(0, 0.065, 0), "Charcoal")
	var r0: float = 0.2
	var r1: float = 0.035
	var y0: float = 0.08
	var y1: float = 0.9
	var bands: Array = [[0.0, 0.3, "Orange"], [0.3, 0.42, "Cream"], [0.42, 0.62, "Orange"], [0.62, 0.72, "Cream"], [0.72, 1.0, "Orange"]]
	for b: Array in bands:
		var ya: float = lerpf(y0, y1, b[0])
		var yb: float = lerpf(y0, y1, b[1])
		var ra: float = lerpf(r0, r1, b[0])
		var rb: float = lerpf(r0, r1, b[1])
		var prof := _pts([Vector2(ra, ya), Vector2(rb, yb)])
		if b[1] >= 1.0:
			prof.append(Vector2(0.0, yb))
		k.lathe(prof, b[2], Transform3D.IDENTITY, 16, 60.0)


## Beer mug, glass with a thick base and a D handle; `full` adds beer and a foam head. About
## 0.24 m tall, handle at +x.
func _mug(k: ModelKit, full: bool) -> void:
	var r: float = 0.075
	var h: float = 0.2
	var t: float = 0.008
	k.lathe(_pts([Vector2(0, 0), Vector2(r - 0.004, 0), Vector2(r, 0.006), Vector2(r, h), Vector2(r - t, h), Vector2(r - t, 0.028), Vector2(0, 0.028)]), "Glass", Transform3D.IDENTITY, 10, 20.0)
	var hp := PackedVector3Array()
	for i: int in 9:
		var a: float = lerpf(PI * 0.5, -PI * 0.5, float(i) / 8.0)
		hp.append(Vector3(r - 0.002 + cos(a) * 0.05 * (1.0 if absf(sin(a)) < 0.7 else 0.85), 0.11 + sin(a) * 0.055, 0))
	k.tube(hp, 0.011, "Glass", Transform3D.IDENTITY, 6)
	if full:
		k.cyl(r - t - 0.001, r - t - 0.001, 0.15, Vector3(0, 0.028 + 0.075, 0), "Beer", Vector3.ZERO, 12)
		var rng := RandomNumberGenerator.new()
		rng.seed = 3
		k.cyl(r + 0.004, r - t, 0.03, Vector3(0, h - 0.012, 0), "Foam", Vector3.ZERO, 12)
		for i: int in 9:
			var a: float = TAU * i / 9.0 + rng.randf_range(-0.2, 0.2)
			var rr: float = rng.randf_range(0.02, 0.055)
			k.ball(Vector3(0.034, 0.024, 0.034) * rng.randf_range(0.8, 1.15), Vector3(cos(a) * rr, h + 0.008, sin(a) * rr), "Foam", Vector3.ZERO, 8)
		# A drip of foam over the rim.
		k.tube(PackedVector3Array([Vector3(-r - 0.002, h + 0.004, 0.02), Vector3(-r - 0.006, h - 0.02, 0.024), Vector3(-r - 0.005, h - 0.045, 0.022)]), [0.012, 0.01, 0.007], "Foam", Transform3D.IDENTITY, 6)


func _beer_mug_empty(k: ModelKit) -> void:
	_mug(k, false)


func _beer_mug_full(k: ModelKit) -> void:
	_mug(k, true)


# --- Architecture -------------------------------------------------------------------------------

## A fluted outline (circle of `r` with `flutes` shallow scallops), counter-clockwise.
static func fluted(r: float, flutes: int, depth: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n: int = flutes * 4
	for i: int in n:
		var a: float = TAU * i / n
		var f: float = fposmod(float(i), 4.0)
		var rr: float = r - (depth if f == 2.0 else (depth * 0.6 if f != 0.0 else 0.0))
		out.append(Vector2(cos(a), sin(a)) * rr)
	return out


## Classical column, 5.4 m: square plinth, torus mouldings, a fluted shaft with a gold collar and
## a Doric-style capital. All marble except two gold rings (the game recolours "Marble").
func _column(k: ModelKit) -> void:
	var H: float = 5.4
	var R: float = 0.42
	k.bbox(Vector3(1.32, 0.22, 1.32), 0.03, Vector3(0, 0.11, 0), "Marble")
	k.lathe(_pts([Vector2(0.62, 0.22), Vector2(0.64, 0.26), Vector2(0.6, 0.32), Vector2(0.52, 0.34), Vector2(0.5, 0.38),
		Vector2(0.53, 0.42), Vector2(0.5, 0.47), Vector2(R + 0.02, 0.5), Vector2(R + 0.02, 0.56)]), "Marble", Transform3D.IDENTITY, 24, 50.0)
	k.torus(R + 0.01, R + 0.05, Vector3(0, 0.58, 0), "Gold", Vector3.ZERO, 24, 6)
	# Shaft: fluted, slightly narrower at the top (two stacked extrusions).
	var shaft_bottom: float = 0.58
	var shaft_top: float = H - 0.62
	var mid: float = lerpf(shaft_bottom, shaft_top, 0.5)
	k.extrude(fluted(R, 16, 0.025), mid - shaft_bottom, "Marble", ModelKit.T(Vector3(0, (shaft_bottom + mid) * 0.5, 0), Vector3(90, 0, 0)), 0.0, "", false)
	k.extrude(fluted(R * 0.94, 16, 0.024), shaft_top - mid, "Marble", ModelKit.T(Vector3(0, (mid + shaft_top) * 0.5, 0), Vector3(90, 0, 0)), 0.0, "", false)
	k.lathe(_pts([Vector2(R, mid - 0.04), Vector2(R * 0.97, mid), Vector2(R * 0.94, mid + 0.04)]), "Marble", Transform3D.IDENTITY, 24)
	# Capital.
	k.torus(R * 0.94 - 0.01, R * 0.94 + 0.04, Vector3(0, shaft_top + 0.03, 0), "Gold", Vector3.ZERO, 24, 6)
	k.lathe(_pts([Vector2(R * 0.94, shaft_top + 0.06), Vector2(R * 0.96, shaft_top + 0.2), Vector2(0.5, shaft_top + 0.26),
		Vector2(0.6, shaft_top + 0.34), Vector2(0.64, shaft_top + 0.4), Vector2(0, shaft_top + 0.4)]), "Marble", Transform3D.IDENTITY, 24, 40.0)
	k.bbox(Vector3(1.38, 0.2, 1.38), 0.03, Vector3(0, H - 0.1, 0), "Marble")
	k.bbox(Vector3(1.3, 0.03, 1.3), 0.01, Vector3(0, H - 0.215, 0), "Marble")


## Statue pedestal, 1.77 m: square foot and top slab, a turned body with a gold band.
func _pedestal(k: ModelKit) -> void:
	k.bbox(Vector3(1.4, 0.2, 1.4), 0.04, Vector3(0, 0.1, 0), "Marble")
	k.bbox(Vector3(1.22, 0.12, 1.22), 0.03, Vector3(0, 0.26, 0), "Marble")
	k.lathe(_pts([Vector2(0.56, 0.32), Vector2(0.58, 0.38), Vector2(0.5, 0.46), Vector2(0.42, 0.5), Vector2(0.4, 0.58),
		Vector2(0.37, 1.0), Vector2(0.36, 1.2), Vector2(0.4, 1.28), Vector2(0.38, 1.33), Vector2(0.44, 1.38), Vector2(0.56, 1.46), Vector2(0.6, 1.5)]), "Marble", Transform3D.IDENTITY, 24, 40.0)
	k.torus(0.37, 0.41, Vector3(0, 0.62, 0), "Gold", Vector3.ZERO, 24, 6)
	k.bbox(Vector3(1.44, 0.14, 1.44), 0.03, Vector3(0, 1.57, 0), "Marble")
	k.bbox(Vector3(1.3, 0.13, 1.3), 0.02, Vector3(0, 1.705, 0), "Marble")


## Arched window, 0.9 x 1.55 m, 0.11 m deep: white frame and muntins round "Glass" panes (the game
## recolours "White" and "Glass"), with a sill and a keystone.
func _window_arch(k: ModelKit) -> void:
	var w: float = 0.9
	var spring: float = 1.1
	var fw: float = 0.07
	var d: float = 0.11
	var rr: float = w * 0.5
	# Outer frame: sides, bottom and the arch band.
	for sx: float in [-1.0, 1.0]:
		k.box(Vector3(fw, spring, d), Vector3(sx * (rr - fw * 0.5), spring * 0.5, 0), "White")
	k.box(Vector3(w, fw, d), Vector3(0, fw * 0.5, 0), "White")
	arch_band(k, Vector3(0, spring, 0), rr - fw, rr, d, 0.0, PI, 16, "White")
	# Sill and keystone.
	k.bbox(Vector3(w + 0.1, 0.05, d + 0.08), 0.012, Vector3(0, -0.02, 0.03), "White")
	k.extrude(_pts([Vector2(-0.05, 0), Vector2(0.05, 0), Vector2(0.07, 0.12), Vector2(-0.07, 0.12)]), d + 0.03, "White", ModelKit.T(Vector3(0, spring + rr - fw - 0.01, 0)), 0.01)
	# Glass, set back a little.
	k.extrude(arch_shape(w - fw * 2.0 + 0.01, spring - fw, 16), 0.012, "Glass", ModelKit.T(Vector3(0, fw, -0.02)), 0.0)
	# Muntins: a centre bar, two cross bars and a fan in the arch.
	var mw: float = 0.025
	var md: float = d * 0.6
	k.box(Vector3(mw, spring + rr - fw * 2.0, md), Vector3(0, (spring + rr) * 0.5, 0), "White")
	for y: float in [0.4, 0.78]:
		k.box(Vector3(w - fw * 2.0, mw, md), Vector3(0, y, 0), "White")
	k.box(Vector3(w - fw * 2.0, mw, md), Vector3(0, spring, 0), "White")
	for a: float in [PI * 0.25, PI * 0.75]:
		var dir := Vector3(cos(a), sin(a), 0)
		k.box(Vector3(rr - fw, mw, md), Vector3(0, spring, 0) + dir * (rr - fw) * 0.5, "White", Vector3(0, 0, rad_to_deg(a)))
	arch_band(k, Vector3(0, spring, 0), 0.12, 0.12 + mw, md, 0.0, PI, 10, "White")


## One drape: a pleated cloth hanging from x0..x1 at the top, gathered towards `gather_x` by a
## tie-back at `tie_y`, hem at y = 0, folds along z.
static func drape(k: ModelKit, x0: float, x1: float, top: float, tie_y: float, gather_x: float, mat: String) -> void:
	var cols: int = 22
	var rows: int = 14
	var grid: Array = []
	for j: int in rows + 1:
		var v: float = float(j) / rows  # 0 = top
		var y: float = lerpf(top, 0.0, v)
		var row: Array = []
		# Squeeze towards the tie-back: strongest at tie height, eases off above and below.
		var squeeze: float
		if y >= tie_y:
			squeeze = smoothstep(top, tie_y, y) * 0.62
		else:
			squeeze = lerpf(0.62, 0.4, smoothstep(tie_y, 0.0, y))
		for i: int in cols + 1:
			var u: float = float(i) / cols
			var x: float = lerpf(x0, x1, u)
			x = lerpf(x, gather_x + (x - gather_x) * 0.35, squeeze)
			var amp: float = 0.045 * (1.0 + squeeze * 0.8)
			var z: float = sin(u * PI * 9.0) * amp + 0.05
			row.append(Vector3(x, y, z))
		grid.append(row)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normal_at := func(j: int, i: int) -> Vector3:
		var a: Vector3 = grid[j][mini(i + 1, cols)] - grid[j][maxi(i - 1, 0)]
		var b: Vector3 = grid[maxi(j - 1, 0)][i] - grid[mini(j + 1, rows)][i]
		return a.cross(b).normalized()
	for j: int in rows:
		for i: int in cols:
			var p00: Vector3 = grid[j][i]
			var p01: Vector3 = grid[j][i + 1]
			var p10: Vector3 = grid[j + 1][i]
			var p11: Vector3 = grid[j + 1][i + 1]
			var n00: Vector3 = normal_at.call(j, i)
			var n01: Vector3 = normal_at.call(j, i + 1)
			var n10: Vector3 = normal_at.call(j + 1, i)
			var n11: Vector3 = normal_at.call(j + 1, i + 1)
			# Front (+z), clockwise for the viewer: top-left, top-right, bottom-right, bottom-left.
			verts.append_array([p00, p01, p11, p00, p11, p10])
			norms.append_array([n00, n01, n11, n00, n11, n10])
			# Back.
			verts.append_array([p00, p11, p01, p00, p10, p11])
			norms.append_array([-n00, -n11, -n01, -n00, -n10, -n11])
			for _q: int in 12:
				uvs.append(Vector2.ZERO)
	k.tris(verts, norms, uvs, Transform3D.IDENTITY, mat)


## Velvet curtains for a window, 3.5 m wide and 4.3 m tall: a gold rod with ball finials and
## rings, two pleated drapes held by gold tie-backs, tassels. Recoloured by "Fabric" and "Gold".
func _curtains(k: ModelKit) -> void:
	var w: float = 3.4
	var top: float = 4.2
	k.tube(PackedVector3Array([Vector3(-w * 0.5 - 0.05, top + 0.06, 0.05), Vector3(w * 0.5 + 0.05, top + 0.06, 0.05)]), 0.03, "Gold", Transform3D.IDENTITY, 8)
	for sx: float in [-1.0, 1.0]:
		k.ball(Vector3(0.07, 0.07, 0.07), Vector3(sx * (w * 0.5 + 0.1), top + 0.06, 0.05), "Gold", Vector3.ZERO, 10)
		k.cyl(0.02, 0.035, 0.05, Vector3(sx * (w * 0.5 + 0.03), top + 0.06, 0.05), "Gold", Vector3(0, 0, 90 * sx), 8)
	var half: float = w * 0.5
	var tie_y: float = top * 0.36
	drape(k, -half, -0.06, top, tie_y, -half + 0.05, "Fabric")
	drape(k, 0.06, half, top, tie_y, half - 0.05, "Fabric")
	for i: int in 12:
		var x: float = lerpf(-half + 0.05, half - 0.05, float(i) / 11.0)
		if absf(x) < 0.1:
			continue
		k.torus(0.03, 0.042, Vector3(x, top + 0.06, 0.05), "Gold", Vector3(90, 0, 90), 10, 4)
	for sx: float in [-1.0, 1.0]:
		var cx: float = sx * (half - 0.05 - 0.5)
		k.tube(PackedVector3Array([Vector3(sx * (half + 0.02), tie_y, 0.0), Vector3(cx, tie_y + 0.02, 0.14), Vector3(sx * (half - 0.3), tie_y, 0.16)]), 0.025, "Gold", Transform3D.IDENTITY, 6)
		var tx: float = sx * (half - 0.32)
		k.ball(Vector3(0.05, 0.05, 0.05), Vector3(tx, tie_y - 0.02, 0.17), "Gold", Vector3.ZERO, 8)
		k.cyl(0.02, 0.06, 0.22, Vector3(tx, tie_y - 0.17, 0.17), "Gold", Vector3.ZERO, 8)


## Double doors, 3.5 x 4.2 m: a wood frame and two leaves with raised panels, gold kick plates and
## long gold pull bars, an arched transom panel. Recoloured by "Wood" and "Gold".
func _door_double(k: ModelKit) -> void:
	var w: float = 3.48
	var h: float = 4.19
	var d: float = 0.42
	var fw: float = 0.18
	for sx: float in [-1.0, 1.0]:
		k.bbox(Vector3(fw, h, d), 0.03, Vector3(sx * (w * 0.5 - fw * 0.5), h * 0.5, 0), "Wood")
	k.bbox(Vector3(w, fw, d), 0.03, Vector3(0, h - fw * 0.5, 0), "Wood")
	var lw: float = (w - fw * 2.0) * 0.5
	var lh: float = h - fw
	var lt: float = 0.1
	for sx: float in [-1.0, 1.0]:
		var cx: float = sx * lw * 0.5
		k.bbox(Vector3(lw - 0.01, lh, lt), 0.015, Vector3(cx, lh * 0.5, 0), "Wood")
		# Three raised panels per leaf (tall, square, tall).
		var panels: Array = [[0.25, 1.3], [1.7, 0.75], [2.6, 1.25]]
		for p: Array in panels:
			k.bbox(Vector3(lw - 0.36, p[1], 0.05), 0.03, Vector3(cx, p[0] + p[1] * 0.5, lt * 0.5 + 0.01), "Wood")
			k.bbox(Vector3(lw - 0.36, p[1], 0.05), 0.03, Vector3(cx, p[0] + p[1] * 0.5, -lt * 0.5 - 0.01), "Wood")
			# Gold bead around each panel.
			var pw: float = lw - 0.3
			for sy: float in [-1.0, 1.0]:
				k.box(Vector3(pw, 0.018, 0.018), Vector3(cx, p[0] + p[1] * 0.5 + sy * (p[1] * 0.5 + 0.03), lt * 0.5 + 0.01), "Gold")
			for sxx: float in [-1.0, 1.0]:
				k.box(Vector3(0.018, p[1] + 0.078, 0.018), Vector3(cx + sxx * pw * 0.5, p[0] + p[1] * 0.5, lt * 0.5 + 0.01), "Gold")
		# Kick plate and pull bar near the meeting edge.
		k.box(Vector3(lw - 0.12, 0.16, 0.012), Vector3(cx, 0.1, lt * 0.5 + 0.006), "Gold")
		var bx: float = sx * 0.16
		k.tube(PackedVector3Array([Vector3(bx, 1.3, lt * 0.5), Vector3(bx, 1.3, lt * 0.5 + 0.09), Vector3(bx, 2.3, lt * 0.5 + 0.09), Vector3(bx, 2.3, lt * 0.5)]), 0.022, "Gold", Transform3D.IDENTITY, 8)
	# Meeting stile.
	k.box(Vector3(0.04, lh, lt + 0.03), Vector3(0, lh * 0.5, 0), "Wood")


# --- Wall art -----------------------------------------------------------------------------------

## A moulded gold frame: four mitred bars with a stepped profile around a w x h opening.
static func moulded_frame(k: ModelKit, w: float, h: float, bar: float, depth: float, z: float, mat: String) -> void:
	var steps: Array = [[0.0, 1.0, 0.45], [0.18, 0.7, 1.0], [0.62, 0.35, 0.7]]
	for s: Array in steps:
		var inset: float = bar * float(s[0])
		var bw: float = bar * float(s[1]) * 0.6 if s[0] > 0.0 else bar
		var dz: float = depth * float(s[2])
		var ow: float = w * 0.5 + bar - inset
		var oh: float = h * 0.5 + bar - inset
		var iw: float = ow - bw
		var ih: float = oh - bw
		for side: int in 4:
			var poly: PackedVector2Array
			match side:
				0: poly = _pts([Vector2(-ow, -oh), Vector2(ow, -oh), Vector2(iw, -ih), Vector2(-iw, -ih)])
				1: poly = _pts([Vector2(ow, -oh), Vector2(ow, oh), Vector2(iw, ih), Vector2(iw, -ih)])
				2: poly = _pts([Vector2(ow, oh), Vector2(-ow, oh), Vector2(-iw, ih), Vector2(iw, ih)])
				3: poly = _pts([Vector2(-ow, oh), Vector2(-ow, -oh), Vector2(-iw, -ih), Vector2(-iw, ih)])
			k.extrude(poly, dz, mat, ModelKit.T(Vector3(0, 0, z + dz * 0.5)), minf(dz, bw) * 0.25)


## Framed oil painting, 0.6 x 0.46 m, hanging flat on the wall (back at z = 0, front +z): our own
## painted landscape in a stepped gold frame with corner rosettes.
func _picture(k: ModelKit) -> void:
	var w: float = 0.5
	var h: float = 0.36
	var canvas := StandardMaterial3D.new()
	canvas.resource_name = "Canvas"
	canvas.albedo_texture = ImageTexture.create_from_image(Image.load_from_file(ProjectSettings.globalize_path(TEX_DIR + "painting_dusk.png")))
	canvas.roughness = 0.75
	ModelKit.register(canvas)
	k.quad(Vector3(-w * 0.5, h * 0.5, 0.006), Vector3(w * 0.5, h * 0.5, 0.006), Vector3(w * 0.5, -h * 0.5, 0.006), Vector3(-w * 0.5, -h * 0.5, 0.006), "Canvas")
	k.box(Vector3(w + 0.02, h + 0.02, 0.005), Vector3(0, 0, 0.0025), "WoodDark")
	moulded_frame(k, w, h, 0.05, 0.02, 0.0, "Gold")
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			k.ball(Vector3(0.016, 0.016, 0.008), Vector3(sx * (w * 0.5 + 0.025), sy * (h * 0.5 + 0.025), 0.022), "Gold", Vector3.ZERO, 8)
	k.ball(Vector3(0.03, 0.02, 0.01), Vector3(0, h * 0.5 + 0.03, 0.02), "Gold", Vector3.ZERO, 8)


## Arched wall mirror, 0.49 x 0.74 m (back at z = 0): a mirror pane in a gold arch frame with a
## shell crest and little scrolls at the shoulders.
func _mirror(k: ModelKit) -> void:
	var w: float = 0.4
	var spring: float = 0.42
	var bar: float = 0.043
	k.extrude(arch_shape(w, spring, 18), 0.006, "Mirror", ModelKit.T(Vector3(0, 0, 0.008)))
	k.extrude(arch_shape(w + 0.02, spring, 18), 0.006, "WoodDark", ModelKit.T(Vector3(0, -0.01, 0.003)))
	# Frame: sides, bottom, arch, an inner bead.
	for sx: float in [-1.0, 1.0]:
		k.bbox(Vector3(bar, spring + bar, 0.026), 0.008, Vector3(sx * (w * 0.5 + bar * 0.5), (spring - bar) * 0.5, 0.013), "Gold")
	k.bbox(Vector3(w + bar * 2.0, bar, 0.026), 0.008, Vector3(0, -bar * 0.5, 0.013), "Gold")
	arch_band(k, Vector3(0, spring, 0.013), w * 0.5, w * 0.5 + bar, 0.026, 0.0, PI, 18, "Gold")
	arch_band(k, Vector3(0, spring, 0.026), w * 0.5 - 0.006, w * 0.5 + 0.006, 0.012, 0.0, PI, 18, "Gold")
	# Shell crest.
	var crest_y: float = spring + w * 0.5 + bar
	for i: int in 7:
		var a: float = lerpf(PI * 0.15, PI * 0.85, float(i) / 6.0)
		var dir := Vector3(cos(a), sin(a), 0)
		k.ball(Vector3(0.012, 0.045, 0.01), Vector3(0, crest_y - 0.01, 0.024) + dir * 0.035, "Gold", Vector3(0, 0, rad_to_deg(a) - 90.0), 6)
	k.ball(Vector3(0.022, 0.018, 0.014), Vector3(0, crest_y - 0.008, 0.03), "Gold", Vector3.ZERO, 8)
	# Scrolls at the shoulders and the foot.
	for sx: float in [-1.0, 1.0]:
		k.torus(0.012, 0.022, Vector3(sx * (w * 0.5 + bar + 0.012), spring, 0.016), "Gold", Vector3(90, 0, 0), 12, 5)
		k.torus(0.01, 0.019, Vector3(sx * (w * 0.5 + bar * 0.4), -bar - 0.012, 0.016), "Gold", Vector3(90, 0, 0), 12, 5)


# --- Statues ------------------------------------------------------------------------------------

## Marble bust, 0.51 m: round socle with a gold ring, draped shoulders, neck and a stylised
## classical head (laurel wreath, curled hair, nose, brow, ears). Faces +z, turned slightly to -x.
func _bust(k: ModelKit) -> void:
	var m: String = "Marble"
	k.lathe(_pts([Vector2(0, 0), Vector2(0.075, 0), Vector2(0.078, 0.02), Vector2(0.062, 0.03), Vector2(0.045, 0.045),
		Vector2(0.04, 0.07), Vector2(0.052, 0.085), Vector2(0.056, 0.095), Vector2(0, 0.095)]), m, Transform3D.IDENTITY, 18, 40.0)
	k.torus(0.04, 0.047, Vector3(0, 0.068, 0), "Gold", Vector3.ZERO, 18, 5)
	var turn := Vector3(0, -12, 0)
	var xf: Transform3D = ModelKit.T(Vector3(0, 0, 0), turn)
	var sub := ModelKit.new()
	# Chest and shoulders: a wide squashed ellipsoid cut flat at the bottom (lathe dome).
	sub.lathe(_pts([Vector2(0, 0.1), Vector2(0.06, 0.1), Vector2(0.11, 0.12), Vector2(0.135, 0.16), Vector2(0.135, 0.2), Vector2(0.12, 0.235), Vector2(0.08, 0.255), Vector2(0.035, 0.265), Vector2(0, 0.268)]), m, ModelKit.T(Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 1.0, 0.62)), 18, 70.0)
	# Drapery folds across the chest.
	sub.tube(PackedVector3Array([Vector3(-0.118, 0.225, 0.035), Vector3(-0.05, 0.19, 0.078), Vector3(0.04, 0.2, 0.08), Vector3(0.115, 0.24, 0.04)]), 0.01, m, Transform3D.IDENTITY, 8)
	# Neck.
	sub.cyl(0.036, 0.044, 0.08, Vector3(0, 0.29, 0.005), m, Vector3(-8, 0, 0), 12)
	# Head.
	var hc := Vector3(0, 0.39, 0.012)
	sub.ball(Vector3(0.068, 0.085, 0.078), hc, m, Vector3(-6, 0, 0), 16)
	sub.ball(Vector3(0.05, 0.05, 0.05), hc + Vector3(0, -0.045, 0.035), m, Vector3.ZERO, 12)  # jaw
	sub.ball(Vector3(0.022, 0.016, 0.02), hc + Vector3(0, -0.085, 0.045), m, Vector3.ZERO, 8)  # chin
	# Nose: a small wedge.
	sub.extrude(_pts([Vector2(0, 0.0), Vector2(0.014, -0.034), Vector2(-0.014, -0.034)]), 0.022, m, ModelKit.T(hc + Vector3(0, 0.015, 0.08), Vector3(0, 0, 0)), 0.004)
	sub.box(Vector3(0.09, 0.012, 0.02), hc + Vector3(0, 0.022, 0.07), m, Vector3(-10, 0, 0))  # brow
	for sx: float in [-1.0, 1.0]:
		sub.ball(Vector3(0.012, 0.024, 0.016), hc + Vector3(sx * 0.068, -0.005, 0.0), m, Vector3.ZERO, 8)  # ears
	# Curled hair: rows of little balls over the crown and the back.
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for ring_i: int in 4:
		var el: float = lerpf(0.35, 1.35, float(ring_i) / 3.0)
		var count: int = 12 - ring_i * 2
		for j: int in count:
			var az: float = lerpf(-PI * 0.95, PI * 0.95, float(j) / maxf(count - 1, 1))
			var dir := Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el))
			if dir.z > 0.55 and el < 0.6:
				continue  # keep the forehead clear
			var p: Vector3 = hc + Vector3(dir.x * 0.07, dir.y * 0.085 + 0.008, dir.z * 0.08)
			sub.ball(Vector3(0.017, 0.015, 0.017) * rng.randf_range(0.85, 1.15), p, m, Vector3.ZERO, 6)
	# Laurel wreath in gold: two rows of leaves lying along a band around the head.
	for row: int in 2:
		for j: int in 16:
			var az: float = lerpf(-PI * 0.82, PI * 0.82, (float(j) + row * 0.5) / 16.0) + PI
			var dir := Vector3(sin(az), 0, cos(az))
			var p: Vector3 = hc + Vector3(dir.x * 0.071, 0.035 + row * 0.012 - dir.z * 0.012, dir.z * 0.081)
			sub.ball(Vector3(0.016, 0.006, 0.003), p, "Gold", Vector3(0, rad_to_deg(az), 25.0 if row == 0 else -25.0), 6)
	_merge(k, sub, xf)


## Copies every surface of `src` into `dst` through `xf`.
static func _merge(dst: ModelKit, src: ModelKit, xf: Transform3D) -> void:
	for name: String in src._surf:
		var b: Array = src._surf[name]
		dst.tris(b[0], b[1], b[2], xf, name)


## Rearing horse statue, 0.22 m: marble horse on its hind legs on a round dark base with a gold
## rim, the tail flowing down to the base as a support. Faces -z, turned a little to -x.
func _horse(k: ModelKit) -> void:
	var m: String = "Marble"
	k.lathe(_pts([Vector2(0, 0), Vector2(0.075, 0), Vector2(0.078, 0.004), Vector2(0.078, 0.012), Vector2(0.072, 0.016), Vector2(0, 0.016)]), "WoodDark", Transform3D.IDENTITY, 24, 50.0)
	k.torus(0.074, 0.08, Vector3(0, 0.012, 0), "Gold", Vector3.ZERO, 24, 5)
	k.lathe(_pts([Vector2(0, 0.016), Vector2(0.065, 0.016), Vector2(0.06, 0.022), Vector2(0, 0.024)]), m, Transform3D.IDENTITY, 24, 50.0)
	var sub := ModelKit.new()
	# Local frame: horse along -z (head), rearing: body pitched up about 50 degrees.
	var hips := Vector3(0, 0.07, 0.025)
	var pitch: float = 52.0
	var body_dir: Vector3 = Vector3(0, sin(deg_to_rad(pitch)), -cos(deg_to_rad(pitch)))
	var chest: Vector3 = hips + body_dir * 0.075
	var mid: Vector3 = (hips + chest) * 0.5
	sub.ball(Vector3(0.02, 0.023, 0.052), mid, m, Vector3(pitch, 0, 0), 14)
	sub.ball(Vector3(0.021, 0.023, 0.024), hips, m, Vector3.ZERO, 12)
	sub.ball(Vector3(0.019, 0.024, 0.022), chest, m, Vector3.ZERO, 12)
	# Hind legs: thigh, hock, cannon down to the base.
	for sx: float in [-1.0, 1.0]:
		var x: float = sx * 0.014
		sub.tube(PackedVector3Array([hips + Vector3(x, -0.005, 0.0), Vector3(x, 0.05, 0.042), Vector3(x, 0.033, 0.03), Vector3(x, 0.024, 0.012 + sx * 0.006)]), [0.012, 0.007, 0.006, 0.006], m, Transform3D.IDENTITY, 6)
		sub.cyl(0.006, 0.008, 0.006, Vector3(x, 0.026, 0.012 + sx * 0.006), m, Vector3.ZERO, 6)
	# Front legs: raised and bent at the knee.
	for sx: float in [-1.0, 1.0]:
		var x: float = sx * 0.012
		var sh: Vector3 = chest + Vector3(x, -0.012, 0.0)
		var knee: Vector3 = sh + Vector3(0, 0.0 + (0.008 if sx > 0.0 else -0.004), -0.03)
		var hoof: Vector3 = knee + Vector3(0, -0.028, -0.006 + (0.004 if sx > 0.0 else 0.0))
		sub.tube(PackedVector3Array([sh, knee, hoof]), [0.009, 0.006, 0.005], m, Transform3D.IDENTITY, 6)
		sub.cyl(0.005, 0.0065, 0.007, hoof + Vector3(0, -0.003, 0), m, Vector3.ZERO, 6)
	# Neck and head.
	var neck_top: Vector3 = chest + Vector3(0, 0.05, -0.012)
	sub.tube(PackedVector3Array([chest + Vector3(0, 0.01, 0.004), chest + Vector3(0, 0.03, -0.004), neck_top]), [0.019, 0.015, 0.012], m, Transform3D.IDENTITY, 8)
	var head: Vector3 = neck_top + Vector3(0, 0.004, -0.018)
	sub.ball(Vector3(0.012, 0.014, 0.016), head, m, Vector3(-20, 0, 0), 10)
	sub.tube(PackedVector3Array([head, head + Vector3(0, -0.012, -0.022)]), [0.011, 0.008], m, Transform3D.IDENTITY, 8)
	for sx: float in [-1.0, 1.0]:
		sub.cyl(0.0, 0.004, 0.014, head + Vector3(sx * 0.006, 0.016, 0.006), m, Vector3(15, 0, -sx * 10), 5)
	# Mane: a row of little flicks along the neck.
	for j: int in 6:
		var t: float = float(j) / 5.0
		var p: Vector3 = (chest + Vector3(0, 0.02, 0.014)).lerp(neck_top + Vector3(0, 0.01, 0.01), t)
		sub.ball(Vector3(0.004, 0.009, 0.006), p, m, Vector3(-30 - t * 30, 0, 0), 6)
	# Tail sweeping down to the base (supports the statue).
	sub.tube(PackedVector3Array([hips + Vector3(0, 0.005, 0.02), hips + Vector3(0, -0.01, 0.045), Vector3(0.006, 0.03, 0.058), Vector3(0.01, 0.022, 0.05)]), [0.007, 0.009, 0.011, 0.012], m, Transform3D.IDENTITY, 7)
	_merge(k, sub, ModelKit.T(Vector3(0, 0, 0), Vector3(0, 30, 0)))


# --- Items --------------------------------------------------------------------------------------

## Baseball bat, 2.5 units long (scaled down in the hand): turned light wood, black grip tape and a
## gold band, barrel at -y and knob at +y (the grips in ItemModels expect that).
func _bat(k: ModelKit) -> void:
	var L: float = 2.5
	var prof := _pts([
		Vector2(0, 0), Vector2(0.07, 0.0), Vector2(0.11, 0.02), Vector2(0.125, 0.07), Vector2(0.127, 0.5),
		Vector2(0.11, 0.95), Vector2(0.075, 1.35), Vector2(0.052, 1.7), Vector2(0.046, 2.3), Vector2(0.048, 2.36),
		Vector2(0.09, 2.38), Vector2(0.1, 2.42), Vector2(0.085, 2.48), Vector2(0, L)])
	# Lathe in pieces so the grip and band take their own material.
	k.lathe(prof.slice(0, 8), "WoodLight", ModelKit.T(Vector3(0, -L * 0.5, 0)), 14, 30.0)
	k.lathe(_pts([Vector2(0.052, 1.7), Vector2(0.046, 2.3)]), "WoodLight", ModelKit.T(Vector3(0, -L * 0.5, 0)), 14)
	k.lathe(_pts([Vector2(0.052, 1.74), Vector2(0.05, 2.0), Vector2(0.049, 2.3)]), "Black", ModelKit.T(Vector3(0, -L * 0.5 + 0.0, 0), Vector3.ZERO, Vector3(1.08, 1.0, 1.08)), 14)
	k.lathe(prof.slice(8), "WoodLight", ModelKit.T(Vector3(0, -L * 0.5, 0)), 14, 40.0)
	k.lathe(_pts([Vector2(0.077, 1.3), Vector2(0.074, 1.36)]), "Gold", ModelKit.T(Vector3(0, -L * 0.5, 0), Vector3.ZERO, Vector3(1.04, 1.0, 1.04)), 14)
	k.cyl(0.07, 0.07, 0.006, Vector3(0, -L * 0.5 - 0.001, 0), "WoodDark", Vector3.ZERO, 14)


## Gold-plated six-shooter with cream grips, 2 units long, barrel along +x, grip down at -x.
func _revolver(k: ModelKit) -> void:
	# Frame (side profile in xy, extruded along z).
	var frame := _pts([Vector2(-0.55, 0.12), Vector2(-0.05, 0.14), Vector2(0.18, 0.12), Vector2(0.2, 0.0), Vector2(0.15, -0.12),
		Vector2(-0.15, -0.14), Vector2(-0.38, -0.12), Vector2(-0.6, 0.02)])
	k.extrude(frame, 0.16, "Gold", Transform3D.IDENTITY, 0.025)
	# Barrel with a top rib and front sight.
	k.cyl(0.07, 0.07, 1.25, Vector3(0.78, 0.05, 0), "Gold", Vector3(0, 0, 90), 12)
	k.cyl(0.075, 0.075, 0.04, Vector3(1.4, 0.05, 0), "Gold", Vector3(0, 0, 90), 12)
	k.cyl(0.03, 0.03, 0.01, Vector3(1.422, 0.05, 0), "Gunmetal", Vector3(0, 0, 90), 10)
	k.bbox(Vector3(1.2, 0.05, 0.05), 0.012, Vector3(0.78, 0.13, 0), "Gold")
	k.extrude(_pts([Vector2(-0.03, 0), Vector2(0.03, 0), Vector2(0.01, 0.06), Vector2(-0.02, 0.06)]), 0.03, "Gold", ModelKit.T(Vector3(1.36, 0.15, 0)), 0.005)
	# Ejector rod under the barrel.
	k.cyl(0.03, 0.03, 0.7, Vector3(0.55, -0.06, 0), "Gold", Vector3(0, 0, 90), 8)
	# Cylinder: fluted drum with six chamber mouths at the front.
	var drum := PackedVector2Array()
	for i: int in 24:
		var a: float = TAU * i / 24.0
		var r: float = 0.16 if i % 4 != 2 else 0.135
		drum.append(Vector2(cos(a), sin(a)) * r)
	k.extrude(drum, 0.36, "Gunmetal", ModelKit.T(Vector3(0.0, 0.0, 0), Vector3(0, 90, 0)), 0.03)
	for i: int in 6:
		var a: float = TAU * i / 6.0 + TAU / 24.0
		k.cyl(0.035, 0.035, 0.01, Vector3(0.181, cos(a) * 0.09, sin(a) * 0.09), "Black", Vector3(0, 0, 90), 8)
	# Hammer.
	k.extrude(_pts([Vector2(-0.05, 0), Vector2(0.04, 0), Vector2(-0.06, 0.16), Vector2(-0.14, 0.18), Vector2(-0.12, 0.12)]), 0.06, "Gunmetal", ModelKit.T(Vector3(-0.42, 0.1, 0)), 0.01)
	# Trigger guard and trigger.
	var guard := PackedVector3Array()
	for i: int in 11:
		var a: float = lerpf(0.0, PI, float(i) / 10.0)
		guard.append(Vector3(-0.2 + cos(a) * 0.15, -0.13 - sin(a) * 0.17, 0))
	k.tube(guard, 0.022, "Gold", Transform3D.IDENTITY, 6)
	k.tube(PackedVector3Array([Vector3(-0.2, -0.12, 0), Vector3(-0.18, -0.2, 0), Vector3(-0.22, -0.26, 0)]), [0.025, 0.02, 0.015], "Gunmetal", Transform3D.IDENTITY, 6)
	# Grip: a curved bird's-head grip in cream with gold screws and a gold butt cap.
	var grip := _pts([Vector2(-0.38, -0.1), Vector2(-0.6, 0.02), Vector2(-0.78, -0.18), Vector2(-0.9, -0.5), Vector2(-0.9, -0.74),
		Vector2(-0.82, -0.82), Vector2(-0.66, -0.8), Vector2(-0.6, -0.6), Vector2(-0.5, -0.36), Vector2(-0.4, -0.22)])
	k.extrude(grip, 0.2, "Cream", Transform3D.IDENTITY, 0.04)
	k.extrude(_pts([Vector2(-0.9, -0.74), Vector2(-0.82, -0.82), Vector2(-0.66, -0.8), Vector2(-0.68, -0.74), Vector2(-0.84, -0.73)]), 0.22, "Gold", Transform3D.IDENTITY, 0.015)
	for sz: float in [-1.0, 1.0]:
		k.cyl(0.03, 0.03, 0.02, Vector3(-0.68, -0.42, sz * 0.1), "Gold", Vector3(90, 0, 0), 10)


# --- Roulette -----------------------------------------------------------------------------------

## Roulette wheel, 4 m across in its own units (the station scales it by 0.4): its origin is the
## rotor centre and the base sits at y = -0.512 (RouletteStation). A mahogany bowl with a gold rim,
## polished ball track (TRACK_R 1.7, ball centre at y 0.29), gold diamond deflectors on the apron,
## and the separate "Rotor" part that RouletteWheelFx turns: a wooden cone with pocket frets
## round the number ring (RING_R 0.84, at y -0.03) and a gold turret with a four-arm handle.
func _roulette_wheel(k: ModelKit) -> void:
	var base: float = -0.512
	# Bowl outside and rim.
	k.lathe(_pts([Vector2(0, base), Vector2(1.7, base), Vector2(1.82, base + 0.04), Vector2(1.86, base + 0.2),
		Vector2(1.95, base + 0.5), Vector2(2.0, base + 0.82), Vector2(2.0, 0.42)]), "Wood", Transform3D.IDENTITY, 48, 30.0)
	k.lathe(_pts([Vector2(1.9, base + 0.36), Vector2(1.93, base + 0.4), Vector2(1.94, base + 0.44), Vector2(1.92, base + 0.46)]), "Gold", Transform3D.IDENTITY, 48, 70.0)
	k.lathe(_pts([Vector2(2.0, 0.42), Vector2(2.02, 0.44), Vector2(2.02, 0.47), Vector2(1.95, 0.49), Vector2(1.84, 0.49)]), "Gold", Transform3D.IDENTITY, 48, 50.0)
	# Inner wall down to the ball track, track, then the stationary apron down to the rotor.
	k.lathe(_pts([Vector2(1.84, 0.49), Vector2(1.8, 0.47), Vector2(1.79, 0.26), Vector2(1.77, 0.215), Vector2(1.6, 0.2),
		Vector2(1.5, 0.18)]).duplicate(), "WoodDark", Transform3D.IDENTITY, 48, 30.0)
	# Inner faces point inwards: lathe with the profile reversed (top to bottom along the inside).
	var apron := _pts([Vector2(1.5, 0.18), Vector2(1.2, 0.1), Vector2(0.92, 0.02)])
	k.lathe(apron, "Felt", Transform3D.IDENTITY, 48, 30.0)
	for i: int in 8:
		var a: float = TAU * (i + 0.5) / 8.0
		var p := Vector3(sin(a) * 1.25, 0.13, -cos(a) * 1.25)
		var deflector := _pts([Vector2(0, -0.09), Vector2(0.035, 0), Vector2(0, 0.09), Vector2(-0.035, 0)])
		k.extrude(deflector, 0.03, "Gold", Transform3D(Basis.from_euler(Vector3(-PI * 0.5 + 0.26, -a, 0), EULER_ORDER_YXZ), p), 0.008)
	# Rotor (separate node, turned by RouletteWheelFx about y).
	var r := k.part("Rotor")
	r.lathe(_pts([Vector2(0.92, -0.2), Vector2(0.9, 0.0), Vector2(0.86, 0.01), Vector2(0.84, -0.03)]), "Wood", Transform3D.IDENTITY, 48, 40.0)
	r.lathe(_pts([Vector2(0.84, -0.035), Vector2(0.0, -0.035)]), "WoodDark", Transform3D.IDENTITY, 48)
	r.torus(0.85, 0.875, Vector3(0, 0.005, 0), "Gold", Vector3.ZERO, 48, 5)
	# Pocket frets between the numbers (aligned with the ring texture: pocket i at angle i).
	for i: int in 37:
		var a: float = TAU * (i + 0.5) / 37.0
		var p := Vector3(sin(a), 0, -cos(a))
		r.box(Vector3(0.018, 0.05, 0.22), p * 0.61 + Vector3(0, -0.005, 0), "Gold", Vector3(0, -rad_to_deg(a), 0))
	# Centre cone and turret.
	r.lathe(_pts([Vector2(0.52, -0.034), Vector2(0.5, 0.0), Vector2(0.38, 0.08), Vector2(0.22, 0.17), Vector2(0.14, 0.21), Vector2(0.0, 0.215)]), "Wood", Transform3D.IDENTITY, 36, 30.0)
	r.torus(0.48, 0.52, Vector3(0, 0.0, 0), "Gold", Vector3.ZERO, 36, 5)
	r.lathe(_pts([Vector2(0.14, 0.2), Vector2(0.12, 0.24), Vector2(0.06, 0.28), Vector2(0.05, 0.4), Vector2(0.08, 0.46), Vector2(0.05, 0.52),
		Vector2(0.04, 0.64), Vector2(0.07, 0.68), Vector2(0.07, 0.72), Vector2(0.04, 0.76), Vector2(0.0, 0.8)]), "Gold", Transform3D.IDENTITY, 16, 40.0)
	for i: int in 4:
		var a: float = TAU * i / 4.0
		var dir := Vector3(cos(a), 0, sin(a))
		r.tube(PackedVector3Array([Vector3(0, 0.7, 0), dir * 0.2 + Vector3(0, 0.71, 0), dir * 0.32 + Vector3(0, 0.74, 0)]), [0.025, 0.02, 0.018], "Gold", Transform3D.IDENTITY, 8)
		r.ball(Vector3(0.05, 0.05, 0.05), dir * 0.34 + Vector3(0, 0.75, 0), "Gold", Vector3.ZERO, 10)
	r.ball(Vector3(0.045, 0.045, 0.045), Vector3(0, 0.82, 0), "Gold", Vector3.ZERO, 10)
