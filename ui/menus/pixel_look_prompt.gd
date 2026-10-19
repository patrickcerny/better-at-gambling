class_name PixelLookPrompt
extends Control
## The first-launch question (Patrick: "When first started the game, give an option if you want the
## filter, or you dont. Then its saved in the settings, and in the video settings you can change it
## again."): a full-screen card over the main menu with two big buttons, PIXEL LOOK (the world at a
## third of the resolution with hard pixels, `PixelView`) and SHARP LOOK (full resolution, smooth).
## Picking one saves `video/pixel_look` in user://settings.cfg, applies it live and closes; it is
## never asked again (Settings > Video has the toggle). The main menu opens it only when
## `should_ask` says so: no choice saved yet and the game booted normally (not `--smoke-test` or a
## dev/test shortcut, not headless, not under GUT or a dev tool's own SceneTree script).

## A look was picked (`pixel_look` true for the pixel look), saved and applied; the prompt is gone.
signal chosen(pixel_look: bool)

const PIXEL_TEXT: String = "Pixel look: the casino is drawn in big, chunky pixels for a retro, slightly grainy style."
const SHARP_TEXT: String = "Sharp look: the casino is drawn at your screen's full resolution, smooth and crisp."
## Command-line flags that boot past the menu or only run it for a test: never ask then.
const SKIP_FLAGS: Array[String] = ["smoke-test", "server", "practice", "autoplay", "create-room"]
const SKIP_VALUES: Array[String] = ["connect", "join-code"]

## Tests only: ask even headless and under GUT (the saved choice and the flags still decide).
static var test_force: bool = false

var pixel_button: Button
var sharp_button: Button


## True when the main menu should ask: no saved choice, and a normal boot of the game.
static func should_ask(tree: SceneTree, cmdline: Cmdline) -> bool:
	if Settings.has_pixel_look_choice():
		return false
	if cmdline != null:
		for f: String in SKIP_FLAGS:
			if cmdline.has_flag(f):
				return false
		for k: String in SKIP_VALUES:
			if cmdline.has(k):
				return false
	if test_force:
		return true
	# Nobody to click when headless; GUT and tools/screenshot.gd drive the scene from their own SceneTree.
	return DisplayServer.get_name() != "headless" and tree.get_script() == null


func _ready() -> void:
	name = "PixelLookPrompt"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # the menu underneath waits for the choice
	var bg := ColorRect.new()
	bg.name = "Backdrop"
	bg.color = Color(Palette.CASINO_BLACK, 0.94)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 18)
	panel.add_child(v)
	var title := Label.new()
	title.name = "Title"
	title.text = "PICK YOUR LOOK"
	title.theme_type_variation = &"HeadingLabel"
	title.add_theme_font_size_override(&"font_size", 44)
	title.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var row := HBoxContainer.new()
	row.name = "Choices"
	row.add_theme_constant_override(&"separation", 24)
	v.add_child(row)
	pixel_button = _choice(row, "PIXEL LOOK", PIXEL_TEXT, true)
	pixel_button.name = "Pixel"
	sharp_button = _choice(row, "SHARP LOOK", SHARP_TEXT, false)
	sharp_button.name = "Sharp"
	# Keyboard / gamepad focus stays on the two choices, never on the menu underneath.
	for b: Button in [pixel_button, sharp_button]:
		var other: Button = sharp_button if b == pixel_button else pixel_button
		b.focus_neighbor_left = b.get_path_to(other)
		b.focus_neighbor_right = b.get_path_to(other)
		b.focus_neighbor_top = b.get_path_to(b)
		b.focus_neighbor_bottom = b.get_path_to(b)
		b.focus_next = b.get_path_to(other)
		b.focus_previous = b.get_path_to(other)
	var note := Label.new()
	note.name = "Note"
	note.text = "You can change this any time in Settings > Video."
	note.theme_type_variation = &"MutedLabel"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(note)
	pixel_button.grab_focus.call_deferred()


## Saves the look, applies it and closes (the buttons call this).
func choose(pixel_look: bool) -> void:
	Settings.choose_pixel_look(pixel_look)
	Log.info(&"menu", "first launch: %s look" % ("pixel" if pixel_look else "sharp"))
	chosen.emit(pixel_look)
	queue_free()


func _choice(parent: Control, text: String, explain: String, pixel_look: bool) -> Button:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(380, 0)
	col.add_theme_constant_override(&"separation", 10)
	parent.add_child(col)
	var b := Button.new()
	b.text = text
	b.theme_type_variation = &"ActionButton"
	b.custom_minimum_size = Vector2(380, 120)
	b.add_theme_font_size_override(&"font_size", 36)
	b.pressed.connect(choose.bind(pixel_look))
	col.add_child(b)
	var l := Label.new()
	l.text = explain
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(380, 0)
	col.add_child(l)
	return b
