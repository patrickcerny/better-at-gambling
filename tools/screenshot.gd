extends SceneTree
## Loads a scene, waits N frames, saves the viewport to a PNG, quits.
## Used by scripts/screenshot.sh (needs a display; Xvfb is fine).
## `--pixel N` overrides the fixed pixel look (shrink 1..4, 1 = off) for this run only; the
## log line also reports the mean frame time and the window's measured render time (CPU and GPU)
## over the last `--perf-frames` (default 60) frames; `--no-vsync` so a swap wait doesn't hide them.
## `--cam x,y,z --look x,y,z [--fov 70]` swaps in a free camera for the last frames (map shots).

var _frames_left: int = 30
var _out: String = ""
var _perf_frames: int = 60
var _perf_sum_ms: float = 0.0
var _perf_n: int = 0
var _perf_cpu_ms: float = 0.0
var _perf_gpu_ms: float = 0.0
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
	_perf_frames = c.get_int("perf-frames", 60)
	_start.call_deferred(packed, c)


func _start(packed: PackedScene, c: Cmdline) -> void:
	if c.has("pixel"):  # the autoloads are up by now; a run-only override, never saved
		_settings().call(&"set_pixel_override", c.get_int("pixel", 1))
	if c.has_flag("no-vsync"):
		_settings().set_value("video", "vsync", false)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	root.add_child(packed.instantiate())


## The `Settings` autoload (a SceneTree script can't name autoloads at compile time).
func _settings() -> Node:
	return root.get_node("Settings")


func _process(delta: float) -> bool:
	_frames_left -= 1
	if _frames_left < _perf_frames:
		_perf_sum_ms += delta * 1000.0
		_perf_cpu_ms += RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid())
		_perf_gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
		_perf_n += 1
	if _frames_left == 4 and _cam_pos != Vector3.INF:
		var cam := Camera3D.new()
		cam.fov = _fov
		cam.near = 0.05
		# The match renders its 3D inside the pixel view's own viewport: the camera goes there.
		var host: Node = root
		for child: Node in root.get_children():
			var pv: Variant = child.get("pixel_view")  # MatchScene (no class reference: this tool script loads before the game's)
			if pv != null and (pv as Node).get("world") != null:
				host = (pv as Node).get("world")
		host.add_child(cam)
		cam.global_position = _cam_pos
		cam.look_at(_look_at, Vector3.UP)
		cam.current = true
	if _frames_left == 0:
		var img: Image = root.get_texture().get_image()
		var err: Error = img.save_png(_out)
		var n: int = maxi(_perf_n, 1)
		print("screenshot %s (%dx%d) err=%d pixel=%d frame_ms=%.2f render_cpu_ms=%.2f render_gpu_ms=%.2f over %d frames" % [_out, img.get_width(), img.get_height(), err, _settings().pixel_scale(), _perf_sum_ms / n, _perf_cpu_ms / n, _perf_gpu_ms / n, _perf_n])
		quit(0 if err == OK else 1)
	return false


static func _vec(s: String) -> Vector3:
	var p: PackedStringArray = s.split(",")
	if p.size() != 3:
		return Vector3.ZERO
	return Vector3(float(p[0]), float(p[1]), float(p[2]))
