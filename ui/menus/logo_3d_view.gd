class_name Logo3DView
extends TextureRect
## The swaying 3D title logo (`Logo3D`) as a menu Control. It renders into its own transparent
## SubViewport and, like the casino behind it, goes through the pixel look: under
## `Settings.pixel_scale()` 2..4 it renders at that fraction of its on-screen pixels and is blown
## back up with hard pixels. Nothing 3D is built when headless; the Control keeps its size.

var logo: Logo3D
var _viewport: SubViewport


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	if DisplayServer.get_name() == "headless":
		return
	_viewport = SubViewport.new()
	_viewport.name = "LogoViewport"
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_viewport)
	logo = Logo3D.new()
	_viewport.add_child(logo)
	texture = _viewport.get_texture()
	resized.connect(_fit)
	Settings.changed.connect(_fit)
	get_viewport().size_changed.connect(_fit)
	_fit()


func _fit() -> void:
	if _viewport == null:
		return
	var shrink: int = Settings.pixel_scale()
	# On-screen pixels: canvas units times the window's stretch.
	var window: Window = get_window()
	var stretch: Vector2 = Vector2(window.size) / get_viewport_rect().size if window != null else Vector2.ONE
	var px: Vector2 = size * stretch
	_viewport.size = Vector2i(maxi(int(px.x / shrink), 32), maxi(int(px.y / shrink), 16))
	_viewport.msaa_3d = Viewport.MSAA_DISABLED if shrink > 1 else Viewport.MSAA_4X
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if shrink > 1 else CanvasItem.TEXTURE_FILTER_LINEAR
