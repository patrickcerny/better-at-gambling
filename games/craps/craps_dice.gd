class_name CrapsDice
extends RefCounted
## The two dice a craps shooter throws, on the client (presentation only; the money is settled on
## the server's roll and never depends on this).
##
## `simulate` runs a small deterministic rigid-body throw of two cubes in the table's frame
## (gravity, the felt, the four rail walls with their rubber, and each other; impulses with
## restitution and friction on the eight corners, the same doubles on every machine), so every
## client shows the same tumbling throw for the same `seed`. How it ends on the server's faces:
## 1. Once a die has slowed down on the felt (or at `SETTLE_BY` at the latest) it eases flat onto
##    whichever face is nearest to up (the "last bounce" snap), and both rest by `REST_TIME`.
## 2. The die's geometry is a cube, so relabelling its faces with one of the cube's 24 rotations
##    `C` changes nothing about the throw: every corner traces the same path. After the throw is
##    simulated, the face that ended up is known; `C` is chosen so the server's face is the one
##    painted there, and every recorded orientation is turned by `C` (`orientation × C`). The
##    trajectory stays the simulated one; the face on top at rest is, exactly, the server's.

## Edge of a die (a table miniature, larger than life so it reads from the stools).
const EDGE: float = 0.085
const HALF: float = EDGE * 0.5
## Physics step and the spacing of the recorded frames.
const SIM_DT: float = 1.0 / 240.0
const FRAME_DT: float = 1.0 / 60.0
## Every throw is still by this many seconds after leaving the hand (inside the server's
## `craps_throw_time`, so the dice rest before the bets settle).
const REST_TIME: float = 2.2
## A die still moving at this time eases flat anyway; the ease takes `SETTLE_SECONDS`.
const SETTLE_BY: float = 1.75
const SETTLE_SECONDS: float = 0.3
const GRAVITY: float = 9.8
const RESTITUTION_FELT: float = 0.32
const RESTITUTION_RAIL: float = 0.55  # the rubber diamonds on the rail
const FRICTION: float = 0.45
## Distance between the two dice's centres they never come closer than (a sphere between the
## inscribed and the corner sphere).
const DICE_GAP: float = EDGE * 1.18
## Body-frame normal of each face, value 1..6 at index 0..5 (opposite faces add up to seven).
const FACE_NORMALS: Array[Vector3] = [Vector3.UP, Vector3.BACK, Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.DOWN]
const PIP_SPOTS: Dictionary = {
	1: [Vector2.ZERO], 2: [Vector2(-1, -1), Vector2(1, 1)], 3: [Vector2(-1, -1), Vector2.ZERO, Vector2(1, 1)],
	4: [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)],
	5: [Vector2(-1, -1), Vector2(1, -1), Vector2.ZERO, Vector2(-1, 1), Vector2(1, 1)],
	6: [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 0), Vector2(1, 0), Vector2(-1, 1), Vector2(1, 1)],
}


## The value on top of a die with orientation `b` (the face whose normal points most up).
static func face_up(b: Basis) -> int:
	var best: int = 1
	var best_y: float = -INF
	for i: int in FACE_NORMALS.size():
		var y: float = (b * FACE_NORMALS[i]).y
		if y > best_y:
			best_y = y
			best = i + 1
	return best


## A rotation of the cube onto itself that carries face `from`'s normal to face `to`'s.
static func relabel(from: int, to: int) -> Basis:
	var a: Vector3 = FACE_NORMALS[from - 1]
	var b: Vector3 = FACE_NORMALS[to - 1]
	if a == b:
		return Basis.IDENTITY
	var axis: Vector3 = a.cross(b)
	var angle: float = PI * 0.5
	if axis.length() < 0.5:  # opposite faces: half a turn about any axis square to them
		axis = Vector3.RIGHT if absf(a.x) < 0.5 else Vector3.UP
		angle = PI
	var r := Basis(axis.normalized(), angle)
	# Exact: a cube rotation has entries 0 and ±1 only.
	return Basis(r.x.round(), r.y.round(), r.z.round())


## The whole throw, identical wherever it runs. `from` is where the dice leave the hand, `toward`
## a point on the felt they are thrown at, `felt` the walls' inner faces (x0, z0, x1, z1 as a
## Rect2 position/end in the table's x/z) and `felt_y` the felt's height; `faces` the two values
## the server rolled. Returns {pos: [PackedVector3Array ×2], rot: [Array[Quaternion] ×2], rest:
## seconds until both lie still, wall: true if a die reached the far rail}.
static func simulate(seed_value: int, from: Vector3, toward: Vector3, felt: Rect2, felt_y: float, faces: Array) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var dir: Vector3 = toward - from
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.RIGHT
	var side: Vector3 = dir.cross(Vector3.UP)
	var pos: Array[Vector3] = []
	var vel: Array[Vector3] = []
	var rot: Array[Quaternion] = []
	var spin: Array[Vector3] = []
	var settle_at: Array[float] = [-1.0, -1.0]
	var settle_from: Array[Quaternion] = [Quaternion.IDENTITY, Quaternion.IDENTITY]
	var settle_to: Array[Quaternion] = [Quaternion.IDENTITY, Quaternion.IDENTITY]
	var settle_y: Array[float] = [0.0, 0.0]
	var speed: float = r.randf_range(3.9, 4.5)
	for i: int in 2:
		pos.append(from + side * (EDGE * 0.75 * (1.0 if i == 0 else -1.0)) + Vector3(0.0, r.randf_range(-0.01, 0.01), 0.0))
		var spread: Vector3 = side * r.randf_range(-0.22, 0.22)
		vel.append((dir + spread).normalized() * speed * r.randf_range(0.93, 1.05) + Vector3.UP * r.randf_range(0.9, 1.3))
		rot.append(Quaternion(_random_axis(r), r.randf_range(0.0, TAU)))
		spin.append(_random_axis(r) * r.randf_range(20.0, 32.0))
	var frames_pos: Array[PackedVector3Array] = [PackedVector3Array([pos[0]]), PackedVector3Array([pos[1]])]
	var frames_rot: Array = [[rot[0]], [rot[1]]]
	var subs: int = roundi(FRAME_DT / SIM_DT)
	var t: float = 0.0
	var rest: float = REST_TIME
	var wall: bool = false
	var far_x: float = felt.end.x if dir.x > 0.0 else felt.position.x
	var inv_i: float = 6.0 / (EDGE * EDGE)  # a cube's inertia is the same about every axis (mass 1)
	while t < REST_TIME - 0.0001:
		for _s: int in subs:
			t += SIM_DT
			for i: int in 2:
				if settle_at[i] >= 0.0:
					# Easing flat onto its nearest face, sliding to a stop.
					var u: float = clampf((t - settle_at[i]) / SETTLE_SECONDS, 0.0, 1.0)
					var e: float = u * u * (3.0 - 2.0 * u)
					rot[i] = settle_from[i].slerp(settle_to[i], e)
					vel[i] = Vector3.ZERO if u >= 1.0 else vel[i] * exp(-12.0 * SIM_DT)
					vel[i].y = 0.0
					pos[i] += vel[i] * SIM_DT
					pos[i].y = lerpf(settle_y[i], felt_y + HALF, e)
					spin[i] = Vector3.ZERO
					continue
				vel[i].y -= GRAVITY * SIM_DT
				pos[i] += vel[i] * SIM_DT
				var w: Vector3 = spin[i]
				if w.length() > 0.0001:
					rot[i] = (Quaternion(w.normalized(), w.length() * SIM_DT) * rot[i]).normalized()
				var touching: bool = _contacts(pos, vel, rot, spin, i, felt, felt_y, inv_i)
				if absf(pos[i].x - far_x) < HALF * 1.8:
					wall = true  # reached the far rail
				if touching:
					spin[i] *= exp(-2.5 * SIM_DT)  # rolling resistance on the felt
				var slow: bool = touching and vel[i].length() < 0.12 and spin[i].length() < 2.5
				if slow or t >= SETTLE_BY:
					settle_at[i] = t
					settle_from[i] = rot[i]
					settle_to[i] = _nearest_flat(rot[i])
					settle_y[i] = maxf(pos[i].y, felt_y + HALF)
			_separate(pos, vel, felt)
		frames_pos[0].append(pos[0])
		frames_pos[1].append(pos[1])
		(frames_rot[0] as Array).append(rot[0])
		(frames_rot[1] as Array).append(rot[1])
		if rest == REST_TIME and settle_at[0] >= 0.0 and settle_at[1] >= 0.0 and t >= maxf(settle_at[0], settle_at[1]) + SETTLE_SECONDS:
			rest = t
	# Relabel each die so the server's face is the one on top (see the class comment).
	for i: int in 2:
		var ended: int = face_up(Basis(rot[i]))
		var want: int = clampi(int(faces[i]) if i < faces.size() else 1, 1, 6)
		var c: Quaternion = Quaternion(relabel(want, ended))
		var list: Array = frames_rot[i]
		for k: int in list.size():
			list[k] = (list[k] as Quaternion) * c
	return {"pos": frames_pos, "rot": frames_rot, "rest": rest, "wall": wall, "duration": (frames_pos[0].size() - 1) * FRAME_DT}


## Transform of die `i` at `seconds` into a throw plan (table frame).
static func sample(plan: Dictionary, i: int, seconds: float) -> Transform3D:
	var ps: PackedVector3Array = (plan["pos"] as Array)[i]
	var rs: Array = (plan["rot"] as Array)[i]
	var x: float = clampf(seconds / FRAME_DT, 0.0, float(ps.size() - 1))
	var a: int = mini(int(floor(x)), ps.size() - 1)
	var b: int = mini(a + 1, ps.size() - 1)
	var f: float = x - a
	var q: Quaternion = (rs[a] as Quaternion).slerp(rs[b] as Quaternion, f)
	return Transform3D(Basis(q), ps[a].lerp(ps[b], f))


## Corner contacts of die `i` with the felt and the rails: impulses with restitution and friction,
## then pushes it out. True if a corner touches the felt.
static func _contacts(pos: Array[Vector3], vel: Array[Vector3], rot: Array[Quaternion], spin: Array[Vector3], i: int, felt: Rect2, felt_y: float, inv_i: float) -> bool:
	var b := Basis(rot[i])
	var touching: bool = false
	var push_up: Vector3 = Vector3.ZERO  # deepest correction along +x, +y, +z
	var push_down: Vector3 = Vector3.ZERO  # and along −x, −z
	for cx: float in [-HALF, HALF]:
		for cy: float in [-HALF, HALF]:
			for cz: float in [-HALF, HALF]:
				var arm: Vector3 = b * Vector3(cx, cy, cz)
				var p: Vector3 = pos[i] + arm
				var hits: Array = []
				if p.y < felt_y:
					hits.append([Vector3.UP, felt_y - p.y, RESTITUTION_FELT])
					touching = true
				# The rails: walls round the felt (a die never gets over them).
				if p.x < felt.position.x:
					hits.append([Vector3.RIGHT, felt.position.x - p.x, RESTITUTION_RAIL])
				elif p.x > felt.end.x:
					hits.append([Vector3.LEFT, p.x - felt.end.x, RESTITUTION_RAIL])
				if p.z < felt.position.y:
					hits.append([Vector3.BACK, felt.position.y - p.z, RESTITUTION_RAIL])
				elif p.z > felt.end.y:
					hits.append([Vector3.FORWARD, p.z - felt.end.y, RESTITUTION_RAIL])
				for h: Array in hits:
					var n: Vector3 = h[0]
					var depth: float = h[1]
					var e: float = h[2]
					var pv: Vector3 = vel[i] + spin[i].cross(arm)
					var vn: float = pv.dot(n)
					if vn < 0.0:
						var rn: Vector3 = arm.cross(n)
						var jn: float = -(1.0 + e) * vn / (1.0 + rn.length_squared() * inv_i)
						vel[i] += n * jn
						spin[i] += rn * (jn * inv_i)
						# Friction against the sliding direction, at most FRICTION × the normal push.
						pv = vel[i] + spin[i].cross(arm)
						var vt: Vector3 = pv - n * pv.dot(n)
						var vt_len: float = vt.length()
						if vt_len > 0.0001:
							var tdir: Vector3 = vt / vt_len
							var rt: Vector3 = arm.cross(tdir)
							var jt: float = minf(vt_len / (1.0 + rt.length_squared() * inv_i), FRICTION * jn)
							vel[i] -= tdir * jt
							spin[i] -= rt * (jt * inv_i)
					push_up = push_up.max(n * depth)
					push_down = push_down.min(n * depth)
	pos[i] += push_up + push_down
	return touching


## Keeps the two dice apart (and both inside the rails): equal masses swap their closing speed.
static func _separate(pos: Array[Vector3], vel: Array[Vector3], felt: Rect2) -> void:
	var d: Vector3 = pos[1] - pos[0]
	var dist: float = d.length()
	if dist < DICE_GAP:
		var n: Vector3 = d / dist if dist > 0.0001 else Vector3.RIGHT
		var closing: float = (vel[1] - vel[0]).dot(n)
		if closing < 0.0:
			var j: float = -(1.0 + 0.3) * closing * 0.5
			vel[0] -= n * j
			vel[1] += n * j
		var fix: float = (DICE_GAP - dist) * 0.5
		pos[0] -= n * fix
		pos[1] += n * fix
	var m: float = HALF * 1.42  # a flat die turned any way stays this far from a rail
	for i: int in 2:
		pos[i].x = clampf(pos[i].x, felt.position.x + m, felt.end.x - m)
		pos[i].z = clampf(pos[i].z, felt.position.y + m, felt.end.y - m)


## The orientation nearest to `q` lying flat on a face (the face most up turned straight up, the
## yaw kept).
static func _nearest_flat(q: Quaternion) -> Quaternion:
	var b := Basis(q)
	var up_face: Vector3 = b * FACE_NORMALS[face_up(b) - 1]
	var axis: Vector3 = up_face.cross(Vector3.UP)
	if axis.length() < 0.000001:
		return q
	var angle: float = up_face.angle_to(Vector3.UP)
	return (Quaternion(axis.normalized(), angle) * q).normalized()


static func _random_axis(r: RandomNumberGenerator) -> Vector3:
	var v := Vector3(r.randf_range(-1.0, 1.0), r.randf_range(-1.0, 1.0), r.randf_range(-1.0, 1.0))
	return v.normalized() if v.length() > 0.01 else Vector3.UP


# --- The die itself (client only) ----------------------------------------------------------------

## A die: a casino red cube with cream pips, faces as in `FACE_NORMALS`.
static func make_die(body_mat: Material, pip_mat: Material) -> Node3D:
	var die := Node3D.new()
	var cube := MeshInstance3D.new()
	cube.name = "Cube"
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * EDGE
	cube.mesh = bm
	cube.material_override = body_mat
	die.add_child(cube)
	var pip := CylinderMesh.new()
	pip.top_radius = EDGE * 0.085
	pip.bottom_radius = EDGE * 0.085
	pip.height = EDGE * 0.03
	pip.radial_segments = 10
	pip.rings = 1
	for f: int in FACE_NORMALS.size():
		var normal: Vector3 = FACE_NORMALS[f]
		var u: Vector3 = Vector3.RIGHT if absf(normal.x) < 0.5 else Vector3.BACK
		var v: Vector3 = normal.cross(u)
		var up_to_normal: Basis = _basis_up_to(normal)
		for s: Vector2 in PIP_SPOTS[f + 1]:
			var mi := MeshInstance3D.new()
			mi.mesh = pip
			mi.material_override = pip_mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.transform = Transform3D(up_to_normal, normal * (HALF + EDGE * 0.003) + (u * s.x + v * s.y) * EDGE * 0.27)
			die.add_child(mi)
	return die


static func _basis_up_to(n: Vector3) -> Basis:
	if n == Vector3.UP:
		return Basis.IDENTITY
	if n == Vector3.DOWN:
		return Basis(Vector3.RIGHT, PI)
	return Basis(Vector3.UP.cross(n).normalized(), PI * 0.5)
