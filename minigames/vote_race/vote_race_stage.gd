class_name VoteRaceStage
extends MinigameStage
## Client presentation for Vote Race: vote to slow others down, avoid votes to advance.

var main_container: VBoxContainer
var title_label: Label
var track_container: VBoxContainer
var lanes: Dictionary = {}  # player -> lane panel
var lane_positions: Dictionary = {}  # player -> visual position
var voting_panel: VBoxContainer
var voting_buttons: Dictionary = {}  # player -> vote button
var tally_label: Label
var status_label: Label
var my_vote: int = -1
var can_vote: bool = false
var players_list: Array[int] = []
var current_positions: Dictionary[int, int] = {}  # player -> position


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	main_container = VBoxContainer.new()
	main_container.anchors_rect = Rect2(0, 0, 1, 1)
	main_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui.add_child(main_container)

	# Title
	title_label = Label.new()
	title_label.text = "Vote Race - Vote to Slow Others"
	title_label.add_theme_font_size_override("font_size", 32)
	main_container.add_child(title_label)

	# Race track
	track_container = VBoxContainer.new()
	track_container.custom_minimum_size = Vector2(0, 250)
	main_container.add_child(track_container)

	# Voting section
	voting_panel = VBoxContainer.new()
	voting_panel.custom_minimum_size = Vector2(0, 150)
	main_container.add_child(voting_panel)

	var voting_title: Label = Label.new()
	voting_title.text = "Cast Your Vote:"
	voting_title.add_theme_font_size_override("font_size", 24)
	voting_panel.add_child(voting_title)

	# Tally
	tally_label = Label.new()
	tally_label.text = "Vote Tally:"
	tally_label.add_theme_font_size_override("font_size", 18)
	main_container.add_child(tally_label)

	# Status
	status_label = Label.new()
	status_label.text = ""
	status_label.add_theme_font_size_override("font_size", 16)
	main_container.add_child(status_label)


func _build_lanes() -> void:
	# Clear existing lanes
	for child in track_container.get_children():
		child.queue_free()
	lanes.clear()
	lane_positions.clear()

	# Create lanes for each player
	for player: int in players_list:
		var lane_container: VBoxContainer = VBoxContainer.new()

		# Lane label with player info
		var lane_label: Label = Label.new()
		lane_label.text = "Player %d:" % player
		lane_label.add_theme_font_size_override("font_size", 14)
		lane_container.add_child(lane_label)

		# Progress bar showing position
		var progress: ProgressBar = ProgressBar.new()
		progress.min_value = 0
		progress.max_value = 5
		progress.value = current_positions.get(player, 0)
		progress.custom_minimum_size = Vector2(300, 30)
		lane_container.add_child(progress)

		track_container.add_child(lane_container)
		lanes[player] = lane_container


func _build_voting_buttons() -> void:
	# Clear existing voting buttons
	for child in voting_panel.get_children():
		if child != voting_panel.get_child(0):
			child.queue_free()
	voting_buttons.clear()

	var button_container: HBoxContainer = HBoxContainer.new()
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER
	voting_panel.add_child(button_container)

	for player: int in players_list:
		if player == local_id:
			continue

		var btn: Button = Button.new()
		btn.text = "Vote P%d" % player
		btn.custom_minimum_size = Vector2(80, 40)
		btn.pressed.connect(_on_vote_pressed.bindv([player]))
		button_container.add_child(btn)
		voting_buttons[player] = btn


func apply_state(st: Dictionary) -> void:
	var new_positions: Dictionary = st.get("positions", {})
	current_positions = new_positions.duplicate()

	my_vote = int(st.get("voted_for", -1))
	can_vote = bool(st.get("can_vote", false))

	if players_list.is_empty() and new_positions.size() > 0:
		players_list = new_positions.keys()
		players_list.sort()
		_build_lanes()
		_build_voting_buttons()

	_update_lanes()
	_update_vote_buttons()


func on_event(ev: Dictionary) -> void:
	match ev["type"]:
		&"vote_race_started":
			var start_players: Array = ev.get("players", [])
			players_list = start_players as Array[int]
			players_list.sort()
			current_positions.clear()
			for p: int in players_list:
				current_positions[p] = 0
			_build_lanes()
			_build_voting_buttons()
			status_label.text = "Round starting..."
			my_vote = -1

		&"vote_race_votes_ready":
			status_label.text = "Votes submitted..."

		&"vote_race_voting_phase":
			var vote_counts: Dictionary = ev.get("vote_counts", {})
			_show_vote_tally(vote_counts)

		&"vote_race_progress":
			var player: int = int(ev.get("player", -1))
			var new_pos: int = int(ev.get("new_position", 0))
			current_positions[player] = new_pos
			if player == local_id:
				status_label.text = "You advanced to position %d!" % new_pos
			_update_lanes()

		&"vote_race_winner":
			var winner: int = int(ev.get("winner", -1))
			if winner == local_id:
				status_label.text = "YOU WIN!"
			else:
				status_label.text = "Player %d wins!" % winner
			can_vote = false
			_update_vote_buttons()


func _on_vote_pressed(target: int) -> void:
	if not can_vote or my_vote >= 0:
		return

	my_vote = target
	status_label.text = "You voted for Player %d" % target
	Net.send_intent(Intents.make(&"vote_race_vote", {"target": target}))
	_update_vote_buttons()


func _update_lanes() -> void:
	for player: int in players_list:
		if player in lanes:
			var lane: Node = lanes[player]
			# Find the progress bar (second child)
			if lane.get_child_count() > 1:
				var progress: Node = lane.get_child(1)
				if progress is ProgressBar:
					(progress as ProgressBar).value = current_positions.get(player, 0)


func _update_vote_buttons() -> void:
	for player: int in voting_buttons:
		var btn: Button = voting_buttons[player]
		if my_vote == player:
			btn.modulate = Color(0.5, 1.0, 0.5)  # Green for selected
		elif my_vote >= 0:
			btn.modulate = Color(0.5, 0.5, 0.5)  # Gray for disabled
			btn.disabled = true
		else:
			btn.modulate = Color.WHITE
			btn.disabled = not can_vote


func _show_vote_tally(vote_counts: Dictionary) -> void:
	var tally_text: String = "Vote Tally:\n"
	for player: int in players_list:
		var votes_received: int = int(vote_counts.get(player, 0))
		tally_text += "Player %d: %d votes\n" % [player, votes_received]
	tally_label.text = tally_text


func on_private(priv: Dictionary) -> void:
	var can_vote_priv: bool = bool(priv.get("can_vote", false))
	var voted_for: int = int(priv.get("voted_for", -1))

	can_vote = can_vote_priv
	if voted_for >= 0:
		my_vote = voted_for

	_update_vote_buttons()
