class_name LonelyNumberStage
extends MinigameStage
## Client presentation for Lonely Number: pick 1-20, highest unclaimed wins each round.

var picks_panel: Control
var buttons: Array[Button] = []


func _build(_start: Dictionary) -> void:
	picks_panel = Control.new()
	picks_panel.custom_minimum_size = Vector2(400, 300)
	ui.add_child(picks_panel)
	_build_ui()


func _build_ui() -> void:
	var container := VBoxContainer.new()
	container.anchors_rect = Rect2(0, 0, 1, 1)
	picks_panel.add_child(container)
	container.add_child(_make_label("Pick a Number (1-20)"))
	var grid := GridContainer.new()
	grid.columns = 5
	for num: int in range(1, 21):
		var btn := Button.new()
		btn.text = str(num)
		btn.custom_minimum_size = Vector2(60, 40)
		btn.pressed.connect(func() -> void: _on_pick(num))
		buttons.append(btn)
		grid.add_child(btn)
	container.add_child(grid)


func _on_pick(num: int) -> void:
	Net.send_intent(Intents.make(&"submit_answer", {"number": num}))
	for btn: Button in buttons:
		btn.disabled = true


func _make_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	return lbl


func apply_state(state: Dictionary) -> void:
	var can_pick: bool = state.get("can_pick", false)
	for btn: Button in buttons:
		btn.disabled = not can_pick
	picks_panel.visible = not state.get("finished", false)
