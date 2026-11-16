extends Control
## Dev: look-dev for the Daily Spin (`DailySpinPanel`) on the main menu.
## Run with scripts/screenshot.sh res://tools/dev/daily_spin_shot.tscn <name> 120 [args]
##   --spin       spin (locally) once the panel is open
##   --land N     put the wheel at rest on slice N, won (confetti, glow, prize card)
##   --wait       show the cooldown (spun a moment ago)


func _ready() -> void:
	var args: Cmdline = Cmdline.parse(OS.get_cmdline_user_args())
	ProfileManager.persist = false
	ProfileManager.profile.daily_last = int(Time.get_unix_time_from_system()) - 60 if args.has_flag("wait") else 0
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.16, 0.11, 0.09)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var panel := DailySpinPanel.new()
	add_child(panel)
	panel.open()
	var land: int = args.get_int("land", -1)
	if land >= 0:
		panel.wheel.angle = DailyWheelView.angle_for(land, 0.1) - 0.4
		panel.wheel.speed = 4.0
		panel._prize = {"index": land, "coins": 0, "piece": &"hat_party", "gold": 0}
		panel.wheel.target = land
		panel.wheel._begin_stop(0.4)
		panel.wheel._dur = 0.3
	elif args.has_flag("spin"):
		panel.spin()
