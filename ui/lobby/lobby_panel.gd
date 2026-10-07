class_name LobbyPanel
extends PanelContainer
## The 2D lobby panel (§2.2) that mirrors the physical entrance hall for gamepad and
## accessibility: the 8 slots (name, color, skin, ready, leader), the ready toggle, your skin
## and — for the party leader — match length (minigames, gambling minutes between them) and items. Every
## button sends an intent; the panel only redraws from the ClientMatchState mirror.

signal closed
signal leave_requested

var state: ClientMatchState
var local_id: int = -1

var _title: Label
var _slots: VBoxContainer
var _ready_button: Button
var _settings_box: VBoxContainer
var _settings_note: Label
var _countdown_label: Label
## Match length steppers (Patrick's note #12): setting key → {minus, plus, value: Label}.
var _steppers: Dictionary[String, Dictionary] = {}
var _items_button: Button
var _length_note: Label
var _skin_label: Label
var _skin_next: Button
## The 8 slot rows, built once and updated in place (rebuilding them made the panel, and the
## READY button with it, jump on every snapshot, so clicks missed). Each: {frame, swatch, name, ready, empty}.
var _rows: Array[Dictionary] = []
## Frame the panel was opened on: the Tab press that opened it must not close it again.
var _opened_frame: int = -1


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -470
	offset_right = 470
	offset_top = -290
	offset_bottom = 290
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	visible = false
	_build()


## Connects to the mirror.
func bind(p_state: ClientMatchState, p_local_id: int) -> void:
	state = p_state
	local_id = p_local_id
	state.lobby_changed.connect(_refresh)
	state.players_changed.connect(_refresh)
	_refresh()


## Shows the panel; `focus` is &"settings", &"wardrobe" or &"" (general).
func open(focus: StringName = &"") -> void:
	visible = true
	_opened_frame = Engine.get_process_frames()
	_refresh()
	match focus:
		&"settings":
			if _steppers.has("minigames"):
				(_steppers["minigames"]["plus"] as Button).grab_focus()
		&"wardrobe":
			_skin_next.grab_focus()
		_:
			_ready_button.grab_focus()


func close() -> void:
	if visible:
		visible = false
		closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var tab: bool = event.is_action_pressed(&"leaderboard") and Engine.get_process_frames() != _opened_frame
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause") or tab:
		get_viewport().set_input_as_handled()
		close()


func _build() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 10)
	add_child(v)
	_title = Label.new()
	_title.theme_type_variation = &"TitleLabel"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_title)
	_countdown_label = Label.new()
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	v.add_child(_countdown_label)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override(&"separation", 24)
	v.add_child(cols)
	_slots = VBoxContainer.new()
	_slots.custom_minimum_size = Vector2(420, 0)
	_slots.add_theme_constant_override(&"separation", 4)
	cols.add_child(_slots)
	for i: int in Protocol.MAX_PLAYERS:
		_rows.append(_make_row())
	var right := VBoxContainer.new()
	right.add_theme_constant_override(&"separation", 8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	_ready_button = Button.new()
	_ready_button.custom_minimum_size = Vector2(0, 60)
	_ready_button.theme_type_variation = &"ActionButton"
	_ready_button.toggle_mode = true
	# The button's own pressed flag is what gets sent, so a click always means "this state",
	# even if a snapshot lands between the click and the server's answer.
	_ready_button.toggled.connect(func(on: bool) -> void:
		_ready_button.text = "NOT READY" if on else "READY"
		Net.send_intent(Intents.make(&"set_ready", {"ready": on})))
	right.add_child(_ready_button)
	right.add_child(_heading("YOUR SKIN"))
	var skin_row := HBoxContainer.new()
	skin_row.add_theme_constant_override(&"separation", 8)
	right.add_child(skin_row)
	var prev := Button.new()
	prev.text = "◀"
	prev.custom_minimum_size = Vector2(54, 44)
	prev.pressed.connect(_cycle_skin.bind(-1))
	skin_row.add_child(prev)
	_skin_label = Label.new()
	_skin_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_skin_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skin_row.add_child(_skin_label)
	_skin_next = Button.new()
	var next: Button = _skin_next
	next.text = "▶"
	next.custom_minimum_size = Vector2(54, 44)
	next.pressed.connect(_cycle_skin.bind(1))
	skin_row.add_child(next)
	right.add_child(_heading("PARTY SETTINGS"))
	_settings_note = Label.new()
	_settings_note.theme_type_variation = &"SmallLabel"
	right.add_child(_settings_note)
	_settings_box = VBoxContainer.new()
	right.add_child(_settings_box)
	_add_stepper("minigames", "MINIGAMES")
	_add_stepper("gamble_minutes", "GAMBLING BETWEEN")
	_items_button = Button.new()
	_items_button.toggle_mode = true
	_items_button.pressed.connect(func() -> void:
		Net.send_intent(Intents.make(&"lobby_setting", {"key": "items_enabled", "value": not bool(state.lobby_settings.get("items_enabled", true))})))
	_settings_box.add_child(_items_button)
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override(&"separation", 20)
	v.add_child(bottom)
	var close_b := Button.new()
	close_b.text = "CLOSE"
	close_b.pressed.connect(close)
	bottom.add_child(close_b)
	var leave := Button.new()
	leave.text = "LEAVE PARTY"
	leave.pressed.connect(func() -> void: leave_requested.emit())
	bottom.add_child(leave)


func _make_row() -> Dictionary:
	var framed := PanelContainer.new()
	framed.custom_minimum_size = Vector2(0, 46)
	framed.theme_type_variation = &"RowPanel"
	_slots.add_child(framed)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	framed.add_child(row)
	var empty := Label.new()
	empty.text = "open slot"
	empty.theme_type_variation = &"MutedLabel"
	empty.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(empty)
	var sw := ColorRect.new()
	sw.custom_minimum_size = Vector2(28, 28)
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(sw)
	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	row.add_child(label)
	var ready := Label.new()
	ready.theme_type_variation = &"SmallLabel"
	ready.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ready)
	return {"frame": framed, "swatch": sw, "name": label, "ready": ready, "empty": empty}


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"HeadingLabel"
	return l


func _refresh() -> void:
	if state == null or _title == null:
		return
	var code: String = str(Net.room.get("room_code", ""))
	_title.text = "PARTY LOBBY" + ("   ·   CODE %s" % code if code != "" else "")
	_countdown_label.text = "Doors open in %d…" % ceili(state.countdown) if state.countdown > 0.0 else "Stand on your colored READY pad (or press READY)."
	var ids: Array = state.players.keys()
	ids.sort()
	for i: int in _rows.size():
		var r: Dictionary = _rows[i]
		var taken: bool = i < ids.size()
		(r["frame"] as PanelContainer).theme_type_variation = &"RowPanelHighlight" if taken and ids[i] == local_id else &"RowPanel"
		(r["empty"] as Label).visible = not taken
		(r["swatch"] as ColorRect).visible = taken
		(r["name"] as Label).visible = taken
		(r["ready"] as Label).visible = taken
		if not taken:
			continue
		var pid: int = ids[i]
		var p: Dictionary = state.players[pid]
		(r["swatch"] as ColorRect).color = Palette.player_color(int(p.get("color", 0)))
		var tags: PackedStringArray = []
		if pid == state.leader:
			tags.append("★")
		if not bool(p.get("connected", true)):
			tags.append("(away)")
		var label: Label = r["name"]
		label.text = "%s  %s" % [str(p.get("name", "?")), " ".join(tags)]
		if pid == local_id:
			label.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
		else:
			label.remove_theme_color_override(&"font_color")
		var is_ready: bool = bool(p.get("ready", false))
		var ready: Label = r["ready"]
		ready.text = "READY" if is_ready else "NOT READY"
		ready.add_theme_color_override(&"font_color", Palette.MONEY_GREEN if is_ready else Color("#9A8F7A"))
	_ready_button.set_pressed_no_signal(_my_ready())
	_ready_button.text = "NOT READY" if _my_ready() else "READY"
	_skin_label.text = str(Cosmetics.SKIN_NAMES.get(_my_skin(), "Bean"))
	var leader: bool = local_id == state.leader
	_settings_note.text = "You lead this party." if leader else "Only the party leader (★) can change these."
	var presets: MatchPresets = Registry.presets
	var mg: int = int(state.lobby_settings.get("minigames", presets.default_minigames))
	var gm: int = int(state.lobby_settings.get("gamble_minutes", presets.default_gamble_minutes))
	_set_stepper("minigames", "%d" % mg, leader and mg > presets.min_minigames, leader and mg < presets.max_minigames)
	_set_stepper("gamble_minutes", "%d MIN" % gm, leader and gm > presets.min_gamble_minutes, leader and gm < presets.max_gamble_minutes)
	_length_note.text = "About %d min of gambling in all" % (gm * (mg + 1))
	_items_button.text = "ITEMS: %s" % ("ON" if bool(state.lobby_settings.get("items_enabled", true)) else "OFF")
	_items_button.button_pressed = bool(state.lobby_settings.get("items_enabled", true))
	_items_button.disabled = not leader


## One "LABEL  [−] value [+]" row; the buttons ask the server to step the setting by one.
func _add_stepper(key: String, title: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	_settings_box.add_child(row)
	var label := Label.new()
	label.text = title
	label.custom_minimum_size = Vector2(220, 0)
	row.add_child(label)
	var minus := Button.new()
	minus.text = "−"
	minus.custom_minimum_size = Vector2(54, 44)
	minus.pressed.connect(_step_setting.bind(key, -1))
	row.add_child(minus)
	var value := Label.new()
	value.custom_minimum_size = Vector2(90, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(value)
	var plus := Button.new()
	plus.text = "+"
	plus.custom_minimum_size = Vector2(54, 44)
	plus.pressed.connect(_step_setting.bind(key, 1))
	row.add_child(plus)
	_steppers[key] = {"minus": minus, "plus": plus, "value": value}
	if key == "gamble_minutes":
		_length_note = Label.new()
		_length_note.theme_type_variation = &"SmallLabel"
		_settings_box.add_child(_length_note)


func _set_stepper(key: String, text: String, can_down: bool, can_up: bool) -> void:
	var s: Dictionary = _steppers[key]
	(s["value"] as Label).text = text
	(s["minus"] as Button).disabled = not can_down
	(s["plus"] as Button).disabled = not can_up


func _step_setting(key: String, step: int) -> void:
	var presets: MatchPresets = Registry.presets
	var fallback: int = presets.default_minigames if key == "minigames" else presets.default_gamble_minutes
	var now: int = int(state.lobby_settings.get(key, fallback))
	Net.send_intent(Intents.make(&"lobby_setting", {"key": key, "value": now + step}))


func _my_skin() -> StringName:
	return StringName(state.players.get(local_id, {}).get("skin", "bean"))


## Steps through the skins; the choice is remembered for the next party.
func _cycle_skin(step: int) -> void:
	if state == null:
		return
	var i: int = maxi(Cosmetics.SKINS.find(_my_skin()), 0)
	var skin: StringName = Cosmetics.SKINS[posmod(i + step, Cosmetics.SKINS.size())]
	Settings.set_value("profile", "skin", String(skin))
	Settings.save()
	Net.send_intent(Intents.make(&"set_skin", {"skin": skin}))


func _my_ready() -> bool:
	return bool(state.players.get(local_id, {}).get("ready", false))

