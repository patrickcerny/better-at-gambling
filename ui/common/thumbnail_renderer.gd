class_name ThumbnailRenderer
extends Node
## Shared engine of the offscreen picture makers (`CosmeticThumbnails`, `ItemThumbnails`,
## `BeanPortraits`): `request` hands out a texture at once and fills it in later. Built so the
## pictures never make the game stutter (Patrick 2026-11-17: "lags very hard on launch and on join"):
## - Pictures are kept on disk per build (`user://thumbnails/<build>/<kind>/`), so only the first
##   launch of a new version renders them; later launches load the files a few per frame.
## - Only one node per kind does the work (several panels each add their own renderer), and all
##   kinds together render at most one picture every `GAP_FRAMES` frames (urgent ones every frame).
## - Pictures nobody is waiting for start `START_DELAY_MS` after launch and pause while the loading
##   screen is up, so they never compete with building the menu or the match.
## - The finished picture is read back from the GPU without stalling it (`texture_get_data_async`),
##   with the old blocking `get_image` only where there is no RenderingDevice (Compatibility).
## Subclasses set `kind`, `image_size`, build their stage in `_ready` (calling `setup_viewport`) and
## dress it for a key in `_stage`. Headless: nothing renders, the textures stay blank.

## Bump when the pictures' look changes without a version bump (dev builds).
const STYLE: int = 1
const ROOT_DIR: String = "user://thumbnails"
## Nothing that isn't urgent renders before this many ms after launch.
const START_DELAY_MS: int = 2500
## Frames between two background renders (all kinds together).
const GAP_FRAMES: int = 3
## Time per frame spent loading cached pictures from disk.
const DISK_BUDGET_USEC: int = 2000

## kind -> {key -> ImageTexture}, shared by every panel that ever opens.
static var _caches: Dictionary = {}
## kind -> Array[String] of keys still waiting for their picture.
static var _queues: Dictionary = {}
## kind -> {key: true} for the queued keys someone is looking at right now.
static var _urgent: Dictionary = {}
## kind -> {key: true} for keys known not to be on disk yet.
static var _missing: Dictionary = {}
## kind -> instance id of the node doing that kind's work.
static var _owners: Dictionary = {}
static var _last_render_frame: int = -1000
## False once an async readback came back in a format we can't use (then `get_image` is used).
static var _async_ok: bool = true
static var _pruned: bool = false
static var _logged: bool = false
## WorkerThreadPool tasks still saving pictures (waited for once done, and all before quitting).
static var _saving: Array[int] = []

## Set by the subclass before `_ready` finishes.
var kind: String = ""
var image_size: Vector2i = Vector2i(128, 128)
var _viewport: SubViewport
var _busy: String = ""
var _wait: int = 0
var _reading: bool = false


## The picture for `key` of `kind` (blank until it is loaded or rendered). `urgent` ones (shown
## right now) jump the queue and skip the start delay.
static func request(of_kind: String, key: String, size: Vector2i, urgent: bool = false) -> ImageTexture:
	var cache: Dictionary = _caches.get_or_add(of_kind, {})
	var queue: Array = _queues.get_or_add(of_kind, [])
	var hot: Dictionary = _urgent.get_or_add(of_kind, {})
	if cache.has(key):
		if urgent and key in queue:
			queue.erase(key)
			queue.push_front(key)
			hot[key] = true
		return cache[key]
	var tex := ImageTexture.create_from_image(Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8))
	cache[key] = tex
	if urgent:
		queue.push_front(key)
		hot[key] = true
	else:
		queue.append(key)
	return tex


## Whether every requested picture of `of_kind` is done.
static func queue_empty(of_kind: String) -> bool:
	return (_queues.get(of_kind, []) as Array).is_empty()


## Folder of this build's cached pictures of `of_kind`.
static func cache_dir(of_kind: String) -> String:
	return "%s/%s-%d/%s" % [ROOT_DIR, Protocol.BUILD_ID, STYLE, of_kind]


static func _file(of_kind: String, key: String) -> String:
	return "%s/%s.png" % [cache_dir(of_kind), key.md5_text()]


## Removes the pictures of other builds (once per run, they are never used again).
static func _prune_old() -> void:
	if _pruned:
		return
	_pruned = true
	var keep: String = "%s-%d" % [Protocol.BUILD_ID, STYLE]
	var root: DirAccess = DirAccess.open(ROOT_DIR)
	if root == null:
		return
	for build: String in root.get_directories():
		if build != keep:
			_remove_tree("%s/%s" % [ROOT_DIR, build])


static func _remove_tree(path: String) -> void:
	var d: DirAccess = DirAccess.open(path)
	if d == null:
		return
	for sub: String in d.get_directories():
		_remove_tree("%s/%s" % [path, sub])
	for f: String in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute(path)


## Makes the offscreen viewport (call from the subclass's `_ready`); null when headless.
func setup_viewport() -> SubViewport:
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return null
	_viewport = SubViewport.new()
	_viewport.size = image_size
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	return _viewport


## Dresses the stage for `key` (subclass).
func _stage(_key: String) -> void:
	pass


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		_reap_saves(true)


func _exit_tree() -> void:
	if _busy != "" and not _reading:  # half done: the next renderer of this kind takes it again
		(_queues.get_or_add(kind, []) as Array).push_front(_busy)
		_busy = ""
	if int(_owners.get(kind, 0)) == get_instance_id():
		_owners.erase(kind)


## True when this node does its kind's work (the first one that asks, until it leaves).
func _is_worker() -> bool:
	var owner_id: int = int(_owners.get(kind, 0))
	if owner_id == get_instance_id():
		return true
	var other: Object = instance_from_id(owner_id) if owner_id != 0 else null
	if other != null and other is Node and (other as Node).is_inside_tree():
		return false
	_owners[kind] = get_instance_id()
	return true


func _process(_delta: float) -> void:
	if _viewport == null or _reading or not _is_worker():
		return
	if not _saving.is_empty():
		_reap_saves()
	if _busy != "":
		_wait -= 1
		if _wait <= 0:
			_read_back()
		return
	var queue: Array = _queues.get_or_add(kind, [])
	if queue.is_empty():
		return
	_load_from_disk(queue)
	if queue.is_empty():
		return
	var hot: Dictionary = _urgent.get_or_add(kind, {})
	var key: String = queue[0]
	var urgent: bool = hot.has(key)
	var frame: int = Engine.get_process_frames()
	if frame - _last_render_frame < (1 if urgent else GAP_FRAMES):
		return
	if not urgent and (Time.get_ticks_msec() < START_DELAY_MS or Loading.is_showing()):
		return
	_last_render_frame = frame
	queue.pop_front()
	hot.erase(key)
	_busy = key
	_stage(key)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_wait = 2  # rendered at the end of this frame; read it back after that


## Fills queued pictures that are already on disk, within the frame's budget.
func _load_from_disk(queue: Array) -> void:
	_prune_old()
	var missing: Dictionary = _missing.get_or_add(kind, {})
	var start: int = Time.get_ticks_usec()
	var i: int = 0
	while i < queue.size() and Time.get_ticks_usec() - start < DISK_BUDGET_USEC:
		var key: String = queue[i]
		if missing.has(key):
			i += 1
			continue
		var path: String = _file(kind, key)
		var img: Image = Image.load_from_file(path) if FileAccess.file_exists(path) else null
		if img == null or img.get_size() != image_size:
			missing[key] = true
			i += 1
			continue
		queue.remove_at(i)
		(_urgent.get_or_add(kind, {}) as Dictionary).erase(key)
		_apply(kind, key, img, false)


## Reads the rendered picture back: asynchronously where the RenderingDevice allows it.
func _read_back() -> void:
	var key: String = _busy
	var tex: ViewportTexture = _viewport.get_texture()
	var rd: RenderingDevice = RenderingServer.get_rendering_device()
	if _async_ok and rd != null:
		var rid: RID = RenderingServer.texture_get_rd_texture(tex.get_rid())
		if rid.is_valid():
			_reading = true
			var err: Error = rd.texture_get_data_async(rid, 0, _data_callback(kind, key, image_size, get_instance_id()))
			if err == OK:
				if not _logged:
					_logged = true
					Log.info(&"thumbs", "pictures read back asynchronously, cached in %s" % cache_dir(kind).get_base_dir())
				return
			_reading = false
			_async_ok = false
	_busy = ""
	_apply(kind, key, tex.get_image(), true)


## The readback's callback: static, so it still lands when the renderer is gone by then.
static func _data_callback(of_kind: String, key: String, size: Vector2i, worker_id: int) -> Callable:
	return func(data: PackedByteArray) -> void:
		var worker: ThumbnailRenderer = instance_from_id(worker_id) as ThumbnailRenderer
		if worker != null:
			worker._reading = false
			worker._busy = ""
		if data.size() != size.x * size.y * 4:
			# Not plain RGBA8: render it again and read it the blocking way.
			_async_ok = false
			(_queues.get_or_add(of_kind, []) as Array).push_front(key)
			return
		_apply(of_kind, key, Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, data), true)


## Puts `img` into the shared texture of `key` (and saves a fresh render to disk off the main thread).
static func _apply(of_kind: String, key: String, img: Image, save: bool) -> void:
	if img == null or img.is_empty():
		return
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var tex: ImageTexture = (_caches.get(of_kind, {}) as Dictionary).get(key, null)
	if tex != null and tex.get_size() == Vector2(img.get_size()):
		tex.update(img)
	if save:
		var dir: String = cache_dir(of_kind)
		var path: String = _file(of_kind, key)
		_saving.append(WorkerThreadPool.add_task(func() -> void:
			DirAccess.make_dir_recursive_absolute(dir)
			img.save_png(path)))


## Collects the finished save tasks (`all`: waits for the running ones too).
static func _reap_saves(all: bool = false) -> void:
	for id: int in _saving.duplicate():
		if all or WorkerThreadPool.is_task_completed(id):
			WorkerThreadPool.wait_for_task_completion(id)
			_saving.erase(id)
