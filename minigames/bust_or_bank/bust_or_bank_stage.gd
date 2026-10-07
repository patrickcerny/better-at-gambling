class_name BustOrBankStage
extends MinigameStage
## Client presentation for Bust or Bank: hit or stand with shared blackjack cards.

var main_container: VBoxContainer
var round_label: Label
var my_hand_label: Label
var cards_display: HBoxContainer
var total_label: Label
var buttons_container: HBoxContainer
var hit_button: Button
var stand_button: Button
var points_label: Label
var players_panel: VBoxContainer
var status_label: Label

var current_round: int = 0
var my_hand: Array[int] = []
var my_total: int = 0
var my_points: int = 0
var can_act: bool = false
var standing: bool = false
var busted: bool = false
var all_hands: Dictionary = {}  # player -> {cards, total, busted, stood}


func _build(start: Dictionary) -> void:
	_build_ui()


func _build_ui() -> void:
	main_container = VBoxContainer.new()
	main_container.anchors_rect = Rect2(0, 0, 1, 1)
	main_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui.add_child(main_container)

	# Round and title
	round_label = Label.new()
	round_label.text = "Round 1/5"
	round_label.add_theme_font_size_override("font_size", 32)
	main_container.add_child(round_label)

	# My hand section
	my_hand_label = Label.new()
	my_hand_label.text = "Your Hand:"
	my_hand_label.add_theme_font_size_override("font_size", 24)
	main_container.add_child(my_hand_label)

	# Cards display
	cards_display = HBoxContainer.new()
	cards_display.custom_minimum_size = Vector2(400, 100)
	cards_display.alignment = BoxContainer.ALIGNMENT_CENTER
	main_container.add_child(cards_display)

	# Total
	total_label = Label.new()
	total_label.text = "Total: 0"
	total_label.add_theme_font_size_override("font_size", 20)
	main_container.add_child(total_label)

	# Status
	status_label = Label.new()
	status_label.text = ""
	status_label.add_theme_font_size_override("font_size", 18)
	main_container.add_child(status_label)

	# Action buttons
	buttons_container = HBoxContainer.new()
	buttons_container.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons_container.custom_minimum_size = Vector2(0, 60)
	main_container.add_child(buttons_container)

	hit_button = Button.new()
	hit_button.text = "HIT"
	hit_button.custom_minimum_size = Vector2(100, 40)
	hit_button.pressed.connect(_on_hit)
	buttons_container.add_child(hit_button)

	stand_button = Button.new()
	stand_button.text = "STAND"
	stand_button.custom_minimum_size = Vector2(100, 40)
	stand_button.pressed.connect(_on_stand)
	buttons_container.add_child(stand_button)

	# Points display
	points_label = Label.new()
	points_label.text = "Points: 0"
	points_label.add_theme_font_size_override("font_size", 18)
	main_container.add_child(points_label)

	# Players section
	players_panel = VBoxContainer.new()
	players_panel.custom_minimum_size = Vector2(0, 200)
	main_container.add_child(players_panel)


func _on_hit() -> void:
	if not can_act:
		return
	hit_button.disabled = true
	stand_button.disabled = true
	Net.send_intent(Intents.make(&"bust_or_bank_action", {"action": "hit"}))


func _on_stand() -> void:
	if not can_act:
		return
	standing = true
	hit_button.disabled = true
	stand_button.disabled = true
	Net.send_intent(Intents.make(&"bust_or_bank_action", {"action": "stand"}))


func apply_state(st: Dictionary) -> void:
	current_round = int(st.get("round", 0))
	round_label.text = "Round %d/5" % [current_round + 1]

	var hands: Dictionary = st.get("hands", {})
	if hands.has(local_id):
		var my_hand_data: Dictionary = hands[local_id]
		my_hand = my_hand_data.get("cards", []).duplicate()
		my_total = int(my_hand_data.get("total", 0))
		busted = bool(my_hand_data.get("busted", false))
		standing = bool(my_hand_data.get("stood", false))
		_update_my_hand_display()

	all_hands = hands.duplicate(true)
	_update_players_display()

	var points: Dictionary = st.get("points", {})
	if points.has(local_id):
		my_points = int(points[local_id])
		points_label.text = "Points: %d" % my_points

	can_act = true
	if busted:
		can_act = false
		status_label.text = "BUST!"
		hit_button.disabled = true
		stand_button.disabled = true
	elif standing:
		can_act = false
		status_label.text = "Standing"
		hit_button.disabled = true
		stand_button.disabled = true
	else:
		can_act = true
		status_label.text = ""
		hit_button.disabled = false
		stand_button.disabled = false


func on_event(ev: Dictionary) -> void:
	match ev["type"]:
		&"bust_or_bank_started":
			current_round = int(ev.get("round", 0))
			round_label.text = "Round %d/5" % [current_round + 1]
			my_hand.clear()
			standing = false
			busted = false
			_update_my_hand_display()
			status_label.text = ""

		&"bust_or_bank_card_dealt":
			var player: int = int(ev.get("player", -1))
			if player == local_id:
				my_hand = ev.get("hand", []).duplicate()
				my_total = int(ev.get("total", 0))
				_update_my_hand_display()

		&"bust_or_bank_player_bust":
			var player: int = int(ev.get("player", -1))
			if player == local_id:
				busted = true
				status_label.text = "BUST!"
				hit_button.disabled = true
				stand_button.disabled = true
			if player in all_hands:
				all_hands[player]["busted"] = true
			_update_players_display()

		&"bust_or_bank_player_stood":
			var player: int = int(ev.get("player", -1))
			if player == local_id:
				standing = true
				hit_button.disabled = true
				stand_button.disabled = true
			if player in all_hands:
				all_hands[player]["stood"] = true
			_update_players_display()

		&"bust_or_bank_round_end":
			var points: Dictionary = ev.get("points", {})
			if points.has(local_id):
				my_points += int(points[local_id])
				points_label.text = "Points: %d" % my_points


func _update_my_hand_display() -> void:
	# Clear existing cards
	for child in cards_display.get_children():
		child.queue_free()

	# Display each card
	for card: int in my_hand:
		var card_label: Label = Label.new()
		card_label.text = Card.label(card)
		card_label.add_theme_font_size_override("font_size", 20)
		cards_display.add_child(card_label)

	# Update total
	if my_hand.is_empty():
		total_label.text = "Total: 0"
	else:
		my_total = HandEval.total(my_hand as Array[int])
		if HandEval.is_bust(my_hand as Array[int]):
			total_label.text = "Total: %d (BUST)" % my_total
		else:
			total_label.text = "Total: %d" % my_total


func _update_players_display() -> void:
	# Clear existing
	for child in players_panel.get_children():
		child.queue_free()

	for player: int in all_hands:
		var player_info: Dictionary = all_hands[player]
		var hand_info: Label = Label.new()

		var status_str: String = ""
		if bool(player_info.get("busted", false)):
			status_str = " - BUST"
		elif bool(player_info.get("stood", false)):
			status_str = " - Standing"

		var player_label: String = "Player %d: Total %d%s" % [
			player,
			player_info.get("total", 0),
			status_str
		]
		hand_info.text = player_label
		players_panel.add_child(hand_info)


func on_private(priv: Dictionary) -> void:
	# Not needed for bust_or_bank currently
	pass
