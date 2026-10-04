extends GutTest
## `core/` and `games/*_logic.gd` are pure logic: no Node, scene, I/O or engine-singleton use.

const BANNED: Array[String] = ["extends Node", "get_tree(", "PackedScene", "FileAccess", "OS.", "Input.", "Engine.", "get_node(", "@onready", "preload(", "load("]


func test_no_node_references_in_core_or_game_logic() -> void:
	var files: Array[String] = []
	_collect("res://core", files)
	_collect("res://games", files)
	assert_gt(files.size(), 10)
	for path: String in files:
		if path.begins_with("res://games") and not path.ends_with("_logic.gd") and not path.ends_with("station_logic_base.gd") and not path.ends_with("progressive_jackpot.gd"):
			continue
		var text: String = FileAccess.get_file_as_string(path)
		for banned: String in BANNED:
			assert_false(text.contains(banned), "%s uses %s" % [path, banned])


func _collect(dir_path: String, out: Array[String]) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		_collect(dir_path.path_join(sub), out)
	for f: String in dir.get_files():
		if f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
