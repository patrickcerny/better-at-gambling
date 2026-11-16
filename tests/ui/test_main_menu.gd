extends GutTest
## Main menu (Patrick's playtest notes): the logo and entries are centred; PLAY ONLINE, PRACTICE,
## TUTORIAL, QUIT; the settings sit behind a small gear in the bottom-right corner; no "Rejoin
## last party" and no LAN/IP hosting; lobbies only through Steam (Patrick 2026-11-14: "nur noch
## über Steam"); PLAY ONLINE is four picture cards (Patrick 2026-11-16): PUBLIC LOBBY, PRIVATE
## LOBBY, BROWSE LOBBIES, FRIENDS' LOBBIES, all simply disabled when Steam isn't running (as in these headless tests),
## with no "Start Steam" text (Patrick: "useless text"); TUTORIAL opens the how-to-play pages and
## DONE returns. (The first-run tutorial gate is in test_tutorial.gd; here the tutorial counts as
## seen.) PLAY ONLINE has no join-by-address and no room codes; PRACTICE goes
## straight into a solo casino match (Patrick: "The practise mode should only be the game, not the
## minigames selection"), no choice box in between.

var menu: Control
var _old_seen: Variant


func before_each() -> void:
	_old_seen = Settings.get_value("tutorial", "seen", "unset")
	Settings.set_value("tutorial", "seen", true)
	menu = (load("res://ui/menus/main_menu.tscn") as PackedScene).instantiate()
	add_child_autofree(menu)
	await wait_process_frames(3)


func after_each() -> void:
	# Put the player's own flag back ("unset": erase the key again).
	Settings.set_value("tutorial", "seen", null if typeof(_old_seen) == TYPE_STRING else _old_seen)
	Settings.save()


func _texts(root: Node) -> PackedStringArray:
	var out: PackedStringArray = []
	for b: Node in root.find_children("*", "Button", true, false):
		out.append((b as Button).text)
	return out


func _label_texts(root: Node) -> PackedStringArray:
	var out: PackedStringArray = []
	for l: Node in root.find_children("*", "Label", true, false):
		out.append((l as Label).text)
	return out


func test_entries_in_order_without_a_settings_entry() -> void:
	var box: VBoxContainer = menu.get_node("Center/Column/VBox")
	var names: PackedStringArray = []
	for b: Node in box.get_children():
		names.append((b as Button).text)
	assert_eq(names, PackedStringArray(["PLAY ONLINE", "PRACTICE", "TUTORIAL", "SHOP", "QUIT"]))


func test_every_entry_has_its_logo() -> void:
	# Patrick 2026-11-16: "its only text right now make it better with logos to distinguish".
	var seen: Array[Texture2D] = []
	for b: Node in menu.get_node("Center/Column/VBox").get_children():
		var t: Texture2D = (b as Button).icon
		assert_not_null(t, "%s has a logo" % (b as Button).text)
		assert_false(t in seen, "%s has its own logo" % (b as Button).text)
		seen.append(t)


func test_logo_and_entries_are_centred() -> void:
	var w: float = menu.get_viewport_rect().size.x
	var h: float = menu.get_viewport_rect().size.y
	for path: String in ["Center/Column/Logo", "Center/Column/Rule", "Center/Column/VBox", "Center/Column/VBox/PlayOnline"]:
		var r: Rect2 = (menu.get_node(path) as Control).get_global_rect()
		assert_almost_eq(r.get_center().x, w * 0.5, 2.0, "%s centred horizontally" % path)
	var col: Rect2 = (menu.get_node("Center/Column") as Control).get_global_rect()
	assert_almost_eq(col.get_center().y, h * 0.5, 4.0, "column centred vertically")
	for b: Node in menu.get_node("Center/Column/VBox").get_children():
		assert_eq((b as Button).alignment, HORIZONTAL_ALIGNMENT_CENTER, "%s text centred" % (b as Button).text)


func test_gear_in_the_bottom_right_opens_settings() -> void:
	var gear: GearButton = menu.find_child("SettingsButton", true, false) as GearButton
	assert_not_null(gear, "settings gear")
	if gear == null:
		return
	var vp: Vector2 = menu.get_viewport_rect().size
	var r: Rect2 = gear.get_global_rect()
	assert_gt(r.position.x, vp.x * 0.85, "right edge")
	assert_gt(r.position.y, vp.y * 0.85, "bottom edge")
	assert_lt(r.end.x, vp.x + 0.5)
	assert_lt(r.end.y, vp.y + 0.5)
	assert_lt(r.size.x, 100.0, "small")
	gear.pressed.emit()
	var settings: SettingsPanel = menu.find_children("*", "SettingsPanel", true, false)[0] as SettingsPanel
	assert_true(settings.visible)
	assert_false(settings._resume.visible, "no RESUME from the main menu")
	settings.close()
	assert_true(gear.has_focus(), "focus back on the gear")


func test_only_steam_hosting_and_no_rejoin() -> void:
	menu.call(&"_show_online")
	await wait_process_frames(1)
	for t: String in _texts(menu):
		assert_false(t.to_lower().contains("host on"), "no Host on this PC: %s" % t)
		assert_false(t.to_lower().contains("steam"), "no Steam wording, it's the only way: %s" % t)
		assert_false(t.to_lower().contains("rejoin"), "no Rejoin last party: %s" % t)
	assert_false(menu.has_method(&"_host_local"))
	assert_false(menu.has_method(&"_rejoin_last"))
	assert_true(menu.online.visible, "the online screen is there")
	for e: Node in menu.find_children("*", "LineEdit", true, false):
		assert_false((e as LineEdit).placeholder_text.to_lower().contains("code"), "no room codes")


func test_create_lobby_needs_steam() -> void:
	assert_false(SteamSvc.is_available(), "no Steam client in the headless tests")
	menu.call(&"_show_online")
	await wait_process_frames(1)
	for n: String in ["CreatePublic", "CreatePrivate", "BrowseLobbies", "FriendsLobbies"]:
		var c: PictureCard = menu.find_child(n, true, false) as PictureCard
		assert_not_null(c, n)
		if c != null:
			assert_true(c.disabled, "%s disabled without Steam" % n)
			assert_true(c.is_visible_in_tree())
	for t: String in _texts(menu) + _label_texts(menu):
		assert_false(t.to_lower().contains("start steam"), "no Start Steam text: %s" % t)
	assert_false((menu.find_child("JoinFriend", true, false) as Control).visible, "no friends list without Steam")
	menu.public_card.pressed.emit()  # even if it fired: nothing starts, nothing breaks
	await wait_process_frames(2)
	assert_eq(Net.mode, Net.Mode.NONE)
	assert_eq(Net.steam_party.server_pid, 0, "no server process started")


## Patrick 2026-11-16: "der play online button sollte uns jetzt in ein menu bringen mit bildern als
## buttons und die bild beschreiben was abgeht" and "Der Name in der Lobby ist auch nicht setzbar".
func test_play_online_is_four_picture_cards_without_a_name_field() -> void:
	menu.call(&"_show_online")
	await wait_process_frames(2)
	var online: OnlineMenu = menu.online
	assert_eq(online.get_parent(), menu, "a full screen over the menu")
	assert_eq(online.anchor_right, 1.0)
	assert_eq(online.anchor_bottom, 1.0)
	assert_eq(online.cards().size(), 4)
	for c: PictureCard in online.cards():
		assert_not_null(c.picture.texture, "%s has its picture" % c.name)
		assert_ne(c.caption_label.text, "", "%s says what happens" % c.name)
		assert_gt(c.size.x, 250.0, "%s is big" % c.name)
	assert_eq(online.public_card.get_parent(), online.top_row, "PUBLIC big on top")
	assert_eq(online.private_card.get_parent(), online.top_row, "PRIVATE big on top")
	assert_eq(online.browse_card.get_parent(), online.bottom_row, "BROWSE below")
	assert_eq(online.friends_card.get_parent(), online.bottom_row, "FRIENDS' below")
	assert_gt(online.public_card.size.x, online.browse_card.size.x * 1.2, "the top two are bigger")
	assert_eq(menu.find_children("*", "LineEdit", true, false).filter(func(e: Node) -> bool: return (e as Control).is_visible_in_tree()).size(), 0, "no name field")
	assert_false(menu.profile_badge.visible, "corner things step aside")
	online.set_friend_lobbies(2)
	assert_eq(online.friends_card.title_label.text, "Friends' Lobbies  ·  2")
	online.back_button.pressed.emit()
	assert_false(online.visible)
	assert_true((menu.get_node("Center/Column/VBox") as Control).visible)
	assert_true(menu.profile_badge.visible)


func test_online_name_is_the_steam_name() -> void:
	# No Steam here: the saved name; with Steam `SceneRouter.profile_name` is the persona name.
	assert_false(menu.has_method(&"_save_name"), "nothing to type a name into")
	assert_eq(menu.call(&"_display_name"), SceneRouter.profile_name())


func test_browse_list_rows() -> void:
	menu.call(&"_show_online")
	var box: Control = menu.find_child("Browse", true, false) as Control
	assert_not_null(box, "PUBLIC LOBBIES box")
	assert_false(box.visible)
	menu.call(&"_show_browse")  # no Steam: stays on PLAY ONLINE
	assert_false(box.visible)
	var rows: Array[Dictionary] = [SteamSvc.public_lobby_entry(11, "Anna's lobby", 3, 8), SteamSvc.public_lobby_entry(12, "  ", 1, 0)]
	menu.call(&"_fill_browse", rows)
	var list: Node = menu.find_child("LobbyList", true, false)
	assert_eq(list.get_child_count(), 2)
	var texts: PackedStringArray = _label_texts(list)
	assert_true("Anna's lobby" in texts)
	assert_true("3/8" in texts)
	assert_true("Lobby" in texts, "an empty name gets a stand-in")
	assert_true("1/%d" % Protocol.MAX_PLAYERS in texts)
	var sorted: Array[Dictionary] = menu.call(&"sort_public_lobbies", [SteamSvc.public_lobby_entry(1, "a", 2, 8), SteamSvc.public_lobby_entry(2, "b", 6, 8), SteamSvc.public_lobby_entry(3, "c", 1, 8), SteamSvc.public_lobby_entry(2, "b", 6, 8)] as Array[Dictionary], {3: ["Anna"]})
	assert_eq(sorted.map(func(l: Dictionary) -> int: return int(l["lobby"])), [3, 2, 1], "friends first, then fullest, each once")
	menu.call(&"_fill_friends", SteamSvc.group_friend_lobbies([{"name": "Anna", "lobby": 5, "party": "", "build": Protocol.BUILD_ID}, {"name": "Ben", "lobby": 5, "party": "", "build": Protocol.BUILD_ID}] as Array[Dictionary]))
	var friends_list: Node = menu.find_child("JoinFriend", true, false)
	assert_eq(friends_list.find_children("Lobby*", "PanelContainer", true, false).size(), 1, "two friends, one lobby card")
	assert_true("Friends: Anna and Ben" in _label_texts(friends_list))
	menu.call(&"_fill_browse", [] as Array[Dictionary])
	assert_eq(list.get_child_count(), 1, "just the 'no lobbies' line")


func test_no_join_by_ip_and_port() -> void:
	menu.call(&"_show_online")
	await wait_process_frames(1)
	for e: Node in menu.find_children("*", "LineEdit", true, false):
		var hint: String = (e as LineEdit).placeholder_text.to_lower()
		assert_false(hint.contains("host") or hint.contains("port") or hint.contains(":"), "no address field: %s" % hint)
	for t: String in _texts(menu):
		assert_ne(t, "Connect", "no direct Connect button")
	assert_false(menu.has_method(&"_join_ip"))


func test_practice_starts_the_solo_casino_match() -> void:
	var old_settings: Dictionary = SceneRouter.practice_settings
	SceneRouter.practice_settings = {"mode": MatchMode.MINIGAMES, "minigames": 3}
	menu.set(&"load_match", false)
	watch_signals(menu)
	(menu.get_node("Center/Column/VBox/Practice") as Button).pressed.emit()
	await wait_process_frames(1)
	assert_signal_emitted(menu, "practice_requested", "PRACTICE starts the match")
	assert_eq(SceneRouter.practice_settings, {"mode": MatchMode.CASINO, "no_minigames": true}, "the casino match without minigames")
	assert_null(menu.find_child("PracticeMenu", true, false), "no practice choice box")
	assert_null(menu.find_child("MinigamesOnly", true, false), "no minigames-only entry")
	assert_null(menu.get(&"practice_box"))
	SceneRouter.practice_settings = old_settings


func test_tutorial_pages_and_done() -> void:
	(menu.get_node("Center/Column/VBox/Tutorial") as Button).pressed.emit()
	await wait_process_frames(1)
	var how: HowToPlayPanel = menu.find_child("HowToPlay", true, false) as HowToPlayPanel
	assert_not_null(how)
	if how == null:
		return
	assert_true(how.visible)
	assert_false((menu.get_node("Center/Column/VBox") as Control).visible, "entries step aside")
	assert_gte(HowToPlayPanel.PAGES.size(), 7, "goal, moving, tables, items, odd jobs, minigames, rough play, jail, friends")
	assert_true(how.on_overview, "the three chapter cards first")
	how.chapter_cards[0].pressed.emit()
	assert_eq(how.page, 0)
	for i: int in HowToPlayPanel.PAGES.size() - 1:
		how.next_button.pressed.emit()
	assert_eq(how.page, HowToPlayPanel.PAGES.size() - 1)
	assert_false(how.next_button.visible)
	assert_true(how.done_button.visible)
	assert_false(how.body.text.contains("{"), "key names filled in")
	how.done_button.pressed.emit()
	assert_false(how.visible)
	assert_true((menu.get_node("Center/Column/VBox") as Control).visible)
	assert_true((menu.get_node("Center/Column/Logo") as Control).visible)
	assert_true((menu.get_node("Center/Column/VBox/Tutorial") as Button).has_focus(), "focus back on TUTORIAL")


func test_browse_cards_show_settings_and_beans() -> void:
	var info: Dictionary = LobbyInfo.parse(JSON.stringify({"mode": "casino", "mg": 5, "gm": 3, "items": true, "picked": 16, "all": 16,
		"beans": [{"n": "Patrick", "c": 1, "o": ["hat_top"], "l": true}, {"n": "Anna", "c": 4, "o": []}]}))
	menu.call(&"_fill_browse", [SteamSvc.public_lobby_entry(7, "Patrick's lobby", 2, 8, info)] as Array[Dictionary])
	var list: Node = menu.find_child("LobbyList", true, false)
	var texts: PackedStringArray = _label_texts(list)
	assert_true("Casino · 5 minigames · 3 min gambling · items on" in texts, "the lobby's settings")
	var beans: Node = list.find_child("Beans", true, false)
	assert_not_null(beans)
	assert_eq(beans.get_child_count(), 2, "one head per player")
	var tips: Array = beans.get_children().map(func(h: Control) -> String: return h.tooltip_text)
	assert_eq(tips, ["★ Patrick", "Anna"], "names as tooltips, the leader starred")
	for h: Control in beans.get_children():
		assert_eq(h.custom_minimum_size, Vector2(42, 42), "just a small head")


func test_lobby_lists_are_full_screens() -> void:
	for screen: LobbyListScreen in [menu.browse_screen, menu.friends_screen]:
		assert_eq(screen.get_parent(), menu, "over the whole menu, not in the centre column")
		assert_eq(screen.anchor_right, 1.0)
		assert_eq(screen.anchor_bottom, 1.0)
	assert_eq(menu.friends_screen.title.text, "FRIENDS' LOBBIES")
	assert_false(Array(_label_texts(menu.online)).has("JOIN A FRIEND"), "no friends list under PLAY ONLINE")
	menu._open_list(menu.friends_screen)
	assert_true(menu.friends_screen.visible)
	assert_false(menu.profile_badge.visible, "corner things step aside")
	assert_false(menu.online.visible)
	menu._back_to_online(menu.friends_card)
	assert_false(menu.friends_screen.visible)
	assert_true(menu.online.visible)


func test_browse_shows_other_versions_without_join() -> void:
	menu.call(&"_fill_browse", [SteamSvc.public_lobby_entry(8, "Old lobby", 2, 8, {}, "0.0.1"), SteamSvc.public_lobby_entry(9, "Ours", 1, 8)] as Array[Dictionary])
	var list: Node = menu.find_child("LobbyList", true, false)
	assert_eq(list.get_child(0).name, &"Lobby9", "joinable lobbies first")
	assert_true(Array(_label_texts(list)).any(func(t: String) -> bool: return t.begins_with("Version 0.0.1")), "the other version is named")
	var old: Node = list.find_child("Lobby8", true, false)
	var join: Button = old.find_children("*", "Button", true, false)[0] as Button
	assert_true(join.disabled, "another version can't be joined")


func test_daily_spin_opens_the_wheel_and_counts_down() -> void:
	ProfileManager.profile.daily_last = 0
	menu._refresh_daily()
	assert_true(menu.daily_button.spin_ready, "the big wheel button shines")
	assert_null(menu.get_node("Center/Column/VBox").get_node_or_null("DailySpin"), "no DAILY SPIN entry in the menu list")
	assert_eq(menu.daily_button.size.x, DailySpinButton.SIZE, "as wide as the three corner buttons")
	menu.daily_button.pressed.emit()
	assert_true(menu.daily_spin.visible)
	assert_false(menu.daily_spin.spin_button.disabled)
	menu.daily_spin.spin()
	assert_true(menu.daily_spin.wheel.busy(), "the wheel turns")
	assert_gt(ProfileManager.profile.daily_last, 0, "the spin is remembered")
	menu.daily_spin.close()
	menu._refresh_daily()
	assert_false(menu.daily_button.spin_ready, "and rests with the countdown")
	assert_ne(menu.daily_button.wait_text, "")
	ProfileManager.reload()


func test_trophy_opens_leaderboards_and_stats() -> void:
	var trophy: Button = menu.get_node("TrophyButton")
	var help: Control = menu.get_node("HelpButton")
	assert_lt(trophy.get_global_rect().position.x, help.get_global_rect().position.x, "left of the ?, bottom right")
	assert_gt(trophy.get_global_rect().position.y, menu.get_viewport_rect().size.y * 0.8)
	trophy.pressed.emit()
	await wait_process_frames(2)
	var panel: LeaderboardPanel = menu.leaderboards
	assert_true(panel.visible)
	assert_true(panel.boards_page.visible)
	assert_true(panel.status_label.text.contains("Steam"), "headless: no Steam, and it says so")
	panel.page_buttons[LeaderboardPanel.PAGE_STATS].pressed.emit()
	await wait_process_frames(2)
	assert_true(panel.stats_page.visible)
	assert_false(panel.boards_page.visible)
	assert_gt(panel.stats_grid.get_child_count(), 20)
	panel.close()
	assert_false(panel.visible)


## Patrick 2026-11-16: "I can open different dialogs (tutorial settings) over each other. Close the
## other one if I open the other." Opening any menu dialog closes whichever one was open.
func test_opening_a_dialog_closes_the_open_one() -> void:
	var tutorial: Button = menu.get_node("Center/Column/VBox/Tutorial")
	var gear: Button = menu.get_node("SettingsButton")
	tutorial.pressed.emit()
	await wait_process_frames(1)
	assert_true(menu.how_to_play.visible)
	gear.pressed.emit()
	await wait_process_frames(1)
	assert_true(menu._settings.visible, "settings open")
	assert_false(menu.how_to_play.visible, "the tutorial closed")
	assert_true((menu.get_node("Center/Column/VBox") as Control).visible, "the entries are back behind it")
	tutorial.pressed.emit()
	await wait_process_frames(1)
	assert_true(menu.how_to_play.visible)
	assert_false(menu._settings.visible, "and the other way round")
	menu.trophy_button.pressed.emit()
	assert_true(menu.leaderboards.visible)
	assert_false(menu.how_to_play.visible)
	menu.cosmetics_button.pressed.emit()
	assert_true(menu.cosmetics.visible)
	assert_false(menu.leaderboards.visible)
	menu.profile_badge.pressed.emit()
	assert_true(menu.level_pass.visible)
	assert_false(menu.cosmetics.visible)
	menu.daily_button.pressed.emit()
	assert_true(menu.daily_spin.visible)
	assert_false(menu.level_pass.visible)
	gear.pressed.emit()
	assert_true(menu._settings.visible)
	assert_false(menu.daily_spin.visible)
	var open := 0
	for d: Control in menu.dialogs.members:
		if d.visible:
			open += 1
	assert_eq(open, 1, "only ever one")
	menu._settings.close()


## The first-run tutorial before PRACTICE: replaced by another dialog, it does not go on into the
## match and does not count as seen.
func test_replaced_first_run_tutorial_does_not_start_the_match() -> void:
	Settings.set_value("tutorial", "seen", false)
	menu.load_match = false
	watch_signals(menu)
	(menu.get_node("Center/Column/VBox/Practice") as Button).pressed.emit()
	await wait_process_frames(1)
	assert_true(menu.how_to_play.visible)
	(menu.get_node("SettingsButton") as Button).pressed.emit()
	assert_false(menu.how_to_play.visible)
	assert_signal_not_emitted(menu, "practice_requested")
	assert_false(bool(Settings.get_value("tutorial", "seen", false)))
	menu._settings.close()


func test_clicking_the_wheel_spins_it() -> void:
	ProfileManager.profile.daily_last = 0
	menu.daily_button.pressed.emit()
	await wait_process_frames(2)
	var wheel: DailyWheelView = menu.daily_spin.wheel
	assert_true(wheel.clickable, "a free spin: the wheel takes a click")
	var corner := InputEventMouseButton.new()
	corner.button_index = MOUSE_BUTTON_LEFT
	corner.pressed = true
	corner.position = Vector2(1, 1)
	wheel._gui_input(corner)
	assert_false(wheel.busy(), "a click beside the wheel does nothing")
	var click := corner.duplicate() as InputEventMouseButton
	click.position = wheel.size * 0.5
	wheel._gui_input(click)
	assert_true(wheel.busy(), "a click on the wheel spins it")
	assert_gt(ProfileManager.profile.daily_last, 0)
	menu.daily_spin._refresh()
	assert_false(wheel.clickable, "not while it turns")
	menu.daily_spin.close()
	ProfileManager.reload()
