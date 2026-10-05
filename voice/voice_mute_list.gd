class_name VoiceMuteList
extends VBoxContainer
## Per-player voice mute toggles for the in-game settings/pause panel. Reads the live
## `VoiceChannel`; hides itself when there is none (main menu, Practice) or nobody else is here.

var _flow: HFlowContainer


func _ready() -> void:
	add_theme_constant_override(&"separation", 4)
	var l := Label.new()
	l.text = "Mute players (voice)"
	add_child(l)
	_flow = HFlowContainer.new()
	_flow.add_theme_constant_override(&"h_separation", 8)
	_flow.add_theme_constant_override(&"v_separation", 4)
	add_child(_flow)
	refresh()


## Rebuilds the toggles from the current players.
func refresh() -> void:
	if _flow == null:
		return
	for c: Node in _flow.get_children():
		_flow.remove_child(c)
		c.queue_free()
	var roster: Array[Dictionary] = []
	var ch: VoiceChannel = VoiceChannel.current
	if ch != null and ch.online:
		roster = ch.roster()
	visible = not roster.is_empty()
	for p: Dictionary in roster:
		var pid: int = int(p["id"])
		var b := Button.new()
		b.toggle_mode = true
		b.button_pressed = bool(p["muted"])
		b.custom_minimum_size = Vector2(0, 40)
		b.icon = VoiceIcons.speaker(Palette.CREAM, bool(p["muted"]), 32)
		b.text = str(p["name"])
		b.tooltip_text = "Mute or unmute %s's voice" % str(p["name"])
		b.toggled.connect(func(on: bool) -> void:
			if VoiceChannel.current != null:
				VoiceChannel.current.set_muted(pid, on)
			b.icon = VoiceIcons.speaker(Palette.CREAM, on, 32))
		_flow.add_child(b)
