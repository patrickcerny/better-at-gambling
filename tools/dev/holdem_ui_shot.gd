extends Control
## Dev: the Casino Hold'em overlay for screenshots. `--phase bet` (default) shows the ante chips and
## the AA BONUS with its rule line and paytable (`--bonus N` picks size N), `--phase flop` the hand
## after the flop with the bonus result (`--miss` for a lost bonus); `--pad` shows gamepad key names.
## Run with scripts/screenshot.sh res://tools/dev/holdem_ui_shot.tscn holdem_ui 30 [--phase flop]


func _ready() -> void:
	theme = load("res://ui/theme/main_theme.tres") as Theme
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var c: Cmdline = Cmdline.parse(OS.get_cmdline_user_args())
	var bg := ColorRect.new()
	bg.color = Palette.FELT_GREEN.darkened(0.4)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	InputGlyphs.set_gamepad(c.has_flag("pad"))
	var st := ClientMatchState.new()
	st.players[1] = {"name": "Ada", "color": 0}
	st.players[2] = {"name": "Bert", "color": 1}
	st.balances[1] = 2400
	var pub: Dictionary = {"game": &"holdem", "state": HoldemLogic.State.BETTING, "timer": 6.0, "seats": [1, 2, -1, -1], "hands": {}, "board": [], "dealer": [], "dealer_down": 0}
	st.stations[&"holdem_1"] = pub
	var ui := HoldemUi.new()
	add_child(ui)
	ui.open(&"holdem_1", 1, st)
	if c.get_string("phase", "bet") == "flop":
		var miss: bool = c.has_flag("miss")
		pub = pub.duplicate()
		pub["state"] = HoldemLogic.State.DECIDING
		pub["board"] = [Card.make(1, 3), Card.make(9, 1), Card.make(4, 2)]
		pub["dealer_down"] = 2
		pub["hands"] = {1: {"ante": 50, "bonus": 30, "hole": [Card.make(13), Card.make(13, 1)] if miss else [Card.make(1), Card.make(9)], "decision": &"",
			"hand": "Pair of Kings" if miss else "Two Pair, Aces and Nines", "clock": 11.0, "bonus_returned": 0 if miss else 240}}
		ui.update_state(pub, {})
	else:
		var sizes: Array[int] = ui.bonus_sizes
		ui.set_bonus(sizes[clampi(c.get_int("bonus", 0), 0, sizes.size() - 1)])
		ui.update_state(pub, {})
