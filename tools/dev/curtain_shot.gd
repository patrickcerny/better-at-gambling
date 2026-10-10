extends Node
## Dev: the real match scene with the minigame curtain frozen at `--amount` (0 = closed showing
## `--title`, 0.5 = gathered at the tiebacks, 1 = open). Saves `--shot` at `--at` seconds and quits.
## Run with tools/screenshot.gd --scene res://tools/dev/curtain_shot.tscn --frames 100000 --pixel 1
## -- --shot out.png [--amount 0] [--title "Plinko"] [--kicker MINIGAME] [--at 2.5]

var _scene: MatchScene
var _t: float = 0.0
var _at: float = 2.5
var _amount: float = 0.0
var _shot: String = ""
var _title: String = "Plinko"
var _kicker: String = "MINIGAME"


func _ready() -> void:
	var c: Cmdline = Cmdline.parse(OS.get_cmdline_user_args())
	_at = c.get_float("at", 2.5)
	_amount = c.get_float("amount", 0.0)
	_shot = c.get_string("shot", "/tmp/curtain.png")
	_title = c.get_string("title", "Plinko")
	_kicker = c.get_string("kicker", "MINIGAME")
	MatchScene.test_dummies = 2
	_scene = (load("res://match/match_scene.tscn") as PackedScene).instantiate()
	add_child(_scene)


func _process(delta: float) -> void:
	_t += delta
	if _scene.curtain_title == null:
		return
	_scene.curtain_title.text = _title.to_upper()
	_scene.curtain_kicker.text = _kicker
	_scene.curtain_kicker.visible = _kicker != ""
	_scene.curtain_plaque.reset_size()
	_scene._center_curtain_plaque()
	_scene._set_curtain(_amount)
	if _shot != "" and _t >= _at:
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png(_shot)
		print("curtain shot %s" % _shot)
		_shot = ""
		get_tree().quit(0)
