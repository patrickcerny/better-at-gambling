class_name VoiceMuteList
extends VBoxContainer
## Each other player's own voice volume (0–200 %) and mute, for the in-game settings/pause panel.
## Reads the live `VoiceChannel`, which remembers both per Steam id; hides itself when there is
## none (main menu, Practice) or nobody else is here.

## One row per player id: {mute: Button, slider: HSlider, value: Label}.
var rows: Dictionary[int, Dictionary] = {}
var _list: VBoxContainer


func _ready() -> void:
	add_theme_constant_override(&"separation", 4)
	var l := Label.new()
	l.text = "Player voices"
	add_child(l)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override(&"separation", 4)
	add_child(_list)
	refresh()


## Rebuilds the rows from the current players.
func refresh() -> void:
	if _list == null:
		return
	for c: Node in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	rows.clear()
	var roster: Array[Dictionary] = []
	var ch: VoiceChannel = VoiceChannel.current
	if ch != null and ch.online:
		roster = ch.roster()
	visible = not roster.is_empty()
	for p: Dictionary in roster:
		_add_row(int(p["id"]), str(p["name"]), bool(p["muted"]), float(p.get("volume", 1.0)))


func _add_row(pid: int, player_name: String, is_muted: bool, volume: float) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 10)
	_list.add_child(h)
	var b := Button.new()
	b.toggle_mode = true
	b.button_pressed = is_muted
	b.custom_minimum_size = Vector2(220, 40)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.icon = VoiceIcons.speaker(Palette.CREAM, is_muted, 32)
	b.text = player_name
	b.tooltip_text = "Mute or unmute %s's voice" % player_name
	h.add_child(b)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = VoiceChannel.MAX_PLAYER_VOLUME
	s.step = 0.05
	s.value = volume
	s.editable = not is_muted
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.tooltip_text = "How loud %s is for you" % player_name
	h.add_child(s)
	var val := Label.new()
	val.custom_minimum_size = Vector2(70, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.text = _percent(volume)
	h.add_child(val)
	b.toggled.connect(func(on: bool) -> void:
		if VoiceChannel.current != null:
			VoiceChannel.current.set_muted(pid, on)
		b.icon = VoiceIcons.speaker(Palette.CREAM, on, 32)
		s.editable = not on)
	s.value_changed.connect(func(x: float) -> void:
		val.text = _percent(x)
		if VoiceChannel.current != null:
			VoiceChannel.current.set_volume(pid, x))
	rows[pid] = {"mute": b, "slider": s, "value": val}


static func _percent(v: float) -> String:
	return "%d%%" % roundi(v * 100.0)
