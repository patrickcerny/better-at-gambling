class_name SkinPreviewView
extends TextureRect
## A bean wearing one character skin (`Cosmetics.SKINS`), turning gently on a transparent
## SubViewport: the tiles of the `ClothesPanel`. Same pattern as `Logo3DView` (own world, full
## resolution); nothing 3D is built when headless. `portrait` frames the
## head and shoulders instead of the whole bean (the Tab list's player rows).

var skin: StringName = &"bean"
var color: Color = Palette.player_color(0)
var portrait: bool = false
var visuals: AvatarVisuals
var _viewport: SubViewport
var _t: float = 0.0


static func make(p_skin: StringName, min_size: Vector2 = Vector2(150, 180)) -> SkinPreviewView:
	var v := SkinPreviewView.new()
	v.name = "Preview"
	v.skin = p_skin
	v.custom_minimum_size = min_size
	return v


## Re-dresses the bean (a player changed skin or colour) without rebuilding the viewport.
func set_look(p_skin: StringName, p_color: Color) -> void:
	skin = p_skin
	color = p_color
	if visuals != null:
		visuals.set_skin(skin)
		visuals.set_color(color)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	visuals.skin_id = skin
	root.add_child(visuals)
	visuals.set_color(color)
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.position = Vector3(0, 1.2, -2.0) if portrait else Vector3(0, 1.0, -3.6)
	root.add_child(cam)
	cam.look_at_from_position(cam.position, Vector3(0, 1.0 if portrait else 0.82, 0), Vector3.UP)
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
	if visuals != null:
		visuals.rotation.y = sin(_t * 0.7) * (0.35 if portrait else 0.6)


func _fit() -> void:
	if _viewport == null:
		return
	var window: Window = get_window()
	var stretch: Vector2 = Vector2(window.size) / get_viewport_rect().size if window != null else Vector2.ONE
	var px: Vector2 = size * stretch
	_viewport.size = Vector2i(maxi(int(px.x), 32), maxi(int(px.y), 32))
	_viewport.msaa_3d = Viewport.MSAA_4X
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
