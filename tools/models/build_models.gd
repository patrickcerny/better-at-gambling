extends SceneTree
## Writes every `PropRecipes` model to `assets/models/own/<id>.glb` (our own models, see
## docs/MODELS.md). Run, then re-import so Godot picks the files up:
##   tools/godot/godot --headless --path . -s tools/models/build_models.gd -- [--only a,b] [--out DIR]
##   tools/godot/godot --headless --path . --import


func _initialize() -> void:
	var c: Cmdline = Cmdline.parse(OS.get_cmdline_user_args())
	var out: String = c.get_string("out", "res://assets/models/own")
	var only: PackedStringArray = c.get_string("only", "").split(",", false)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var failed: int = 0
	for id: String in PropRecipes.IDS:
		if not only.is_empty() and not only.has(id):
			continue
		var node: Node3D = PropRecipes.build(id)
		root.add_child(node)
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		var err: int = doc.append_from_scene(node, state)
		if err == OK:
			err = doc.write_to_filesystem(state, "%s/%s.glb" % [out, id])
		if err != OK:
			push_error("model %s failed: %d" % [id, err])
			failed += 1
		else:
			print("wrote %s/%s.glb" % [out, id])
		node.free()
	quit(1 if failed > 0 else 0)
