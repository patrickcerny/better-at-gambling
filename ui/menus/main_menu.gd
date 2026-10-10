extends Control
## Main menu, centred under the 3D logo (Patrick: "the main menu centered"): Play Online (create a
## party, join by code, browse public parties), Practice (a casino match or minigames only),
## Tutorial (how to play), Quit, and a small gear in the bottom-right corner for the settings.
## Joining shows the joining screen (`Loading`, with the logo) until the match has loaded;
## connection errors from the last online attempt are shown here when we return. There is no
## join-by-address (Patrick: "Remove join by ip and port"): parties are reached through the
## orchestrator only (`--connect` stays a dev/test command-line flag).

@onready var _play_online: Button = %PlayOnline
@onready var _practice: Button = %Practice
@onready var _tutorial: Button = %Tutorial
@onready var _quit: Button = %Quit
@onready var _main_box: VBoxContainer = %VBox
@onready var _column: VBoxContainer = %Column

var _online_box: VBoxContainer
var _name_edit: LineEdit
var _code_edit: LineEdit
var _create_button: Button
var _browse_button: Button
var _status: Label
var _busy: bool = false
var _settings: SettingsPanel
var _settings_button: GearButton
var _how_to_play: HowToPlayPanel
## Server browser (Patrick: "Server browser good"): public parties from the orchestrator.
var browser_box: VBoxContainer
var browser_list: VBoxContainer
var browser_status: Label
var _refresh_button: Button
var _browser_seq: int = 0
## Practice choice: a casino match or minigames only (Patrick: "Play minigames button").
var practice_box: VBoxContainer
var practice_count: int = 5
var _practice_casino: Button
var _practice_minigames: Button
var _practice_count_label: Label
var _practice_note: Label


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
	_practice.pressed.connect(_show_practice)
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
	_build_browser()
	_build_practice()
	_practice.grab_focus()
	Audio.set_mood(&"menu")
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Loading.cancel()  # back from a failed join: the joining screen goes
	if Net.last_error != "":
		# Back from a failed or lost online session (or a kick): say why.
		_show_online()
		_set_status(Net.last_error, true)
		Net.last_error = ""
	Log.info(&"menu", "main menu ready")


func _sub_box(box_name: String, title_text: String, width: float = 540.0) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = box_name
	box.custom_minimum_size = Vector2(width, 0)
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_theme_constant_override(&"separation", 12)
	box.visible = false
	_column.add_child(box)
	var title := Label.new()
	title.text = title_text
	title.theme_type_variation = &"HeadingLabel"
	title.add_theme_font_size_override(&"font_size", 44)
	title.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	box.add_child(title)
	return box


func _build_online() -> void:
	_online_box = _sub_box("Online", "PLAY ONLINE")
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Your name"
	_name_edit.text = SceneRouter.profile_name()
	_name_edit.max_length = 24
	_online_box.add_child(_name_edit)
	_name_edit.text_submitted.connect(func(_t: String) -> void: _save_name())
	_name_edit.focus_exited.connect(_save_name)
	_create_button = _button("Create Party", _create)
	_online_box.add_child(_create_button)
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
	_browse_button = _button("Browse Parties", _show_browser)
	_browse_button.name = "BrowseParties"
	_online_box.add_child(_browse_button)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(540, 0)
	_online_box.add_child(_status)
	_online_box.add_child(_button("Back", _show_main))


## PLAY ONLINE → Browse Parties: name, players/max, phase and a JOIN button per public party.
func _build_browser() -> void:
	browser_box = _sub_box("Browser", "PUBLIC PARTIES", 860.0)
	var hint := Label.new()
	hint.text = "Parties whose leader switched PUBLIC on in the lobby. Running matches take new players too."
	hint.theme_type_variation = &"MutedLabel"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	browser_box.add_child(hint)
	var frame := PanelContainer.new()
	frame.theme_type_variation = &"HudPlate"
	browser_box.add_child(frame)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 380)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	frame.add_child(scroll)
	browser_list = VBoxContainer.new()
	browser_list.name = "List"
	browser_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	browser_list.add_theme_constant_override(&"separation", 4)
	scroll.add_child(browser_list)
	browser_status = Label.new()
	browser_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	browser_box.add_child(browser_status)
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override(&"separation", 16)
	browser_box.add_child(bottom)
	_refresh_button = _button("Refresh", refresh_browser, 200)
	bottom.add_child(_refresh_button)
	bottom.add_child(_button("Back", _show_online, 200))


## PRACTICE: a casino match (as before) or MINIGAMES ONLY with a chosen number of minigames.
func _build_practice() -> void:
	practice_box = _sub_box("PracticeMenu", "PRACTICE")
	_practice_casino = _button("Casino Match", func() -> void: start_practice(MatchMode.CASINO))
	_practice_casino.name = "CasinoMatch"
	practice_box.add_child(_practice_casino)
	_practice_minigames = _button("Minigames Only", func() -> void: start_practice(MatchMode.MINIGAMES))
	_practice_minigames.name = "MinigamesOnly"
	practice_box.add_child(_practice_minigames)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	practice_box.add_child(row)
	var label := Label.new()
	label.text = "MINIGAMES"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	row.add_child(_button("−", func() -> void: _step_practice_count(-1), 54))
	_practice_count_label = Label.new()
	_practice_count_label.custom_minimum_size = Vector2(70, 0)
	_practice_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_practice_count_label)
	row.add_child(_button("+", func() -> void: _step_practice_count(1), 54))
	_practice_note = Label.new()
	_practice_note.theme_type_variation = &"SmallLabel"
	_practice_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_practice_note.custom_minimum_size = Vector2(540, 0)
	_practice_note.text = practice_note()
	practice_box.add_child(_practice_note)
	practice_box.add_child(_button("Back", _show_main))
	practice_count = int(SceneRouter.practice_settings.get("minigames", Registry.presets.default_minigames))
	_step_practice_count(0)


## Which minigames a solo practice can't play (they need more players).
static func practice_note() -> String:
	var defs: Array = Registry.minigames.values()
	var solo: PackedStringArray = []
	for d: MinigameDefinition in defs:
		if d.min_players <= 1:
			solo.append(d.display_name)
	var parts: PackedStringArray = []
	for d: MinigameDefinition in MatchMode.needs_more_players(defs, 1):
		parts.append("%s (%d+)" % [d.display_name, d.min_players])
	if parts.is_empty():
		return "Every minigame works solo."
	return "Solo you play %s. These need more players, so play them in a party: %s." % [", ".join(solo) if not solo.is_empty() else "none", ", ".join(parts)]


func _step_practice_count(step: int) -> void:
	var presets: MatchPresets = Registry.presets
	practice_count = clampi(practice_count + step, maxi(presets.min_minigames, 1), presets.max_minigames)
	_practice_count_label.text = "%d" % practice_count


## Starts a Practice match in `mode` (the match scene merges `SceneRouter.practice_settings`).
func start_practice(mode: StringName) -> void:
	SceneRouter.practice_settings = {"mode": mode}
	if mode == MatchMode.MINIGAMES:
		SceneRouter.practice_settings["minigames"] = practice_count
	SceneRouter.goto(SceneRouter.MATCH)


func _button(text: String, cb: Callable, min_width: float = 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_width, 52)
	b.pressed.connect(cb)
	return b


func _hide_boxes() -> void:
	_main_box.visible = false
	_set_logo_visible(false)
	_online_box.visible = false
	browser_box.visible = false
	practice_box.visible = false
	_how_to_play.visible = false


func _show_online() -> void:
	_hide_boxes()
	_online_box.visible = true
	_status.text = ""
	_create_button.grab_focus()


func _show_practice() -> void:
	_hide_boxes()
	practice_box.visible = true
	_practice_casino.grab_focus()


func _show_browser() -> void:
	if _busy:
		return
	_hide_boxes()
	browser_box.visible = true
	_refresh_button.grab_focus()
	refresh_browser()


## TUTORIAL: for now the how-to-play pages. Placeholder for the later interactive tutorial (see
## `HowToPlayPanel`).
func _show_tutorial() -> void:
	_hide_boxes()
	_how_to_play.visible = true
	_how_to_play.show_page(0)


func _show_main() -> void:
	if _busy:
		return
	var back_to: Button = _tutorial if _how_to_play.visible else (_practice if practice_box.visible else _play_online)
	_hide_boxes()
	_set_logo_visible(true)
	_main_box.visible = true
	back_to.grab_focus()


## Esc steps back out of a sub-menu (the settings panel handles its own).
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"ui_cancel"):
		return
	if browser_box.visible:
		get_viewport().set_input_as_handled()
		_show_online()
	elif _online_box.visible or _how_to_play.visible or practice_box.visible:
		get_viewport().set_input_as_handled()
		_show_main()


## The sub-menus are tall: the big logo steps aside while one is open.
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
	await _via_orchestrator(func(n: String) -> Dictionary: return await Net.online.create_party(n), "Creating party…", "CREATING PARTY")


func _join_code() -> void:
	var code: String = _code_edit.text.strip_edges().to_upper()
	if code.length() != 5:
		_set_status("Room codes have 5 letters.", true)
		return
	await _via_orchestrator(func(n: String) -> Dictionary: return await Net.online.join_party(n, code), "Joining %s…" % code, "JOINING %s" % code)


# --- Server browser ----------------------------------------------------------------------------

## Asks the orchestrator for the public parties and lists them.
func refresh_browser() -> void:
	_browser_seq += 1
	var seq: int = _browser_seq
	browser_status.text = "Looking for parties…"
	browser_status.remove_theme_color_override(&"font_color")
	_refresh_button.disabled = true
	var rooms: Array[Dictionary] = await Net.online.list_parties()
	if seq != _browser_seq or not is_inside_tree():
		return
	_refresh_button.disabled = false
	if rooms.is_empty() and Net.online.last_error != "":
		fill_browser([])
		browser_status.text = Net.online.last_error
		browser_status.add_theme_color_override(&"font_color", Palette.LOSS_RED)
		return
	fill_browser(rooms)


## One row per party: name, players/max, phase (and mode), JOIN.
func fill_browser(rooms: Array) -> void:
	for c: Node in browser_list.get_children():
		browser_list.remove_child(c)
		c.queue_free()
	browser_status.remove_theme_color_override(&"font_color")
	browser_status.text = "" if not rooms.is_empty() else "No public parties right now. Create one and switch PUBLIC on in the lobby (TAB)."
	for r: Variant in rooms:
		if r is Dictionary:
			browser_list.add_child(_browser_row(r))


static func phase_text(phase: String) -> String:
	match phase:
		"lobby":
			return "IN LOBBY"
		"match":
			return "PLAYING"
		"results":
			return "RESULTS"
	return phase.to_upper()


func _browser_row(r: Dictionary) -> Control:
	var framed := PanelContainer.new()
	framed.name = "Party%s" % str(r.get("room_code", ""))
	framed.theme_type_variation = &"RowPanel"
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 16)
	framed.add_child(row)
	var name_label := Label.new()
	name_label.text = str(r.get("name", "Party"))
	name_label.clip_text = true
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(name_label)
	var count := Label.new()
	count.name = "Players"
	count.text = "%d/%d" % [int(r.get("players", 0)), int(r.get("max_players", Protocol.MAX_PLAYERS))]
	count.custom_minimum_size = Vector2(70, 0)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(count)
	var phase := Label.new()
	phase.name = "Phase"
	var mode_tag: String = "  ·  MINIGAMES" if MatchMode.normalize(r.get("mode", "casino")) == MatchMode.MINIGAMES else ""
	phase.text = phase_text(str(r.get("phase", "lobby"))) + mode_tag
	phase.theme_type_variation = &"SmallLabel"
	phase.custom_minimum_size = Vector2(230, 0)
	phase.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	phase.add_theme_color_override(&"font_color", Palette.MONEY_GREEN if str(r.get("phase", "")) == "lobby" else Palette.WARM_GOLD)
	row.add_child(phase)
	var join := Button.new()
	join.name = "Join"
	join.text = "JOIN"
	join.custom_minimum_size = Vector2(120, 44)
	join.disabled = not bool(r.get("joinable", true))
	var room_id: String = str(r.get("room_id", ""))
	var code: String = str(r.get("room_code", ""))
	join.pressed.connect(func() -> void: _join_listed(room_id, code))
	row.add_child(join)
	return framed


func _join_listed(room_id: String, code: String) -> void:
	await _via_orchestrator(func(n: String) -> Dictionary: return await Net.online.join_party(n, "", room_id), "Joining %s…" % code, "JOINING %s" % code, browser_status)


# --- Connecting --------------------------------------------------------------------------------

func _via_orchestrator(call: Callable, busy_text: String, screen_text: String, status_label: Label = null) -> void:
	if _busy:
		return
	_busy = true
	var label: Label = status_label if status_label != null else _status
	label.text = busy_text
	label.remove_theme_color_override(&"font_color")
	var name_: String = _display_name()
	var room: Dictionary = await call.call(name_)
	if room.is_empty():
		_busy = false
		label.text = Net.online.last_error
		label.add_theme_color_override(&"font_color", Palette.LOSS_RED)
		return
	_connect(func() -> Error: return Net.online.connect_room(room, name_, SceneRouter.profile_cosmetics()), screen_text)


## Starts the UDP connection behind the joining screen; the match scene loads once the server
## welcomes us (the screen turns into the loading screen), or we come back here with the reason.
func _connect(start: Callable, screen_text: String) -> void:
	Net.connected.connect(_on_connected, CONNECT_ONE_SHOT)
	Net.disconnected.connect(_on_failed, CONNECT_ONE_SHOT)
	Loading.begin(screen_text)
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
	Loading.cancel()
	_busy = false
	Net.last_error = ""
	if browser_box.visible:
		_show_online()
	_set_status(reason, true)


func _on_quit_pressed() -> void:
	get_tree().quit()
