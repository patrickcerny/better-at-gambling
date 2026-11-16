class_name ModelKit
extends RefCounted
## Builds our own low-poly prop models out of code: turned (lathe) profiles, bevelled extrusions,
## swept tubes and primitive parts, merged into one mesh with one surface per material, so a
## whole stool or door is one draw call per material. `tools/models/build_models.gd` writes each
## recipe of `PropRecipes` to a .glb under `assets/models/own/`.
##
## Material names matter: game code recolours props by them (`LoungeDecor._recolor`), so the
## palette names here are the contract ("Marble", "Wood", "Gold", "Fabric", "Glass", ...).

## name -> [albedo, metallic, roughness, emission energy, alpha]
const PALETTE: Dictionary = {
	"Gold": [Color(0.84, 0.64, 0.3), 0.85, 0.3, 0.0, 1.0],
	"Brass": [Color(0.66, 0.5, 0.26), 0.8, 0.38, 0.0, 1.0],
	"Bronze": [Color(0.42, 0.28, 0.16), 0.75, 0.42, 0.0, 1.0],
	"Steel": [Color(0.55, 0.55, 0.57), 0.85, 0.35, 0.0, 1.0],
	"Gunmetal": [Color(0.2, 0.2, 0.22), 0.8, 0.4, 0.0, 1.0],
	"Marble": [Color(0.93, 0.9, 0.84), 0.0, 0.32, 0.0, 1.0],
	"Stone": [Color(0.86, 0.82, 0.74), 0.0, 0.55, 0.0, 1.0],
	"White": [Color(0.93, 0.89, 0.8), 0.0, 0.6, 0.0, 1.0],
	"Cream": [Color(0.95, 0.9, 0.79), 0.0, 0.55, 0.0, 1.0],
	"Wood": [Color(0.38, 0.17, 0.09), 0.0, 0.5, 0.0, 1.0],
	"WoodDark": [Color(0.2, 0.1, 0.06), 0.0, 0.5, 0.0, 1.0],
	"WoodLight": [Color(0.62, 0.4, 0.22), 0.0, 0.55, 0.0, 1.0],
	"Fabric": [Color(0.45, 0.11, 0.15), 0.0, 0.9, 0.0, 1.0],
	"Leather": [Color(0.3, 0.09, 0.1), 0.0, 0.45, 0.0, 1.0],
	"LeatherBrown": [Color(0.4, 0.22, 0.12), 0.0, 0.6, 0.0, 1.0],
	"Felt": [Color(0.15, 0.37, 0.28), 0.0, 0.95, 0.0, 1.0],
	"Red": [Color(0.78, 0.22, 0.2), 0.0, 0.5, 0.0, 1.0],
	"Black": [Color(0.08, 0.075, 0.075), 0.0, 0.45, 0.0, 1.0],
	"Charcoal": [Color(0.14, 0.13, 0.12), 0.0, 0.6, 0.0, 1.0],
	"Leaf": [Color(0.2, 0.42, 0.18), 0.0, 0.7, 0.0, 1.0],
	"LeafLight": [Color(0.38, 0.58, 0.24), 0.0, 0.7, 0.0, 1.0],
	"LeafDark": [Color(0.11, 0.27, 0.13), 0.0, 0.75, 0.0, 1.0],
	"Soil": [Color(0.17, 0.11, 0.07), 0.0, 1.0, 0.0, 1.0],
	"Petal": [Color(0.86, 0.24, 0.3), 0.0, 0.7, 0.0, 1.0],
	"PetalCream": [Color(0.97, 0.92, 0.8), 0.0, 0.7, 0.0, 1.0],
	"Orange": [Color(0.93, 0.42, 0.13), 0.0, 0.55, 0.0, 1.0],
	"Glass": [Color(0.75, 0.82, 0.8), 0.1, 0.08, 0.0, 0.35],
	"Mirror": [Color(0.62, 0.62, 0.6), 1.0, 0.04, 0.0, 1.0],
	"Beer": [Color(0.93, 0.62, 0.16), 0.0, 0.2, 0.0, 0.85],
	"Foam": [Color(0.99, 0.96, 0.88), 0.0, 0.8, 0.0, 1.0],
	"Screen": [Color(0.1, 0.22, 0.2), 0.0, 0.3, 0.6, 1.0],
	"Coin": [Color(0.95, 0.74, 0.28), 0.9, 0.28, 0.0, 1.0],
	"ChipBody": [Color(0.12, 0.11, 0.11), 0.0, 0.4, 0.0, 1.0],
	"ChipStripe": [Color(0.95, 0.9, 0.79), 0.0, 0.45, 0.0, 1.0],
	"ChipInlay": [Color(0.78, 0.22, 0.2), 0.0, 0.45, 0.0, 1.0],
	"Bill": [Color(0.5, 0.66, 0.45), 0.0, 0.8, 0.0, 1.0],
}

## Extra materials a recipe made itself (textured ones), by name.
static var _extra: Dictionary = {}
static var _shared: Dictionary = {}

## mat name -> [verts, normals, uvs]
var _surf: Dictionary = {}
## Child parts that stay separate nodes (a rotor that turns): name -> [ModelKit, Transform3D].
var _children: Array = []


## The shared material `name` (from PALETTE or registered with `register`).
static func mat(name: String) -> Material:
	if _extra.has(name):
		return _extra[name]
	if _shared.has(name):
		return _shared[name]
	var p: Array = PALETTE.get(name, [Color.MAGENTA, 0.0, 0.5, 0.0, 1.0])
	var m := StandardMaterial3D.new()
	m.resource_name = name
	m.albedo_color = Color(p[0], p[4])
	m.metallic = p[1]
	m.roughness = p[2]
	if p[3] > 0.0:
		m.emission_enabled = true
		m.emission = p[0]
		m.emission_energy_multiplier = p[3]
	if p[4] < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shared[name] = m
	return m


static func register(m: Material) -> void:
	_extra[m.resource_name] = m


## Transform from a position, rotation in degrees (applied Y, X, Z like Node3D) and scale.
static func T(pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> Transform3D:
	var b := Basis.from_euler(rot_deg * (PI / 180.0)).scaled(scl)
	return Transform3D(b, pos)


## A separate child part (its own MeshInstance3D, named `name`) placed at `xf`.
func part(name: String, xf: Transform3D = Transform3D.IDENTITY) -> ModelKit:
	var k := ModelKit.new()
	_children.append([name, k, xf])
	return k


# --- Raw triangles ------------------------------------------------------------------------------

func _bucket(mat_name: String) -> Array:
	if not _surf.has(mat_name):
		_surf[mat_name] = [PackedVector3Array(), PackedVector3Array(), PackedVector2Array()]
	return _surf[mat_name]


## Adds triangles (three vertices each, Godot's clockwise front faces) through `xf`.
func tris(verts: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, xf: Transform3D, mat_name: String) -> void:
	var b: Array = _bucket(mat_name)
	var nb: Basis = xf.basis.inverse().transposed()
	var flip: bool = xf.basis.determinant() < 0.0
	var n: int = verts.size()
	var i: int = 0
	while i < n:
		var order: Array = [0, 2, 1] if flip else [0, 1, 2]
		for k: int in order:
			b[0].append(xf * verts[i + k])
			b[1].append((nb * normals[i + k]).normalized())
			b[2].append(uvs[i + k] if i + k < uvs.size() else Vector2.ZERO)
		i += 3


## A quad a-b-c-d (clockwise seen from the front) with one flat normal.
func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, mat_name: String, xf: Transform3D = Transform3D.IDENTITY, uv: Rect2 = Rect2(0, 0, 1, 1)) -> void:
	var n: Vector3 = (c - a).cross(b - a).normalized()
	var u0: Vector2 = uv.position
	var u1: Vector2 = uv.end
	tris(PackedVector3Array([a, b, c, a, c, d]), PackedVector3Array([n, n, n, n, n, n]),
		PackedVector2Array([Vector2(u0.x, u0.y), Vector2(u1.x, u0.y), Vector2(u1.x, u1.y), Vector2(u0.x, u0.y), Vector2(u1.x, u1.y), Vector2(u0.x, u1.y)]), xf, mat_name)


## A Godot primitive (BoxMesh, SphereMesh, CylinderMesh, TorusMesh, PrismMesh...) through `xf`.
func prim(mesh: PrimitiveMesh, xf: Transform3D, mat_name: String) -> void:
	var arr: Array = mesh.get_mesh_arrays()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var nn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var ov := PackedVector3Array()
	var on := PackedVector3Array()
	var ou := PackedVector2Array()
	if idx.is_empty():
		for i: int in v.size():
			idx.append(i)
	for i: int in idx:
		ov.append(v[i])
		on.append(nn[i])
		ou.append(uv[i] if i < uv.size() else Vector2.ZERO)
	tris(ov, on, ou, xf, mat_name)


# --- Shapes -------------------------------------------------------------------------------------

func box(size: Vector3, pos: Vector3, mat_name: String, rot: Vector3 = Vector3.ZERO) -> void:
	var m := BoxMesh.new()
	m.size = size
	prim(m, T(pos, rot), mat_name)


## A box with chamfered edges (`bevel` metres), flat shaded.
func bbox(size: Vector3, bevel: float, pos: Vector3, mat_name: String, rot: Vector3 = Vector3.ZERO) -> void:
	var b: float = minf(bevel, minf(size.x, minf(size.y, size.z)) * 0.45)
	var h := size * 0.5
	var pts := PackedVector2Array([
		Vector2(-h.x + b, -h.y), Vector2(h.x - b, -h.y), Vector2(h.x, -h.y + b), Vector2(h.x, h.y - b),
		Vector2(h.x - b, h.y), Vector2(-h.x + b, h.y), Vector2(-h.x, h.y - b), Vector2(-h.x, -h.y + b)])
	extrude(pts, size.z, mat_name, T(pos, rot), b)


func cyl(r_top: float, r_bottom: float, h: float, pos: Vector3, mat_name: String, rot: Vector3 = Vector3.ZERO, segs: int = 16) -> void:
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bottom
	m.height = h
	m.radial_segments = segs
	m.rings = 1
	prim(m, T(pos, rot), mat_name)


## An ellipsoid with radii `r`.
func ball(r: Vector3, pos: Vector3, mat_name: String, rot: Vector3 = Vector3.ZERO, segs: int = 12) -> void:
	var m := SphereMesh.new()
	m.radius = 1.0
	m.height = 2.0
	m.radial_segments = segs
	m.rings = maxi(segs / 2, 4)
	prim(m, T(pos, rot, r), mat_name)


func torus(inner: float, outer: float, pos: Vector3, mat_name: String, rot: Vector3 = Vector3.ZERO, rings: int = 24, ring_segs: int = 8, scl: Vector3 = Vector3.ONE) -> void:
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.rings = rings
	m.ring_segments = ring_segs
	prim(m, T(pos, rot, scl), mat_name)


## A turned shape: `profile` is (radius, height) points from the bottom up along the outside
## (radius 0 closes an end). Corners sharper than `crease` degrees stay hard.
func lathe(profile: PackedVector2Array, mat_name: String, xf: Transform3D = Transform3D.IDENTITY, segs: int = 24, crease: float = 35.0, arc: float = TAU) -> void:
	var np: int = profile.size()
	# Per segment 2D outward normals.
	var seg_n: Array[Vector2] = []
	for i: int in np - 1:
		var t: Vector2 = profile[i + 1] - profile[i]
		seg_n.append(Vector2(t.y, -t.x).normalized())
	var cos_c: float = cos(deg_to_rad(crease))
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var total: float = 0.0
	var acc: Array[float] = [0.0]
	for i: int in np - 1:
		total += profile[i].distance_to(profile[i + 1])
		acc.append(total)
	for i: int in np - 1:
		var n0: Vector2 = seg_n[i]
		var n1: Vector2 = seg_n[i]
		if i > 0 and seg_n[i - 1].dot(seg_n[i]) > cos_c:
			n0 = (seg_n[i - 1] + seg_n[i]).normalized()
		if i < np - 2 and seg_n[i + 1].dot(seg_n[i]) > cos_c:
			n1 = (seg_n[i + 1] + seg_n[i]).normalized()
		var p0: Vector2 = profile[i]
		var p1: Vector2 = profile[i + 1]
		for s: int in segs:
			var a0: float = arc * float(s) / segs
			var a1: float = arc * float(s + 1) / segs
			var c0 := Vector2(cos(a0), sin(a0))
			var c1 := Vector2(cos(a1), sin(a1))
			var v00 := Vector3(p0.x * c0.x, p0.y, p0.x * c0.y)
			var v01 := Vector3(p0.x * c1.x, p0.y, p0.x * c1.y)
			var v10 := Vector3(p1.x * c0.x, p1.y, p1.x * c0.y)
			var v11 := Vector3(p1.x * c1.x, p1.y, p1.x * c1.y)
			var m00 := Vector3(n0.x * c0.x, n0.y, n0.x * c0.y)
			var m01 := Vector3(n0.x * c1.x, n0.y, n0.x * c1.y)
			var m10 := Vector3(n1.x * c0.x, n1.y, n1.x * c0.y)
			var m11 := Vector3(n1.x * c1.x, n1.y, n1.x * c1.y)
			var u0: float = float(s) / segs
			var u1: float = float(s + 1) / segs
			var w0: float = acc[i] / maxf(total, 0.0001)
			var w1: float = acc[i + 1] / maxf(total, 0.0001)
			verts.append_array([v00, v11, v10, v00, v01, v11])
			norms.append_array([m00, m11, m10, m00, m01, m11])
			uvs.append_array([Vector2(u0, w0), Vector2(u1, w1), Vector2(u0, w1), Vector2(u0, w0), Vector2(u1, w0), Vector2(u1, w1)])
	tris(verts, norms, uvs, xf, mat_name)


## A flat polygon (x, y; counter-clockwise) extruded `depth` along z (centred), front at +z,
## with a `bevel` chamfer around both faces.
func extrude(poly: PackedVector2Array, depth: float, mat_name: String, xf: Transform3D = Transform3D.IDENTITY, bevel: float = 0.0, side_mat: String = "", back: bool = true) -> void:
	var pts: PackedVector2Array = poly
	if Geometry2D.is_polygon_clockwise(pts):
		pts.reverse()
	var sm: String = side_mat if side_mat != "" else mat_name
	var hz: float = depth * 0.5
	var inner: PackedVector2Array = _inset(pts, bevel) if bevel > 0.0 else pts
	var zf: float = hz
	var zs: float = hz - bevel if bevel > 0.0 else hz
	var tri: PackedInt32Array = Geometry2D.triangulate_polygon(inner)
	var bounds: Rect2 = Rect2(pts[0], Vector2.ZERO)
	for p: Vector2 in pts:
		bounds = bounds.expand(p)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	# Caps (front: +z, back: -z). Counter-clockwise in xy seen from +z is front-facing for Godot
	# when emitted in reverse order.
	var i: int = 0
	while i < tri.size():
		for k: int in [2, 1, 0]:
			var p: Vector2 = inner[tri[i + k]]
			verts.append(Vector3(p.x, p.y, zf))
			norms.append(Vector3.BACK)
			uvs.append(Vector2((p.x - bounds.position.x) / maxf(bounds.size.x, 1e-5), 1.0 - (p.y - bounds.position.y) / maxf(bounds.size.y, 1e-5)))
		if back:
			for k: int in [0, 1, 2]:
				var p: Vector2 = inner[tri[i + k]]
				verts.append(Vector3(p.x, p.y, -zf))
				norms.append(Vector3.FORWARD)
				uvs.append(Vector2(1.0 - (p.x - bounds.position.x) / maxf(bounds.size.x, 1e-5), 1.0 - (p.y - bounds.position.y) / maxf(bounds.size.y, 1e-5)))
		i += 3
	tris(verts, norms, uvs, xf, mat_name)
	# Sides and chamfers.
	var n: int = pts.size()
	for j: int in n:
		var a: Vector2 = pts[j]
		var b: Vector2 = pts[(j + 1) % n]
		quad(Vector3(a.x, a.y, zs), Vector3(b.x, b.y, zs), Vector3(b.x, b.y, -zs), Vector3(a.x, a.y, -zs), sm, xf)
		if bevel > 0.0:
			var ia: Vector2 = inner[j]
			var ib: Vector2 = inner[(j + 1) % n]
			quad(Vector3(ia.x, ia.y, zf), Vector3(ib.x, ib.y, zf), Vector3(b.x, b.y, zs), Vector3(a.x, a.y, zs), sm, xf)
			if back:
				quad(Vector3(a.x, a.y, -zs), Vector3(b.x, b.y, -zs), Vector3(ib.x, ib.y, -zf), Vector3(ia.x, ia.y, -zf), sm, xf)


## Offsets a counter-clockwise polygon inwards by `d` (mitred, clamped).
static func _inset(pts: PackedVector2Array, d: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n: int = pts.size()
	for i: int in n:
		var p0: Vector2 = pts[(i - 1 + n) % n]
		var p1: Vector2 = pts[i]
		var p2: Vector2 = pts[(i + 1) % n]
		var e0: Vector2 = (p1 - p0).normalized()
		var e1: Vector2 = (p2 - p1).normalized()
		var n0 := Vector2(-e0.y, e0.x)
		var n1 := Vector2(-e1.y, e1.x)
		var bis: Vector2 = (n0 + n1)
		if bis.length() < 1e-4:
			bis = n0
		bis = bis.normalized()
		var k: float = d / maxf(bis.dot(n0), 0.35)
		out.append(p1 + bis * k)
	return out


## A tube swept along `path` with radius `radii[i]` (or one radius), `segs` sides, capped ends.
func tube(path: PackedVector3Array, radii: Variant, mat_name: String, xf: Transform3D = Transform3D.IDENTITY, segs: int = 8, caps: bool = true) -> void:
	var n: int = path.size()
	if n < 2:
		return
	var rs: Array[float] = []
	for i: int in n:
		rs.append(float(radii[i]) if radii is Array or radii is PackedFloat32Array else float(radii))
	# Parallel-transport frames.
	var tangents: Array[Vector3] = []
	for i: int in n:
		var t: Vector3 = (path[mini(i + 1, n - 1)] - path[maxi(i - 1, 0)]).normalized()
		tangents.append(t)
	var ref: Vector3 = Vector3.UP if absf(tangents[0].dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var normal: Vector3 = tangents[0].cross(ref).normalized()
	var frames: Array = []
	for i: int in n:
		if i > 0:
			var axis: Vector3 = tangents[i - 1].cross(tangents[i])
			if axis.length() > 1e-6:
				var ang: float = tangents[i - 1].angle_to(tangents[i])
				normal = normal.rotated(axis.normalized(), ang)
		var binorm: Vector3 = tangents[i].cross(normal).normalized()
		frames.append([normal, binorm])
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	for i: int in n - 1:
		for s: int in segs:
			var a0: float = TAU * s / segs
			var a1: float = TAU * (s + 1) / segs
			var d00: Vector3 = frames[i][0] * cos(a0) + frames[i][1] * sin(a0)
			var d01: Vector3 = frames[i][0] * cos(a1) + frames[i][1] * sin(a1)
			var d10: Vector3 = frames[i + 1][0] * cos(a0) + frames[i + 1][1] * sin(a0)
			var d11: Vector3 = frames[i + 1][0] * cos(a1) + frames[i + 1][1] * sin(a1)
			var v00: Vector3 = path[i] + d00 * rs[i]
			var v01: Vector3 = path[i] + d01 * rs[i]
			var v10: Vector3 = path[i + 1] + d10 * rs[i + 1]
			var v11: Vector3 = path[i + 1] + d11 * rs[i + 1]
			verts.append_array([v00, v10, v11, v00, v11, v01])
			norms.append_array([d00, d10, d11, d00, d11, d01])
			var u0: float = float(s) / segs
			var u1: float = float(s + 1) / segs
			var w0: float = float(i) / (n - 1)
			var w1: float = float(i + 1) / (n - 1)
			uvs.append_array([Vector2(u0, w0), Vector2(u0, w1), Vector2(u1, w1), Vector2(u0, w0), Vector2(u1, w1), Vector2(u1, w0)])
	if caps:
		for e: int in [0, n - 1]:
			var c: Vector3 = path[e]
			var nn: Vector3 = -tangents[e] if e == 0 else tangents[e]
			for s: int in segs:
				var a0: float = TAU * s / segs
				var a1: float = TAU * (s + 1) / segs
				var p0: Vector3 = c + (frames[e][0] * cos(a0) + frames[e][1] * sin(a0)) * rs[e]
				var p1: Vector3 = c + (frames[e][0] * cos(a1) + frames[e][1] * sin(a1)) * rs[e]
				if e == 0:
					verts.append_array([c, p0, p1])
				else:
					verts.append_array([c, p1, p0])
				norms.append_array([nn, nn, nn])
				uvs.append_array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	tris(verts, norms, uvs, xf, mat_name)


# --- Output -------------------------------------------------------------------------------------

## The finished model: a Node3D named `name` with one MeshInstance3D ("Mesh") and the parts.
func build(name: String) -> Node3D:
	var root := Node3D.new()
	root.name = name
	var mi: MeshInstance3D = _mesh_instance("Mesh")
	if mi != null:
		root.add_child(mi)
	for c: Array in _children:
		var k: ModelKit = c[1]
		var sub: MeshInstance3D = k._mesh_instance(c[0])
		if sub != null:
			sub.transform = c[2]
			root.add_child(sub)
	return root


func _mesh_instance(name: String) -> MeshInstance3D:
	if _surf.is_empty():
		return null
	var mesh := ArrayMesh.new()
	var keys: Array = _surf.keys()
	keys.sort()
	for k: String in keys:
		var b: Array = _surf[k]
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = b[0]
		arrays[Mesh.ARRAY_NORMAL] = b[1]
		arrays[Mesh.ARRAY_TEX_UV] = b[2]
		var st := SurfaceTool.new()
		st.create_from_arrays(arrays)
		st.index()
		st.set_material(mat(k))
		st.commit(mesh)
		mesh.surface_set_name(mesh.get_surface_count() - 1, k)
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	return mi
