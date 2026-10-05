class_name LobbyPanel
extends PanelContainer
## The 2D lobby panel (§2.2) that mirrors the physical entrance hall for gamepad and
## accessibility: the 8 slots (name, color, ready, leader), the ready
## toggle and — for the party leader — duration, items, bot difficulty and bot slots. Every
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
var _duration_buttons: Dictionary[int, Button] = {}
var _items_button: Button
var _difficulty_buttons: Dictionary[StringName, Button] = {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -470
	offset_right = 470
	offset_top = -340
	offset_bottom = 340
	visible = false
	_build()


## Connects to the mirror.
func bind(p_state: ClientMatchState, p_local_id: int) -> void:
	state = p_state
	local_id = p_local_id
	state.lobby_changed.connect(_refresh)
	state.players_changed.connect(_refresh)
	_refresh()


## Shows the panel; `focus` is &"settings" or &"" (general).
func open(focus: StringName = &"") -> void:
	visible = true
	_refresh()
	match focus:
		&"settings":
			if not _duration_buttons.is_empty():
				_duration_buttons.values()[0].grab_focus()
		_:
			_ready_button.grab_focus()


func close() -> void:
	if visible:
		visible = false
		closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause")):
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
	_countdown_label.theme_type_variation = &"HeadingLabel"
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
	var right := VBoxContainer.new()
	right.add_theme_constant_override(&"separation", 8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	_ready_button = Button.new()
	_ready_button.custom_minimum_size = Vector2(0, 54)
	_ready_button.pressed.connect(func() -> void:
		Net.send_intent(Intents.make(&"set_ready", {"ready": not _my_ready()})))
	right.add_child(_ready_button)
	right.add_child(_heading("PARTY SETTINGS"))
	_settings_note = Label.new()
	_settings_note.theme_type_variation = &"SmallLabel"
	right.add_child(_settings_note)
	_settings_box = VBoxContainer.new()
	right.add_child(_settings_box)
	var dur := HBoxContainer.new()
	_settings_box.add_child(dur)
	for d: int in LobbyController.DURATIONS:
		var b := Button.new()
		b.text = "%d MIN" % d
		b.toggle_mode = true
		b.pressed.connect(func() -> void: Net.send_intent(Intents.make(&"lobby_setting", {"key": "duration", "value": d})))
		dur.add_child(b)
		_duration_buttons[d] = b
	_items_button = Button.new()
	_items_button.toggle_mode = true
	_items_button.pressed.connect(func() -> void:
		Net.send_intent(Intents.make(&"lobby_setting", {"key": "items_enabled", "value": not bool(state.lobby_settings.get("items_enabled", true))})))
	_settings_box.add_child(_items_button)
	var diff := HBoxContainer.new()
	_settings_box.add_child(diff)
	for dname: StringName in LobbyController.BOT_DIFFICULTIES:
		var b := Button.new()
		b.text = "BOTS: %s" % String(dname).to_upper()
		b.toggle_mode = true
		b.add_theme_font_size_override(&"font_size", 18)
		b.pressed.connect(func() -> void: Net.send_intent(Intents.make(&"lobby_setting", {"key": "bot_difficulty", "value": dname})))
		diff.add_child(b)
		_difficulty_buttons[dname] = b
	var add_bot := Button.new()
	add_bot.text = "ADD BOT"
	add_bot.pressed.connect(func() -> void: Net.send_intent(Intents.make(&"add_bot")))
	_settings_box.add_child(add_bot)
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
	for c: Node in _slots.get_children():
		c.queue_free()
	var ids: Array = state.players.keys()
	ids.sort()
	for i: int in Protocol.MAX_PLAYERS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 8)
		_slots.add_child(row)
		if i >= ids.size():
			var empty := Label.new()
			empty.text = "— open slot —"
			empty.theme_type_variation = &"SmallLabel"
			row.add_child(empty)
			continue
		var pid: int = ids[i]
		var p: Dictionary = state.players[pid]
		var sw := ColorRect.new()
		sw.custom_minimum_size = Vector2(28, 28)
		sw.color = Palette.player_color(int(p.get("color", 0)))
		row.add_child(sw)
		var label := Label.new()
		var tags: PackedStringArray = []
		if pid == state.leader:
			tags.append("★")
		if bool(p.get("bot", false)):
			tags.append("BOT")
		if not bool(p.get("connected", true)):
			tags.append("away")
		label.text = "%s %s" % [str(p.get("name", "?")), " ".join(tags)]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if pid == local_id:
			label.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
		row.add_child(label)
		var ready := Label.new()
		var is_ready: bool = bool(p.get("ready", false)) or bool(p.get("bot", false))
		ready.text = "READY" if is_ready else "…"
		ready.add_theme_color_override(&"font_color", Palette.MONEY_GREEN if is_ready else Color("#9A8F7A"))
		row.add_child(ready)
		if bool(p.get("bot", false)) and local_id == state.leader:
			var rm := Button.new()
			rm.text = "✕"
			rm.pressed.connect(func() -> void: Net.send_intent(Intents.make(&"remove_bot", {"player": pid})))
			row.add_child(rm)
	_ready_button.text = "NOT READY" if _my_ready() else "READY"
	var leader: bool = local_id == state.leader
	_settings_note.text = "You lead this party." if leader else "Only the party leader (★) can change these."
	for d: int in _duration_buttons:
		_duration_buttons[d].button_pressed = int(state.lobby_settings.get("duration", 10)) == d
		_duration_buttons[d].disabled = not leader
	_items_button.text = "ITEMS: %s" % ("ON" if bool(state.lobby_settings.get("items_enabled", true)) else "OFF")
	_items_button.button_pressed = bool(state.lobby_settings.get("items_enabled", true))
	_items_button.disabled = not leader
	for dname: StringName in _difficulty_buttons:
		_difficulty_buttons[dname].button_pressed = StringName(state.lobby_settings.get("bot_difficulty", &"normal")) == dname
		_difficulty_buttons[dname].disabled = not leader
	_settings_box.get_child(_settings_box.get_child_count() - 1).set(&"disabled", not leader)


func _my_ready() -> bool:
	return bool(state.players.get(local_id, {}).get("ready", false))

