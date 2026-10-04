class_name GreyboxKit
extends RefCounted
## Helpers that build simple collidable placeholder geometry (boxes, cylinders) with palette
## materials. Everything in the greybox map comes from here so it is cheap to restyle later.

static var _materials: Dictionary[Color, StandardMaterial3D] = {}


## Flat material for a colour (cached).
static func material(color: Color, metallic: float = 0.0, roughness: float = 0.9) -> StandardMaterial3D:
	var key: Color = color
	if _materials.has(key) and metallic == 0.0:
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	if metallic == 0.0:
		_materials[key] = m
	return m


## Gold-ish shiny material.
static func gold() -> StandardMaterial3D:
	return material(Palette.WARM_GOLD, 0.8, 0.35)


## Static box with collision. `pos` is the centre.
static func box(parent: Node, size: Vector3, pos: Vector3, color: Color, name: String = "Box", collide: bool = true) -> Node3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _solid(parent, mesh, BoxShape3D.new() if collide else null, size, pos, color, name)


## Static cylinder (vertical) with collision.
static func cylinder(parent: Node, radius: float, height: float, pos: Vector3, color: Color, name: String = "Cylinder", collide: bool = true, metallic: float = 0.0) -> Node3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	var shape: CylinderShape3D = null
	if collide:
		shape = CylinderShape3D.new()
		shape.radius = radius
		shape.height = height
	var node: Node3D = _solid(parent, mesh, shape, Vector3.ZERO, pos, color, name)
	if metallic > 0.0:
		(node.get_node("Mesh") as MeshInstance3D).material_override = material(color, metallic, 0.35)
	return node


## Visual-only sphere.
static func sphere(parent: Node, radius: float, pos: Vector3, color: Color, name: String = "Sphere") -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	mi.material_override = material(color)
	mi.position = pos
	parent.add_child(mi)
	return mi


## Visual-only capsule (statues, beans).
static func capsule(parent: Node, radius: float, height: float, pos: Vector3, mat: Material, name: String = "Capsule") -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


## Warm omni light.
static func lamp(parent: Node, pos: Vector3, energy: float = 2.0, range_m: float = 12.0, color: Color = Color(1.0, 0.85, 0.6)) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = range_m
	l.shadow_enabled = false
	parent.add_child(l)
	return l


## A thin sloped box used for stairs/ramps from `from` to `to` (centres of the two ends).
static func ramp(parent: Node, from: Vector3, to: Vector3, width: float, color: Color, name: String = "Ramp") -> Node3D:
	# A solid wedge whose top surface runs from `from` up to `to`: no lip at the bottom for
	# characters to catch on, and a vertical back face so it reads as a staircase block.
	var delta: Vector3 = to - from
	var flat: Vector3 = Vector3(delta.x, 0.0, delta.z)
	var length: float = flat.length()
	var yaw: float = atan2(-flat.x, -flat.z) if length > 0.001 else 0.0
	var h: float = delta.y
	var hw: float = width * 0.5
	# Local frame: ramp rises toward -z (forward), from z = +length/2 (low end) to z = -length/2 (high end).
	var lo: float = length * 0.5
	var pts: PackedVector3Array = PackedVector3Array([
		Vector3(-hw, 0.0, lo), Vector3(hw, 0.0, lo),  # bottom edge at the low end
		Vector3(-hw, 0.0, -lo), Vector3(hw, 0.0, -lo),  # bottom edge at the high end
		Vector3(-hw, h, -lo), Vector3(hw, h, -lo),  # top edge at the high end
	])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad(st, pts[0], pts[1], pts[5], pts[4])  # sloped top
	_quad(st, pts[3], pts[2], pts[4], pts[5])  # vertical back
	_quad(st, pts[1], pts[0], pts[2], pts[3])  # bottom
	_tri(st, pts[0], pts[4], pts[2])  # left side
	_tri(st, pts[1], pts[3], pts[5])  # right side
	st.generate_normals()
	var mesh: ArrayMesh = st.commit()
	var body := StaticBody3D.new()
	body.name = name
	body.add_to_group(&"navsource")
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	mi.material_override = material(color)
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	cs.shape = shape
	body.add_child(cs)
	body.position = Vector3((from.x + to.x) * 0.5, from.y, (from.z + to.z) * 0.5)
	body.rotation.y = yaw
	parent.add_child(body)
	return body


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_tri(st, a, b, c)
	_tri(st, a, c, d)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


static func _solid(parent: Node, mesh: Mesh, shape: Shape3D, size: Vector3, pos: Vector3, color: Color, name: String) -> Node3D:
	var root: Node3D
	if shape != null:
		root = StaticBody3D.new()
		root.add_to_group(&"navsource")
		if shape is BoxShape3D:
			(shape as BoxShape3D).size = size
		var cs := CollisionShape3D.new()
		cs.shape = shape
		root.add_child(cs)
	else:
		root = Node3D.new()
	root.name = name
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	mi.material_override = material(color)
	root.add_child(mi)
	root.position = pos
	parent.add_child(root)
	return root
