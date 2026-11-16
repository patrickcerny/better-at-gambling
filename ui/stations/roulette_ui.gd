class_name RouletteUi
extends StationUi
## Roulette overlay, docked at the right edge so the wheel and the table stay visible: the last
## numbers, the drawn betting layout (`RouletteBoard`: every bet of a real table, from a single
## number to splits, streets, corners, six lines, dozens, columns and the even-money bets), what
## the spot under the mouse covers and pays, your bets this spin, the chips and CLEAR / REBET.
## Pick a chip, click a spot; each click puts one chip there.

const PANEL_W: float = 376.0
## How many past numbers the strip shows.
const HISTORY: int = 10

var bet_panel: BetPanel
var board: RouletteBoard
var my_bets: Label
var result_label: Label
## What the spot under the mouse is ("SPLIT 17-20 · pays 17:1").
var spot_info: Label
## The last numbers (newest first), as coloured discs.
var history_row: HBoxContainer
var rebet_btn: Button
var history: Array[int] = []
## Your bets of the last spin that went down ({type, value, amount}), for REBET.
var last_round: Array[Dictionary] = []
var _prev_state: int = -1
var _round_bets: Array[Dictionary] = []


func _init() -> void:
	game_title = "ROULETTE"


func _panel_height() -> float:
	return 760.0


func _dock_right() -> bool:
	return true


## Locked while bets are open.
func wants_camera_lock() -> bool:
	return int(pub.get("state", 0)) == RouletteLogic.State.BETTING


func _build() -> void:
	panel.offset_left = panel.offset_right - PANEL_W
	body.add_theme_constant_override(&"separation", 7)
	status_label.add_theme_font_size_override(&"font_size", 22)
	history_row = HBoxContainer.new()
	history_row.name = "History"
	history_row.alignment = BoxContainer.ALIGNMENT_CENTER
	history_row.add_theme_constant_override(&"separation", 4)
	history_row.custom_minimum_size = Vector2(0, 30)
	history_row.visible = false
	body.add_child(history_row)
	result_label = TableSkin.label("", 24, Palette.CREAM, true)
	result_label.name = "Result"
	result_label.visible = false
	body.add_child(result_label)
	board = RouletteBoard.new()
	board.name = "Board"
	board.local_id = local_id
	board.spot_clicked.connect(_on_spot)
	board.hover_changed.connect(_on_hover)
	body.add_child(board)
	spot_info = TableSkin.label("", 16, Palette.WARM_GOLD, true)
	spot_info.name = "SpotInfo"
	body.add_child(spot_info)
	my_bets = TableSkin.label("", 15, Palette.CREAM)
	my_bets.name = "MyBets"
	my_bets.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	my_bets.custom_minimum_size = Vector2(120, 0)
	body.add_child(my_bets)
	bet_panel = BetPanel.new()
	bet_panel.chip_size = Vector2(56, 56)
	bet_panel.chip_gap = 6
	bet_panel.add_theme_stylebox_override(&"panel", StyleBoxEmpty.new())
	bet_panel.cleared.connect(func() -> void: send(&"clear_bets"))
	bet_panel.repeated.connect(func() -> void:  # R / Y puts last spin's bets down again
		if rebet_btn.visible:
			rebet())
	body.add_child(bet_panel)
	rebet_btn = Button.new()
	rebet_btn.name = "Rebet"
	rebet_btn.text = "REBET"
	rebet_btn.tooltip_text = "Put down your bets of the last spin again"
	rebet_btn.focus_mode = Control.FOCUS_NONE
	rebet_btn.custom_minimum_size = Vector2(0, 40)
	TableSkin.style_button(rebet_btn, &"felt", 20)
	rebet_btn.pressed.connect(rebet)
	body.add_child(rebet_btn)
	_on_hover(&"", 0)


func _on_open() -> void:
	board.local_id = local_id
	board.color_of = func(pid: int) -> Color:
		return PlayerColors.of_player(state.players, pid) if state != null else Palette.CREAM
	var lo: int = scaled(Registry.balance.roulette_min_bet)
	var hi: int = scaled(Registry.balance.roulette_max_total)
	bet_panel.setup([lo, lo * 2 + lo / 2, lo * 5, lo * 10], lo, hi, "")
	bet_panel.configure_visibility(false, false, true, false)


## Gamepad: the left stick moves a pointer over the layout (any bet the mouse can reach), A puts
## the chip down where it points.
func _process(delta: float) -> void:
	super(delta)
	if not visible or board == null:
		return
	if not InputGlyphs.gamepad or not board.open:
		board.pad_hide()
		return
	var stick: Vector2 = left_stick()
	if stick.length() < 0.2:
		stick = Vector2.ZERO
	board.pad_nudge(stick * stick.length(), delta)  # squared: fine moves near the middle


func _input(event: InputEvent) -> void:
	super(event)
	if visible and event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed and (event as InputEventJoypadButton).button_index == JOY_BUTTON_A and InputGlyphs.gamepad:
		board.pad_click()
		get_viewport().set_input_as_handled()  # A is the pointer's click here, never "confirm"


func _hint_text() -> String:
	if InputGlyphs.gamepad:
		return InputGlyphs.fill("Left stick: point at a bet  [%s] put a chip there\n[{bet_chip_prev} / {bet_chip_next}] chip  [{bet_clear}] clear  [{bet_repeat}] rebet  [{leave_station}] stand up" % InputGlyphs.pad_name("A"))
	return super()


func _on_spot(type: StringName, value: int) -> void:
	if send(&"place_bet", {"bet": {"type": type, "value": value, "amount": bet_panel.chip_stake(bet_room())}}):
		Audio.play(&"chip_clack", &"UI", -10.0, randf_range(0.95, 1.1))


func _on_hover(type: StringName, value: int) -> void:
	if type == &"":
		spot_info.text = ("Point at a number, a line or a corner" if InputGlyphs.gamepad else "Click a number, a line or a corner") if board.open else ""
		return
	spot_info.text = "%s  ·  pays %d : 1" % [RouletteLogic.bet_name(type, value), int(RouletteLogic.RATIOS.get(type, 0))]


## Puts last spin's bets down again (each as its own chip; stops at the first refusal).
func rebet() -> void:
	for b: Dictionary in last_round:
		if not send(&"place_bet", {"bet": {"type": b["type"], "value": b["value"], "amount": b["amount"]}}):
			break


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
	# Remember your bets as the wheel starts, and the number once it lands.
	if st != _prev_state:
		if _prev_state == RouletteLogic.State.BETTING and st == RouletteLogic.State.SPINNING and not _round_bets.is_empty():
			last_round = _round_bets.duplicate(true)
		if st == RouletteLogic.State.RESULT and result >= 0:
			history.push_front(result)
			if history.size() > HISTORY:
				history.resize(HISTORY)
			_refresh_history()
		_prev_state = st
	if st == RouletteLogic.State.RESULT and result >= 0:
		var colour: String = "GREEN" if result == 0 else ("RED" if result in RouletteLogic.RED else "BLACK")
		result_label.text = "%d  %s" % [result, colour]
		result_label.add_theme_color_override(&"font_color", Palette.FELT_GREEN.lightened(0.4) if result == 0 else (Palette.CASINO_RED.lightened(0.15) if result in RouletteLogic.RED else Palette.CREAM))
	elif st == RouletteLogic.State.SPINNING:
		result_label.text = "…"
	else:
		result_label.text = ""
	result_label.visible = result_label.text != ""
	board.open = open_bets
	board.winning = result if st == RouletteLogic.State.RESULT else -1
	board.bets = pub.get("bets", [])
	board.queue_redraw()
	if not open_bets:
		_on_hover(&"", 0)
	var mine: Array[String] = []
	var total: int = 0
	_round_bets.clear()
	for b: Dictionary in pub.get("bets", []):
		if int(b["player"]) != local_id:
			continue
		total += int(b["amount"])
		_round_bets.append({"type": StringName(b["type"]), "value": int(b["value"]), "amount": int(b["amount"])})
		mine.append("%s $%d" % [RouletteLogic.bet_name(StringName(b["type"]), int(b["value"])), int(b["amount"])])
	if mine.size() > 4:
		mine = mine.slice(0, 4) + ["+%d more" % (mine.size() - 4)]
	my_bets.text = ("YOUR BETS $%d:  " % total) + ", ".join(mine) if not mine.is_empty() else "No bets yet: pick a chip, click the layout"
	rebet_btn.visible = open_bets and _round_bets.is_empty() and not last_round.is_empty()
	if rebet_btn.visible:
		var sum: int = 0
		for b: Dictionary in last_round:
			sum += int(b["amount"])
		rebet_btn.text = "REBET  $%d  %s" % [sum, InputGlyphs.hint(&"bet_repeat")]


## The strip of past numbers: newest first and biggest, in their pocket colours.
func _refresh_history() -> void:
	history_row.visible = not history.is_empty()
	for c: Node in history_row.get_children():
		history_row.remove_child(c)
		c.queue_free()
	for i: int in history.size():
		var n: int = history[i]
		var l := Label.new()
		l.text = str(n)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var side: float = 30.0 if i == 0 else 24.0
		l.custom_minimum_size = Vector2(side, side)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		l.add_theme_font_override(&"font", TableSkin.black_font())
		l.add_theme_font_size_override(&"font_size", 17 if i == 0 else 14)
		l.add_theme_color_override(&"font_color", Palette.CREAM)
		var sb := StyleBoxFlat.new()
		sb.bg_color = RouletteBoard.FELT.lightened(0.1) if n == 0 else (RouletteBoard.RED_TILE if n in RouletteLogic.RED else RouletteBoard.BLACK_TILE)
		sb.set_corner_radius_all(int(side))
		sb.border_color = Palette.VIP_GOLD if i == 0 else Color(Palette.CREAM, 0.5)
		sb.set_border_width_all(2 if i == 0 else 1)
		sb.anti_aliasing = true
		l.add_theme_stylebox_override(&"normal", sb)
		l.modulate.a = 1.0 - i * 0.06
		history_row.add_child(l)
		if i == 0:
			TableSkin.pop.call_deferred(l, 0.3)
