extends GutTest
## Instantiates every project scene (outside addons/) and runs a few frames, so
## broken references and script errors in `_ready` fail the suite.

const SKIP_DIRS: Array[String] = ["res://addons", "res://.godot", "res://tools", "res://build"]
const FRAMES: int = 10


func test_every_scene_instantiates() -> void:
	var scenes: Array[String] = []
	_collect("res://", scenes)
	assert_gt(scenes.size(), 0, "found scenes")
	for path: String in scenes:
		var packed: PackedScene = load(path) as PackedScene
		assert_not_null(packed, "load %s" % path)
		if packed == null:
			continue
		var node: Node = packed.instantiate()
		assert_not_null(node, "instantiate %s" % path)
		add_child_autofree(node)
		await wait_physics_frames(FRAMES)
		node.queue_free()
		await wait_process_frames(1)


func _collect(dir_path: String, out: Array[String]) -> void:
	if dir_path.trim_suffix("/") in SKIP_DIRS:
		return
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		_collect(dir_path.path_join(sub), out)
	for file: String in dir.get_files():
		if file.ends_with(".tscn"):
			out.append(dir_path.path_join(file))
