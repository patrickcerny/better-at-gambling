class_name SplitOrStealStage
extends MinigameStage
## Client presentation for Split or Steal Tournament: choose SPLIT or STEAL in each pairing.

var main_container: VBoxContainer
var match_label: Label
var opponent_label: Label
var status_label: Label
var choice_buttons: Dictionary[StringName, Button] = {}
var results_container: VBoxContainer
var scores_label: Label


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
	title.text = "SPLIT OR STEAL TOURNAMENT"
	title.add_theme_font_size_override(&"font_size", 28)
	main_container.add_child(title)

	# Match info
	match_label = Label.new()
	match_label.text = "Match: --"
	main_container.add_child(match_label)

	opponent_label = Label.new()
	opponent_label.text = "Waiting for opponent..."
	main_container.add_child(opponent_label)

	# Status
	status_label = Label.new()
	status_label.text = "Make your choice"
	main_container.add_child(status_label)

	# Choice buttons
	var button_container := HBoxContainer.new()
	main_container.add_child(button_container)

	for choice: StringName in [&"SPLIT", &"STEAL"]:
		var btn := Button.new()
		btn.text = choice
		btn.custom_minimum_size = Vector2(120, 60)
		btn.pressed.connect(func() -> void: _on_choice(choice))
		button_container.add_child(btn)
		choice_buttons[choice] = btn

	# Results area
	results_container = VBoxContainer.new()
	main_container.add_child(results_container)

	# Scores
	scores_label = Label.new()
	scores_label.text = "Current Score: 0"
	main_container.add_child(scores_label)


func _on_choice(choice: StringName) -> void:
	Net.send_intent(Intents.make(&"submit_answer", {"choice": choice}))
	for btn: Button in choice_buttons.values():
		btn.disabled = true
	status_label.text = "Waiting for opponent..."


func apply_state(state: Dictionary) -> void:
	var can_choose: bool = state.get("can_choose", false)
	var in_match: bool = state.get("in_current_match", false)
	var current_score: int = state.get("current_score", 0)

	scores_label.text = "Current Score: %d" % current_score

	if can_choose:
		for btn: Button in choice_buttons.values():
			btn.disabled = false
	else:
		for btn: Button in choice_buttons.values():
			btn.disabled = true


func on_event(ev: Dictionary) -> void:
	match ev.get("type", &""):
		&"split_or_steal_started":
			status_label.text = "Tournament started!"

		&"split_or_steal_pairing":
			var match_idx: int = ev.get("match_index", 0)
			var player_a: int = ev.get("player_a", 0)
			var player_b: int = ev.get("player_b", 0)

			var total_matches: int = state.match_state.get("total_matches", 0)
			match_label.text = "Match %d of %d" % [match_idx + 1, total_matches]

			var opponent_id: int = 0
			if local_id == player_a:
				opponent_id = player_b
			else:
				opponent_id = player_a

			opponent_label.text = "vs Player %d" % opponent_id
			status_label.text = "Make your choice..."

		&"split_or_steal_choice_ready":
			var player: int = ev.get("player", 0)
			if player == local_id:
				status_label.text = "Waiting for opponent..."

		&"split_or_steal_payoff":
			var player_a: int = ev.get("player_a", 0)
			var player_b: int = ev.get("player_b", 0)
			var choice_a: StringName = StringName(ev.get("choice_a", ""))
			var choice_b: StringName = StringName(ev.get("choice_b", ""))
			var payoff_a: int = ev.get("payoff_a", 0)
			var payoff_b: int = ev.get("payoff_b", 0)

			var my_payoff: int = 0
			var opponent_choice: StringName = &""
			var opponent_id: int = 0

			if local_id == player_a:
				my_payoff = payoff_a
				opponent_choice = choice_b
				opponent_id = player_b
			else:
				my_payoff = payoff_b
				opponent_choice = choice_a
				opponent_id = player_a

			_add_result_text("Player %d chose %s, you earned %d points" % [opponent_id, opponent_choice, my_payoff])

		&"split_or_steal_finished":
			status_label.text = "Tournament complete!"
			var final_scores: Dictionary = ev.get("final_scores", {})
			var my_score: int = final_scores.get(local_id, 0)
			_add_result_text("Final Score: %d" % my_score)


func _add_result_text(text: String) -> void:
	var label := Label.new()
	label.text = text
	results_container.add_child(label)

	# Keep results scrollable by limiting visible results
	while results_container.get_child_count() > 10:
		results_container.get_child(0).queue_free()
