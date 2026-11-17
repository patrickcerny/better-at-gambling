extends Node
## `FocusGate` autoload: with the mouse in hand no button is shown as selected (Patrick 2026-11-17:
## "allgemein aufm pc ist alles immer selected, in jedem menu änder das"). Menus still give a
## button the focus when they open (so keys and pads can start right away), but while you use the
## mouse the focus is let go again and only the button under the cursor lights up (hover). The
## first arrow key, Tab, Enter or pad press brings the focus back to where it was (that press only
## shows it), and from then on the focus shows as before. Text fields keep their focus.

## True while the last input came from the mouse: no focus is kept (except in text fields).
var mouse: bool = false
## The control that had the focus last (where a key or pad press puts it back).
var _last: WeakRef = weakref(null)
var _hooked: Viewport


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# On a PC you start with the mouse; on a Deck, with a pad plugged in or headless (tests), not.
	mouse = DisplayServer.get_name() != "headless" and not InputGlyphs.on_steam_deck() and Input.get_connected_joypads().is_empty()
	_hook()


func _hook() -> void:
	var vp: Viewport = get_viewport()
	if vp != null and vp != _hooked:
		_hooked = vp
		vp.gui_focus_changed.connect(_on_focus_changed)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_set_mouse(true)
		if not event.is_pressed():
			_drop.call_deferred()  # after the click went through (dropping it earlier cancels the press)
	elif event is InputEventMouseMotion:
		if (event as InputEventMouseMotion).relative.length() >= 6.0:
			_set_mouse(true)
	elif _is_nav(event):
		if mouse:
			_set_mouse(false)
			var owner_: Control = get_viewport().gui_get_focus_owner()
			if owner_ == null:
				var back: Control = _last.get_ref() as Control
				if back != null and back.is_visible_in_tree() and back.focus_mode != Control.FOCUS_NONE:
					back.grab_focus()
					get_viewport().set_input_as_handled()  # this press only shows where you are
	elif (event is InputEventKey or event is InputEventJoypadButton) and event.is_pressed():
		_set_mouse(false)


## A key or pad press that moves or uses the focus (arrows, Tab, Enter, the pad's stick and A).
static func _is_nav(event: InputEvent) -> bool:
	if not event.is_pressed() or event.is_echo():
		return false
	if event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) < 0.5:
		return false
	for a: StringName in [&"ui_up", &"ui_down", &"ui_left", &"ui_right", &"ui_focus_next", &"ui_focus_prev", &"ui_accept"]:
		if InputMap.has_action(a) and event.is_action(a):
			return true
	return false


func _set_mouse(on: bool) -> void:
	if on == mouse:
		return
	mouse = on
	if on:
		_drop()
	else:
		var f: Control = get_viewport().gui_get_focus_owner()
		if f != null:
			f.queue_redraw()


func _on_focus_changed(c: Control) -> void:
	_last = weakref(c)
	if mouse and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_drop.call_deferred()


## Lets the focus go while the mouse is in hand (text fields keep it).
func _drop() -> void:
	if not mouse or not is_inside_tree():
		return
	var f: Control = get_viewport().gui_get_focus_owner()
	if f == null or f is LineEdit or f is TextEdit or f is SpinBox:
		return
	_last = weakref(f)
	f.release_focus()
