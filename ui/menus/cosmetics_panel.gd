class_name CosmeticsPanel
extends PanelContainer
## The cosmetics shop (Patrick: "There will be a shop for cosmetics", docs/GDD.md "Cosmetics
## shop"), from the main menu's COSMETICS entry, its T-shirt button and the lobby's settings
## tablet. A turning bean shows the picked item; one tab per kind of cosmetic that has stock
## (`CosmeticShop`, data/progression/cosmetics_shop.tres: only COLOURS for now), a tile per item
## with its price or state. BUY spends Coins, WEAR makes a colour the preferred one (worn from the
## next join on, and in the lobby at once through `set_color`). Coins are out-of-match money: the
## tables never take them. BACK (or Esc) closes.

signal closed
## A colour was put on (the lobby forwards it to the server).
signal color_worn(index: int)

const COLUMNS: int = 4
const KIND_TITLES: Dictionary = {CosmeticDef.KIND_COLOR: "COLOURS", CosmeticDef.KIND_HAT: "HATS"}

## Item id -> its tile (a toggle Button).
var tiles: Dictionary[StringName, Button] = {}
## The item the preview and the action button are about.
var selected: StringName = &""
var preview: BeanPreviewView
var item_name: Label
var action_button: Button
var status_label: Label
var coins_label: Label
var back_button: Button
var shop: CosmeticShop


func _ready() -> void:
	name = "Cosmetics"
	shop = CosmeticShop.default()
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -560
	offset_right = 560
	offset_top = -380
	offset_bottom = 380
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 10)
	add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.text = "COSMETICS"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var wallet := HBoxContainer.new()
	wallet.add_theme_constant_override(&"separation", 8)
	head.add_child(wallet)
	var coin := CoinIcon.make(36.0)
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wallet.add_child(coin)
	coins_label = Label.new()
	coins_label.name = "Coins"
	coins_label.theme_type_variation = &"HeadingLabel"
	coins_label.add_theme_color_override(&"font_color", Palette.COIN_GOLD)
	wallet.add_child(coins_label)
	var hint := Label.new()
	hint.theme_type_variation = &"SmallLabel"
	hint.text = "Coins come from playing matches (and every level up). They only buy cosmetics: the tables take $, which starts fresh every match."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(hint)
	var body := HBoxContainer.new()
	body.add_theme_constant_override(&"separation", 18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 300
	left.add_theme_constant_override(&"separation", 8)
	body.add_child(left)
	preview = BeanPreviewView.make(Palette.player_color(0), Vector2(300, 380))
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(preview)
	item_name = Label.new()
	item_name.name = "ItemName"
	item_name.theme_type_variation = &"HeadingLabel"
	item_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(item_name)
	action_button = Button.new()
	action_button.name = "Action"
	action_button.theme_type_variation = &"ActionButton"
	action_button.custom_minimum_size = Vector2(0, 52)
	action_button.pressed.connect(press_action)
	left.add_child(action_button)
	status_label = Label.new()
	status_label.name = "Status"
	status_label.theme_type_variation = &"SmallLabel"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(status_label)
	var tabs := TabContainer.new()
	tabs.name = "Kinds"
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(tabs)
	for kind: StringName in CosmeticDef.KINDS:
		var items: Array[CosmeticDef] = shop.of_kind(kind)
		if items.is_empty():
			continue  # a kind shows up once the shop stocks it
		var grid := GridContainer.new()
		grid.name = str(KIND_TITLES.get(kind, String(kind).to_upper()))
		grid.columns = COLUMNS
		grid.add_theme_constant_override(&"h_separation", 10)
		grid.add_theme_constant_override(&"v_separation", 10)
		tabs.add_child(grid)
		for d: CosmeticDef in items:
			grid.add_child(_tile(d))
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(bottom)
	back_button = Button.new()
	back_button.name = "Back"
	back_button.text = "BACK"
	back_button.custom_minimum_size = Vector2(200, 48)
	back_button.pressed.connect(close)
	bottom.add_child(back_button)
	ProfileManager.changed.connect(_refresh)


func _tile(d: CosmeticDef) -> Button:
	var b := Button.new()
	b.name = String(d.id)
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(170, 132)
	b.tooltip_text = d.display_name
	SettingsPanel.style_tab(b)
	for st: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed"]:
		var sb: StyleBoxFlat = (b.get_theme_stylebox(st) as StyleBoxFlat).duplicate()
		sb.set_corner_radius_all(14)
		b.add_theme_stylebox_override(st, sb)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	b.add_child(box)
	if d.kind == CosmeticDef.KIND_COLOR:
		var sw := Panel.new()
		sw.name = "Swatch"
		sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sw.custom_minimum_size = Vector2(56, 56)
		sw.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var sb := StyleBoxFlat.new()
		sb.bg_color = Palette.player_color(d.color_index)
		sb.set_corner_radius_all(28)
		sb.set_border_width_all(3)
		sb.border_color = Palette.CASINO_BLACK
		sw.add_theme_stylebox_override(&"panel", sb)
		box.add_child(sw)
	var label := Label.new()
	label.name = "Name"
	label.text = d.display_name.to_upper()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(label)
	var price := Label.new()
	price.name = "Price"
	price.theme_type_variation = &"SmallLabel"
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(price)
	b.pressed.connect(select.bind(d.id))
	tiles[d.id] = b
	return b


## Shows `id` in the preview and points the action button at it.
func select(id: StringName) -> void:
	if shop.find(id) == null:
		return
	selected = id
	status_label.text = ""
	_refresh()


## BUY when not owned (refused with a message when the Coins don't reach), else WEAR.
func press_action() -> void:
	var d: CosmeticDef = shop.find(selected)
	if d == null:
		return
	var p: PlayerProfile = ProfileManager.profile
	if not p.owns(d.id):
		var err: StringName = ProfileManager.buy(d.id)
		match err:
			&"":
				status_label.text = "Bought %s! Wear it whenever you like." % d.display_name
				Audio.play(&"cash_register", &"UI", -6.0)
			&"not_enough_coins":
				status_label.text = "Not enough Coins: %d more to go. Play matches to earn them." % (d.price - p.coins)
				Audio.play(&"ui_hover", &"UI", -8.0, 0.6)
			_:
				status_label.text = "Can't buy that right now."
		_refresh()
		return
	if d.kind == CosmeticDef.KIND_COLOR and p.preferred_color != d.color_index:
		ProfileManager.set_preferred_color(d.color_index)
		status_label.text = "Your bean wears %s from now on." % d.display_name
		color_worn.emit(d.color_index)
	_refresh()


func _refresh() -> void:
	if action_button == null:
		return
	var p: PlayerProfile = ProfileManager.profile
	coins_label.text = "%d" % p.coins
	for id: StringName in tiles:
		var d: CosmeticDef = shop.find(id)
		var b: Button = tiles[id]
		b.set_pressed_no_signal(id == selected)
		var price: Label = b.find_child("Price", true, false) as Label
		var wearing: bool = d.kind == CosmeticDef.KIND_COLOR and p.preferred_color == d.color_index
		if wearing:
			price.text = "WEARING"
		elif p.owns(id):
			price.text = "FREE" if d.is_free() else "OWNED"
		else:
			price.text = "%d COINS" % d.price
		price.add_theme_color_override(&"font_color", Palette.VIP_GOLD if wearing else (Palette.CREAM if p.owns(id) else Palette.COIN_GOLD))
	var sel: CosmeticDef = shop.find(selected)
	if sel == null:
		action_button.disabled = true
		action_button.text = "PICK SOMETHING"
		item_name.text = ""
		return
	item_name.text = sel.display_name.to_upper()
	if sel.kind == CosmeticDef.KIND_COLOR:
		preview.set_bean_color(Palette.player_color(sel.color_index))
	action_button.disabled = false
	if not p.owns(sel.id):
		action_button.text = "BUY  ·  %d COINS" % sel.price
	elif sel.kind == CosmeticDef.KIND_COLOR and p.preferred_color == sel.color_index:
		action_button.text = "WEARING"
		action_button.disabled = true
	else:
		action_button.text = "WEAR"


func open() -> void:
	var p: PlayerProfile = ProfileManager.profile
	var worn: CosmeticDef = shop.color_item(p.preferred_color)
	selected = worn.id if worn != null else (shop.items[0].id if not shop.items.is_empty() else &"")
	status_label.text = ""
	_refresh()
	back_button.text = "BACK %s" % InputGlyphs.hint(&"ui_cancel")
	visible = true
	if tiles.has(selected):
		tiles[selected].grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause")):
		get_viewport().set_input_as_handled()
		close()
