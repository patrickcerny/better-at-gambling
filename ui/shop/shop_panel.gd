class_name ShopPanel
extends PanelContainer
## The Gift Shop counter window (reworked 2026-11-15, Patrick: "rework that UI, it looks super
## ugly"): this round's four offers as cards in a row under a red-and-cream awning like the booth's,
## each with the item's 3D picture on a velvet plate (`ItemThumbnails`), its rarity, name, what it
## does and the price, the number key in a brass badge. Cards you can't afford show the price in red;
## once you bought this round every card is marked SOLD. One buy per player per casino round. Keys
## 1–4 or a click buy, Esc closes. Sends `shop_buy`; the server checks the price, the distance and
## the one-per-round rule. Online the answer is a round trip away: the window stays open
## ("Buying…") until the server confirms (`shop_bought`) or refuses (`intent_rejected`), so a
## refused buy is shown where it was made.

signal closed

const CARD_SIZE: Vector2 = Vector2(250, 452)
const THUMB: float = 150.0

var state: ClientMatchState
var local_id: int = -1

## The offer cards (Buttons), left to right.
var _rows: HBoxContainer
var _note: Label
var _cash: Label
var _close: Button
var _thumbs: ItemThumbnails
var _bought: bool = false
## Waiting for the server's answer to a buy (online).
var _pending: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -560
	offset_right = 560
	offset_top = -340
	offset_bottom = 340
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	visible = false
	add_theme_stylebox_override(&"panel", _frame_style())
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 0)
	add_child(v)
	# The booth's awning across the top.
	var awning := ShopAwning.new()
	awning.custom_minimum_size = Vector2(0, 46)
	v.add_child(awning)
	var body := MarginContainer.new()
	for side: String in ["left", "right"]:
		body.add_theme_constant_override("margin_" + side, 26)
	body.add_theme_constant_override(&"margin_top", 10)
	body.add_theme_constant_override(&"margin_bottom", 22)
	v.add_child(body)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override(&"separation", 12)
	body.add_child(inner)
	# Title row: the sign in the middle, your cash on the right.
	var top := HBoxContainer.new()
	inner.add_child(top)
	var left_pad := Control.new()
	left_pad.custom_minimum_size = Vector2(220, 0)
	top.add_child(left_pad)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override(&"separation", -4)
	top.add_child(titles)
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text = "GIFT SHOP"
	title.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	titles.add_child(title)
	_note = Label.new()
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.add_theme_color_override(&"font_color", Palette.CREAM.darkened(0.1))
	_note.add_theme_font_size_override(&"font_size", 22)
	titles.add_child(_note)
	var cash_box := PanelContainer.new()
	cash_box.custom_minimum_size = Vector2(220, 0)
	cash_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cash_box.add_theme_stylebox_override(&"panel", _pill_style())
	top.add_child(cash_box)
	var cash_v := VBoxContainer.new()
	cash_v.add_theme_constant_override(&"separation", -6)
	cash_box.add_child(cash_v)
	var cash_cap := Label.new()
	cash_cap.text = "YOUR CASH"
	cash_cap.theme_type_variation = &"SmallLabel"
	cash_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cash_cap.add_theme_color_override(&"font_color", Palette.WARM_GOLD)
	cash_v.add_child(cash_cap)
	_cash = Label.new()
	_cash.theme_type_variation = &"MoneyLabel"
	_cash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cash.add_theme_font_size_override(&"font_size", 34)
	cash_v.add_child(_cash)
	# The cards.
	_rows = HBoxContainer.new()
	_rows.alignment = BoxContainer.ALIGNMENT_CENTER
	_rows.add_theme_constant_override(&"separation", 16)
	inner.add_child(_rows)
	_close = Button.new()
	_close.text = "Close [Esc]"
	_close.custom_minimum_size = Vector2(240, 0)
	_close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_close.pressed.connect(close_panel)
	inner.add_child(_close)


func bind(p_state: ClientMatchState, p_local_id: int) -> void:
	state = p_state
	local_id = p_local_id
	state.shop_changed.connect(_refresh)
	state.players_changed.connect(func() -> void:
		if visible:
			_refresh())
	if not Net.event_received.is_connected(_on_event):
		Net.event_received.connect(_on_event)


func _exit_tree() -> void:
	if Net.event_received.is_connected(_on_event):
		Net.event_received.disconnect(_on_event)


func open() -> void:
	visible = true
	_pending = false
	_close.text = "Close %s" % InputGlyphs.hint(&"ui_cancel")
	_refresh()
	_focus_row(0)


func close_panel() -> void:
	if visible:
		visible = false
		closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		close_panel()
	elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var k: Key = (event as InputEventKey).physical_keycode
		if k >= KEY_1 and k <= KEY_4:
			get_viewport().set_input_as_handled()
			buy(int(k - KEY_1))


func buy(index: int) -> void:
	if state == null or index >= state.shop_offers.size():
		return
	if _pending:
		return
	var res: Dictionary = Net.send_intent(Intents.make(&"shop_buy", {"index": index}))
	if res["ok"] and bool(res.get("pending", false)):
		_pending = true  # online: wait for the server's word before closing
		_note.text = "Buying…"
		_set_buttons_enabled(false)
	elif res["ok"]:
		_bought = true
		close_panel()
	else:
		_note.text = ItemController.rejection_text(res["error"])


## The server's answer to a pending buy: bought closes the window, a refusal says why.
func _on_event(ev: Dictionary) -> void:
	if not _pending or int(ev.get("player", -1)) != local_id:
		return
	match StringName(ev.get("type", &"")):
		&"shop_bought":
			_pending = false
			_bought = true
			close_panel()
		&"intent_rejected":
			if StringName(ev.get("intent", &"")) != &"shop_buy":
				return
			_pending = false
			_refresh()
			_note.text = ItemController.rejection_text(StringName(ev.get("error", &"")))


func _set_buttons_enabled(on: bool) -> void:
	for c: Node in _rows.get_children():
		if c is Button:
			(c as Button).disabled = not on


func _refresh() -> void:
	if state == null or _rows == null:
		return
	if _pending:
		return  # keep "Buying…" until the server answers
	_bought = bool(Net.request_private_snapshot().get("items", {}).get("shop_bought", false))
	var money: int = state.balance(local_id)
	_note.text = "You already bought something this round. New stock after the next minigame." if _bought else "One souvenir per round. Pick wisely."
	_cash.text = "$%s" % Hud._thousands(money)
	if _thumbs == null and is_inside_tree():
		_thumbs = ItemThumbnails.new()
		add_child(_thumbs)
	# Which card had the focus, so a refresh (money or stock changed) does not drop a pad player's focus.
	var focused: int = -1
	var owner_now: Control = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var old_rows: Array[Node] = _rows.get_children()
	for i: int in old_rows.size():
		var c: Node = old_rows[i]
		if owner_now != null and (c == owner_now or c.is_ancestor_of(owner_now)):
			focused = i
		_rows.remove_child(c)  # out of the list now, so the new cards take indices 0..n at once
		c.queue_free()
	for i: int in state.shop_offers.size():
		_rows.add_child(_card(i, state.shop_offers[i], money))
	if state.shop_offers.is_empty():
		var l := Label.new()
		l.text = "Sold out. New stock after the next minigame."
		l.custom_minimum_size = Vector2(0, 200)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_rows.add_child(l)
	if focused >= 0 and visible:
		_focus_row(focused)


## One offer card: key badge, 3D picture on a velvet plate, rarity, name, what it does, price.
func _card(i: int, o: Dictionary, money: int) -> Button:
	var id: StringName = StringName(o["item"])
	var price: int = int(o["price"])
	var rarity: int = clampi(int(o.get("rarity", 0)), 0, 2)
	var tint: Color = RewardPanel.RARITY_COLORS[rarity]
	var affordable: bool = money >= price
	var b := Button.new()
	b.name = "Offer%d" % i
	b.custom_minimum_size = CARD_SIZE
	b.disabled = _bought or not affordable
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(buy.bind(i))
	b.add_theme_stylebox_override(&"normal", _card_style(tint, false))
	b.add_theme_stylebox_override(&"hover", _card_style(tint, true))
	b.add_theme_stylebox_override(&"focus", _card_style(tint, true))
	b.add_theme_stylebox_override(&"pressed", _card_style(tint, true))
	b.add_theme_stylebox_override(&"disabled", _card_style(tint.darkened(0.5), false))
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 14
	v.offset_right = -14
	v.offset_top = 14
	v.offset_bottom = -14
	v.add_theme_constant_override(&"separation", 4)
	b.add_child(v)
	# The picture on its plate, the key badge in the corner.
	var plate := PanelContainer.new()
	plate.custom_minimum_size = Vector2(0, THUMB + 12)
	plate.add_theme_stylebox_override(&"panel", _plate_style(tint))
	v.add_child(plate)
	var pic := TextureRect.new()
	pic.name = "Icon"
	pic.texture = ItemThumbnails.texture_for(id)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.custom_minimum_size = Vector2(THUMB, THUMB)
	plate.add_child(pic)
	var badge := Label.new()
	badge.text = str(i + 1)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.custom_minimum_size = Vector2(38, 38)
	badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	badge.add_theme_font_size_override(&"font_size", 24)
	badge.add_theme_color_override(&"font_color", Palette.CASINO_BLACK)
	badge.add_theme_stylebox_override(&"normal", _badge_style())
	plate.add_child(badge)
	var tag := Label.new()
	tag.text = RewardPanel.RARITY_NAMES[rarity]
	tag.theme_type_variation = &"SmallLabel"
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_color_override(&"font_color", tint)
	v.add_child(tag)
	var n := Label.new()
	n.text = RewardPanel.item_name(id)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	n.add_theme_font_size_override(&"font_size", 28)
	n.add_theme_color_override(&"font_color", Palette.CREAM)
	v.add_child(n)
	# What the item does, readable at a glance (Patrick: "item descriptions also in the shop").
	var d := Label.new()
	d.name = "Description"
	d.text = RewardPanel.item_description(id)
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.size_flags_vertical = Control.SIZE_EXPAND_FILL
	d.add_theme_font_size_override(&"font_size", 18)
	d.add_theme_color_override(&"font_color", Palette.CREAM.darkened(0.22))
	v.add_child(d)
	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(0, 2)
	rule.color = Color(Palette.WARM_GOLD, 0.45)
	v.add_child(rule)
	var cost := Label.new()
	cost.name = "Price"
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost.theme_type_variation = &"MoneyLabel"
	cost.add_theme_font_size_override(&"font_size", 40)
	if _bought:
		cost.text = "SOLD"
		cost.add_theme_color_override(&"font_color", Palette.CREAM.darkened(0.4))
	else:
		cost.text = "$%s" % Hud._thousands(price)
		cost.add_theme_color_override(&"font_color", Palette.VIP_GOLD if affordable else Palette.LOSS_RED)
	v.add_child(cost)
	var hint := Label.new()
	hint.theme_type_variation = &"SmallLabel"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.text = "ALREADY BOUGHT THIS ROUND" if _bought else ("PRESS %d OR CLICK TO BUY" % (i + 1) if affordable else "NOT ENOUGH CASH")
	hint.add_theme_color_override(&"font_color", Palette.WARM_GOLD if affordable and not _bought else Palette.CREAM.darkened(0.45))
	v.add_child(hint)
	for c: Node in b.find_children("*", "Control", true, false):
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	if b.disabled:
		v.modulate = Color(1, 1, 1, 0.55)
	return b


static func _frame_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Palette.CASINO_BLACK.lerp(Palette.VIP_BURGUNDY, 0.22), 0.97)
	sb.border_color = Palette.WARM_GOLD
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(14)
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 18
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb


static func _card_style(tint: Color, lit: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.WARM_CHARCOAL.lerp(Palette.WARM_GOLD, 0.12) if lit else Palette.WARM_CHARCOAL
	sb.border_color = Palette.VIP_GOLD if lit else tint.darkened(0.15)
	sb.set_border_width_all(4 if lit else 2)
	sb.border_width_top = 8
	sb.set_corner_radius_all(12)
	if lit:
		sb.shadow_color = Color(Palette.WARM_GOLD, 0.35)
		sb.shadow_size = 10
	return sb


static func _plate_style(tint: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.VIP_BURGUNDY.darkened(0.15)
	sb.border_color = Color(tint, 0.5)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	return sb


static func _badge_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.WARM_GOLD
	sb.border_color = Palette.VIP_GOLD.lightened(0.3)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(19)
	return sb


static func _pill_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Palette.CASINO_BLACK, 0.85)
	sb.border_color = Color(Palette.WARM_GOLD, 0.6)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_top = 4
	sb.content_margin_bottom = 6
	return sb


## Focuses row `index` if it can be bought, else the first row that can, else the close button.
func _focus_row(index: int) -> void:
	if not visible or not is_inside_tree():
		return
	var rows: Array[Node] = _rows.get_children()
	var order: Array[Node] = []
	if index >= 0 and index < rows.size():
		order.append(rows[index])
	order.append_array(rows)
	for c: Node in order:
		if c is Button and not (c as Button).disabled:
			(c as Button).grab_focus()
			return
	_close.grab_focus()
