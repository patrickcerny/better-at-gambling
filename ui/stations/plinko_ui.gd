class_name PlinkoUi
extends StationUi
## Plinko overlay: a slim panel docked at the right edge so the whole board stays in view. Risk
## row, bet stepper, DROP and the last few drops. The payouts themselves are written on the
## board's buckets (and switch with the risk picked here).
## Keys: 1–4 / [ ] bet size, Space / Enter drop.

const PANEL_W: float = 300.0
const HISTORY: int = 4

var risk: StringName = &"medium"
var risk_buttons: Dictionary[StringName, Button] = {}
var sizes: Array[int] = []
var bet_index: int = 0
var amount_label: Label
var minus_btn: Button
var plus_btn: Button
var drop_btn: Button
var history_box: VBoxContainer
## Newest first: {mult, net}.
var history: Array[Dictionary] = []
var _cooldown: float = 0.0
var _history_station: StringName = &""


func _init() -> void:
	game_title = "PLINKO"


func _panel_height() -> float:
	return 360.0


func _dock_right() -> bool:
	return true


## Locked while the cursor is over the panel (picking risk and bet); free while you watch the drop.
func wants_camera_lock() -> bool:
	return is_visible_in_tree() and panel.get_global_rect().has_point(panel.get_global_mouse_position())


func _build() -> void:
	panel.offset_left = panel.offset_right - PANEL_W
	body.add_theme_constant_override(&"separation", 8)
	status_label.add_theme_font_size_override(&"font_size", 20)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_caption("RISK"))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 6)
	body.add_child(row)
	for r: StringName in PlinkoLogic.RISKS:
		var b := Button.new()
		b.text = String(r).to_upper()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(84, 38)
		b.add_theme_font_size_override(&"font_size", 18)
		var rr: StringName = r
		b.pressed.connect(func() -> void: _set_risk(rr))
		row.add_child(b)
		risk_buttons[r] = b
	body.add_child(_caption("BET"))
	var bet := HBoxContainer.new()
	bet.alignment = BoxContainer.ALIGNMENT_CENTER
	bet.add_theme_constant_override(&"separation", 8)
	body.add_child(bet)
	minus_btn = _small_button("−", func() -> void: _select(bet_index - 1))
	bet.add_child(minus_btn)
	amount_label = Label.new()
	amount_label.theme_type_variation = &"MoneyLabel"
	amount_label.custom_minimum_size = Vector2(120, 0)
	amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bet.add_child(amount_label)
	plus_btn = _small_button("+", func() -> void: _select(bet_index + 1))
	bet.add_child(plus_btn)
	drop_btn = Button.new()
	drop_btn.name = "Drop"
	drop_btn.custom_minimum_size = Vector2(PANEL_W - 48, 54)
	drop_btn.focus_mode = Control.FOCUS_NONE
	drop_btn.pressed.connect(drop)
	body.add_child(drop_btn)
	history_box = VBoxContainer.new()
	history_box.add_theme_constant_override(&"separation", 0)
	body.add_child(history_box)
	_set_risk(&"medium")
	if not Net.event_received.is_connected(_on_event):
		Net.event_received.connect(_on_event)


func _exit_tree() -> void:
	if Net.event_received.is_connected(_on_event):
		Net.event_received.disconnect(_on_event)


func _on_open() -> void:
	if station_id != _history_station:  # another board: its own history
		history.clear()
		_history_station = station_id
	sizes.clear()
	for s: int in Registry.balance.plinko_bet_sizes:
		sizes.append(scaled(s))
	bet_index = clampi(bet_index, 0, sizes.size() - 1)
	_select(bet_index)
	_set_risk(risk)
	_render_history()


## Drops a chip at the chosen bet and risk.
func drop() -> void:
	if _cooldown > 0.0 or sizes.is_empty():
		return
	if send(&"place_bet", {"bet": {"amount": sizes[bet_index], "risk": risk}}):
		_cooldown = Registry.balance.plinko_drop_cooldown
		Audio.play(&"chip_clack", &"UI", -8.0)
		_update_drop()


func _relabel() -> void:
	_update_drop()


func _hint_text() -> String:
	var bet_keys: String = InputGlyphs.hint(&"bet_chip_next") if InputGlyphs.gamepad else "[1–4]"
	return "%s Bet  %s Drop  %s Stand up" % [bet_keys, InputGlyphs.hint(&"bet_confirm"), InputGlyphs.hint(&"leave_station")]


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventKey and (event as InputEventKey).shift_pressed:
		return  # Shift+1–3 uses items while seated
	var handled: bool = true
	if event.is_action_pressed(&"bet_confirm"):
		drop()
	elif event.is_action_pressed(&"bet_chip_1"):
		_select(0)
	elif event.is_action_pressed(&"bet_chip_2"):
		_select(1)
	elif event.is_action_pressed(&"bet_chip_3"):
		_select(2)
	elif event.is_action_pressed(&"bet_chip_4"):
		_select(3)
	elif event.is_action_pressed(&"bet_chip_prev"):
		_select(bet_index - 1)
	elif event.is_action_pressed(&"bet_chip_next"):
		_select(bet_index + 1)
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown = maxf(_cooldown - delta, 0.0)
		if visible:
			_update_drop()


func _select(i: int) -> void:
	if sizes.is_empty():
		return
	bet_index = clampi(i, 0, sizes.size() - 1)
	amount_label.text = money(sizes[bet_index])
	minus_btn.disabled = bet_index == 0
	plus_btn.disabled = bet_index == sizes.size() - 1


func _set_risk(r: StringName) -> void:
	risk = r
	for k: StringName in risk_buttons:
		risk_buttons[k].button_pressed = k == r
	var board: PlinkoStation = _board()
	if board != null:
		board.set_risk(r)


func _board() -> PlinkoStation:
	if not is_inside_tree():
		return null
	for n: Node in get_tree().get_nodes_in_group(&"stations"):
		if n is PlinkoStation and (n as PlinkoStation).station_id == station_id:
			return n
	return null


func _update_drop() -> void:
	if drop_btn == null:
		return
	drop_btn.disabled = _cooldown > 0.0
	drop_btn.text = ("DROP  %s" % InputGlyphs.hint(&"bet_confirm")) if _cooldown <= 0.0 else ("NEXT IN %.1fs" % _cooldown)


func _on_event(ev: Dictionary) -> void:
	var t: StringName = StringName(ev.get("type", &""))
	if t != &"plinko_dropped" and t != &"round_result":
		return
	var who: Variant = ev.get("player", -1)
	if StringName(ev.get("station", &"")) != station_id or not (who is int or who is float) or int(who) != local_id:
		return
	if t == &"plinko_dropped" and visible:
		_set_risk(StringName(ev.get("risk", risk)))  # the plates always show the row you are playing
		return
	var details: Dictionary = ev.get("details", {})
	if not details.has("slot"):
		return
	var mults: PackedFloat32Array = Registry.balance.plinko_multipliers(StringName(details.get("risk", risk)))
	var slot: int = clampi(int(details["slot"]), 0, mults.size() - 1)
	history.push_front({"mult": mults[slot], "net": int(ev.get("net", 0))})
	history.resize(mini(history.size(), HISTORY))
	_render_history()


func _render_history() -> void:
	if history_box == null:
		return
	for c: Node in history_box.get_children():
		c.queue_free()
	if history.is_empty():
		return
	history_box.add_child(_caption("LAST DROPS"))
	for h: Dictionary in history:
		var l := Label.new()
		var net: int = int(h["net"])
		l.text = "%s   %s%s" % [PlinkoStation.mult_text(float(h["mult"])), "+" if net >= 0 else "−", money(absi(net))]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override(&"font_size", 18)
		l.add_theme_color_override(&"font_color", Palette.MONEY_GREEN if net > 0 else (Palette.CREAM if net == 0 else Palette.LOSS_RED))
		history_box.add_child(l)


func _refresh() -> void:
	var flying: int = 0
	for d: Dictionary in pub.get("drops", []):
		if int(d["player"]) == local_id:
			flying += 1
	status_label.text = ("Chip in flight…" if flying == 1 else "%d chips in flight…" % flying) if flying > 0 else "Pick a risk and drop a chip"
	_update_drop()


func _caption(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"SmallLabel"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override(&"font_color", Palette.WARM_GOLD)
	return l


func _small_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(46, 42)
	b.pressed.connect(cb)
	return b
