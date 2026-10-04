class_name RouletteUi
extends StationUi
## Roulette overlay: pick a chip, click a spot on the layout to place it. Shows the betting
## timer, your bets, the result. Straight numbers 0–36, red/black, odd/even, low/high,
## dozens and columns (§2.5.2).

var bet_panel: BetPanel
var grid: GridContainer
var outside: HBoxContainer
var my_bets: Label
var result_label: Label
var _buttons: Array[Button] = []


func _init() -> void:
	game_title = "ROULETTE"


func _panel_height() -> float:
	return 560.0


func _build() -> void:
	result_label = Label.new()
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.add_theme_font_size_override(&"font_size", 40)
	body.add_child(result_label)
	grid = GridContainer.new()
	grid.columns = 13
	grid.add_theme_constant_override(&"h_separation", 4)
	grid.add_theme_constant_override(&"v_separation", 4)
	var centre := CenterContainer.new()
	centre.add_child(grid)
	body.add_child(centre)
	# Standard 3-row layout: row 0 = 3,6,9… row 1 = 2,5,8… row 2 = 1,4,7…; zero spans the left.
	for row: int in 3:
		var zero: Button = _spot("0" if row == 1 else "", &"straight", 0, Palette.FELT_GREEN)
		zero.disabled = row != 1
		for col: int in 12:
			var n: int = col * 3 + (3 - row)
			_spot(str(n), &"straight", n, Palette.CASINO_RED if n in RouletteLogic.RED else Palette.CASINO_BLACK)
	outside = HBoxContainer.new()
	outside.alignment = BoxContainer.ALIGNMENT_CENTER
	outside.add_theme_constant_override(&"separation", 4)
	body.add_child(outside)
	for spec: Array in [["1-12", &"dozen", 1], ["13-24", &"dozen", 2], ["25-36", &"dozen", 3], ["1st COL", &"column", 1], ["2nd COL", &"column", 2], ["3rd COL", &"column", 3]]:
		_spot(spec[0], spec[1], int(spec[2]), Palette.WARM_CHARCOAL, outside, Vector2(92, 40))
	var outside2 := HBoxContainer.new()
	outside2.alignment = BoxContainer.ALIGNMENT_CENTER
	outside2.add_theme_constant_override(&"separation", 4)
	body.add_child(outside2)
	for spec: Array in [["LOW 1-18", &"low", 0, Palette.WARM_CHARCOAL], ["EVEN", &"even", 0, Palette.WARM_CHARCOAL], ["RED", &"red", 0, Palette.CASINO_RED], ["BLACK", &"black", 0, Palette.CASINO_BLACK], ["ODD", &"odd", 0, Palette.WARM_CHARCOAL], ["HIGH 19-36", &"high", 0, Palette.WARM_CHARCOAL]]:
		_spot(spec[0], spec[1], int(spec[2]), spec[3], outside2, Vector2(110, 40))
	my_bets = Label.new()
	my_bets.theme_type_variation = &"SmallLabel"
	my_bets.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	my_bets.autowrap_mode = TextServer.AUTOWRAP_WORD
	body.add_child(my_bets)
	bet_panel = BetPanel.new()
	bet_panel.cleared.connect(func() -> void: send(&"clear_bets"))
	body.add_child(bet_panel)


func _on_open() -> void:
	var lo: int = scaled(Registry.balance.roulette_min_bet)
	var hi: int = scaled(Registry.balance.roulette_max_total)
	bet_panel.setup([lo, lo * 2 + lo / 2, lo * 5, lo * 10], lo, hi, "")
	bet_panel.configure_visibility(false, false, true, false)


func _refresh() -> void:
	var st: int = int(pub.get("state", 0))
	var timer: float = float(pub.get("timer", 0.0))
	var result: int = int(pub.get("result", -1))
	var open_bets: bool = st == RouletteLogic.State.BETTING
	match st:
		RouletteLogic.State.IDLE:
			status_label.text = "Waiting for players…"
		RouletteLogic.State.BETTING:
			status_label.text = "PLACE YOUR BETS  %d s" % int(ceil(timer))
		RouletteLogic.State.SPINNING:
			status_label.text = "No more bets — spinning…"
		RouletteLogic.State.RESULT:
			status_label.text = "Next spin in %d s" % int(ceil(timer))
	if st == RouletteLogic.State.RESULT and result >= 0:
		var colour: String = "GREEN" if result == 0 else ("RED" if result in RouletteLogic.RED else "BLACK")
		result_label.text = "%d  %s" % [result, colour]
		result_label.add_theme_color_override(&"font_color", Palette.FELT_GREEN.lightened(0.4) if result == 0 else (Palette.CASINO_RED if result in RouletteLogic.RED else Palette.CREAM))
	elif st == RouletteLogic.State.SPINNING:
		result_label.text = "…"
	else:
		result_label.text = ""
	for b: Button in _buttons:
		b.disabled = not open_bets or (b.text == "" and b.get_meta(&"type") == &"straight")
	var mine: Array[String] = []
	var total: int = 0
	for b: Dictionary in pub.get("bets", []):
		if int(b["player"]) != local_id:
			continue
		total += int(b["amount"])
		var t: StringName = StringName(b["type"])
		var label: String = String(t).to_upper()
		if t == &"straight":
			label = str(int(b["value"]))
		elif t == &"dozen" or t == &"column":
			label = "%s %d" % [label, int(b["value"])]
		mine.append("%s $%d" % [label, int(b["amount"])])
	my_bets.text = ("YOUR BETS ($%d): " % total) + ", ".join(mine) if not mine.is_empty() else "No bets yet — pick a chip, click a spot"


func _spot(text: String, type: StringName, value: int, color: Color, parent: Control = null, size: Vector2 = Vector2(46, 40)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = size
	b.add_theme_font_size_override(&"font_size", 18)
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(4)
	sb.set_border_width_all(1)
	sb.border_color = Palette.WARM_GOLD
	b.add_theme_stylebox_override(&"normal", sb)
	var hover: StyleBoxFlat = sb.duplicate()
	hover.border_color = Palette.VIP_GOLD
	hover.set_border_width_all(2)
	b.add_theme_stylebox_override(&"hover", hover)
	b.add_theme_stylebox_override(&"focus", hover)
	b.set_meta(&"type", type)
	b.pressed.connect(func() -> void: send(&"place_bet", {"bet": {"type": type, "value": value, "amount": bet_panel.chip_value()}}))
	(parent if parent != null else grid).add_child(b)
	_buttons.append(b)
	return b
