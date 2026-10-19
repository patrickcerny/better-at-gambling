class_name PixelView
extends Node
## Holds the 3D world of the match scene: everything 3D (`world`) renders inside a `SubViewport`
## at the window's full resolution with linear filtering, while every Control (HUD, menus, station
## overlays, the quiz and results 2D) is drawn on the window on top. (It once drew the world at a
## third of the resolution with hard pixels, "the pixel look"; removed in 0.9.15, the code lives on
## the branch `pixel-look-saved`.)
##
## The sub viewport shares the window's `World3D`, so physics, navigation, the environment and 3D
## audio are untouched. The container is sized in window pixels (not canvas units), so it renders
## exactly the window's pixels, as the bare window would. The dedicated server never builds the
## viewport: `setup(true)` leaves a plain Node3D.

## Window-level render settings the sub viewport copies so it draws exactly like the bare window.
const COPIED_SETTINGS: Array[StringName] = [
	&"msaa_3d", &"screen_space_aa", &"use_taa", &"use_debanding", &"use_occlusion_culling", &"mesh_lod_threshold",
	&"scaling_3d_mode", &"scaling_3d_scale", &"texture_mipmap_bias", &"fsr_sharpness",
	&"positional_shadow_atlas_size", &"positional_shadow_atlas_16_bits", &"positional_shadow_atlas_quad_0",
	&"positional_shadow_atlas_quad_1", &"positional_shadow_atlas_quad_2", &"positional_shadow_atlas_quad_3",
	&"canvas_item_default_texture_filter", &"canvas_item_default_texture_repeat",
]

## Parent for everything 3D (the map, avatars, props, minigame stages, the results podium).
var world: Node3D
## Null on the dedicated server.
var container: SubViewportContainer = null
var viewport: SubViewport = null


## Builds the holder; `dedicated` (the headless room server) skips the viewport altogether.
func setup(dedicated: bool) -> void:
	world = Node3D.new()
	world.name = "World"
	if dedicated:
		add_child(world)
		return
	container = SubViewportContainer.new()
	container.name = "PixelContainer"
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_PASS  # forwards into the viewport, then on to the router
	container.focus_mode = Control.FOCUS_NONE
	add_child(container)
	viewport = SubViewport.new()
	viewport.name = "PixelViewport"
	viewport.own_world_3d = false  # the window's world: same physics, navigation, environment
	viewport.audio_listener_enable_3d = true  # its camera positions 3D sound
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	viewport.add_child(world)
	for p: StringName in COPIED_SETTINGS:
		viewport.set(p, get_viewport().get(p))
	container.stretch_shrink = 1
	container.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	get_viewport().size_changed.connect(_fit)
	_fit()


## The viewport whose camera draws the world (the window itself on the server).
func world_viewport() -> Viewport:
	return viewport if viewport != null else get_viewport()


## Sizes the container in window pixels (the canvas may be scaled by the stretch mode), so each
## pixel the viewport renders is exactly one window pixel.
func _fit() -> void:
	if container == null or not is_inside_tree():
		return
	var root: Viewport = get_viewport()
	var window: Window = root as Window
	var px: Vector2 = Vector2(window.size) if window != null else root.get_visible_rect().size
	px = Vector2(maxf(px.x, 8.0), maxf(px.y, 8.0))
	var canvas: Vector2 = root.get_visible_rect().size
	container.position = Vector2.ZERO
	container.size = px
	container.scale = canvas / px


## Maps a point `cam.unproject_position()` gave (in the camera's viewport) onto a canvas item
## drawn at full resolution (the HUD). Identity when the camera draws the window itself.
static func to_canvas(cam: Camera3D, p: Vector2, ui: CanvasItem) -> Vector2:
	var cam_vp: Viewport = cam.get_viewport()
	var ui_vp: Viewport = ui.get_viewport()
	if cam_vp == null or ui_vp == null or cam_vp == ui_vp:
		return p
	return p * ui_vp.get_visible_rect().size / cam_vp.get_visible_rect().size

