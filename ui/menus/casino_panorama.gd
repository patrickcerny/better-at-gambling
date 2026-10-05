class_name CasinoPanorama
extends Control
## The menu and loading-screen backdrop (Patrick, 2026-10-05: "a moving camera of the game, a bit
## blurry and tilting left and right, like Minecraft but with the casino room"). A decorative copy
## of the Lucky Lounge renders into its own half-resolution world; a camera drifts slowly along a
## loop over the casino floor, looks around and rolls gently from side to side, and a blur shader
## softens the result. Nothing is built when headless.

## Camera loop over the casino floor (x, y, z), visited in order and wrapped.
const PATH: Array[Vector3] = [
	Vector3(-8, 3.2, 12.5), Vector3(-1, 3.0, 6.5), Vector3(-16, 3.0, 7.0), Vector3(-19, 3.2, -3.0),
	Vector3(-14, 3.6, -11.0), Vector3(0, 3.2, -13.0), Vector3(14, 3.0, -12.0), Vector3(6, 2.6, 3.0),
]
## Seconds for one leg between two path points.
const LEG_SECONDS: float = 14.0
## Gentle side-to-side roll (degrees) and its period (seconds).
const ROLL_DEG: float = 4.0
const ROLL_PERIOD: float = 9.0
## Slow look-around: yaw swing (degrees) on top of looking at the floor's centre.
const LOOK_SWING_DEG: float = 22.0
const LOOK_PERIOD: float = 23.0

@export var blur_px: float = 2.0
@export var darken: float = 0.35
## Starting point on the loop (in legs), so the menu and the loading screen don't show the same shot.
@export var start_leg: float = 0.0

var camera: Camera3D
var _viewport: SubViewport
var _view: TextureRect
var _t: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if DisplayServer.get_name() == "headless":
		return
	_t = start_leg * LEG_SECONDS
	_viewport = SubViewport.new()
	_viewport.name = "Panorama"
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	add_child(_viewport)
	var map := LuckyLounge.new()
	map.bake_navmesh = false
	_viewport.add_child(map)
	camera = Camera3D.new()
	camera.fov = 70.0
	camera.current = true
	_viewport.add_child(camera)
	_view = TextureRect.new()
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_view.texture = _viewport.get_texture()
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://ui/menus/panorama_blur.gdshader")
	mat.set_shader_parameter(&"blur_px", blur_px)
	mat.set_shader_parameter(&"darken", darken)
	_view.material = mat
	add_child(_view)
	resized.connect(_fit)
	_fit()
	_place_camera()


func _fit() -> void:
	if _viewport != null:
		_viewport.size = Vector2i(maxi(int(size.x * 0.5), 64), maxi(int(size.y * 0.5), 36))


func _process(delta: float) -> void:
	if camera == null:
		return
	_t += delta
	_place_camera()


## Camera pose at the current time: a smooth (Catmull-Rom) point on the loop, looking at the
## floor's centre with a slow swing, rolled gently left and right.
func _place_camera() -> void:
	var legs: float = _t / LEG_SECONDS
	var i: int = int(floor(legs))
	var f: float = legs - i
	var n: int = PATH.size()
	var p0: Vector3 = PATH[posmod(i - 1, n)]
	var p1: Vector3 = PATH[posmod(i, n)]
	var p2: Vector3 = PATH[posmod(i + 1, n)]
	var p3: Vector3 = PATH[posmod(i + 2, n)]
	var pos: Vector3 = p1.cubic_interpolate(p2, p0, p3, f)
	var to_centre: Vector3 = Vector3(0, 1.2, -2) - pos
	var yaw: float = atan2(-to_centre.x, -to_centre.z) + deg_to_rad(LOOK_SWING_DEG) * sin(TAU * _t / LOOK_PERIOD)
	var pitch: float = atan2(to_centre.y, Vector2(to_centre.x, to_centre.z).length())
	camera.position = pos
	camera.rotation = Vector3(pitch, yaw, deg_to_rad(ROLL_DEG) * sin(TAU * _t / ROLL_PERIOD))
