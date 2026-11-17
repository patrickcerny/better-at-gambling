class_name BeanPortraits
extends ThumbnailRenderer
## Little still pictures of a player's bean in its colour and outfit, for lists with many beans
## (the lobby panel's rows, BROWSE LOBBIES' bean line-ups). One offscreen SubViewport renders them
## a few frames apart and keeps them (on disk too, `ThumbnailRenderer`) (same pattern as `CosmeticThumbnails`), so eight
## lobbies × eight beans never mean 64 live 3D views. `texture_for` hands the texture out at once
## and fills it in when its turn comes. Headless: nothing renders, the textures stay blank.
## Any panel that shows portraits adds one `BeanPortraits` node; they share the cache and queue.

const SIZE: Vector2i = Vector2i(160, 200)
## Head and shoulders (lobby rows) or the whole bean with its hat (lobby line-ups).
enum Framing { HEAD, FULL }

const KIND: String = "beans"

var _bean: AvatarVisuals
var _cam: Camera3D


## The picture of a bean in colour `bean_color` (palette index) wearing `outfit` (wire list).
static func texture_for(bean_color: int, outfit: Variant, framing: Framing = Framing.HEAD) -> ImageTexture:
	var clean: PackedStringArray = Cosmetics.sanitize_outfit(outfit)
	# The key says everything the picture shows (`_stage` reads the job back out of it).
	var key: String = "%d|%d|%s" % [framing, bean_color, ",".join(clean)]
	return request(KIND, key, SIZE)


## Whether every requested picture is done.
static func idle() -> bool:
	return queue_empty(KIND)


func _ready() -> void:
	name = "BeanPortraits"
	kind = KIND
	image_size = SIZE
	if setup_viewport() == null:
		return
	var root := Node3D.new()
	_viewport.add_child(root)
	_bean = AvatarVisuals.new()
	root.add_child(_bean)
	_bean.no_blink = true
	_bean.rotation.y = PI + 0.35  # face the camera, a little turned
	_cam = Camera3D.new()
	_cam.current = true
	_cam.fov = 30.0
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


func _stage(key: String) -> void:
	var parts: PackedStringArray = key.split("|")
	var framing: int = int(parts[0])
	_bean.set_color(Palette.player_color(int(parts[1])))
	_bean.set_outfit(Cosmetics.outfit_dict(Cosmetics.sanitize_outfit(parts[2].split(","))))
	var look := Vector3(0, 1.2, 0)
	var dist: float = 3.1
	if framing == Framing.FULL:
		look = Vector3(0, 0.95, 0)
		dist = 4.6
	_cam.position = look + Vector3(0.0, 0.18, dist)
	_cam.look_at(look, Vector3.UP)
