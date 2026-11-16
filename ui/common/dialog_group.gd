class_name DialogGroup
extends RefCounted
## Only one of its dialogs is ever open: when one shows, every other member is closed (its own
## `close()`, so it saves, emits `closed` and hands the focus back as usual). Patrick 2026-11-16:
## "I can open different dialogs (tutorial, settings) over each other. Close the other one."
##
## A member is any Control with a `close()` method. The group watches `visibility_changed`, so the
## dialogs need no changes and every way of opening one (button, entry, shortcut) is covered.

var members: Array[Control] = []
## The dialog that is opening while the others close (null otherwise). A `closed` handler checks it
## to tell "replaced by another dialog" from "closed by the player" (e.g. the tutorial then does not
## go on to the match it was opened before).
var replacing: Control = null


func add(dialog: Control) -> void:
	if dialog == null or members.has(dialog):
		return
	members.append(dialog)
	dialog.visibility_changed.connect(_on_visibility_changed.bind(dialog))


## The open member (the first one found), or null.
func open_dialog() -> Control:
	for d: Control in members:
		if is_instance_valid(d) and d.visible:
			return d
	return null


func _on_visibility_changed(dialog: Control) -> void:
	if replacing != null or not dialog.visible:
		return
	replacing = dialog
	for d: Control in members:
		if d != dialog and is_instance_valid(d) and d.visible:
			d.call(&"close")
	replacing = null
