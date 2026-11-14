class_name CapeCloth
extends RefCounted
## A worn cape's cloth: a coarse grid of points (NU across, NV down) simulated in world space with
## Verlet steps. The top row is pinned to the shoulders; the rest swings with inertia and gravity,
## keeps its stitch lengths, is pulled gently back towards the cape's designed shape (more near
## the shoulders, less at the hem), is held back by the air (so it trails behind a running bean), and stays outside the bean's body and above the floor. Each
## frame the grid's offsets from rest go to the cape's shader (`toon_cloth.gdshader`), which moves
## every vertex by them. Purely visual and client-side: nothing here touches gameplay.

const NU: int = 7
const NV: int = 6
const GRAVITY: Vector3 = Vector3(0.0, -9.8, 0.0)
## Velocity kept per 60 Hz frame (air drag in world space: it makes the cloth trail), at the
## shoulders and at the hem.
const DRAG_TOP: float = 0.97
const DRAG_HEM: float = 0.86
const ITERATIONS: int = 3
## Pull back to the designed shape per 60 Hz frame, at the shoulders and at the hem.
const SHAPE_TOP: float = 0.4
const SHAPE_HEM: float = 0.04
## Further than this between two frames is a teleport: start from rest again.
const SNAP_DISTANCE: float = 1.5

var mesh_node: MeshInstance3D
var material: ShaderMaterial
## Rest places of the grid points in the mesh's space (body space), row by row.
var rest := PackedVector3Array()
var _pos := PackedVector3Array()
var _prev := PackedVector3Array()
var _disp := PackedVector3Array()
var _started: bool = false
var _last_origin: Vector3 = Vector3.ZERO


func _init(id: StringName, node: MeshInstance3D, mat: ShaderMaterial) -> void:
	mesh_node = node
	material = mat
	for j: int in NV:
		for i: int in NU:
			rest.append(OutfitMeshes.cape_rest(id, float(i) / float(NU - 1), float(j) / float(NV - 1)))
	_pos.resize(rest.size())
	_prev.resize(rest.size())
	_disp.resize(rest.size())
	material.set_shader_parameter(&"cloth", _disp)


## Starts again from the cape's rest shape (after a teleport or a respawn).
func reset() -> void:
	_started = false


## Advances the cloth by `delta`; `floor_y` is the ground under the bean (world).
func step(delta: float, floor_y: float) -> void:
	if mesh_node == null or not mesh_node.is_inside_tree():
		return
	var xf: Transform3D = mesh_node.global_transform
	if not _started or xf.origin.distance_to(_last_origin) > SNAP_DISTANCE:
		for k: int in rest.size():
			_pos[k] = xf * rest[k]
			_prev[k] = _pos[k]
		_started = true
	_last_origin = xf.origin
	var dt: float = clampf(delta, 0.0, 1.0 / 30.0)
	var frames: float = dt * 60.0
	# Move: inertia, gravity, and the pull back to the designed shape.
	for j: int in NV:
		var v: float = float(j) / float(NV - 1)
		var shape: float = 1.0 - pow(1.0 - lerpf(SHAPE_TOP, SHAPE_HEM, v), frames)
		var keep: float = pow(lerpf(DRAG_TOP, DRAG_HEM, v), frames)
		for i: int in NU:
			var k: int = j * NU + i
			var target: Vector3 = xf * rest[k]
			if j == 0:
				_pos[k] = target
				_prev[k] = target
				continue
			var vel: Vector3 = (_pos[k] - _prev[k]) * keep
			_prev[k] = _pos[k]
			_pos[k] += vel + GRAVITY * dt * dt
			_pos[k] = _pos[k].lerp(target, shape)
	# Keep the stitches their length (across and down), then keep out of the body and the floor.
	for _it: int in ITERATIONS:
		for j: int in NV:
			for i: int in NU:
				var k: int = j * NU + i
				if i + 1 < NU:
					_link(k, k + 1, xf, j == 0)
				if j + 1 < NV:
					_link(k, k + NU, xf, j == 0)
	var inv: Transform3D = xf.affine_inverse()
	for k: int in range(NU, rest.size()):
		var q: Vector3 = inv * _pos[k]
		var t: float = q.y / AvatarVisuals.BODY_HEIGHT + 0.5
		if t > 0.0 and t < 1.0:
			var r: float = AvatarVisuals.radius_at(t) + 0.06
			var bend: float = AvatarVisuals.bend_at(t)
			var flat := Vector2(q.x, (q.z - bend) / AvatarVisuals.BODY_DEPTH)
			if flat.length_squared() < r * r:
				flat = (flat.normalized() if flat.length_squared() > 1e-8 else Vector2(0.0, 1.0)) * r
				q.x = flat.x
				q.z = bend + flat.y * AvatarVisuals.BODY_DEPTH
				_pos[k] = xf * q
		if _pos[k].y < floor_y + 0.02:
			_pos[k].y = floor_y + 0.02
		_disp[k] = inv * _pos[k] - rest[k]
	material.set_shader_parameter(&"cloth", _disp)


## Pulls points `a` and `b` back to their rest distance (`a` pinned on the top row).
func _link(a: int, b: int, xf: Transform3D, a_pinned: bool) -> void:
	var want: float = (xf.basis * (rest[b] - rest[a])).length()
	var d: Vector3 = _pos[b] - _pos[a]
	var len: float = d.length()
	if len < 1e-6:
		return
	var fix: Vector3 = d * ((len - want) / len)
	var b_pinned: bool = a_pinned and b < NU
	if a_pinned and b_pinned:
		return
	if a_pinned:
		_pos[b] -= fix
	else:
		_pos[a] += fix * 0.5
		_pos[b] -= fix * 0.5
