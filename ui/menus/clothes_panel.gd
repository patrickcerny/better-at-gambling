class_name ClothesPanel
extends PanelContainer
## The clothes menu (Patrick: "Remove in-game skin picker, put in clothes menu (T-shirt icon next
## to settings gear)"): a grid of every skin (`Cosmetics.SKINS`), each tile a turning 3D bean
## wearing it (`SkinPreviewView`). Picking a tile saves it as profile/skin in user://settings.cfg,
## which `SceneRouter.profile_cosmetics()` sends with the next join. BACK (or Esc) closes.

signal closed

const COLUMNS: int = 4

## Skin id -> its tile (a toggle Button).
var tiles: Dictionary = {}
var back_button: Button


func _ready() -> void:
	name = "Clothes"
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -420
	offset_right = 420
	offset_top = -340
	offset_bottom = 340
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 12)
	add_child(v)
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.text = "CLOTHES"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var hint := Label.new()
	hint.theme_type_variation = &"SmallLabel"
	hint.text = "Pick what you wear. It applies from your next match."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hint)
	var grid := GridContainer.new()
	grid.name = "Grid"
	grid.columns = COLUMNS
	grid.add_theme_constant_override(&"h_separation", 12)
	grid.add_theme_constant_override(&"v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(grid)
	for skin: StringName in Cosmetics.SKINS:
		grid.add_child(_tile(skin))
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(bottom)
	back_button = Button.new()
	back_button.name = "Back"
	back_button.text = "BACK"
	back_button.custom_minimum_size = Vector2(200, 48)
	back_button.pressed.connect(close)
	bottom.add_child(back_button)


func _tile(skin: StringName) -> Button:
	var b := Button.new()
	b.name = String(skin)
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(186, 236)
	b.tooltip_text = str(Cosmetics.SKIN_NAMES.get(skin, skin))
	SettingsPanel.style_tab(b)
	for state: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed"]:
		var sb: StyleBoxFlat = (b.get_theme_stylebox(state) as StyleBoxFlat).duplicate()
		sb.set_corner_radius_all(14)
		b.add_theme_stylebox_override(state, sb)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	b.add_child(box)
	var preview := SkinPreviewView.make(skin)
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(preview)
	var label := Label.new()
	label.name = "Name"
	label.text = str(Cosmetics.SKIN_NAMES.get(skin, skin)).to_upper()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(label)
	b.pressed.connect(select.bind(skin))
	tiles[skin] = b
	return b


## The saved skin (falls back to the bean).
static func saved_skin() -> StringName:
	var skin := StringName(str(Settings.get_value("profile", "skin", "bean")))
	return skin if Cosmetics.is_valid_skin(skin) else &"bean"


## Wears `skin` from the next match on: saves it and lights its tile.
func select(skin: StringName) -> void:
	if not Cosmetics.is_valid_skin(skin):
		return
	Settings.set_value("profile", "skin", String(skin))
	Settings.save()
	_refresh()


func _refresh() -> void:
	var now: StringName = saved_skin()
	for s: StringName in tiles:
		(tiles[s] as Button).set_pressed_no_signal(s == now)


func open() -> void:
	_refresh()
	back_button.text = "BACK %s" % InputGlyphs.hint(&"ui_cancel")
	visible = true
	(tiles[saved_skin()] as Button).grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause")):
		get_viewport().set_input_as_handled()
		close()
