class_name HiLoUi
extends StationUi
## Hi-Lo panel, docked right (the cards are dealt on the felt in the middle of the screen). Ante
## with the chips; once your card is up the two big buttons carry the call's true chance and what
## it pays, both straight from the server ("HIGHER ▲ 55% · ×1.74"). After a right call the pot and
## your step on the ladder show, and CASH OUT banks it; calling again lets it ride.
## Keys: ↑ or H higher, ↓ or S lower, P cash out (gamepad: A higher, X lower, RB cash out).

const LADDER_STEPS: int = 6

var card_label: Label
var pot_label: Label
var ladder_row: HBoxContainer
var ladder_marks: Array[Label] = []
var actions: VBoxContainer
var higher_btn: Button
var lower_btn: Button
var cash_btn: Button
var bet_panel: BetPanel
var others_label: Label


func _init() -> void:
	game_title = "HI-LO"


func _panel_height() -> float:
	return 470.0


func _dock_right() -> bool:
	return true


## Always locked: at this table you can always act (ante, or make the open call).
func wants_camera_lock() -> bool:
	return true


## The local player's hand in the newest state (empty when they have none).
func my_hand() -> Dictionary:
	return HiLoStation.hand_of(pub.get("hands", {}), local_id)


func _build() -> void:
	card_label = _line("", 30, Palette.CREAM)
	card_label.name = "Card"
	pot_label = _line("", 24, Palette.VIP_GOLD)
	pot_label.name = "Pot"
	ladder_row = HBoxContainer.new()
	ladder_row.name = "Ladder"
	ladder_row.alignment = BoxContainer.ALIGNMENT_CENTER
	ladder_row.add_theme_constant_override(&"separation", 6)
	body.add_child(ladder_row)
	for i: int in LADDER_STEPS:
		var l := Label.new()
		l.text = str(i + 1)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.custom_minimum_size = Vector2(40, 32)
		l.add_theme_font_size_override(&"font_size", 18)
		ladder_row.add_child(l)
		ladder_marks.append(l)
	actions = VBoxContainer.new()
	actions.name = "Actions"
	actions.add_theme_constant_override(&"separation", 8)
	body.add_child(actions)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 10)
	actions.add_child(row)
	higher_btn = _call_button("Higher", func() -> void: call_it(&"higher"))
	row.add_child(higher_btn)
	lower_btn = _call_button("Lower", func() -> void: call_it(&"lower"))
	row.add_child(lower_btn)
	cash_btn = Button.new()
	cash_btn.name = "CashOut"
	cash_btn.theme_type_variation = &"ActionButton"
	cash_btn.custom_minimum_size = Vector2(0, 52)
	cash_btn.focus_mode = Control.FOCUS_NONE
	cash_btn.pressed.connect(cash_out)
	actions.add_child(cash_btn)
	others_label = _line("", 16, Color("#9A8F7A"))
	others_label.name = "Others"
	others_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bet_panel = BetPanel.new()
	bet_panel.confirmed.connect(func(a: int) -> void: send(&"place_bet", {"bet": {"amount": a}}))
	body.add_child(bet_panel)


func _on_open() -> void:
	var lo: int = scaled(Registry.balance.hilo_min_bet)
	var hi: int = scaled(Registry.balance.hilo_max_bet)
	bet_panel.setup([lo, lo * 2 + lo / 2, lo * 5, lo * 10], lo, hi, "ANTE")
	bet_panel.set_amount(lo * 2 + lo / 2)


## Sends the call (the server checks it and deals the card).
func call_it(guess: StringName) -> bool:
	return send(&"action", {"action": guess})


func cash_out() -> bool:
	return send(&"action", {"action": &"cash_out"})


func _hint_text() -> String:
	if InputGlyphs.gamepad:
		return InputGlyphs.fill("[{bet_chip_prev} / {bet_chip_next}] chip  [{bet_confirm}] ante\n[{leave_station}] stand up")
	return InputGlyphs.fill("Aces high, a tie loses\n[1-4] chip  [{bet_confirm}] ante  [{leave_station}] stand up")


func _relabel() -> void:
	_refresh_buttons()


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not actions.visible:
		return
	var key: Key = (event as InputEventKey).physical_keycode if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo else KEY_NONE
	if (event.is_action_pressed(&"bj_hit") or key == KEY_UP) and not higher_btn.disabled:
		higher_btn.pressed.emit()
	elif (event.is_action_pressed(&"bj_stand") or key == KEY_DOWN) and not lower_btn.disabled:
		lower_btn.pressed.emit()
	elif event.is_action_pressed(&"bj_split") and cash_btn.visible:
		cash_btn.pressed.emit()
	else:
		return
	get_viewport().set_input_as_handled()


func _refresh() -> void:
	var mine: Dictionary = my_hand()
	var phase: String = String(mine.get("phase", ""))
	var playing: bool = phase == "play"
	var cards: Array = mine.get("cards", [])
	var rung: int = int(mine.get("rung", 0))
	if mine.is_empty():
		status_label.text = "Ante up for a card"
		card_label.text = ""
		pot_label.text = ""
	else:
		var up: String = _pretty(Card.label(int(cards.back()))) if not cards.is_empty() else "—"
		card_label.text = ("SHOWING  %s" % up) if playing else "  ".join(_labels(cards))
		var pot: int = int(mine.get("pot", 0))
		match String(mine.get("outcome", "")):
			"lose":
				status_label.text = "%s: wrong call, the pot is lost" % up
				pot_label.text = "−$%d" % int(mine.get("stake", 0))
			"cashed":
				status_label.text = "Cashed out after %d right call%s" % [rung, "" if rung == 1 else "s"]
				pot_label.text = "+$%d" % pot
			_:
				var secs: int = int(ceil(float(mine.get("timer", 0.0))))
				status_label.text = ("Right! Ride it or cash out  (%d s)" % secs) if rung > 0 else ("Your call  (%d s)" % secs)
				pot_label.text = ("POT $%d  ·  ×%.2f" % [pot, float(mine.get("mult", 1.0))]) if rung > 0 else ("ANTE $%d" % int(mine.get("stake", 0)))
	for i: int in ladder_marks.size():
		var lit: bool = i < rung
		ladder_marks[i].add_theme_color_override(&"font_color", Palette.CASINO_BLACK if lit else Color(Palette.CREAM, 0.45))
		var sb := StyleBoxFlat.new()
		sb.bg_color = Palette.VIP_GOLD if lit else Color(Palette.CASINO_BLACK, 0.5)
		sb.border_color = Color(Palette.WARM_GOLD, 0.6)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(6)
		ladder_marks[i].add_theme_stylebox_override(&"normal", sb)
	ladder_row.visible = not mine.is_empty()
	actions.visible = playing
	_refresh_buttons()
	bet_panel.visible = not playing
	others_label.text = _others_text()


## The two calls with their true chance and pay (as the server locked them), and the cash-out.
func _refresh_buttons() -> void:
	if higher_btn == null:
		return
	var mine: Dictionary = my_hand()
	var odds: Dictionary = mine.get("odds", {})
	var pays: Dictionary = mine.get("pays", {})
	_set_call(higher_btn, "HIGHER ▲", "higher", odds, pays, &"bj_hit")
	_set_call(lower_btn, "LOWER ▼", "lower", odds, pays, &"bj_stand")
	var rung: int = int(mine.get("rung", 0))
	cash_btn.visible = rung > 0
	cash_btn.text = "CASH OUT  $%d  %s" % [int(mine.get("pot", 0)), InputGlyphs.hint(&"bj_split")]


func _set_call(b: Button, title: String, side: String, odds: Dictionary, pays: Dictionary, action: StringName) -> void:
	var p: float = float(odds.get(side, 0.0))
	var pay: float = float(pays.get(side, 0.0))
	if p <= 0.0:
		b.text = "%s\nno card can" % title
		b.disabled = true
	else:
		b.text = "%s  %s\n%s  ·  pays ×%.2f" % [title, InputGlyphs.hint(action), percent(p), pay]
		b.disabled = false


## "55%", or "<1%" / ">99%" at the very edges (the button never claims a sure thing).
static func percent(p: float) -> String:
	if p > 0.0 and p < 0.01:
		return "<1%"
	if p < 1.0 and p > 0.99:
		return ">99%"
	return "%d%%" % roundi(p * 100.0)


## Everyone else at the table: their card up and their step on the ladder.
func _others_text() -> String:
	var lines: PackedStringArray = []
	var hands: Dictionary = pub.get("hands", {})
	for s: Variant in pub.get("seats", []):
		var pid: int = int(s)
		if pid < 0 or pid == local_id:
			continue
		var h: Dictionary = HiLoStation.hand_of(hands, pid)
		var who: String = state.player_name(pid) if state != null else str(pid)
		if h.is_empty():
			lines.append("%s: watching" % who)
			continue
		var cards: Array = h.get("cards", [])
		var up: String = _pretty(Card.label(int(cards.back()))) if not cards.is_empty() else "—"
		lines.append("%s: %s  ·  step %d  ·  $%d" % [who, up, int(h.get("rung", 0)), int(h.get("pot", 0))])
	return "\n".join(lines)


func _call_button(node_name: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.name = node_name
	b.theme_type_variation = &"ActionButton"
	b.custom_minimum_size = Vector2(186, 78)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override(&"font_size", 19)
	b.pressed.connect(on_pressed)
	return b


func _line(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", color)
	body.add_child(l)
	return l


func _labels(cards: Array) -> Array[String]:
	var out: Array[String] = []
	for c: Variant in cards:
		out.append(_pretty(Card.label(int(c))))
	return out


static func _pretty(label: String) -> String:
	return label.replace("S", "♠").replace("H", "♥").replace("D", "♦").replace("C", "♣")
