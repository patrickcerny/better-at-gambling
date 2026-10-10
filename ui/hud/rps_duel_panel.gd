class_name RpsDuelPanel
extends CanvasLayer
## Rock Paper Scissors duel screen (0.8.19): both players are pulled straight into it (no accept
## step). Shows who you play and for how much, the countdown, three big buttons (keys 1–3 or the
## d-pad pick too), what's happening ("Waiting for Anna…") and the result. ItemController feeds
## it from the private snapshot and the `rps_result` event; a pick comes back as `picked`.

signal picked(choice: int)

const NAMES: Array[String] = ["ROCK", "PAPER", "SCISSORS"]
const RESULT_SECONDS: float = 2.6

var panel: PanelContainer
var title: Label
var vs_label: Label
var timer_label: Label
var status_label: Label
var buttons: Array[Button] = []
## The duel shown ({} = none), and whether the result is up (the panel then closes by itself).
var duel: Dictionary = {}
var showing_result: bool = false
var _result_left: float = 0.0
var _my_pick: int = -1


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
	dim.color = Color(Palette.CASINO_BLACK, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.42
	panel.anchor_bottom = 0.42
	panel.offset_left = -330
	panel.offset_right = 330
	panel.offset_top = -170
	panel.offset_bottom = 170
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Palette.CASINO_BLACK, 0.94)
	sb.border_color = Palette.VIP_GOLD
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(18)
	panel.add_theme_stylebox_override(&"panel", sb)
	root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 10)
	panel.add_child(v)
	title = _label("ROCK  PAPER  SCISSORS", &"TitleLabel", Palette.VIP_GOLD)
	v.add_child(title)
	vs_label = _label("", &"HeadingLabel", Palette.CREAM)
	v.add_child(vs_label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 14)
	v.add_child(row)
	for i: int in 3:
		var b := Button.new()
		b.custom_minimum_size = Vector2(180, 96)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override(&"font_size", 26)
		b.text = "%s\n[%d]" % [NAMES[i], i + 1]
		b.pressed.connect(func() -> void: choose(i))
		row.add_child(b)
		buttons.append(b)
	timer_label = _label("", &"HeadingLabel", Palette.WARM_GOLD)
	v.add_child(timer_label)
	status_label = _label("", &"", Palette.CREAM)
	status_label.add_theme_font_size_override(&"font_size", 22)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(status_label)
	visible = false


func _process(delta: float) -> void:
	if _result_left > 0.0:
		_result_left -= delta
		if _result_left <= 0.0:
			if showing_result:
				close()
			else:
				status_label.remove_theme_color_override(&"font_color")  # tie banner over


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
	if int(d.get("duel", -1)) != int(duel.get("duel", -2)):
		_my_pick = -1
	duel = d
	visible = true
	vs_label.text = "vs %s   ·   stake $%d" % [other, int(d.get("stake", 0))]
	timer_label.text = "%d s" % ceili(float(d.get("left", 0.0)))
	var mine: bool = bool(d.get("picked", false)) or _my_pick >= 0
	for i: int in buttons.size():
		buttons[i].disabled = mine
		buttons[i].modulate = Color(1, 1, 1, 1) if (not mine or i == _my_pick) else Color(1, 1, 1, 0.4)
	if _result_left > 0.0:
		return  # "Tie! Go again…" stays readable for a moment
	if mine:
		status_label.text = "You picked %s. Waiting for %s…" % [NAMES[_my_pick], other] if _my_pick >= 0 else "Waiting for %s…" % other
	else:
		status_label.text = "Pick one! (no pick = a random one)"


## The local player picked `choice` (button, key or d-pad).
func choose(choice: int) -> void:
	if not visible or showing_result or _my_pick >= 0 or bool(duel.get("picked", false)) or choice < 0 or choice > 2:
		return
	_my_pick = choice
	for i: int in buttons.size():
		buttons[i].disabled = true
		buttons[i].modulate = Color(1, 1, 1, 1) if i == choice else Color(1, 1, 1, 0.4)
	status_label.text = "You picked %s…" % NAMES[choice]
	picked.emit(choice)


## The round's outcome: `mine`/`theirs` are pick names, `won` 1 = you, -1 = them, 0 = tie,
## `amount` what changed hands, `replay` true when a tie goes again.
func show_result(mine: String, theirs: String, won: int, amount: int, replay: bool, other: String) -> void:
	visible = true
	timer_label.text = ""
	var line: String = "You: %s   ·   %s: %s\n" % [mine.to_upper(), other, theirs.to_upper()]
	if replay:
		line += "Tie! Go again…"
	elif won > 0:
		line += "YOU WIN $%d!" % amount
	elif won < 0:
		line += "You lose $%d." % amount
	else:
		line += "Tie again: the duel is off."
	status_label.text = line
	status_label.add_theme_color_override(&"font_color", Palette.MONEY_GREEN if won > 0 else (Palette.LOSS_RED if won < 0 else Palette.CREAM))
	_my_pick = -1
	duel["picked"] = false
	for b: Button in buttons:
		b.disabled = not replay
		b.modulate = Color(1, 1, 1, 1)
	showing_result = not replay
	_result_left = 1.4 if replay else RESULT_SECONDS


func close() -> void:
	visible = false
	showing_result = false
	duel = {}
	_my_pick = -1
	_result_left = 0.0
	status_label.remove_theme_color_override(&"font_color")


func _label(text: String, variation: StringName, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	if variation != &"":
		l.theme_type_variation = variation
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override(&"font_color", color)
	return l
