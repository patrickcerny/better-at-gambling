class_name RouletteRoyaleStage
extends MinigameStage
## Client presentation for Roulette Royale: pick red, black, or green; watch hearts.

var main_container: VBoxContainer
var player_list: VBoxContainer
var result_label: Label
var spin_label: Label
var choice_buttons: Dictionary[StringName, Button] = {}
var player_hearts: Dictionary[int, Label] = {}


func _build(start: Dictionary) -> void:
	camera = Camera3D.new()
	camera.position = Vector3(0, 3, 5)
	camera.look_at(Vector3(0, 2, 0), Vector3.UP)
	add_child(camera)

	# Build UI
	main_container = VBoxContainer.new()
	main_container.custom_minimum_size = Vector2(800, 600)
	ui.add_child(main_container)

	# Title
	var title := Label.new()
	title.text = "ROULETTE ROYALE"
	title.add_theme_font_size_override(&"font_size", 32)
	main_container.add_child(title)

	# Player status
	player_list = VBoxContainer.new()
	main_container.add_child(player_list)

	# Result display
	result_label = Label.new()
	result_label.text = "Waiting for bets..."
	main_container.add_child(result_label)

	# Spin number display
	spin_label = Label.new()
	spin_label.text = ""
	spin_label.add_theme_font_size_override(&"font_size", 24)
	main_container.add_child(spin_label)

	# Choice buttons
	var button_container := HBoxContainer.new()
	main_container.add_child(button_container)

	for choice: StringName in [&"red", &"black", &"green"]:
		var btn := Button.new()
		btn.text = choice.to_upper()
		btn.custom_minimum_size = Vector2(100, 50)
		btn.pressed.connect(func() -> void: _on_choice(choice))
		button_container.add_child(btn)
		choice_buttons[choice] = btn

	# Update player list
	_update_player_list()


func _update_player_list() -> void:
	player_list.queue_free_children()

	var players_data: Array = state.match_state.get("players", [])
	var hearts_data: Dictionary = state.match_state.get("hearts", {})

	for player_id: int in players_data:
		var player_label := Label.new()
		var hearts: int = hearts_data.get(player_id, 0)
		var player_name: String = "Player %d" % player_id
		var hearts_display: String = ""
		for i: int in range(hearts):
			hearts_display += "❤️"
		player_label.text = "%s: %s" % [player_name, hearts_display]
		player_list.add_child(player_label)
		player_hearts[player_id] = player_label


func _on_choice(choice: StringName) -> void:
	Net.send_intent(Intents.make(&"submit_answer", {"choice": choice}))
	for btn: Button in choice_buttons.values():
		btn.disabled = true


func apply_state(state: Dictionary) -> void:
	var can_choose: bool = state.get("can_choose", false)

	if can_choose:
		for btn: Button in choice_buttons.values():
			btn.disabled = false
	else:
		for btn: Button in choice_buttons.values():
			btn.disabled = true


func on_event(ev: Dictionary) -> void:
	match ev.get("type", &""):
		&"roulette_royale_started":
			result_label.text = "Game started! Choose red, black, or green."
			_update_hearts_display(ev.get("hearts", {}))

		&"roulette_royale_round_start":
			result_label.text = "Round %d: Choose your color!" % ev.get("round", 0)

		&"roulette_royale_spin_result":
			var number: int = ev.get("number", 0)
			var color: StringName = StringName(ev.get("color", ""))
			spin_label.text = "Landed on %d (%s)" % [number, color]

			var correct: Array = ev.get("correct_players", [])
			var wrong: Array = ev.get("wrong_players", [])

			if local_id in correct:
				result_label.text = "You got it right!"
			elif local_id in wrong:
				result_label.text = "You lost a heart..."
			else:
				result_label.text = "Round result shown"

		&"roulette_royale_hearts_update":
			_update_hearts_display(ev.get("hearts", {}))

		&"roulette_royale_finished":
			var winner: int = ev.get("winner", -1)
			if winner == local_id:
				result_label.text = "YOU WIN!"
			elif winner >= 0:
				result_label.text = "Player %d wins!" % winner
			else:
				result_label.text = "Game Over"


func _update_hearts_display(hearts_data: Dictionary) -> void:
	for player_id: int in hearts_data.keys():
		var hearts: int = hearts_data[player_id]
		if player_id in player_hearts:
			var hearts_display: String = ""
			for i: int in range(maxf(hearts, 0)):
				hearts_display += "❤️"
			player_hearts[player_id].text = "Player %d: %s" % [player_id, hearts_display]
