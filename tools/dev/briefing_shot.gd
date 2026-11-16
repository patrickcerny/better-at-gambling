extends Node
## Dev: a minigame's rules card (MinigameBriefing) with its preview clip and controls, for a
## render check. `xvfb-run -a tools/godot/godot --path . -s tools/screenshot.gd -- --scene
## res://tools/dev/briefing_shot.tscn --out /tmp/b.png --frames 30 --game bat_heist [--pad]`.

const NAMES: Array[String] = ["Patrick", "Chip", "Lucky", "Dice", "Big Wendy", "Snake Eyes"]


func _ready() -> void:
	var c: Cmdline = Cmdline.parse(OS.get_cmdline_user_args())
	var game := StringName(c.get_string("game", "bat_heist"))
	InputGlyphs.set_gamepad(c.has_flag("pad"))
	var bg := ColorRect.new()
	bg.color = Palette.FELT_GREEN
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var st := ClientMatchState.new()
	var ids: Array = []
	for i: int in NAMES.size():
		st.players[i + 1] = {"id": i + 1, "name": NAMES[i], "color": i}
		ids.append(i + 1)
	var card := MinigameBriefing.new()
	add_child(card)
	card.open({"minigame": game, "players": ids, "briefing": {"left": 24.0, "ready": [2, 4]}}, st, 1)
