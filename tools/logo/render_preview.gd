extends SceneTree
## Renders the 3D logo on a transparent background from a few angles.
##   xvfb-run godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility \
##     -s tools/logo/render_preview.gd -- --out DIR [--size 1600x800]

const ANGLES: Array = [["front", 0.0, 0.0], ["left", -28.0, 4.0], ["right", 26.0, -6.0], ["above", 8.0, 22.0]]

var _out: String
var _vp: SubViewport
var _logo: Logo3D
var _i: int = 0
var _wait: int = 0


func _initialize() -> void:
	var c: Cmdline = Cmdline.parse(OS.get_cmdline_user_args())
	_out = c.get_string("out", "user://logo_preview")
	var size: PackedStringArray = c.get_string("size", "1600x800").split("x")
	DirAccess.make_dir_recursive_absolute(_out)
	_vp = SubViewport.new()
	_vp.size = Vector2i(int(size[0]), int(size[1]))
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child.call_deferred(_vp)
	_logo = Logo3D.new()
	_logo.sway = false
	_vp.add_child(_logo)
	_set_angle()


func _set_angle() -> void:
	_logo.yaw_deg = ANGLES[_i][1]
	_logo.pitch_deg = ANGLES[_i][2]
	if _logo.is_inside_tree():
		_logo._apply_pose()
	_wait = 8


func _process(_delta: float) -> bool:
	if _wait > 0:
		_wait -= 1
		return false
	var img: Image = _vp.get_texture().get_image()
	var path: String = "%s/logo_%s.png" % [_out, ANGLES[_i][0]]
	img.save_png(path)
	print("[logo] saved ", path, " ", img.get_size(), " alpha=", img.detect_alpha())
	_i += 1
	if _i >= ANGLES.size():
		return true
	_set_angle()
	return false
