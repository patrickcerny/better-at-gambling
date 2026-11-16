class_name LobbyListScreen
extends Control
## A full-screen list of lobbies (Patrick 2026-11-16: "way smaller the stuff only peek the heads of
## the players and use the whole screen for that on the public lobbies. Friends lobbies also own
## button and screen"). PUBLIC LOBBIES and FRIENDS' LOBBIES are both one of these: the title,
## a grid of small lobby cards over the whole screen (as many columns as fit), and a bottom bar
## with the status line, REFRESH and BACK. The cards come from the main menu (`set_cards`); a
## rebuild keeps the pad / keyboard focus on the same lobby's JOIN when it is still listed.

signal back_pressed
signal refresh_pressed

## One card's width; the grid takes as many columns as fit.
const CARD_WIDTH: float = 420.0
const GAP: int = 14
const MARGIN_X: int = 64
const MARGIN_Y: int = 44

var title: Label
var grid: GridContainer
var status: Label
var refresh_button: Button
var back_button: Button
var _scroll: ScrollContainer


func _init(screen_name: String, title_text: String) -> void:
	name = screen_name
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()  # the casino stays faintly visible behind
	shade.name = "Shade"
	shade.color = Color(Palette.CASINO_BLACK, 0.82)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override(&"margin_left", MARGIN_X)
	margin.add_theme_constant_override(&"margin_right", MARGIN_X)
	margin.add_theme_constant_override(&"margin_top", MARGIN_Y)
	margin.add_theme_constant_override(&"margin_bottom", MARGIN_Y)
	add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 14)
	margin.add_child(v)
	title = Label.new()
	title.name = "Title"
	title.text = title_text
	title.theme_type_variation = &"HeadingLabel"
	title.add_theme_font_size_override(&"font_size", 44)
	title.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	v.add_child(title)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	v.add_child(_scroll)
	grid = GridContainer.new()
	grid.name = "LobbyList"
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override(&"h_separation", GAP)
	grid.add_theme_constant_override(&"v_separation", GAP)
	grid.columns = 3
	_scroll.add_child(grid)
	var bar := HBoxContainer.new()
	bar.name = "Bar"
	bar.add_theme_constant_override(&"separation", 12)
	v.add_child(bar)
	status = Label.new()
	status.name = "Status"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(status)
	refresh_button = _bar_button("Refresh", func() -> void: refresh_pressed.emit())
	refresh_button.name = "Refresh"
	bar.add_child(refresh_button)
	back_button = _bar_button("Back", func() -> void: back_pressed.emit())
	back_button.name = "Back"
	bar.add_child(back_button)


func _ready() -> void:
	resized.connect(_fit_columns)
	_fit_columns()


func _bar_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(200, 52)
	b.pressed.connect(cb)
	return b


## As many card columns as the screen is wide (at least one).
func _fit_columns() -> void:
	var w: float = size.x - 2.0 * MARGIN_X
	if w <= 0.0:
		return
	grid.columns = maxi(1, int((w + GAP) / (CARD_WIDTH + GAP)))
	var card_w: float = (w - GAP * (grid.columns - 1)) / float(grid.columns) - 1.0
	for c: Node in grid.get_children():
		if c is Control and not (c is Label):
			(c as Control).custom_minimum_size.x = card_w


## Puts `cards` in the grid (or `empty_text` when there are none). The focus stays on the same
## lobby's JOIN if it was on a card and that lobby is still there, else it goes to REFRESH.
func set_cards(cards: Array[Control], empty_text: String) -> void:
	var focus: Control = get_viewport().gui_get_focus_owner() if get_viewport() != null else null
	var had_focus: bool = focus != null and grid.is_ancestor_of(focus)
	var focused_card: StringName = &""
	if had_focus:
		for c: Node in grid.get_children():
			if c.is_ancestor_of(focus):
				focused_card = c.name
	for c: Node in grid.get_children():
		grid.remove_child(c)
		c.queue_free()
	if cards.is_empty():
		var none := Label.new()
		none.name = "None"
		none.text = empty_text
		none.theme_type_variation = &"MutedLabel"
		grid.add_child(none)
	for c: Control in cards:
		grid.add_child(c)
	_fit_columns()
	if not had_focus:
		return
	var again: Node = grid.get_node_or_null(NodePath(String(focused_card))) if focused_card != &"" else null
	var join: Button = again.find_child("Join", true, false) as Button if again != null else null
	if join != null and not join.disabled:
		join.grab_focus()
	else:
		refresh_button.grab_focus()


## Opens the screen with the focus on the first joinable lobby, else on REFRESH.
func focus_first() -> void:
	for c: Node in grid.get_children():
		var join: Button = c.find_child("Join", true, false) as Button
		if join != null and not join.disabled:
			join.grab_focus()
			return
	refresh_button.grab_focus()
