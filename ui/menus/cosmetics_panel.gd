class_name CosmeticsPanel
extends PanelContainer
## The cosmetics shop (Patrick: "There will be a shop for cosmetics", docs/GDD.md "Cosmetics
## shop"), from the main menu's COSMETICS entry, its T-shirt button and the lobby's settings
## tablet. Nearly full screen: on the left a big bean on a pedestal wearing what you wear with the
## picked item tried on (drag it, or use the right stick, to turn it round), the item's name, price
## and the action button; on the right a row of icon tabs (colours, hats, shirts, trousers, capes,
## boots; each icon a little 3D picture) over a grid of tiles, each tile a 3D picture of the piece
## (`CosmeticThumbnails`), its name and its price in Coins. BUY spends Coins; WEAR makes a colour
## the preferred one or puts a piece on (worn from the next join on, and in the lobby at once
## through `set_color` / `set_outfit`); TAKE OFF takes a piece off. Coins are out-of-match money:
## the tables never take them. BACK (or Esc) closes.
## Real money (Patrick 2026-11-14): every paid piece can also be bought through Steam for 0,50 to
## 1 euro, a few only that way (`CosmeticDef.money_only`), and the PACKS tab sells whole outfits
## 50 cents under their pieces (`CosmeticPack`). The STEAM button opens the Steam overlay
## (`SteamSvc.buy_item`); Steam's inventory then says what is owned. Without Steam it is greyed out.

signal closed
## A colour was put on (the lobby forwards it to the server).
signal color_worn(index: int)
## An outfit piece was put on in slot `kind` (`id` &"": taken off); the lobby forwards it.
signal outfit_worn(kind: StringName, id: StringName)

const COLUMNS: int = 4
const TILE: Vector2 = Vector2(196, 236)
const KIND_TITLES: Dictionary = {
	CosmeticDef.KIND_COLOR: "COLOURS", CosmeticDef.KIND_HAT: "HATS", CosmeticDef.KIND_SHIRT: "SHIRTS",
	CosmeticDef.KIND_PANTS: "TROUSERS", CosmeticDef.KIND_CAPE: "CAPES", CosmeticDef.KIND_BOOTS: "BOOTS",
	KIND_PACK: "PACKS",
}
## The packs tab's key (not a `CosmeticDef` kind).
const KIND_PACK: StringName = &"pack"
## The piece each tab's icon shows.
const TAB_ICONS: Dictionary = {
	CosmeticDef.KIND_COLOR: &"color_gold", CosmeticDef.KIND_HAT: &"hat_top", CosmeticDef.KIND_SHIRT: &"shirt_tux",
	CosmeticDef.KIND_PANTS: &"pants_jeans", CosmeticDef.KIND_CAPE: &"cape_hero", CosmeticDef.KIND_BOOTS: &"boots_sneakers",
	KIND_PACK: &"pack_royal",
}
const MUTED := Color("#B9A98C")

## Item id -> its tile (a toggle Button).
var tiles: Dictionary[StringName, Button] = {}
## The item the preview and the action button are about.
var selected: StringName = &""
var preview: BeanPreviewView
var item_name: Label
var item_kind: Label
var price_row: HBoxContainer
var price_label: Label
var price_coin: CoinIcon
var action_button: Button
## Pays real money through Steam (a piece or a pack).
var steam_button: Button
var status_label: Label
var coins_label: Label
var back_button: Button
var tabs: TabContainer
## Kind -> its icon tab button.
var tab_buttons: Dictionary[StringName, Button] = {}
var shop: CosmeticShop
var thumbnails: CosmeticThumbnails
var _dim: ColorRect


func _ready() -> void:
	name = "Cosmetics"
	shop = CosmeticShop.default()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 56
	offset_right = -56
	offset_top = 40
	offset_bottom = -40
	visible = false
	add_theme_stylebox_override(&"panel", _panel_style())
	thumbnails = CosmeticThumbnails.new()
	add_child(thumbnails)
	# Dims the menu behind the shop (a sibling put just under the panel on open).
	_dim = ColorRect.new()
	_dim.name = "CosmeticsDim"
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.color = Color(0.05, 0.03, 0.03, 0.72)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 14)
	add_child(v)
	# Header: title, the wallet.
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 16)
	v.add_child(head)
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.text = "COSMETICS"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var wallet := PanelContainer.new()
	wallet.add_theme_stylebox_override(&"panel", _box(Color("#1E1414"), Color(Palette.WARM_GOLD, 0.6), 2, 28, 18))
	wallet.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(wallet)
	var wrow := HBoxContainer.new()
	wrow.add_theme_constant_override(&"separation", 10)
	wallet.add_child(wrow)
	coins_label = Label.new()
	coins_label.name = "Coins"
	coins_label.theme_type_variation = &"HeadingLabel"
	coins_label.add_theme_color_override(&"font_color", Palette.COIN_GOLD)
	wrow.add_child(coins_label)
	var coin := CoinIcon.make(40.0)
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wrow.add_child(coin)
	var hint := Label.new()
	hint.theme_type_variation = &"SmallLabel"
	hint.add_theme_color_override(&"font_color", MUTED)
	hint.text = "Coins come from playing matches (and every level up). They only buy cosmetics: the tables take $, which starts fresh every match."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(hint)
	var body := HBoxContainer.new()
	body.add_theme_constant_override(&"separation", 28)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	# Left: the stage.
	var stage := PanelContainer.new()
	stage.name = "Stage"
	stage.add_theme_stylebox_override(&"panel", _stage_style())
	stage.custom_minimum_size.x = 520
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.size_flags_stretch_ratio = 0.8
	body.add_child(stage)
	var left := VBoxContainer.new()
	left.add_theme_constant_override(&"separation", 10)
	stage.add_child(left)
	preview = BeanPreviewView.make(Palette.player_color(0), Vector2(360, 240))  # grows with the space; never pushes the panel off a 1080-high screen
	preview.interactive = true
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.tooltip_text = "Drag to turn"
	left.add_child(preview)
	var drag_hint := Label.new()
	drag_hint.theme_type_variation = &"SmallLabel"
	drag_hint.add_theme_color_override(&"font_color", MUTED)
	drag_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	drag_hint.text = "Drag to turn"
	left.add_child(drag_hint)
	item_kind = Label.new()
	item_kind.name = "ItemKind"
	item_kind.theme_type_variation = &"SmallLabel"
	item_kind.add_theme_color_override(&"font_color", Palette.WARM_GOLD)
	item_kind.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(item_kind)
	item_name = Label.new()
	item_name.name = "ItemName"
	item_name.theme_type_variation = &"HeadingLabel"
	item_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(item_name)
	var pr: Array = _price_widget(32.0, &"HeadingLabel")
	price_row = pr[0]
	price_label = pr[1]
	price_coin = pr[2]
	price_row.name = "PriceRow"
	left.add_child(price_row)
	action_button = Button.new()
	action_button.name = "Action"
	action_button.theme_type_variation = &"ActionButton"
	action_button.custom_minimum_size = Vector2(0, 60)
	action_button.pressed.connect(press_action)
	left.add_child(action_button)
	steam_button = Button.new()
	steam_button.name = "Steam"
	steam_button.custom_minimum_size = Vector2(0, 52)
	steam_button.pressed.connect(press_steam)
	left.add_child(steam_button)
	status_label = Label.new()
	status_label.name = "Status"
	status_label.theme_type_variation = &"SmallLabel"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size.y = 26
	left.add_child(status_label)
	# Right: icon tabs over the tiles.
	var right := VBoxContainer.new()
	right.add_theme_constant_override(&"separation", 14)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	var tab_row := HBoxContainer.new()
	tab_row.name = "TabIcons"
	tab_row.add_theme_constant_override(&"separation", 12)
	right.add_child(tab_row)
	tabs = TabContainer.new()
	tabs.name = "Kinds"
	tabs.tabs_visible = false
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_theme_stylebox_override(&"panel", StyleBoxEmpty.new())
	right.add_child(tabs)
	for kind: StringName in CosmeticDef.KINDS:
		var items: Array[CosmeticDef] = shop.of_kind(kind)
		if items.is_empty():
			continue  # a kind shows up once the shop stocks it
		var grid: GridContainer = _grid_tab(str(KIND_TITLES.get(kind, String(kind).to_upper())))
		for d: CosmeticDef in items:
			grid.add_child(_tile(d))
		tab_row.add_child(_tab_button(kind, tabs.get_tab_count() - 1))
	if not shop.packs.is_empty():
		var pgrid: GridContainer = _grid_tab(str(KIND_TITLES[KIND_PACK]))
		for k: CosmeticPack in shop.packs:
			pgrid.add_child(_tile(null, k))
		tab_row.add_child(_tab_button(KIND_PACK, tabs.get_tab_count() - 1))
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(bottom)
	back_button = Button.new()
	back_button.name = "Back"
	back_button.text = "BACK"
	back_button.custom_minimum_size = Vector2(240, 52)
	back_button.pressed.connect(close)
	bottom.add_child(back_button)
	ProfileManager.changed.connect(_refresh)
	SteamSvc.store_changed.connect(_refresh)
	SteamSvc.purchase_finished.connect(_on_purchase_finished)
	resized.connect(_fit_columns)


## A scrolling grid of tiles as a new page of `tabs`.
func _grid_tab(title: String) -> GridContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	tabs.add_child(scroll)
	var grid := GridContainer.new()
	grid.name = "Grid"
	grid.columns = COLUMNS
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override(&"h_separation", 14)
	grid.add_theme_constant_override(&"v_separation", 14)
	scroll.add_child(grid)
	return grid


## An icon tab: a 3D picture of a typical piece, the kind's name as its tooltip.
func _tab_button(kind: StringName, index: int) -> Button:
	var b := Button.new()
	b.name = "Tab" + str(KIND_TITLES.get(kind, kind))
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(88, 88)
	b.tooltip_text = str(KIND_TITLES.get(kind, kind)).capitalize()
	b.icon = CosmeticThumbnails.texture_for(TAB_ICONS.get(kind, &""), true)
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	SettingsPanel.style_tab(b)
	for st: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"focus"]:
		var sb: StyleBox = b.get_theme_stylebox(st)
		if sb is StyleBoxFlat:
			var c := (sb as StyleBoxFlat).duplicate() as StyleBoxFlat
			c.set_corner_radius_all(20)
			c.set_content_margin_all(6)
			b.add_theme_stylebox_override(st, c)
	b.pressed.connect(func() -> void: show_kind(kind))
	b.set_meta(&"tab", index)
	tab_buttons[kind] = b
	return b


## Switches the grid to `kind`'s tab.
func show_kind(kind: StringName) -> void:
	var b: Button = tab_buttons.get(kind, null)
	if b == null:
		return
	tabs.current_tab = int(b.get_meta(&"tab"))
	for k: StringName in tab_buttons:
		tab_buttons[k].set_pressed_no_signal(k == kind)


## A piece's tile, or a pack's (`d` null).
func _tile(d: CosmeticDef, pack: CosmeticPack = null) -> Button:
	var id: StringName = d.id if d != null else pack.id
	var title: String = d.display_name if d != null else pack.display_name
	var b := Button.new()
	b.name = String(id)
	b.toggle_mode = true
	b.custom_minimum_size = TILE
	b.tooltip_text = title if d != null else "%s: %d pieces, %s cheaper than one by one" % [title, pack.pieces.size(), SteamSvc.format_price(CosmeticPack.DISCOUNT_CENTS, "EUR")]
	b.clip_contents = true
	SettingsPanel.style_tab(b)
	for st: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed"]:
		var sb: StyleBoxFlat = (b.get_theme_stylebox(st) as StyleBoxFlat).duplicate()
		sb.set_corner_radius_all(18)
		b.add_theme_stylebox_override(st, sb)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override(&"separation", 2)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
	b.add_child(box)
	var pic := TextureRect.new()
	pic.name = "Picture"
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.texture = CosmeticThumbnails.texture_for(id)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(pic)
	var label := Label.new()
	label.name = "Name"
	label.text = title.to_upper()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.clip_text = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(label)
	var pr: Array = _price_widget(22.0, &"SmallLabel")
	var row: HBoxContainer = pr[0]
	row.name = "PriceRow"
	(pr[1] as Label).name = "Price"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)
	b.pressed.connect(select.bind(id))
	b.focus_entered.connect(select.bind(id))
	tiles[id] = b
	return b


## [row, label, coin]: a price as a number with the Coin after it (the coin hides for words).
func _price_widget(coin_px: float, variation: StringName) -> Array:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 6)
	var l := Label.new()
	l.theme_type_variation = variation
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(l)
	var c := CoinIcon.make(coin_px)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(c)
	return [row, l, c]


## Shows `id` in the preview and points the action button at it.
func select(id: StringName) -> void:
	var d: CosmeticDef = shop.find(id)
	if d == null and shop.find_pack(id) == null:
		return
	if selected == id:
		return
	selected = id
	status_label.text = ""
	if preview != null:
		preview.face(d != null and d.kind == CosmeticDef.KIND_CAPE)
		preview.focus(d.kind if d != null else &"")
	_refresh()


## A pack's pieces as an outfit (kind -> id).
static func pack_outfit(pack: CosmeticPack) -> Dictionary:
	var o: Dictionary = {}
	var shop: CosmeticShop = CosmeticShop.default()
	for id: StringName in pack.pieces:
		var d: CosmeticDef = shop.find(id)
		if d != null and d.kind in CosmeticDef.OUTFIT_KINDS:
			o[d.kind] = id
	return o


## The real-money price of Steam item definition `def`: Steam's, in the player's currency, or the
## reference euro price while Steam hasn't answered (or isn't running).
static func money_text(def: int, cents: int) -> String:
	var t: String = SteamSvc.price_text(def)
	return t if t != "" else SteamSvc.format_price(cents, "EUR")


## STEAM: opens the Steam overlay to pay for the picked piece or pack.
func press_steam() -> void:
	var d: CosmeticDef = shop.find(selected)
	var pack: CosmeticPack = shop.find_pack(selected)
	var def: int = d.steam_item if d != null else (pack.steam_item if pack != null else 0)
	if def <= 0 or not SteamSvc.is_available():
		status_label.text = "Buying with real money needs Steam running."
		return
	if SteamSvc.buy_item(def):
		status_label.text = "Finish the purchase in the Steam overlay."
	else:
		status_label.text = "A purchase is already open in the Steam overlay."
	_refresh()


func _on_purchase_finished(ok: bool) -> void:
	if not visible:
		return
	status_label.text = "Thanks! It shows up here in a moment." if ok else "Purchase cancelled."
	_refresh()


## BUY when not owned (refused with a message when the Coins don't reach), else WEAR / TAKE OFF.
func press_action() -> void:
	var pack: CosmeticPack = shop.find_pack(selected)
	if pack != null:
		if ProfileManager.profile.owns_pack(pack):
			for id: StringName in pack.pieces:
				var piece: CosmeticDef = shop.find(id)
				if piece != null and ProfileManager.wear(id):
					outfit_worn.emit(piece.kind, id)
			status_label.text = "Your bean wears the whole %s outfit." % pack.display_name
		_refresh()
		return
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
				status_label.text = "Not enough Coins: %d more to go. Play matches to earn them%s." % [d.price - p.coins, (", or buy it with Steam" if d.steam_buyable() else "")]
				Audio.play(&"ui_hover", &"UI", -8.0, 0.6)
			_:
				status_label.text = "Can't buy that right now."
		_refresh()
		return
	if d.kind == CosmeticDef.KIND_COLOR and p.preferred_color != d.color_index:
		ProfileManager.set_preferred_color(d.color_index)
		status_label.text = "Your bean wears %s from now on." % d.display_name
		color_worn.emit(d.color_index)
	elif d.kind in CosmeticDef.OUTFIT_KINDS:
		if p.is_worn(d.id):
			ProfileManager.take_off(d.kind)
			status_label.text = "Took off the %s." % d.display_name
			outfit_worn.emit(d.kind, &"")
		elif ProfileManager.wear(d.id):
			status_label.text = "Your bean wears the %s from now on." % d.display_name
			outfit_worn.emit(d.kind, d.id)
	_refresh()


## Whether item `d` is what the bean wears now (its colour or one of its outfit pieces).
static func _wearing(p: PlayerProfile, d: CosmeticDef) -> bool:
	if d.kind == CosmeticDef.KIND_COLOR:
		return p.preferred_color == d.color_index
	return p.is_worn(d.id)


## Fills a price row: "WEARING" / "OWNED" / "FREE" as words, the Steam price for real-money-only
## pieces, else the number and the Coin.
static func _show_price(label: Label, coin: CoinIcon, p: PlayerProfile, d: CosmeticDef) -> void:
	var wearing: bool = _wearing(p, d)
	coin.visible = not p.owns(d.id)
	if wearing:
		label.text = "WEARING"
	elif p.owns(d.id):
		label.text = "FREE" if d.is_free() else "OWNED"
	elif not d.coin_buyable() and d.steam_buyable():
		label.text = money_text(d.steam_item, d.cents)
		coin.visible = false
	else:
		label.text = "%s" % Hud._thousands(d.price)
	label.add_theme_color_override(&"font_color", Palette.VIP_GOLD if wearing else (Palette.CREAM if p.owns(d.id) else Palette.COIN_GOLD))


func _refresh() -> void:
	if action_button == null:
		return
	var p: PlayerProfile = ProfileManager.profile
	coins_label.text = Hud._thousands(p.coins)
	for id: StringName in tiles:
		var d: CosmeticDef = shop.find(id)
		var b: Button = tiles[id]
		b.set_pressed_no_signal(id == selected)
		var row: Node = b.find_child("PriceRow", true, false)
		if d != null:
			_show_price(row.get_node("Price") as Label, row.get_child(1) as CoinIcon, p, d)
		else:
			_show_pack_price(row.get_node("Price") as Label, row.get_child(1) as CoinIcon, p, shop.find_pack(id))
	var pack: CosmeticPack = shop.find_pack(selected)
	if pack != null:
		_refresh_pack(p, pack)
		return
	var sel: CosmeticDef = shop.find(selected)
	if sel == null:
		steam_button.visible = false
		action_button.disabled = true
		action_button.text = "PICK SOMETHING"
		item_name.text = ""
		item_kind.text = ""
		price_row.visible = false
		return
	item_name.text = sel.display_name.to_upper()
	item_kind.text = str(KIND_TITLES.get(sel.kind, "")).trim_suffix("S").replace("TROUSER", "TROUSERS")
	price_row.visible = true
	_show_price(price_label, price_coin, p, sel)
	# The preview: what you wear, with the picked item tried on.
	var worn_color: int = p.preferred_color if p.preferred_color >= 0 else 0
	preview.set_bean_color(Palette.player_color(sel.color_index if sel.kind == CosmeticDef.KIND_COLOR else worn_color))
	var dress: Dictionary = p.outfit.duplicate()
	if sel.kind in CosmeticDef.OUTFIT_KINDS:
		dress[sel.kind] = sel.id
	if preview.outfit != dress:
		preview.set_outfit(dress)
	action_button.disabled = false
	action_button.visible = true
	_show_steam_button(not p.owns(sel.id) and sel.steam_buyable(), sel.steam_item, sel.cents, "BUY WITH STEAM")
	if not p.owns(sel.id) and not sel.coin_buyable():
		action_button.visible = false  # real money only: the Steam button is the way
	elif not p.owns(sel.id):
		action_button.text = "BUY FOR COINS" if sel.steam_buyable() else "BUY"
	elif sel.kind == CosmeticDef.KIND_COLOR and p.preferred_color == sel.color_index:
		action_button.text = "WEARING"
		action_button.disabled = true
	elif sel.kind in CosmeticDef.OUTFIT_KINDS and p.is_worn(sel.id):
		action_button.text = "TAKE OFF"
	else:
		action_button.text = "WEAR"


## A pack's tile price: OWNED when every piece is, else the Steam price.
static func _show_pack_price(label: Label, coin: CoinIcon, p: PlayerProfile, pack: CosmeticPack) -> void:
	coin.visible = false
	var owned: bool = p.owns_pack(pack)
	label.text = "OWNED" if owned else money_text(pack.steam_item, pack.cents)
	label.add_theme_color_override(&"font_color", Palette.CREAM if owned else Palette.COIN_GOLD)


## The stage for a pack: the bean in the whole outfit, its price and what it saves; WEAR ALL once
## it is owned.
func _refresh_pack(p: PlayerProfile, pack: CosmeticPack) -> void:
	item_name.text = pack.display_name.to_upper()
	var single: String = SteamSvc.format_price(shop.pieces_cents(pack), "EUR")
	item_kind.text = "PACK OF %d · %s ONE BY ONE" % [pack.pieces.size(), single]
	price_row.visible = true
	_show_pack_price(price_label, price_coin, p, pack)
	var worn_color: int = p.preferred_color if p.preferred_color >= 0 else 0
	preview.set_bean_color(Palette.player_color(worn_color))
	var dress: Dictionary = pack_outfit(pack)
	if preview.outfit != dress:
		preview.set_outfit(dress)
	var owned: bool = p.owns_pack(pack)
	action_button.visible = owned
	action_button.disabled = false
	action_button.text = "WEAR ALL"
	_show_steam_button(not owned, pack.steam_item, pack.cents, "BUY PACK")


## The Steam button: shown when real money can buy the pick, greyed out without Steam.
func _show_steam_button(on: bool, def: int, cents: int, verb: String) -> void:
	steam_button.visible = on
	if not on:
		return
	var ready: bool = SteamSvc.is_available() and not SteamSvc.buying
	steam_button.disabled = not ready
	steam_button.text = "%s · %s" % [verb, money_text(def, cents)]
	steam_button.tooltip_text = "" if SteamSvc.is_available() else "Needs Steam running"


## As many tile columns as fit.
func _fit_columns() -> void:
	if tabs == null:
		return
	var w: float = tabs.size.x - 24.0
	var cols: int = clampi(int(floor((w + 14.0) / (TILE.x + 14.0))), 2, 6)
	for scroll: Node in tabs.get_children():
		var grid: GridContainer = scroll.get_node_or_null("Grid") as GridContainer
		if grid != null:
			grid.columns = cols


func open() -> void:
	SteamSvc.refresh_inventory()  # bought on another PC, or in the Steam store
	var p: PlayerProfile = ProfileManager.profile
	var worn: CosmeticDef = shop.color_item(p.preferred_color)
	selected = &""
	select(worn.id if worn != null else (shop.items[0].id if not shop.items.is_empty() else &""))
	status_label.text = ""
	_refresh()
	back_button.text = "BACK %s" % InputGlyphs.hint(&"ui_cancel")
	var host: Node = get_parent()
	if host != null:
		# Over the menu's corner buttons and profile line, the dim right under it.
		if _dim.get_parent() == null:
			host.add_child(_dim)
		host.move_child(_dim, -1)
		host.move_child(self, -1)
		_dim.visible = true
	visible = true
	var sel: CosmeticDef = shop.find(selected)
	show_kind(sel.kind if sel != null else (KIND_PACK if shop.find_pack(selected) != null else CosmeticDef.KIND_COLOR))
	_fit_columns.call_deferred()
	if tiles.has(selected):
		tiles[selected].grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	_dim.visible = false
	closed.emit()


func _exit_tree() -> void:
	if _dim != null and _dim.get_parent() == null:
		_dim.free()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		close()
	elif event is InputEventJoypadButton and event.is_pressed():
		# Shoulder buttons flip through the tabs.
		var jb: InputEventJoypadButton = event
		if jb.button_index in [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER]:
			var kinds: Array[StringName] = tab_buttons.keys()
			var cur: int = tabs.current_tab
			var next: int = posmod(cur + (1 if jb.button_index == JOY_BUTTON_RIGHT_SHOULDER else -1), kinds.size())
			show_kind(kinds[next])
			get_viewport().set_input_as_handled()


static func _box(fill: Color, border: Color, width: int, radius: int, margin: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	sb.content_margin_top = margin * 0.5
	sb.content_margin_bottom = margin * 0.5
	return sb


static func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#221717")
	sb.border_color = Palette.WARM_GOLD
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(26)
	sb.set_content_margin_all(36)
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 24
	return sb


static func _stage_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#2E1C1C")
	sb.border_color = Color(Palette.WARM_GOLD, 0.35)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(22)
	sb.set_content_margin_all(22)
	return sb
