extends Node3D
## Dev: the dev's entrance (`DevEntrance`) in the Lucky Lounge, seen from the casino floor. Run with
## tools/screenshot.gd --scene res://tools/dev/entrance_shot.tscn --frames 100000 -- --shot out.png
## [--at seconds] [--lobby]. The scene saves the shot itself at `--at` seconds and quits.

var _t: float = 0.0
var _at: float = 5.0
var _shot: String = ""
var _show: DevEntrance


func _ready() -> void:
	var c: Cmdline = Cmdline.parse(OS.get_cmdline_user_args())
	_at = c.get_float("at", 5.0)
	_shot = c.get_string("shot", "")
	var map: Node3D = (load("res://maps/lucky_lounge/lucky_lounge.tscn") as PackedScene).instantiate()
	add_child(map)
	var lobby: bool = c.has("lobby")
	var def := MapDefinition.new()
	LuckyLounge.describe_rooms(def)
	var stage: Vector3 = def.entrance_stage_lobby if lobby else def.entrance_stage
	var dev := PlayerAvatar.new()
	dev.player_id = 1
	dev.display_name = "Patrick"
	dev.color = Palette.player_color(3)
	dev.drive = PlayerAvatar.Drive.PUPPET
	add_child(dev)
	dev.teleport(stage)
	var cam := Camera3D.new()
	cam.fov = 75.0
	add_child(cam)
	var eye: Vector3 = stage + (Vector3(1.5, 1.7, 6.5) if lobby else Vector3(2.0, 1.7, -8.0))
	cam.look_at_from_position(eye, stage + Vector3(0, 2.6, 0))
	cam.current = true
	_show = DevEntrance.new()
	add_child(_show)
	_show.play(map, dev, null, null, null, stage, 9.0)


func _process(delta: float) -> void:
	_t += delta
	if _t >= _at and _shot != "":
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png(_shot)
		print("entrance shot %s at %.1f s" % [_shot, _t])
		get_tree().quit()
