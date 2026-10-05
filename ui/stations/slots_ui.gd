class_name SlotsUi
extends StationUi
## Slot machine overlay: three reels, pick a bet size to pull the lever, STOP to skip the spin.

const SYMBOL_GLYPHS: Dictionary = {
	&"cherry": "🍒", &"lemon": "🍋", &"bell": "🔔", &"bar": "BAR", &"seven": "7", &"clover": "☘", &"diamond": "◆",
}

var reels: Array[Label] = []
var bet_panel: BetPanel
var stop_btn: Button
var pay_label: Label
var _spin_anim: float = 0.0
var _last_line: Array = []
## Reels stop one after another on a new result: seconds left per reel (< 0 = stopped).
const STOP_STAGGER: float = 0.35
var _stop_in: Array[float] = [-1.0, -1.0, -1.0]
var _result_pending: bool = false
var _saw_spin: bool = false


func _init() -> void:
	game_title = "SLOTS"


func _panel_height() -> float:
	return 420.0


func _build() -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 18)
	body.add_child(row)
	for i: int in 3:
		var p := PanelContainer.new()
		p.custom_minimum_size = Vector2(120, 120)
		var l := Label.new()
		l.text = "?"
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override(&"font_size", 64)
		l.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
		p.add_child(l)
		row.add_child(p)
		reels.append(l)
	pay_label = Label.new()
	pay_label.theme_type_variation = &"SmallLabel"
	pay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pay_label.text = "3× 🍒 6  🍋 8  🔔 12  BAR 20  7 40  ☘ WILD  ◆◆◆ JACKPOT   •  2× 🍒 2  1× 🍒 1"
	body.add_child(pay_label)
	stop_btn = Button.new()
	stop_btn.text = "STOP  [Enter]"
	stop_btn.custom_minimum_size = Vector2(200, 52)
	stop_btn.pressed.connect(func() -> void: send(&"action", {"action": &"stop"}))
	var c := CenterContainer.new()
	c.add_child(stop_btn)
	body.add_child(c)
	bet_panel = BetPanel.new()
	bet_panel.confirmed.connect(func(a: int) -> void: send(&"place_bet", {"bet": {"amount": a}}))
	body.add_child(bet_panel)


func _on_open() -> void:
	var sizes: Array[int] = []
	for s: int in Registry.balance.slots_bet_sizes:
		sizes.append(scaled(s))
	bet_panel.setup(sizes, sizes[0], sizes[sizes.size() - 1], "PULL", true)


func _unhandled_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed(&"bet_confirm") and stop_btn.visible:
		stop_btn.pressed.emit()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return
	var spinning: bool = bool(pub.get("spinning", false))
	_spin_anim += delta * 18.0
	for i: int in 3:
		if _stop_in[i] >= 0.0:
			_stop_in[i] -= delta
			if _stop_in[i] < 0.0:
				_land_reel(i)
				continue
		if spinning or _stop_in[i] >= 0.0:
			reels[i].text = SYMBOL_GLYPHS[SlotsLogic.SYMBOL_NAMES[(int(_spin_anim) + i * 2) % SlotsLogic.SYMBOL_NAMES.size()]]
	if _result_pending and _stop_in[2] < 0.0:
		_result_pending = false
		_show_result()


func _land_reel(i: int) -> void:
	if i < _last_line.size():
		reels[i].text = SYMBOL_GLYPHS[SlotsLogic.SYMBOL_NAMES[int(_last_line[i])]]
	var p: Control = reels[i].get_parent() as Control
	p.pivot_offset = p.size * 0.5
	p.scale = Vector2(1.0, 0.9)
	var t: Tween = p.create_tween()
	t.tween_property(p, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Audio.play(&"reel_stop", &"UI", -10.0, 1.0 + i * 0.08)


func _show_result() -> void:
	var mult: int = SlotsLogic.payout_multiplier(_ints(_last_line), Registry.balance)
	status_label.text = ("WIN ×%d" % mult) if mult > 0 else "No luck — pull again"
	status_label.add_theme_color_override(&"font_color", Palette.MONEY_GREEN if mult > 0 else Palette.CREAM)


func _refresh() -> void:
	var spinning: bool = bool(pub.get("spinning", false))
	var line: Array = pub.get("line", [])
	stop_btn.visible = spinning
	bet_panel.visible = not spinning
	if spinning:
		status_label.text = "Spinning… ($%d)" % int(pub.get("stake", 0))
		status_label.remove_theme_color_override(&"font_color")
		_saw_spin = true
	elif line.is_empty():
		status_label.text = "Pick a bet to pull the lever"
	elif _saw_spin:
		# A new result: the reels stop left to right, then the payout shows.
		_saw_spin = false
		_last_line = line.duplicate()
		for i: int in 3:
			_stop_in[i] = 0.1 + STOP_STAGGER * i
		_result_pending = true
	elif not _result_pending:
		_last_line = line.duplicate()
		for i: int in mini(3, line.size()):
			reels[i].text = SYMBOL_GLYPHS[SlotsLogic.SYMBOL_NAMES[int(line[i])]]
		_show_result()


func _ints(a: Array) -> Array[int]:
	var out: Array[int] = []
	for v: Variant in a:
		out.append(int(v))
	return out
