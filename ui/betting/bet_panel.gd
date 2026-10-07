class_name BetPanel
extends PanelContainer
## Reusable chip selector + amount stepper + CONFIRM / CLEAR / REPEAT (§2.7). This is the
## keyboard/gamepad/accessibility path; physical betting (chips on the felt) sits on top of it.
## Keys: 1–4 chips, [ ] prev/next chip, Enter confirm, Backspace clear, R repeat.

signal confirmed(amount: int)
signal cleared
signal repeated
signal amount_changed(amount: int)
signal chip_changed(value: int)

var chips: Array[int] = [10, 25, 50, 100]
var min_bet: int = 10
var max_bet: int = 200
var amount: int = 0
var selected_chip: int = 0
var last_amount: int = 0
## When true, selecting a chip confirms immediately (slots/Plinko style).
var instant: bool = false
## Chip button size and gap; slim docked panels (roulette) set smaller ones before `_ready`.
var chip_size: Vector2 = Vector2(84, 56)
var chip_gap: int = 10

var _chip_buttons: Array[Button] = []
var _amount_label: Label
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


func set_amount(a: int) -> void:
	amount = clampi(a, 0, max_bet)
	_refresh()
	amount_changed.emit(amount)


func select_chip(index: int) -> void:
	selected_chip = clampi(index, 0, chips.size() - 1)
	_refresh()
	chip_changed.emit(chip_value())
	Audio.play(&"ui_click", &"UI", -12.0)
	if instant:
		confirmed.emit(chip_value())


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
	_confirm.disabled = amount < min_bet and amount != 0
	_repeat.disabled = last_amount <= 0


func _build() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 8)
	add_child(v)
	_limits_label = Label.new()
	_limits_label.theme_type_variation = &"SmallLabel"
	_limits_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_limits_label.add_theme_color_override(&"font_color", Palette.WARM_GOLD)
	v.add_child(_limits_label)
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
	_minus.custom_minimum_size = Vector2(56, 48)
	_minus.pressed.connect(func() -> void: _adjust(amount - chip_value()))
	_stepper.add_child(_minus)
	_amount_label = Label.new()
	_amount_label.theme_type_variation = &"MoneyLabel"
	_amount_label.custom_minimum_size = Vector2(160, 0)
	_amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stepper.add_child(_amount_label)
	_plus = Button.new()
	_plus.text = "+"
	_plus.custom_minimum_size = Vector2(56, 48)
	_plus.pressed.connect(func() -> void: _adjust(amount + chip_value()))
	_stepper.add_child(_plus)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override(&"separation", 10)
	v.add_child(actions)
	_clear = Button.new()
	_clear.text = "CLEAR"
	_clear.pressed.connect(clear)
	actions.add_child(_clear)
	_repeat = Button.new()
	_repeat.text = "REPEAT"
	_repeat.pressed.connect(repeat_last)
	actions.add_child(_repeat)
	_confirm = Button.new()
	_confirm.text = "BET"
	_confirm.custom_minimum_size = Vector2(140, 52)
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
		var b := Button.new()
		b.theme_type_variation = &"ChipButton"
		b.toggle_mode = not instant
		b.text = "$%d" % chips[i]
		b.custom_minimum_size = chip_size
		b.focus_mode = Control.FOCUS_ALL
		var idx: int = i
		b.pressed.connect(func() -> void: select_chip(idx))
		_chips_row.add_child(b)
		_chip_buttons.append(b)
	if not _chip_buttons.is_empty():
		_chip_buttons[0].grab_focus()
