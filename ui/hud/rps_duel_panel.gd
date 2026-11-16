class_name RpsDuelPanel
extends CanvasLayer
## Rock Paper Scissors duel screen (0.8.19, redrawn in 0.9.72 in the table look): both players
## are pulled straight into it (no accept step). A walnut-and-brass panel with who you play and
## for how much, three cards with drawn hands (keys 1–3, the d-pad or a click pick; the badge on
## each card follows the device), a ring that runs down the seconds and a felt status band. The
## result flips the cards into a face-off: your hand against theirs, the winner lifted in gold.
## ItemController feeds it from the private snapshot and the `rps_result` event; a pick comes
## back as `picked`.

signal picked(choice: int)

const NAMES: Array[String] = ["ROCK", "PAPER", "SCISSORS"]
const RESULT_SECONDS: float = 2.6
const CARD_SIZE := Vector2(196, 228)

var panel: PanelContainer
var title: Label
var vs_label: Label
var stake_label: Label
var timer_ring: RpsTimerRing
var timer_label: Label
var status_label: Label
var status_band: PanelContainer
var buttons: Array[Button] = []
var icons: Array[RpsHandIcon] = []
var badges: Array[RpsKeyBadge] = []
var cards_row: HBoxContainer
var reveal_row: HBoxContainer
var reveal_mine: RpsHandIcon
var reveal_theirs: RpsHandIcon
var reveal_mine_label: Label
var reveal_theirs_label: Label
var verdict_label: Label
## The duel shown ({} = none), and whether the result is up (the panel then closes by itself).
var duel: Dictionary = {}
var showing_result: bool = false
var _result_left: float = 0.0
var _my_pick: int = -1
var _total: float = 0.0
var _epoch: int = -1


func _init() -> void:
	name = "RpsDuelPanel"
	layer = 40


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = load("res://ui/theme/main_theme.tres") as Theme
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(Palette.CASINO_BLACK, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	panel = PanelContainer.new()
	panel.add_theme_stylebox_override(&"panel", TableSkin.panel_box())
	panel.draw.connect(func() -> void: TableSkin.draw_frame(panel))
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 12)
	panel.add_child(v)

	# Title between two brass rules.
	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override(&"separation", 14)
	v.add_child(head)
	head.add_child(DecoRule.new(false, 70.0))
	title = TableSkin.label("ROCK  ·  PAPER  ·  SCISSORS", 44, Palette.VIP_GOLD)
	title.add_theme_font_override(&"font", TableSkin.black_font())
	head.add_child(title)
	head.add_child(DecoRule.new(true, 70.0))

	# Who and how much.
	var info := HBoxContainer.new()
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.add_theme_constant_override(&"separation", 12)
	v.add_child(info)
	var vs_band := PanelContainer.new()
	vs_band.add_theme_stylebox_override(&"panel", TableSkin.band_box(Palette.VIP_BURGUNDY, TableSkin.BRASS))
	info.add_child(vs_band)
	vs_label = TableSkin.label("", 26, Palette.CREAM, true)
	vs_band.add_child(vs_label)
	var stake_band := PanelContainer.new()
	stake_band.add_theme_stylebox_override(&"panel", TableSkin.band_box(TableSkin.FELT_DEEP, TableSkin.BRASS))
	info.add_child(stake_band)
	stake_label = TableSkin.label("", 26, Palette.VIP_GOLD, true)
	stake_band.add_child(stake_label)

	# The three cards.
	cards_row = HBoxContainer.new()
	cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	cards_row.add_theme_constant_override(&"separation", 18)
	v.add_child(cards_row)
	for i: int in 3:
		cards_row.add_child(_card(i))

	# The face-off after the result (hidden until then).
	reveal_row = HBoxContainer.new()
	reveal_row.alignment = BoxContainer.ALIGNMENT_CENTER
	reveal_row.add_theme_constant_override(&"separation", 26)
	reveal_row.custom_minimum_size = Vector2(0, CARD_SIZE.y)
	reveal_row.visible = false
	v.add_child(reveal_row)
	var mine_box: VBoxContainer = _reveal_side()
	reveal_mine = mine_box.get_child(0) as RpsHandIcon
	reveal_mine_label = mine_box.get_child(1) as Label
	reveal_row.add_child(mine_box)
	var mid := VBoxContainer.new()
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	reveal_row.add_child(mid)
	var vs := TableSkin.label("VS", 54, TableSkin.BRASS)
	vs.add_theme_font_override(&"font", TableSkin.black_font())
	mid.add_child(vs)
	var theirs_box: VBoxContainer = _reveal_side()
	reveal_theirs = theirs_box.get_child(0) as RpsHandIcon
	reveal_theirs_label = theirs_box.get_child(1) as Label
	reveal_row.add_child(theirs_box)

	# The clock and the status band.
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override(&"separation", 14)
	v.add_child(foot)
	timer_ring = RpsTimerRing.new()
	foot.add_child(timer_ring)
	timer_label = timer_ring.number
	status_band = PanelContainer.new()
	status_band.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_band.add_theme_stylebox_override(&"panel", TableSkin.felt_box(12, 10))
	foot.add_child(status_band)
	var sv := VBoxContainer.new()
	sv.alignment = BoxContainer.ALIGNMENT_CENTER
	sv.add_theme_constant_override(&"separation", 0)
	status_band.add_child(sv)
	verdict_label = TableSkin.label("", 36, Palette.VIP_GOLD)
	verdict_label.add_theme_font_override(&"font", TableSkin.black_font())
	verdict_label.visible = false
	sv.add_child(verdict_label)
	status_label = TableSkin.label("", 22, Palette.CREAM, true)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(420, 0)
	sv.add_child(status_label)
	visible = false


func _card(i: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = CARD_SIZE
	b.focus_mode = Control.FOCUS_NONE
	TableSkin.style_button(b, &"ghost")
	b.pressed.connect(func() -> void: choose(i))
	b.mouse_entered.connect(func() -> void: _hover(i, true))
	b.mouse_exited.connect(func() -> void: _hover(i, false))
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_top = 12
	box.offset_bottom = -12
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override(&"separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(box)
	var icon := RpsHandIcon.new(i, 118.0)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(icon)
	var name_l: Label = TableSkin.label(NAMES[i], 30, Palette.CREAM, true)
	box.add_child(name_l)
	var badge := RpsKeyBadge.new(StringName("item_%d" % (i + 1)), str(i + 1))
	badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(badge)
	buttons.append(b)
	icons.append(icon)
	badges.append(badge)
	return b


func _reveal_side() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override(&"separation", 4)
	box.custom_minimum_size = Vector2(220, 0)
	var icon := RpsHandIcon.new(0, 156.0)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(icon)
	box.add_child(TableSkin.label("", 28, Palette.CREAM, true))
	return box


func _process(delta: float) -> void:
	if not visible:
		return
	if _epoch != InputGlyphs.epoch:
		_epoch = InputGlyphs.epoch
		for b: RpsKeyBadge in badges:
			b.queue_redraw()
	if _result_left > 0.0:
		_result_left -= delta
		if _result_left <= 0.0:
			if showing_result:
				close()
			else:
				_set_verdict("", Palette.CREAM)  # tie banner over


func is_open() -> bool:
	return visible


## True while a result (or the tie banner) is still on screen.
func is_settling() -> bool:
	return showing_result or _result_left > 0.0


## Shows/updates the running duel: `d` is the private snapshot's duel entry, `other` the
## opponent's name.
func show_duel(d: Dictionary, other: String) -> void:
	if showing_result:
		return  # the result stays up until it closes itself
	var fresh: bool = int(d.get("duel", -1)) != int(duel.get("duel", -2))
	if fresh:
		_my_pick = -1
		_total = 0.0
	duel = d
	var opening: bool = not visible
	visible = true
	cards_row.visible = true
	reveal_row.visible = false
	timer_ring.visible = true
	vs_label.text = "VS  %s" % other.to_upper()
	stake_label.text = "STAKE  $%d" % int(d.get("stake", 0))
	var left: float = float(d.get("left", 0.0))
	_total = maxf(_total, left)
	timer_ring.set_time(left, _total)
	timer_label.text = "%d" % ceili(left)
	var mine: bool = bool(d.get("picked", false)) or _my_pick >= 0
	_mark_cards(mine)
	if opening:
		TableSkin.pop(panel, 0.85)
	if _result_left > 0.0:
		return  # "Tie! Go again…" stays readable for a moment
	if mine:
		status_label.text = "You picked %s. Waiting for %s…" % [NAMES[_my_pick], other] if _my_pick >= 0 else "Waiting for %s…" % other
	else:
		status_label.text = "Pick one! No pick = a random one."


## The local player picked `choice` (card, key or d-pad).
func choose(choice: int) -> void:
	if not visible or showing_result or _my_pick >= 0 or bool(duel.get("picked", false)) or choice < 0 or choice > 2:
		return
	_my_pick = choice
	_mark_cards(true)
	TableSkin.flash(buttons[choice])
	Audio.play(&"chip_clack", &"UI", -6.0, 1.1)
	status_label.text = "You picked %s…" % NAMES[choice]
	picked.emit(choice)


## The round's outcome: `mine`/`theirs` are pick names, `won` 1 = you, -1 = them, 0 = tie,
## `amount` what changed hands, `replay` true when a tie goes again.
func show_result(mine: String, theirs: String, won: int, amount: int, replay: bool, other: String) -> void:
	visible = true
	timer_label.text = ""
	timer_ring.set_time(0.0, 0.0)
	timer_ring.visible = replay  # the face-off needs no clock
	var line: String = "You: %s   ·   %s: %s" % [mine.to_upper(), other, theirs.to_upper()]
	_my_pick = -1
	duel["picked"] = false
	showing_result = not replay
	_result_left = 1.4 if replay else RESULT_SECONDS
	if replay:
		_set_verdict("TIE!  GO AGAIN", Palette.CREAM)
		status_label.text = line
		_mark_cards(false)
		return
	# The face-off: your hand on the left, theirs on the right, the winner lifted.
	cards_row.visible = false
	reveal_row.visible = true
	reveal_mine.kind = maxi(NAMES.find(mine.to_upper()), 0)
	reveal_theirs.kind = maxi(NAMES.find(theirs.to_upper()), 0)
	reveal_mine_label.text = "YOU"
	reveal_theirs_label.text = other.to_upper()
	reveal_mine.dim = 0.85 if won < 0 else 0.0
	reveal_theirs.dim = 0.85 if won > 0 else 0.0
	reveal_mine.glow = won > 0
	reveal_theirs.glow = won < 0
	reveal_mine_label.add_theme_color_override(&"font_color", Palette.VIP_GOLD if won > 0 else Palette.CREAM)
	reveal_theirs_label.add_theme_color_override(&"font_color", Palette.VIP_GOLD if won < 0 else Palette.CREAM)
	TableSkin.pop(reveal_row, 0.7)
	if won > 0:
		_set_verdict("YOU WIN  $%d!" % amount, Palette.MONEY_GREEN)
	elif won < 0:
		_set_verdict("YOU LOSE  $%d" % amount, Palette.LOSS_RED)
	else:
		_set_verdict("TIE AGAIN", Palette.CREAM)
	status_label.text = line if won != 0 else "Tie again: the duel is off."


func close() -> void:
	visible = false
	showing_result = false
	duel = {}
	_my_pick = -1
	_result_left = 0.0
	_total = 0.0
	_set_verdict("", Palette.CREAM)
	cards_row.visible = true
	reveal_row.visible = false


## Greys the cards out once a pick is in (the picked one stays lit and lifted).
func _mark_cards(locked: bool) -> void:
	for i: int in buttons.size():
		buttons[i].disabled = locked
		var chosen: bool = locked and i == _my_pick
		icons[i].dim = 0.75 if locked and not chosen else 0.0
		icons[i].glow = chosen
		buttons[i].modulate = Color(1, 1, 1, 1) if (not locked or chosen) else Color(1, 1, 1, 0.55)
		if chosen:
			buttons[i].add_theme_stylebox_override(&"disabled", _picked_box())
		else:
			TableSkin.style_button(buttons[i], &"ghost")


func _picked_box() -> StyleBoxFlat:
	var sb: StyleBoxFlat = TableSkin.plaque(Palette.VIP_BURGUNDY, Palette.VIP_GOLD, true)
	sb.set_border_width_all(3)
	return sb


func _hover(i: int, on: bool) -> void:
	if buttons[i].disabled:
		return
	icons[i].lift(1.1 if on else 1.0)


func _set_verdict(text: String, color: Color) -> void:
	verdict_label.text = text
	verdict_label.visible = text != ""
	verdict_label.add_theme_color_override(&"font_color", color)
	if text != "":
		TableSkin.pop(verdict_label, 0.6)
