class_name BetPanel
extends PanelContainer
## Reusable chip selector + amount stepper + CONFIRM / CLEAR / REPEAT (§2.7). This is the
## keyboard/gamepad/accessibility path; physical betting (chips on the felt) sits on top of it.
## Keys: 1–4 chips, [ ] prev/next chip, Enter confirm, Backspace clear, R repeat.
##
## All-in (BetClamp): with `set_balance` fed, a bet over what you have bets everything you have
## (still capped by the max; under the minimum it stays as asked and the server refuses it).
## An "ALL IN" tag marks the bet and `went_all_in` fires once each time the bet becomes all-in
## (the table shows a toast). Chips worth more than your balance are greyed out (Patrick: "Disable
## the button if I don't have this much money anymore"); picking one picks the dearest chip you
## can still pay, so a chip never bets an amount the table doesn't list.

signal confirmed(amount: int)
signal cleared
signal repeated
signal amount_changed(amount: int)
signal chip_changed(value: int)
## The bet just became all-in at `amount` (everything the player has).
signal went_all_in(amount: int)

var chips: Array[int] = [10, 25, 50, 100]
var min_bet: int = 10
var max_bet: int = 200
var amount: int = 0
var selected_chip: int = 0
var last_amount: int = 0
## What the player can bet (-1 = unknown: no all-in clamping).
var balance: int = -1
## True while the current bet is everything the player has (the "ALL IN" tag shows).
var all_in: bool = false
## When true, selecting a chip confirms immediately (slots/Plinko style).
var instant: bool = false
## Chip button size and gap; slim docked panels (roulette) set smaller ones before `_ready`.
var chip_size: Vector2 = Vector2(84, 56)
var chip_gap: int = 10

var _chip_buttons: Array[Button] = []
var _amount_label: Label
var _all_in_tag: Label
var _limits_label: Label
var _confirm: Button
var _clear: Button
var _repeat: Button
var _minus: Button
var _plus: Button
var _stepper: HBoxContainer
var _chips_row: HBoxContainer


func _ready() -> void:
	_build()
	_refresh()


## Configures chips and limits; `confirm_text` labels the confirm button.
func setup(p_chips: Array[int], p_min: int, p_max: int, confirm_text: String = "BET", p_instant: bool = false) -> void:
	chips = p_chips.duplicate()
	min_bet = p_min
	max_bet = p_max
	instant = p_instant
	selected_chip = clampi(selected_chip, 0, chips.size() - 1)
	if _confirm != null:
		_confirm.text = confirm_text
		for b: Button in _chip_buttons:
			b.queue_free()
		_chip_buttons.clear()
		_make_chip_buttons()
		_stepper.visible = not instant
		_confirm.visible = not instant
		_clear.visible = not instant
		_repeat.visible = not instant
		_refresh()


## Shows/hides the stepper and action buttons (roulette places bets by clicking spots).
func configure_visibility(stepper: bool, confirm_btn: bool, clear_btn: bool, repeat_btn: bool) -> void:
	_stepper.visible = stepper
	_confirm.visible = confirm_btn
	_clear.visible = clear_btn
	_repeat.visible = repeat_btn


## Current chip value.
func chip_value() -> int:
	return chips[clampi(selected_chip, 0, chips.size() - 1)]


## True when the player can pay chip `i` (always while the balance is unknown).
func chip_affordable(i: int) -> bool:
	return i >= 0 and i < chips.size() and (balance < 0 or chips[i] <= balance)


## `i` itself when you can pay it, else the dearest cheaper chip you can pay; the smallest when
## you can pay none, so the server says "not enough money".
func affordable_index(i: int) -> int:
	var idx: int = clampi(i, 0, chips.size() - 1)
	for j: int in range(idx, -1, -1):
		if chip_affordable(j):
			return j
	return 0


## Updates what the player has; an amount over it drops to it (all-in), and a picked chip you
## can't pay any more drops to the dearest one you can.
func set_balance(b: int) -> void:
	if b == balance:
		return
	balance = b
	selected_chip = affordable_index(selected_chip)
	if amount > 0:
		set_amount(amount)  # re-clamps, and re-checks the ALL IN tag
	else:
		_refresh()  # a chip already on the layout keeps its tag until the next chip or CLEAR


## The stake for one chip placed on the layout (roulette, horse race), all-in when the chip is
## worth more than the balance. `room` is what the table still takes from you (-1 = `max_bet`).
func chip_stake(room: int = -1) -> int:
	var r: int = max_bet if room < 0 else room
	var stake: int = _clamped(chip_value(), r)
	_set_all_in(_is_all_in(chip_value(), r))
	return stake


func set_amount(a: int) -> void:
	amount = _clamped(clampi(a, 0, max_bet), max_bet)
	_set_all_in(amount > 0 and _is_all_in(a, max_bet))
	_refresh()
	amount_changed.emit(amount)


## `requested` cut to `room` and then to the balance (BetClamp); unchanged when the bet would be
## refused anyway (balance under the minimum, no room, unknown balance) so the server says why.
func _clamped(requested: int, room: int) -> int:
	if balance < 0 or requested < min_bet:
		return requested
	var c: int = BetClamp.clamp_amount(requested, balance, min_bet, room)
	return c if c > 0 else requested


func _is_all_in(requested: int, room: int) -> bool:
	if balance < 0 or requested < min_bet:
		return false
	return bool(BetClamp.resolve(requested, balance, min_bet, room)["all_in"])


func _set_all_in(v: bool) -> void:
	var was: bool = all_in
	all_in = v
	if _all_in_tag != null:
		_all_in_tag.visible = all_in
		_all_in_tag.text = "ALL IN  $%d" % balance if all_in else "ALL IN"
	if all_in and not was:
		went_all_in.emit(balance)


func select_chip(index: int) -> void:
	selected_chip = affordable_index(index)
	_refresh()
	chip_changed.emit(chip_value())
	Audio.play(&"ui_click", &"UI", -12.0)
	if instant:
		confirmed.emit(chip_stake())


func confirm() -> void:
	if amount < min_bet:
		set_amount(min_bet)
	last_amount = amount
	Audio.play(&"chips_in_pot", &"SFX", -4.0)
	confirmed.emit(amount)


func clear() -> void:
	_adjust(0)
	cleared.emit()


func repeat_last() -> void:
	if last_amount > 0:
		_adjust(last_amount)
	repeated.emit()


## A player-made change of the bet amount: Patrick's chip sound, a touch higher when adding and
## lower when taking chips off (programmatic `set_amount` stays silent).
func _adjust(a: int) -> void:
	var before: int = amount
	set_amount(a)
	if amount != before:
		Audio.play(&"chips_in_pot", &"SFX", -9.0, 1.08 if amount > before else 0.9)
		if _amount_label != null:
			TableSkin.flash(_amount_label)


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventKey and (event as InputEventKey).shift_pressed:
		return  # Shift+1–3 uses items while seated
	var handled: bool = true
	if event.is_action_pressed(&"bet_chip_1"):
		select_chip(0)
	elif event.is_action_pressed(&"bet_chip_2"):
		select_chip(1)
	elif event.is_action_pressed(&"bet_chip_3"):
		select_chip(2)
	elif event.is_action_pressed(&"bet_chip_4"):
		select_chip(3)
	elif event.is_action_pressed(&"bet_chip_prev"):
		select_chip(selected_chip - 1)
	elif event.is_action_pressed(&"bet_chip_next"):
		select_chip(selected_chip + 1)
	elif event.is_action_pressed(&"bet_confirm") and not instant:
		if amount == 0:
			set_amount(chip_value())
		confirm()
	elif event.is_action_pressed(&"bet_clear") and not instant:
		clear()
	elif event.is_action_pressed(&"bet_repeat") and not instant:
		repeat_last()
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _refresh() -> void:
	if _amount_label == null:
		return
	_amount_label.text = "$%d" % amount
	_limits_label.text = "MIN $%d   MAX $%d" % [min_bet, max_bet]
	for i: int in _chip_buttons.size():
		_chip_buttons[i].button_pressed = i == selected_chip
		# A chip worth more than you have is greyed out (it keeps its own value).
		var c: int = chips[i] if i < chips.size() else 0
		var can_pay: bool = chip_affordable(i)
		_chip_buttons[i].text = "$%d" % c
		if _chip_buttons[i].disabled == can_pay:
			_chip_buttons[i].disabled = not can_pay
			_chip_buttons[i].queue_redraw()
		_chip_buttons[i].tooltip_text = "" if can_pay else "Not enough money"
	_confirm.disabled = amount < min_bet and amount != 0
	_repeat.disabled = last_amount <= 0


func _build() -> void:
	if not has_theme_stylebox_override(&"panel"):
		var felt: StyleBoxFlat = TableSkin.felt_box(12, 10)
		felt.bg_color = Color(TableSkin.FELT_DEEP, 0.75)
		add_theme_stylebox_override(&"panel", felt)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 8)
	add_child(v)
	_limits_label = Label.new()
	_limits_label.theme_type_variation = &"SmallLabel"
	_limits_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_limits_label.add_theme_color_override(&"font_color", Palette.WARM_GOLD)
	_limits_label.add_theme_font_size_override(&"font_size", 16)
	v.add_child(_limits_label)
	_all_in_tag = Label.new()
	_all_in_tag.name = "AllInTag"
	_all_in_tag.text = "ALL IN"
	_all_in_tag.theme_type_variation = &"SmallLabel"
	_all_in_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_all_in_tag.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	_all_in_tag.visible = all_in
	v.add_child(_all_in_tag)
	_chips_row = HBoxContainer.new()
	_chips_row.name = "Chips"
	_chips_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_chips_row.add_theme_constant_override(&"separation", chip_gap)
	v.add_child(_chips_row)
	_make_chip_buttons()
	_stepper = HBoxContainer.new()
	_stepper.alignment = BoxContainer.ALIGNMENT_CENTER
	_stepper.add_theme_constant_override(&"separation", 12)
	v.add_child(_stepper)
	_minus = Button.new()
	_minus.text = "−"
	_minus.custom_minimum_size = Vector2(52, 44)
	TableSkin.style_button(_minus, &"ghost", 26)
	_minus.pressed.connect(func() -> void: _adjust(amount - chip_value()))
	_stepper.add_child(_minus)
	_amount_label = Label.new()
	_amount_label.theme_type_variation = &"MoneyLabel"
	_amount_label.custom_minimum_size = Vector2(160, 0)
	_amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_amount_label.add_theme_font_size_override(&"font_size", 42)
	_amount_label.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	_amount_label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.5))
	_amount_label.add_theme_constant_override(&"outline_size", 5)
	_stepper.add_child(_amount_label)
	_plus = Button.new()
	_plus.text = "+"
	_plus.custom_minimum_size = Vector2(52, 44)
	TableSkin.style_button(_plus, &"ghost", 26)
	_plus.pressed.connect(func() -> void: _adjust(amount + chip_value()))
	_stepper.add_child(_plus)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override(&"separation", 10)
	v.add_child(actions)
	_clear = Button.new()
	_clear.text = "CLEAR"
	TableSkin.style_button(_clear, &"ghost", 20)
	_clear.pressed.connect(clear)
	actions.add_child(_clear)
	_repeat = Button.new()
	_repeat.text = "REPEAT"
	TableSkin.style_button(_repeat, &"ghost", 20)
	_repeat.pressed.connect(repeat_last)
	actions.add_child(_repeat)
	_confirm = Button.new()
	_confirm.text = "BET"
	_confirm.custom_minimum_size = Vector2(150, 52)
	TableSkin.style_button(_confirm, &"gold", 26)
	_confirm.pressed.connect(func() -> void:
		if amount == 0:
			set_amount(chip_value())
		confirm())
	actions.add_child(_confirm)
	_instant_layout()


func _instant_layout() -> void:
	_stepper.visible = not instant
	_confirm.visible = not instant
	_clear.visible = not instant
	_repeat.visible = not instant


func _make_chip_buttons() -> void:
	for i: int in chips.size():
		var b := ChipToken.new()
		b.step = i
		b.toggle_mode = not instant
		b.text = "$%d" % chips[i]
		var side: float = clampf(minf(chip_size.x, chip_size.y) + 8.0, 44.0, 72.0)
		b.custom_minimum_size = Vector2(side, side)
		# No GUI focus: chips are picked with 1-4 / the shoulder buttons, and a focused chip took the
		# d-pad (items) and A (bet) away from a gamepad at the table.
		b.focus_mode = Control.FOCUS_NONE
		var idx: int = i
		b.pressed.connect(func() -> void: select_chip(idx))
		_chips_row.add_child(b)
		_chip_buttons.append(b)
