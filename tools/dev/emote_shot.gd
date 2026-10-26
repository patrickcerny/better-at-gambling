extends Node3D
## Dev: an emote frozen part-way through, for look-dev screenshots. Run with
## tools/screenshot.gd --scene res://tools/dev/emote_shot.tscn --frames 100000 --
## --emote six_seven --at 0.6 --shot out.png [--skins bean,king,wizard,regular] [--view row|camera]
## row: the bean and the listed skins side by side, facing the camera, all at `--at` seconds into
## the emote. camera: a local player in a seat-less room emoting, seen through their own camera
## (the emote view). strip: one bean per moment of the emote (`--times 0.1,0.4,...`, default eight
## steps across `Emotes.length`), so a whole emote reads left to right; `--angle` (degrees) turns
## the beans (0 = facing the camera, 90 = side on). The scene saves the shot after `--wait` seconds
## (default 1.2) and quits.

var _beans: Array[AvatarVisuals] = []
var _emote: StringName = &"six_seven"
var _at: float = 0.6
var _shot: String = ""
var _wait: float = 1.2
var _t: float = 0.0
var _player: PlayerAvatar
## Per bean: the moment of the emote it is frozen at (row: all `_at`).
var _times: Array[float] = []


func _ready() -> void:
	var c: Cmdline = Cmdline.parse(OS.get_cmdline_user_args())
	_emote = StringName(c.get_string("emote", "six_seven"))
	_at = c.get_float("at", 0.6)
	_shot = c.get_string("shot", "")
	_wait = c.get_float("wait", 1.2)
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
	if c.get_string("view", "row") == "camera":
		_player = PlayerAvatar.new()
		_player.is_local = true
		add_child(_player)
		_player.teleport(Vector3.ZERO, 0.0)
		_player.cam.activate()
		return
	var skins: PackedStringArray = c.get_string("skins", "bean,king,wizard,regular").split(",")
	if c.get_string("view", "row") == "strip":
		skins = PackedStringArray()
		var spec: String = c.get_string("times", "")
		if spec == "":
			for k: int in 8:
				_times.append(snappedf((k + 0.5) * Emotes.length(_emote) / 8.0, 0.01))
		else:
			for part: String in spec.split(","):
				_times.append(float(part))
		for k: int in _times.size():
			skins.append("bean")
	else:
		for k: int in skins.size():
			_times.append(_at)
	var angle: float = deg_to_rad(c.get_float("angle", 0.0))
	var gap: float = 1.8 if skins.size() <= 5 else 1.3
	for i: int in skins.size():
		var v := AvatarVisuals.new()
		v.position = Vector3((i - (skins.size() - 1) * 0.5) * gap, 0, 0)
		v.rotation.y = PI + angle
		add_child(v)
		v.set_color(Palette.player_color(i % 8))
		v.set_skin(StringName(skins[i]))
		_beans.append(v)
		var tag := Label3D.new()
		tag.text = ("%.2fs" % _times[i]) if _times.size() > 5 else "%s · %s @ %.2fs" % [skins[i], _emote, _times[i]]
		tag.font_size = 32
		tag.pixel_size = 0.005
		tag.position = v.position + Vector3(0, 0.02, 0.9)
		tag.rotation.x = -0.6
		tag.modulate = Palette.CREAM
		add_child(tag)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.fov = 50
	cam.position = Vector3(0, 1.6, 6.2) if skins.size() <= 5 else Vector3(0, 1.45, 7.6)
	cam.look_at(Vector3(0, 0.95, 0) if skins.size() <= 5 else Vector3(0, 0.85, 0))


func _process(delta: float) -> void:
	_t += delta
	if _player != null:
		if _t > 0.2 and not _player.visuals.is_emoting():
			_player.play_emote(_emote)
		if _player.visuals.is_emoting():
			_player.visuals.emote_time = minf(_player.visuals.emote_time, _at)
	for i: int in _beans.size():
		var v: AvatarVisuals = _beans[i]
		if v.emote_id != _emote:
			v.emote(_emote)
			v.set_process(false)  # driven here: a slow software-rendered frame must not move the clock
		v.update_motion(Vector3.ZERO, true, delta)  # skins pick their emote clip here
		for k: int in 3:  # frozen: the springs settle into the pose at that moment
			v.emote_time = _times[i]
			v._animate(1.0 / 60.0)
	if _shot != "" and _t >= _wait:
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png(_shot)
		print("emote shot %s" % _shot)
		_shot = ""
		get_tree().quit(0)
