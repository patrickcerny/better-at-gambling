class_name ItemThumbnails
extends ThumbnailRenderer
## Little 3D pictures of the items for the tutorial's item list (`HowToPlayPanel`): the item's own
## model (`ItemModels.make`, the one players hold), turned a little and rendered once each in an
## offscreen SubViewport, kept for the rest of the run. Works like `CosmeticThumbnails`:
## `texture_for` hands out the texture at once and fills it in when its turn comes
## (`ThumbnailRenderer`: cached on disk per build, rendered a few frames apart). Headless: nothing
## renders, the textures stay blank.

const SIZE: int = 128
## The items are built facing forward (-z), the way the bean holds them out to the others, so the
## preview turns them round to face the camera (Patrick: "monkey ist verkehr rum"), a little to the
## side so they read as 3D. `TILT` sets single items upright (degrees, x/y/z, on top of the turn):
## bat.glb has its barrel at -y, so it stood on its head (Patrick: "wrong way"); it now leans
## barrel up across the square.
const YAW: float = 180.0 - 28.0
const TILT: Dictionary = {&"baseball_bat": Vector3(0, 0, 145)}
## Models that stand on their head as built (the round results' turning cards flip them upright).
const UPSIDE_DOWN: Array[StringName] = [&"baseball_bat"]
## Dev: extra turn for every item (tools/dev/item_thumbs_shot.gd --turn).
static var extra_turn: float = 0.0

const KIND: String = "items"

var _stand: Node3D
var _model: Node3D


func _ready() -> void:
	name = "ItemThumbnails"
	kind = KIND
	image_size = Vector2i(SIZE, SIZE)
	if setup_viewport() == null:
		return
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
static func texture_for(id: StringName, urgent: bool = false) -> ImageTexture:
	return request(KIND, String(id), Vector2i(SIZE, SIZE), urgent)


## The y turn of `id`'s preview, degrees (also the item bar's live model turns from there).
static func preview_yaw(id: StringName) -> float:
	return YAW + extra_turn


## The whole preview rotation of `id`, degrees (turn plus `TILT`).
static func preview_rotation(id: StringName) -> Vector3:
	return Vector3(0.0, preview_yaw(id), 0.0) + (TILT.get(id, Vector3.ZERO) as Vector3)


## Whether every requested picture is done.
static func idle() -> bool:
	return queue_empty(KIND)


func _stage(key: String) -> void:
	if _model != null:
		_model.queue_free()
	_model = ItemModels.make(StringName(key), 1.0)
	_model.rotation_degrees = preview_rotation(StringName(key))
	_stand.add_child(_model)
