extends Control
## Dev: the blackjack panel mid-split, plus the emote wheel, for screenshots. `--pad` shows the
## gamepad key names. Run with tools/screenshot.gd --scene res://tools/dev/blackjack_ui_shot.tscn.


func _ready() -> void:
	theme = load("res://ui/theme/main_theme.tres") as Theme
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Palette.FELT_GREEN.darkened(0.4)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	InputGlyphs.set_gamepad(Cmdline.parse(OS.get_cmdline_user_args()).has_flag("pad"))
	var ui: BlackjackUi = (load("res://ui/stations/blackjack_ui.tscn") as PackedScene).instantiate()
	add_child(ui)
	ui.open(&"blackjack_1", 1, null)
	ui.update_state({"state": BlackjackLogic.State.ACTING, "timer": 7.2, "seats": [1, -1, -1, -1], "dealer": [Card.make(6, 1)], "dealer_revealed": false,
		"hands": {1: {"stake": 50, "cards": [Card.make(8, 0), Card.make(3, 1)], "done": false, "total": 11, "active": 0,
			"split": {"stake": 50, "cards": [Card.make(8, 2), Card.make(13, 3)], "done": false, "total": 18}}}}, {})
	var wheel := EmoteWheel.new()
	add_child(wheel)
	wheel.open()
	wheel.selected = 1
	wheel.set_process(false)
	wheel._highlight()
