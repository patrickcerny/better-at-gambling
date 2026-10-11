class_name OddJobsPanel
extends PanelContainer
## The Odd Jobs cabinet next to the Gift Shop: smash the big button (click it or Space) to fill the
## bar; every full bar pays $50. The server counts the presses, owns the bar and pays
## (`odd_jobs_press` → `odd_jobs_bar`, `odd_jobs_payout`); this window only shows its numbers, with
## a press counted ahead locally so smashing feels instant. At $500+ the cabinet refuses. E or Esc
## closes it.

signal closed
## The local player smashed the button (the map's button cap dips).
signal smashed

const ENOUGH_TEXT: String = "You've got enough. Go gamble!"
## Client-side cap on sends (the server drops anything over ~12/s anyway).
const MIN_SEND_GAP: float = 1.0 / 14.0

var state: ClientMatchState
var local_id: int = -1

var _button: Button
var _bar: ProgressBar
var _count: Label
var _note: Label
var _close: Button
var _fill: float = 0.0
var _needed: int = OddJobs.MIN_PRESSES
var _time: float = 0.0
var _last_send: float = -INF
var _punch: float = 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -330
	offset_right = 330
	offset_top = -300
	offset_bottom = 300
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 14)
	add_child(v)
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text = "ODD JOBS"
	v.add_child(title)
	var sub := Label.new()
	sub.name = "PerBar"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.text = "$%d per bar" % OddJobs.PAYOUT
	sub.theme_type_variation = &"HeadingLabel"
	sub.add_theme_color_override(&"font_color", Palette.MONEY_GREEN)
	v.add_child(sub)
	_button = Button.new()
	_button.name = "Smash"
	_button.text = "SMASH!"
	_button.focus_mode = Control.FOCUS_NONE
	_button.custom_minimum_size = Vector2(320, 170)
	_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_button.add_theme_font_size_override(&"font_size", 56)
	for st: StringName in [&"normal", &"hover", &"pressed", &"disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Palette.CASINO_RED.darkened(0.25 if st == &"pressed" else 0.0).lightened(0.08 if st == &"hover" else 0.0)
		if st == &"disabled":
			sb.bg_color = Palette.WARM_CHARCOAL
		sb.set_corner_radius_all(80)
		sb.set_border_width_all(6)
		sb.border_color = Palette.WARM_GOLD
		_button.add_theme_stylebox_override(st, sb)
	_button.add_theme_color_override(&"font_color", Palette.CREAM)
	_button.button_down.connect(press)
	v.add_child(_button)
	_bar = ProgressBar.new()
	_bar.name = "Bar"
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.step = 0.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 34)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Palette.CASINO_BLACK
	bg.set_corner_radius_all(8)
	bg.set_border_width_all(2)
	bg.border_color = Palette.WARM_GOLD.darkened(0.3)
	var fg := StyleBoxFlat.new()
	fg.bg_color = Palette.WARM_GOLD
	fg.set_corner_radius_all(8)
	_bar.add_theme_stylebox_override(&"background", bg)
	_bar.add_theme_stylebox_override(&"fill", fg)
	v.add_child(_bar)
	_count = Label.new()
	_count.name = "Presses"
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_count)
	_note = Label.new()
	_note.name = "Note"
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.add_theme_color_override(&"font_color", Palette.WARM_GOLD)
	v.add_child(_note)
	_close = Button.new()
	_close.text = "Close [Esc]"
	_close.focus_mode = Control.FOCUS_NONE
	_close.pressed.connect(close_panel)
	v.add_child(_close)


func bind(p_state: ClientMatchState, p_local_id: int) -> void:
	state = p_state
	local_id = p_local_id
	state.players_changed.connect(func() -> void:
		if visible:
			_refresh())
	if not Net.event_received.is_connected(_on_event):
		Net.event_received.connect(_on_event)


func _exit_tree() -> void:
	if Net.event_received.is_connected(_on_event):
		Net.event_received.disconnect(_on_event)


func open() -> void:
	visible = true
	_close.text = "Close %s" % InputGlyphs.hint(&"ui_cancel")
	_note.text = ""
	_refresh()


func close_panel() -> void:
	if visible:
		visible = false
		closed.emit()


func _money() -> int:
	return state.balance(local_id) if state != null else 0


func is_refused() -> bool:
	return _money() >= OddJobs.CAP


## One smash: counted ahead locally, sent to the server (which has the last word).
func press() -> void:
	if not visible:
		return
	if is_refused():
		_refresh()
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - _last_send < MIN_SEND_GAP:
		return
	_last_send = now
	var res: Dictionary = Net.send_intent(Intents.make(&"odd_jobs_press"))
	if not res["ok"]:
		_note.text = _reason(res["error"])
		return
	_punch = 1.0
	Audio.play(&"thud", &"UI", -8.0, randf_range(0.9, 1.1))
	smashed.emit()
	if bool(res.get("pending", false)):
		_fill = minf(_fill + 1.0 / maxi(_needed, 1), 0.999)  # online: the server's bar follows
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause") or event.is_action_pressed(&"interact"):
		get_viewport().set_input_as_handled()
		close_panel()
	elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo and (event as InputEventKey).physical_keycode == KEY_SPACE:
		get_viewport().set_input_as_handled()
		press()


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	_punch = maxf(0.0, _punch - delta * 8.0)
	_button.pivot_offset = _button.size * 0.5
	var pulse: float = 0.0 if is_refused() else 0.035 * sin(_time * 7.0)
	_button.scale = Vector2.ONE * (1.0 + pulse - 0.08 * _punch)


func _on_event(ev: Dictionary) -> void:
	var type: StringName = StringName(ev.get("type", &""))
	if type != &"odd_jobs_bar" and type != &"odd_jobs_payout":
		return  # other events carry "player" as a dictionary (player_joined), never int() those
	if int(ev.get("player", -1)) != local_id:
		return
	match type:
		&"odd_jobs_bar":
			_fill = float(ev["fill"])
			_needed = int(ev["presses_needed"])
			if visible:
				_refresh()
		&"odd_jobs_payout":
			_fill = 0.0
			if visible:
				_note.text = "+$%d! Keep smashing." % int(ev["amount"])
				_refresh()
		&"intent_rejected":
			if StringName(ev.get("intent", &"")) == &"odd_jobs_press" and visible:
				_note.text = _reason(StringName(ev.get("error", &"")))


func _refresh() -> void:
	if _bar == null:
		return
	var refused: bool = is_refused()
	if not refused:
		_needed = OddJobs.presses_needed(_money())
	_bar.value = _fill
	_bar.modulate = Color(1, 1, 1, 0.5) if refused else Color.WHITE
	_button.disabled = refused
	_count.text = "%d / %d presses" % [roundi(_fill * _needed), _needed] if not refused else "Bar frozen"
	if refused:
		_note.text = ENOUGH_TEXT
	elif _note.text == ENOUGH_TEXT or _note.text == "":
		_note.text = "Smash it! Click the button or press Space."


static func _reason(error: StringName) -> String:
	match error:
		&"enough_money":
			return ENOUGH_TEXT
		&"money_off":
			return "No money in this mode."
		&"too_far":
			return "Too far away"
		&"wrong_phase":
			return "The casino is closed."
	return String(error).capitalize()
