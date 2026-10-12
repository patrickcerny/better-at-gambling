class_name MinigameSelector
extends PanelContainer
## Which minigames are in the rotation (lobby setting `minigame_pool`), opened from the lobby
## panel's settings: one tile per registered minigame (picture, name, the rules' first sentence,
## min players, ON/OFF) plus ALL / NONE. The leader's toggles send `lobby_setting` intents;
## everyone else sees the same tiles read-only. At least one game stays on: the last one's toggle
## is locked and NONE keeps the first game that is on. Redraws only from the ClientMatchState mirror.

signal closed

const PICTURE_DIR: String = "res://assets/minigames/"
const PICTURE_SIZE: Vector2 = Vector2(208, 117)
const COLUMNS: int = 4

var state: ClientMatchState
var local_id: int = -1
var all_button: Button
var none_button: Button
var back_button: Button
## id → {tile, picture: TextureRect, toggle: Button}
var tiles: Dictionary[StringName, Dictionary] = {}

var _note: Label
var _grid: GridContainer


func _ready() -> void:
	top_level = true  # floats over the lobby panel instead of being laid out inside it
	set_anchors_preset(Control.PRESET_CENTER)
	offset_left = -490
	offset_right = 490
	offset_top = -320
	offset_bottom = 320
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	visible = false
	_build()


func bind(p_state: ClientMatchState, p_local_id: int) -> void:
	state = p_state
	local_id = p_local_id
	state.lobby_changed.connect(_refresh)
	_refresh()


func open() -> void:
	visible = true
	_refresh()
	if all_button.disabled:
		back_button.grab_focus()
	else:
		all_button.grab_focus()


func close() -> void:
	if visible:
		visible = false
		closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause")):
		get_viewport().set_input_as_handled()
		close()


## Ids in the rotation, registry order ("" in the setting = all of them).
func enabled_ids() -> PackedStringArray:
	var pool: PackedStringArray = str(state.lobby_settings.get("minigame_pool", "") if state != null else "").split(",", false)
	var out: PackedStringArray = []
	for id: StringName in Registry.minigames:
		if pool.is_empty() or pool.has(String(id)):
			out.append(String(id))
	return out


func is_leader() -> bool:
	return state != null and local_id == state.leader


func _build() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 8)
	add_child(v)
	var title := Label.new()
	title.text = "MINIGAMES"
	title.theme_type_variation = &"TitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var top := HBoxContainer.new()
	top.add_theme_constant_override(&"separation", 8)
	v.add_child(top)
	_note = Label.new()
	_note.theme_type_variation = &"SmallLabel"
	_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_note)
	all_button = Button.new()
	all_button.name = "All"
	all_button.text = "ALL"
	all_button.custom_minimum_size = Vector2(110, 0)
	all_button.pressed.connect(func() -> void: _send(PackedStringArray()))
	top.add_child(all_button)
	none_button = Button.new()
	none_button.name = "None"
	none_button.text = "NONE"
	none_button.custom_minimum_size = Vector2(110, 0)
	none_button.pressed.connect(func() -> void:
		var on: PackedStringArray = enabled_ids()
		_send(PackedStringArray([on[0]]) if not on.is_empty() else PackedStringArray()))
	top.add_child(none_button)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override(&"h_separation", 10)
	_grid.add_theme_constant_override(&"v_separation", 10)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid)
	for id: StringName in Registry.minigames:
		_add_tile(Registry.minigames[id])
	back_button = Button.new()
	back_button.name = "Back"
	back_button.text = "BACK"
	back_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back_button.custom_minimum_size = Vector2(160, 0)
	back_button.pressed.connect(close)
	v.add_child(back_button)


func _add_tile(def: MinigameDefinition) -> void:
	var tile := PanelContainer.new()
	tile.name = String(def.id)
	tile.theme_type_variation = &"RowPanel"
	tile.tooltip_text = def.rules_text
	_grid.add_child(tile)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 4)
	tile.add_child(v)
	var pic := TextureRect.new()
	pic.custom_minimum_size = PICTURE_SIZE
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.texture = picture(def.id)
	v.add_child(pic)
	if pic.texture == null:
		pic.add_child(_placeholder(def.display_name))
	var name_l := Label.new()
	name_l.text = def.display_name.to_upper()
	name_l.theme_type_variation = &"HeadingLabel"
	name_l.add_theme_font_size_override(&"font_size", 22)
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_l.custom_minimum_size = Vector2(PICTURE_SIZE.x, 0)
	v.add_child(name_l)
	var rules := Label.new()
	rules.text = first_sentence(def.rules_text)
	rules.theme_type_variation = &"SmallLabel"
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules.max_lines_visible = 2
	rules.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	rules.custom_minimum_size = Vector2(PICTURE_SIZE.x, 0)
	v.add_child(rules)
	var row := HBoxContainer.new()
	v.add_child(row)
	var players := Label.new()
	players.text = "%d+ players" % def.min_players
	players.theme_type_variation = &"MutedLabel"
	players.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(players)
	var toggle := Button.new()
	toggle.name = "Toggle"
	toggle.toggle_mode = true
	toggle.theme_type_variation = &"ChipButton"
	toggle.custom_minimum_size = Vector2(76, 32)
	toggle.toggled.connect(_on_toggled.bind(String(def.id)))
	row.add_child(toggle)
	tiles[def.id] = {"tile": tile, "picture": pic, "toggle": toggle}


## The game's picture (assets/minigames/<id>.webp or .png), or null.
static func picture(id: StringName) -> Texture2D:
	for ext: String in ["webp", "png"]:
		var path: String = "%s%s.%s" % [PICTURE_DIR, id, ext]
		if ResourceLoader.exists(path):
			return load(path) as Texture2D
	return null


## The rules' first sentence (the tooltip carries the rest).
static func first_sentence(rules: String) -> String:
	var text: String = rules.strip_edges()
	var cut: int = text.find(". ")
	return text if cut < 0 else text.substr(0, cut + 1)


func _placeholder(title: String) -> Control:
	var bg := ColorRect.new()
	bg.color = Palette.CASINO_BLACK.lerp(Palette.VIP_GOLD, 0.18)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var l := Label.new()
	l.text = title.to_upper()
	l.theme_type_variation = &"HeadingLabel"
	l.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_child(l)
	return bg


func _on_toggled(on: bool, id: String) -> void:
	if not is_leader():
		_refresh()
		return
	var ids: PackedStringArray = enabled_ids()
	if on and not ids.has(id):
		ids.append(id)
	elif not on:
		if ids.size() <= 1:
			_refresh()  # the last game stays on
			return
		ids.remove_at(ids.find(id))
	_send(ids)


## Sends the pool ("" = every game).
func _send(ids: PackedStringArray) -> void:
	if not is_leader():
		return
	var ordered: PackedStringArray = []
	for id: StringName in Registry.minigames:
		if ids.has(String(id)):
			ordered.append(String(id))
	var value: String = "" if ordered.size() >= Registry.minigames.size() else ",".join(ordered)
	Net.send_intent(Intents.make(&"lobby_setting", {"key": "minigame_pool", "value": value}))


func _refresh() -> void:
	if state == null or _grid == null:
		return
	var leader: bool = is_leader()
	var on: PackedStringArray = enabled_ids()
	_note.text = ("%d of %d in the rotation. At least one stays on." if leader else "%d of %d in the rotation. Only the lobby leader (★) can change these.") % [on.size(), Registry.minigames.size()]
	all_button.disabled = not leader or on.size() == Registry.minigames.size()
	none_button.disabled = not leader or on.size() <= 1
	for id: StringName in tiles:
		var t: Dictionary = tiles[id]
		var is_on: bool = on.has(String(id))
		var toggle: Button = t["toggle"]
		toggle.set_pressed_no_signal(is_on)
		toggle.text = "ON" if is_on else "OFF"
		toggle.disabled = not leader or (is_on and on.size() <= 1)
		(t["tile"] as PanelContainer).theme_type_variation = &"RowPanelHighlight" if is_on else &"RowPanel"
		(t["picture"] as TextureRect).modulate = Color.WHITE if is_on else Color(0.45, 0.45, 0.45)
