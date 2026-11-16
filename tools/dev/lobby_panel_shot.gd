extends Control
## Dev: the lobby player list (LobbyPanel) with a few players, for look-dev of the player cards.
## Run with scripts/screenshot.sh res://tools/dev/lobby_panel_shot.tscn lobby 60 [--players N].


func _ready() -> void:
	var n: int = Cmdline.parse(OS.get_cmdline_user_args()).get_int("players", 4)
	var bg := ColorRect.new()
	bg.color = Color("#0E0C0B")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var state := ClientMatchState.new()
	state.leader = 1
	var names: Array = ["Patrick", "Ekvimsa", "Lucky Lu", "Big Stack", "Mo", "Zed", "Ana", "Kai"]
	for pid: int in range(1, n + 1):
		state.players[pid] = {"name": names[pid - 1], "color": pid, "bean_color": pid, "ready": pid % 3 == 0, "connected": true}
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := LobbyPanel.new()
	layer.add_child(panel)
	panel.bind(state, 1)
	panel.open()
