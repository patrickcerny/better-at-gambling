class_name OutfitMeshKit
extends RefCounted
## Builds one low-poly outfit piece (a hat, a shirt, a pair of boots ...) out of simple parts, each
## part in its own vertex colour, into ONE ArrayMesh: a whole item is a single draw call
## (`OutfitMeshes`). Everything is in the bean body's space (`AvatarVisuals.body`: centre of the
## body at the origin, front is -Z, the body runs from y = -0.7 to +0.7), except boots, which are
## built around the foot's centre.
## Godot treats clockwise triangles as front faces; every hand-made triangle here is turned to face
## along its normals, so nothing comes out inside out.

var verts := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()
var indices := PackedInt32Array()
## Second UVs (a cape's cloth coordinates), one per vertex while `record_uv2` is on: surfaces
## built with `surface_uv2` on get their own (u, v), everything else gets `uv2`.
var uv2s := PackedVector2Array()
var record_uv2: bool = false
var surface_uv2: bool = false
var uv2: Vector2 = Vector2.ZERO
## A surface cell that a pattern edge runs through is split up to this many times each way, as
## far as REFINE_BUDGET allows (busy patterns like plaid get split less, so pieces stay light).
const REFINE: int = 2
## Extra quads the splitting may add, as a share of the surface's own cells.
const REFINE_BUDGET: float = 2.5
## Applied to everything added (hats are built upright around the hat's base, then tipped back).
var xf: Transform3D = Transform3D.IDENTITY


# --- Primitives ---------------------------------------------------------------------------------

## A primitive mesh (sphere, cylinder, box, torus, text ...) placed by `xf`, all in `color`.
func add_primitive(mesh: PrimitiveMesh, place: Transform3D, color: Color) -> void:
	var full: Transform3D = xf * place
	var arr: Array = mesh.get_mesh_arrays()
	if arr.is_empty() or arr[Mesh.ARRAY_VERTEX] == null:
		return
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if idx.is_empty():
		for i: int in v.size():
			idx.append(i)
	var base: int = verts.size()
	var nb: Basis = full.basis.inverse().transposed()
	for i: int in v.size():
		verts.append(full * v[i])
		normals.append((nb * n[i]).normalized() if i < n.size() else Vector3.UP)
		colors.append(color)
		if record_uv2:
			uv2s.append(uv2)
	var flip: bool = full.basis.determinant() < 0.0
	for i: int in range(0, idx.size() - 2, 3):
		indices.append(base + idx[i])
		indices.append(base + (idx[i + 2] if flip else idx[i + 1]))
		indices.append(base + (idx[i + 1] if flip else idx[i + 2]))


## An ellipsoid with radii `radii` at `center` (turned by `basis`).
func sphere(center: Vector3, radii: Vector3, color: Color, segs: int = 10, rings: int = 6, basis: Basis = Basis.IDENTITY) -> void:
	var m := SphereMesh.new()
	m.radius = 1.0
	m.height = 2.0
	m.radial_segments = segs
	m.rings = rings
	add_primitive(m, Transform3D(basis * Basis.from_scale(radii), center), color)


## Half an ellipsoid (the dome of a helmet or a cap): the flat side down at `center`.
func dome(center: Vector3, radii: Vector3, color: Color, segs: int = 12, basis: Basis = Basis.IDENTITY) -> void:
	var m := SphereMesh.new()
	m.radius = 1.0
	m.height = 1.0
	m.is_hemisphere = true
	m.radial_segments = segs
	m.rings = 4
	add_primitive(m, Transform3D(basis * Basis.from_scale(radii), center), color)


## A cylinder (or cone, or frustum) standing on its axis: `center` is its middle; `depth` squashes
## it front to back (1 = round), `basis` turns it.
func cylinder(center: Vector3, r_top: float, r_bottom: float, height: float, color: Color, segs: int = 12, basis: Basis = Basis.IDENTITY, depth: float = 1.0) -> void:
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bottom
	m.height = height
	m.radial_segments = segs
	m.rings = 1
	add_primitive(m, Transform3D(basis * Basis.from_scale(Vector3(1.0, 1.0, depth)), center), color)


func box(center: Vector3, size: Vector3, color: Color, basis: Basis = Basis.IDENTITY) -> void:
	var m := BoxMesh.new()
	m.size = size
	add_primitive(m, Transform3D(basis, center), color)


## A ring lying flat (around Y) at `center`; `depth` squashes it front to back.
func torus(center: Vector3, inner: float, outer: float, color: Color, segs: int = 16, basis: Basis = Basis.IDENTITY, depth: float = 1.0) -> void:
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.ring_segments = 6
	m.rings = segs
	add_primitive(m, Transform3D(basis * Basis.from_scale(Vector3(1.0, 1.0, depth)), center), color)


## A flat 2D shape (`poly`, counter-clockwise in its own XY plane) extruded `thickness` along +Z,
## placed by `xf` (its +Z is the side that faces out).
func prism(poly: PackedVector2Array, thickness: float, place: Transform3D, color: Color) -> void:
	var px: Transform3D = place
	var tris: PackedInt32Array = Geometry2D.triangulate_polygon(poly)
	if tris.is_empty():
		return
	var out: Vector3 = (px.basis * Vector3.BACK).normalized()
	for i: int in range(0, tris.size(), 3):
		var a: Vector2 = poly[tris[i]]
		var b: Vector2 = poly[tris[i + 1]]
		var c: Vector2 = poly[tris[i + 2]]
		tri(px * Vector3(a.x, a.y, thickness), px * Vector3(b.x, b.y, thickness), px * Vector3(c.x, c.y, thickness), out, color)
		tri(px * Vector3(a.x, a.y, 0.0), px * Vector3(b.x, b.y, 0.0), px * Vector3(c.x, c.y, 0.0), -out, color)
	var centre: Vector2 = Vector2.ZERO
	for p: Vector2 in poly:
		centre += p
	centre /= float(poly.size())
	for i: int in poly.size():
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		var mid: Vector2 = (a + b) * 0.5
		var side_dir: Vector2 = Vector2(b.y - a.y, a.x - b.x)
		if side_dir.dot(mid - centre) < 0.0:
			side_dir = -side_dir
		var n: Vector3 = (px.basis * Vector3(side_dir.x, side_dir.y, 0.0)).normalized()
		var p0: Vector3 = px * Vector3(a.x, a.y, 0.0)
		var p1: Vector3 = px * Vector3(b.x, b.y, 0.0)
		var p2: Vector3 = px * Vector3(b.x, b.y, thickness)
		var p3: Vector3 = px * Vector3(a.x, a.y, thickness)
		tri(p0, p1, p2, n, color)
		tri(p0, p2, p3, n, color)


## One triangle facing along `n` (flat).
func tri(a: Vector3, b: Vector3, c: Vector3, n: Vector3, color: Color) -> void:
	tri_n(a, b, c, n, n, n, color)


## One triangle with its own vertex normals; turned so its front faces along them.
func tri_n(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, color: Color, uva: Vector2 = -Vector2.ONE, uvb: Vector2 = -Vector2.ONE, uvc: Vector2 = -Vector2.ONE) -> void:
	if xf != Transform3D.IDENTITY:
		var nbasis: Basis = xf.basis.inverse().transposed()
		a = xf * a
		b = xf * b
		c = xf * c
		na = (nbasis * na).normalized()
		nb = (nbasis * nb).normalized()
		nc = (nbasis * nc).normalized()
	var base: int = verts.size()
	var swap: bool = (b - a).cross(c - a).dot(na + nb + nc) > 0.0
	verts.append(a)
	verts.append(c if swap else b)
	verts.append(b if swap else c)
	normals.append(na)
	normals.append(nc if swap else nb)
	normals.append(nb if swap else nc)
	for i: int in 3:
		colors.append(color)
		indices.append(base + i)
	if record_uv2:
		var own: bool = uva.x >= 0.0
		uv2s.append(uva if own else uv2)
		uv2s.append((uvc if swap else uvb) if own else uv2)
		uv2s.append((uvb if swap else uvc) if own else uv2)


# --- Surfaces -----------------------------------------------------------------------------------

## A smooth surface sampled on a `nu` × `nv` grid: `at(u, v)` gives the point (u, v in 0..1),
## `paint(u, v)` the colour at (u, v) (crisp: stripes and checks stay sharp; cells an edge runs
## through are split finer, `REFINE`), `outward(p)` a direction the front should face at `p`. `closed_u` wraps u around.
func surface(at: Callable, nu: int, nv: int, paint: Callable, outward: Callable, closed_u: bool = false, refine: bool = true) -> void:
	var pts: Array[PackedVector3Array] = []
	var nrm: Array[PackedVector3Array] = []
	var du: float = 1.0 / float(nu)
	var dv: float = 1.0 / float(nv)
	for i: int in nu + 1:
		var col := PackedVector3Array()
		var ncol := PackedVector3Array()
		for j: int in nv + 1:
			var u: float = float(i) / float(nu)
			var v: float = float(j) / float(nv)
			var p: Vector3 = at.call(u, v)
			var pu: Vector3 = at.call(minf(u + du * 0.25, 1.0) if not closed_u else u + du * 0.25, v) - at.call(maxf(u - du * 0.25, 0.0) if not closed_u else u - du * 0.25, v)
			var pv: Vector3 = at.call(u, minf(v + dv * 0.25, 1.0)) - at.call(u, maxf(v - dv * 0.25, 0.0))
			var n: Vector3 = pu.cross(pv)
			var hint: Vector3 = outward.call(p)
			if n.length_squared() < 1e-12:
				n = hint
			n = n.normalized()
			if n.dot(hint) < 0.0:
				n = -n
			col.append(p)
			ncol.append(n)
		pts.append(col)
		nrm.append(ncol)
	# The paint at every grid corner (shared by neighbouring cells): a cell whose corners and centre
	# agree is one quad; one the pattern's edge runs through is split REFINE x REFINE, so lapels,
	# V-necks and ties come out smooth instead of in steps.
	var corner: Array[PackedColorArray] = []
	for i: int in nu + 1:
		var col := PackedColorArray()
		for j: int in nv + 1:
			col.append(paint.call(float(i) / float(nu), float(j) / float(nv)))
		corner.append(col)
	var centre: Array[PackedColorArray] = []
	var edges: int = 0
	for i: int in nu:
		var col := PackedColorArray()
		for j: int in nv:
			var c: Color = paint.call((float(i) + 0.5) / float(nu), (float(j) + 0.5) / float(nv))
			col.append(c)
			if not (_same(corner[i][j], c) and _same(corner[i + 1][j], c) and _same(corner[i + 1][j + 1], c) and _same(corner[i][j + 1], c)):
				edges += 1
		centre.append(col)
	var split: int = 1
	if refine:
		for n: int in range(REFINE, 1, -1):
			if float(edges * (n * n - 1)) <= REFINE_BUDGET * float(nu * nv):
				split = n
				break
	for i: int in nu:
		for j: int in nv:
			var c: Color = centre[i][j]
			var flat: bool = _same(corner[i][j], c) and _same(corner[i + 1][j], c) and _same(corner[i + 1][j + 1], c) and _same(corner[i][j + 1], c)
			var n: int = 1 if flat else split
			if flat:
				if c.a <= 0.0:
					continue  # a hole (cut-outs, ragged edges)
				_quad(pts[i][j], pts[i + 1][j], pts[i + 1][j + 1], pts[i][j + 1], nrm[i][j], nrm[i + 1][j], nrm[i + 1][j + 1], nrm[i][j + 1], c,
						Vector2(float(i) / float(nu), float(j) / float(nv)), Vector2(float(i + 1) / float(nu), float(j + 1) / float(nv)))
				continue
			# A cell an edge runs through: split n x n, and each little quad cut exactly along the
			# edge (marching squares, the crossing found by bisection), so lapels, V-necks and ties
			# come out as clean lines instead of steps.
			var cell := Vector2(float(i), float(j))
			var size := Vector2(float(nu), float(nv))
			var normal_at := func(f: Vector2) -> Vector3:
				return _bilerp(nrm[i][j], nrm[i + 1][j], nrm[i + 1][j + 1], nrm[i][j + 1], f).normalized()
			for si: int in n:
				for sj: int in n:
					_piece(at, normal_at, paint, cell, size, Vector2(float(si) / n, float(sj) / n), Vector2(float(si + 1) / n, float(sj + 1) / n), 1)


## A piece of a split cell from cell fractions `lo` to `hi`: one colour is a quad, two colours are cut
## along their edge, more (where three meet) are split again `depth` more times.
func _piece(at: Callable, normal_at: Callable, paint: Callable, cell: Vector2, size: Vector2, lo: Vector2, hi: Vector2, depth: int) -> void:
	var fs: Array[Vector2] = [lo, Vector2(hi.x, lo.y), hi, Vector2(lo.x, hi.y)]
	var cs: Array[Color] = []
	for f: Vector2 in fs:
		cs.append(paint.call((cell.x + f.x) / size.x, (cell.y + f.y) / size.y))
	var cls: Array[int] = [0, 0, 0, 0]
	var other: int = -1
	var two: bool = true
	for kk: int in range(1, 4):
		if _same(cs[kk], cs[0]):
			continue
		if other < 0:
			other = kk
		if not _same(cs[kk], cs[other]):
			two = false
		cls[kk] = 1
	var flips: int = 0
	for kk: int in 4:
		if cls[kk] != cls[(kk + 1) % 4]:
			flips += 1
	var mid: Vector2 = (lo + hi) * 0.5
	if other < 0:
		# One colour at the corners; the centre decides (a thin stripe can pass between them).
		var cc: Color = paint.call((cell.x + mid.x) / size.x, (cell.y + mid.y) / size.y)
		if not _same(cc, cs[0]) and depth > 0:
			_split4(at, normal_at, paint, cell, size, lo, hi, depth - 1)
			return
		if cs[0].a > 0.0:
			_tri_at(at, normal_at, cell, size, fs[0], fs[1], fs[2], cs[0])
			_tri_at(at, normal_at, cell, size, fs[0], fs[2], fs[3], cs[0])
		return
	if two and flips == 2:
		var polys: Array = [[], []]
		for kk: int in 4:
			polys[cls[kk]].append(fs[kk])
			var nx: int = (kk + 1) % 4
			if cls[kk] != cls[nx]:
				var x: Vector2 = _crossing(paint, cell, size, fs[kk], fs[nx], cs[kk])
				polys[0].append(x)
				polys[1].append(x)
		for side: int in 2:
			var col: Color = cs[0] if side == 0 else cs[other]
			if col.a <= 0.0:
				continue
			var poly: Array = polys[side]
			for m: int in range(1, poly.size() - 1):
				_tri_at(at, normal_at, cell, size, poly[0], poly[m], poly[m + 1], col)
		return
	if depth > 0:
		_split4(at, normal_at, paint, cell, size, lo, hi, depth - 1)
		return
	# Three colours or a saddle, small enough: two triangles, each in the paint at its own centre.
	for tri: int in 2:
		var p0: Vector2 = fs[0]
		var p1: Vector2 = fs[1] if tri == 0 else fs[2]
		var p2: Vector2 = fs[2] if tri == 0 else fs[3]
		var g: Vector2 = (p0 + p1 + p2) / 3.0
		var tc: Color = paint.call((cell.x + g.x) / size.x, (cell.y + g.y) / size.y)
		if tc.a > 0.0:
			_tri_at(at, normal_at, cell, size, p0, p1, p2, tc)


func _split4(at: Callable, normal_at: Callable, paint: Callable, cell: Vector2, size: Vector2, lo: Vector2, hi: Vector2, depth: int) -> void:
	var mid: Vector2 = (lo + hi) * 0.5
	_piece(at, normal_at, paint, cell, size, lo, mid, depth)
	_piece(at, normal_at, paint, cell, size, Vector2(mid.x, lo.y), Vector2(hi.x, mid.y), depth)
	_piece(at, normal_at, paint, cell, size, mid, hi, depth)
	_piece(at, normal_at, paint, cell, size, Vector2(lo.x, mid.y), Vector2(mid.x, hi.y), depth)


## One flat quad of the grid (corners counter-clockwise from (u0, v0)); `uv_lo`/`uv_hi` its uv2 corners.
func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3, col: Color, uv_lo: Vector2, uv_hi: Vector2) -> void:
	if surface_uv2:
		tri_n(a, b, c, na, nb, nc, col, uv_lo, Vector2(uv_hi.x, uv_lo.y), uv_hi)
		tri_n(a, c, d, na, nc, nd, col, uv_lo, uv_hi, Vector2(uv_lo.x, uv_hi.y))
	else:
		tri_n(a, b, c, na, nb, nc, col)
		tri_n(a, c, d, na, nc, nd, col)


## A triangle inside cell `cell` at cell fractions `fa`, `fb`, `fc` (points taken from the shape itself).
func _tri_at(at: Callable, normal_at: Callable, cell: Vector2, size: Vector2, fa: Vector2, fb: Vector2, fc: Vector2, col: Color) -> void:
	var ua: Vector2 = (cell + fa) / size
	var ub: Vector2 = (cell + fb) / size
	var uc: Vector2 = (cell + fc) / size
	var pa: Vector3 = at.call(ua.x, ua.y)
	var pb: Vector3 = at.call(ub.x, ub.y)
	var pc: Vector3 = at.call(uc.x, uc.y)
	if surface_uv2:
		tri_n(pa, pb, pc, normal_at.call(fa), normal_at.call(fb), normal_at.call(fc), col, ua, ub, uc)
	else:
		tri_n(pa, pb, pc, normal_at.call(fa), normal_at.call(fb), normal_at.call(fc), col)


## Where the paint changes between cell fractions `fa` (painted `ca`) and `fb`, by bisection. The
## search always runs from the smaller end, so the two quads sharing a side find the same point.
static func _crossing(paint: Callable, cell: Vector2, size: Vector2, fa: Vector2, fb: Vector2, ca: Color) -> Vector2:
	var lo: Vector2 = fa
	var hi: Vector2 = fb
	var lo_is_a: bool = true
	if fb.x < fa.x or (fb.x == fa.x and fb.y < fa.y):
		lo = fb
		hi = fa
		lo_is_a = false
	var t0: float = 0.0
	var t1: float = 1.0
	for _it: int in 7:
		var tm: float = (t0 + t1) * 0.5
		var f: Vector2 = lo.lerp(hi, tm)
		var on_a: bool = _same(paint.call((cell.x + f.x) / size.x, (cell.y + f.y) / size.y), ca)
		if on_a == lo_is_a:
			t0 = tm
		else:
			t1 = tm
	return lo.lerp(hi, (t0 + t1) * 0.5)


## Whether two paints read as the same colour (soft shading inside a cell is no edge worth splitting).
static func _same(a: Color, b: Color) -> bool:
	return (a.a > 0.0) == (b.a > 0.0) and absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) < 0.12


static func _bilerp(a: Vector3, b: Vector3, c: Vector3, d: Vector3, f: Vector2) -> Vector3:
	return a.lerp(b, f.x).lerp(d.lerp(c, f.x), f.y)


## A point on the bean's surface (`AvatarVisuals`), `inflate` metres further out: `t` is the height
## (0 = bottom, 1 = top), `a` the angle around the body from the front (0 = front centre, +PI/2 =
## the bean's left, the viewer's right when facing it).
static func body_point(t: float, a: float, inflate: float) -> Vector3:
	t = body_t(t)
	var r: float = AvatarVisuals.radius_at(t) + inflate
	return Vector3(sin(a) * r, (t - 0.5) * AvatarVisuals.BODY_HEIGHT, AvatarVisuals.bend_at(t) - cos(a) * r * AvatarVisuals.BODY_DEPTH)


## Pattern heights to body heights: the clothes are drawn on a "pattern" scale (trousers up to
## 0.205, shirts 0.17 .. 0.40 at the front, 0.60 at the back) and worn a little higher and fuller on
## the bean, so the trousers show below the belly and the shirt reaches up to the mouth.
const T_MAP: PackedVector2Array = [Vector2(0.0, 0.0), Vector2(0.17, 0.25), Vector2(0.4, 0.43), Vector2(0.6, 0.62), Vector2(1.0, 1.0)]


static func body_t(t: float) -> float:
	for i: int in range(1, T_MAP.size()):
		if t <= T_MAP[i].x or i == T_MAP.size() - 1:
			var f: float = clampf((t - T_MAP[i - 1].x) / (T_MAP[i].x - T_MAP[i - 1].x), 0.0, 1.0)
			return lerpf(T_MAP[i - 1].y, T_MAP[i].y, f)
	return t


## The outward direction of the bean's surface at `p` (good enough to orient cloth).
static func body_out(p: Vector3) -> Vector3:
	return Vector3(p.x, p.y * 0.35, p.z + 0.03)


## Where something flat sits on the body surface: origin on the skin (+`inflate`), +Z out of the
## body, +Y up along it, +X sideways. Emblems and buttons go here.
static func body_frame(t: float, a: float, inflate: float) -> Transform3D:
	var p: Vector3 = body_point(t, a, inflate)
	var up: Vector3 = (body_point(t + 0.01, a, inflate) - body_point(t - 0.01, a, inflate)).normalized()
	var side: Vector3 = (body_point(t, a + 0.02, inflate) - body_point(t, a - 0.02, inflate)).normalized()
	var out: Vector3 = side.cross(up).normalized()
	if out.dot(body_out(p)) < 0.0:
		out = -out
	side = up.cross(out).normalized()
	return Transform3D(Basis(side, up, out), p)


## Cloth around the body between heights `t0` and `top(a)` (a band: a shirt, trousers, a skirt).
## `top` is a Callable(a) -> t (a neckline), `paint(t, a)` the colour, `flare` extra width at the
## bottom edge (skirts, coat tails). The inside is drawn too, a shade darker, so open edges don't
## show a hole.
func band(t0: float, top: Callable, inflate: float, paint: Callable, flare: float = 0.0, nu: int = 48, nv: int = 30) -> void:
	var t_max: float = t0
	for i: int in 64:
		t_max = maxf(t_max, top.call((float(i) / 64.0 - 0.5) * TAU))
	for side: int in 2:
		var off: float = inflate if side == 0 else inflate - 0.006
		# Rows sit at fixed heights (stripes stay straight); above the neckline they fold onto it.
		var at := func(u: float, v: float) -> Vector3:
			var a: float = (u - 0.5) * TAU
			var t: float = minf(lerpf(t0, t_max, v), top.call(a))
			var below: float = clampf((t - t0) / maxf(t_max - t0, 0.001), 0.0, 1.0)
			return body_point(t, a, off + flare * pow(1.0 - below, 2.0))
		var pt := func(u: float, v: float) -> Color:
			var a: float = (u - 0.5) * TAU
			var t: float = lerpf(t0, t_max, v)
			if t > top.call(a) + 0.5 * (t_max - t0) / float(nv):
				return Color(0, 0, 0, 0)  # folded away above the neckline
			var c: Color = paint.call(minf(t, top.call(a)), a)
			return c if side == 0 else Color(c.darkened(0.45), c.a)
		var out := func(p: Vector3) -> Vector3:
			return body_out(p) if side == 0 else -body_out(p)
		surface(at, nu, nv, pt, out, true, side == 0)  # the inside only shows at the hems: no splitting


## A neckline: `front` height at the front centre, `back` at the back, `v` > 0 cuts a V.
static func neckline(front: float, back: float, v: float = 0.0) -> Callable:
	return func(a: float) -> float:
		var f: float = (1.0 + cos(a)) * 0.5  # 1 at the front, 0 at the back
		return lerpf(back, front, pow(f, 2.5)) - v * pow(maxf(cos(a), 0.0), 10.0)


## A flat height (a waistband).
static func level(t: float) -> Callable:
	return func(_a: float) -> float:
		return t


# --- Output -------------------------------------------------------------------------------------

## The same piece mirrored left to right (boots for the other foot).
func mirrored() -> OutfitMeshKit:
	var k := OutfitMeshKit.new()
	for i: int in verts.size():
		k.verts.append(Vector3(-verts[i].x, verts[i].y, verts[i].z))
		k.normals.append(Vector3(-normals[i].x, normals[i].y, normals[i].z))
	k.colors = colors.duplicate()
	for i: int in range(0, indices.size(), 3):
		k.indices.append(indices[i])
		k.indices.append(indices[i + 2])
		k.indices.append(indices[i + 1])
	return k


func is_empty() -> bool:
	return indices.is_empty()


func commit() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if indices.is_empty():
		return mesh
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_INDEX] = indices
	if uv2s.size() == verts.size():
		arr[Mesh.ARRAY_TEX_UV2] = uv2s
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


# --- 2D shapes for emblems ----------------------------------------------------------------------

static func star_poly(points: int, r_out: float, r_in: float) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i: int in points * 2:
		var a: float = PI * 0.5 + PI * float(i) / float(points)
		var r: float = r_out if i % 2 == 0 else r_in
		p.append(Vector2(cos(a), sin(a)) * r)
	return p


static func heart_poly(size: float) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i: int in 24:
		var t: float = TAU * float(i) / 24.0
		var x: float = 16.0 * pow(sin(t), 3.0)
		var y: float = 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
		p.append(Vector2(x, y) * size / 32.0)
	return p


static func diamond_poly(w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(0, h), Vector2(-w, 0), Vector2(0, -h), Vector2(w, 0)])


## A spade: an upside-down heart with a little stem.
static func spade_poly(size: float) -> PackedVector2Array:
	var p := PackedVector2Array()
	var heart: PackedVector2Array = heart_poly(size)
	for i: int in heart.size():
		var q: Vector2 = heart[i]
		p.append(Vector2(q.x, -q.y + size * 0.12))
	return p


static func circle_poly(r: float, n: int = 12) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i: int in n:
		var a: float = TAU * float(i) / float(n)
		p.append(Vector2(cos(a), sin(a)) * r)
	return p


static func rect_poly(w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(-w, -h), Vector2(w, -h), Vector2(w, h), Vector2(-w, h)])


static func cross_poly(arm: float, thick: float) -> PackedVector2Array:
	var a: float = arm
	var t: float = thick
	return PackedVector2Array([
		Vector2(-t, a), Vector2(-t, t), Vector2(-a, t), Vector2(-a, -t), Vector2(-t, -t), Vector2(-t, -a * 1.4),
		Vector2(t, -a * 1.4), Vector2(t, -t), Vector2(a, -t), Vector2(a, t), Vector2(t, t), Vector2(t, a),
	])
