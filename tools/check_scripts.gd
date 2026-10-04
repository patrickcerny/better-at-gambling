extends SceneTree
## Loads every project .gd file so the parser reports errors (and untyped
## declarations, which project settings make errors). Exit 1 on any failure.

const SKIP: Array[String] = ["res://addons", "res://.godot", "res://build", "res://tools/godot"]


var _done: bool = false


# Runs on the first frame rather than in _init so autoload names (Log, Net...) resolve.
func _process(_delta: float) -> bool:
	if _done:
		return false
	_done = true
	var files: Array[String] = []
	_collect("res://", files)
	var bad: int = 0
	for path: String in files:
		var script: GDScript = load(path) as GDScript
		if script == null or not script.can_instantiate() and not _is_tool_script(path):
			push_error("script failed to load: %s" % path)
			bad += 1
	print("checked %d scripts, %d failed" % [files.size(), bad])
	quit(1 if bad > 0 else 0)
	return false


func _is_tool_script(path: String) -> bool:
	return path.begins_with("res://tools/")


func _collect(dir_path: String, out: Array[String]) -> void:
	if dir_path.trim_suffix("/") in SKIP:
		return
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		_collect(dir_path.path_join(sub), out)
	for f: String in dir.get_files():
		if f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
