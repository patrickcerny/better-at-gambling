extends Node3D
## Dev: look-dev for the item models (`ItemModels`, `ItemArt`).
## Run with scripts/screenshot.sh res://tools/dev/item_models_shot.tscn <name> 40 [--view ...]
##   --view models   every item's model on a shelf grid, labelled (default)
##   --view hands    beans holding items, front three-quarter (--items a,b,c,... up to 6,
##                   --page N takes items 6N..6N+5 of the full list; --side for a side view,
##                   --walk to have them walk on the spot, --far for the distance others see)
##   --view first    the first-person view of one item (--items x)
##   --t S           pose every idle animation S seconds in (default 0.7)

var _beans: Array[AvatarVisuals] = []
var _walk: bool = false


func _ready() -> void:
	process_priority = 10
	var args: Cmdline = Cmdline.parse(OS.get_cmdline_user_args())
	var view: String = args.get_string("view", "models")
	_walk = args.has("walk")
	_stage()
	var all: Array[StringName] = []
	for id: StringName in Registry.items.keys():
		all.append(id)
	all.sort()
	var picked: Array[StringName] = []
	if args.has("items"):
		for s: String in args.get_string("items").split(","):
			picked.append(StringName(s))
	elif args.has("page"):
		var p: int = args.get_int("page", 0)
		picked.assign(all.slice(p * 6, p * 6 + 6))
	else:
		picked = all
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.fov = 40
	match view:
		"hands":
			_hands(picked, cam, args.has("side"), args.has("far"))
		"close":
			_close(picked, cam, args.get_float("turn", 155.0))
		"first":
			_first(picked[0], cam)
		_:
			_models(picked, cam)
	var t: float = args.get_float("t", 0.7)
	for idle: Node in find_children("Idle", "ItemIdle", true, false):
		(idle as ItemIdle).set_process(false)
		(idle as ItemIdle).pose(t)


func _stage() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Palette.WARM_CHARCOAL
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(1.0, 0.88, 0.75)
	env.environment.ambient_light_energy = 0.7
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 150, 0)
	sun.light_energy = 1.1
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, -30, 0)
	fill.light_energy = 0.4
	add_child(fill)
	var fm := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	fm.mesh = plane
	fm.material_override = GreyboxKit.material(Palette.CASINO_RED.darkened(0.45))
	add_child(fm)


func _models(items: Array[StringName], cam: Camera3D) -> void:
	var cols: int = mini(7, items.size()) if items.size() <= 7 else (5 if items.size() <= 10 else 7)
	var gap: float = 0.62
	for i: int in items.size():
		var x: float = (i % cols - (cols - 1) * 0.5) * gap
		var y: float = 0.55 + (items.size() / cols - i / cols) * gap * 0.82
		var m: Node3D = ItemModels.make(items[i], 0.36)
		m.position = Vector3(x, y, 0)
		m.rotation_degrees.y = 160.0  # face the camera (models face -z)
		add_child(m)
		var l := Label3D.new()
		l.text = String(items[i])
		l.font_size = 22
		l.pixel_size = 0.0018
		l.modulate = Palette.CREAM
		l.position = Vector3(x, y - 0.25, 0)
		add_child(l)
	var rows: int = ceili(items.size() / float(cols))
	cam.position = Vector3(0, 0.55 + rows * gap * 0.41, 0.6 + maxf(cols * 0.55, rows * 0.9))
	cam.look_at(Vector3(0, 0.55 + rows * gap * 0.41 - 0.15, 0))


## Up to 6 items big, in a 3 × 2 grid, turned `turn` degrees (180 = straight on).
func _close(items: Array[StringName], cam: Camera3D, turn: float) -> void:
	for i: int in mini(items.size(), 6):
		var m: Node3D = ItemModels.make(items[i], 0.8)
		m.position = Vector3((i % 3 - 1) * 1.15, 1.6 - (i / 3) * 1.0, 0)
		m.rotation_degrees = Vector3(12, turn, 0)
		add_child(m)
		var l := Label3D.new()
		l.text = String(items[i])
		l.font_size = 28
		l.pixel_size = 0.0025
		l.modulate = Palette.CREAM
		l.position = m.position + Vector3(0, -0.47, 0.2)
		add_child(l)
	cam.position = Vector3(0, 1.1, 4.4)
	cam.look_at(Vector3(0, 1.1, 0))


func _hands(items: Array[StringName], cam: Camera3D, side: bool, far: bool) -> void:
	for i: int in items.size():
		var v := AvatarVisuals.new()
		add_child(v)
		v.set_color(Palette.player_color(i % 8))
		v.position = Vector3((i - (items.size() - 1) * 0.5) * 1.15, 0, 0)
		v.rotation.y = PI  # face the camera at +z
		v.hold_right_arm(ItemModels.arm_pose(items[i]))
		var held: Node3D = ItemModels.make_held(items[i])
		ItemModels.attach_to_hand(v, held)
		var l := Label3D.new()
		l.text = String(items[i])
		l.font_size = 26
		l.pixel_size = 0.003
		l.modulate = Palette.CREAM
		l.position = v.position + Vector3(0, 2.0, 0)
		add_child(l)
		_beans.append(v)
	var w: float = items.size() * 1.15
	if side:
		cam.position = Vector3(w * 0.5 + 2.2, 1.3, 1.6)
		cam.look_at(Vector3(0, 0.9, 0))
	else:
		cam.position = Vector3(-0.6, 1.4, (w * 0.9 + 1.2) * (2.2 if far else 1.0))
		cam.look_at(Vector3(0, 0.9, 0))


func _first(item: StringName, cam: Camera3D) -> void:
	cam.fov = 75
	cam.position = Vector3(0, AvatarVisuals.EYE_Y + 0.35, 0)
	cam.rotation.x = -0.1
	var m: Node3D = ItemModels.make_view(item)
	cam.add_child(m)
	var ahead := AvatarVisuals.new()
	add_child(ahead)
	ahead.set_color(Palette.player_color(3))
	ahead.position = Vector3(0.6, 0, -3.5)


func _physics_process(delta: float) -> void:
	for v: AvatarVisuals in _beans:
		v.update_motion(Vector3(0, 0, 2.5) if _walk else Vector3.ZERO, true, delta)
