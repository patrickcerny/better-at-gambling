class_name DevMatchPanel
extends PanelContainer
## Developer mode in a Practice match (`DevMode`; DEV TOOLS in the pause menu, Patrick only):
## money up or down, any item into your bag, and the next minigame now (a chosen one or the
## bag's next). Talks straight to the Practice server on this PC (`MatchServer.dev_*`); online
## matches never show it. CLOSE or Esc goes back to play.

signal closed

const MONEY_STEPS: Array[int] = [1000, 10000, -1000]

var _scene: MatchScene
var status: Label
var minigame_pick: OptionButton
var minigame_button: Button
## Item id -> its GIVE button.
var item_buttons: Dictionary = {}
var close_button: Button


func setup(scene: MatchScene) -> void:
	_scene = scene


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	custom_minimum_size = Vector2(860, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 10)
	add_child(v)
	var title := Label.new()
	title.text = "DEV TOOLS"
	title.theme_type_variation = &"HeadingLabel"
	title.add_theme_color_override(&"font_color", Palette.MONEY_GREEN)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	# Money.
	v.add_child(_section("MONEY"))
	var money := HBoxContainer.new()
	money.add_theme_constant_override(&"separation", 10)
	v.add_child(money)
	for amount: int in MONEY_STEPS:
		var b := _button(money, ("+$%s" if amount > 0 else "-$%s") % _thousands(absi(amount)), give_money.bind(amount))
		b.name = "Money%d" % amount
	# The next minigame.
	v.add_child(_section("MINIGAME"))
	var mg := HBoxContainer.new()
	mg.add_theme_constant_override(&"separation", 10)
	v.add_child(mg)
	minigame_pick = OptionButton.new()
	minigame_pick.name = "MinigamePick"
	minigame_pick.custom_minimum_size = Vector2(320, 48)
	minigame_pick.add_item("Next in the bag")
	minigame_pick.set_item_metadata(0, "")
	for id: Variant in Registry.minigames:
		var def: MinigameDefinition = Registry.minigames[id]
		minigame_pick.add_item(def.display_name)
		minigame_pick.set_item_metadata(minigame_pick.item_count - 1, String(def.id))
	mg.add_child(minigame_pick)
	minigame_button = _button(mg, "START IT NOW", minigame_now)
	minigame_button.name = "MinigameNow"
	# Items.
	v.add_child(_section("ITEMS (click one: it goes in your bag)"))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override(&"h_separation", 8)
	grid.add_theme_constant_override(&"v_separation", 8)
	scroll.add_child(grid)
	for d: ItemDefinition in sorted_items():
		var b := _button(grid, d.display_name, give_item.bind(d.id))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 42)
		b.tooltip_text = d.description
		item_buttons[d.id] = b
	status = Label.new()
	status.name = "Status"
	status.theme_type_variation = &"MutedLabel"
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(status)
	close_button = _button(v, "CLOSE", close)
	close_button.name = "Close"


## Every item, by name (Empty Bottle and the like included: dev wants them all).
static func sorted_items() -> Array[ItemDefinition]:
	var out: Array[ItemDefinition] = []
	for id: Variant in Registry.items:
		out.append(Registry.items[id] as ItemDefinition)
	out.sort_custom(func(a: ItemDefinition, b: ItemDefinition) -> bool: return a.display_name.naturalnocasecmp_to(b.display_name) < 0)
	return out


func open() -> void:
	visible = true
	status.text = ""
	_refresh()
	close_button.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func give_money(amount: int) -> void:
	if not _ok():
		return
	DevMode.mark_used()
	_scene.server.dev_give_money(_scene.local_id, amount)
	_say("%s$%s" % ["+" if amount > 0 else "-", _thousands(absi(amount))])


func give_item(id: StringName) -> void:
	if not _ok():
		return
	DevMode.mark_used()
	var def: ItemDefinition = Registry.items.get(id, null)
	var name_: String = def.display_name if def != null else String(id)
	_say("%s in your bag" % name_ if _scene.server.dev_give_item(_scene.local_id, id) else "Bag full: pick what to throw away")
	close()  # a full bag asks in the HUD


func minigame_now() -> void:
	if not _ok():
		return
	DevMode.mark_used()
	var id := StringName(str(minigame_pick.get_selected_metadata()))
	if _scene.server.dev_minigame_now(id):
		close()
	else:
		_say("Only in the casino, and only while a minigame is left this match")


func _refresh() -> void:
	if not _ok():
		return
	var players: int = _scene.server.state.players.size()
	for i: int in minigame_pick.item_count:
		var id := StringName(str(minigame_pick.get_item_metadata(i)))
		var def: MinigameDefinition = Registry.minigames.get(id, null)
		minigame_pick.set_item_disabled(i, def != null and def.min_players > players)


func _ok() -> bool:
	return _scene != null and _scene.dev_tools_available()


func _say(text: String) -> void:
	status.text = text
	if _scene != null and _scene.hud != null:
		_scene.hud.toast("DEV: " + text, 2.0)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"SmallLabel"
	return l


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(150, 48)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


static func _thousands(n: int) -> String:
	var s: String = str(n)
	var out: String = ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out
