class_name BustOrBankStage
extends MinigameStage
## Client presentation for Bust or Bank: one shared shoe flips a card every few seconds; everyone
## still drawing adds it to their total. STAND (button, Space/Enter, gamepad A) banks your total.
## Everything shown comes from server events / snapshots; the only input is the stand intent.

const PAD_STAND: JoyButton = JOY_BUTTON_A

var root: Control
var round_label: Label
var banner: Label
var shoe_card: Label
var deal_bar: ProgressBar
var my_cards: Label
var my_total_label: Label
var status_label: Label
var stand_button: Button
var points_label: Label
var board: VBoxContainer
## player → their row on the board (built once, updated in place).
var board_rows: Dictionary = {}

## Everyone who started (display order).
var players: Array[int] = []
## Still in the game (not thrown out).
var in_game: Array[int] = []
## player → {cards: Array, total: int, busted: bool, stood: bool} for the current round.
var hands: Dictionary = {}
## player → players outlasted (absolute, straight from the server).
var points: Dictionary = {}
var current_round: int = 0
var replay: bool = false
## The round that just ended was an everyone-busted replay: busts there don't mean "out".
var end_was_replay: bool = false
var deal_interval: float = BustOrBankLogic.DEAL_INTERVAL
var deal_left: float = 0.0
var deal_span: float = 1.0
var dealing: bool = false
var over: bool = false
## Sent a stand and waiting for the server to confirm it.
var stand_sent: bool = false


func _build(start: Dictionary) -> void:
	for p: Variant in start.get("players", []):
		players.append(int(p))
	in_game = players.duplicate()
	for p: int in players:
		points[p] = 0
		hands[p] = _empty_hand()
	camera = Camera3D.new()
	camera.far = 50.0  # the casino floor is far away: keep it out of shot
	add_child(camera)
	_build_ui()
	_refresh()


func _build_ui() -> void:
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)

	var bg := ColorRect.new()
	bg.color = Palette.FELT_GREEN.darkened(0.35)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	root.add_child(margin)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 48)
	margin.add_child(columns)

	# Left: the table.
	var table := VBoxContainer.new()
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table.add_theme_constant_override("separation", 14)
	columns.add_child(table)

	var title := _label("BUST OR BANK", 44, Palette.WARM_GOLD)
	table.add_child(title)
	round_label = _label("", 26, Palette.CREAM)
	table.add_child(round_label)
	banner = _label("", 30, Palette.CREAM)
	banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	table.add_child(banner)

	table.add_child(_label("Shared shoe", 20, Palette.CREAM.darkened(0.25)))
	shoe_card = _label("--", 72, Palette.CREAM)
	table.add_child(shoe_card)
	deal_bar = ProgressBar.new()
	deal_bar.custom_minimum_size = Vector2(360, 14)
	deal_bar.show_percentage = false
	deal_bar.max_value = 1.0
	deal_bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	table.add_child(deal_bar)

	table.add_child(_label("Your hand", 20, Palette.CREAM.darkened(0.25)))
	my_cards = _label("", 30, Palette.CREAM)
	table.add_child(my_cards)
	my_total_label = _label("", 56, Palette.CREAM)
	table.add_child(my_total_label)
	status_label = _label("", 30, Palette.WARM_GOLD)
	table.add_child(status_label)

	stand_button = Button.new()
	stand_button.text = "STAND  (Space / A)"
	stand_button.custom_minimum_size = Vector2(320, 72)
	stand_button.add_theme_font_size_override("font_size", 30)
	stand_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	stand_button.focus_mode = Control.FOCUS_NONE  # Space is ours, not the focused button's
	stand_button.pressed.connect(_on_stand)
	table.add_child(stand_button)

	points_label = _label("", 22, Palette.CREAM)
	table.add_child(points_label)

	# Right: everyone at the table.
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(520, 0)
	side.add_theme_constant_override("separation", 8)
	columns.add_child(side)
	side.add_child(_label("Players", 26, Palette.WARM_GOLD))
	board = VBoxContainer.new()
	board.add_theme_constant_override("separation", 6)
	side.add_child(board)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _empty_hand() -> Dictionary:
	return {"cards": [], "total": 0, "busted": false, "stood": false}


# --- Input -------------------------------------------------------------------------------------

func _unhandled_input(ev: InputEvent) -> void:
	var press: bool = false
	if ev is InputEventKey and ev.is_pressed() and not ev.is_echo():
		press = (ev as InputEventKey).keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]
	elif ev is InputEventJoypadButton and ev.is_pressed():
		press = (ev as InputEventJoypadButton).button_index == PAD_STAND
	if press and can_stand():
		_on_stand()
		get_viewport().set_input_as_handled()


func can_stand() -> bool:
	if over or not dealing or stand_sent or local_id not in in_game:
		return false
	var h: Dictionary = hands.get(local_id, {})
	return not h.is_empty() and not bool(h["busted"]) and not bool(h["stood"]) and not (h["cards"] as Array).is_empty()


func _on_stand() -> void:
	if not can_stand():
		return
	stand_sent = true
	_refresh()
	var r: Dictionary = Net.send_intent(Intents.make(&"bust_or_bank_action", {"action": "stand"}))
	if not bool(r.get("ok", true)):
		stand_sent = false
		_refresh()


func _process(delta: float) -> void:
	if dealing and deal_left > 0.0:
		deal_left = maxf(deal_left - delta, 0.0)
	if deal_bar != null:
		deal_bar.value = 1.0 - deal_left / maxf(deal_span, 0.01) if (dealing or deal_left > 0.0) else 0.0


# --- Server data -------------------------------------------------------------------------------

func apply_state(st: Dictionary) -> void:
	current_round = int(st.get("round", 0))
	deal_interval = float(st.get("deal_interval", deal_interval))
	if st.has("players"):
		players.clear()
		for p: Variant in st["players"]:
			players.append(int(p))
	in_game.clear()
	for p: Variant in st.get("in_round", players):
		in_game.append(int(p))
	var hs: Dictionary = st.get("hands", {})
	for p: Variant in hs:
		var h: Dictionary = hs[p]
		hands[int(p)] = {"cards": (h.get("cards", []) as Array).duplicate(), "total": int(h.get("total", 0)),
			"busted": bool(h.get("busted", false)), "stood": bool(h.get("stood", false))}
	_set_points(st.get("points", {}))
	var s: int = int(st.get("state", BustOrBankLogic.State.INTRO))
	dealing = s == BustOrBankLogic.State.DEALING
	deal_left = float(st.get("timer", 0.0))
	deal_span = deal_interval if dealing else maxf(deal_left, 0.01)
	var last: int = int(st.get("last_card", -1))
	shoe_card.text = Card.label(last) if last >= 0 else "--"
	if st.has("ranking"):
		_show_finish(st["ranking"])
	else:
		banner.text = "Cards are coming..." if not dealing else ""
	_refresh()


func on_event(ev: Dictionary) -> void:
	match ev["type"]:
		&"bust_or_bank_started":
			deal_interval = float(ev.get("deal_interval", deal_interval))
			if ev.has("players"):
				players.clear()
				for p: Variant in ev["players"]:
					players.append(int(p))
				in_game = players.duplicate()

		&"bust_or_bank_round_started":
			current_round = int(ev.get("round", 0))
			replay = bool(ev.get("replay", false))
			end_was_replay = false
			in_game.clear()
			for p: Variant in ev.get("players", []):
				in_game.append(int(p))
				hands[int(p)] = _empty_hand()
			dealing = false
			stand_sent = false
			deal_left = float(ev.get("deal_in", 0.0))
			deal_span = maxf(deal_left, 0.01)
			shoe_card.text = "--"
			banner.text = "Everyone busted. Replay!" if replay else "New round: fresh count"

		&"bust_or_bank_card":
			dealing = true
			var card: int = int(ev.get("card", -1))
			shoe_card.text = Card.label(card) if card >= 0 else "--"
			var totals: Dictionary = ev.get("totals", {})
			for p: Variant in ev.get("receivers", []):
				var pid: int = int(p)
				if not hands.has(pid):
					hands[pid] = _empty_hand()
				(hands[pid]["cards"] as Array).append(card)
				hands[pid]["total"] = int(totals.get(pid, totals.get(p, hands[pid]["total"])))
			deal_left = float(ev.get("next_in", deal_interval))
			deal_span = maxf(deal_left, 0.01)
			banner.text = ""

		&"bust_or_bank_player_bust":
			var pid: int = int(ev.get("player", -1))
			if hands.has(pid):
				hands[pid]["busted"] = true
				hands[pid]["total"] = int(ev.get("total", hands[pid]["total"]))
			if pid == local_id:
				banner.text = "BUST! You're out."

		&"bust_or_bank_player_stood":
			var pid: int = int(ev.get("player", -1))
			if hands.has(pid):
				hands[pid]["stood"] = true
				hands[pid]["total"] = int(ev.get("total", hands[pid]["total"]))
			if pid == local_id:
				stand_sent = false
				if bool(ev.get("auto", false)):
					banner.text = "21! Banked automatically."

		&"bust_or_bank_round_end":
			dealing = false
			stand_sent = false
			deal_left = 0.0
			_set_points(ev.get("points", {}))
			end_was_replay = bool(ev.get("replay", false))
			in_game.clear()
			for p: Variant in ev.get("remaining", []):
				in_game.append(int(p))
			banner.text = _round_summary(ev)

		&"bust_or_bank_finished":
			_set_points(ev.get("points", {}))
			_show_finish(ev.get("ranking", []))
	_refresh()


func on_private(_priv: Dictionary) -> void:
	pass  # can_stand is derived from public events


func _set_points(src: Dictionary) -> void:
	for p: Variant in src:
		points[int(p)] = int(src[p])  # absolute values from the server: set, never add


func _round_summary(ev: Dictionary) -> String:
	if bool(ev.get("replay", false)):
		return "Everyone busted! Nobody is out. Replay the round."
	var busted_out: Array = ev.get("busted", [])
	var worst: Array = ev.get("worst", [])
	if busted_out.is_empty() and worst.is_empty():
		return "All tied. Nobody is out."
	var parts: Array[String] = []
	if not worst.is_empty():
		parts.append("Worst hand: %s" % _names(worst))
	if not busted_out.is_empty():
		parts.append("Busted: %s" % _names(busted_out))
	return "Out: " + ". ".join(parts)


func _names(ids: Array) -> String:
	var out: Array[String] = []
	for p: Variant in ids:
		out.append(_name(int(p)))
	return ", ".join(out)


func _name(pid: int) -> String:
	if pid == local_id:
		return "You"
	return state.player_name(pid) if state != null else "Player %d" % pid


func _show_finish(ranking: Array) -> void:
	over = true
	dealing = false
	var winners: Array = []
	for row: Variant in ranking:
		if int((row as Dictionary).get("rank", 0)) == 1:
			winners.append(int(row["player"]))
	if winners.size() == 1:
		banner.text = "%s %s the last one standing!" % [_name(winners[0]), "are" if winners[0] == local_id else "is"]
	else:
		banner.text = "Survivors share the win: %s" % _names(winners)


# --- Drawing -----------------------------------------------------------------------------------

func _refresh() -> void:
	round_label.text = "Round %d%s  ·  %d left" % [current_round + 1, "  (replay)" if replay else "", in_game.size()]
	var mine: Dictionary = hands.get(local_id, _empty_hand())
	var cards: Array = mine["cards"]
	var labels: Array[String] = []
	for c: Variant in cards:
		labels.append(Card.label(int(c)))
	my_cards.text = "  ".join(labels) if not labels.is_empty() else "-"
	my_total_label.text = str(int(mine["total"]))
	var bust: bool = bool(mine["busted"])
	my_total_label.add_theme_color_override("font_color", Palette.LOSS_RED if bust else Palette.CREAM)

	if over:
		status_label.text = "Game over"
	elif local_id not in in_game and local_id in players:
		status_label.text = "OUT, watching"
	elif bust and end_was_replay:
		status_label.text = "BUST! Everyone did: replay"
	elif bust:
		status_label.text = "BUST!"
	elif bool(mine["stood"]):
		status_label.text = "Banked %d" % int(mine["total"])
	elif stand_sent:
		status_label.text = "Standing..."
	elif dealing:
		status_label.text = "Stand or ride the next card?"
	else:
		status_label.text = "Get ready"
	stand_button.disabled = not can_stand()
	points_label.text = "Points (players outlasted): %d" % int(points.get(local_id, 0))
	_update_board()


func _update_board() -> void:
	for p: Variant in board_rows:
		(board_rows[p] as Label).visible = int(p) in players  # gone after a disconnect
	for p: int in players:
		var row: Label = board_rows.get(p)
		if row == null:
			row = Label.new()
			row.add_theme_font_size_override("font_size", 22)
			row.set_meta("player", p)
			board.add_child(row)
			board_rows[p] = row
		var h: Dictionary = hands.get(p, _empty_hand())
		var status: String
		var color: Color = Palette.CREAM
		if bool(h["busted"]) and p in in_game and end_was_replay:
			status = "BUST (replay)"
			color = Palette.LOSS_RED
		elif bool(h["busted"]):
			status = "BUST, OUT"
			color = Palette.LOSS_RED
		elif p not in in_game:
			status = "OUT"
			color = Palette.CREAM.darkened(0.45)
		elif bool(h["stood"]):
			status = "STAND"
			color = Palette.WARM_GOLD
		else:
			status = "drawing" if dealing else ""
		row.text = "%s   %d   %s   (%d pts)" % [_name(p), int(h["total"]), status, int(points.get(p, 0))]
		row.add_theme_color_override("font_color", color)
		row.set_meta("status", status)
