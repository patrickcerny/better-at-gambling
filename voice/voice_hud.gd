class_name VoiceHud
extends VBoxContainer
## Voice indicator on the left edge (online only): our own mic state ("Hold T to talk",
## "TALKING", "Open mic", "Voice off") and below it everyone we can hear right now, in their
## player colour.

var channel: VoiceChannel = null

var _self_icon: TextureRect
var _self_label: Label
var _talkers: VBoxContainer
var _icon_idle: ImageTexture
var _icon_live: ImageTexture
var _icon_off: ImageTexture
var _rows: Dictionary[int, HBoxContainer] = {}
var _refresh_in: float = 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER_LEFT)
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = 28
	offset_right = 360
	offset_top = -40
	offset_bottom = 200
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override(&"separation", 6)
	_icon_idle = VoiceIcons.speaker(Color(Palette.CREAM, 0.6), false, 48)
	_icon_live = VoiceIcons.speaker(Palette.MONEY_GREEN, false, 48)
	_icon_off = VoiceIcons.speaker(Palette.CREAM, true, 48)
	var me := HBoxContainer.new()
	me.add_theme_constant_override(&"separation", 8)
	me.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(me)
	_self_icon = _icon(me, _icon_idle)
	_self_label = _label(me, "", Palette.CREAM)
	_talkers = VBoxContainer.new()
	_talkers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_talkers)


func _process(delta: float) -> void:
	if channel == null or not is_instance_valid(channel):
		visible = false
		return
	_refresh_in -= delta
	if _refresh_in > 0.0:
		return
	_refresh_in = 0.1
	if not channel.is_active():
		_self_icon.texture = _icon_off
		_self_label.text = "Voice off"
	elif channel.capture.transmitting:
		_self_icon.texture = _icon_live
		_self_label.text = "TALKING"
	else:
		_self_icon.texture = _icon_idle
		_self_label.text = "Open mic" if channel.mode_key() == "open_mic" else "Hold %s to talk" % _ptt_key()
	_self_label.add_theme_color_override(&"font_color", Palette.MONEY_GREEN if channel.capture.transmitting else Palette.CREAM)
	# Who we can hear.
	var talking: Dictionary[int, bool] = {}
	for pid: int in channel.playbacks:
		if channel.is_talking(pid):
			talking[pid] = true
	for pid: int in _rows.keys():
		if not talking.has(pid):
			_rows[pid].queue_free()
			_rows.erase(pid)
	for pid: int in talking:
		if _rows.has(pid):
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 8)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var info: Dictionary = channel.state.players.get(pid, {}) if channel.state != null else {}
		var col: Color = Palette.player_color(int(info.get("color", pid - 1)))
		_icon(row, VoiceIcons.speaker(col, false, 40))
		_label(row, channel.state.player_name(pid) if channel.state != null else "Player %d" % pid, col)
		_talkers.add_child(row)
		_rows[pid] = row


func _ptt_key() -> String:
	if not InputMap.has_action(&"push_to_talk"):
		return "T"
	for ev: InputEvent in InputMap.action_get_events(&"push_to_talk"):
		if ev is InputEventKey:
			var k: InputEventKey = ev
			return OS.get_keycode_string(k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode)
	return "T"


func _icon(parent: Control, tex: Texture2D) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex
	t.custom_minimum_size = Vector2(32, 32)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(t)
	return t


func _label(parent: Control, text: String, col: Color) -> Label:
	var l := Label.new()
	l.theme_type_variation = &"SmallLabel"
	l.text = text
	l.add_theme_color_override(&"font_color", col)
	l.add_theme_constant_override(&"outline_size", 6)
	l.add_theme_color_override(&"font_outline_color", Palette.CASINO_BLACK)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l
