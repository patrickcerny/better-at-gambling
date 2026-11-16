class_name OnlineMenu
extends Control
## PLAY ONLINE (Patrick 2026-11-16: "der play online button sollte uns jetzt in ein menu bringen mit
## bildern als buttons und die bild beschreiben was abgeht"): a full screen like the lobby lists,
## with four big picture cards (`PictureCard`): CREATE PUBLIC LOBBY, CREATE PRIVATE LOBBY, BROWSE
## LOBBIES and FRIENDS' LOBBIES, each with an in-game picture (assets/ui/online/, rendered by
## tools/online_pictures.sh) and a line on what happens, four in a row. Under them the status line and BACK. There is no name field: your
## name in a lobby is your Steam name (Patrick: "Der Name in der Lobby ist auch nicht setzbar
## sondern einfach der Name aus Steam"). The main menu wires the cards up.

signal back_pressed

const PICTURES: String = "res://assets/ui/online/%s.webp"
const GAP: int = 28
const MARGIN_X: int = 64
const MARGIN_Y: int = 44
## A card is this much taller than wide (picture on top, caption band at the bottom).
const CARD_ASPECT: float = 1.18

var title: Label
var grid: GridContainer
var public_card: PictureCard
var private_card: PictureCard
var browse_card: PictureCard
var friends_card: PictureCard
var status: Label
var back_button: Button


func _init() -> void:
	name = "Online"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()  # the casino stays faintly visible behind
	shade.name = "Shade"
	shade.color = Color(Palette.CASINO_BLACK, 0.78)
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
	v.add_theme_constant_override(&"separation", 18)
	margin.add_child(v)
	title = Label.new()
	title.name = "Title"
	title.text = "PLAY ONLINE"
	title.theme_type_variation = &"HeadingLabel"
	title.add_theme_font_size_override(&"font_size", 52)
	title.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var center := CenterContainer.new()
	center.name = "Cards"
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(center)
	grid = GridContainer.new()
	grid.name = "Grid"
	grid.columns = 4
	grid.add_theme_constant_override(&"h_separation", GAP)
	grid.add_theme_constant_override(&"v_separation", GAP)
	center.add_child(grid)
	public_card = _card("CreatePublic", "Public Lobby", "Open a lobby anyone can find and join under Browse Lobbies.", "public")
	private_card = _card("CreatePrivate", "Private Lobby", "Open a lobby only your friends and players you invite can join.", "private")
	browse_card = _card("BrowseLobbies", "Browse Lobbies", "Find an open lobby of other players and jump in.", "browse")
	friends_card = _card("FriendsLobbies", OnlineMenu.FRIENDS_TITLE, "Join a lobby one of your friends is already in.", "friends")
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
	back_button = Button.new()
	back_button.name = "Back"
	back_button.text = "Back"
	back_button.custom_minimum_size = Vector2(200, 52)
	back_button.pressed.connect(func() -> void: back_pressed.emit())
	bar.add_child(back_button)


const FRIENDS_TITLE: String = "Friends' Lobbies"


func _ready() -> void:
	resized.connect(_fit)
	_fit()


func cards() -> Array[PictureCard]:
	return [public_card, private_card, browse_card, friends_card]


## How many of your friends' lobbies there are, on the FRIENDS' LOBBIES card.
func set_friend_lobbies(count: int) -> void:
	friends_card.title_label.text = FRIENDS_TITLE if count <= 0 else "%s  ·  %d" % [FRIENDS_TITLE, count]


## The first card that can be used, else BACK.
func focus_first() -> void:
	for c: PictureCard in cards():
		if not c.disabled:
			c.grab_focus()
			return
	back_button.grab_focus()


func _card(card_name: String, title_text: String, caption: String, picture: String) -> PictureCard:
	var path: String = PICTURES % picture
	var tex: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	var c := PictureCard.new(card_name, title_text, caption, tex)
	grid.add_child(c)
	return c


## Four in a row (2×2 only on a very narrow window); the cards as big as the screen allows.
func _fit() -> void:
	var w: float = size.x - 2.0 * MARGIN_X
	var h: float = size.y - 2.0 * MARGIN_Y - 52.0 - 52.0 - 2.0 * 18.0 - 24.0  # title, bar, gaps, lift room
	if w <= 0.0 or h <= 0.0:
		return
	var cols: int = 4 if w >= 1000.0 else 2
	grid.columns = cols
	var rows: int = 4 / cols
	var card_w: float = (w - GAP * (cols - 1)) / float(cols)
	var card_h: float = card_w * CARD_ASPECT
	var max_h: float = (h - GAP * (rows - 1)) / float(rows)
	if card_h > max_h:
		card_h = max_h
		card_w = minf(card_w, card_h / CARD_ASPECT * 1.6)  # wide, short cards on a flat screen
	card_w = minf(card_w, 460.0)
	card_h = minf(card_h, 560.0)
	for c: PictureCard in cards():
		c.custom_minimum_size = Vector2(floorf(card_w), floorf(card_h))
