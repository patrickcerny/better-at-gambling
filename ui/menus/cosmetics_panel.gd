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
## Two currencies (Patrick 2026-11-15): red Coins are earned by playing and buy the normal pieces;
## Gold Coins only come for real money (the + next to them opens the GOLD page, `CoinPack`, bought
## in the Steam overlay) and buy the premium pieces (`CosmeticDef.gold`) and the PACKS tab's whole
## outfits (`CosmeticPack`) through the Steam inventory (`SteamSvc.buy_with_gold`). Without Steam
## there is no Gold. Some items
## unlock for free at a player level (`CosmeticDef.level`, a LV badge on the tile) and can be
## bought before that.

signal closed
## A colour was put on (the lobby forwards it to the server).
signal color_worn(index: int)
## An outfit piece was put on in slot `kind` (`id` &"": taken off); the lobby forwards it.
signal outfit_worn(kind: StringName, id: StringName)

const COLUMNS: int = 4
const TILE: Vector2 = Vector2(196, 236)
const KIND_TITLES: Dictionary = {
	CosmeticDef.KIND_COLOR: "SKINS", CosmeticDef.KIND_SKIN: "SKINS", CosmeticDef.KIND_HAT: "HATS",
	CosmeticDef.KIND_SHIRT: "SHIRTS", CosmeticDef.KIND_PANTS: "TROUSERS", CosmeticDef.KIND_CAPE: "CAPES",
	CosmeticDef.KIND_BOOTS: "BOOTS", CosmeticDef.KIND_EYES: "EYES", CosmeticDef.KIND_MOUTH: "MOUTHS",
	CosmeticDef.KIND_BEARD: "BEARDS", KIND_PACK: "PACKS", KIND_COINS: "GOLD",
}
## The packs tab's key (not a `CosmeticDef` kind).
const KIND_PACK: StringName = &"pack"
## The coins page's key (opened by the + next to the wallet; no tab icon).
const KIND_COINS: StringName = &"coins"
## The piece each tab's icon shows.
const TAB_ICONS: Dictionary = {
	CosmeticDef.KIND_COLOR: &"skin_rainbow", CosmeticDef.KIND_SKIN: &"skin_rainbow", CosmeticDef.KIND_HAT: &"hat_top",
	CosmeticDef.KIND_SHIRT: &"shirt_tux", CosmeticDef.KIND_PANTS: &"pants_jeans", CosmeticDef.KIND_CAPE: &"cape_hero",
	CosmeticDef.KIND_BOOTS: &"boots_sneakers", CosmeticDef.KIND_EYES: &"eyes_star", CosmeticDef.KIND_MOUTH: &"mouth_tongue",
	CosmeticDef.KIND_BEARD: &"beard_full", KIND_PACK: &"pack_royal",
}
const MUTED := Color("#B9A98C")

## Inventory mode (the T-shirt in the menu's corner): only what the player owns, to wear it.
## Shop mode (SHOP in the menu) shows everything to buy.
var inventory: bool = false
var title_label: Label
## Switches between the shop and the inventory.
var switch_button: Button
## Item id -> its tile (a toggle Button).
var tiles: Dictionary[StringName, Button] = {}
## The item the preview and the action button are about.
var selected: StringName = &""
## What the preview tries on, one per slot (kind -> id): picks stack across the tabs, so a hat, a
## shirt and a skin can be seen together. Clicking a picked tile again takes it back off.
var trying: Dictionary[StringName, StringName] = {}
## The tried-on look: how many pieces, what they cost together.
var look_label: Label
## BUY ALL for the tried-on pieces not owned yet, then WEAR ALL.
var look_button: Button
## Takes every try-on off again.
var reset_button: Button
var preview: BeanPreviewView
var item_name: Label
var item_kind: Label
var price_row: HBoxContainer
var price_label: Label
var price_coin: CoinIcon
var action_button: Button
## The open "Buy ...? Can't be refunded" question, if any.
var confirm_dialog: ConfirmDialog
## Pays real money through Steam (a piece or a pack).
var steam_button: Button
var status_label: Label
var coins_label: Label
## The Gold Coins in the Steam inventory.
var gold_label: Label
## The + next to the wallet: opens the COINS page.
var coins_button: Button
var back_button: Button
var tabs: TabContainer
## Kind -> its icon tab button.
var tab_buttons: Dictionary[StringName, Button] = {}
var shop: CosmeticShop
var thumbnails: CosmeticThumbnails
var _dim: ColorRect
## Shop and inventory look like two places, not one page with a different button (Patrick
## 2026-11-15): the shop is a storefront (striped awning, the wallet, FEATURED cards of the day),
## the inventory a wardrobe (dark wood, a WEARING column with one slot per kind, how much you own,
## no prices or wallet).
var wallet: Control
var hint_label: Label
## Shop only: today's featured cards over the tabs.
var featured_row: HBoxContainer
## Inventory only: "N OF M OWNED" where the shop has the wallet.
var owned_label: Label
## Inventory only: the WEARING column between the stage and the tiles.
var wardrobe: PanelContainer
## Kind -> its slot in the WEARING column.
var slots: Dictionary[StringName, Button] = {}
var stage: PanelContainer
## How many featured cards the shop shows.
const FEATURED: int = 3


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
	title_label = Label.new()
	title_label.name = "Title"
	title_label.theme_type_variation = &"TitleLabel"
	title_label.text = "SHOP"
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title_label)
	switch_button = Button.new()
	switch_button.name = "Switch"
	switch_button.custom_minimum_size = Vector2(0, 52)
	switch_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	switch_button.pressed.connect(func() -> void: set_inventory(not inventory))
	head.add_child(switch_button)
	owned_label = Label.new()
	owned_label.name = "Owned"
	owned_label.theme_type_variation = &"HeadingLabel"
	owned_label.add_theme_color_override(&"font_color", Palette.WARM_GOLD)
	owned_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(owned_label)
	wallet = PanelContainer.new()
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
	coins_label.add_theme_color_override(&"font_color", Palette.COIN_RED)
	coins_label.tooltip_text = "Coins: earned by playing"
	coins_label.mouse_filter = Control.MOUSE_FILTER_STOP
	var coin := CoinIcon.make(40.0)
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wrow.add_child(coin)
	var gap := Control.new()
	gap.custom_minimum_size.x = 14
	wrow.add_child(gap)
	gold_label = Label.new()
	gold_label.name = "Gold"
	gold_label.theme_type_variation = &"HeadingLabel"
	gold_label.add_theme_color_override(&"font_color", Palette.COIN_GOLD)
	gold_label.tooltip_text = "Gold Coins: bought with real money, for premium pieces and sets"
	gold_label.mouse_filter = Control.MOUSE_FILTER_STOP
	wrow.add_child(gold_label)
	var gcoin := CoinIcon.make(40.0, true)
	gcoin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wrow.add_child(gcoin)
	# The + sits inside the wallet next to the Gold, a round button in the coin's own gold.
	coins_button = GoldPlusButton.make()
	coins_button.name = "BuyCoins"
	coins_button.tooltip_text = "Buy Gold Coins"
	coins_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	coins_button.pressed.connect(func() -> void: show_kind(KIND_COINS))
	wrow.add_child(coins_button)
	var hint := Label.new()
	hint_label = hint
	hint.theme_type_variation = &"SmallLabel"
	hint.add_theme_color_override(&"font_color", MUTED)
	hint.text = "Red Coins come from playing matches and every level up, Gold Coins only with + through Steam (for premium pieces and sets). Both only buy cosmetics: the tables take $, which starts fresh every match."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(hint)
	var body := HBoxContainer.new()
	body.add_theme_constant_override(&"separation", 28)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	# Left: the stage.
	stage = PanelContainer.new()
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
	var look_row := HBoxContainer.new()
	look_row.name = "Look"
	look_row.add_theme_constant_override(&"separation", 8)
	left.add_child(look_row)
	look_label = Label.new()
	look_label.name = "LookLabel"
	look_label.theme_type_variation = &"SmallLabel"
	look_label.add_theme_color_override(&"font_color", MUTED)
	look_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	look_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	look_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	look_row.add_child(look_label)
	look_button = Button.new()
	look_button.name = "LookAction"
	look_button.custom_minimum_size = Vector2(0, 44)
	look_button.pressed.connect(press_look)
	look_row.add_child(look_button)
	reset_button = Button.new()
	reset_button.name = "Reset"
	reset_button.text = "RESET"
	reset_button.tooltip_text = "Take off everything you're trying on"
	reset_button.custom_minimum_size = Vector2(0, 44)
	reset_button.pressed.connect(reset_look)
	look_row.add_child(reset_button)
	status_label = Label.new()
	status_label.name = "Status"
	status_label.theme_type_variation = &"SmallLabel"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size.y = 26
	left.add_child(status_label)
	body.add_child(_build_wardrobe())
	# Right: (shop) the featured cards, the icon tabs over the tiles.
	var right := VBoxContainer.new()
	right.add_theme_constant_override(&"separation", 14)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	featured_row = HBoxContainer.new()
	featured_row.name = "Featured"
	featured_row.add_theme_constant_override(&"separation", 14)
	right.add_child(featured_row)
	for id: StringName in featured_ids():
		featured_row.add_child(_featured_card(id))
	var tab_row := HFlowContainer.new()  # wraps onto a second row on narrow screens
	tab_row.name = "TabIcons"
	tab_row.add_theme_constant_override(&"h_separation", 8)
	tab_row.add_theme_constant_override(&"v_separation", 8)
	right.add_child(tab_row)
	tabs = TabContainer.new()
	tabs.name = "Kinds"
	tabs.tabs_visible = false
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_theme_stylebox_override(&"panel", StyleBoxEmpty.new())
	right.add_child(tabs)
	for kind: StringName in CosmeticDef.KINDS:
		if kind == CosmeticDef.KIND_SKIN:
			continue  # on the colours' page: plain and animated skins are one tab (Patrick 2026-11-16)
		var items: Array[CosmeticDef] = shop.of_kind(kind)
		if kind == CosmeticDef.KIND_COLOR:
			items = items + shop.of_kind(CosmeticDef.KIND_SKIN)
		if items.is_empty():
			continue  # a kind shows up once the shop stocks it
		var grid: GridContainer = _grid_tab(str(KIND_TITLES.get(kind, String(kind).to_upper())))
		for d: CosmeticDef in items:
			grid.add_child(_tile(d))
		tab_row.add_child(_tab_button(kind, tabs.get_tab_count() - 1))
		if kind == CosmeticDef.KIND_COLOR:
			tab_buttons[CosmeticDef.KIND_SKIN] = tab_buttons[kind]
	if not shop.packs.is_empty():
		var pgrid: GridContainer = _grid_tab(str(KIND_TITLES[KIND_PACK]))
		for k: CosmeticPack in shop.packs:
			pgrid.add_child(_tile(null, k))
		tab_row.add_child(_tab_button(KIND_PACK, tabs.get_tab_count() - 1))
	if not shop.coin_packs.is_empty():
		var cgrid: GridContainer = _grid_tab(str(KIND_TITLES[KIND_COINS]))
		for c: CoinPack in shop.coin_packs:
			cgrid.add_child(_coin_tile(c))
		var coins_tab: Button = _tab_button(KIND_COINS, tabs.get_tab_count() - 1)
		coins_tab.visible = false  # the + next to the wallet opens it
		tab_row.add_child(coins_tab)
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
	SteamSvc.gold_spent.connect(_on_gold_spent)
	resized.connect(_fit_columns)
	tabs.resized.connect(_fit_columns)  # the tile area settles after the panel: count columns from it


## Today's featured ids: premium pieces and sets, a new three every day (the same for everyone).
func featured_ids(day: int = -1) -> Array[StringName]:
	var pool: Array[StringName] = []
	for d: CosmeticDef in shop.items:
		if d.premium():
			pool.append(d.id)
	for k: CosmeticPack in shop.packs:
		pool.append(k.id)
	var out: Array[StringName] = []
	if pool.is_empty():
		return out
	if day < 0:
		day = int(Time.get_unix_time_from_system() / 86400.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(day)
	while out.size() < mini(FEATURED, pool.size()):
		var id: StringName = pool[rng.randi_range(0, pool.size() - 1)]
		if id not in out:
			out.append(id)
	return out


## A wide FEATURED card: the picture, a gold ribbon, the name and the Gold price.
func _featured_card(id: StringName) -> Button:
	var d: CosmeticDef = shop.find(id)
	var pack: CosmeticPack = shop.find_pack(id)
	var b := Button.new()
	b.name = "Featured_" + String(id)
	b.custom_minimum_size = Vector2(0, 118)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_contents = true
	b.focus_mode = Control.FOCUS_ALL  # a gamepad reaches the featured offers too
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.tooltip_text = (d.display_name if d != null else pack.display_name)
	var normal := _box(Color("#3A2318"), Color(Palette.COIN_GOLD, 0.75), 2, 18, 10)
	var hover := _box(Color("#4A2D1E"), Palette.COIN_GOLD, 3, 18, 10)
	b.add_theme_stylebox_override(&"normal", normal)
	b.add_theme_stylebox_override(&"hover", hover)
	b.add_theme_stylebox_override(&"pressed", hover)
	var ring := _box(Color(0, 0, 0, 0), Palette.VIP_GOLD, 4, 18, 10)
	ring.draw_center = false
	b.add_theme_stylebox_override(&"focus", ring)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 10)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	b.add_child(row)
	var pic := TextureRect.new()
	pic.name = "Picture"
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.texture = CosmeticThumbnails.texture_for(id)
	pic.custom_minimum_size = Vector2(100, 100)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(pic)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override(&"separation", 2)
	row.add_child(col)
	var ribbon := PanelContainer.new()
	ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ribbon.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	ribbon.add_theme_stylebox_override(&"panel", _box(Palette.COIN_GOLD, Palette.COIN_GOLD, 0, 8, 10))
	col.add_child(ribbon)
	var rl := Label.new()
	rl.theme_type_variation = &"SmallLabel"
	rl.text = "FEATURED" if d != null else "FEATURED SET"
	rl.add_theme_color_override(&"font_color", Color("#2A1A10"))
	rl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ribbon.add_child(rl)
	var name_l := Label.new()
	name_l.name = "Name"
	name_l.text = b.tooltip_text.to_upper()
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_l.clip_text = true
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_l)
	var pr: Array = _price_widget(22.0, &"SmallLabel")
	var prow: HBoxContainer = pr[0]
	prow.name = "PriceRow"
	prow.alignment = BoxContainer.ALIGNMENT_BEGIN
	prow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(pr[1] as Label).name = "Price"
	col.add_child(prow)
	b.pressed.connect(func() -> void:
		show_kind(d.kind if d != null else KIND_PACK)
		select(id))
	return b


## The inventory's WEARING column: one slot per kind with what is worn there (empty slots show
## the kind's icon faded); a click opens that kind's tab with the worn piece picked.
func _build_wardrobe() -> PanelContainer:
	wardrobe = PanelContainer.new()
	wardrobe.name = "Wardrobe"
	wardrobe.add_theme_stylebox_override(&"panel", _box(Color("#1A120C"), Color("#6B4E2E"), 2, 22, 14))
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 10)
	wardrobe.add_child(col)
	var title := Label.new()
	title.theme_type_variation = &"SmallLabel"
	title.text = "WEARING"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override(&"font_color", Palette.WARM_GOLD)
	col.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 8)
	grid.add_theme_constant_override(&"v_separation", 8)
	col.add_child(grid)
	for kind: StringName in CosmeticDef.KINDS:
		if shop.of_kind(kind).is_empty() or kind == CosmeticDef.KIND_SKIN:
			continue  # one SKIN slot: the animated skin if one is on, else the colour
		var b := Button.new()
		b.name = "Slot_" + String(kind)
		b.custom_minimum_size = Vector2(72, 72)
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.focus_mode = Control.FOCUS_ALL  # the outfit slots, on a gamepad too
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.theme_type_variation = &"SmallLabel"
		b.add_theme_font_size_override(&"font_size", 15)
		b.add_theme_color_override(&"font_color", Color(MUTED, 0.6))
		b.add_theme_color_override(&"font_hover_color", MUTED)
		b.add_theme_stylebox_override(&"normal", _box(Color("#2A1D14"), Color("#5A4128"), 2, 14, 6))
		b.add_theme_stylebox_override(&"hover", _box(Color("#36261A"), Palette.WARM_GOLD, 2, 14, 6))
		b.add_theme_stylebox_override(&"pressed", _box(Color("#36261A"), Palette.WARM_GOLD, 2, 14, 6))
		var slot_ring := _box(Color(0, 0, 0, 0), Palette.VIP_GOLD, 3, 14, 6)
		slot_ring.draw_center = false
		b.add_theme_stylebox_override(&"focus", slot_ring)
		b.pressed.connect(func() -> void:
			show_kind(kind)
			var worn: StringName = worn_in(ProfileManager.profile, kind)
			if worn != &"":
				select(worn))
		slots[kind] = b
		grid.add_child(b)
	return wardrobe


## The id worn in slot `kind` (the colour for KIND_COLOR), &"" when nothing is.
func worn_in(p: PlayerProfile, kind: StringName) -> StringName:
	if kind == CosmeticDef.KIND_COLOR:
		var skin: StringName = p.outfit.get(CosmeticDef.KIND_SKIN, &"")
		if skin != &"":
			return skin  # an animated skin covers the colour
		var c: CosmeticDef = shop.color_item(p.preferred_color if p.preferred_color >= 0 else 0)
		return c.id if c != null else &""
	return p.outfit.get(kind, &"")


## The shop's featured prices, the wardrobe's slots and the owned count.
func _refresh_places(p: PlayerProfile) -> void:
	if featured_row != null:
		for card: Node in featured_row.get_children():
			var id := StringName(String(card.name).trim_prefix("Featured_"))
			var row: Node = card.find_child("PriceRow", true, false)
			var d: CosmeticDef = shop.find(id)
			if d != null:
				_show_price(row.get_node("Price") as Label, row.get_child(1) as CoinIcon, p, d)
			elif shop.find_pack(id) != null:
				_show_pack_price(row.get_node("Price") as Label, row.get_child(1) as CoinIcon, p, shop.find_pack(id))
	for kind: StringName in slots:
		var b: Button = slots[kind]
		var worn: StringName = worn_in(p, kind)
		var title: String = str(KIND_TITLES.get(kind, kind)).capitalize()
		if worn != &"":
			b.icon = CosmeticThumbnails.texture_for(worn)
			b.text = ""
			b.modulate = Color.WHITE
			var d: CosmeticDef = shop.find(worn)
			b.tooltip_text = "%s: %s" % [title, d.display_name if d != null else String(worn)]
		else:
			# Nothing worn there: an empty slot with its name, not a faded picture (that read as
			# a greyed-out piece, Patrick 2026-11-16).
			b.icon = null
			b.text = title.to_upper()
			b.modulate = Color.WHITE
			b.tooltip_text = "%s: nothing" % title
	var owned: int = 0
	var total: int = 0
	for d: CosmeticDef in shop.items:
		if d.dev_only and not DevMode.dev_skins():
			continue
		total += 1
		if p.owns(d.id):
			owned += 1
	owned_label.text = "%d OF %d OWNED" % [owned, total]


func _draw() -> void:
	if inventory:
		# The wardrobe: vertical planks of slightly different browns, with dark seams.
		var inset: float = 18.0
		var plank: float = 120.0
		var x: float = inset
		var i: int = 0
		while x < size.x - inset:
			var w: float = minf(plank, size.x - inset - x)
			var shade: Color = Color("#22180F") if i % 3 == 0 else (Color("#1D150F") if i % 3 == 1 else Color("#251A11"))
			draw_rect(Rect2(x, 18.0, w, size.y - 36.0), shade)  # clear of the rounded corners
			if i > 0:
				draw_line(Vector2(x, 18.0), Vector2(x, size.y - 18.0), Color(0, 0, 0, 0.45), 2.0)
			x += plank
			i += 1
		return
	# The storefront's awning: deep red and cream stripes over the top edge, scalloped below.
	var x0: float = 30.0
	var x1: float = size.x - 30.0
	var stripe: float = 44.0
	var top: float = 3.0
	var h: float = 22.0
	var n: int = int(ceil((x1 - x0) / stripe))
	var w: float = (x1 - x0) / float(n)
	for i: int in n:
		var col: Color = Color("#8E2F25") if i % 2 == 0 else Color("#F1E3C6")
		var a: float = x0 + w * float(i)
		draw_rect(Rect2(a, top, w, h), col)
		draw_circle(Vector2(a + w * 0.5, top + h), w * 0.5, col)
	draw_line(Vector2(x0, top + 1.0), Vector2(x1, top + 1.0), Palette.WARM_GOLD, 3.0)


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
	b.custom_minimum_size = Vector2(76, 76)
	b.tooltip_text = str(KIND_TITLES.get(kind, kind)).capitalize()
	if TAB_ICONS.has(kind):
		b.icon = CosmeticThumbnails.texture_for(TAB_ICONS[kind], true)
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
		tab_buttons[k].set_pressed_no_signal(tab_buttons[k] == b)
	if coins_button != null:
		coins_button.set_pressed_no_signal(kind == KIND_COINS)
	# The pictures on this page first (backwards, so the first tile ends up at the front).
	var ids: Array[StringName] = []
	if kind == KIND_PACK:
		for pack: CosmeticPack in CosmeticShop.default().packs:
			ids.append(pack.id)
	elif kind != KIND_COINS:
		for d: CosmeticDef in CosmeticShop.default().of_kind(kind):
			ids.append(d.id)
		if kind == CosmeticDef.KIND_COLOR or kind == CosmeticDef.KIND_SKIN:
			var other: StringName = CosmeticDef.KIND_SKIN if kind == CosmeticDef.KIND_COLOR else CosmeticDef.KIND_COLOR
			for d: CosmeticDef in CosmeticShop.default().of_kind(other):
				ids.append(d.id)
	ids.reverse()
	for id: StringName in ids:
		CosmeticThumbnails.texture_for(id, true)


## A piece's tile, or a pack's (`d` null).
func _tile(d: CosmeticDef, pack: CosmeticPack = null) -> Button:
	var id: StringName = d.id if d != null else pack.id
	var title: String = d.display_name if d != null else pack.display_name
	var b := Button.new()
	b.name = String(id)
	b.toggle_mode = true
	b.custom_minimum_size = TILE
	b.tooltip_text = title if d != null else "%s: a set of %d pieces for Gold Coins" % [title, pack.pieces.size()]
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
	if d != null and d.level > 0:
		var badge := Label.new()
		badge.name = "Level"
		badge.theme_type_variation = &"SmallLabel"
		badge.text = "LV %d" % d.level
		badge.tooltip_text = "Free at level %d" % d.level
		badge.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 10)
		b.add_child(badge)
	var lock := LockIcon.make(24.0)
	lock.name = "Lock"
	lock.visible = false
	lock.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, 10)
	b.add_child(lock)
	var pr: Array = _price_widget(22.0, &"SmallLabel")
	var row: HBoxContainer = pr[0]
	row.name = "PriceRow"
	(pr[1] as Label).name = "Price"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)
	b.pressed.connect(_on_tile_pressed.bind(id))
	b.focus_entered.connect(func() -> void:
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):  # a click selects on release instead
			select(id))
	tiles[id] = b
	return b


## A gold pack's tile: a pile of Gold Coins, how many, and the Steam price.
func _coin_tile(c: CoinPack) -> Button:
	var b := Button.new()
	b.name = String(c.id)
	b.toggle_mode = true
	b.custom_minimum_size = TILE
	b.tooltip_text = "%s Gold Coins" % Hud._thousands(c.gold)
	SettingsPanel.style_tab(b)
	for st: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed"]:
		var sb: StyleBoxFlat = (b.get_theme_stylebox(st) as StyleBoxFlat).duplicate()
		sb.set_corner_radius_all(18)
		b.add_theme_stylebox_override(st, sb)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override(&"separation", 6)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
	b.add_child(box)
	var pile := HBoxContainer.new()
	pile.alignment = BoxContainer.ALIGNMENT_CENTER
	pile.add_theme_constant_override(&"separation", -34)
	pile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pile.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var n: int = 1 + shop.coin_packs.find(c)
	for i: int in n:
		var ci := CoinIcon.make(72.0 - float(n - 1) * 6.0, true)
		ci.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pile.add_child(ci)
	box.add_child(pile)
	var label := Label.new()
	label.name = "Name"
	label.theme_type_variation = &"HeadingLabel"
	label.add_theme_color_override(&"font_color", Palette.COIN_GOLD)
	label.text = Hud._thousands(c.gold)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(label)
	var price := Label.new()
	price.name = "Price"
	price.theme_type_variation = &"SmallLabel"
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(price)
	b.pressed.connect(select.bind(c.id))
	b.focus_entered.connect(select.bind(c.id))
	tiles[c.id] = b
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
	if d == null and shop.find_pack(id) == null and shop.find_coin_pack(id) == null:
		return
	if selected == id:
		return
	selected = id
	if d != null:
		trying[d.kind] = id
		if d.kind == CosmeticDef.KIND_COLOR:
			trying.erase(CosmeticDef.KIND_SKIN)  # a plain colour shows without the animated skin
	status_label.text = ""
	if preview != null:
		preview.face(d != null and d.kind == CosmeticDef.KIND_CAPE)
		preview.focus(d.kind if d != null else &"")
	_refresh()


## A click on a tile: picks it, or (picked already) takes that try-on back off.
func _on_tile_pressed(id: StringName) -> void:
	var d: CosmeticDef = shop.find(id)
	if d != null and selected == id and trying.get(d.kind, &"") == id:
		untry(d.kind)
	elif d != null and selected != id and trying.get(d.kind, &"") == id:
		selected = id  # stacked further back: just bring it to the front
		_refresh()
	else:
		select(id)


## Takes the try-on in slot `kind` off; the stage goes back to the whole look.
func untry(kind: StringName) -> void:
	var id: StringName = trying.get(kind, &"")
	trying.erase(kind)
	if selected == id or shop.find(selected) == null:
		selected = &""
	status_label.text = ""
	_refresh()


## RESET: no try-ons, the bean as it is worn.
func reset_look() -> void:
	trying.clear()
	selected = &""
	status_label.text = ""
	_refresh()


## The tried-on pieces that aren't worn yet.
func look_pieces() -> Array[CosmeticDef]:
	var out: Array[CosmeticDef] = []
	var p: PlayerProfile = ProfileManager.profile
	for kind: StringName in trying:
		var d: CosmeticDef = shop.find(trying[kind])
		if d != null and not _wearing(p, d):
			out.append(d)
	return out


## What the tried-on pieces not owned yet cost in Coins together (pieces Coins can't buy left out).
func look_price() -> int:
	var total: int = 0
	var p: PlayerProfile = ProfileManager.profile
	for d: CosmeticDef in look_pieces():
		if not p.owns(d.id) and d.coin_buyable():
			total += d.price
	return total


## BUY ALL (every tried-on piece Coins can buy) when some aren't owned, else WEAR ALL.
func press_look() -> void:
	var p: PlayerProfile = ProfileManager.profile
	var to_buy: Array[CosmeticDef] = []
	for d: CosmeticDef in look_pieces():
		if not p.owns(d.id) and d.coin_buyable():
			to_buy.append(d)
	if not to_buy.is_empty():
		if p.coins < look_price():
			status_label.text = "Not enough Coins for the whole look: %s more to go." % Hud._thousands(look_price() - p.coins)
			_refresh()
			return
		_confirm_buy("BUY THE WHOLE LOOK?", "%d pieces for %s Coins." % [to_buy.size(), Hud._thousands(look_price())], func() -> void:
			for d: CosmeticDef in to_buy:
				ProfileManager.buy(d.id)
			status_label.text = "Bought %d pieces! WEAR ALL puts the look on." % to_buy.size()
			Audio.play(&"cash_register", &"UI", -6.0)
			_refresh(), look_button)
		return
	var n: int = 0
	for d: CosmeticDef in look_pieces():
		if not p.owns(d.id):
			continue
		if d.kind == CosmeticDef.KIND_COLOR:
			ProfileManager.set_preferred_color(d.color_index)
			color_worn.emit(d.color_index)
			n += 1
		elif ProfileManager.wear(d.id):
			outfit_worn.emit(d.kind, d.id)
			n += 1
	status_label.text = "Your bean wears the new look." if n > 0 else ""
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


## STEAM: opens the Steam overlay to pay for the picked gold pack.
func press_steam() -> void:
	var coin_pack: CoinPack = shop.find_coin_pack(selected)
	var def: int = coin_pack.steam_item if coin_pack != null else 0
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
	status_label.text = "Thanks! Your Gold Coins show up in a moment." if ok else "Steam couldn't start the purchase. Restart Steam and try again."
	_refresh()


## A premium piece or a set paid in Gold Coins: Steam exchanges them (the answer: `_on_gold_spent`).
## Too few Gold Coins: off to the GOLD tab to get more. Enough: asks first (no refunds).
func _buy_with_gold(title: String, def: int, cost: int) -> void:
	if not SteamSvc.is_available():
		status_label.text = "Gold Coins need Steam running."
	elif SteamSvc.gold < cost:
		open_gold_shop(cost - SteamSvc.gold)
		return
	else:
		_confirm_buy("BUY %s?" % title.to_upper(), "%s Gold Coins." % Hud._thousands(cost), func() -> void:
			if SteamSvc.buy_with_gold(def, cost):
				status_label.text = "Buying %s..." % title
			else:
				status_label.text = "Can't buy that right now, try again in a moment."
			_refresh())
		return
	_refresh()


## "MORE GOLD NEEDED · BUY MORE": the GOLD tab, with the smallest pack that covers `missing` picked.
func open_gold_shop(missing: int) -> void:
	var pick: CoinPack = null
	for c: CoinPack in shop.coin_packs:
		if c.gold >= missing and (pick == null or c.gold < pick.gold):
			pick = c
	if pick == null and not shop.coin_packs.is_empty():
		pick = shop.coin_packs[-1]
	show_kind(KIND_COINS)
	if pick != null:
		select(pick.id)
		if tiles.has(pick.id):
			tiles[pick.id].grab_focus()
	status_label.text = "%s more Gold Coins needed: pick a pack, Steam handles the payment." % Hud._thousands(missing)


## Every cosmetic purchase asks first and says it can't be refunded (Patrick: "for both buys both
## currencies dialog about non refundability of the bought skin"). `on_yes` buys.
func _confirm_buy(title: String, price_text: String, on_yes: Callable, from: Control = null) -> void:
	if confirm_dialog != null and is_instance_valid(confirm_dialog) and confirm_dialog.visible:
		return
	# CANCEL hands the focus back here: to the button, never to a tile (that would pick it).
	var back: Control = from if from != null else action_button
	if back.is_visible_in_tree():
		back.grab_focus()
	var host: Node = get_parent() if get_parent() != null else self
	confirm_dialog = ConfirmDialog.ask(host, title, "%s\nCosmetics can't be refunded once bought." % price_text, "BUY", on_yes)
	for c: StringName in [&"font_color", &"font_hover_color", &"font_focus_color"]:
		confirm_dialog.yes_button.add_theme_color_override(c, Palette.COIN_GOLD)


func _on_gold_spent(ok: bool) -> void:
	if not visible:
		return
	status_label.text = "Bought! Wear it whenever you like." if ok else "That didn't go through: no Gold Coins were spent."
	if ok:
		Audio.play(&"cash_register", &"UI", -6.0)
	_refresh()


## Buys `d` with red Coins, or says why not.
func _buy_with_coins(d: CosmeticDef) -> void:
	var p: PlayerProfile = ProfileManager.profile
	match ProfileManager.buy(d.id):
		&"":
			status_label.text = "Bought %s! Wear it whenever you like." % d.display_name
			Audio.play(&"cash_register", &"UI", -6.0)
		&"owned":
			pass
		&"not_enough_coins":
			status_label.text = "Not enough Coins: %d more to go. Play matches to earn them." % (d.price - p.coins)
			Audio.play(&"ui_hover", &"UI", -8.0, 0.6)
		&"level" when d.wheel_only:
			status_label.text = "Only the Daily Spin has it."
		&"level":
			status_label.text = "Reach level %d to unlock it (you're level %d)." % [d.level, p.level]
		_:
			status_label.text = "Can't buy that right now."
	_refresh()


## BUY when not owned (asks first, as no purchase can be refunded; refused with a message when the
## Coins don't reach; too few Gold Coins opens the GOLD tab), else WEAR / TAKE OFF.
func press_action() -> void:
	var pack: CosmeticPack = shop.find_pack(selected)
	if pack != null and not ProfileManager.profile.owns_pack(pack):
		_buy_with_gold(pack.display_name, pack.steam_item, pack.gold)
		return
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
	if not p.owns(d.id) and d.premium():
		_buy_with_gold(d.display_name, d.steam_item, d.gold)
		return
	if not p.owns(d.id) and d.coin_buyable() and p.coins >= d.price:
		_confirm_buy("BUY %s?" % d.display_name.to_upper(), "%s Coins." % Hud._thousands(d.price), func() -> void: _buy_with_coins(d))
		return
	if not p.owns(d.id):
		_buy_with_coins(d)  # refused: says why
		return
	if d.kind == CosmeticDef.KIND_COLOR and not _wearing(p, d):
		# One skins page: a plain colour takes an animated skin off (else nothing would change).
		var skin: StringName = p.outfit.get(CosmeticDef.KIND_SKIN, &"")
		if skin != &"":
			ProfileManager.take_off(CosmeticDef.KIND_SKIN)
			outfit_worn.emit(CosmeticDef.KIND_SKIN, &"")
		if p.preferred_color != d.color_index:
			ProfileManager.set_preferred_color(d.color_index)
			color_worn.emit(d.color_index)
		status_label.text = "Your bean wears %s from now on." % d.display_name
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
		return p.preferred_color == d.color_index and p.outfit.get(CosmeticDef.KIND_SKIN, &"") == &""
	return p.is_worn(d.id)


## Fills a price row: "WEARING" / "OWNED" / "FREE" as words, the Steam price for real-money-only
## pieces, else the number and the Coin.
static func _show_price(label: Label, coin: CoinIcon, p: PlayerProfile, d: CosmeticDef) -> void:
	var wearing: bool = _wearing(p, d)
	coin.visible = not p.owns(d.id)
	if wearing:
		label.text = "WEARING"
	elif p.owns(d.id):
		label.text = "FREE" if d.is_free() else ("DEVELOPER" if d.dev_only else ("JACKPOT" if d.wheel_only else "OWNED"))
	elif d.premium():
		label.text = Hud._thousands(d.gold)
	elif d.wheel_only:
		label.text = "DAILY SPIN"
		coin.visible = false
	elif not d.coin_buyable():
		label.text = "LEVEL %d" % d.level
		coin.visible = false
	else:
		label.text = "%s" % Hud._thousands(d.price)
	coin.set_gold(d.premium())
	var short: bool = not p.owns(d.id) and ((d.coin_buyable() and p.coins < d.price) or (d.premium() and SteamSvc.gold < d.gold))
	# Short of money keeps the currency's colour, only dimmed: a red number next to a Gold Coin read
	# as a red-coin price (Patrick 2026-11-15).
	var cur: Color = Palette.COIN_GOLD if d.premium() else (Palette.COIN_RED if d.coin_buyable() else Palette.VIP_GOLD)
	label.add_theme_color_override(&"font_color", Palette.VIP_GOLD if wearing else (Palette.CREAM if p.owns(d.id) else cur))
	label.modulate = Color(1, 1, 1, 0.6) if short else Color.WHITE
	coin.modulate = Color(1, 1, 1, 0.6) if short else Color.WHITE


## Whether piece `d` can be had right now: enough Coins, or enough Gold for a premium one.
static func _can_get_now(p: PlayerProfile, d: CosmeticDef) -> bool:
	if d.premium():
		return SteamSvc.is_available() and SteamSvc.gold >= d.gold
	return d.coin_buyable() and p.coins >= d.price


func _refresh() -> void:
	if action_button == null:
		return
	var p: PlayerProfile = ProfileManager.profile
	coins_label.text = Hud._thousands(p.coins)
	gold_label.text = Hud._thousands(SteamSvc.gold)
	for id: StringName in tiles:
		var d: CosmeticDef = shop.find(id)
		var b: Button = tiles[id]
		b.visible = (not inventory or (d != null and p.owns(id))) and (d == null or not d.dev_only or DevMode.dev_skins())
		b.set_pressed_no_signal(id == selected or (d != null and trying.get(d.kind, &"") == id))
		var badge: Node = b.get_node_or_null("Level")
		if badge != null:
			(badge as Control).visible = d != null and not p.owns(id)
		# Out of reach for now (level not reached and no Coins price, or too few Coins): a lock in
		# the corner, the picture stays bright (a dimmed bean read as a broken one).
		var locked: bool = d != null and not p.owns(id) and not _can_get_now(p, d)
		var lock: Control = b.get_node_or_null("Lock") as Control
		if lock != null:
			lock.visible = locked
		if badge != null:
			(badge as Label).add_theme_color_override(&"font_color", MUTED if locked else Palette.VIP_GOLD)
		var coin_pack: CoinPack = shop.find_coin_pack(id)
		if coin_pack != null:
			var pl: Label = b.find_child("Price", true, false) as Label
			pl.text = money_text(coin_pack.steam_item, coin_pack.cents)
			pl.add_theme_color_override(&"font_color", Palette.CREAM)
			continue
		var row: Node = b.find_child("PriceRow", true, false)
		# The wardrobe has no prices: only WEARING on what is worn.
		(row as Control).visible = not inventory or (d != null and _wearing(p, d))
		if d != null:
			_show_price(row.get_node("Price") as Label, row.get_child(1) as CoinIcon, p, d)
		else:
			_show_pack_price(row.get_node("Price") as Label, row.get_child(1) as CoinIcon, p, shop.find_pack(id))
	_refresh_look(p)
	_refresh_places(p)
	var pack: CosmeticPack = shop.find_pack(selected)
	if pack != null:
		_refresh_pack(p, pack)
		return
	var coin_pack: CoinPack = shop.find_coin_pack(selected)
	if coin_pack != null:
		item_name.text = "%s GOLD COINS" % Hud._thousands(coin_pack.gold)
		item_kind.text = "FOR PREMIUM PIECES AND SETS"
		price_row.visible = true
		price_label.text = money_text(coin_pack.steam_item, coin_pack.cents)
		price_label.add_theme_color_override(&"font_color", Palette.COIN_GOLD)
		price_coin.visible = false
		action_button.visible = false
		_show_steam_button(true, coin_pack.steam_item, coin_pack.cents, "BUY WITH STEAM")
		return
	var sel: CosmeticDef = shop.find(selected)
	if sel == null:
		# Nothing picked: the bean as worn, with whatever is still tried on.
		_dress_preview(p)
		steam_button.visible = false
		action_button.visible = true
		action_button.disabled = true
		action_button.text = "PICK SOMETHING"
		item_name.text = "YOUR LOOK" if not look_pieces().is_empty() else ""
		item_kind.text = ""
		price_row.visible = false
		return
	item_name.text = sel.display_name.to_upper()
	item_kind.text = str(KIND_TITLES.get(sel.kind, "")).trim_suffix("S").replace("TROUSER", "TROUSERS")
	if sel.level > 0 and not p.owns(sel.id):
		item_kind.text += " · FREE AT LEVEL %d" % sel.level
	price_row.visible = true
	_show_price(price_label, price_coin, p, sel)
	if inventory and p.owns(sel.id):
		price_row.visible = false  # the wardrobe has no prices
	_dress_preview(p)
	action_button.disabled = false
	action_button.visible = true
	steam_button.visible = false
	if not p.owns(sel.id) and sel.premium():
		if not SteamSvc.is_available():
			action_button.text = "GOLD NEEDS STEAM"
			action_button.disabled = true
		elif SteamSvc.gold < sel.gold:
			action_button.text = "%s MORE GOLD NEEDED · BUY MORE" % Hud._thousands(sel.gold - SteamSvc.gold)
		else:
			action_button.text = "BUY FOR %s GOLD" % Hud._thousands(sel.gold)
	elif not p.owns(sel.id) and sel.wheel_only:
		action_button.text = "ONLY ON THE DAILY SPIN"
		action_button.disabled = true
	elif not p.owns(sel.id) and not sel.coin_buyable():
		action_button.text = "LEVEL PASS · LEVEL %d" % sel.level  # only levelling up unlocks it
		action_button.disabled = true
	elif not p.owns(sel.id) and p.coins < sel.price:
		action_button.text = "%s MORE COINS NEEDED" % Hud._thousands(sel.price - p.coins)
		action_button.disabled = true
	elif not p.owns(sel.id):
		action_button.text = "BUY"
	elif sel.kind == CosmeticDef.KIND_COLOR and p.preferred_color == sel.color_index:
		action_button.text = "WEARING"
		action_button.disabled = true
	elif sel.kind in CosmeticDef.OUTFIT_KINDS and p.is_worn(sel.id):
		action_button.text = "TAKE OFF"
	else:
		action_button.text = "WEAR"


## The preview: what the bean wears, with every try-on on top.
func _dress_preview(p: PlayerProfile) -> void:
	var color: int = p.preferred_color if p.preferred_color >= 0 else 0
	var dress: Dictionary = p.outfit.duplicate()
	for kind: StringName in trying:
		var d: CosmeticDef = shop.find(trying[kind])
		if d == null:
			continue
		if d.kind == CosmeticDef.KIND_COLOR:
			color = d.color_index
		elif d.kind in CosmeticDef.OUTFIT_KINDS:
			dress[d.kind] = d.id
	if trying.has(CosmeticDef.KIND_COLOR) and not trying.has(CosmeticDef.KIND_SKIN):
		dress.erase(CosmeticDef.KIND_SKIN)
	preview.set_bean_color(Palette.player_color(color))
	if preview.outfit != dress:
		preview.set_outfit(dress)


## The look row: shown once two or more pieces are tried on (or one and nothing is picked), with
## their total and BUY ALL / WEAR ALL, and RESET.
func _refresh_look(p: PlayerProfile) -> void:
	var pieces: Array[CosmeticDef] = look_pieces()
	var on: bool = shop.find_pack(selected) == null and shop.find_coin_pack(selected) == null \
		and (pieces.size() >= 2 or (pieces.size() == 1 and selected == &""))
	look_label.get_parent().visible = on
	if not on:
		return
	var total: int = look_price()
	var unbuyable: int = 0
	var to_buy: int = 0
	for d: CosmeticDef in pieces:
		if not p.owns(d.id):
			if d.coin_buyable():
				to_buy += 1
			else:
				unbuyable += 1
	look_label.text = "TRYING ON %d" % pieces.size()
	if to_buy > 0:
		look_label.text += " · %s COINS TOGETHER" % Hud._thousands(total)
	if unbuyable > 0:
		look_label.text += " · %d NEED GOLD OR A LEVEL" % unbuyable
	look_button.visible = true
	if to_buy > 0:
		look_button.text = "BUY ALL · %s" % Hud._thousands(total)
		look_button.disabled = p.coins < total
		look_button.tooltip_text = "%s more Coins needed" % Hud._thousands(total - p.coins) if p.coins < total else ""
	else:
		look_button.text = "WEAR ALL"
		look_button.tooltip_text = ""
		look_button.disabled = pieces.size() == unbuyable


## A pack's tile price: OWNED when every piece is, else the Steam price.
static func _show_pack_price(label: Label, coin: CoinIcon, p: PlayerProfile, pack: CosmeticPack) -> void:
	var owned: bool = p.owns_pack(pack)
	coin.visible = not owned
	coin.set_gold(true)
	label.text = "OWNED" if owned else Hud._thousands(pack.gold)
	var short: bool = not owned and SteamSvc.gold < pack.gold
	label.add_theme_color_override(&"font_color", Palette.CREAM if owned else Palette.COIN_GOLD)
	label.modulate = Color(1, 1, 1, 0.6) if short else Color.WHITE
	coin.modulate = Color(1, 1, 1, 0.6) if short else Color.WHITE


## The stage for a pack: the bean in the whole outfit, its price and what it saves; WEAR ALL once
## it is owned.
func _refresh_pack(p: PlayerProfile, pack: CosmeticPack) -> void:
	item_name.text = pack.display_name.to_upper()
	item_kind.text = "SET OF %d PIECES" % pack.pieces.size()
	price_row.visible = true
	_show_pack_price(price_label, price_coin, p, pack)
	var worn_color: int = p.preferred_color if p.preferred_color >= 0 else 0
	preview.set_bean_color(Palette.player_color(worn_color))
	var dress: Dictionary = pack_outfit(pack)
	if preview.outfit != dress:
		preview.set_outfit(dress)
	var owned: bool = p.owns_pack(pack)
	action_button.visible = true
	action_button.disabled = false
	steam_button.visible = false
	if owned:
		action_button.text = "WEAR ALL"
	elif not SteamSvc.is_available():
		action_button.text = "GOLD NEEDS STEAM"
		action_button.disabled = true
	elif SteamSvc.gold < pack.gold:
		action_button.text = "%s MORE GOLD NEEDED · BUY MORE" % Hud._thousands(pack.gold - SteamSvc.gold)
	else:
		action_button.text = "BUY FOR %s GOLD" % Hud._thousands(pack.gold)


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
	var cols: int = clampi(int(floor((w + 14.0) / (TILE.x + 14.0))), 2, 8)
	for scroll: Node in tabs.get_children():
		var grid: GridContainer = scroll.get_node_or_null("Grid") as GridContainer
		if grid != null:
			grid.columns = cols
			# The tiles share the whole width (no empty strip to the right).
			var tw: float = maxf(TILE.x, floor((w - 14.0 * float(cols - 1)) / float(cols)))
			for t: Node in grid.get_children():
				(t as Control).custom_minimum_size.x = tw


## Shop (everything) or inventory (only what is owned).
func set_inventory(on: bool) -> void:
	inventory = on
	title_label.text = "MY COSMETICS" if on else "SHOP"
	switch_button.text = "OPEN SHOP" if on else "MY COSMETICS"
	add_theme_stylebox_override(&"panel", _wardrobe_style() if on else _panel_style())
	wallet.visible = not on
	owned_label.visible = on
	featured_row.visible = not on
	wardrobe.visible = on
	stage.add_theme_stylebox_override(&"panel", _stage_style(on))
	stage.custom_minimum_size.x = 440 if on else 520
	stage.size_flags_stretch_ratio = 0.6 if on else 0.8
	hint_label.text = ("Everything you own. Pick a piece to try it on, WEAR puts it on; the slots on the left of the grid show what you wear now." if on
		else "Red Coins come from playing matches and every level up, Gold Coins only with + through Steam (for premium pieces and sets). Both only buy cosmetics: the tables take $, which starts fresh every match.")
	queue_redraw()
	if tab_buttons.has(KIND_PACK):
		tab_buttons[KIND_PACK].visible = not on
	var sel: CosmeticDef = shop.find(selected)
	if on and (sel == null or not ProfileManager.profile.owns(sel.id)):
		selected = &""
		trying.clear()
		if tabs != null and tab_buttons.get(KIND_PACK, null) != null and tabs.current_tab == int(tab_buttons[KIND_PACK].get_meta(&"tab")):
			show_kind(CosmeticDef.KIND_COLOR)
		if tabs != null and tab_buttons.get(KIND_COINS, null) != null and tabs.current_tab == int(tab_buttons[KIND_COINS].get_meta(&"tab")):
			show_kind(CosmeticDef.KIND_COLOR)
	status_label.text = ""
	_refresh()


## Opens the shop, or with `as_inventory` the player's own cosmetics.
func open(as_inventory: bool = false) -> void:
	set_inventory(as_inventory)
	SteamSvc.refresh_inventory()  # bought on another PC, or in the Steam store
	var p: PlayerProfile = ProfileManager.profile
	var worn: CosmeticDef = shop.color_item(p.preferred_color)
	selected = &""
	trying.clear()
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
	sb.content_margin_top = 64  # room for the awning
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 24
	return sb


## The inventory's frame: a dark wood wardrobe instead of the shop's casino red.
static func _wardrobe_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#1D150F")
	sb.border_color = Color("#7A5A34")
	sb.set_border_width_all(6)
	sb.set_corner_radius_all(18)
	sb.set_content_margin_all(36)
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 24
	return sb


static func _stage_style(wood: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#2B1E14", 0.92) if wood else Color("#2E1C1C")
	sb.border_color = Color("#7A5A34") if wood else Color(Palette.WARM_GOLD, 0.35)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(22)
	sb.set_content_margin_all(22)
	return sb
