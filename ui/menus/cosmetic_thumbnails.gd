class_name CosmeticThumbnails
extends Node
## Little 3D pictures of the cosmetics for the shop's tiles and tab icons: a bean wearing the piece,
## framed on it (a hat on the head, boots at the feet, a cape from behind), rendered once each in an
## offscreen SubViewport and kept for the rest of the run. `texture_for` hands out the texture at
## once and fills it in when its turn comes (one render per frame, so opening the shop never
## stalls). Headless: nothing renders, the textures stay blank.

const SIZE: int = 256
## The bean colour the outfit pictures use (warm cream, every piece reads on it).
const BEAN_COLOR: Color = Color("#E9DCBC")

## id -> ImageTexture, shared by every shop that ever opens.
static var _cache: Dictionary = {}
## Ids still waiting for their render.
static var _queue: Array[StringName] = []

var _viewport: SubViewport
var _bean: AvatarVisuals
var _cam: Camera3D
var _busy: StringName = &""
var _wait: int = 0


func _ready() -> void:
	name = "CosmeticThumbnails"
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
	_bean = AvatarVisuals.new()
	root.add_child(_bean)
	_bean.set_color(BEAN_COLOR)
	_cam = Camera3D.new()
	_cam.current = true
	root.add_child(_cam)
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.94, 0.84)
	key.light_energy = 1.15
	key.rotation_degrees = Vector3(-35, 160, 0)
	root.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(1.0, 0.75, 0.55)
	fill.light_energy = 0.45
	fill.rotation_degrees = Vector3(-15, 20, 0)
	root.add_child(fill)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.66, 0.58)
	env.ambient_light_energy = 0.85
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)


## The picture of item `id` (blank until rendered). `urgent` ones (the tab icons) jump the queue.
static func texture_for(id: StringName, urgent: bool = false) -> ImageTexture:
	if _cache.has(id):
		return _cache[id]
	var img := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var tex := ImageTexture.create_from_image(img)
	_cache[id] = tex
	if urgent:
		_queue.push_front(id)
	else:
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
	_stage(_busy)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_wait = 2  # rendered at the end of this frame; read it back next frame (plus one for safety)


## Dresses the bean for item `id` and frames the camera on it.
func _stage(id: StringName) -> void:
	var d: CosmeticDef = CosmeticShop.default().find(id)
	var kind: StringName = d.kind if d != null else &""
	var pack: CosmeticPack = CosmeticShop.default().find_pack(id)
	if pack != null:
		_bean.set_outfit(CosmeticsPanel.pack_outfit(pack))  # a whole outfit, the whole bean
	else:
		_bean.set_outfit({kind: id} if kind in CosmeticDef.OUTFIT_KINDS else {})
	_bean.set_color(Palette.player_color(d.color_index) if d != null and kind == CosmeticDef.KIND_COLOR else BEAN_COLOR)
	_bean.rotation.y = PI + 0.45  # face the camera, a little turned
	# Boots alone read best: no body or arms looming over them.
	var bare_feet: bool = kind == CosmeticDef.KIND_BOOTS
	_bean.body.visible = not bare_feet
	_bean.arm_l.visible = not bare_feet
	_bean.arm_r.visible = not bare_feet
	var look := Vector3(0, 0.9, 0)
	var dist: float = 3.6
	var height: float = 0.25
	match kind:
		CosmeticDef.KIND_HAT:
			look = Vector3(0, 1.6, 0)
			dist = 2.0
			height = 0.35
		CosmeticDef.KIND_SHIRT:
			look = Vector3(0, 0.82, 0)
			dist = 2.3
		CosmeticDef.KIND_PANTS:
			look = Vector3(0, 0.45, 0)
			dist = 2.2
		CosmeticDef.KIND_CAPE:
			_bean.rotation.y = 0.55  # from behind
			look = Vector3(0, 0.75, 0)
			dist = 3.0
		CosmeticDef.KIND_BOOTS:
			look = Vector3(0, 0.1, -0.03)
			dist = 1.45
			height = 0.55
	_cam.fov = 32.0
	_cam.position = look + Vector3(0.0, height, dist)
	_cam.look_at(look, Vector3.UP)
