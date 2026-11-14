class_name BeanPreviewView
extends TextureRect
## A bean in one colour turning gently on a transparent SubViewport: the cosmetics shop's preview
## and the Tab list's player portraits. Same pattern as `Logo3DView` (own world, full
## resolution); nothing 3D is built when headless. `portrait` frames the head and shoulders
## instead of the whole bean (the Tab list's player rows).

var color: Color = Palette.player_color(0)
## Outfit pieces worn (kind -> item id).
var outfit: Dictionary = {}
var portrait: bool = false
## The shop's big preview: drag with the mouse (or the right stick) to turn the bean, it keeps
## spinning a little and settles back into a slow sway; a pedestal under its feet; the whole bean
## and the tallest hat in frame.
var interactive: bool = false
## Extra turn from dragging (radians), and its spin speed.
var turn: float = 0.0
var _spin: float = 0.0
var _dragging: bool = false
## The turn to ease towards when nobody drags (a cape picked: show its back).
var rest_turn: float = 0.0
var visuals: AvatarVisuals
var _viewport: SubViewport
var _t: float = 0.0
var _cam: Camera3D
## The interactive camera's framing: (look-at height, distance), eased towards `_frame_goal`.
var _frame: Vector2 = Vector2(0.95, 5.0)
var _frame_goal: Vector2 = Vector2(0.95, 5.0)


static func make(p_color: Color, min_size: Vector2 = Vector2(150, 180)) -> BeanPreviewView:
	var v := BeanPreviewView.new()
	v.name = "Preview"
	v.color = p_color
	v.custom_minimum_size = min_size
	return v


## Dresses the bean (kind -> item id) without rebuilding the viewport.
func set_outfit(o: Dictionary) -> void:
	outfit = o.duplicate()
	if visuals != null:
		visuals.set_outfit(outfit)


## Recolours the bean without rebuilding the viewport.
func set_bean_color(p_color: Color) -> void:
	color = p_color
	if visuals != null:
		visuals.set_color(color)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	if interactive:
		mouse_default_cursor_shape = Control.CURSOR_DRAG
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	_viewport = SubViewport.new()
	_viewport.name = "PreviewViewport"
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_viewport)
	var root := Node3D.new()
	_viewport.add_child(root)
	visuals = AvatarVisuals.new()
	root.add_child(visuals)
	visuals.set_color(color)
	visuals.set_outfit(outfit)
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.position = Vector3(0, 1.2, -2.0) if portrait else (Vector3(0, 1.45, -5.6) if interactive else Vector3(0, 1.0, -3.6))
	root.add_child(cam)
	cam.look_at_from_position(cam.position, Vector3(0, 1.0 if portrait else (0.98 if interactive else 0.82), 0), Vector3.UP)
	_cam = cam
	if interactive:
		_place_camera()
	if interactive:
		var stand := MeshInstance3D.new()
		stand.name = "Pedestal"
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.78
		cyl.bottom_radius = 0.84
		cyl.height = 0.12
		cyl.radial_segments = 40
		stand.mesh = cyl
		stand.material_override = GreyboxKit.material(Palette.VIP_BURGUNDY, 0.0, 0.6)
		stand.position.y = -0.06
		root.add_child(stand)
		var rim := MeshInstance3D.new()
		var tor := TorusMesh.new()
		tor.inner_radius = 0.8
		tor.outer_radius = 0.86
		tor.rings = 40
		rim.mesh = tor
		rim.material_override = GreyboxKit.material(Palette.WARM_GOLD, 0.7, 0.35)
		rim.position.y = -0.01
		root.add_child(rim)
	cam.current = true
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.94, 0.84)
	key.light_energy = 1.1
	key.rotation_degrees = Vector3(-35, 150, 0)
	root.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(1.0, 0.7, 0.5)
	fill.light_energy = 0.4
	fill.rotation_degrees = Vector3(-10, 220, 0)
	root.add_child(fill)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.62, 0.56)
	env.ambient_light_energy = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	texture = _viewport.get_texture()
	_t = randf() * TAU
	resized.connect(_fit)
	_fit()


func _process(delta: float) -> void:
	_t += delta
	if visuals == null:
		return
	if not interactive:
		visuals.rotation.y = sin(_t * 0.7) * (0.35 if portrait else 0.6)
		return
	var stick: float = Input.get_axis(&"look_left", &"look_right") if is_visible_in_tree() else 0.0
	if absf(stick) > 0.2:
		_spin = stick * 3.5
	if not _dragging:
		turn += _spin * delta
		_spin = move_toward(_spin, 0.0, 5.0 * delta)
		if absf(_spin) < 0.05:
			# Settle back towards the rest pose (the nearest full turn of it).
			var goal: float = rest_turn + roundf((turn - rest_turn) / TAU) * TAU
			turn = lerpf(turn, goal, minf(1.0, 1.5 * delta))
	visuals.rotation.y = turn + sin(_t * 0.6) * 0.18
	if not _frame.is_equal_approx(_frame_goal):
		_frame = _frame.lerp(_frame_goal, minf(1.0, 6.0 * delta))
		_place_camera()


## Frames the part of the bean that `kind` dresses (a hat: the head; boots: the feet; anything
## else: the whole bean), easing there.
func focus(kind: StringName) -> void:
	match kind:
		CosmeticDef.KIND_HAT:
			_frame_goal = Vector2(1.45, 3.3)
		CosmeticDef.KIND_SHIRT:
			_frame_goal = Vector2(0.85, 3.9)
		CosmeticDef.KIND_PANTS:
			_frame_goal = Vector2(0.5, 3.6)
		CosmeticDef.KIND_BOOTS:
			_frame_goal = Vector2(0.55, 4.2)
		_:
			_frame_goal = Vector2(0.95, 5.0)


func _place_camera() -> void:
	if _cam == null:
		return
	var look := Vector3(0, _frame.x, 0)
	_cam.look_at_from_position(look + Vector3(0, 0.12 * _frame.y, -_frame.y), look, Vector3.UP)


func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_dragging = (event as InputEventMouseButton).pressed
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var dx: float = (event as InputEventMouseMotion).relative.x
		turn += dx * 0.012
		_spin = clampf(dx * 0.012 / maxf(get_process_delta_time(), 0.001), -8.0, 8.0)
		accept_event()


## Shows the back (capes) or the front.
func face(back: bool) -> void:
	rest_turn = PI if back else 0.0
	_spin = 0.0


func _fit() -> void:
	if _viewport == null:
		return
	var window: Window = get_window()
	var stretch: Vector2 = Vector2(window.size) / get_viewport_rect().size if window != null else Vector2.ONE
	var px: Vector2 = size * stretch
	_viewport.size = Vector2i(maxi(int(px.x), 32), maxi(int(px.y), 32))
	_viewport.msaa_3d = Viewport.MSAA_4X
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
