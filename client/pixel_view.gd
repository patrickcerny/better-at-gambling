class_name PixelView
extends Node
## The "pixel look" (Patrick: "this pixelated blur effect the game Yap Yap has ... a bit of 8-bit
## style"): the 3D casino renders at 1/2, 1/3 or 1/4 of the window's resolution and is blown back
## up with hard, nearest-neighbour pixels, while every Control (HUD, menus, station overlays, the
## quiz and results 2D) stays at full resolution on top. No dithering, no palette.
##
## The 3D world (`world`) lives inside a `SubViewport` that shares the window's `World3D`, so
## physics, navigation, the environment and 3D audio are untouched; only the camera and the
## pixels move. The container is sized in window pixels (not canvas units), so "Off" renders
## exactly the window's pixels, as the bare window would. The setting (`video/pixel_scale`, the
## shrink factor 1..4) applies live through `Settings.changed`. The dedicated server never builds
## the viewport: `setup(true)` leaves a plain Node3D.

## Shrink factor for each setting entry, in the order the settings panel lists them.
const SCALES: Array[int] = [1, 2, 3, 4]
const LABELS: Array[String] = ["Off", "Light (1/2)", "Retro (1/3)", "Chunky (1/4)"]
## Window-level render settings the sub viewport copies so Off looks exactly like the bare window.
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
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
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
	_apply()
	Settings.changed.connect(_apply)
	get_viewport().size_changed.connect(_fit)
	_fit()


## Current shrink factor (1 = off).
func shrink() -> int:
	return container.stretch_shrink if container != null else 1


## The viewport whose camera draws the world (the window itself on the server).
func world_viewport() -> Viewport:
	return viewport if viewport != null else get_viewport()


func _apply() -> void:
	if container == null:
		return
	var s: int = Settings.pixel_scale()
	if s != container.stretch_shrink:
		container.stretch_shrink = s
		Log.info(&"video", "pixel look: 1/%d" % s)


## Sizes the container in window pixels (the canvas may be scaled by the stretch mode), so each
## pixel the viewport renders covers exactly `shrink` window pixels and Off is 1:1.
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


## Shrink factor of the viewport `node` is drawn in (1 outside a pixel view).
static func shrink_of(node: Node) -> int:
	var vp: Viewport = node.get_viewport() if node.is_inside_tree() else null
	if vp is SubViewport and vp.get_parent() is SubViewportContainer:
		var c: SubViewportContainer = vp.get_parent()
		return c.stretch_shrink if c.stretch else 1
	return 1
