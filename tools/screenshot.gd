extends SceneTree
## Loads a scene, waits N frames, saves the viewport to a PNG, quits.
## Used by scripts/screenshot.sh (needs a display; Xvfb is fine).

var _frames_left: int = 30
var _out: String = ""


func _initialize() -> void:
	var c: Cmdline = Cmdline.parse(OS.get_cmdline_user_args())
	_out = c.get_string("out", "user://screenshot.png")
	_frames_left = c.get_int("frames", 30)
	var packed: PackedScene = load(c.get_string("scene", "res://ui/menus/main_menu.tscn")) as PackedScene
	if packed == null:
		push_error("scene not found")
		quit(1)
		return
	root.size = Vector2i(1920, 1080)
	root.add_child.call_deferred(packed.instantiate())


func _process(_delta: float) -> bool:
	_frames_left -= 1
	if _frames_left == 0:
		var img: Image = root.get_texture().get_image()
		var err: Error = img.save_png(_out)
		print("screenshot %s (%dx%d) err=%d" % [_out, img.get_width(), img.get_height(), err])
		quit(0 if err == OK else 1)
	return false
