class_name SkinArmModifier
extends SkeletonModifier3D
## A character skin's arms for emotes and held items, on top of whatever clip plays (idle, walk):
## each arm's upper bone and forearm swing to point along directions given in the skin root's
## space (the bean's: -Z forward, +Y up, +X right), blended in by a weight per arm. Godot puts the
## clip's pose back after every frame, so a weight of 0 is simply the clip again. Skins without
## arm bones (the warrior) get none of this; `AvatarVisuals` still moves their whole body.

## Upper arm, forearm and hand bones per rig (left, right), tried in order.
const RIGS: Array[Array] = [
	[[&"UpperArm.L", &"LowerArm.L", &"Wrist.L"], [&"UpperArm.R", &"LowerArm.R", &"Wrist.R"]],
	[[&"UpperArm.L", &"LowerArm.L", &"Palm.L"], [&"UpperArm.R", &"LowerArm.R", &"Palm.R"]],
	[[&"DEF-ARM.L", &"DEF-FOREARM.L", &"DEF-HAND.L"], [&"DEF-ARM.R", &"DEF-FOREARM.R", &"DEF-HAND.R"]],
]

## The skin root the directions are given in.
var root: Node3D
## Per arm (0 left, 1 right): where the upper arm and the forearm point, and how much (0..1).
var upper_dir: Array[Vector3] = [Vector3.DOWN, Vector3.DOWN]
var lower_dir: Array[Vector3] = [Vector3.DOWN, Vector3.DOWN]
var weight: Array[float] = [0.0, 0.0]
## Measured right after the last modification (for tests), in root space, normalized, per arm:
## shoulder → hand, and elbow → hand (the forearm). Zero until the first frame.
var measured: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var measured_forearm: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]

## [upper, forearm, hand] bone indices per arm.
var _bones: Array[PackedInt32Array] = []


## Finds the arm bones on `skel`; false when the skeleton has none we know.
func setup(skel: Skeleton3D) -> bool:
	for rig: Array in RIGS:
		var found: Array[PackedInt32Array] = []
		for arm: Array in rig:
			var ids := PackedInt32Array()
			for bone_name: StringName in arm:
				ids.append(skel.find_bone(bone_name))
			if ids.has(-1):
				break
			found.append(ids)
		if found.size() == 2:
			_bones = found
			return true
	return false


func _process_modification_with_delta(_delta: float) -> void:
	var skel: Skeleton3D = get_skeleton()
	if skel == null or root == null or _bones.size() != 2 or not is_instance_valid(root):
		return
	var to_root: Transform3D = _skeleton_to_root(skel)
	var inv: Basis = to_root.basis.inverse()
	for i: int in 2:
		var w: float = clampf(weight[i], 0.0, 1.0)
		var ids: PackedInt32Array = _bones[i]
		if w > 0.001:
			_aim(skel, ids[0], ids[1], (inv * upper_dir[i]).normalized(), w)
			_aim(skel, ids[1], ids[2], (inv * lower_dir[i]).normalized(), w)
		var hand: Vector3 = skel.get_bone_global_pose(ids[2]).origin
		measured[i] = (to_root.basis * (hand - skel.get_bone_global_pose(ids[0]).origin)).normalized()
		measured_forearm[i] = (to_root.basis * (hand - skel.get_bone_global_pose(ids[1]).origin)).normalized()


## Swings bone `b` (in place) so the way to its `tip` bone points along `want` (skeleton space).
func _aim(skel: Skeleton3D, b: int, tip: int, want: Vector3, w: float) -> void:
	var g: Transform3D = skel.get_bone_global_pose(b)
	var cur: Vector3 = skel.get_bone_global_pose(tip).origin - g.origin
	if cur.length() < 0.0001 or want.length() < 0.5:
		return
	cur = cur.normalized()
	if cur.dot(want) < -0.995:
		want = (want + g.basis.x.normalized() * 0.05).normalized()  # straight opposite: pick a side
	var to: Vector3 = cur.slerp(want, w).normalized()
	var q := Quaternion(cur, to)
	skel.set_bone_global_pose(b, Transform3D(Basis(q) * g.basis, g.origin))


## The skeleton's transform in the skin root's space.
func _skeleton_to_root(skel: Skeleton3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = skel
	while n != null and n != root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf
