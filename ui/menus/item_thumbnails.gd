class_name ItemThumbnails
extends Node
## Little 3D pictures of the items for the tutorial's item list (`HowToPlayPanel`): the item's own
## model (`ItemModels.make`, the one players hold), turned a little and rendered once each in an
## offscreen SubViewport, kept for the rest of the run. Works like `CosmeticThumbnails`:
## `texture_for` hands out the texture at once and fills it in when its turn comes (one render per
## frame). Headless: nothing renders, the textures stay blank.

const SIZE: int = 128
## The items are built facing forward (-z), the way the bean holds them out to the others, so the
## preview turns them round to face the camera (Patrick: "monkey ist verkehr rum"), a little to the
## side so they read as 3D. `TILT` sets single items upright (degrees, x/y/z, on top of the turn):
## bat.glb has its barrel at -y, so it stood on its head (Patrick: "wrong way"); it now leans
## barrel up across the square.
const YAW: float = 180.0 - 28.0
const TILT: Dictionary = {&"baseball_bat": Vector3(0, 0, 145)}
## Dev: extra turn for every item (tools/dev/item_thumbs_shot.gd --turn).
static var extra_turn: float = 0.0

## id -> ImageTexture, shared by every list that ever opens.
static var _cache: Dictionary = {}
## Ids still waiting for their render.
static var _queue: Array[StringName] = []

var _viewport: SubViewport
var _stand: Node3D
var _model: Node3D
var _busy: StringName = &""
var _wait: int = 0


func _ready() -> void:
	name = "ItemThumbnails"
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(SIZE, SIZE)
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_stand = build_stage(_viewport)


## Sets up `vp` as a little photo booth for one item (transparent background, its own world, the
## warm key and fill light, the camera a little above): returns the stand to put the model on.
## Shared with the item bar's live model of the held item (`ItemBar`).
static func build_stage(vp: SubViewport) -> Node3D:
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	var root := Node3D.new()
	vp.add_child(root)
	var stand := Node3D.new()
	root.add_child(stand)
	var cam := Camera3D.new()
	cam.current = true
	cam.fov = 30.0
	cam.position = Vector3(0.0, 0.35, 2.3)
	root.add_child(cam)
	cam.basis = Basis.looking_at(-cam.position, Vector3.UP)
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.94, 0.84)
	key.light_energy = 1.2
	key.rotation_degrees = Vector3(-35, 30, 0)
	root.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(1.0, 0.75, 0.55)
	fill.light_energy = 0.45
	fill.rotation_degrees = Vector3(-15, -150, 0)
	root.add_child(fill)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.66, 0.58)
	env.ambient_light_energy = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	return stand


## The picture of item `id` (blank until rendered).
static func texture_for(id: StringName) -> ImageTexture:
	if _cache.has(id):
		return _cache[id]
	var img := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var tex := ImageTexture.create_from_image(img)
	_cache[id] = tex
	_queue.append(id)
	return tex


## The y turn of `id`'s preview, degrees (also the item bar's live model turns from there).
static func preview_yaw(id: StringName) -> float:
	return YAW + extra_turn


## The whole preview rotation of `id`, degrees (turn plus `TILT`).
static func preview_rotation(id: StringName) -> Vector3:
	return Vector3(0.0, preview_yaw(id), 0.0) + (TILT.get(id, Vector3.ZERO) as Vector3)


## Whether every requested picture is done.
static func idle() -> bool:
	return _queue.is_empty()


func _process(_delta: float) -> void:
	if _busy != &"":
		_wait -= 1
		if _wait > 0:
			return
		var img: Image = _viewport.get_texture().get_image()
		if img != null and not img.is_empty():
			img.convert(Image.FORMAT_RGBA8)
			(_cache[_busy] as ImageTexture).update(img)
		_busy = &""
	if _queue.is_empty():
		return
	_busy = _queue.pop_front()
	if _model != null:
		_model.queue_free()
	_model = ItemModels.make(_busy, 1.0)
	_model.rotation_degrees = preview_rotation(_busy)
	_stand.add_child(_model)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_wait = 2  # rendered at the end of this frame; read it back next frame (plus one for safety)
