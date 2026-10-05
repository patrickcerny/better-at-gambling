class_name SkinLibrary
extends RefCounted
## Character skins (Patrick's poly.pizza picks, credited in CREDITS.md). The server only knows the
## ids (`Cosmetics.SKINS`); this builds the models. Each one is scaled to about 1.6 m and turned to
## face -Z like the bean; skins that ship with clips play idle/walk/run (and sit when they have it).

const SKINS: Dictionary = {
	&"wizard": {"path": "res://assets/polypizza/skin_01.glb", "scale": 0.85, "lower_arms": [&"DEF-ARM.L", &"DEF-ARM.R"]},
	&"business": {"path": "res://assets/polypizza/skin_02.glb", "scale": 0.89},
	&"warrior": {"path": "res://assets/polypizza/skin_03.glb", "scale": 73.7},
	&"king": {"path": "res://assets/polypizza/skin_04.glb", "scale": 0.87},
	&"regular": {"path": "res://assets/polypizza/skin_05.glb", "scale": 0.33},
	&"swat": {"path": "res://assets/polypizza/skin_06.glb", "scale": 0.89},
}
## Clip name endings per motion, tried in order ("CharacterArmature|Walk", "HumanArmature|Man_Walk").
const CLIPS: Dictionary = {
	&"idle": ["|Idle", "_Idle"],
	&"walk": ["|Walk", "_Walk"],
	&"run": ["|Run", "_Run"],
	&"sit": ["_Sitting"],
}


static func has_model(id: StringName) -> bool:
	return SKINS.has(id)


## A new node holding the skin's model, or null for the bean (and unknown ids). Call
## `relax_pose` once it is in the tree.
static func instantiate(id: StringName) -> Node3D:
	if not SKINS.has(id):
		return null
	var d: Dictionary = SKINS[id]
	var ps: PackedScene = load(str(d["path"])) as PackedScene
	if ps == null:
		return null
	var root := Node3D.new()
	root.name = "Skin"
	var model: Node3D = ps.instantiate()
	model.scale = Vector3.ONE * float(d["scale"])
	model.rotation.y = PI
	root.add_child(model)
	root.set_meta(&"lower_arms", d.get("lower_arms", []))
	return root


## The skin's AnimationPlayer, or null when the model has no clips.
static func animation_player(root: Node3D) -> AnimationPlayer:
	var found: Array[Node] = root.find_children("*", "AnimationPlayer", true, false)
	return found[0] as AnimationPlayer if not found.is_empty() else null


## The clip for a motion (`&"idle"`, `&"walk"`, `&"run"`, `&"sit"`), looping, or &"" if missing.
static func clip(ap: AnimationPlayer, motion: StringName) -> StringName:
	for ending: String in CLIPS.get(motion, []):
		for a: StringName in ap.get_animation_list():
			if String(a).ends_with(ending):
				ap.get_animation(a).loop_mode = Animation.LOOP_LINEAR
				return a
	return &""


## Models without clips stand in a T-pose; this swings their arms down to the sides.
static func relax_pose(root: Node3D) -> void:
	var arms: Array = root.get_meta(&"lower_arms", [])
	if arms.is_empty():
		return
	var found: Array[Node] = root.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return
	var skel: Skeleton3D = found[0]
	# World "down" in skeleton space, walking the transforms up to the skin root.
	var xf := Transform3D.IDENTITY
	var n: Node = skel
	while n != null and n != root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	var down: Vector3 = (xf.basis.inverse() * Vector3.DOWN).normalized()
	for bone_name: StringName in arms:
		var b: int = skel.find_bone(bone_name)
		if b < 0 or skel.get_bone_children(b).is_empty():
			continue
		var g: Transform3D = skel.get_bone_global_pose(b)
		var tip: Vector3 = skel.get_bone_global_pose(skel.get_bone_children(b)[0]).origin
		var dir: Vector3 = (tip - g.origin).normalized()
		var target: Vector3 = dir.slerp(down, 0.85).normalized()
		var swung := Basis(Quaternion(dir, target)) * g.basis
		var parent: int = skel.get_bone_parent(b)
		var pg: Basis = skel.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
		skel.set_bone_pose_rotation(b, (pg.inverse() * swung).get_rotation_quaternion())
