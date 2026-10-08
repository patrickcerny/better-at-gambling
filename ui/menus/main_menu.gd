extends Control
## Main menu, centred under the 3D logo (Patrick: "the main menu centered"): Play Online (create a
## party, join by code or address), Practice, Tutorial (how to play), Quit, and a small gear in the
## bottom-right corner for the settings. Connection errors from the last online attempt are shown
## here when we return.

@onready var _play_online: Button = %PlayOnline
@onready var _practice: Button = %Practice
@onready var _tutorial: Button = %Tutorial
@onready var _quit: Button = %Quit
@onready var _main_box: VBoxContainer = %VBox
@onready var _column: VBoxContainer = %Column

var _online_box: VBoxContainer
var _name_edit: LineEdit
var _code_edit: LineEdit
var _ip_edit: LineEdit
var _status: Label
var _busy: bool = false
var _settings: SettingsPanel
var _settings_button: GearButton
var _how_to_play: HowToPlayPanel


func _ready() -> void:
	# Live casino behind the menu (art direction: the menu is the casino, slightly blurred).
	var pano := CasinoPanorama.new()
	pano.name = "Panorama"
	pano.blur_px = 1.5
	pano.darken = 0.45
	pano.start_leg = randf() * CasinoPanorama.PATH.size()
	add_child(pano)
	move_child(pano, 1)  # above the plain background, below the buttons
	# Dark wash behind the menu column so the logo and entries read over any part of the casino.
	var shade := TextureRect.new()
	shade.name = "Shade"
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var grad := Gradient.new()  # darkest down the middle, where the column sits
	grad.set_color(0, Color(Palette.CASINO_BLACK, 0.15))
	grad.set_color(1, Color(Palette.CASINO_BLACK, 0.15))
	grad.add_point(0.25, Color(Palette.CASINO_BLACK, 0.6))
	grad.add_point(0.5, Color(Palette.CASINO_BLACK, 0.85))
	grad.add_point(0.75, Color(Palette.CASINO_BLACK, 0.6))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 256
	gt.height = 4
	gt.fill_to = Vector2(1, 0)
	shade.texture = gt
	add_child(shade)
	move_child(shade, 2)
	(%Footer as Label).text = "BUILD %s" % Protocol.BUILD_ID
	_quit.pressed.connect(_on_quit_pressed)
	_practice.pressed.connect(func() -> void: SceneRouter.goto(SceneRouter.MATCH))
	_play_online.pressed.connect(_show_online)
	_tutorial.pressed.connect(_show_tutorial)
	_settings_button = GearButton.new()
	_settings_button.name = "SettingsButton"
	_settings_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_settings_button.offset_left = -32.0 - GearButton.SIZE
	_settings_button.offset_top = -32.0 - GearButton.SIZE
	_settings_button.offset_right = -32.0
	_settings_button.offset_bottom = -32.0
	_settings_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_settings_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_settings_button)
	_settings = SettingsPanel.new()
	add_child(_settings)
	_settings.closed.connect(func() -> void: _settings_button.grab_focus())
	_settings_button.pressed.connect(func() -> void: _settings.open(false))
	_how_to_play = HowToPlayPanel.new()
	_how_to_play.name = "HowToPlay"
	_how_to_play.visible = false
	_column.add_child(_how_to_play)
	_how_to_play.closed.connect(_show_main)
	_build_online()
	_practice.grab_focus()
	Audio.set_mood(&"menu")
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if Net.last_error != "":
		# Back from a failed or lost online session: say why.
		_show_online()
		_set_status(Net.last_error, true)
		Net.last_error = ""
	Log.info(&"menu", "main menu ready")


func _build_online() -> void:
	_online_box = VBoxContainer.new()
	_online_box.name = "Online"
	_online_box.custom_minimum_size = Vector2(540, 0)
	_online_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_online_box.add_theme_constant_override(&"separation", 12)
	_online_box.visible = false
	_column.add_child(_online_box)
	var title := Label.new()
	title.text = "PLAY ONLINE"
	title.theme_type_variation = &"HeadingLabel"
	title.add_theme_font_size_override(&"font_size", 44)
	title.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	_online_box.add_child(title)
	_name_edit = _field("Your name", SceneRouter.profile_name(), 24)
	_name_edit.text_submitted.connect(func(_t: String) -> void: _save_name())
	_name_edit.focus_exited.connect(_save_name)
	_online_box.add_child(_button("Create Party", _create))
	var join_row := HBoxContainer.new()
	_online_box.add_child(join_row)
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "ROOM CODE"
	_code_edit.max_length = 5
	_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code_edit.text_changed.connect(func(t: String) -> void:
		var caret: int = _code_edit.caret_column
		_code_edit.text = t.to_upper()
		_code_edit.caret_column = caret)
	_code_edit.text_submitted.connect(func(_t: String) -> void: _join_code())
	join_row.add_child(_code_edit)
	join_row.add_child(_button("Join", _join_code, 140))
	var ip_row := HBoxContainer.new()
	_online_box.add_child(ip_row)
	_ip_edit = LineEdit.new()
	_ip_edit.placeholder_text = "host:port (direct, for testing)"
	_ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ip_edit.text_submitted.connect(func(_t: String) -> void: _join_ip())
	ip_row.add_child(_ip_edit)
	ip_row.add_child(_button("Connect", _join_ip, 140))
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(540, 0)
	_online_box.add_child(_status)
	_online_box.add_child(_button("Back", _show_main))


func _field(placeholder: String, value: String, max_len: int) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.text = value
	e.max_length = max_len
	_online_box.add_child(e)
	return e


func _button(text: String, cb: Callable, min_width: float = 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_width, 52)
	b.pressed.connect(cb)
	return b


func _show_online() -> void:
	_main_box.visible = false
	_set_logo_visible(false)
	_online_box.visible = true
	_status.text = ""
	_online_box.get_child(2).grab_focus()  # Create Party


## TUTORIAL: for now the how-to-play pages. Placeholder for the later interactive tutorial (see
## `HowToPlayPanel`).
func _show_tutorial() -> void:
	_main_box.visible = false
	_set_logo_visible(false)
	_how_to_play.visible = true
	_how_to_play.show_page(0)


func _show_main() -> void:
	if _busy:
		return
	var from_tutorial: bool = _how_to_play.visible
	_online_box.visible = false
	_how_to_play.visible = false
	_set_logo_visible(true)
	_main_box.visible = true
	(_tutorial if from_tutorial else _play_online).grab_focus()


## Esc steps back out of the online form or the tutorial (the settings panel handles its own).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and (_online_box.visible or _how_to_play.visible):
		get_viewport().set_input_as_handled()
		_show_main()


## The online form is tall: the big logo steps aside while it is open.
func _set_logo_visible(on: bool) -> void:
	(_column.get_node("Logo") as Control).visible = on
	(_column.get_node("Rule") as Control).visible = on


func _save_name() -> void:
	var n: String = _name_edit.text.strip_edges()
	if n != "":
		Settings.set_value("profile", "name", n)
		Settings.save()


func _display_name() -> String:
	_save_name()
	return SceneRouter.profile_name()


func _set_status(text: String, error: bool = false) -> void:
	_status.text = text
	_status.add_theme_color_override(&"font_color", Palette.LOSS_RED if error else Palette.CREAM)


func _create() -> void:
	await _via_orchestrator(func(n: String) -> Dictionary: return await Net.online.create_party(n), "Creating party…")


func _join_code() -> void:
	var code: String = _code_edit.text.strip_edges().to_upper()
	if code.length() != 5:
		_set_status("Room codes have 5 letters.", true)
		return
	await _via_orchestrator(func(n: String) -> Dictionary: return await Net.online.join_party(n, code), "Joining %s…" % code)


func _via_orchestrator(call: Callable, busy_text: String) -> void:
	if _busy:
		return
	_busy = true
	_set_status(busy_text)
	var name_: String = _display_name()
	var room: Dictionary = await call.call(name_)
	if room.is_empty():
		_busy = false
		_set_status(Net.online.last_error, true)
		return
	_connect(func() -> Error: return Net.online.connect_room(room, name_, SceneRouter.profile_cosmetics()))


func _join_ip() -> void:
	if _busy:
		return
	var parts: PackedStringArray = _ip_edit.text.strip_edges().rsplit(":", true, 1)
	var host: String = parts[0] if parts.size() > 0 and parts[0] != "" else "127.0.0.1"
	var port: int = int(parts[1]) if parts.size() > 1 else Protocol.DEFAULT_PORT
	_busy = true
	_set_status("Connecting to %s:%d…" % [host, port])
	var hello: Dictionary = SceneRouter.profile_cosmetics()
	hello["name"] = _display_name()
	_connect(func() -> Error: return Net.join_server(host, port, hello))


## Starts the UDP connection; the match scene loads once the server welcomes us.
func _connect(start: Callable) -> void:
	Net.connected.connect(_on_connected, CONNECT_ONE_SHOT)
	Net.disconnected.connect(_on_failed, CONNECT_ONE_SHOT)
	var err: Error = start.call()
	if err != OK:
		_on_failed(Net.last_error if Net.last_error != "" else "Could not open a connection.")


func _on_connected() -> void:
	if Net.disconnected.is_connected(_on_failed):
		Net.disconnected.disconnect(_on_failed)
	SceneRouter.goto(SceneRouter.MATCH)


func _on_failed(reason: String) -> void:
	if Net.connected.is_connected(_on_connected):
		Net.connected.disconnect(_on_connected)
	_busy = false
	Net.last_error = ""
	_set_status(reason, true)


func _on_quit_pressed() -> void:
	get_tree().quit()
