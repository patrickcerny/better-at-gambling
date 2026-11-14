class_name DevPanel
extends VBoxContainer
## Developer mode in the main menu (`DevMode`; the DEV entry, Patrick only): Coins and levels for
## the profile, every cosmetic (until the game closes), a Practice casino with standing dummies
## and the dev tools on (pause menu: DEV TOOLS), and a tile per minigame that drops straight into
## it. BACK or Esc returns to the entries.

## BACK / Esc.
signal closed
## A practice match was chosen: the main menu starts it with these settings.
signal practice_requested(settings: Dictionary)

const LEVEL_STEPS: Array[int] = [1, 10]
const TILE_PICTURE: Vector2 = Vector2(176, 99)

var dummies: SpinBox
var unlock_toggle: CheckButton
var profile_line: Label
## Minigame id -> its tile button.
var minigame_tiles: Dictionary = {}
var casino_button: Button
var back_button: Button


func _ready() -> void:
	name = "Dev"
	custom_minimum_size = Vector2(860, 0)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_theme_constant_override(&"separation", 10)
	visible = false
	var title := Label.new()
	title.text = "DEV MODE"
	title.theme_type_variation = &"HeadingLabel"
	title.add_theme_font_size_override(&"font_size", 44)
	title.add_theme_color_override(&"font_color", Palette.MONEY_GREEN)
	add_child(title)
	# Profile.
	profile_line = Label.new()
	profile_line.name = "ProfileLine"
	profile_line.theme_type_variation = &"SmallLabel"
	add_child(profile_line)
	var prof := HBoxContainer.new()
	prof.add_theme_constant_override(&"separation", 10)
	add_child(prof)
	_button(prof, "+10,000 COINS", func() -> void: DevMode.add_coins(10000)).name = "Coins"
	for step: int in LEVEL_STEPS:
		_button(prof, "+%d LEVEL%s" % [step, "" if step == 1 else "S"], func() -> void: DevMode.set_level(ProfileManager.profile.level + step)).name = "Level%d" % step
	_button(prof, "LEVEL 1", func() -> void: DevMode.set_level(1)).name = "Level1Reset"
	unlock_toggle = CheckButton.new()
	unlock_toggle.name = "UnlockAll"
	unlock_toggle.text = "All cosmetics"
	unlock_toggle.tooltip_text = "Every hat, shirt, colour and pack counts as owned until the game closes. Nothing is bought or saved."
	unlock_toggle.toggled.connect(DevMode.set_unlock_all)
	prof.add_child(unlock_toggle)
	# Practice.
	var play := HBoxContainer.new()
	play.add_theme_constant_override(&"separation", 10)
	add_child(play)
	var dl := Label.new()
	dl.text = "Dummies"
	dl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	play.add_child(dl)
	dummies = SpinBox.new()
	dummies.name = "Dummies"
	dummies.min_value = 0
	dummies.max_value = 7
	dummies.value = 3
	dummies.custom_minimum_size = Vector2(110, 48)
	play.add_child(dummies)
	casino_button = _button(play, "PRACTICE CASINO (DEV TOOLS ON)", func() -> void:
		practice_requested.emit(DevMode.casino_settings(int(dummies.value))))
	casino_button.name = "Casino"
	casino_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	casino_button.theme_type_variation = &"ActionButton"
	_button(play, "SHOW TUTORIAL AGAIN", func() -> void:
		Settings.set_value("tutorial", "seen", false)
		Settings.save()).name = "ResetTutorial"
	# Minigames.
	var mt := Label.new()
	mt.text = "PLAY A MINIGAME NOW (with the dummies)"
	mt.theme_type_variation = &"SmallLabel"
	add_child(mt)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 430)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var grid := GridContainer.new()
	grid.name = "Minigames"
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override(&"h_separation", 10)
	grid.add_theme_constant_override(&"v_separation", 10)
	scroll.add_child(grid)
	for id: Variant in Registry.minigames:
		var def: MinigameDefinition = Registry.minigames[id]
		var tile := Button.new()
		tile.name = String(def.id)
		tile.custom_minimum_size = Vector2(TILE_PICTURE.x + 16, TILE_PICTURE.y + 46)
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.tooltip_text = def.rules_text
		var tv := VBoxContainer.new()
		tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 6)
		tile.add_child(tv)
		var pic := TextureRect.new()
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pic.custom_minimum_size = TILE_PICTURE
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pic.texture = MinigameSelector.picture(def.id)
		tv.add_child(pic)
		var nl := Label.new()
		nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		nl.text = def.display_name
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nl.clip_text = true
		tv.add_child(nl)
		var mid: StringName = def.id
		tile.pressed.connect(func() -> void: practice_requested.emit(DevMode.minigame_settings(mid, int(dummies.value))))
		grid.add_child(tile)
		minigame_tiles[def.id] = tile
	back_button = _button(self, "Back", close)
	back_button.name = "Back"
	ProfileManager.changed.connect(_refresh)


func open() -> void:
	visible = true
	_refresh()
	casino_button.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _refresh() -> void:
	if profile_line == null:
		return
	var p: PlayerProfile = ProfileManager.profile
	profile_line.text = "Level %d   ·   %s Coins   ·   Steam achievements are off for this run once you use anything here" % [p.level, DevMatchPanel._thousands(p.coins)]
	unlock_toggle.set_pressed_no_signal(DevMode.unlock_all())


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 48)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b
