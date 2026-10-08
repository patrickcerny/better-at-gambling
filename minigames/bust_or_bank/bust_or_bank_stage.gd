class_name BustOrBankStage
extends MinigameStage
## Client presentation for Bust or Bank: one shared shoe flips a card every few seconds; everyone
## still drawing adds it to their total. The NEXT card is shown face up, so the decision is "do I
## want that card?". STAND (button, Space/Enter, gamepad A) banks your total. Cards are drawn as
## real faces (`CardFace`). Everything shown comes from server events / snapshots; the only input
## is the stand intent. Timings (deal bar) come from the events' `next_in` / `deal_in` / snapshot
## `timer`, never from local constants.

const PAD_STAND: JoyButton = JOY_BUTTON_A
## Card heights (px): the shared next / dealt cards, your hand, the board's small hands.
const BIG_CARD_H: float = 150.0
const HAND_CARD_H: float = 112.0
const BOARD_CARD_H: float = 50.0

var root: Control
var round_label: Label
var banner: Label
## The shared upcoming card, face up for everyone.
var next_face: CardFace
## The card the shoe just dealt (face down before the first card of a round).
var dealt_face: CardFace
var deal_time_label: Label
var deal_bar: ProgressBar
## Your hand: a row of `CardFace`s.
var my_hand_row: HBoxContainer
var my_total_label: Label
var status_label: Label
var stand_button: Button
var points_label: Label
var board: VBoxContainer
## player → {box: VBoxContainer, label: Label, cards: HBoxContainer, total: Label} on the board
## (built once, updated in place).
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
## The shared upcoming card (-1 = unknown, drawn face down) and the one just dealt.
var next_card: int = -1
var last_card: int = -1
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

	# The shoe: the next card (face up, the whole point) and the card just dealt.
	var shoe_row := HBoxContainer.new()
	shoe_row.add_theme_constant_override("separation", 36)
	table.add_child(shoe_row)
	var next_col := VBoxContainer.new()
	next_col.add_theme_constant_override("separation", 6)
	shoe_row.add_child(next_col)
	var next_title := _label("NEXT CARD", 24, Palette.WARM_GOLD)
	next_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	next_col.add_child(next_title)
	next_face = CardFace.make(-1, BIG_CARD_H)
	next_face.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	next_col.add_child(next_face)
	var dealt_col := VBoxContainer.new()
	dealt_col.add_theme_constant_override("separation", 6)
	shoe_row.add_child(dealt_col)
	var dealt_title := _label("JUST DEALT", 20, Palette.CREAM.darkened(0.25))
	dealt_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dealt_col.add_child(dealt_title)
	dealt_face = CardFace.make(-1, BIG_CARD_H * 0.8)
	dealt_face.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	dealt_col.add_child(dealt_face)
	var timer_col := VBoxContainer.new()
	timer_col.add_theme_constant_override("separation", 8)
	timer_col.alignment = BoxContainer.ALIGNMENT_CENTER
	shoe_row.add_child(timer_col)
	deal_time_label = _label("", 24, Palette.CREAM)
	timer_col.add_child(deal_time_label)
	deal_bar = ProgressBar.new()
	deal_bar.custom_minimum_size = Vector2(280, 16)
	deal_bar.show_percentage = false
	deal_bar.max_value = 1.0
	deal_bar.step = 0.0  # smooth fill
	deal_bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	timer_col.add_child(deal_bar)

	table.add_child(_label("Your hand", 20, Palette.CREAM.darkened(0.25)))
	my_hand_row = HBoxContainer.new()
	my_hand_row.add_theme_constant_override("separation", 10)
	my_hand_row.custom_minimum_size = Vector2(0, HAND_CARD_H)
	table.add_child(my_hand_row)
	my_total_label = _label("", 48, Palette.CREAM)
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
	board.add_theme_constant_override("separation", 10)
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
	if deal_left > 0.0:
		deal_left = maxf(deal_left - delta, 0.0)
	_update_deal_timer()


## The bar fills up towards the next card; the label counts down the seconds left.
func _update_deal_timer() -> void:
	if deal_bar == null:
		return
	var counting: bool = not over and (dealing or deal_left > 0.0)
	deal_bar.value = 1.0 - deal_left / maxf(deal_span, 0.01) if counting else 0.0
	if not counting:
		deal_time_label.text = ""
	elif dealing:
		deal_time_label.text = "Next card in %.1fs" % deal_left
	else:
		deal_time_label.text = "Dealing in %.1fs" % deal_left


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
	_show_shoe(int(st.get("next_card", -1)), int(st.get("last_card", -1)), false)
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
			_show_shoe(int(ev.get("next_card", -1)), -1, true)
			banner.text = "Everyone busted. Replay!" if replay else "New round: fresh count"

		&"bust_or_bank_card":
			dealing = true
			var card: int = int(ev.get("card", -1))
			_show_shoe(int(ev.get("next_card", -1)), card, true)
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
			_show_shoe(-1, last_card, false)  # the next round reveals its own next card
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


## Shows the shared next card (face up) and the card just dealt; `animate` flips changed cards in.
func _show_shoe(p_next: int, p_last: int, animate: bool) -> void:
	var next_changed: bool = p_next != next_card
	var last_changed: bool = p_last != last_card
	next_card = p_next
	last_card = p_last
	next_face.card = next_card
	dealt_face.card = last_card
	if animate and next_changed and next_card >= 0:
		next_face.flip_in()
	if animate and last_changed and last_card >= 0:
		dealt_face.deal_in()


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
	var bust: bool = bool(mine["busted"])
	_sync_faces(my_hand_row, mine["cards"], HAND_CARD_H, bust)
	my_total_label.text = str(int(mine["total"]))
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
	_update_deal_timer()


func _update_board() -> void:
	for p: Variant in board_rows:
		(board_rows[p]["box"] as Control).visible = int(p) in players  # gone after a disconnect
	for p: int in players:
		var row: Dictionary = board_rows.get(p, {})
		if row.is_empty():
			row = _make_board_row(p)
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
		var label: Label = row["label"]
		label.text = "%s   %s   (%d pts)" % [_name(p), status, int(points.get(p, 0))]
		label.add_theme_color_override("font_color", color)
		label.set_meta("status", status)
		_sync_faces(row["cards"], h["cards"], BOARD_CARD_H, bool(h["busted"]))
		var total: Label = row["total"]
		total.text = "Total %d" % int(h["total"]) if not (h["cards"] as Array).is_empty() else ""
		total.add_theme_color_override("font_color", color)


func _make_board_row(p: int) -> Dictionary:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.set_meta("player", p)
	board.add_child(box)
	var label := _label("", 22, Palette.CREAM)
	label.set_meta("player", p)
	box.add_child(label)
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 4)
	cards.custom_minimum_size = Vector2(0, BOARD_CARD_H)
	box.add_child(cards)
	var total := _label("", 18, Palette.CREAM)
	box.add_child(total)
	return {"box": box, "label": label, "cards": cards, "total": total}


## Makes `row` show `cards` as faces `height` px tall: new cards are dealt in with a short tween,
## a new round (fewer cards) clears the row first.
func _sync_faces(row: HBoxContainer, cards: Array, height: float, dim: bool) -> void:
	var faces: Array[Node] = row.get_children()
	if faces.size() > cards.size():
		for f: Node in faces:
			row.remove_child(f)
			f.queue_free()
		faces.clear()
	for i: int in faces.size():
		var face: CardFace = faces[i]
		face.card = int(cards[i])
		face.dimmed = dim
	for i: int in range(faces.size(), cards.size()):
		var face: CardFace = CardFace.make(int(cards[i]), height)
		face.dimmed = dim
		row.add_child(face)
		face.deal_in(0.12 * (i - faces.size()))
