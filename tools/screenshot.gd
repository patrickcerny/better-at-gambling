extends SceneTree
## Loads a scene, waits N frames, saves the viewport to a PNG, quits.
## Used by scripts/screenshot.sh (needs a display; Xvfb is fine).
## `--pixel N` sets the pixel look (video/pixel_scale 1..4) for this run without saving it; the
## log line also reports the mean frame time over the last `--perf-frames` (default 60) frames.

var _frames_left: int = 30
var _out: String = ""
var _perf_frames: int = 60
var _perf_sum_ms: float = 0.0
var _perf_n: int = 0


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
	_perf_frames = c.get_int("perf-frames", 60)
	_start.call_deferred(packed, c)


func _start(packed: PackedScene, c: Cmdline) -> void:
	if c.has("pixel"):  # the autoloads are up by now; not saved, so the dev's own setting survives
		Settings.set_value("video", "pixel_scale", c.get_int("pixel", 1))
	root.add_child(packed.instantiate())


func _process(delta: float) -> bool:
	_frames_left -= 1
	if _frames_left < _perf_frames:
		_perf_sum_ms += delta * 1000.0
		_perf_n += 1
	if _frames_left == 0:
		var img: Image = root.get_texture().get_image()
		var err: Error = img.save_png(_out)
		print("screenshot %s (%dx%d) err=%d pixel=%d frame_ms=%.2f over %d frames" % [_out, img.get_width(), img.get_height(), err, Settings.pixel_scale(), _perf_sum_ms / maxi(_perf_n, 1), _perf_n])
		quit(0 if err == OK else 1)
	return false
