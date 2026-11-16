extends SceneTree
## Look-dev renders of model files (ours and, while they still existed, the reference originals):
## each model framed by its bounds in a warm neutral studio, from a three-quarter and a side angle.
##   xvfb-run godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility \
##     --audio-driver Dummy -s tools/models/render_models.gd -- --out DIR --models a.glb,b.fbx [--size 640x640]

const ANGLES: Array = [["a", -35.0, 18.0], ["b", 70.0, 8.0], ["c", 180.0, 14.0]]

var _out: String
var _paths: PackedStringArray
var _vp: SubViewport
var _cam: Camera3D
var _holder: Node3D
var _i: int = 0
var _angle: int = 0
var _wait: int = 0
var _bounds: AABB


func _initialize() -> void:
	var c: Cmdline = Cmdline.parse(OS.get_cmdline_user_args())
	_out = c.get_string("out", "user://model_renders")
	_paths = c.get_string("models", "").split(",", false)
	var size: PackedStringArray = c.get_string("size", "640x640").split("x")
	DirAccess.make_dir_recursive_absolute(_out)
	_vp = SubViewport.new()
	_vp.size = Vector2i(int(size[0]), int(size[1]))
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child.call_deferred(_vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.12, 0.11)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1.0, 0.92, 0.82)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	_vp.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, -30, 0)
	key.light_color = Color(1.0, 0.9, 0.75)
	key.light_energy = 1.3
	key.shadow_enabled = true
	_vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15, 140, 0)
	fill.light_color = Color(0.75, 0.8, 1.0)
	fill.light_energy = 0.45
	_vp.add_child(fill)
	_cam = Camera3D.new()
	_cam.fov = 30.0
	_vp.add_child(_cam)
	_holder = Node3D.new()
	_vp.add_child(_holder)
	_load_next()


func _load_next() -> void:
	for ch: Node in _holder.get_children():
		ch.free()
	if _i >= _paths.size():
		quit()
		return
	var ps: PackedScene = load(_paths[_i]) as PackedScene
	if ps == null:
		push_error("cannot load %s" % _paths[_i])
		_i += 1
		_load_next()
		return
	var m: Node3D = ps.instantiate()
	for n: Node in m.find_children("*", "", true, false):
		if n is Camera3D or n is Light3D:
			n.free()
	_holder.add_child(m)
	_bounds = _measure(m)
	_angle = 0
	_wait = 0
	_place_camera()


func _place_camera() -> void:
	var a: Array = ANGLES[_angle]
	var centre: Vector3 = _bounds.get_center()
	var r: float = _bounds.size.length() * 0.5
	var dist: float = r / sin(deg_to_rad(_cam.fov * 0.5)) * 1.05
	var dir := Vector3(sin(deg_to_rad(a[1])), 0, cos(deg_to_rad(a[1]))).rotated(Vector3.UP, 0.0)
	dir = (dir * cos(deg_to_rad(a[2])) + Vector3.UP * sin(deg_to_rad(a[2]))).normalized()
	_cam.near = maxf(dist * 0.01, 0.001)
	_cam.far = dist * 10.0
	_cam.look_at_from_position(centre + dir * dist, centre)


func _process(_delta: float) -> bool:
	if _i >= _paths.size():
		return true
	_wait += 1
	if _wait < 6:
		return false
	var img: Image = _vp.get_texture().get_image()
	var base: String = _paths[_i].get_file().get_basename()
	img.save_png("%s/%s_%s.png" % [_out, base, ANGLES[_angle][0]])
	if _i == 0 and _angle == 0:
		print("bounds %s %s" % [base, _bounds])
	_angle += 1
	_wait = 0
	if _angle >= ANGLES.size():
		print("%s size %s" % [base, _bounds.size])
		_i += 1
		_load_next()
	else:
		_place_camera()
	return false


static func _measure(model: Node3D) -> AABB:
	var acc: Array = []
	_collect(model, Transform3D.IDENTITY, acc)
	if acc.is_empty():
		return AABB(Vector3.ZERO, Vector3.ONE)
	var out: AABB = acc[0]
	for a: AABB in acc:
		out = out.merge(a)
	return out


static func _collect(n: Node, xf: Transform3D, acc: Array) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null and String(n.name) != "Plane":
		acc.append(xf * (n as MeshInstance3D).get_aabb())
	for c: Node in n.get_children():
		_collect(c, xf * (c as Node3D).transform if c is Node3D else xf, acc)
