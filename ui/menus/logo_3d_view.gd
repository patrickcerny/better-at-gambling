class_name Logo3DView
extends TextureRect
## The swaying 3D title logo (`Logo3D`) as a menu Control. It renders into its own transparent
## SubViewport at its full on-screen resolution (4x MSAA, linear filtering). Nothing 3D is built
## when headless; the Control keeps its size.
## The one way the game shows its logo: the main menu (main_menu.tscn), the loading screen and the
## joining screen (`Loading`) all use this view; build one in code with `make`.
## With `spinnable` (the main menu) the sign can be dragged round with the mouse (or a finger) and
## spun with the right stick (`LogoSpin`); every full turn adds to the profile's `logo_spins`, and
## 1000 of them unlock the hidden achievement (`Achievements.LOGO_SPINS`). The count stands on the
## sign's back (`Logo3D.set_spins`).

## Drag / right stick spins the sign (main menu only; the loading screens just show it).
@export var spinnable: bool = false

var logo: Logo3D
var spin := LogoSpin.new()
## Unlocks achievements by API name (tests swap it for a recorder).
var unlock: Callable = func(ids: Array[StringName]) -> void: SteamSvc.unlock_achievements(ids)
var _viewport: SubViewport


## A centred logo of `min_size` (canvas units) for a container.
static func make(min_size: Vector2 = Vector2(640, 516)) -> Logo3DView:
	var v := Logo3DView.new()
	v.name = "Logo"
	v.custom_minimum_size = min_size
	v.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return v


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP if spinnable else Control.MOUSE_FILTER_IGNORE
	mouse_default_cursor_shape = Control.CURSOR_DRAG if spinnable else Control.CURSOR_ARROW
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
	if spinnable:  # the spin counter on the back
		logo.set_spins(ProfileManager.profile.logo_spins if ProfileManager.profile != null else 0)
	resized.connect(_fit)
	get_viewport().size_changed.connect(_fit)
	_fit()


func _fit() -> void:
	if _viewport == null:
		return
	# On-screen pixels: canvas units times the window's stretch.
	var window: Window = get_window()
	var stretch: Vector2 = Vector2(window.size) / get_viewport_rect().size if window != null else Vector2.ONE
	var px: Vector2 = size * stretch
	_viewport.size = Vector2i(maxi(int(px.x), 32), maxi(int(px.y), 16))
	_viewport.msaa_3d = Viewport.MSAA_4X
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR


func _gui_input(event: InputEvent) -> void:
	if not spinnable:
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			spin.press()
		else:
			spin.release()
		accept_event()
		return
	var mm := event as InputEventMouseMotion
	if mm != null and spin.dragging:
		_credit(spin.drag(mm.relative.x))
		accept_event()


func _process(delta: float) -> void:
	if not spinnable:
		return
	var stick: float = Input.get_axis(&"look_left", &"look_right") if is_visible_in_tree() else 0.0
	if not is_visible_in_tree() and spin.dragging:
		spin.release()  # the menu hid the logo mid-drag
	_credit(spin.step(delta, stick))
	if logo != null:
		logo.spin_deg = spin.yaw


## Adds `turns` full turns to the profile and unlocks the achievement once there are enough.
func _credit(turns: int) -> void:
	if turns <= 0:
		return
	var total: int = ProfileManager.add_logo_spins(turns)
	if logo != null:
		logo.set_spins(total)
	var earned: Array[StringName] = Achievements.from_logo_spins(total)
	if not earned.is_empty():
		unlock.call(earned)
