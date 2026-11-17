class_name DevTrollPanel
extends PanelContainer
## The dev's tools in an online match (Patrick 2026-11-16: "When i join ... ill have different stuff
## in the dev menu ingame to troll the players"): DEV TOOLS in the pause menu once he joined a room
## as the dev (`MatchScene.joined_as_dev`). Pick a player (or EVERYONE), then knock them over,
## freeze them, jail or free them, give or take money, slip them an item, start a minigame now or
## say something as DEV to the whole casino. Every button only sends a `dev_troll` intent: the room
## server checks that it comes from the dev (`MatchServer.dev_troll`). CLOSE or Esc: back to play.

signal closed

## Target "everyone but the dev" (`MatchServer.dev_troll`).
const EVERYONE: int = -2

var _state: ClientMatchState
var _local_id: int = -1
var target_pick: OptionButton
var amount_spin: SpinBox
var item_pick: OptionButton
var minigame_pick: OptionButton
var say_edit: LineEdit
var status: Label
var close_button: Button
## Action -> its button (tests).
var buttons: Dictionary[StringName, Button] = {}
## Intents sent (tests read the last one).
var sent: Array[Dictionary] = []
## Off in tests: the intents are only kept in `sent`.
var send_to_server: bool = true


func setup(state: ClientMatchState, local_id: int) -> void:
	_state = state
	_local_id = local_id


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	custom_minimum_size = Vector2(900, 0)
	add_theme_stylebox_override(&"panel", LevelPassPanel._panel_style())
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 12)
	add_child(v)
	var title := Label.new()
	title.text = "DEV TOOLS"
	title.theme_type_variation = &"TitleLabel"
	title.add_theme_color_override(&"font_color", Palette.MONEY_GREEN)
	v.add_child(title)
	var sub := Label.new()
	sub.text = "You joined as the dev: invisible until your entrance, endless money, no rank, no minigames."
	sub.theme_type_variation = &"SmallLabel"
	sub.add_theme_color_override(&"font_color", Color(Palette.CREAM, 0.55))
	v.add_child(sub)
	# The entrance (Patrick 2026-11-17): lights down, drumroll, spotlight, the dev floats in.
	var entrance := Button.new()
	entrance.name = "Entrance"
	entrance.text = "GRAND ENTRANCE"
	entrance.theme_type_variation = &"ActionButton"
	entrance.custom_minimum_size = Vector2(0, 60)
	entrance.tooltip_text = "Lights down, drumroll, \"Be prepared for a special guest....\", everyone looks at the entrance and you float down into the spotlight with your song. Ends your invisibility."
	entrance.pressed.connect(func() -> void:
		do(&"entrance")
		close())
	v.add_child(entrance)
	buttons[&"entrance"] = entrance
	# Target.
	var trow := _row(v, "WHO")
	target_pick = OptionButton.new()
	target_pick.name = "TargetPick"
	target_pick.custom_minimum_size = Vector2(0, 46)
	target_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trow.add_child(target_pick)
	# Body.
	var body := _row(v, "BODY")
	for a: Array in [[&"knock", "KNOCK OVER"], [&"freeze", "FREEZE"], [&"jail", "JAIL"], [&"free", "FREE"]]:
		_action(body, a[0], a[1])
	# Money.
	var mrow := _row(v, "MONEY")
	amount_spin = SpinBox.new()
	amount_spin.name = "Amount"
	amount_spin.min_value = 0
	amount_spin.max_value = 1_000_000
	amount_spin.step = 100
	amount_spin.value = 500
	amount_spin.prefix = "$"
	amount_spin.alignment = HORIZONTAL_ALIGNMENT_CENTER
	amount_spin.custom_minimum_size = Vector2(200, 46)
	mrow.add_child(amount_spin)
	_action(mrow, &"give_money", "GIVE")
	_action(mrow, &"take_money", "TAKE")
	# Item.
	var irow := _row(v, "ITEM")
	item_pick = OptionButton.new()
	item_pick.name = "ItemPick"
	item_pick.custom_minimum_size = Vector2(0, 46)
	item_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for d: ItemDefinition in DevMatchPanel.sorted_items():
		item_pick.add_item(d.display_name)
		item_pick.set_item_metadata(item_pick.item_count - 1, String(d.id))
	irow.add_child(item_pick)
	_action(irow, &"give_item", "GIVE ITEM")
	# Minigame (no target).
	var grow_ := _row(v, "MINIGAME")
	minigame_pick = OptionButton.new()
	minigame_pick.name = "MinigamePick"
	minigame_pick.custom_minimum_size = Vector2(0, 46)
	minigame_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	minigame_pick.add_item("Next in the bag")
	minigame_pick.set_item_metadata(0, "")
	for id: Variant in Registry.minigames:
		var def: MinigameDefinition = Registry.minigames[id]
		minigame_pick.add_item(def.display_name)
		minigame_pick.set_item_metadata(minigame_pick.item_count - 1, String(def.id))
	grow_.add_child(minigame_pick)
	_action(grow_, &"minigame", "START NOW")
	# Say (no target).
	var srow := _row(v, "SAY")
	say_edit = LineEdit.new()
	say_edit.name = "SayEdit"
	say_edit.placeholder_text = "Everyone sees it as DEV: ..."
	say_edit.max_length = 120
	say_edit.custom_minimum_size = Vector2(0, 46)
	say_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	say_edit.text_submitted.connect(func(_t: String) -> void: do(&"say"))
	srow.add_child(say_edit)
	_action(srow, &"say", "SEND")
	status = Label.new()
	status.name = "Status"
	status.theme_type_variation = &"MutedLabel"
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(status)
	close_button = Button.new()
	close_button.name = "Close"
	close_button.text = "CLOSE"
	close_button.custom_minimum_size = Vector2(260, 44)
	close_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_button.pressed.connect(close)
	v.add_child(close_button)


func open() -> void:
	visible = true
	status.text = ""
	refresh_targets()
	close_button.text = "CLOSE %s" % InputGlyphs.hint(&"ui_cancel")
	target_pick.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


## The players to pick from: EVERYONE, then everyone connected but the dev, by name.
func refresh_targets() -> void:
	var keep: int = selected_target()
	target_pick.clear()
	target_pick.add_item("EVERYONE")
	target_pick.set_item_metadata(0, EVERYONE)
	if _state != null:
		var ids: Array = _state.players.keys()
		ids.sort()
		for id: int in ids:
			var p: Dictionary = _state.players[id]
			if id == _local_id or bool(p.get("dev", false)) or not bool(p.get("connected", true)):
				continue
			target_pick.add_item(str(p.get("name", "Player %d" % id)))
			target_pick.set_item_metadata(target_pick.item_count - 1, id)
	for i: int in target_pick.item_count:
		if int(target_pick.get_item_metadata(i)) == keep:
			target_pick.select(i)
			return
	target_pick.select(0)


func selected_target() -> int:
	if target_pick == null or target_pick.selected < 0:
		return EVERYONE
	return int(target_pick.get_item_metadata(target_pick.selected))


## Sends `action` with the panel's current picks.
func do(action: StringName) -> void:
	var intent: Dictionary = {"action": String(action), "target": selected_target()}
	match action:
		&"give_money", &"take_money":
			intent["amount"] = int(amount_spin.value)
		&"give_item":
			intent["item"] = str(item_pick.get_selected_metadata())
		&"minigame":
			intent["item"] = str(minigame_pick.get_selected_metadata())
		&"say":
			var text: String = say_edit.text.strip_edges()
			if text == "":
				status.text = "Type something first"
				return
			intent["text"] = text
			say_edit.clear()
	var full: Dictionary = Intents.make(&"dev_troll", intent)
	sent.append(full)
	if send_to_server:
		Net.send_intent(full)
	var who: String = "everyone" if selected_target() == EVERYONE else target_pick.get_item_text(target_pick.selected)
	status.text = "%s: %s" % [buttons[action].text if buttons.has(action) else String(action), "the casino" if action in [&"minigame", &"say", &"entrance"] else who]


func _action(parent: Control, action: StringName, text: String) -> Button:
	var b := Button.new()
	b.name = String(action).capitalize().replace(" ", "")
	b.text = text
	b.custom_minimum_size = Vector2(140, 46)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(do.bind(action))
	parent.add_child(b)
	buttons[action] = b
	return b


func _row(parent: Control, caption: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	parent.add_child(row)
	var l := Label.new()
	l.text = caption
	l.custom_minimum_size.x = 120
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	row.add_child(l)
	return row


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
