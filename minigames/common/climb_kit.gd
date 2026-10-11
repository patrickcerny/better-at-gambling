class_name ClimbKit
extends RefCounted
## Shared climbing tech ("K") of the climb room (`ClimbRoom`): Dodge the Dice climbs a stepped,
## tilted roulette board; Jackpot Climb will climb chip-stack towers. Pure maths for the server
## (heights, rows, slide-back spots) plus node builders with collision for the client. Nothing
## here knows a game.
##
## A **flight** is a stepped slope climbing toward -z: `rows` rows, each a tread `depth` metres
## deep (flat) that rises `rise - lip` toward the top, then a vertical `lip` (a ledge the bean
## jumps) up to the next tread. Row 0's front lip stands on the floor at `base` (the centre of the
## bottom edge); above the last row a landing waits one more `lip` up. A flight is a Dictionary
## (`flight()`), in whatever frame its `base` is given in: the room builds in local coordinates,
## the server reads world ones.
##
## Progress (`height_of`) is the fraction of a climb axis [from, to] a position has covered: the
## projection onto the axis, 0 at `from`, 1 at `to`. The board's axis runs from the bottom edge to
## the landing's lip; Jackpot Climb's will run straight up a tower.


static func flight(base: Vector3, half_width: float, rows: int, depth: float, rise: float, lip: float) -> Dictionary:
	return {"base": base, "half_width": half_width, "rows": rows, "depth": depth, "rise": rise, "lip": lip}


## z of the flight's top edge (where the landing starts).
static func top_z(f: Dictionary) -> float:
	return (f["base"] as Vector3).z - float(f["rows"]) * float(f["depth"])


## Height of the landing above the flight (the last row's top plus one lip).
static func landing_y(f: Dictionary) -> float:
	return (f["base"] as Vector3).y + float(f["rows"]) * float(f["rise"]) + float(f["lip"])


## Tread angle (radians): the slope of each row's walking surface.
static func tread_angle(f: Dictionary) -> float:
	return atan2(float(f["rise"]) - float(f["lip"]), float(f["depth"]))


## Average angle of the whole flight (radians), lips included.
static func slope_angle(f: Dictionary) -> float:
	return atan2(float(f["rise"]), float(f["depth"]))


## Row under `z`: -1 below the flight (the floor in front), `rows` on the landing.
static func row_at(f: Dictionary, z: float) -> int:
	var d: float = (f["base"] as Vector3).z - z
	if d < 0.0:
		return -1
	return mini(floori(d / float(f["depth"])), int(f["rows"]))


## Height of the walking surface under `z`: the floor in front, a tread, or the landing.
static func surface_y(f: Dictionary, z: float) -> float:
	var base: Vector3 = f["base"]
	var row: int = row_at(f, z)
	if row < 0:
		return base.y
	if row >= int(f["rows"]):
		return landing_y(f)
	var depth: float = f["depth"]
	var frac: float = clampf((base.z - z - float(row) * depth) / depth, 0.0, 1.0)
	return base.y + float(row) * float(f["rise"]) + float(f["lip"]) + (float(f["rise"]) - float(f["lip"])) * frac


## True if `pos` is over the flight (flat), from the bottom edge to the top edge.
static func over_flight(f: Dictionary, pos: Vector3) -> bool:
	var base: Vector3 = f["base"]
	return absf(pos.x - base.x) <= float(f["half_width"]) and pos.z <= base.z and pos.z >= top_z(f)


## Where a bean at `pos` lands after sliding `metres` (flat) down the flight: on the surface,
## never past `floor_z` (the far edge of the floor in front of the flight).
static func downhill(f: Dictionary, pos: Vector3, metres: float, floor_z: float = INF) -> Vector3:
	var z: float = minf(pos.z + metres, floor_z)
	var base: Vector3 = f["base"]
	var hw: float = float(f["half_width"]) - 0.5
	var x: float = clampf(pos.x, base.x - hw, base.x + hw)
	return Vector3(x, surface_y(f, z) + 0.05, z)


## Fraction of the climb axis `from` → `to` covered at `pos` (0..1).
static func height_of(from: Vector3, to: Vector3, pos: Vector3) -> float:
	var a: Vector3 = to - from
	var l2: float = a.length_squared()
	if l2 <= 0.0001:
		return 0.0
	return clampf((pos - from).dot(a) / l2, 0.0, 1.0)


## True if `pos` stands in one of `fields` ([row, x0, x1] in the flight's frame): flat inside
## the field and no higher than `slack` over its tread (a bean jumping over it is not on it).
static func in_field(f: Dictionary, fields: Array, pos: Vector3, slack: float = 0.6) -> bool:
	var row: int = row_at(f, pos.z)
	if row < 0 or row >= int(f["rows"]):
		return false
	for fd: Array in fields:
		if int(fd[0]) == row and pos.x >= float(fd[1]) and pos.x <= float(fd[2]):
			return pos.y <= surface_y(f, pos.z) + slack
	return false


# --- Builders (client and dedicated server: the collision is the climb) -------------------------

## Builds the flight under `parent`: per row a solid wedge (collision: a convex prism down to the
## floor) in `body_mat`, a brass `nosing_mat` bar on every ledge. Returns the flight's node.
static func build_flight(parent: Node3D, f: Dictionary, body_mat: Material, nosing_mat: Material) -> Node3D:
	var root := Node3D.new()
	root.name = "Flight"
	parent.add_child(root)
	var base: Vector3 = f["base"]
	var hw: float = f["half_width"]
	var depth: float = f["depth"]
	var rise: float = f["rise"]
	var lip: float = f["lip"]
	for k: int in int(f["rows"]):
		var z0: float = base.z - float(k) * depth
		var z1: float = z0 - depth
		var y0: float = base.y + float(k) * rise
		var yb: float = y0 + lip
		var yt: float = y0 + rise
		var pts := PackedVector3Array([
			Vector3(base.x - hw, base.y, z0), Vector3(base.x + hw, base.y, z0),
			Vector3(base.x - hw, base.y, z1), Vector3(base.x + hw, base.y, z1),
			Vector3(base.x - hw, yb, z0), Vector3(base.x + hw, yb, z0),
			Vector3(base.x - hw, yt, z1), Vector3(base.x + hw, yt, z1),
		])
		var body := StaticBody3D.new()
		body.name = "Row%d" % k
		var cs := CollisionShape3D.new()
		var shape := ConvexPolygonShape3D.new()
		shape.points = pts
		cs.shape = shape
		body.add_child(cs)
		root.add_child(body)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_smooth_group(0xFFFFFFFF)  # flat shading
		_quad(st, pts[0], pts[1], pts[5], pts[4])  # front (the ledge face)
		_quad(st, pts[4], pts[5], pts[7], pts[6])  # tread
		_quad(st, pts[2], pts[0], pts[4], pts[6])  # west side
		_quad(st, pts[1], pts[3], pts[7], pts[5])  # east side
		st.generate_normals()
		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		mi.mesh = st.commit()
		mi.material_override = body_mat
		body.add_child(mi)
		# A brass nosing along the ledge's edge.
		var nose := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.07
		cm.bottom_radius = 0.07
		cm.height = hw * 2.0
		cm.radial_segments = 10
		nose.mesh = cm
		nose.material_override = nosing_mat
		nose.rotation.z = PI * 0.5
		nose.position = Vector3(base.x, yb - 0.03, z0 - 0.02)
		root.add_child(nose)
	return root


## The tread plane of `row`: origin at its centre, local -z uphill along the tread, local +y its
## normal. Things printed on the tread go under a Node3D with this transform (y a hair above 0).
static func tread_frame(f: Dictionary, row: int) -> Transform3D:
	var base: Vector3 = f["base"]
	var y0: float = base.y + float(row) * float(f["rise"])
	var mid := Vector3(base.x, y0 + float(f["lip"]) + (float(f["rise"]) - float(f["lip"])) * 0.5, base.z - (float(row) + 0.5) * float(f["depth"]))
	return Transform3D(Basis(Vector3.RIGHT, tread_angle(f)), mid)


## Length of a tread along its slope.
static func tread_length(f: Dictionary) -> float:
	return Vector2(float(f["depth"]), float(f["rise"]) - float(f["lip"])).length()


## A slide chute printed over the field [x0, x1] (flight frame) of `row` (visual; the stage pushes
## beans down it): a polished brass trough with side rails and chevrons pointing downhill.
static func build_chute(parent: Node3D, f: Dictionary, row: int, x0: float, x1: float, trough: Material, rail: Material, chevron: Material) -> Node3D:
	var frame := Node3D.new()
	frame.name = "Chute%d" % row
	frame.transform = tread_frame(f, row)
	parent.add_child(frame)
	var length: float = tread_length(f)
	var w: float = x1 - x0
	var cx: float = (x0 + x1) * 0.5 - (f["base"] as Vector3).x
	var bed := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w - 0.1, 0.04, length - 0.04)
	bed.mesh = bm
	bed.material_override = trough
	bed.position = Vector3(cx, 0.02, 0.0)
	frame.add_child(bed)
	for side: float in [-1.0, 1.0]:
		var r := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(0.1, 0.14, length - 0.04)
		r.mesh = rm
		r.material_override = rail
		r.position = Vector3(cx + side * (w * 0.5 - 0.05), 0.07, 0.0)
		frame.add_child(r)
	for i: int in 3:
		var c := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(minf(w * 0.45, 1.1), 0.55, 0.02)
		c.mesh = pm
		c.material_override = chevron
		# Lying flat on the trough, its tip pointing downhill (+z of the frame).
		c.rotation = Vector3(PI * 0.5, 0.0, 0.0)
		c.position = Vector3(cx, 0.05, -length * 0.3 + float(i) * length * 0.3)
		frame.add_child(c)
	return frame


## A flat platform with collision (a chip-stack top, a tower ledge): `size` box centred on `pos`;
## `mat` null makes it invisible (a guard wall).
static func ledge(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, name: String = "Ledge") -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = name
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	if mat != null:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.material_override = mat
		body.add_child(mi)
	body.position = pos
	parent.add_child(body)
	return body


## An invisible wall that keeps beans on the climb.
static func guard(parent: Node3D, size: Vector3, pos: Vector3, name: String = "Guard") -> StaticBody3D:
	return ledge(parent, size, pos, null, name)


## Both windings (the faces show from either side whatever the material's culling).
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for v: Vector3 in [a, b, c, a, c, d, a, c, b, a, d, c]:
		st.add_vertex(v)
