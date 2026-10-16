class_name ScratchUi
extends StationUi
## Scratch-card kiosk overlay: the card big in the middle of the screen (`ScratchCardView`) and a
## strip at the bottom with the three cards for sale and REVEAL ALL. Buying sends `place_bet
## {tier}`; the server's card arrives in the station state and goes under fresh foil here. Scratch
## it with the mouse (or REVEAL ALL / Enter); once the whole card is bare the prize stamp shows and
## `action reveal` tells the server, which pays. A card the server paid without us (walked away,
## left too long) is scratched open on its own; a refunded card goes back to the sample.

const STRIP_WIDTH: float = 820.0
const CARD_TOP: float = 16.0

var card_view: ScratchCardView
var buy_buttons: Array[Button] = []
var reveal_btn: Button
var info_label: Label
## The card on screen: its serial at the kiosk (−1 = none), symbols, tier and price.
var shown_serial: int = -1
var shown_card: Array[int] = []
var shown_tier: int = 0
var shown_price: int = 0
## The card on screen is bare (the prize shows), and the server has been told.
var revealed: bool = false
var reported: bool = false
## Tier the sample card shows while nothing is bought (the last one bought or hovered).
var preview_tier: int = 0


func _init() -> void:
	game_title = "SCRATCH CARDS"


func _panel_height() -> float:
	return 170.0


## The card needs the mouse: the head stays put while you are at the counter.
func wants_camera_lock() -> bool:
	return true


func _build() -> void:
	panel.offset_left = -STRIP_WIDTH * 0.5
	panel.offset_right = STRIP_WIDTH * 0.5
	body.add_theme_constant_override(&"separation", 6)
	title.visible = false  # the card and the board say what it is
	status_label.add_theme_font_size_override(&"font_size", 22)
	var row := HBoxContainer.new()
	row.name = "BuyRow"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 10)
	body.add_child(row)
	for t: int in Registry.balance.scratch_prices.size():
		var b := Button.new()
		b.name = "Buy%d" % t
		b.custom_minimum_size = Vector2(170, 60)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override(&"font_size", 18)
		var tier: int = t
		b.pressed.connect(func() -> void: buy(tier))
		b.mouse_entered.connect(func() -> void: _hover(tier))
		row.add_child(b)
		buy_buttons.append(b)
	reveal_btn = Button.new()
	reveal_btn.name = "RevealAll"
	reveal_btn.theme_type_variation = &"ActionButton"
	reveal_btn.custom_minimum_size = Vector2(190, 60)
	reveal_btn.focus_mode = Control.FOCUS_NONE
	reveal_btn.pressed.connect(reveal_all)
	row.add_child(reveal_btn)
	info_label = Label.new()
	info_label.name = "Info"
	info_label.theme_type_variation = &"SmallLabel"
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_label.add_theme_color_override(&"font_color", Palette.CREAM)
	body.add_child(info_label)
	card_view = ScratchCardView.new()
	card_view.name = "Card"
	card_view.anchor_left = 0.5
	card_view.anchor_right = 0.5
	card_view.offset_left = -ScratchCardView.CARD_SIZE.x * 0.5
	card_view.offset_right = ScratchCardView.CARD_SIZE.x * 0.5
	card_view.offset_top = CARD_TOP
	card_view.offset_bottom = CARD_TOP + ScratchCardView.CARD_SIZE.y
	add_child(card_view)
	card_view.all_revealed.connect(_on_all_revealed)


func _on_open() -> void:
	shown_serial = -1
	shown_card = []
	revealed = false
	reported = false
	var last: Dictionary = pub.get("last", {})
	var c: Array = pub.get("card", [])
	if c.is_empty() and not last.is_empty() and int(last.get("tier", -1)) >= 0:
		# Back at the counter after a card paid: it lies there scratched.
		shown_tier = int(last["tier"])
		shown_price = int(last.get("stake", 0))
		shown_card = _ints(last.get("card", []))
		card_view.show_revealed(shown_card, shown_tier, shown_price)
		revealed = true
		reported = true
		_show_prize()
	else:
		_preview()
	_relabel()


func _relabel() -> void:
	reveal_btn.text = "REVEAL ALL  [%s]" % InputGlyphs.keys(&"bet_confirm")
	var prices: Array[int] = _prices()
	for t: int in buy_buttons.size():
		buy_buttons[t].text = "$%d\n%s" % [prices[t], ScratchStation.TIER_NAMES[t]]


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event.is_action_pressed(&"bet_confirm"):
		return
	if card_open():
		reveal_all()
	elif shown_serial >= 0:
		buy(shown_tier)  # another card of the same kind
	get_viewport().set_input_as_handled()


## Card prices as the server scales them.
func _prices() -> Array[int]:
	var out: Array[int] = []
	for p: int in Registry.balance.scratch_prices:
		out.append(scaled(p))
	return out


## True while there is a card on screen still under foil.
func card_open() -> bool:
	return shown_serial >= 0 and not revealed


## Buys a card of `tier`.
func buy(tier: int) -> bool:
	if card_open():
		return false
	preview_tier = tier
	return send(&"place_bet", {"bet": {"tier": tier}})


## Scratches the rest of the card for you.
func reveal_all() -> void:
	if card_open():
		card_view.reveal_all()


func _hover(tier: int) -> void:
	if shown_serial < 0 and not revealed:
		preview_tier = tier
		_preview()


func _preview() -> void:
	shown_serial = -1
	revealed = false
	card_view.set_preview(preview_tier, _prices()[preview_tier])
	status_label.text = "Pick a card"
	status_label.remove_theme_color_override(&"font_color")


func _refresh() -> void:
	var c: Array = pub.get("card", [])
	var serial: int = int(pub.get("serial", 0))
	if not c.is_empty() and int(pub.get("player", -1)) == local_id:
		if serial != shown_serial:
			# A new card from the server: under fresh foil.
			shown_serial = serial
			shown_card = _ints(c)
			shown_tier = int(pub.get("tier", 0))
			shown_price = int(pub.get("stake", 0))
			preview_tier = shown_tier
			revealed = false
			reported = false
			card_view.set_card(shown_card, shown_tier, shown_price)
			status_label.text = "Scratch the foil!"
			status_label.remove_theme_color_override(&"font_color")
			Audio.play(&"card_flip", &"UI", -6.0)
	elif card_open():
		var last: Dictionary = pub.get("last", {})
		if not last.is_empty() and _ints(last.get("card", [])) == shown_card:
			reported = true  # the server paid it already (walked off, left too long)
			card_view.reveal_all(true)
		else:
			status_label.text = "Card refunded"
			_preview()
			status_label.text = "Card refunded"
	_update_controls()


func _update_controls() -> void:
	var open: bool = card_open()
	reveal_btn.visible = open
	var bal: int = my_balance()
	var prices: Array[int] = _prices()
	for t: int in buy_buttons.size():
		buy_buttons[t].visible = not open
		buy_buttons[t].disabled = bal < prices[t]
	info_label.text = "%s %s   •   %s" % ["PLAY MONEY" if fun else "BALANCE", money(bal), "CARD %s" % money(shown_price) if shown_serial >= 0 else "Three in a line wins"]


func _process(_delta: float) -> void:
	if visible:
		_update_controls()


func _on_all_revealed() -> void:
	revealed = true
	_show_prize()
	if not reported:
		reported = true
		var c: Array = pub.get("card", [])
		if not c.is_empty() and int(pub.get("serial", -1)) == shown_serial:
			send(&"action", {"action": &"reveal"})
	_update_controls()


## The prize stamp over the bare card (what the printed table pays for it).
func _show_prize() -> void:
	var won: int = prize_of(shown_card, shown_tier, shown_price)
	card_view.prize_label.visible = true
	if won > 0:
		card_view.prize_label.text = "WIN %s!" % money(won)
		card_view.prize_label.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
		status_label.text = "You won %s" % money(won)
		status_label.add_theme_color_override(&"font_color", Palette.MONEY_GREEN)
	else:
		card_view.prize_label.text = "NO WIN"
		card_view.prize_label.add_theme_color_override(&"font_color", Palette.CREAM)
		status_label.text = "No luck: try another card"
		status_label.remove_theme_color_override(&"font_color")


## What a card pays as printed (before Hot Table / item multipliers).
static func prize_of(c: Array[int], tier: int, price: int) -> int:
	return ScratchLogic.prize(price, ScratchLogic.card_multiplier(c, tier, Registry.balance))


func _ints(a: Array) -> Array[int]:
	var out: Array[int] = []
	for v: Variant in a:
		out.append(int(v))
	return out
