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
var _bought: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -430
	offset_right = 430
	offset_top = -280
	offset_bottom = 280
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
	_note.theme_type_variation = &"HeadingLabel"
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	v.add_child(_note)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override(&"separation", 6)
	v.add_child(_rows)
	var close := Button.new()
	close.text = "Close [Esc]"
	close.pressed.connect(close_panel)
	v.add_child(close)


func bind(p_state: ClientMatchState, p_local_id: int) -> void:
	state = p_state
	local_id = p_local_id
	state.shop_changed.connect(_refresh)
	state.players_changed.connect(func() -> void:
		if visible:
			_refresh())


func open() -> void:
	visible = true
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
	_note.text = "You already bought something this round. New stock after the next minigame." if _bought else "Pick one item per round. You have $%d." % money
	for c: Node in _rows.get_children():
		c.queue_free()
	for i: int in state.shop_offers.size():
		var o: Dictionary = state.shop_offers[i]
		var id: StringName = StringName(o["item"])
		var price: int = int(o["price"])
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 64)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.text = "[%d]  %s  (%s)   $%d\n%s" % [i + 1, RewardPanel.item_name(id), ["common", "rare", "legendary"][clampi(int(o.get("rarity", 0)), 0, 2)], price, RewardPanel.item_description(id)]
		b.add_theme_font_size_override(&"font_size", 18)
		b.disabled = _bought or money < price
		b.pressed.connect(buy.bind(i))
		_rows.add_child(b)
	if state.shop_offers.is_empty():
		var l := Label.new()
		l.text = "Sold out. New stock after the next minigame."
		_rows.add_child(l)
