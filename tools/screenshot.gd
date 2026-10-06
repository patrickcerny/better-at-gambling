extends SceneTree
## Loads a scene, waits N frames, saves the viewport to a PNG, quits.
## Used by scripts/screenshot.sh (needs a display; Xvfb is fine).
## `--cam x,y,z --look x,y,z [--fov 70]` swaps in a free camera for the last frames (map shots).

var _frames_left: int = 30
var _out: String = ""
var _cam_pos: Vector3 = Vector3.INF
var _look_at: Vector3 = Vector3.ZERO
var _fov: float = 70.0


func _initialize() -> void:
	var c: Cmdline = Cmdline.parse(OS.get_cmdline_user_args())
	_out = c.get_string("out", "user://screenshot.png")
	_frames_left = c.get_int("frames", 30)
	if c.has("cam"):
		_cam_pos = _vec(c.get_string("cam"))
		_look_at = _vec(c.get_string("look", "0,1,0"))
		_fov = c.get_float("fov", 70.0)
	var packed: PackedScene = load(c.get_string("scene", "res://ui/menus/main_menu.tscn")) as PackedScene
	if packed == null:
		push_error("scene not found")
		quit(1)
		return
	root.size = Vector2i(1920, 1080)
	root.add_child.call_deferred(packed.instantiate())


func _process(_delta: float) -> bool:
	_frames_left -= 1
	if _frames_left == 4 and _cam_pos != Vector3.INF:
		var cam := Camera3D.new()
		cam.fov = _fov
		cam.near = 0.05
		root.add_child(cam)
		cam.global_position = _cam_pos
		cam.look_at(_look_at, Vector3.UP)
		cam.current = true
	if _frames_left == 0:
		var img: Image = root.get_texture().get_image()
		var err: Error = img.save_png(_out)
		print("screenshot %s (%dx%d) err=%d" % [_out, img.get_width(), img.get_height(), err])
		quit(0 if err == OK else 1)
	return false


static func _vec(s: String) -> Vector3:
	var p: PackedStringArray = s.split(",")
	if p.size() != 3:
		return Vector3.ZERO
	return Vector3(float(p[0]), float(p[1]), float(p[2]))
