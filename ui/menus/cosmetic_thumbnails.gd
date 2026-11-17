class_name CosmeticThumbnails
extends ThumbnailRenderer
## Little 3D pictures of the cosmetics for the shop's tiles and tab icons: a bean wearing the piece,
## framed on it (a hat on the head, boots at the feet, a cape from behind), rendered once each in an
## offscreen SubViewport and kept for the rest of the run. `texture_for` hands out the texture at
## once and fills it in when its turn comes (`ThumbnailRenderer`: cached on disk per build, rendered
## a few frames apart, read back without stalling). Headless: nothing renders, the textures stay blank.

const SIZE: int = 256
## The bean colour the outfit pictures use (warm cream, every piece reads on it).
const BEAN_COLOR: Color = Color("#E9DCBC")

const KIND: String = "cosmetics"

var _bean: AvatarVisuals
var _cam: Camera3D


func _ready() -> void:
	name = "CosmeticThumbnails"
	kind = KIND
	image_size = Vector2i(SIZE, SIZE)
	if setup_viewport() == null:
		return
	var root := Node3D.new()
	_viewport.add_child(root)
	_bean = AvatarVisuals.new()
	root.add_child(_bean)
	_bean.set_color(BEAN_COLOR)
	_bean.no_blink = true  # always open eyes in the pictures
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
	return request(KIND, String(id), Vector2i(SIZE, SIZE), urgent)


## Whether every requested picture is done.
static func idle() -> bool:
	return queue_empty(KIND)


func _stage(key: String) -> void:
	_dress(StringName(key))


## Dresses the bean for item `id` and frames the camera on it.
func _dress(id: StringName) -> void:
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
		CosmeticDef.KIND_EYES:
			_bean.rotation.y = PI + 0.2
			look = Vector3(0, 1.02, 0)
			dist = 2.1
			height = 0.05
		CosmeticDef.KIND_MOUTH:
			_bean.rotation.y = PI + 0.15
			look = Vector3(0, 0.9, 0)
			dist = 1.9
			height = 0.05
		CosmeticDef.KIND_BEARD:
			_bean.rotation.y = PI + 0.3
			look = Vector3(0, 0.82 if id != &"beard_wizard" else 0.62, 0)
			dist = 2.3 if id != &"beard_wizard" else 2.9
			height = 0.1
	_cam.fov = 32.0
	_cam.position = look + Vector3(0.0, height, dist)
	_cam.look_at(look, Vector3.UP)
