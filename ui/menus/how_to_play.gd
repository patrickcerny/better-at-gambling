class_name HowToPlayPanel
extends PanelContainer
## The tutorial (Patrick: "add a Tutorial (when you first start the game, you have to click
## through it with buttons. After that, theres a questionmark button just like the settings where
## you can see it again"): a few pages, each a real in-game picture (assets/tutorial/, rendered by
## tools/tutorial_pictures.sh) with a heading and a short text from the rules (docs/GDD.md). BACK /
## NEXT step through the pages, DONE on the last one closes it, SKIP (or Esc) closes it any time.
## Key names follow the player's bindings. Shown by the main menu (TUTORIAL, the "?" button, and
## once before the first PRACTICE / PLAY ONLINE, see `MainMenu`) and by the pause menu's "?".

## DONE, SKIP or Esc.
signal closed

## [heading, body, picture] per page; `{action}` turns into that action's key (`InputGlyphs.fill`).
const PAGES: Array[Array] = [
	["THE GOAL", "Everyone starts with $1,000 in fictional chips. Gamble, play the minigames and get in each other's way: whoever has the most money when the last call ends wins. [{leaderboard}] shows the standings.\n\nNo real money, ever: the chips are only for bragging.", "res://assets/tutorial/leaderboard.webp"],
	["MOVING AROUND", "[{move_forward}][{move_left}][{move_back}][{move_right}] walk, the mouse looks around, [{sprint}] sprints and [{jump}] jumps. [{ping}] pings a spot for your friends.\n\nWalk up to a table or machine and press [{interact}] to sit down; [{leave_station}] stands you up again.", "res://assets/tutorial/hall.webp"],
	["THE TABLES", "Blackjack, Roulette, Slots and Plinko. Pick a chip, place your bet and confirm; the table limits rise after every minigame.\n\nThe last stretch is LAST CALL: the final 60 seconds pay winnings ×1.5. Broke? The house comps you once per stretch.", "res://assets/tutorial/table.webp"],
	["ITEMS", "You carry up to three items. Use them with [{item_1}] [{item_2}] [{item_3}] (hold Shift while seated, where the number keys pick chips).\n\nEvery player gets an item after each minigame, and the gift shop sells more. Some help you (Lucky Clover), some hurt a rival (Black Cat, Banana Peel).", "res://assets/tutorial/shop.webp"],
	["MINIGAMES", "Every few minutes the curtain closes for a minigame: a quiz, Plinko, Split or Steal and more. Open bets are refunded and everyone is stood up first.\n\nThe briefing explains each one. Placing well pays cash and a better item.", "res://assets/tutorial/minigame.webp"],
	["ROUGH PLAY", "[{grab}] grabs and throws, [{shove}] shoves. Knock a rival down and [{shake}] shakes chips out of their pockets.\n\nSeated players are safe.", "res://assets/tutorial/rough.webp"],
	["SECURITY & JAIL", "The security guards watch: get caught attacking someone and you go to jail, behind the bars in the casino wall.\n\nEvery time you are caught you sit longer and pay a bigger fine.", "res://assets/tutorial/jail.webp"],
	["PLAYING WITH FRIENDS", "PLAY ONLINE: Create Lobby puts your lobby on our server; friends join with its 5-letter code or from Browse Lobbies. In the lobby, step up on your pedestal to be ready.\n\nWith Steam running you can also Host on this PC: friends join through Steam (INVITE FRIENDS in the lobby, or Join Game in their friends list). Everyone needs the same version of the game.", "res://assets/tutorial/lobby.webp"],
]
const PICTURE_SIZE: Vector2 = Vector2(640, 360)

var page: int = 0
var picture: TextureRect
var heading: Label
var body: Label
var counter: Label
var skip_button: Button
var back_button: Button
var next_button: Button
var done_button: Button


func _ready() -> void:
	custom_minimum_size = Vector2(760, 0)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 10)
	add_child(v)
	var title := Label.new()
	title.name = "Title"
	title.text = "HOW TO PLAY"
	title.theme_type_variation = &"HeadingLabel"
	title.add_theme_font_size_override(&"font_size", 44)
	title.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	picture = TextureRect.new()
	picture.name = "Picture"
	picture.custom_minimum_size = PICTURE_SIZE
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(picture)
	heading = Label.new()
	heading.name = "Heading"
	heading.theme_type_variation = &"HeadingLabel"
	v.add_child(heading)
	body = Label.new()
	body.name = "Body"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(720, 150)
	v.add_child(body)
	var row := HBoxContainer.new()
	row.name = "Buttons"
	row.add_theme_constant_override(&"separation", 12)
	v.add_child(row)
	skip_button = _button(row, "SKIP", close)
	skip_button.name = "Skip"
	counter = Label.new()
	counter.name = "Counter"
	counter.theme_type_variation = &"MutedLabel"
	counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	counter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(counter)
	back_button = _button(row, "BACK", func() -> void: show_page(page - 1))
	back_button.name = "Back"
	next_button = _button(row, "NEXT", func() -> void: show_page(page + 1))
	next_button.name = "Next"
	next_button.theme_type_variation = &"ActionButton"
	done_button = _button(row, "DONE", close)
	done_button.name = "Done"
	done_button.theme_type_variation = &"ActionButton"
	show_page(0)


## Opens on the first page.
func open() -> void:
	skip_button.text = "SKIP %s" % InputGlyphs.hint(&"ui_cancel")
	visible = true
	show_page(0)


## DONE, SKIP or Esc: hides the tutorial and says so (once).
func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


## Shows page `i` (clamped) and focuses NEXT, or DONE on the last page.
func show_page(i: int) -> void:
	page = clampi(i, 0, PAGES.size() - 1)
	heading.text = str(PAGES[page][0])
	body.text = InputGlyphs.fill(str(PAGES[page][1]))
	picture.texture = load(str(PAGES[page][2])) as Texture2D
	counter.text = "%d / %d" % [page + 1, PAGES.size()]
	var last: bool = page == PAGES.size() - 1
	back_button.disabled = page == 0
	next_button.visible = not last
	done_button.visible = last
	skip_button.visible = not last
	if is_visible_in_tree():
		(done_button if last else next_button).grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause")):
		get_viewport().set_input_as_handled()
		close()


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(150, 52)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b
