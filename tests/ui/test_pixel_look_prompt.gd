extends GutTest
## First-launch look question (0.9.14, Patrick: "When first started the game, give an option if
## you want the filter, or you dont. Then its saved in the settings"): the main menu covers itself
## with PIXEL LOOK / SHARP LOOK only while no choice is saved; each button saves its look, applies
## it and hands the menu back; it never blocks tests, `--smoke-test` or the dev shortcuts.

var _file: PackedByteArray = PackedByteArray()
var _had_file: bool = false
var _old_look: Variant
var _old_seen: Variant
var _old_scale: int


func before_each() -> void:
	_had_file = FileAccess.file_exists(Settings.PATH)
	_file = FileAccess.get_file_as_bytes(Settings.PATH) if _had_file else PackedByteArray()
	_old_look = Settings._cfg.get_value("video", "pixel_look", "unset")
	_old_seen = Settings.get_value("tutorial", "seen", "unset")
	_old_scale = Settings.pixel_scale_override
	Settings.set_pixel_override(0)
	Settings.set_value("tutorial", "seen", true)
	PixelLookPrompt.test_force = true


func after_each() -> void:
	PixelLookPrompt.test_force = false
	if _had_file:
		var f: FileAccess = FileAccess.open(Settings.PATH, FileAccess.WRITE)
		f.store_buffer(_file)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.PATH))
	if typeof(_old_look) == TYPE_STRING:
		_forget_choice()
	else:
		Settings.set_value("video", "pixel_look", _old_look)
	Settings.set_value("tutorial", "seen", null if typeof(_old_seen) == TYPE_STRING else _old_seen)
	Settings.set_pixel_override(_old_scale)


func _forget_choice() -> void:
	if Settings.has_pixel_look_choice():
		Settings._cfg.erase_section_key("video", "pixel_look")


func _menu() -> Control:
	var menu: Control = (load("res://ui/menus/main_menu.tscn") as PackedScene).instantiate()
	add_child_autofree(menu)
	await wait_process_frames(3)
	return menu


func _saved_look() -> Variant:
	var cfg := ConfigFile.new()
	if cfg.load(Settings.PATH) != OK:
		return null
	return cfg.get_value("video", "pixel_look", null)


func test_asked_only_while_no_choice_is_saved() -> void:
	_forget_choice()
	var menu: Control = await _menu()
	var prompt: PixelLookPrompt = menu.get("pixel_look_prompt")
	assert_not_null(prompt, "first launch: the question is up")
	assert_true(prompt.is_visible_in_tree())
	assert_eq(menu.get_child(menu.get_child_count() - 1), prompt, "over everything on the menu")
	assert_eq(prompt.mouse_filter, Control.MOUSE_FILTER_STOP, "the menu underneath waits")
	assert_eq(prompt.get_rect().size, menu.get_rect().size, "covers the whole screen")
	assert_true(prompt.pixel_button.has_focus(), "PIXEL LOOK focused for keyboard and pad")
	assert_eq(prompt.pixel_button.text, "PIXEL LOOK")
	assert_eq(prompt.sharp_button.text, "SHARP LOOK")
	for l: Node in prompt.find_children("*", "Label", true, false):
		assert_true((l as Label).text != "", "every line says something")
	Settings.set_value("video", "pixel_look", true)
	var again: Control = await _menu()
	assert_null(again.get("pixel_look_prompt"), "a saved choice: never asked again")
	assert_null(again.find_child("PixelLookPrompt", true, false))


func test_pixel_button_saves_the_pixel_look_and_continues() -> void:
	_forget_choice()
	var menu: Control = await _menu()
	var prompt: PixelLookPrompt = menu.get("pixel_look_prompt")
	watch_signals(prompt)
	prompt.pixel_button.pressed.emit()
	assert_signal_emitted_with_parameters(prompt, "chosen", [true])
	assert_true(Settings.has_pixel_look_choice())
	assert_true(Settings.pixel_look())
	assert_eq(_saved_look(), true, "saved in user://settings.cfg")
	assert_eq(Settings.pixel_scale(), Settings.PIXEL_SCALE)
	await wait_process_frames(1)
	assert_false(is_instance_valid(prompt), "gone")
	assert_null(menu.get("pixel_look_prompt"))
	assert_true((menu.get_node("%Practice") as Button).has_focus(), "the menu has the focus again")


func test_sharp_button_saves_the_sharp_look_and_continues() -> void:
	_forget_choice()
	var menu: Control = await _menu()
	var prompt: PixelLookPrompt = menu.get("pixel_look_prompt")
	prompt.sharp_button.pressed.emit()
	assert_false(Settings.pixel_look())
	assert_eq(_saved_look(), false, "saved in user://settings.cfg")
	assert_eq(Settings.pixel_scale(), 1, "full resolution at once")
	await wait_process_frames(1)
	assert_false(is_instance_valid(prompt), "gone")
	assert_true((menu.get_node("%Practice") as Button).has_focus())
	var again: Control = await _menu()
	assert_null(again.get("pixel_look_prompt"), "not asked on the next start")


func test_never_blocks_tests_smoke_runs_or_dev_shortcuts() -> void:
	_forget_choice()
	PixelLookPrompt.test_force = false
	assert_false(PixelLookPrompt.should_ask(get_tree(), Cmdline.parse(PackedStringArray())), "under GUT (and headless)")
	PixelLookPrompt.test_force = true
	assert_true(PixelLookPrompt.should_ask(get_tree(), Cmdline.parse(PackedStringArray())))
	Settings.set_value("video", "pixel_look", false)
	assert_false(PixelLookPrompt.should_ask(get_tree(), null), "already chosen")
	_forget_choice()
	for args: PackedStringArray in [["--smoke-test"], ["--practice"], ["--autoplay"], ["--server"], ["--connect", "127.0.0.1:1"], ["--join-code", "ABCDE"]]:
		var c: Cmdline = Cmdline.parse(args)
		assert_false(PixelLookPrompt.should_ask(get_tree(), c), "skipped with %s" % " ".join(args))
	PixelLookPrompt.test_force = false
	var menu: Control = await _menu()
	assert_null(menu.get("pixel_look_prompt"), "a plain test run sees the menu straight away")
