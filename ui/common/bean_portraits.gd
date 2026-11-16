class_name BeanPortraits
extends Node
## Little still pictures of a player's bean in its colour and outfit, for lists with many beans
## (the lobby panel's rows, BROWSE LOBBIES' bean line-ups). One offscreen SubViewport renders them
## one per frame and keeps them for the run (same pattern as `CosmeticThumbnails`), so eight
## lobbies × eight beans never mean 64 live 3D views. `texture_for` hands the texture out at once
## and fills it in when its turn comes. Headless: nothing renders, the textures stay blank.
## Any panel that shows portraits adds one `BeanPortraits` node; they share the cache and queue.

const SIZE: Vector2i = Vector2i(160, 200)
## Head and shoulders (lobby rows) or the whole bean with its hat (lobby line-ups).
enum Framing { HEAD, FULL }

## key -> ImageTexture, shared by every panel.
static var _cache: Dictionary = {}
## Keys still waiting for their render, and what each one shows.
static var _queue: Array[String] = []
static var _jobs: Dictionary = {}

var _viewport: SubViewport
var _bean: AvatarVisuals
var _cam: Camera3D
var _busy: String = ""
var _wait: int = 0


## The picture of a bean in colour `bean_color` (palette index) wearing `outfit` (wire list).
static func texture_for(bean_color: int, outfit: Variant, framing: Framing = Framing.HEAD) -> ImageTexture:
	var clean: PackedStringArray = Cosmetics.sanitize_outfit(outfit)
	var key: String = "%d|%d|%s" % [framing, bean_color, ",".join(clean)]
	if _cache.has(key):
		return _cache[key]
	var img := Image.create_empty(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	_jobs[key] = {"color": bean_color, "outfit": clean, "framing": framing}
	_queue.append(key)
	return tex


## Whether every requested picture is done.
static func idle() -> bool:
	return _queue.is_empty()


func _ready() -> void:
	name = "BeanPortraits"
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	_viewport = SubViewport.new()
	_viewport.size = SIZE
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
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


func _process(_delta: float) -> void:
	if _busy != "":
		_wait -= 1
		if _wait > 0:
			return
		var img: Image = _viewport.get_texture().get_image()
		if img != null and not img.is_empty() and _cache.has(_busy):
			img.convert(Image.FORMAT_RGBA8)
			(_cache[_busy] as ImageTexture).update(img)
		_busy = ""
	if _queue.is_empty():
		return
	_busy = _queue.pop_front()
	var job: Dictionary = _jobs.get(_busy, {})
	_jobs.erase(_busy)
	if job.is_empty():
		_busy = ""
		return
	_bean.set_color(Palette.player_color(int(job["color"])))
	_bean.set_outfit(Cosmetics.outfit_dict(job["outfit"]))
	var look := Vector3(0, 1.2, 0)
	var dist: float = 3.1
	if int(job["framing"]) == Framing.FULL:
		look = Vector3(0, 0.95, 0)
		dist = 4.6
	_cam.position = look + Vector3(0.0, 0.18, dist)
	_cam.look_at(look, Vector3.UP)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_wait = 2  # rendered at the end of this frame; read back next frame (plus one for safety)
