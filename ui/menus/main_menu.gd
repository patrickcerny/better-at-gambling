extends Control
## Main menu, centred under the 3D logo (Patrick: "the main menu centered"): Play Online (create a
## lobby, join a friend's lobby), Practice (straight into a solo casino match;
## Patrick: "The practise mode should only be the game"; minigames only stays a lobby mode),
## Tutorial (how to play), Shop (the cosmetics shop, `CosmeticsPanel`), Quit, the profile line in the
## top-left corner (level, XP bar, Coins: `ProfileBadge`) and small buttons in the bottom-right
## corner: the trophy (global leaderboards and your lifetime stats, Patrick 2026-11-16), "?" (the tutorial again), the T-shirt (your cosmetics inventory: only what you own, Patrick 2026-11-15) and the gear (settings). The first PRACTICE or PLAY ONLINE shows
## the tutorial first (Patrick: "The Tutorial pops up when you click practise or play for the first
## time") and then carries on to what the player chose; `tutorial/seen` in user://settings.cfg
## remembers it.
## Joining shows the joining screen (`Loading`, with the logo) until the match has loaded;
## connection errors from the last online attempt are shown here when we return. There is no
## join-by-address (Patrick: "Remove join by ip and port") and no lobby server of ours any more
## (Patrick 2026-11-14: "nur noch über Steam"): CREATE LOBBY runs the party on this PC, PUBLIC or
## PRIVATE (Patrick 2026-11-15: "open lobby, private public and browse lobbies"). Private = friends
## and invited players only (Steam invites, FRIENDS' LOBBIES); public lobbies are also
## listed under BROWSE LOBBIES for everyone (other versions greyed out, `SteamParty`). Both lists
## are full screens of small cards with the players' heads (`LobbyListScreen`). Without Steam
## running the online buttons are just disabled, with no text about it (Patrick: "useless text").
## `--connect` stays a dev/test command-line flag.

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
## PUBLIC / PRIVATE for the next CREATE LOBBY (remembered in `online/public_lobby`).
var public_toggle: Button
var private_toggle: Button
## BROWSE LOBBIES and the full-screen PUBLIC LOBBIES it opens.
var browse_button: Button
var browse_screen: LobbyListScreen
## FRIENDS' LOBBIES and its full-screen list (the lobbies your Steam friends are in).
var friends_button: Button
var friends_screen: LobbyListScreen
var _online_back: Button
var _status: Label
var _busy: bool = false
var _settings: SettingsPanel
var _settings_button: GearButton
## The T-shirt button next to the gear and the cosmetics shop it opens (so does COSMETICS).
var cosmetics_button: TShirtButton
var cosmetics: CosmeticsPanel
## Level, XP bar and Coins in the top-left corner.
var profile_badge: ProfileBadge
## The red dots on the T-shirt and the COSMETICS entry: rewards waiting in the COLLECT tab.
var _shop_dots: Array[NotifyDot] = []
var level_pass: LevelPassPanel
var how_to_play: HowToPlayPanel
## The small dev button (bottom right, `DevButton`) and the Dev Dashboard it opens: only for
## Patrick's Steam account (`DevMode`); for everyone else neither exists.
var dev_entry: Button
var dev_panel: DevPanel
## The prize wheel the big Daily Spin button opens (`DailySpinPanel`).
var daily_spin: DailySpinPanel
## The big wheel button above the corner buttons (Patrick 2026-11-16), always there.
var daily_button: DailySpinButton
var _daily_tick: float = 0.0
## The "?" left of the T-shirt: the tutorial any time.
var help_button: HelpButton
## "Your game is out of date" (top right) and the check behind it (`VersionCheck`).
var update_banner: UpdateBanner
var version_check: VersionCheck
## The trophy left of the "?": global leaderboards and your lifetime stats (`LeaderboardPanel`).
var trophy_button: TrophyButton
var leaderboards: LeaderboardPanel
## Settings, cosmetics, level pass, leaderboards, daily spin, tutorial and dev panel: opening one
## closes whichever other one is open (Patrick 2026-11-16).
var dialogs := DialogGroup.new()
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
	_settings_button.pressed.connect(func() -> void: _settings.open(false))
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
	cosmetics_button.tooltip_text = "My cosmetics"
	cosmetics_button.pressed.connect(func() -> void:
		cosmetics_opener[0] = cosmetics_button
		cosmetics.open(true))  # the T-shirt: your own things, to wear
	_cosmetics_entry.pressed.connect(func() -> void:
		cosmetics_opener[0] = _cosmetics_entry
		cosmetics.open())
	# Rewards waiting in the shop's COLLECT tab: a red dot with the count on both shop buttons.
	_shop_dots = [NotifyDot.attach(cosmetics_button), NotifyDot.attach(_cosmetics_entry, true)]
	ProfileManager.changed.connect(_count_shop_dots)
	_count_shop_dots()
	profile_badge = ProfileBadge.new()
	profile_badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	profile_badge.offset_left = 32.0
	profile_badge.offset_top = 28.0
	add_child(profile_badge)
	# Click the profile line: the level pass (every level's Coins and unlocks).
	level_pass = LevelPassPanel.new()
	add_child(level_pass)
	profile_badge.pressed.connect(level_pass.open)
	# The Gold Coins on the profile line (and their +): straight to the shop's GOLD packs.
	profile_badge.gold_pressed.connect(func() -> void:
		cosmetics_opener[0] = _cosmetics_entry
		cosmetics.open()
		cosmetics.open_gold_shop())
	level_pass.item_pressed.connect(func(id: StringName) -> void:
		level_pass.close()
		cosmetics.open()
		cosmetics.select(id)
		var d: CosmeticDef = CosmeticShop.default().find(id)
		if d != null:
			cosmetics.show_kind(d.kind))
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
		_after_tutorial = Callable()
		_show_tutorial(help_button))
	_build_leaderboards()
	_build_daily()
	_build_update_banner()
	how_to_play = HowToPlayPanel.new()
	how_to_play.name = "HowToPlay"
	how_to_play.visible = false
	_column.add_child(how_to_play)
	how_to_play.closed.connect(_on_tutorial_closed)
	if DevMode.allowed():
		_build_dev()
	_build_online()
	for d: Control in [_settings, cosmetics, level_pass, leaderboards, daily_spin, how_to_play, dev_panel]:
		dialogs.add(d)
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


func _build_update_banner() -> void:
	update_banner = UpdateBanner.new()
	update_banner.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	update_banner.offset_left = -32.0 - UpdateBanner.WIDTH
	update_banner.offset_right = -32.0
	update_banner.offset_top = 28.0
	update_banner.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(update_banner)
	version_check = VersionCheck.new()
	version_check.name = "VersionCheck"
	version_check.checked.connect(update_banner.show_verdict)
	add_child(version_check)


## The trophy left of the "?" and the leaderboards / stats panel it opens.
func _build_leaderboards() -> void:
	trophy_button = TrophyButton.new()
	trophy_button.name = "TrophyButton"
	trophy_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	trophy_button.offset_left = -80.0 - 4.0 * GearButton.SIZE
	trophy_button.offset_top = -32.0 - GearButton.SIZE
	trophy_button.offset_right = -80.0 - 3.0 * GearButton.SIZE
	trophy_button.offset_bottom = -32.0
	trophy_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	trophy_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(trophy_button)
	leaderboards = LeaderboardPanel.new()
	add_child(leaderboards)
	leaderboards.closed.connect(func() -> void:
		if trophy_button.is_visible_in_tree():
			trophy_button.grab_focus())
	trophy_button.pressed.connect(func() -> void:
		if _busy:
			return
		leaderboards.open())


func _build_daily() -> void:
	daily_spin = DailySpinPanel.new()
	add_child(daily_spin)
	daily_spin.closed.connect(func() -> void:
		_refresh_daily()
		if daily_button.is_visible_in_tree():
			daily_button.grab_focus())
	# The big wheel above the three corner buttons, as wide as they are together.
	daily_button = DailySpinButton.new()
	daily_button.name = "DailySpinButton"
	daily_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	daily_button.offset_right = -32.0
	daily_button.offset_left = -32.0 - DailySpinButton.SIZE
	daily_button.offset_bottom = -48.0 - GearButton.SIZE
	daily_button.offset_top = -48.0 - GearButton.SIZE - DailySpinButton.SIZE
	daily_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	daily_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(daily_button)
	move_child(daily_button, daily_spin.get_index())  # under the wheel panel
	daily_button.pressed.connect(daily_spin.open)
	_refresh_daily()


## The big wheel button shines while a spin is free, else says when the next one is.
func _refresh_daily() -> void:
	if daily_button == null:
		return
	var w: int = DailySpinPanel.wait_s()
	daily_button.set_state(w <= 0, DailyWheel.wait_text(w))


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
	PadKeyboard.attach(_name_edit)  # A on it with a gamepad: Steam's keyboard (Deck) or ours
	var kind_row := HBoxContainer.new()
	kind_row.name = "LobbyKind"
	kind_row.add_theme_constant_override(&"separation", 8)
	_online_box.add_child(kind_row)
	var group := ButtonGroup.new()
	public_toggle = _button("Public", func() -> void: _set_public(true))
	public_toggle.name = "Public"
	public_toggle.tooltip_text = "Anyone can find and join it under Browse Lobbies"
	private_toggle = _button("Private", func() -> void: _set_public(false))
	private_toggle.name = "Private"
	private_toggle.tooltip_text = "Only your friends and players you invite can join"
	for t: Button in [public_toggle, private_toggle]:
		t.toggle_mode = true
		t.button_group = group
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		kind_row.add_child(t)
	(public_toggle if lobby_public() else private_toggle).set_pressed_no_signal(true)
	host_button = _button(HOST_LABEL, _host_steam)
	host_button.name = "HostParty"
	_online_box.add_child(host_button)
	browse_button = _button("Browse Lobbies", _show_browse)
	browse_button.name = "BrowseLobbies"
	_online_box.add_child(browse_button)
	friends_button = _button(FRIENDS_LABEL, _show_friends)
	friends_button.name = "FriendsLobbies"
	_online_box.add_child(friends_button)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(540, 0)
	_online_box.add_child(_status)
	_online_back = _button("Back", _show_main)
	_online_box.add_child(_online_back)
	_build_lists()
	_refresh_steam_entries()


## PUBLIC LOBBIES and FRIENDS' LOBBIES: full screens over the whole menu (`LobbyListScreen`).
func _build_lists() -> void:
	add_child(BeanPortraits.new())  # the heads on the lobby cards
	browse_screen = LobbyListScreen.new("Browse", "PUBLIC LOBBIES")
	add_child(browse_screen)
	browse_screen.refresh_pressed.connect(_refresh_browse)
	browse_screen.back_pressed.connect(_back_to_online.bind(browse_button))
	friends_screen = LobbyListScreen.new("JoinFriend", "FRIENDS' LOBBIES")
	add_child(friends_screen)
	friends_screen.refresh_pressed.connect(_refresh_steam_entries)
	friends_screen.back_pressed.connect(_back_to_online.bind(friends_button))
	SteamSvc.public_lobbies_received.connect(_on_public_lobbies)


## Developer mode (Patrick only): the small "</>" corner button above the trophy, left of the
## Daily Spin wheel (Patrick 2026-11-16), and the Dev Dashboard it opens.
func _build_dev() -> void:
	dev_panel = DevPanel.new()
	add_child(dev_panel)
	dev_entry = DevButton.new()
	dev_entry.name = "DevMode"
	dev_entry.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	# Right-aligned with the trophy, its bottom level with the wheel's.
	dev_entry.offset_right = -80.0 - 3.0 * GearButton.SIZE
	dev_entry.offset_left = dev_entry.offset_right - DevButton.SMALL
	dev_entry.offset_bottom = -48.0 - GearButton.SIZE
	dev_entry.offset_top = dev_entry.offset_bottom - DevButton.SMALL
	dev_entry.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	dev_entry.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(dev_entry)
	move_child(dev_entry, trophy_button.get_index())  # with the corner buttons, under every panel
	dev_entry.pressed.connect(func() -> void:
		if _busy:
			return
		dev_panel.open())
	dev_panel.closed.connect(func() -> void:
		if dev_entry.is_visible_in_tree():
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
## `SceneRouter.practice_settings` over the command line's). No minigames (Patrick 2026-11-16):
## the rounds turn over in the casino where a minigame would start.
func start_practice() -> void:
	SceneRouter.practice_settings = {"mode": MatchMode.CASINO, "no_minigames": true}
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
	browse_screen.visible = false
	friends_screen.visible = false
	_set_corner_visible(true)
	how_to_play.visible = false
	if dev_panel != null:
		dev_panel.close()


func _show_online() -> void:
	_hide_boxes()
	_online_box.visible = true
	if not _busy:
		_status.text = ""
	_refresh_steam_entries()
	(host_button if not host_button.disabled else _online_back).grab_focus()


func _show_browse() -> void:
	if _busy or not SteamSvc.is_available():
		return
	_open_list(browse_screen)
	_refresh_browse()
	browse_screen.focus_first()


func _show_friends() -> void:
	if _busy or not SteamSvc.is_available():
		return
	_open_list(friends_screen)
	_refresh_steam_entries()
	friends_screen.focus_first()


func _open_list(screen: LobbyListScreen) -> void:
	_hide_boxes()
	_set_corner_visible(false)
	screen.status.text = ""
	screen.visible = true


## BACK / Esc on a lobby list: PLAY ONLINE again, the focus on the button that opened the list.
func _back_to_online(opener: Button) -> void:
	if _busy:
		return
	_show_online()
	if not opener.disabled:
		opener.grab_focus()


## The profile line and the corner buttons step aside while a full-screen lobby list is open.
func _set_corner_visible(on: bool) -> void:
	for c: Control in [profile_badge, _settings_button, cosmetics_button, help_button, trophy_button, daily_button, dev_entry]:
		if c != null:
			c.visible = on


## Whether CREATE LOBBY makes a public lobby (default: private).
static func lobby_public() -> bool:
	return bool(Settings.get_value("online", "public_lobby", false))


func _set_public(on: bool) -> void:
	Settings.set_value("online", "public_lobby", on)
	Settings.save()


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
## Closed because another dialog opened (settings, cosmetics, ...): just back to the entries.
func _on_tutorial_closed() -> void:
	if dialogs.replacing != null:
		# Not `_show_main()`: its `_hide_boxes()` would close the dialog that is opening.
		_after_tutorial = Callable()
		_set_logo_visible(true)
		_main_box.visible = true
		return
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
	if browse_screen.visible or friends_screen.visible:
		get_viewport().set_input_as_handled()
		_back_to_online(browse_button if browse_screen.visible else friends_button)
	elif _online_box.visible:
		get_viewport().set_input_as_handled()
		_show_main()


func _count_shop_dots() -> void:
	var n: int = ProfileManager.profile.collectable().size()
	for dot: NotifyDot in _shop_dots:
		dot.count = n


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


## The status line of the open box (PLAY ONLINE or a lobby list).
func _set_status(text: String, error: bool = false) -> void:
	for l: Label in [_status, browse_screen.status if browse_screen != null else null, friends_screen.status if friends_screen != null else null]:
		if l == null:
			continue
		l.text = text
		l.add_theme_color_override(&"font_color", Palette.LOSS_RED if error else Palette.CREAM)


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
const FRIENDS_LABEL: String = "Friends' Lobbies"
const FRIENDS_REFRESH: float = 3.0
## BROWSE LOBBIES asks Steam again this often while it is open.
const BROWSE_REFRESH: float = 8.0
var _friends_timer: float = 0.0
var _browse_timer: float = 0.0
## Lobby id -> names of your friends in it (from FRIENDS' LOBBIES), for BROWSE LOBBIES.
var _friend_lobby_ids: Dictionary = {}


## Host button state and the friends' parties (Steam only).
func _refresh_steam_entries() -> void:
	var on: bool = SteamSvc.is_available()
	for b: Button in [host_button, browse_button, friends_button, public_toggle, private_toggle]:
		b.disabled = not on
	host_button.tooltip_text = "Invite your friends from the lobby" if on else ""
	friends_button.text = FRIENDS_LABEL
	if not on:
		return
	var parties: Array[Dictionary] = SteamSvc.friend_lobbies()
	_friend_lobby_ids.clear()
	for f: Dictionary in parties:
		_friend_lobby_ids[int(f["lobby"])] = (f["friends"] as Array).duplicate()
	if not parties.is_empty():
		friends_button.text = "%s  ·  %d" % [FRIENDS_LABEL, parties.size()]
	_fill_friends(parties)


## FRIENDS' LOBBIES: one card per lobby (never one per friend), with who of your friends is in it.
func _fill_friends(parties: Array[Dictionary]) -> void:
	var cards: Array[Control] = []
	for f: Dictionary in parties:
		var friends: Array = f["friends"]
		var party: String = str(f.get("party", ""))
		var title: String = party if party != "" else "%s's lobby" % str(friends[0])
		var build: String = str(f.get("build", ""))
		var same: bool = build == "" or build == Protocol.BUILD_ID
		var sub: String = "Friends: %s" % SteamSvc.friends_text(friends) if same else "Version %s (you have %s)" % [build, Protocol.BUILD_ID]
		cards.append(_lobby_row(int(f["lobby"]), title, sub, int(f.get("members", 0)), int(f.get("max", 0)), same, f.get("info", {})))
	friends_screen.set_cards(cards, "No friends in a lobby right now.")


## One lobby as a small card (Patrick 2026-11-16: "way smaller the stuff only peek the heads of
## the players"): its name, who of your friends is in it (or why it can't be joined), the host's
## settings, players and JOIN on top; under that a row of the players' heads in their colour and
## outfit, the leader's ring in gold, the names as tooltips. Hosts on an older version send no
## `info`: then there are no settings and no heads.
func _lobby_row(lid: int, title_text: String, sub_text: String, members: int, max_members: int, joinable: bool = true, info: Dictionary = {}) -> Control:
	var card := PanelContainer.new()
	card.name = "Lobby%d" % lid
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(LobbyListScreen.CARD_WIDTH, 0)
	var sb: StyleBoxFlat = LobbyPanel.box(Color("#221E1C"), Color("#3A322C"), 12, 1)
	sb.set_content_margin_all(10)
	card.add_theme_stylebox_override(&"panel", sb)
	if not joinable:
		card.modulate = Color(1, 1, 1, 0.55)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 6)
	card.add_child(v)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	v.add_child(row)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override(&"separation", -3)
	row.add_child(text)
	var title := Label.new()
	title.text = title_text
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.add_theme_font_size_override(&"font_size", 21)
	text.add_child(title)
	var settings: String = LobbyInfo.settings_text(info)
	for line: String in [sub_text, settings]:
		if line == "":
			continue
		var sub := Label.new()
		sub.text = line
		sub.tooltip_text = line
		sub.mouse_filter = Control.MOUSE_FILTER_PASS
		sub.theme_type_variation = &"MutedLabel"
		sub.add_theme_font_size_override(&"font_size", 14)
		if line == sub_text and sub_text.begins_with("Friends"):
			sub.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
		sub.clip_text = true
		sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		text.add_child(sub)
	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_theme_constant_override(&"separation", -2)
	row.add_child(right)
	var count := Label.new()
	count.text = "%d/%d" % [members, max_members if max_members > 0 else Protocol.MAX_PLAYERS] if members > 0 else ""
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.add_theme_font_size_override(&"font_size", 20)
	count.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	right.add_child(count)
	if bool(info.get("playing", false)):
		var playing := Label.new()
		playing.text = "IN A MATCH"
		playing.theme_type_variation = &"SmallLabel"
		playing.add_theme_font_size_override(&"font_size", 11)
		playing.add_theme_color_override(&"font_color", Palette.CASINO_RED.lightened(0.25))
		right.add_child(playing)
	var join := _button("Join", func() -> void: _join_steam_lobby(lid), 92.0)
	join.name = "Join"
	join.custom_minimum_size.y = 40
	join.add_theme_font_size_override(&"font_size", 18)
	join.disabled = not joinable
	join.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(join)
	var beans: Array = info.get("beans", [])
	if not beans.is_empty():
		var heads := HBoxContainer.new()
		heads.name = "Beans"
		heads.add_theme_constant_override(&"separation", 5)
		v.add_child(heads)
		for b: Dictionary in beans:
			heads.add_child(_lobby_head(b))
	return card


const HEAD_SIZE: float = 42.0


## One player of a lobby card: a round peek of the bean's head in its outfit, ringed in its
## colour (gold for the leader, with a star), the name as the tooltip.
func _lobby_head(b: Dictionary) -> Control:
	var leader: bool = bool(b.get("leader", false))
	var name_: String = str(b.get("name", ""))
	var medal := Panel.new()
	medal.name = "Head"
	medal.custom_minimum_size = Vector2(HEAD_SIZE, HEAD_SIZE)
	medal.tooltip_text = ("★ " if leader else "") + name_
	medal.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	medal.add_theme_stylebox_override(&"panel", LobbyPanel.box(Color("#3A302A"), Color(0, 0, 0, 0), int(HEAD_SIZE / 2.0)))
	var pic := TextureRect.new()
	pic.name = "Portrait"
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.texture = BeanPortraits.texture_for(int(b.get("color", 0)), b.get("outfit", []), BeanPortraits.Framing.HEAD)
	medal.add_child(pic)
	var ring := Panel.new()  # over the clipped picture so the ring stays crisp
	ring.name = "Ring"
	ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ring_color: Color = Palette.VIP_GOLD if leader else PlayerColors.own({"bean_color": int(b.get("color", 0)), "outfit": b.get("outfit", [])})
	ring.add_theme_stylebox_override(&"panel", LobbyPanel.box(Color(0, 0, 0, 0), ring_color, int(HEAD_SIZE / 2.0), 3 if leader else 2))
	medal.add_child(ring)
	return medal


func _process(delta: float) -> void:
	_daily_tick += delta
	if _daily_tick >= 1.0:
		_daily_tick = 0.0
		_refresh_daily()
	if browse_screen.visible and SteamSvc.is_available() and not _busy:
		_browse_timer += delta
		if _browse_timer >= BROWSE_REFRESH:
			_refresh_browse()
	if not (_online_box.visible or friends_screen.visible) or not SteamSvc.is_available():
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
	var port: int = await Net.steam_party.start_hosting(name_, public_toggle.button_pressed)
	if port == 0:
		_busy = false
		_set_status(Net.steam_party.last_error, true)
		return
	_connect(func() -> Error: return Net.steam_party.join_own_party(name_, SceneRouter.profile_cosmetics()), "CREATING LOBBY")


func _on_steam_join_requested(lobby_id: int) -> void:
	if not is_inside_tree():
		return
	if not (_online_box.visible or browse_screen.visible or friends_screen.visible):
		_show_online()
	_join_steam_lobby(lobby_id)


## Joins a party (a friend's, or a public one from BROWSE LOBBIES): its Steam lobby, then the
## host's game over Steam.
func _join_steam_lobby(lobby_id: int) -> void:
	SteamSvc.pending_lobby = 0
	if _busy:
		return
	_busy = true
	_set_status("Joining the lobby…")
	_status.remove_theme_color_override(&"font_color")
	var host_id: int = await Net.steam_party.enter_lobby(lobby_id)
	if host_id == 0:
		_busy = false
		_set_status(Net.steam_party.last_error, true)
		return
	var name_: String = _display_name()
	_connect(func() -> Error: return Net.steam_party.join_host(host_id, name_, SceneRouter.profile_cosmetics()), "JOINING")


## Asks Steam for the public lobbies again (the list redraws when they arrive).
func _refresh_browse() -> void:
	_browse_timer = 0.0
	_friend_lobby_ids.clear()
	for f: Dictionary in SteamSvc.friend_lobbies():
		_friend_lobby_ids[int(f["lobby"])] = (f["friends"] as Array).duplicate()
	if not SteamSvc.request_public_lobbies() and browse_screen.grid.get_child_count() == 0:
		_fill_browse([])


func _on_public_lobbies(lobbies: Array[Dictionary]) -> void:
	if browse_screen.visible:
		_fill_browse(lobbies)


## Lobbies with your friends first, then the fullest (a game about to start), each lobby once.
static func sort_public_lobbies(lobbies: Array[Dictionary], friend_lobbies_: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ids: Dictionary[int, bool] = {}
	for l: Dictionary in lobbies:
		if not ids.has(int(l["lobby"])):
			ids[int(l["lobby"])] = true
			out.append(l)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var fa: int = (friend_lobbies_.get(int(a["lobby"]), []) as Array).size()
		var fb: int = (friend_lobbies_.get(int(b["lobby"]), []) as Array).size()
		var va: bool = str(a.get("build", Protocol.BUILD_ID)) == Protocol.BUILD_ID
		var vb: bool = str(b.get("build", Protocol.BUILD_ID)) == Protocol.BUILD_ID
		if va != vb:
			return va  # lobbies we can join first
		if fa != fb:
			return fa > fb
		return int(a["members"]) > int(b["members"]))
	return out


## Why a public lobby of another version can't be joined, and what to do about it.
static func version_text(build: String) -> String:
	if build == "":
		return "Version unknown, refresh in a moment"
	if VersionCheck.compare_versions(build, Protocol.BUILD_ID) > 0:
		return "Version %s (you have %s): your game is out of date, restart Steam to update" % [build, Protocol.BUILD_ID]
	return "Version %s (you have %s): the host's game is out of date" % [build, Protocol.BUILD_ID]


## One card per public lobby: its name, your friends in it, players and JOIN; full ones are left
## out by Steam.
func _fill_browse(lobbies: Array[Dictionary]) -> void:
	var cards: Array[Control] = []
	for l: Dictionary in sort_public_lobbies(lobbies, _friend_lobby_ids):
		var lid: int = int(l["lobby"])
		var friends: Array = _friend_lobby_ids.get(lid, [])
		var sub: String = "Friends: %s" % SteamSvc.friends_text(friends) if not friends.is_empty() else ""
		var build: String = str(l.get("build", Protocol.BUILD_ID))
		var same: bool = build == Protocol.BUILD_ID
		if not same:
			sub = version_text(build)
		cards.append(_lobby_row(lid, str(l["name"]), sub, int(l["members"]), int(l["max"]), same, l.get("info", {})))
	browse_screen.set_cards(cards, "No public lobbies right now. Create one!")


## QUIT asks first (Patrick: "Are you sure Dialog after quit game or leave game").
func _on_quit_pressed() -> void:
	ConfirmDialog.ask(self, "QUIT THE GAME?", "", "QUIT", func() -> void: get_tree().quit())
