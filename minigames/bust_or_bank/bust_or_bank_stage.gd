class_name BustOrBankStage
extends MinigameStage
## Client presentation for Bust or Bank: a green felt table in the middle with everyone's hand
## seated round it (you at the bottom, the others clockwise in turn order). One player at a time
## decides: the current seat glows gold with a countdown bar, and the table centre shows whose turn
## it is, the seconds left and the NEXT card face up ("do I want THAT card?"). On your own turn the
## big HIT / STAND buttons light up (keys: the blackjack bindings `bj_hit` / `bj_stand`, H / S by
## default). The result shows every final hand with the winner(s) highlighted.
##
## Everything shown comes from server events / snapshots; timings come from the events' `deal_in`
## / `time` and the snapshot `timer`, never from local constants. The only input is the
## `bust_or_bank_action` intent ("hit" / "stand").

const State := BustOrBankLogic.State
## Card heights (px): the shared next card in the table centre, the cards in each seat.
const NEXT_CARD_H: float = 150.0
const SEAT_CARD_H: float = 66.0
const SEAT_SIZE: Vector2 = Vector2(330, 146)
## Seat colours.
const SEAT_BG: Color = Color(0.141, 0.129, 0.122, 0.94)  # warm charcoal, slightly see-through
const RAIL: Color = Color("#3A2418")  # dark wood rail round the felt

var root: Control
var title_label: Label
var banner: Label
## Holds the table and the seats; laid out from its size (`_layout`).
var arena: Control
var table: Panel
var table_ring: Panel
var centre: VBoxContainer
var next_col: VBoxContainer
var next_title: Label
## The shared upcoming card, face up for everyone.
var next_face: CardFace
var turn_label: Label
var countdown_label: Label
var countdown_bar: ProgressBar
## RESULT: everyone's final place, "#1 Bo 20".
var result_grid: GridContainer
var felt_label: Label
var prompt_label: Label
var hit_button: Button
var stand_button: Button
## player → {panel, style, dot, name, state, cards, total, bar} (built once, updated in place).
var seats: Dictionary = {}

## Seat order (the turn circle), straight from the server.
var players: Array[int] = []
## player → {cards: Array, total: int, busted: bool, stood: bool}.
var hands: Dictionary = {}
var phase: int = State.INTRO
## Whose turn it is (-1 = nobody).
var current: int = -1
## Seconds left on the countdown shown (the intro, or the current turn) and its full span.
var time_left: float = 0.0
var time_span: float = BustOrBankLogic.TURN_TIME
var turn_time: float = BustOrBankLogic.TURN_TIME
## The shared upcoming card (-1 = none, drawn face down) and the card dealt last.
var next_card: int = -1
var last_card: int = -1
var ranking: Array = []
var winners: Array[int] = []
var over: bool = false
## Sent HIT / STAND and waiting for the server's answer.
var action_sent: bool = false
## How intents leave (tests swap it).
var send_intent: Callable = func(i: Dictionary) -> Dictionary: return Net.send_intent(i)


func _build(start: Dictionary) -> void:
	for p: Variant in start.get("players", []):
		players.append(int(p))
	for p: int in players:
		hands[p] = _empty_hand()
	time_left = BustOrBankLogic.INTRO_TIME
	time_span = time_left
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
	bg.color = Palette.CASINO_BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 22)
	root.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 8)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(col)

	# Top bar: title and the latest news.
	var top := HBoxContainer.new()
	top.add_theme_constant_override(&"separation", 24)
	col.add_child(top)
	title_label = _label("BUST OR BANK", 44, Palette.VIP_GOLD)
	title_label.theme_type_variation = &"HeadingLabel"
	title_label.add_theme_font_size_override(&"font_size", 44)
	top.add_child(title_label)
	banner = _label("", 28, Palette.CREAM)
	banner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top.add_child(banner)

	# The table with the seats round it.
	arena = Control.new()
	arena.size_flags_vertical = Control.SIZE_EXPAND_FILL
	arena.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arena.resized.connect(_layout)
	col.add_child(arena)

	table = Panel.new()
	table.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var felt := StyleBoxFlat.new()
	felt.bg_color = Palette.FELT_GREEN
	felt.border_color = RAIL
	felt.set_border_width_all(16)
	felt.shadow_color = Color(0, 0, 0, 0.55)
	felt.shadow_size = 24
	felt.anti_aliasing = true
	table.add_theme_stylebox_override(&"panel", felt)
	arena.add_child(table)
	table_ring = Panel.new()
	table_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ring := StyleBoxFlat.new()
	ring.draw_center = false
	ring.border_color = Color(Palette.WARM_GOLD, 0.55)
	ring.set_border_width_all(2)
	ring.anti_aliasing = true
	table_ring.add_theme_stylebox_override(&"panel", ring)
	arena.add_child(table_ring)
	felt_label = _label("HIGHEST HAND WINS  ·  OVER 21 BUSTS", 20, Color(Palette.WARM_GOLD, 0.6))
	felt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arena.add_child(felt_label)

	# Table centre: the next card and whose turn it is.
	centre = VBoxContainer.new()
	centre.alignment = BoxContainer.ALIGNMENT_CENTER
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arena.add_child(centre)
	var mid := HBoxContainer.new()
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_theme_constant_override(&"separation", 40)
	centre.add_child(mid)
	next_col = VBoxContainer.new()
	next_col.add_theme_constant_override(&"separation", 6)
	mid.add_child(next_col)
	next_title = _label("NEXT CARD", 22, Palette.WARM_GOLD)
	next_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	next_col.add_child(next_title)
	next_face = CardFace.make(-1, NEXT_CARD_H)
	next_face.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	next_col.add_child(next_face)
	var info := VBoxContainer.new()
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.add_theme_constant_override(&"separation", 2)
	info.custom_minimum_size = Vector2(420, 0)
	mid.add_child(info)
	turn_label = _label("", 40, Palette.CREAM)
	turn_label.theme_type_variation = &"HeadingLabel"
	turn_label.add_theme_font_size_override(&"font_size", 40)
	turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turn_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(turn_label)
	countdown_label = _label("", 80, Palette.CREAM)
	countdown_label.theme_type_variation = &"HeadingLabel"
	countdown_label.add_theme_font_size_override(&"font_size", 80)
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_child(countdown_label)
	countdown_bar = _bar(Vector2(340, 16), Palette.WARM_GOLD)
	countdown_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	info.add_child(countdown_bar)
	result_grid = GridContainer.new()
	result_grid.columns = 2
	result_grid.add_theme_constant_override(&"h_separation", 48)
	result_grid.add_theme_constant_override(&"v_separation", 2)
	result_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	result_grid.visible = false
	info.add_child(result_grid)

	# Bottom: what to do and the two big buttons.
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override(&"separation", 28)
	col.add_child(bottom)
	prompt_label = _label("", 28, Palette.CREAM)
	prompt_label.custom_minimum_size = Vector2(520, 0)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bottom.add_child(prompt_label)
	hit_button = _action_button(Palette.FELT_GREEN.lightened(0.15))
	hit_button.pressed.connect(_on_hit)
	bottom.add_child(hit_button)
	stand_button = _action_button(Palette.CASINO_RED)
	stand_button.pressed.connect(_on_stand)
	bottom.add_child(stand_button)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(520, 0)
	bottom.add_child(spacer)
	_relabel()


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _bar(min_size: Vector2, fill_color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = min_size
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.step = 0.0  # smooth
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back := StyleBoxFlat.new()
	back.bg_color = Color(Palette.CASINO_BLACK, 0.75)
	back.set_corner_radius_all(int(min_size.y / 2.0))
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.set_corner_radius_all(int(min_size.y / 2.0))
	bar.add_theme_stylebox_override(&"background", back)
	bar.add_theme_stylebox_override(&"fill", fill)
	return bar


func _action_button(color: Color) -> Button:
	var b := Button.new()
	b.theme_type_variation = &"ActionButton"
	b.custom_minimum_size = Vector2(280, 84)
	b.add_theme_font_size_override(&"font_size", 34)
	b.focus_mode = Control.FOCUS_NONE  # the keys are ours, not the focused button's
	for st: String in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(12)
		sb.set_border_width_all(3)
		sb.content_margin_left = 18
		sb.content_margin_right = 18
		match st:
			"normal":
				sb.bg_color = color
				sb.border_color = Palette.WARM_GOLD
			"hover":
				sb.bg_color = color.lightened(0.12)
				sb.border_color = Palette.VIP_GOLD
			"pressed":
				sb.bg_color = color.darkened(0.2)
				sb.border_color = Palette.VIP_GOLD
			_:
				sb.bg_color = Palette.WARM_CHARCOAL
				sb.border_color = Color(Palette.CREAM, 0.15)
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_color_override(&"font_color", Palette.CREAM)
	b.add_theme_color_override(&"font_hover_color", Palette.CREAM)
	b.add_theme_color_override(&"font_pressed_color", Palette.CREAM)
	b.add_theme_color_override(&"font_disabled_color", Color(Palette.CREAM, 0.3))
	return b


func _relabel() -> void:
	hit_button.text = "HIT  %s" % InputGlyphs.hint(&"bj_hit")
	stand_button.text = "STAND  %s" % InputGlyphs.hint(&"bj_stand")


func _empty_hand() -> Dictionary:
	return {"cards": [], "total": 0, "busted": false, "stood": false}


# --- Layout ------------------------------------------------------------------------------------

## The table fills the middle of the arena; the seats sit on an ellipse round it, you at the
## bottom and the others clockwise in turn order.
func _layout() -> void:
	if arena == null:
		return
	var sz: Vector2 = arena.size
	var c: Vector2 = sz / 2.0
	var tsize := Vector2(sz.x * 0.62, sz.y * 0.6)
	table.position = c - tsize / 2.0
	table.size = tsize
	var felt: StyleBoxFlat = table.get_theme_stylebox(&"panel") as StyleBoxFlat
	felt.set_corner_radius_all(int(tsize.y / 2.0))
	var inset: float = 30.0
	table_ring.position = table.position + Vector2(inset, inset)
	table_ring.size = tsize - Vector2(inset, inset) * 2.0
	(table_ring.get_theme_stylebox(&"panel") as StyleBoxFlat).set_corner_radius_all(int(table_ring.size.y / 2.0))
	centre.size = Vector2(tsize.x * 0.62, tsize.y * 0.8)
	centre.position = c - centre.size / 2.0 - Vector2(0, 8)
	felt_label.size = Vector2(tsize.x * 0.5, 30)
	felt_label.position = Vector2(c.x - felt_label.size.x / 2.0, table.position.y + tsize.y - inset - 40.0)

	var shown: Array[int] = _seat_order()
	var n: int = shown.size()
	var rx: float = maxf(sz.x / 2.0 - SEAT_SIZE.x / 2.0 - 8.0, 0.0)
	var ry: float = maxf(sz.y / 2.0 - SEAT_SIZE.y / 2.0 - 4.0, 0.0)
	for i: int in n:
		var seat: Dictionary = seats.get(shown[i], {})
		if seat.is_empty():
			continue
		var a: float = PI / 2.0 + TAU * float(i) / float(n)
		var pos: Vector2 = c + Vector2(cos(a) * rx, sin(a) * ry)
		var panel: Control = seat["panel"]
		panel.size = SEAT_SIZE
		panel.position = (pos - SEAT_SIZE / 2.0).round()


## Seat order rotated so the local player sits at the bottom.
func _seat_order() -> Array[int]:
	var out: Array[int] = []
	var start: int = maxi(players.find(local_id), 0)
	for i: int in players.size():
		out.append(players[(start + i) % players.size()])
	return out


# --- Input -------------------------------------------------------------------------------------

func _unhandled_input(ev: InputEvent) -> void:
	if ev.is_echo():
		return
	if ev.is_action_pressed(&"bj_hit") and can_act():
		_on_hit()
	elif ev.is_action_pressed(&"bj_stand") and can_act():
		_on_stand()
	else:
		return
	get_viewport().set_input_as_handled()


## True on your own turn while no decision is on its way to the server.
func can_act() -> bool:
	return not over and phase == State.TURN and current == local_id and current >= 0 and not action_sent


func _on_hit() -> void:
	_send("hit")


func _on_stand() -> void:
	_send("stand")


func _send(action: String) -> void:
	if not can_act():
		return
	action_sent = true
	_refresh()
	var r: Dictionary = send_intent.call(Intents.make(&"bust_or_bank_action", {"action": action}))
	if not bool(r.get("ok", true)):
		action_sent = false
		_refresh()


func _process(delta: float) -> void:
	if time_left > 0.0 and not over:
		time_left = maxf(time_left - delta, 0.0)
	_update_countdown()


func _update_countdown() -> void:
	if countdown_bar == null:
		return
	var counting: bool = not over and (phase == State.TURN or phase == State.INTRO)
	countdown_bar.visible = counting
	countdown_label.visible = counting
	countdown_bar.value = time_left / maxf(time_span, 0.01) if counting else 0.0
	countdown_label.text = str(ceili(time_left)) if counting else ""
	var urgent: bool = phase == State.TURN and time_left <= 5.0
	countdown_label.add_theme_color_override(&"font_color", Palette.LOSS_RED if urgent else Palette.CREAM)
	var seat: Dictionary = seats.get(current, {})
	if not seat.is_empty():
		(seat["bar"] as ProgressBar).value = countdown_bar.value


# --- Server data -------------------------------------------------------------------------------

func apply_state(st: Dictionary) -> void:
	if st.has("players"):
		players.clear()
		for p: Variant in st["players"]:
			players.append(int(p))
	var hs: Dictionary = st.get("hands", {})
	for p: Variant in hs:
		hands[int(p)] = _hand_from(hs[p])
	turn_time = float(st.get("turn_time", turn_time))
	phase = int(st.get("state", State.INTRO))
	current = int(st.get("current", -1))
	time_left = float(st.get("timer", 0.0))
	time_span = turn_time if phase == State.TURN else maxf(time_left, 0.01)
	next_card = int(st.get("next_card", -1))
	next_face.card = next_card
	last_card = int(st.get("last_card", -1))
	if st.has("ranking"):
		_show_result(st["ranking"], st.get("winners", []))
	_refresh()


func on_event(ev: Dictionary) -> void:
	match ev["type"]:
		&"bust_or_bank_started":
			turn_time = float(ev.get("turn_time", turn_time))
			_set_players(ev.get("players", []))

		&"bust_or_bank_round_started":
			_set_players(ev.get("players", []))
			for p: int in players:
				hands[p] = _empty_hand()
			phase = State.INTRO
			current = -1
			action_sent = false
			turn_time = float(ev.get("turn_time", turn_time))
			time_left = float(ev.get("deal_in", 0.0))
			time_span = maxf(time_left, 0.01)
			_show_next(int(ev.get("next_card", -1)))
			banner.text = "One card each, then it's turn by turn."

		&"bust_or_bank_card":
			var pid: int = int(ev.get("player", -1))
			if not hands.has(pid):
				hands[pid] = _empty_hand()
			var h: Dictionary = hands[pid]
			var card: int = int(ev.get("card", -1))
			last_card = card
			(h["cards"] as Array).append(card)
			h["total"] = int(ev.get("total", h["total"]))
			h["busted"] = bool(ev.get("busted", false))
			_show_next(int(ev.get("next_card", -1)))
			if not bool(ev.get("opening", false)):
				if pid == local_id:
					action_sent = false
				if bool(h["busted"]):
					banner.text = "%s took the %s: %d, BUST!" % [_name(pid), _card_text(card), int(h["total"])]
				else:
					banner.text = "%s took the %s: %d" % [_name(pid), _card_text(card), int(h["total"])]

		&"bust_or_bank_turn":
			phase = State.TURN
			current = int(ev.get("player", -1))
			action_sent = false
			time_left = float(ev.get("time", turn_time))
			time_span = maxf(time_left, 0.01)
			_show_next(int(ev.get("next_card", next_card)))

		&"bust_or_bank_player_stood":
			var pid: int = int(ev.get("player", -1))
			if hands.has(pid):
				hands[pid]["stood"] = true
				hands[pid]["total"] = int(ev.get("total", hands[pid]["total"]))
			if pid == local_id:
				action_sent = false
			match StringName(str(ev.get("reason", ""))):
				&"timeout":
					banner.text = "Time's up: %s %s on %d" % [_name(pid), _verb(pid, "stand"), int(ev.get("total", 0))]
				&"21":
					banner.text = "21! %s %s automatically" % [_name(pid), _verb(pid, "stand")]
				_:
					banner.text = "%s %s on %d" % [_name(pid), _verb(pid, "stand"), int(ev.get("total", 0))]

		&"bust_or_bank_player_left":
			var pid: int = int(ev.get("player", -1))
			if pid in players:
				banner.text = "%s left the table" % _name(pid)
			players.erase(pid)
			hands.erase(pid)

		&"bust_or_bank_round_end":
			var hs: Dictionary = ev.get("hands", {})
			for p: Variant in hs:
				hands[int(p)] = _hand_from(hs[p])
			_show_result(ev.get("ranking", []), ev.get("winners", []))
	_refresh()


func on_private(_priv: Dictionary) -> void:
	pass  # whose turn it is comes with the public events


func _set_players(src: Array) -> void:
	if src.is_empty():
		return
	players.clear()
	for p: Variant in src:
		players.append(int(p))
		if not hands.has(int(p)):
			hands[int(p)] = _empty_hand()


func _hand_from(h: Dictionary) -> Dictionary:
	return {"cards": (h.get("cards", []) as Array).duplicate(), "total": int(h.get("total", 0)),
		"busted": bool(h.get("busted", false)), "stood": bool(h.get("stood", false))}


## Shows the shared next card face up, flipping it in when it changed.
func _show_next(card: int) -> void:
	var changed: bool = card != next_card
	next_card = card
	next_face.card = card
	if changed and card >= 0:
		next_face.flip_in()


func _show_result(p_ranking: Array, p_winners: Array) -> void:
	over = true
	phase = State.RESULT
	current = -1
	action_sent = false
	time_left = 0.0
	ranking = p_ranking.duplicate(true)
	winners.clear()
	for p: Variant in p_winners:
		winners.append(int(p))
	if winners.is_empty():
		for row: Variant in ranking:
			if int((row as Dictionary).get("rank", 0)) == 1:
				winners.append(int(row["player"]))
	next_card = -1
	next_face.card = -1
	banner.text = "Final hands"


func _name(pid: int) -> String:
	if pid == local_id:
		return "You"
	return state.player_name(pid) if state != null else "Player %d" % pid


func _verb(pid: int, verb: String) -> String:
	return verb if pid == local_id else verb + "s"


func _player_color(pid: int) -> Color:
	var idx: int = int(state.players.get(pid, {}).get("color", pid - 1)) if state != null else pid - 1
	return Palette.player_color(idx)


func _card_text(card: int) -> String:
	if card < 0:
		return "?"
	return Card.RANK_NAMES[Card.rank(card)] + CardFace.SUIT_GLYPHS[Card.suit(card)]


func _names(ids: Array[int]) -> String:
	var out: Array[String] = []
	for p: int in ids:
		out.append(_name(p))
	return " & ".join(out)


# --- Drawing -----------------------------------------------------------------------------------

func _refresh() -> void:
	var mine: bool = current == local_id and current >= 0
	if over:
		var best: int = int(hands.get(winners[0], _empty_hand())["total"]) if not winners.is_empty() else 0
		if winners.is_empty():
			turn_label.text = "Nobody at the table"
		elif bool(hands.get(winners[0], _empty_hand())["busted"]):
			turn_label.text = "Everyone busted!"
		elif winners.size() == 1:
			turn_label.text = "%s %s with %d!" % [_name(winners[0]), "win" if winners[0] == local_id else "wins", best]
		else:
			turn_label.text = "%s share the win with %d!" % [_names(winners), best]
		turn_label.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	elif phase == State.INTRO:
		turn_label.text = "Dealing..."
		turn_label.add_theme_color_override(&"font_color", Palette.CREAM)
	elif mine:
		turn_label.text = "YOUR TURN"
		turn_label.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	elif current >= 0:
		turn_label.text = "%s'S TURN" % _name(current).to_upper()
		turn_label.add_theme_color_override(&"font_color", Palette.CREAM)
	else:
		turn_label.text = ""
	next_col.visible = not over
	_update_result_grid()

	hit_button.disabled = not can_act()
	stand_button.disabled = not can_act()
	var my_hand: Dictionary = hands.get(local_id, _empty_hand())
	if over:
		prompt_label.text = _my_result()
	elif local_id not in players:
		prompt_label.text = "Watching"
	elif bool(my_hand["busted"]):
		prompt_label.text = "Bust! Watch the rest play out."
	elif bool(my_hand["stood"]):
		prompt_label.text = "You stand on %d." % int(my_hand["total"])
	elif mine and action_sent:
		prompt_label.text = "..."
	elif mine:
		prompt_label.text = "You have %d. Take the %s?" % [int(my_hand["total"]), _card_text(next_card)]
	elif phase == State.INTRO:
		prompt_label.text = "Get ready"
	else:
		prompt_label.text = "Wait for your turn (you have %d)" % int(my_hand["total"])
	_update_seats()
	_update_countdown()


func _update_result_grid() -> void:
	result_grid.visible = over and not ranking.is_empty()
	if not result_grid.visible or result_grid.get_child_count() == ranking.size():
		return
	for c: Node in result_grid.get_children():
		result_grid.remove_child(c)
		c.queue_free()
	for row: Variant in ranking:
		var r: Dictionary = row
		var p: int = int(r.get("player", -1))
		var h: Dictionary = hands.get(p, _empty_hand())
		var total: String = "BUST" if bool(h["busted"]) else str(int(h["total"]))
		var l := _label("#%d  %s  %s" % [int(r.get("rank", 0)), _name(p), total], 24, Palette.VIP_GOLD if p in winners else Palette.CREAM)
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.custom_minimum_size = Vector2(200, 0)
		result_grid.add_child(l)


func _my_result() -> String:
	for row: Variant in ranking:
		var r: Dictionary = row
		if int(r.get("player", -1)) == local_id:
			return "You finished #%d" % int(r.get("rank", 0))
	return "Game over"


func _update_seats() -> void:
	for p: Variant in seats:
		(seats[p]["panel"] as Control).visible = int(p) in players  # gone after a disconnect
	for p: int in players:
		if not seats.has(p):
			seats[p] = _make_seat(p)
		_update_seat(p)
	_layout()


func _update_seat(p: int) -> void:
	var seat: Dictionary = seats[p]
	var h: Dictionary = hands.get(p, _empty_hand())
	var is_turn: bool = p == current and not over and phase == State.TURN
	var won: bool = over and p in winners
	var status: String
	var color: Color = Palette.CREAM
	if won:
		status = "WINNER"
		color = Palette.VIP_GOLD
	elif bool(h["busted"]):
		status = "BUST"
		color = Palette.LOSS_RED
	elif bool(h["stood"]):
		status = "STOOD"
		color = Palette.WARM_GOLD
	elif is_turn:
		status = "YOUR TURN" if p == local_id else "TURN"
		color = Palette.VIP_GOLD
	elif over:
		status = ""
	else:
		status = "WAITING"
		color = Color(Palette.CREAM, 0.55)
	var state_label: Label = seat["state"]
	state_label.text = status
	state_label.add_theme_color_override(&"font_color", color)
	var name_label: Label = seat["name"]
	name_label.text = (state.player_name(p) if state != null else "Player %d" % p) + ("  (you)" if p == local_id else "")
	var total: Label = seat["total"]
	total.text = str(int(h["total"])) if not (h["cards"] as Array).is_empty() else ""
	total.add_theme_color_override(&"font_color", Palette.LOSS_RED if bool(h["busted"]) else Palette.CREAM)
	(seat["bar"] as ProgressBar).visible = is_turn
	_sync_faces(seat["cards"], h["cards"], SEAT_CARD_H, bool(h["busted"]))

	var sb: StyleBoxFlat = seat["style"]
	var pc: Color = _player_color(p)
	if is_turn or won:
		sb.border_color = Palette.VIP_GOLD
		sb.set_border_width_all(5)
		sb.shadow_color = Color(Palette.VIP_GOLD, 0.45)
		sb.shadow_size = 18
		sb.bg_color = SEAT_BG.lightened(0.08)
	else:
		sb.border_color = Color(pc, 0.85)
		sb.set_border_width_all(2)
		sb.shadow_color = Color(0, 0, 0, 0.4)
		sb.shadow_size = 8
		sb.bg_color = SEAT_BG
	(seat["panel"] as Control).modulate = Color(1, 1, 1, 0.7) if bool(h["busted"]) and not won else Color.WHITE
	(seat["panel"] as Control).set_meta("status", status)


func _make_seat(p: int) -> Dictionary:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_meta("player", p)
	panel.clip_contents = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = SEAT_BG
	sb.set_corner_radius_all(14)
	sb.set_border_width_all(2)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	sb.anti_aliasing = true
	panel.add_theme_stylebox_override(&"panel", sb)
	arena.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 8)
	box.add_child(head)
	var dot := ColorRect.new()
	dot.color = _player_color(p)
	dot.custom_minimum_size = Vector2(14, 14)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(dot)
	var name_label := _label("", 24, _player_color(p))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.clip_text = true
	head.add_child(name_label)
	var state_label := _label("", 22, Palette.CREAM)
	head.add_child(state_label)

	var body := HBoxContainer.new()
	body.add_theme_constant_override(&"separation", 10)
	box.add_child(body)
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override(&"separation", 4)
	cards.custom_minimum_size = Vector2(0, SEAT_CARD_H)
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(cards)
	var total := _label("", 44, Palette.CREAM)
	total.theme_type_variation = &"HeadingLabel"
	total.add_theme_font_size_override(&"font_size", 44)
	total.custom_minimum_size = Vector2(56, 0)
	total.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	total.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	body.add_child(total)

	var bar := _bar(Vector2(0, 10), Palette.VIP_GOLD)
	bar.visible = false
	box.add_child(bar)
	return {"panel": panel, "style": sb, "dot": dot, "name": name_label, "state": state_label, "cards": cards, "total": total, "bar": bar}


## Makes `row` show `cards` as faces `height` px tall: new cards are dealt in with a short tween,
## a new round (fewer cards) clears the row first. Long hands overlap so they fit the seat.
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
	var card_w: float = roundf(height * CardFace.ASPECT)
	var room: float = SEAT_SIZE.x - 28.0 - 66.0
	var n: int = cards.size()
	var sep: int = 4
	if n > 1 and n * card_w + (n - 1) * 4.0 > room:
		sep = floori((room - n * card_w) / float(n - 1))
	row.add_theme_constant_override(&"separation", sep)
