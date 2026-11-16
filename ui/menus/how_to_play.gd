class_name HowToPlayPanel
extends PanelContainer
## The tutorial (Patrick: "add a Tutorial (when you first start the game, you have to click
## through it with buttons. After that, theres a questionmark button just like the settings where
## you can see it again"), in three chapters (Patrick: "split the tutorial into The casino, The
## items and The mingamges. Minigames also submenu with images"). It opens on an overview of three
## big picture cards (`PictureCard`, Patrick 2026-11-16: "Gleiche idee auf für das Menü vom
## Tutorial. Zuerst ein Screen mit den 3 buttons"): THE CASINO, THE ITEMS, THE MINIGAMES, and a
## card opens that chapter. Most pages are a real in-game picture (assets/tutorial/, rendered by
## tools/tutorial_pictures.sh) with a heading and a short text from the rules (docs/GDD.md). THE
## ITEMS ends with every item (its 3D model, name, rarity and what it does); THE MINIGAMES ends with
## a grid of every minigame (its picture from the lobby's selector, assets/minigames/), and a tile
## opens that game's page (picture and rules; ALL MINIGAMES goes back, NEXT GAME steps on).
## Controls in a chapter ("Mach die controls auch besser ist bisschen verwirrend"): ALL TOPICS (top
## left) back to the overview, ✕ (top right) closes; at the bottom BACK and NEXT with a row of dots
## for where you are in the chapter. NEXT on a chapter's last page goes on to the next chapter
## ("NEXT: THE ITEMS"), on the very last page it is DONE, so a first-time click-through still covers
## everything. BACK on a chapter's first page goes back to the overview. Esc steps back one level
## (a game page → the grid, a chapter → the overview, the overview → closed). Key names follow the
## player's bindings. Shown by the main menu (TUTORIAL, the "?" button, and once before the first
## PRACTICE / PLAY ONLINE, see `MainMenu`) and by the pause menu's "?".

## DONE, CLOSE / ✕, or Esc on the overview.
signal closed

const SECTIONS: Array[String] = ["THE CASINO", "THE ITEMS", "THE MINIGAMES"]
## A page whose "picture" is this shows the item list instead.
const ALL_ITEMS: String = "@items"
## A page whose "picture" is this shows the minigame grid instead.
const ALL_MINIGAMES: String = "@minigames"

## [section, heading, body, picture] per page; `{action}` turns into that action's key
## (`InputGlyphs.fill`).
const PAGES: Array[Array] = [
	[0, "THE GOAL", "Everyone starts with $1,000 in fictional chips. Gamble, play the minigames and get in each other's way: whoever has the most money when the last call ends wins. [{leaderboard}] shows the standings.\n\nNo real money, ever: the chips are only for bragging.", "res://assets/tutorial/leaderboard.webp"],
	[0, "MOVING AROUND", "[{move_forward}][{move_left}][{move_back}][{move_right}] walk, the mouse looks around, [{sprint}] sprints and [{jump}] jumps. [{ping}] pings a spot for your friends.\n\nWalk up to a table or machine and press [{interact}] to sit down; [{leave_station}] stands you up again.", "res://assets/tutorial/hall.webp"],
	[0, "THE TABLES", "Blackjack, Roulette, Slots and Plinko. Pick a chip, place your bet and confirm; the table limits rise after every minigame.\n\nThe last stretch is LAST CALL: the final 60 seconds pay winnings ×1.5. Broke? The house comps you once per stretch.", "res://assets/tutorial/table.webp"],
	[0, "SMASH THE BUTTON", "Broke? Walk to the Odd Jobs cabinet by the Gift Shop, look at the big red button and click [{grab}] as fast as you can.\n\nEveryone fills the same bar, and the click that fills it wins $50. The less money you have, the fewer clicks your share takes; at $500 or more, go gamble instead.", "res://assets/tutorial/oddjobs.webp"],
	[0, "ROUGH PLAY", "[{grab}] grabs and throws, [{shove}] shoves. Knock a rival down and [{shake}] shakes chips out of their pockets.\n\nSeated players are safe.", "res://assets/tutorial/rough.webp"],
	[0, "SECURITY & JAIL", "The security guards watch: get caught attacking someone and you go to jail, behind the bars in the casino wall.\n\nEvery time you are caught you sit longer and pay a bigger fine.", "res://assets/tutorial/jail.webp"],
	[0, "PLAYING WITH FRIENDS", "PLAY ONLINE: open a Private Lobby (only friends and players you invite) or a Public Lobby (anyone can find it under Browse Lobbies), and invite your friends with INVITE FRIENDS in the lobby. Join a friend's lobby under Friends' Lobbies or with Join Game in your friends list, or pick a public one under Browse Lobbies. In the lobby, step up on your pedestal to be ready. Everyone needs the same version of the game.", "res://assets/tutorial/lobby.webp"],
	[1, "USING ITEMS", "You carry up to three items. Use them with [{item_1}] [{item_2}] [{item_3}] (hold Shift while seated, where the number keys pick chips).\n\nThe item you pick goes in your hand, where everyone can see it. Some help you (Lucky Clover), some hurt a rival (Black Cat, Banana Peel).\n\nLUCK (next to your items) is the chance a table result is drawn again in your favour, or against you when it is negative. A losing streak slowly builds a little luck; your next win uses it up.", "res://assets/tutorial/items.webp"],
	[1, "GETTING ITEMS", "Every player gets an item after each minigame: the better you placed, the better the pick. The Gift Shop sells more for chips.\n\nYour bag is full? The new item asks which one to throw away.", "res://assets/tutorial/shop.webp"],
	[1, "ALL ITEMS", "", ALL_ITEMS],
	[2, "MINIGAMES", "Every few minutes the curtain closes for a minigame. Open bets are refunded and everyone is stood up first.\n\nThe briefing explains each one. Placing well pays cash and a better item. Pick a game on the next page to see how it works.", "res://assets/tutorial/minigame.webp"],
	[2, "ALL MINIGAMES", "", ALL_MINIGAMES],
]
const PICTURE_SIZE: Vector2 = Vector2(640, 360)
## The page area: the picture and the text under it, the item list or the minigame grid.
const CONTENT_SIZE: Vector2 = Vector2(720, 610)
const RARITY_NAMES: Array[String] = ["Common", "Rare", "Legendary"]
const TILE_PICTURE: Vector2 = Vector2(160, 90)

## The three chapters' cards (THE CASINO, THE ITEMS, THE MINIGAMES).
const CHAPTER_CARDS: Array[Array] = [
	["Casino", "The tables, moving around, rough play and jail.", "res://assets/tutorial/hall.webp"],
	["Items", "What the items do and how you get them.", "res://assets/tutorial/items.webp"],
	["Minigames", "How minigames work, and every game one by one.", "res://assets/tutorial/minigame.webp"],
]
const OVERVIEW_WIDTH: float = 1180.0
const PAGES_WIDTH: float = 760.0

var page: int = 0
## The minigame whose page is open (&"" = none: the page in `page`).
var minigame: StringName = &""
## On the overview (the three cards) rather than in a chapter.
var on_overview: bool = true
var overview: VBoxContainer
## THE CASINO / THE ITEMS / THE MINIGAMES on the overview.
var chapter_cards: Array[PictureCard] = []
var overview_close: Button
## A chapter: its header, the page and the controls.
var chapter_box: VBoxContainer
var chapter_title: Label
var picture: TextureRect
var heading: Label
var body: Label
## The text scrolls when it is longer than the room under the picture.
var body_scroll: ScrollContainer
## The dots under the page: one per page of the open chapter, the current one in gold.
var dots: HBoxContainer
var topics_button: Button
var close_button: Button
var back_button: Button
var next_button: Button
var done_button: Button
## The picture + heading + text page.
var page_box: VBoxContainer
## Every item, and the minigame grid (with one tile per minigame id).
var items_box: ScrollContainer
var minigames_box: ScrollContainer
var minigame_tiles: Dictionary = {}
## Item id -> its row in the item list.
var item_rows: Dictionary = {}
var _thumbs: ItemThumbnails


func _ready() -> void:
	custom_minimum_size = Vector2(OVERVIEW_WIDTH, 0)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var root := VBoxContainer.new()
	root.add_theme_constant_override(&"separation", 10)
	add_child(root)
	_build_overview(root)
	chapter_box = VBoxContainer.new()
	chapter_box.name = "Chapter"
	chapter_box.add_theme_constant_override(&"separation", 10)
	root.add_child(chapter_box)
	var head := HBoxContainer.new()
	head.name = "Header"
	head.add_theme_constant_override(&"separation", 12)
	chapter_box.add_child(head)
	topics_button = _button(head, "◀  ALL TOPICS", show_overview)
	topics_button.name = "AllTopics"
	topics_button.custom_minimum_size = Vector2(0, 46)
	chapter_title = Label.new()
	chapter_title.name = "Title"
	chapter_title.theme_type_variation = &"HeadingLabel"
	chapter_title.add_theme_font_size_override(&"font_size", 36)
	chapter_title.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	chapter_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chapter_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(chapter_title)
	close_button = _button(head, "✕", close)
	close_button.name = "Close"
	close_button.tooltip_text = "Close the tutorial"
	close_button.custom_minimum_size = Vector2(46, 46)
	var content := Control.new()
	content.name = "Content"
	content.custom_minimum_size = CONTENT_SIZE
	content.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	chapter_box.add_child(content)
	page_box = VBoxContainer.new()
	page_box.name = "Page"
	page_box.add_theme_constant_override(&"separation", 10)
	page_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.add_child(page_box)
	picture = TextureRect.new()
	picture.name = "Picture"
	picture.custom_minimum_size = PICTURE_SIZE
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	page_box.add_child(picture)
	heading = Label.new()
	heading.name = "Heading"
	heading.theme_type_variation = &"HeadingLabel"
	page_box.add_child(heading)
	# Long texts scroll inside the page instead of running under the buttons (Patrick 2026-11-16:
	# "how to play clips").
	body_scroll = ScrollContainer.new()
	body_scroll.name = "BodyScroll"
	body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page_box.add_child(body_scroll)
	body = Label.new()
	body.name = "Body"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(700, 0)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_scroll.add_child(body)
	items_box = _scroll(content, "Items")
	_build_items(items_box)
	minigames_box = _scroll(content, "Minigames")
	_build_minigames(minigames_box)
	var row := HBoxContainer.new()
	row.name = "Buttons"
	row.add_theme_constant_override(&"separation", 12)
	chapter_box.add_child(row)
	back_button = _button(row, "◀  BACK", go_back)
	back_button.name = "Back"
	back_button.custom_minimum_size.x = 210
	var mid := CenterContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(mid)
	dots = HBoxContainer.new()
	dots.name = "Dots"
	dots.add_theme_constant_override(&"separation", 8)
	mid.add_child(dots)
	next_button = _button(row, "NEXT  ▶", go_next)
	next_button.name = "Next"
	next_button.custom_minimum_size.x = 210
	next_button.theme_type_variation = &"ActionButton"
	done_button = _button(row, "DONE", close)
	done_button.name = "Done"
	done_button.custom_minimum_size.x = 210
	done_button.theme_type_variation = &"ActionButton"
	show_overview()


## THE CASINO / THE ITEMS / THE MINIGAMES as three picture cards, and CLOSE under them.
func _build_overview(root: VBoxContainer) -> void:
	overview = VBoxContainer.new()
	overview.name = "Overview"
	overview.add_theme_constant_override(&"separation", 18)
	root.add_child(overview)
	var title := Label.new()
	title.name = "Title"
	title.text = "HOW TO PLAY"
	title.theme_type_variation = &"HeadingLabel"
	title.add_theme_font_size_override(&"font_size", 44)
	title.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overview.add_child(title)
	var cards := HBoxContainer.new()
	cards.name = "Cards"
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	cards.add_theme_constant_override(&"separation", 24)
	overview.add_child(cards)
	for i: int in SECTIONS.size():
		var c: Array = CHAPTER_CARDS[i]
		var tex: Texture2D = _load_picture(str(c[2]))
		var card := PictureCard.new(str(c[0]), "The %s" % str(c[0]), str(c[1]), tex)
		card.custom_minimum_size = Vector2(360, 400)
		card.pressed.connect(open_section.bind(i))
		cards.add_child(card)
		chapter_cards.append(card)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	overview.add_child(row)
	overview_close = _button(row, "CLOSE", close)
	overview_close.name = "CloseOverview"
	overview_close.custom_minimum_size.x = 220


## Opens on the overview (the three chapter cards).
func open() -> void:
	visible = true
	show_overview()


## DONE, CLOSE / ✕: hides the tutorial and says so (once).
func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


## Esc / B: one level back (a game page → the grid, a chapter → the overview, the overview → closed).
func step_back() -> void:
	if not visible:
		return
	if minigame != &"":
		go_back()
	elif not on_overview:
		show_overview()
	else:
		close()


## The three chapter cards; the focus on the chapter you were just in (else THE CASINO).
func show_overview() -> void:
	var was: int = section_of(page) if not on_overview else 0
	on_overview = true
	minigame = &""
	overview.visible = true
	chapter_box.visible = false
	custom_minimum_size.x = OVERVIEW_WIDTH
	size = Vector2.ZERO  # shrink back around the content
	if is_visible_in_tree():
		chapter_cards[was].grab_focus()


## A chapter card: the first page of chapter `i`.
func open_section(i: int) -> void:
	for p: int in PAGES.size():
		if int(PAGES[p][0]) == i:
			show_page(p)
			return


## The chapter page `i` belongs to.
static func section_of(i: int) -> int:
	return int(PAGES[clampi(i, 0, PAGES.size() - 1)][0])


## The pages of chapter `s`, in order.
static func pages_of(s: int) -> Array[int]:
	var out: Array[int] = []
	for p: int in PAGES.size():
		if int(PAGES[p][0]) == s:
			out.append(p)
	return out


## Shows page `i` (clamped) in its chapter and focuses NEXT, or DONE on the last page.
func show_page(i: int) -> void:
	_enter_chapter()
	page = clampi(i, 0, PAGES.size() - 1)
	minigame = &""
	var special: String = str(PAGES[page][3])
	heading.text = str(PAGES[page][1])
	page_box.visible = special != ALL_ITEMS and special != ALL_MINIGAMES
	items_box.visible = special == ALL_ITEMS
	minigames_box.visible = special == ALL_MINIGAMES
	body_scroll.scroll_vertical = 0
	if page_box.visible:
		body.text = InputGlyphs.fill(str(PAGES[page][2]))
		picture.texture = _load_picture(special)
	if items_box.visible:
		_load_item_thumbs()
	var s: int = section_of(page)
	chapter_title.text = SECTIONS[s]
	var in_chapter: Array[int] = pages_of(s)
	_draw_dots(in_chapter.size(), in_chapter.find(page))
	var last: bool = page == PAGES.size() - 1
	var chapter_end: bool = page == in_chapter[-1]
	back_button.text = "◀  BACK"
	back_button.tooltip_text = "Back to all topics" if page == in_chapter[0] else ""
	back_button.disabled = false
	next_button.text = "NEXT: %s  ▶" % SECTIONS[s + 1] if chapter_end and not last else "NEXT  ▶"
	next_button.visible = not last
	done_button.visible = last
	if is_visible_in_tree():
		(done_button if last else next_button).grab_focus()


## A minigame tile: that game's page (picture, name, players, rules).
func open_minigame(id: StringName) -> void:
	var def: MinigameDefinition = Registry.minigames.get(id, null)
	if def == null:
		return
	_enter_chapter()
	page = _minigames_page()
	minigame = id
	page_box.visible = true
	items_box.visible = false
	minigames_box.visible = false
	picture.texture = MinigameSelector.picture(id)
	body_scroll.scroll_vertical = 0
	heading.text = def.display_name.to_upper()
	body.text = InputGlyphs.fill("%s\n\n%d+ players." % [def.rules_text.strip_edges(), maxi(def.min_players, 1)])
	var ids: Array = Registry.minigames.keys()
	var at: int = ids.find(id)
	chapter_title.text = SECTIONS[2]
	_draw_dots(0, -1)
	back_button.text = "◀  ALL MINIGAMES"
	back_button.tooltip_text = ""
	back_button.disabled = false
	next_button.text = "NEXT GAME  ▶"
	next_button.visible = at < ids.size() - 1
	done_button.visible = not next_button.visible
	if is_visible_in_tree():
		(next_button if next_button.visible else back_button).grab_focus()


## BACK: the page before; on a chapter's first page the overview; from a minigame's page the grid.
func go_back() -> void:
	if minigame != &"":
		var was: StringName = minigame
		show_page(_minigames_page())
		var tile: Button = minigame_tiles.get(was, null)
		if tile != null and is_visible_in_tree():
			tile.grab_focus()
		return
	if page == pages_of(section_of(page))[0]:
		show_overview()
		return
	show_page(page - 1)


## NEXT: the page after (the next chapter's first after a chapter's last), or the next minigame.
func go_next() -> void:
	if minigame != &"":
		var ids: Array = Registry.minigames.keys()
		var at: int = ids.find(minigame)
		if at >= 0 and at < ids.size() - 1:
			open_minigame(StringName(ids[at + 1]))
		return
	show_page(page + 1)


func _minigames_page() -> int:
	for p: int in PAGES.size():
		if str(PAGES[p][3]) == ALL_MINIGAMES:
			return p
	return PAGES.size() - 1


func _enter_chapter() -> void:
	if not on_overview:
		return
	on_overview = false
	overview.visible = false
	chapter_box.visible = true
	custom_minimum_size.x = PAGES_WIDTH
	size = Vector2.ZERO


## `count` dots, the one at `at` in gold (none on a minigame's own page).
func _draw_dots(count: int, at: int) -> void:
	for d: Node in dots.get_children():
		dots.remove_child(d)
		d.queue_free()
	for i: int in count:
		var dot := Panel.new()
		var on: bool = i == at
		dot.custom_minimum_size = Vector2(26 if on else 12, 12)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Palette.VIP_GOLD if on else Color(Palette.CREAM, 0.25)
		sb.set_corner_radius_all(6)
		dot.add_theme_stylebox_override(&"panel", sb)
		dots.add_child(dot)


## A page picture; a missing file shows the minigame picture instead of nothing.
func _load_picture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return load("res://assets/tutorial/minigame.webp") as Texture2D


# --- ALL ITEMS ----------------------------------------------------------------------------------

## Every item players can get, rarest last, each with its model, name, rarity and what it does.
static func listed_items() -> Array[ItemDefinition]:
	var out: Array[ItemDefinition] = []
	for id: Variant in Registry.items:
		var d: ItemDefinition = Registry.items[id]
		if d.in_loot:
			out.append(d)
	out.sort_custom(func(a: ItemDefinition, b: ItemDefinition) -> bool:
		if a.rarity != b.rarity:
			return a.rarity < b.rarity
		return a.display_name.naturalnocasecmp_to(b.display_name) < 0)
	return out


func _build_items(scroll: ScrollContainer) -> void:
	var list := VBoxContainer.new()
	list.name = "List"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override(&"separation", 6)
	scroll.add_child(list)
	for d: ItemDefinition in listed_items():
		var row := PanelContainer.new()
		row.name = String(d.id)
		row.theme_type_variation = &"RowPanel"
		list.add_child(row)
		var h := HBoxContainer.new()
		h.add_theme_constant_override(&"separation", 12)
		row.add_child(h)
		var icon := TextureRect.new()
		icon.name = "Icon"
		icon.custom_minimum_size = Vector2(64, 64)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		h.add_child(icon)
		var txt := VBoxContainer.new()
		txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		txt.add_theme_constant_override(&"separation", 0)
		h.add_child(txt)
		var top := HBoxContainer.new()
		txt.add_child(top)
		var name_label := Label.new()
		name_label.name = "Name"
		name_label.text = d.display_name
		var rarity: int = clampi(d.rarity, 0, RARITY_NAMES.size() - 1)
		name_label.add_theme_color_override(&"font_color", RewardPanel.RARITY_COLORS[rarity])
		top.add_child(name_label)
		var tag := Label.new()
		tag.text = "  ·  %s" % RARITY_NAMES[rarity]
		tag.theme_type_variation = &"MutedLabel"
		top.add_child(tag)
		var desc := Label.new()
		desc.name = "Description"
		desc.text = d.description
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.theme_type_variation = &"SmallLabel"
		desc.custom_minimum_size = Vector2(600, 0)
		txt.add_child(desc)
		item_rows[d.id] = row


## The item models are rendered the first time the list shows (one per frame, `ItemThumbnails`).
func _load_item_thumbs() -> void:
	if _thumbs == null:
		_thumbs = ItemThumbnails.new()
		add_child(_thumbs)
	for id: Variant in item_rows:
		var icon: TextureRect = (item_rows[id] as Control).find_child("Icon", true, false) as TextureRect
		if icon.texture == null:
			icon.texture = ItemThumbnails.texture_for(StringName(id))


# --- ALL MINIGAMES ------------------------------------------------------------------------------

func _build_minigames(scroll: ScrollContainer) -> void:
	var grid := GridContainer.new()
	grid.name = "Grid"
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override(&"h_separation", 8)
	grid.add_theme_constant_override(&"v_separation", 8)
	scroll.add_child(grid)
	for id: Variant in Registry.minigames:
		var def: MinigameDefinition = Registry.minigames[id]
		var tile := Button.new()
		tile.name = String(def.id)
		tile.custom_minimum_size = Vector2(TILE_PICTURE.x + 16, TILE_PICTURE.y + 44)
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.tooltip_text = MinigameSelector.first_sentence(def.rules_text)
		var tv := VBoxContainer.new()
		tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
		tv.add_theme_constant_override(&"separation", 2)
		tile.add_child(tv)
		tv.add_child(PictureCard.rounded_picture(MinigameSelector.picture(def.id), TILE_PICTURE))
		var nl := Label.new()
		nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		nl.text = def.display_name
		nl.theme_type_variation = &"SmallLabel"
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nl.clip_text = true
		tv.add_child(nl)
		tile.pressed.connect(open_minigame.bind(def.id))
		grid.add_child(tile)
		minigame_tiles[def.id] = tile


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause")):
		get_viewport().set_input_as_handled()
		step_back()


func _scroll(parent: Control, scroll_name: String) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.name = scroll_name
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	s.visible = false
	parent.add_child(s)
	return s


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(150, 52)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b
