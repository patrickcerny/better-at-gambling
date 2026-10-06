class_name ShopPanel
extends PanelContainer
## The Gift Shop counter: this round's four offers (name, rarity, what it does, price). One buy
## per player per casino round. Keys 1–4 or a click buy, Esc closes. Sends `shop_buy`; the server
## checks the price, the distance and the one-per-round rule.

signal closed

var state: ClientMatchState
var local_id: int = -1

var _rows: VBoxContainer
var _note: Label
var _close: Button
var _bought: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -430
	offset_right = 430
	offset_top = -310
	offset_bottom = 310
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 10)
	add_child(v)
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text = "GIFT SHOP"
	v.add_child(title)
	_note = Label.new()
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.add_theme_color_override(&"font_color", Palette.WARM_GOLD)
	v.add_child(_note)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override(&"separation", 6)
	v.add_child(_rows)
	_close = Button.new()
	_close.text = "Close [Esc]"
	_close.pressed.connect(close_panel)
	v.add_child(_close)


func bind(p_state: ClientMatchState, p_local_id: int) -> void:
	state = p_state
	local_id = p_local_id
	state.shop_changed.connect(_refresh)
	state.players_changed.connect(func() -> void:
		if visible:
			_refresh())


func open() -> void:
	visible = true
	_close.text = "Close %s" % InputGlyphs.hint(&"ui_cancel")
	_refresh()
	if _rows.get_child_count() > 0:
		(_rows.get_child(0) as Control).grab_focus()


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
	var res: Dictionary = Net.send_intent(Intents.make(&"shop_buy", {"index": index}))
	if res["ok"]:
		_bought = true
		close_panel()
	else:
		_note.text = ItemController.rejection_text(res["error"])


func _refresh() -> void:
	if state == null or _rows == null:
		return
	_bought = bool(Net.request_private_snapshot().get("items", {}).get("shop_bought", false))
	var money: int = state.balance(local_id)
	_note.text = "You already bought something this round. New stock after the next minigame." if _bought else "One item per round  ·  you have $%s" % Hud._thousands(money)
	for c: Node in _rows.get_children():
		c.queue_free()
	for i: int in state.shop_offers.size():
		var o: Dictionary = state.shop_offers[i]
		var id: StringName = StringName(o["item"])
		var price: int = int(o["price"])
		var rarity: int = clampi(int(o.get("rarity", 0)), 0, 2)
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 96)
		b.disabled = _bought or money < price
		b.pressed.connect(buy.bind(i))
		var row := HBoxContainer.new()
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 18
		row.offset_right = -20
		row.offset_top = 8
		row.offset_bottom = -12
		row.add_theme_constant_override(&"separation", 16)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(row)
		var key := Label.new()
		key.text = str(i + 1)
		key.theme_type_variation = &"HeadingLabel"
		key.custom_minimum_size = Vector2(34, 0)
		key.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		key.add_theme_color_override(&"font_color", Palette.WARM_GOLD)
		row.add_child(key)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.alignment = BoxContainer.ALIGNMENT_CENTER
		info.add_theme_constant_override(&"separation", 0)
		row.add_child(info)
		var head := HBoxContainer.new()
		head.add_theme_constant_override(&"separation", 12)
		info.add_child(head)
		var n := Label.new()
		n.text = RewardPanel.item_name(id)
		n.add_theme_font_size_override(&"font_size", 28)
		head.add_child(n)
		var tag := Label.new()
		tag.text = RewardPanel.RARITY_NAMES[rarity]
		tag.theme_type_variation = &"SmallLabel"
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tag.add_theme_color_override(&"font_color", RewardPanel.RARITY_COLORS[rarity])
		head.add_child(tag)
		var d := Label.new()
		d.text = RewardPanel.item_description(id)
		d.theme_type_variation = &"MutedLabel"
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(560, 0)
		info.add_child(d)
		var cost := Label.new()
		cost.text = "$%s" % Hud._thousands(price)
		cost.theme_type_variation = &"MoneyLabel"
		cost.add_theme_font_size_override(&"font_size", 36)
		cost.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cost.add_theme_color_override(&"font_color", Palette.VIP_GOLD if money >= price else Palette.LOSS_RED)
		row.add_child(cost)
		for c: Node in [key, info, head, n, tag, d, cost]:
			(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		if b.disabled:
			row.modulate = Color(1, 1, 1, 0.45)
		_rows.add_child(b)
	if state.shop_offers.is_empty():
		var l := Label.new()
		l.text = "Sold out. New stock after the next minigame."
		_rows.add_child(l)
