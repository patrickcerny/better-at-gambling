class_name HowToPlayPanel
extends VBoxContainer
## The main menu's TUTORIAL entry (Patrick: "New button for (Tutorial)"): a few short pages of
## rules (docs/GDD.md) with PREV / NEXT and BACK. Key names follow the player's bindings.
## PLACEHOLDER: this text tutorial stands in for the later interactive tutorial (a guided practice
## match); swap `MainMenu._show_tutorial` over to that once it exists.

signal closed

## [heading, body] per page; `{action}` turns into that action's key (`InputGlyphs.fill`).
const PAGES: Array[Array] = [
	["THE GOAL", "Everyone starts with $1,000 in fictional chips. Gamble, play the minigames and get in each other's way: whoever has the most money when the last call ends wins.\n\nNo real money, ever: the chips are only for bragging."],
	["MOVING AROUND", "[{move_forward}][{move_left}][{move_back}][{move_right}] walk, the mouse looks around, [{sprint}] sprints and [{jump}] jumps.\n\nWalk up to a table or machine and press [{interact}] to sit down; [{leave_station}] stands you up again. [{leaderboard}] shows the standings, [{ping}] pings a spot for your friends."],
	["THE TABLES", "Blackjack, Roulette, Slots and Plinko. Pick a chip, place your bet and confirm; the table limits rise after every minigame.\n\nThe last stretch is LAST CALL: the final 60 seconds pay winnings ×1.5. Broke? The house comps you once per stretch."],
	["ITEMS", "You carry up to three items. Use them with [{item_1}] [{item_2}] [{item_3}] (hold Shift while seated, where the number keys pick chips).\n\nEvery player gets an item after each minigame, and the gift shop sells more. Some help you (Lucky Clover), some hurt a rival (Black Cat, Banana Peel)."],
	["MINIGAMES", "Every few minutes the curtain closes for a minigame: a quiz, Plinko, Split or Steal and more. Open bets are refunded and everyone is stood up first.\n\nThe briefing explains each one. Placing well pays cash and a better item."],
	["ROUGH PLAY & JAIL", "[{grab}] grabs and throws, [{shove}] shoves. Knock a rival down and [{shake}] shakes chips out of their pockets. Seated players are safe.\n\nThe security guards watch: get caught attacking someone and you go to jail, longer and with a bigger fine every time."],
]

var page: int = 0
var heading: Label
var body: Label
var counter: Label
var prev_button: Button
var next_button: Button
var back_button: Button


func _ready() -> void:
	custom_minimum_size = Vector2(720, 0)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_theme_constant_override(&"separation", 14)
	var title := Label.new()
	title.text = "HOW TO PLAY"
	title.theme_type_variation = &"HeadingLabel"
	title.add_theme_font_size_override(&"font_size", 44)
	title.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(720, 380)
	add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 12)
	card.add_child(v)
	heading = Label.new()
	heading.theme_type_variation = &"HeadingLabel"
	v.add_child(heading)
	body = Label.new()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	counter = Label.new()
	counter.theme_type_variation = &"MutedLabel"
	counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(counter)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 12)
	add_child(row)
	prev_button = _button(row, "PREV", func() -> void: show_page(page - 1))
	next_button = _button(row, "NEXT", func() -> void: show_page(page + 1))
	back_button = _button(row, "BACK", func() -> void: closed.emit())
	show_page(0)


## Shows page `i` (clamped) and focuses NEXT, or BACK on the last page.
func show_page(i: int) -> void:
	page = clampi(i, 0, PAGES.size() - 1)
	heading.text = str(PAGES[page][0])
	body.text = InputGlyphs.fill(str(PAGES[page][1]))
	counter.text = "%d / %d" % [page + 1, PAGES.size()]
	prev_button.disabled = page == 0
	next_button.disabled = page == PAGES.size() - 1
	if is_visible_in_tree():
		(back_button if next_button.disabled else next_button).grab_focus()


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(200, 52)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b
