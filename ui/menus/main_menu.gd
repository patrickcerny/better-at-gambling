extends Control
## Main menu, centred under the 3D logo (Patrick: "the main menu centered"): Play Online (create a
## lobby, join a friend's lobby), Practice (straight into a solo casino match;
## Patrick: "The practise mode should only be the game"; minigames only stays a lobby mode),
## Tutorial (how to play), Cosmetics (the shop, `CosmeticsPanel`), Quit, the profile line in the
## top-left corner (level, XP bar, Coins: `ProfileBadge`) and small buttons in the bottom-right
## corner: "?" (the tutorial again), the T-shirt (the cosmetics shop too) and the gear (settings). The first PRACTICE or PLAY ONLINE shows
## the tutorial first (Patrick: "The Tutorial pops up when you click practise or play for the first
## time") and then carries on to what the player chose; `tutorial/seen` in user://settings.cfg
## remembers it.
## Joining shows the joining screen (`Loading`, with the logo) until the match has loaded;
## connection errors from the last online attempt are shown here when we return. There is no
## join-by-address (Patrick: "Remove join by ip and port") and no lobby server of ours any more
## (Patrick 2026-11-14: "nur noch über Steam"): CREATE LOBBY runs the party on this PC and friends
## join through Steam invites or the "Join a friend" list (`SteamParty`); without Steam running the
## button is disabled ("Start Steam to play online"). `--connect` stays a dev/test command-line flag.

## PRACTICE starts a solo casino match: `practice_requested` fires first, then the match scene
## loads unless `load_match` is off (tests stop there instead of leaving the menu).
signal practice_requested(settings: Dictionary)

@onready var _play_online: Button = %PlayOnline
@onready var _practice: Button = %Practice
@onready var _tutorial: Button = %Tutorial
@onready var _cosmetics_entry: Button = %Cosmetics
@onready var _quit: Button = %Quit
@onready var _main_box: VBoxContainer = %VBox
@onready var _column: VBoxContainer = %Column

var _online_box: VBoxContainer
var _name_edit: LineEdit
## CREATE LOBBY (the party runs on this PC, friends join through Steam), and friends' lobbies.
var host_button: Button
var friends_box: VBoxContainer
var _friends_list: VBoxContainer
var _status: Label
var _busy: bool = false
var _settings: SettingsPanel
var _settings_button: GearButton
## The T-shirt button next to the gear and the cosmetics shop it opens (so does COSMETICS).
var cosmetics_button: TShirtButton
var cosmetics: CosmeticsPanel
## Level, XP bar and Coins in the top-left corner.
var profile_badge: ProfileBadge
var how_to_play: HowToPlayPanel
## DEV MODE under TUTORIAL and the panel it opens: only for Patrick's Steam account (`DevMode`);
## for everyone else neither exists.
var dev_entry: Button
var dev_panel: DevPanel
## The "?" left of the T-shirt: the tutorial any time.
var help_button: HelpButton
## What the tutorial opened on the first PRACTICE / PLAY ONLINE carries on to when it closes.
var _after_tutorial: Callable = Callable()
## Who gets the focus back when the tutorial closes to the main entries.
var _tutorial_opener: Control
## Off in tests: PRACTICE stops at `practice_requested` instead of loading the match.
var load_match: bool = true


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
	_practice.pressed.connect(func() -> void: _tutorial_first(start_practice))
	_play_online.pressed.connect(func() -> void: _tutorial_first(_show_online))
	_tutorial.pressed.connect(func() -> void: _show_tutorial(_tutorial))
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
	_settings_button.pressed.connect(func() -> void:
		cosmetics.close()
		_settings.open(false))
	# The cosmetics shop: the T-shirt left of the gear and the COSMETICS entry.
	cosmetics_button = TShirtButton.new()
	cosmetics_button.name = "CosmeticsButton"
	cosmetics_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	cosmetics_button.offset_left = -48.0 - 2.0 * GearButton.SIZE
	cosmetics_button.offset_top = -32.0 - GearButton.SIZE
	cosmetics_button.offset_right = -48.0 - GearButton.SIZE
	cosmetics_button.offset_bottom = -32.0
	cosmetics_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	cosmetics_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(cosmetics_button)
	cosmetics = CosmeticsPanel.new()
	add_child(cosmetics)
	var cosmetics_opener: Array[Control] = [cosmetics_button]
	cosmetics.closed.connect(func() -> void:
		if not _settings.visible and cosmetics_opener[0].is_visible_in_tree():
			cosmetics_opener[0].grab_focus())
	cosmetics_button.pressed.connect(func() -> void:
		cosmetics_opener[0] = cosmetics_button
		_settings.close()
		cosmetics.open())
	_cosmetics_entry.pressed.connect(func() -> void:
		cosmetics_opener[0] = _cosmetics_entry
		_settings.close()
		cosmetics.open())
	profile_badge = ProfileBadge.new()
	profile_badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	profile_badge.offset_left = 32.0
	profile_badge.offset_top = 28.0
	add_child(profile_badge)
	# The tutorial again any time: "?" left of the T-shirt.
	help_button = HelpButton.new()
	help_button.name = "HelpButton"
	help_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	help_button.offset_left = -64.0 - 3.0 * GearButton.SIZE
	help_button.offset_top = -32.0 - GearButton.SIZE
	help_button.offset_right = -64.0 - 2.0 * GearButton.SIZE
	help_button.offset_bottom = -32.0
	help_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	help_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(help_button)
	help_button.pressed.connect(func() -> void:
		if _busy:
			return  # joining: the online box stays up with its status
		_settings.close()
		cosmetics.close()
		_after_tutorial = Callable()
		_show_tutorial(help_button))
	how_to_play = HowToPlayPanel.new()
	how_to_play.name = "HowToPlay"
	how_to_play.visible = false
	_column.add_child(how_to_play)
	how_to_play.closed.connect(_on_tutorial_closed)
	if DevMode.allowed():
		_build_dev()
	_build_online()
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
	SteamSvc.join_requested.connect(_on_steam_join_requested)
	if SteamSvc.pending_lobby != 0:
		_on_steam_join_requested.call_deferred(SteamSvc.pending_lobby)
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
	host_button = _button(HOST_LABEL, _host_steam)
	host_button.name = "HostParty"
	_online_box.add_child(host_button)
	friends_box = VBoxContainer.new()
	friends_box.name = "JoinFriend"
	friends_box.add_theme_constant_override(&"separation", 6)
	_online_box.add_child(friends_box)
	var friends_title := Label.new()
	friends_title.text = "JOIN A FRIEND"
	friends_title.theme_type_variation = &"SmallLabel"
	friends_box.add_child(friends_title)
	_friends_list = VBoxContainer.new()
	friends_box.add_child(_friends_list)
	_refresh_steam_entries()
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(540, 0)
	_online_box.add_child(_status)
	_online_box.add_child(_button("Back", _show_main))


## Developer mode (Patrick only): DEV MODE under TUTORIAL and its panel.
func _build_dev() -> void:
	dev_entry = Button.new()
	dev_entry.name = "DevMode"
	dev_entry.text = "DEV MODE"
	dev_entry.custom_minimum_size = _tutorial.custom_minimum_size
	dev_entry.alignment = _tutorial.alignment
	dev_entry.add_theme_color_override(&"font_color", Palette.MONEY_GREEN)
	_main_box.add_child(dev_entry)
	_main_box.move_child(dev_entry, _tutorial.get_index() + 1)
	dev_panel = DevPanel.new()
	dev_panel.visible = false
	_column.add_child(dev_panel)
	dev_entry.pressed.connect(func() -> void:
		if _busy:
			return
		_settings.close()
		cosmetics.close()
		_hide_boxes()
		dev_panel.open())
	dev_panel.closed.connect(func() -> void:
		_show_main()
		dev_entry.grab_focus())
	dev_panel.practice_requested.connect(start_dev_practice)


## Developer mode's practice: a casino with dummies, or straight into one minigame.
func start_dev_practice(settings: Dictionary) -> void:
	if not DevMode.allowed():
		return
	DevMode.mark_used()
	SceneRouter.practice_settings = settings
	practice_requested.emit(SceneRouter.practice_settings)
	if load_match:
		SceneRouter.goto(SceneRouter.MATCH)


## PRACTICE: the solo casino match straight away (the match scene merges
## `SceneRouter.practice_settings` over the command line's).
func start_practice() -> void:
	SceneRouter.practice_settings = {"mode": MatchMode.CASINO}
	practice_requested.emit(SceneRouter.practice_settings)
	if load_match:
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
	how_to_play.visible = false
	if dev_panel != null:
		dev_panel.visible = false


func _show_online() -> void:
	_hide_boxes()
	_online_box.visible = true
	_status.text = ""
	_refresh_steam_entries()
	host_button.grab_focus()


## Whether the player has been through the tutorial once (`tutorial/seen` in user://settings.cfg).
static func tutorial_seen() -> bool:
	return bool(Settings.get_value("tutorial", "seen", false))


## PRACTICE / PLAY ONLINE: the first time ever, the tutorial comes first and `next` (the match or
## the box the player chose) follows when it closes; afterwards `next` straight away.
func _tutorial_first(next: Callable) -> void:
	if tutorial_seen():
		next.call()
		return
	_after_tutorial = next
	_show_tutorial(_tutorial)


## TUTORIAL or "?": the tutorial pages in place of the entries. `opener` gets the focus back.
func _show_tutorial(opener: Control) -> void:
	_tutorial_opener = opener
	_hide_boxes()
	how_to_play.open()


## DONE / SKIP / Esc: remembered as seen; on to the chosen match or box, or back to the entries.
func _on_tutorial_closed() -> void:
	Settings.set_value("tutorial", "seen", true)
	Settings.save()
	var next: Callable = _after_tutorial
	_after_tutorial = Callable()
	if next.is_valid():
		next.call()
		return
	_show_main()
	if _tutorial_opener != null and _tutorial_opener.is_visible_in_tree():
		_tutorial_opener.grab_focus()


func _show_main() -> void:
	if _busy:
		return
	_hide_boxes()
	_set_logo_visible(true)
	_main_box.visible = true
	_play_online.grab_focus()


## Esc steps back out of a sub-menu (the settings panel and the tutorial handle their own).
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"ui_cancel"):
		return
	if _online_box.visible:
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


# --- Connecting --------------------------------------------------------------------------------

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
	if Net.mode == Net.Mode.NONE:
		Net.steam_party.stop_hosting()  # hosting, but our own game could not join: no orphan server
		SteamSvc.leave_lobby()
	_set_status(reason, true)


# --- Lobbies (Steam) ---------------------------------------------------------------------------

const HOST_LABEL: String = "Create Lobby"
const FRIENDS_REFRESH: float = 3.0
var _friends_timer: float = 0.0


## Host button state and the friends' parties (Steam only).
func _refresh_steam_entries() -> void:
	var on: bool = SteamSvc.is_available()
	host_button.disabled = not on
	host_button.tooltip_text = "Invite your friends from the lobby" if on else "Start Steam to play online"
	friends_box.visible = on
	if not on:
		if not _busy and _status != null and _status.text == "":
			_set_status("Start Steam to play online.")
		return
	for c: Node in _friends_list.get_children():
		c.queue_free()
	var parties: Array[Dictionary] = SteamSvc.friend_lobbies()
	if parties.is_empty():
		var none := Label.new()
		none.text = "No friends in a lobby right now."
		none.theme_type_variation = &"MutedLabel"
		_friends_list.add_child(none)
	for f: Dictionary in parties:
		var lobby: int = int(f["lobby"])
		var party: String = str(f.get("party", ""))
		_friends_list.add_child(_button("Join %s" % (party if party != "" else "%s's lobby" % str(f["name"])), func() -> void: _join_steam_lobby(lobby)))


func _process(delta: float) -> void:
	if not _online_box.visible or not SteamSvc.is_available():
		return
	_friends_timer += delta
	if _friends_timer >= FRIENDS_REFRESH and not _busy:
		_friends_timer = 0.0
		_refresh_steam_entries()


## CREATE LOBBY: start the party server here, open the Steam lobby, then join it.
func _host_steam() -> void:
	if _busy or not SteamSvc.is_available():
		return
	_busy = true
	_set_status("Starting your lobby…")
	_status.remove_theme_color_override(&"font_color")
	var name_: String = _display_name()
	var port: int = await Net.steam_party.start_hosting(name_)
	if port == 0:
		_busy = false
		_set_status(Net.steam_party.last_error, true)
		return
	_connect(func() -> Error: return Net.steam_party.join_own_party(name_, SceneRouter.profile_cosmetics()), "CREATING LOBBY")


func _on_steam_join_requested(lobby_id: int) -> void:
	if not is_inside_tree():
		return
	if not _online_box.visible:
		_show_online()
	_join_steam_lobby(lobby_id)


## Joins a friend's party: their Steam lobby, then their game over Steam.
func _join_steam_lobby(lobby_id: int) -> void:
	SteamSvc.pending_lobby = 0
	if _busy:
		return
	_busy = true
	_set_status("Joining your friend's lobby…")
	_status.remove_theme_color_override(&"font_color")
	var host_id: int = await Net.steam_party.enter_lobby(lobby_id)
	if host_id == 0:
		_busy = false
		_set_status(Net.steam_party.last_error, true)
		return
	var name_: String = _display_name()
	_connect(func() -> Error: return Net.steam_party.join_host(host_id, name_, SceneRouter.profile_cosmetics()), "JOINING")


## QUIT asks first (Patrick: "Are you sure Dialog after quit game or leave game").
func _on_quit_pressed() -> void:
	ConfirmDialog.ask(self, "QUIT THE GAME?", "", "QUIT", func() -> void: get_tree().quit())
