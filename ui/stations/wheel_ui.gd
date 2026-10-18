class_name WheelUi
extends StationUi
## Wheel of Fortune overlay: a column down the right third of the screen, so the wheel and the
## layout fill the rest (the seat camera frames them on the left). Pick a chip, click a symbol (in
## the wheel's colours, with the odds it pays) to put the chip on it; Enter puts another chip on
## the symbol you clicked last. Any number of symbols, up to the table maximum per spin. Shows the
## countdown to the spin, the result, the last spins, your stake per symbol and a dot per other
## player on each symbol; how it works is folded away under the key hint.

## Symbol buttons: size and how many to a row in the column.
const SYMBOL_SIZE: Vector2 = Vector2(128, 88)
const SYMBOL_COLUMNS: int = 4

var bet_panel: BetPanel
var symbol_buttons: Array[Button] = []
var result_label: Label
## Your stake and the chips.
var bets_row: VBoxContainer
var my_bets: Label
## The symbol the local player clicked last (−1 = none yet); Enter adds a chip on it.
var selected_symbol: int = -1
var _badges: Array[Label] = []
var _dots: Array[Label] = []


func _init() -> void:
	game_title = "WHEEL OF FORTUNE"


func _dock_column() -> bool:
	return true


## Locked while bets are open (the spin itself you may watch with the head free).
func wants_camera_lock() -> bool:
	return int(pub.get("state", 0)) == WheelLogic.State.BETTING


func _build() -> void:
	body.add_theme_constant_override(&"separation", 10)
	status_label.add_theme_font_size_override(&"font_size", 22)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(120, 0)
	result_label = Label.new()
	result_label.name = "Result"
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_label.custom_minimum_size = Vector2(120, 0)
	result_label.add_theme_font_size_override(&"font_size", 19)
	result_label.add_theme_color_override(&"font_color", Palette.WARM_GOLD)
	body.add_child(result_label)
	var row := GridContainer.new()
	row.name = "Symbols"
	row.columns = SYMBOL_COLUMNS
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	row.add_theme_constant_override(&"h_separation", 8)
	row.add_theme_constant_override(&"v_separation", 8)
	body.add_child(row)
	for i: int in WheelLogic.SYMBOLS.size():
		row.add_child(_symbol_button(i))
	bets_row = VBoxContainer.new()
	bets_row.name = "BetsRow"
	bets_row.add_theme_constant_override(&"separation", 8)
	body.add_child(bets_row)
	bet_panel = BetPanel.new()
	bet_panel.chip_size = Vector2(66, 44)
	bet_panel.chip_gap = 8
	bet_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bet_panel.add_theme_stylebox_override(&"panel", StyleBoxEmpty.new())
	bet_panel.cleared.connect(func() -> void: send(&"clear_bets"))
	bet_panel.confirmed.connect(func(_a: int) -> void:
		if selected_symbol >= 0:
			bet_on(selected_symbol))
	bets_row.add_child(bet_panel)
	my_bets = Label.new()
	my_bets.name = "MyBets"
	my_bets.theme_type_variation = &"SmallLabel"
	my_bets.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	my_bets.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	my_bets.custom_minimum_size = Vector2(120, 0)
	my_bets.add_theme_font_size_override(&"font_size", 16)
	bets_row.add_child(my_bets)


func _on_open() -> void:
	var lo: int = scaled(Registry.balance.wheel_min_bet)
	var hi: int = scaled(Registry.balance.wheel_max_total)
	bet_panel.setup([lo, lo * 2 + lo / 2, lo * 5, lo * 10], lo, hi, "")
	bet_panel.configure_visibility(false, false, true, false)
	selected_symbol = -1


## Puts the selected chip on `symbol` (sends the bet; the server checks everything).
func bet_on(symbol: int) -> bool:
	selected_symbol = symbol
	return send(&"place_bet", {"bet": {"symbol": symbol, "amount": bet_panel.chip_value()}})


func _hint_text() -> String:
	return "%s Stand up   ·   %s another chip on your last symbol" % [InputGlyphs.hint(&"leave_station"), InputGlyphs.hint(&"bet_confirm")]


func _rules_text() -> String:
	return ("Pick a chip, then click a symbol to put it there; chips on as many symbols as you like, up to the table maximum per spin. "
		+ "The dealer spins %d s after the first bet; the symbol under the clicker pays the odds on its button, the rest goes to the house.") % int(Registry.balance.wheel_countdown)


func _refresh() -> void:
	var st: int = int(pub.get("state", 0))
	var timer: float = float(pub.get("timer", 0.0))
	var open_bets: bool = st == WheelLogic.State.BETTING
	match st:
		WheelLogic.State.IDLE:
			status_label.text = "Waiting for players…"
		WheelLogic.State.BETTING:
			status_label.text = ("PLACE YOUR BETS  ·  THE DEALER SPINS IN %d s" % int(ceil(timer))) if bool(pub.get("counting", false)) else "PICK A SYMBOL: the dealer spins %d s after the first bet" % int(Registry.balance.wheel_countdown)
		WheelLogic.State.SPINNING:
			status_label.text = "No more bets: the wheel is spinning!"
		WheelLogic.State.RESULT:
			status_label.text = "Next spin in %d s" % int(ceil(timer))
	result_label.text = result_text(pub)
	var mine: Dictionary = {}
	var others: Dictionary = {}
	for b: Dictionary in pub.get("bets", []):
		var s: int = int(b["symbol"])
		if int(b["player"]) == local_id:
			mine[s] = int(mine.get(s, 0)) + int(b["amount"])
		else:
			if not others.has(s):
				others[s] = []
			if not int(b["player"]) in others[s]:
				others[s].append(int(b["player"]))
	for i: int in symbol_buttons.size():
		var b: Button = symbol_buttons[i]
		b.disabled = not open_bets
		_badges[i].visible = mine.has(i)
		if mine.has(i):
			_badges[i].text = "$%d" % int(mine[i])
		_dots[i].visible = others.has(i)
		if others.has(i):
			_dots[i].text = "●".repeat(mini((others[i] as Array).size(), 4))
			_dots[i].add_theme_color_override(&"font_color", Palette.player_color(int(state.players.get(int(others[i][0]), {}).get("color", 0))) if state != null else Palette.CREAM)
	if not mine.is_empty():
		var parts: PackedStringArray = []
		var total: int = 0
		for i: int in WheelLogic.SYMBOLS.size():
			if mine.has(i):
				parts.append("%s $%d" % [WheelLogic.LABELS[i], int(mine[i])])
				total += int(mine[i])
		my_bets.text = "YOUR BETS $%d: %s" % [total, ", ".join(parts)]
	elif st == WheelLogic.State.BETTING:
		my_bets.text = "No bet yet: pick a chip, click a symbol"
	else:
		my_bets.text = ""


## The line under the status: the result once the wheel shows it, else the last spins.
static func result_text(p: Dictionary) -> String:
	var seg: int = int(p.get("segment", -1))
	if int(p.get("state", 0)) == WheelLogic.State.RESULT and seg >= 0:
		var s: int = WheelLogic.symbol_at(seg)
		return "THE WHEEL SAYS %s  ·  PAYS %s" % [WheelLogic.LABELS[s], WheelLogic.odds_text(s)]
	var h: Array = p.get("history", [])
	if h.is_empty():
		return ""
	var parts: PackedStringArray = []
	for s: Variant in h.slice(0, 8):
		parts.append(WheelLogic.LABELS[clampi(int(s), 0, WheelLogic.LABELS.size() - 1)])
	return "Last spins: " + "  ".join(parts)


func _symbol_button(i: int) -> Button:
	var b := Button.new()
	b.name = "Symbol%d" % i
	b.custom_minimum_size = SYMBOL_SIZE
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override(&"font_size", 21)
	b.text = "%s\n%s" % [WheelLogic.LABELS[i], WheelLogic.odds_text(i)]
	b.tooltip_text = "%s: %d of the 54 segments, pays %s" % [WheelLogic.LABELS[i], WheelLogic.COUNTS[i], WheelLogic.odds_text(i)]
	var text_color: Color = WheelStation.TEXT_COLORS[i]
	for state_name: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color"]:
		b.add_theme_color_override(state_name, text_color)
	var sb := StyleBoxFlat.new()
	sb.bg_color = WheelStation.SYMBOL_COLORS[i]
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(2)
	sb.border_color = Palette.WARM_GOLD
	b.add_theme_stylebox_override(&"normal", sb)
	var hover: StyleBoxFlat = sb.duplicate()
	hover.border_color = Palette.VIP_GOLD
	hover.set_border_width_all(3)
	b.add_theme_stylebox_override(&"hover", hover)
	b.add_theme_stylebox_override(&"pressed", hover)
	var off: StyleBoxFlat = sb.duplicate()
	off.bg_color = WheelStation.SYMBOL_COLORS[i].darkened(0.5)
	off.border_color = Palette.WARM_CHARCOAL
	b.add_theme_stylebox_override(&"disabled", off)
	b.add_theme_color_override(&"font_disabled_color", text_color.darkened(0.4))
	b.pressed.connect(func() -> void: bet_on(i))
	symbol_buttons.append(b)
	var badge := Label.new()
	badge.add_theme_color_override(&"font_color", Palette.CASINO_BLACK)
	var chip := StyleBoxFlat.new()
	chip.bg_color = Palette.VIP_GOLD
	chip.set_corner_radius_all(9)
	chip.border_color = Palette.CREAM
	chip.set_border_width_all(2)
	chip.content_margin_left = 4
	chip.content_margin_right = 4
	badge.add_theme_stylebox_override(&"normal", chip)
	badge.add_theme_font_size_override(&"font_size", 12)
	badge.anchor_left = 1.0
	badge.anchor_right = 1.0
	badge.offset_left = -46
	badge.offset_right = -3
	badge.offset_top = 3
	badge.offset_bottom = 21
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.visible = false
	b.add_child(badge)
	_badges.append(badge)
	var dots := Label.new()
	dots.add_theme_font_size_override(&"font_size", 11)
	dots.position = Vector2(5, 1)
	dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dots.visible = false
	b.add_child(dots)
	_dots.append(dots)
	return b
