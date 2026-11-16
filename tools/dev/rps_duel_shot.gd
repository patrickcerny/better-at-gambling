extends Control
## Dev: look-dev for the Rock Paper Scissors duel screen (`RpsDuelPanel`).
## scripts/screenshot.sh res://tools/dev/rps_duel_shot.tscn <name> 40 [--picked N] [--result win|lose|tie] [--pad]


func _ready() -> void:
	var args: Cmdline = Cmdline.parse(OS.get_cmdline_user_args())
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.3, 0.12, 0.1)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	InputGlyphs.set_gamepad(args.has_flag("pad"))
	var panel := RpsDuelPanel.new()
	add_child(panel)
	await get_tree().process_frame
	panel.show_duel({"duel": 3, "a": 1, "b": 2, "stake": 230, "left": 9.0, "picked": false}, "Stefafo")
	panel.show_duel({"duel": 3, "a": 1, "b": 2, "stake": 230, "left": float(args.get_int("left", 6)) - 0.4, "picked": false}, "Stefafo")
	var p: int = args.get_int("picked", -1)
	if p >= 0:
		panel.choose(p)
	match args.get_string("result", ""):
		"win":
			panel.show_result("paper", "rock", 1, 230, false, "Stefafo")
		"lose":
			panel.show_result("scissors", "rock", -1, 230, false, "Stefafo")
		"tie":
			panel.show_result("rock", "rock", 0, 0, true, "Stefafo")
