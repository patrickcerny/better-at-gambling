extends SceneTree
## Instantiates a scene headless, runs N frames and prints what `--probe` asks for. Dev helper:
##   godot --headless -s tools/scene_probe.gd -- --scene res://x.tscn --frames 30

var _frames: int = 0
var _max: int = 30
var _node: Node


func _initialize() -> void:
	var c: Cmdline = Cmdline.parse(OS.get_cmdline_user_args())
	_max = c.get_int("frames", 30)
	var packed: PackedScene = load(c.get_string("scene", "")) as PackedScene
	if packed == null:
		push_error("scene not found")
		quit(1)
		return
	var t: int = Time.get_ticks_msec()
	_node = packed.instantiate()
	root.add_child(_node)
	print("instantiated %s in %d ms (%d children)" % [_node.name, Time.get_ticks_msec() - t, _node.get_child_count()])


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames >= _max:
		if _node != null and _node.has_method("probe"):
			print(_node.call("probe"))
		var errors: int = int(root.get_node("Log").get("error_count"))
		print("probe done after %d frames, errors=%d" % [_frames, errors])
		quit(1 if errors > 0 else 0)
	return false
