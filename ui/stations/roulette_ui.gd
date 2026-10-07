class_name RouletteUi
extends StationUi
## Roulette overlay: pick a chip, click a spot on the layout to place it. Shows the betting
## timer, your bets, the result. Straight numbers 0–36, red/black, odd/even, low/high,
## dozens and columns (§2.5.2). Docked at the right edge and laid out like the real felt
## (zero on top, 12 rows of three numbers, the outside bets in two narrow columns beside them),
## so the wheel and the table stay visible while you bet.

const PANEL_W: float = 340.0
## Number spot size; outside columns are as tall as the rows they cover.
const SPOT: Vector2 = Vector2(44, 26)
const GAP: int = 3
const DOZEN_W: float = 50.0
const EVEN_W: float = 62.0

var bet_panel: BetPanel
var grid: GridContainer
## The two narrow outside-bet columns: dozens, then the even-money bets.
var outside: HBoxContainer
var my_bets: Label
var result_label: Label
var _buttons: Array[Button] = []
## Chip badges on the layout: "type:value" → the badge showing your amount there, and the line
## of coloured dots for other players' chips on that spot.
var _badges: Dictionary[String, Label] = {}
var _dots: Dictionary[String, Label] = {}


func _init() -> void:
	game_title = "ROULETTE"


func _panel_height() -> float:
	return 640.0


func _dock_right() -> bool:
	return true


## Locked while bets are open.
func wants_camera_lock() -> bool:
	return int(pub.get("state", 0)) == RouletteLogic.State.BETTING


func _build() -> void:
	panel.offset_left = panel.offset_right - PANEL_W
	body.add_theme_constant_override(&"separation", 6)
	status_label.add_theme_font_size_override(&"font_size", 20)
	result_label = Label.new()
	result_label.name = "Result"
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.add_theme_font_size_override(&"font_size", 22)
	body.add_child(result_label)
	var felt := HBoxContainer.new()
	felt.name = "Felt"
	felt.alignment = BoxContainer.ALIGNMENT_CENTER
	felt.add_theme_constant_override(&"separation", GAP)
	body.add_child(felt)
	outside = HBoxContainer.new()
	outside.name = "Outside"
	outside.add_theme_constant_override(&"separation", GAP)
	felt.add_child(outside)
	var even_col: VBoxContainer = _outside_column()
	for spec: Array in [["1-18", &"low", Palette.WARM_CHARCOAL], ["EVEN", &"even", Palette.WARM_CHARCOAL], ["RED", &"red", Palette.CASINO_RED], ["BLACK", &"black", Palette.CASINO_BLACK], ["ODD", &"odd", Palette.WARM_CHARCOAL], ["19-36", &"high", Palette.WARM_CHARCOAL]]:
		_spot(spec[0], spec[1], 0, spec[2], even_col, Vector2(EVEN_W, _rows_h(2)))
	var dozen_col: VBoxContainer = _outside_column()
	for d: int in [1, 2, 3]:
		_spot(["1st 12", "2nd 12", "3rd 12"][d - 1], &"dozen", d, Palette.WARM_CHARCOAL, dozen_col, Vector2(DOZEN_W, _rows_h(4)))
	outside.add_child(even_col)
	outside.add_child(dozen_col)
	var numbers := VBoxContainer.new()
	numbers.name = "Numbers"
	numbers.add_theme_constant_override(&"separation", GAP)
	felt.add_child(numbers)
	_spot("0", &"straight", 0, Palette.FELT_GREEN, numbers, Vector2(SPOT.x * 3 + GAP * 2, SPOT.y))
	grid = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override(&"h_separation", GAP)
	grid.add_theme_constant_override(&"v_separation", GAP)
	numbers.add_child(grid)
	# Rows run 1-2-3, 4-5-6 … 34-35-36 away from the zero, like the felt seen from the chair.
	for row: int in 12:
		for col: int in 3:
			var n: int = row * 3 + col + 1
			_spot(str(n), &"straight", n, Palette.CASINO_RED if n in RouletteLogic.RED else Palette.CASINO_BLACK)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override(&"separation", GAP)
	numbers.add_child(cols)
	for c: int in [1, 2, 3]:
		_spot("2:1", &"column", c, Palette.WARM_CHARCOAL, cols, SPOT)
	var bets_row := HBoxContainer.new()
	bets_row.name = "BetsRow"
	bets_row.add_theme_constant_override(&"separation", 6)
	body.add_child(bets_row)
	my_bets = Label.new()
	my_bets.name = "MyBets"
	my_bets.theme_type_variation = &"SmallLabel"
	my_bets.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	my_bets.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	my_bets.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	my_bets.custom_minimum_size = Vector2(80, 0)
	my_bets.add_theme_font_size_override(&"font_size", 14)
	bets_row.add_child(my_bets)
	bet_panel = BetPanel.new()
	bet_panel.chip_size = Vector2(50, 40)
	bet_panel.chip_gap = 4
	bet_panel.add_theme_stylebox_override(&"panel", StyleBoxEmpty.new())
	bet_panel.cleared.connect(func() -> void: send(&"clear_bets"))
	bets_row.add_child(bet_panel)


## Height of `n` number rows including the gaps between them.
static func _rows_h(n: int) -> float:
	return SPOT.y * n + GAP * (n - 1)


## A narrow outside column: starts below the zero and ends above the column bets.
func _outside_column() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", GAP)
	var top := Control.new()
	top.custom_minimum_size = Vector2(0, SPOT.y)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(top)
	return v


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
		b.disabled = not open_bets
	var on_spot: Dictionary = {}
	var others_on: Dictionary = {}
	for b: Dictionary in pub.get("bets", []):
		var key: String = _key(StringName(b["type"]), int(b["value"]))
		if int(b["player"]) == local_id:
			on_spot[key] = int(on_spot.get(key, 0)) + int(b["amount"])
		else:
			if not others_on.has(key):
				others_on[key] = []
			if not int(b["player"]) in others_on[key]:
				others_on[key].append(int(b["player"]))
	for key: String in _badges:
		var badge: Label = _badges[key]
		badge.visible = on_spot.has(key)
		if badge.visible:
			badge.text = "$%d" % int(on_spot[key])
		var dots: Label = _dots[key]
		dots.visible = others_on.has(key)
		if dots.visible:
			dots.text = "●".repeat(mini((others_on[key] as Array).size(), 4))
			dots.add_theme_color_override(&"font_color", Palette.player_color(int(state.players.get(int(others_on[key][0]), {}).get("color", 0))) if state != null else Palette.CREAM)
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
	if mine.size() > 4:
		mine = mine.slice(0, 4) + ["+%d more" % (mine.size() - 4)]
	my_bets.text = ("YOUR BETS $%d\n" % total) + ", ".join(mine) if not mine.is_empty() else "No bets yet: pick a chip, click a spot"


func _spot(text: String, type: StringName, value: int, color: Color, parent: Control = null, size: Vector2 = SPOT) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override(&"font_size", 15 if type == &"straight" else 13)
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
	if text != "":
		var key: String = _key(type, value)
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
		# Sits on the spot's own bottom edge, centred. (It used to be anchored top-right with a
		# position computed before layout, which pushed it onto the neighbouring number.)
		badge.add_theme_font_size_override(&"font_size", 11)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.anchor_left = 0.5
		badge.anchor_right = 0.5
		badge.anchor_top = 1.0
		badge.anchor_bottom = 1.0
		badge.offset_left = -17
		badge.offset_right = 17
		badge.offset_top = -9
		badge.offset_bottom = 6
		badge.grow_horizontal = Control.GROW_DIRECTION_BOTH
		badge.clip_text = false
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.visible = false
		badge.z_index = 2
		b.add_child(badge)
		_badges[key] = badge
		var dots := Label.new()
		dots.add_theme_font_size_override(&"font_size", 9)
		dots.position = Vector2(2, -4)
		dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dots.visible = false
		b.add_child(dots)
		_dots[key] = dots
	return b


static func _key(type: StringName, value: int) -> String:
	return "%s:%d" % [type, value]
