class_name PadFocus
extends Node
## Gamepad focus for a screen of mouse buttons (a minigame's number grid, its vote cards). While
## the last input came from a pad the buttons take focus: the d-pad or left stick moves between
## them and A presses (ui_accept), and the first one that can be pressed gets the focus when
## nothing has it. With keyboard and mouse they don't take focus, so Enter and Space keep doing
## what the screen says and nothing sits highlighted.
##
## `candidates` returns the buttons in their current order; `active` (optional) says whether the
## screen wants input right now (a vote open, your turn). Add the node anywhere under the screen.

var candidates: Callable
var active: Callable
## The buttons focus was handed to last frame (to take it back when they change).
var _last: Array = []


static func make(p_candidates: Callable, p_active: Callable = Callable()) -> PadFocus:
	var f := PadFocus.new()
	f.name = "PadFocus"
	f.candidates = p_candidates
	f.active = p_active
	return f


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	refresh()


## Hands focus to (or takes it from) the buttons for the device in use. Called every frame.
func refresh() -> void:
	if not candidates.is_valid():
		return
	var list: Array = candidates.call()
	var on: bool = InputGlyphs.gamepad and (not active.is_valid() or bool(active.call()))
	for c: Variant in _last:
		if is_instance_valid(c) and not c in list:
			(c as Control).focus_mode = Control.FOCUS_NONE
	for c: Variant in list:
		if is_instance_valid(c):
			(c as Control).focus_mode = Control.FOCUS_ALL if on else Control.FOCUS_NONE
	_last = list.duplicate()
	var vp: Viewport = get_viewport()
	if vp == null:
		return
	var owner: Control = vp.gui_get_focus_owner()
	if on:
		if owner == null or (owner in list and not usable(owner)):
			var first: Control = first_usable(list)
			if first != null:
				first.grab_focus()
	elif owner != null and owner in list:
		owner.release_focus()


## True for a button that can be pressed right now.
static func usable(c: Variant) -> bool:
	if not is_instance_valid(c) or not (c as Control).is_visible_in_tree():
		return false
	return not (c is BaseButton and (c as BaseButton).disabled)


static func first_usable(list: Array) -> Control:
	for c: Variant in list:
		if usable(c):
			return c as Control
	return null
