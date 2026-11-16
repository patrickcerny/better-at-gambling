class_name OnlineMenu
extends Control
## PLAY ONLINE (Patrick 2026-11-16: "der play online button sollte uns jetzt in ein menu bringen mit
## bildern als buttons und die bild beschreiben was abgeht"): a full screen like the lobby lists,
## with four big picture cards (`PictureCard`): CREATE PUBLIC LOBBY, CREATE PRIVATE LOBBY, BROWSE
## LOBBIES and FRIENDS' LOBBIES, each with a picture (assets/ui/online/, generated splash
## arts, Patrick 2026-11-16: "es sollen eher so splasharts sein ... generiere sie") and a line on what happens, PUBLIC / PRIVATE big on top, BROWSE / FRIENDS smaller below. Under them the status line and BACK. There is no name field: your
## name in a lobby is your Steam name (Patrick: "Der Name in der Lobby ist auch nicht setzbar
## sondern einfach der Name aus Steam"). The main menu wires the cards up.

signal back_pressed

const PICTURES: String = "res://assets/ui/online/%s.webp"
const GAP: int = 28
const MARGIN_X: int = 64
const MARGIN_Y: int = 44
## Card shapes (width / height): the big ones wide, the small ones a little less so.
const BIG_ASPECT: float = 1.55
const SMALL_ASPECT: float = 1.75
const SMALL_SCALE: float = 0.68

var title: Label
## PUBLIC / PRIVATE big on top, BROWSE / FRIENDS' smaller under them (Patrick 2026-11-16: "public
## und private größer 2 oben und die anderen 2 unten kleiner").
var top_row: HBoxContainer
var bottom_row: HBoxContainer
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
	var rows := VBoxContainer.new()
	rows.name = "Rows"
	rows.add_theme_constant_override(&"separation", GAP)
	center.add_child(rows)
	top_row = _row(rows, "Big")
	bottom_row = _row(rows, "Small")
	public_card = _card(top_row, "CreatePublic", "Public Lobby", "Open a lobby anyone can find and join under Browse Lobbies.", "public")
	private_card = _card(top_row, "CreatePrivate", "Private Lobby", "Open a lobby only your friends and players you invite can join.", "private")
	browse_card = _card(bottom_row, "BrowseLobbies", "Browse Lobbies", "Find an open lobby of other players and jump in.", "browse")
	friends_card = _card(bottom_row, "FriendsLobbies", OnlineMenu.FRIENDS_TITLE, "Join a lobby one of your friends is already in.", "friends")
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


func _row(parent: Control, row_name: String) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.name = row_name
	r.alignment = BoxContainer.ALIGNMENT_CENTER
	r.add_theme_constant_override(&"separation", GAP)
	parent.add_child(r)
	return r


func _card(row: HBoxContainer, card_name: String, title_text: String, caption: String, picture: String) -> PictureCard:
	var path: String = PICTURES % picture
	var tex: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	var c := PictureCard.new(card_name, title_text, caption, tex)
	row.add_child(c)
	return c


## The two big cards fill the width (wide splash arts), the two small ones sit under them at about
## two thirds of their size; both rows shrink together on a short screen.
func _fit() -> void:
	var w: float = size.x - 2.0 * MARGIN_X
	var h: float = size.y - 2.0 * MARGIN_Y - 60.0 - 52.0 - 2.0 * 18.0 - GAP - 24.0  # title, bar, gaps, lift room
	if w <= 0.0 or h <= 0.0:
		return
	var big_w: float = minf((w - GAP) / 2.0, 820.0)
	var big_h: float = big_w / BIG_ASPECT
	var small_w: float = big_w * SMALL_SCALE
	var small_h: float = small_w / SMALL_ASPECT
	var fit: float = minf(1.0, h / (big_h + small_h))
	for c: PictureCard in [public_card, private_card]:
		c.custom_minimum_size = Vector2(floorf(big_w * fit), floorf(big_h * fit))
	for c: PictureCard in [browse_card, friends_card]:
		c.custom_minimum_size = Vector2(floorf(small_w * fit), floorf(small_h * fit))
