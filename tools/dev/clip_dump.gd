extends SceneTree
## Dumps every cosmetic piece's triangles in the bean's space (rest pose) plus the bare bean's parts,
## for tools/dev/clip_check.py (pairwise clipping check). Run:
## xvfb-run -a tools/godot/godot --path . --rendering-driver opengl3 -s tools/dev/clip_dump.gd -- <out.json>
## (needs a real renderer: the headless one returns no mesh arrays), then
## python3 tools/dev/clip_check.py <out.json> <result.json>

var _frames: int = 0


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		_dump()
		return true
	return false


func _dump() -> void:
	AvatarVisuals.outfits_headless = true
	var out_path: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://clip.json"
	var root := Node3D.new()
	get_root().add_child(root)
	var bare := AvatarVisuals.new()
	root.add_child(bare)
	var base: Dictionary = {}
	for mi: MeshInstance3D in _meshes(bare):
		base[String(bare.get_path_to(mi))] = true
	var parts: Dictionary = {}
	for mi: MeshInstance3D in _meshes(bare):
		parts[String(bare.get_path_to(mi))] = _tris(mi, bare)
	var pieces: Dictionary = {}
	for d: CosmeticDef in CosmeticShop.default().items:
		if d.kind in [CosmeticDef.KIND_COLOR, CosmeticDef.KIND_SKIN, CosmeticDef.KIND_MOUTH]:
			continue
		var v := AvatarVisuals.new()
		root.add_child(v)
		v.wear(d.kind, d.id)
		var tris: PackedFloat32Array = PackedFloat32Array()
		for mi: MeshInstance3D in _meshes(v):
			var p: String = String(v.get_path_to(mi))
			if base.has(p) and not (d.kind == CosmeticDef.KIND_EYES and "Pupil" in p):
				continue
			tris.append_array(_tris(mi, v))
		pieces[String(d.id)] = {"kind": String(d.kind), "tris": Array(tris)}
		root.remove_child(v)
		v.free()
	# How far each cape spreads round each bulky shirt / trousers (AvatarVisuals scales it so).
	var spreads: Dictionary = {}
	for c: CosmeticDef in CosmeticShop.default().of_kind(CosmeticDef.KIND_CAPE):
		for kind: StringName in [CosmeticDef.KIND_SHIRT, CosmeticDef.KIND_PANTS]:
			for d: CosmeticDef in CosmeticShop.default().of_kind(kind):
				var s: float = OutfitMeshes.cape_spread(c.id, [d.id] as Array[StringName])
				if s > 1.001:
					spreads["%s|%s" % [c.id, d.id]] = s
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"parts": _arrays(parts), "pieces": pieces, "spreads": spreads}))
	f.close()
	print("dumped %d pieces" % pieces.size())


func _arrays(d: Dictionary) -> Dictionary:
	var o: Dictionary = {}
	for k: String in d:
		o[k] = Array(d[k])
	return o


func _meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for c: Node in n.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi.mesh != null and mi.is_visible_in_tree():
			out.append(mi)
	return out


## Triangles of `mi` in `ref` space, 9 floats each.
func _tris(mi: MeshInstance3D, ref: Node3D) -> PackedFloat32Array:
	var xf: Transform3D = ref.global_transform.affine_inverse() * mi.global_transform
	var out := PackedFloat32Array()
	for s: int in mi.mesh.get_surface_count():
		var arr: Array = mi.mesh.surface_get_arrays(s)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if idx.is_empty():
			for i: int in vs.size():
				idx.append(i)
		for i: int in idx.size():
			var p: Vector3 = xf * vs[idx[i]]
			out.append(p.x); out.append(p.y); out.append(p.z)
	return out
