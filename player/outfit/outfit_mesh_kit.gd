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
func tri_n(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, color: Color) -> void:
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


# --- Surfaces -----------------------------------------------------------------------------------

## A smooth surface sampled on a `nu` × `nv` grid: `at(u, v)` gives the point (u, v in 0..1),
## `paint(u, v)` the colour of the cell around (u, v) (crisp per cell: stripes and checks stay
## sharp), `outward(p)` a direction the front should face at `p`. `closed_u` wraps u around.
func surface(at: Callable, nu: int, nv: int, paint: Callable, outward: Callable, closed_u: bool = false) -> void:
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
	for i: int in nu:
		for j: int in nv:
			var c: Color = paint.call((float(i) + 0.5) / float(nu), (float(j) + 0.5) / float(nv))
			if c.a <= 0.0:
				continue  # a hole (cut-outs, ragged edges)
			var a: Vector3 = pts[i][j]
			var b: Vector3 = pts[i + 1][j]
			var cc: Vector3 = pts[i + 1][j + 1]
			var d: Vector3 = pts[i][j + 1]
			tri_n(a, b, cc, nrm[i][j], nrm[i + 1][j], nrm[i + 1][j + 1], c)
			tri_n(a, cc, d, nrm[i][j], nrm[i + 1][j + 1], nrm[i][j + 1], c)


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
func band(t0: float, top: Callable, inflate: float, paint: Callable, flare: float = 0.0, nu: int = 40, nv: int = 30) -> void:
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
		surface(at, nu, nv, pt, out, true)


## A neckline: `front` height at the front centre, `back` at the back, `v` > 0 cuts a V.
static func neckline(front: float, back: float, v: float = 0.0) -> Callable:
	return func(a: float) -> float:
		var f: float = (1.0 + cos(a)) * 0.5  # 1 at the front, 0 at the back
		return lerpf(back, front, pow(f, 0.6)) - v * pow(maxf(cos(a), 0.0), 10.0)


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
