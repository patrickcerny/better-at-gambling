extends Node3D
## Dev: the M7 bean animations side by side for screenshots. Run with
## tools/screenshot.gd --scene res://tools/dev/bean_shot.tscn --frames 100000 -- [--view faces|chaos]
## --shot out.png [--at seconds]. The scene saves the shot itself at `--at` seconds and quits.
## faces: idle with the leader crown, win, big win, loss, slip. chaos: a guard carrying a bean
## out, a knocked-out ragdoll with birdies, a fountain splash, a skinned bean slipping.

## Seconds into each reaction the poses are frozen at (faces view).
const PHASES: Dictionary = {&"win": 0.28, &"big_win": 0.75, &"loss": 0.9, &"slip": 0.33}

var _beans: Dictionary = {}
var _frame: int = 0
var _view: String = "faces"
var _ko: PlayerAvatar
var _guard: Guard
var _carried: PlayerAvatar
var _t: float = 0.0
var _at: float = 1.3
var _shot: String = ""
var _splashed: bool = false


func _ready() -> void:
	var c: Cmdline = Cmdline.parse(OS.get_cmdline_user_args())
	_view = c.get_string("view", "faces")
	_at = c.get_float("at", 1.3)
	_shot = c.get_string("shot", "")
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Palette.WARM_CHARCOAL
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(1.0, 0.88, 0.75)
	env.environment.ambient_light_energy = 0.6
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_color = Color(1.0, 0.9, 0.75)
	sun.shadow_enabled = true
	add_child(sun)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	add_child(floor_body)
	var fcs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	fcs.shape = box
	fcs.position.y = -0.5
	floor_body.add_child(fcs)
	var fm := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	fm.mesh = plane
	fm.material_override = GreyboxKit.material(Palette.CASINO_RED.darkened(0.3))
	floor_body.add_child(fm)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	if _view == "chaos":
		_chaos(cam)
	else:
		_faces(cam)


func _faces(cam: Camera3D) -> void:
	var kinds: Array[StringName] = [&"", &"win", &"big_win", &"loss", &"slip"]
	for i: int in kinds.size():
		var v := AvatarVisuals.new()
		v.position = Vector3((i - 2) * 1.7, 0, 0)
		v.rotation.y = PI
		add_child(v)
		v.set_color(Palette.player_color(i))
		_beans[kinds[i]] = v
		var tag := Label3D.new()
		tag.text = String(kinds[i]) if kinds[i] != &"" else "leader"
		tag.font_size = 40
		tag.pixel_size = 0.005
		tag.position = Vector3((i - 2) * 1.7, 0.02, 0.8)
		tag.rotation.x = -0.6
		tag.modulate = Palette.CREAM
		add_child(tag)
	var crown: Node3D = LeaderCrown.build_model()
	crown.position = Vector3(-2 * 1.7, LeaderCrown.HEIGHT, 0)
	add_child(crown)
	cam.position = Vector3(0, 1.9, 6.2)
	cam.look_at(Vector3(0, 1.1, 0))
	cam.fov = 55


func _chaos(cam: Camera3D) -> void:
	_guard = Guard.new()
	add_child(_guard)
	_guard.global_position = Vector3(-2.2, 0, 0)
	_carried = _avatar(1, Vector3(-2.0, 0, 0.5), &"bean")
	_ko = _avatar(2, Vector3(1.4, 0, 0.5), &"bean")
	var skinned: PlayerAvatar = _avatar(3, Vector3(4.0, 0, -0.5), &"king")
	_beans[&"skin"] = skinned.visuals
	var basin := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.6
	cyl.bottom_radius = 1.6
	cyl.height = 0.05
	basin.mesh = cyl
	basin.material_override = GreyboxKit.material(Color("#4FA3C7"))
	basin.position = Vector3(-0.2, FountainSplash.WATER_Y - 0.03, -3.5)
	add_child(basin)
	cam.position = Vector3(1.0, 2.4, 6.0)
	cam.look_at(Vector3(0.0, 1.3, -0.5))
	cam.fov = 60


func _avatar(pid: int, pos: Vector3, skin: StringName) -> PlayerAvatar:
	var a := PlayerAvatar.new()
	a.player_id = pid
	a.color = Palette.player_color(pid)
	a.skin = skin
	add_child(a)
	a.teleport(pos, PI)
	return a


func _process(delta: float) -> void:
	_frame += 1
	_t += delta
	if _shot != "" and _t >= _at:
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png(_shot)
		print("bean shot %s" % _shot)
		_shot = ""
		get_tree().quit(0)
	if _view == "chaos":
		if _frame == 3:
			_guard.yaw = -PI * 0.5
			_guard.carry(_carried, Vector3(-30, 0, 0))
			_ko.start_ragdoll(Vector3(0, 3.0, 2.0), 99.0)
			_ko.visuals.set_knocked_out(true)
		if _t >= _at - 0.3 and not _splashed:
			_splashed = true
			FountainSplash.spawn(self, Vector3(-0.2, FountainSplash.WATER_Y, -3.5), true)
		if _frame >= 3:
			var sv: AvatarVisuals = _beans[&"skin"]
			if sv.reaction != &"slip":
				sv.react(&"slip")
			sv.reaction_time = 0.3
		return
	if _frame < 5:
		return
	for k: StringName in PHASES:
		var v: AvatarVisuals = _beans[k]
		if v.reaction != k:
			v.react(k)
		v.reaction_time = PHASES[k]
