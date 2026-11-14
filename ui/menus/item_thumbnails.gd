class_name ItemThumbnails
extends Node
## Little 3D pictures of the items for the tutorial's item list (`HowToPlayPanel`): the item's own
## model (`ItemModels.make`, the one players hold), turned a little and rendered once each in an
## offscreen SubViewport, kept for the rest of the run. Works like `CosmeticThumbnails`:
## `texture_for` hands out the texture at once and fills it in when its turn comes (one render per
## frame). Headless: nothing renders, the textures stay blank.

const SIZE: int = 128

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
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	var root := Node3D.new()
	_viewport.add_child(root)
	_stand = Node3D.new()
	root.add_child(_stand)
	var cam := Camera3D.new()
	cam.current = true
	cam.fov = 30.0
	cam.position = Vector3(0.0, 0.35, 2.3)
	root.add_child(cam)
	cam.look_at(Vector3.ZERO, Vector3.UP)
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


## The picture of item `id` (blank until rendered).
static func texture_for(id: StringName) -> ImageTexture:
	if _cache.has(id):
		return _cache[id]
	var img := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var tex := ImageTexture.create_from_image(img)
	_cache[id] = tex
	_queue.append(id)
	return tex


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
	_model.rotation_degrees = Vector3(0.0, -28.0, 0.0)
	_stand.add_child(_model)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_wait = 2  # rendered at the end of this frame; read it back next frame (plus one for safety)
