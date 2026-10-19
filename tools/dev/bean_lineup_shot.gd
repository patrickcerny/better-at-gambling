extends Node3D
## Dev: a row of beans in chosen poses for look-dev screenshots. Run with
## tools/screenshot.gd --scene res://tools/dev/bean_lineup_shot.tscn --frames 100000 --
## --poses stand,walk,hit,jump --shot out.png [--at seconds] [--view front|side|close]
## Poses: stand, walk, run, hit, jump, win, big_win, loss, slip, ko, emote:<id> (Emotes.ANIMATED),
## and skin:<skin>:<pose> for a character skin. The scene saves the shot at `--at` seconds and quits.

var _beans: Array[AvatarVisuals] = []
var _poses: PackedStringArray = []
var _t: float = 0.0
var _at: float = 1.0
var _shot: String = ""
var _hit_done: bool = false


func _ready() -> void:
	var c: Cmdline = Cmdline.parse(OS.get_cmdline_user_args())
	_poses = c.get_string("poses", "stand,walk,hit,jump").split(",")
	_at = c.get_float("at", 1.0)
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
	var fm := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	fm.mesh = plane
	fm.material_override = GreyboxKit.material(Palette.FELT_GREEN)
	add_child(fm)
	var n: int = _poses.size()
	var gap: float = 1.6
	for i: int in n:
		var v := AvatarVisuals.new()
		v.position = Vector3((i - (n - 1) * 0.5) * gap, 0, 0)
		v.rotation.y = PI
		var parts: PackedStringArray = _poses[i].split(":")
		if parts[0] == "skin" and parts.size() >= 2:
			v.skin_id = StringName(parts[1])
		add_child(v)
		v.set_color(Palette.player_color(i))
		_beans.append(v)
		var tag := Label3D.new()
		tag.text = _poses[i]
		tag.font_size = 32
		tag.pixel_size = 0.005
		tag.position = v.position + Vector3(0, 0.02, 0.9)
		tag.rotation.x = -PI * 0.5
		tag.modulate = Palette.CREAM
		add_child(tag)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.fov = 50
	var width: float = n * gap
	match c.get_string("view", "front"):
		"side":
			cam.position = Vector3(width * 0.7 + 2.0, 1.4, 3.0)
			cam.look_at(Vector3(0, 0.8, 0))
		"close":
			cam.position = Vector3(0, 1.15, width * 0.62 + 1.4)
			cam.look_at(Vector3(0, 0.95, 0))
		_:
			cam.position = Vector3(0, 1.5, maxf(width * 0.95, 3.4) + 0.6)
			cam.look_at(Vector3(0, 0.85, 0))


func _pose_of(i: int) -> String:
	var parts: PackedStringArray = _poses[i].split(":")
	if parts[0] == "skin":
		return ":".join(parts.slice(2)) if parts.size() > 2 else "stand"
	return _poses[i]


func _physics_process(delta: float) -> void:
	_t += delta
	for i: int in _beans.size():
		var v: AvatarVisuals = _beans[i]
		var pose: String = _pose_of(i)
		var vel: Vector3 = Vector3.ZERO
		var floor_contact: bool = true
		match pose:
			"walk":
				vel = Vector3(0, 0, 3.2)
			"run":
				vel = Vector3(0, 0, 6.0)
			"jump":
				floor_contact = _t < 0.5
				vel = Vector3(0, 6.0 - maxf(_t - 0.5, 0.0) * 18.0, 0) if _t >= 0.5 else Vector3.ZERO
				if _t >= 0.5:
					v.position.y = maxf(0.0, 6.0 * (_t - 0.5) - 9.0 * pow(_t - 0.5, 2.0))
		v.update_motion(vel, floor_contact, delta)
		if _t > 0.2 and _t - delta <= 0.2:
			if pose.begins_with("emote:"):
				v.emote(StringName(pose.substr(6)))
			elif pose in ["win", "big_win", "loss", "slip"]:
				v.react(StringName(pose))
			elif pose == "ko":
				v.set_knocked_out(true)
		if pose == "hit" and not _hit_done and _t >= _at - 0.12:
			v.hit(Vector3(0.4, 0, -1.0), 1.5)
	if _t >= _at - 0.12:
		_hit_done = true


func _process(_delta: float) -> void:
	if _shot != "" and _t >= _at:
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png(_shot)
		print("bean shot %s" % _shot)
		_shot = ""
		get_tree().quit(0)
