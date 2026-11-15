extends GutTest
## Main menu (Patrick's playtest notes): the logo and entries are centred; PLAY ONLINE, PRACTICE,
## TUTORIAL, QUIT; the settings sit behind a small gear in the bottom-right corner; no "Rejoin
## last party" and no LAN/IP hosting; lobbies only through Steam (Patrick 2026-11-14: "nur noch
## über Steam", and the button just says CREATE LOBBY), PUBLIC / PRIVATE and BROWSE LOBBIES
## (Patrick 2026-11-15), all simply disabled when Steam isn't running (as in these headless tests),
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
	assert_true("Create Lobby" in _texts(menu), "the online form is still there")
	for e: Node in menu.find_children("*", "LineEdit", true, false):
		assert_false((e as LineEdit).placeholder_text.to_lower().contains("code"), "no room codes")


func test_create_lobby_needs_steam() -> void:
	assert_false(SteamSvc.is_available(), "no Steam client in the headless tests")
	menu.call(&"_show_online")
	await wait_process_frames(1)
	var host: Button = menu.find_child("HostParty", true, false) as Button
	assert_not_null(host, "CREATE LOBBY under PLAY ONLINE")
	if host == null:
		return
	assert_eq(host.text, "Create Lobby")
	assert_true(host.disabled, "disabled without Steam")
	assert_eq(host.tooltip_text, "")
	assert_true(host.is_visible_in_tree())
	for n: String in ["BrowseLobbies", "Public", "Private"]:
		var b: Button = menu.find_child(n, true, false) as Button
		assert_not_null(b, n)
		if b != null:
			assert_true(b.disabled, "%s disabled without Steam" % n)
	for t: String in _texts(menu) + _label_texts(menu):
		assert_false(t.to_lower().contains("start steam"), "no Start Steam text: %s" % t)
	assert_false((menu.find_child("JoinFriend", true, false) as Control).visible, "no friends list without Steam")
	host.pressed.emit()  # even if it fired: nothing starts, nothing breaks
	await wait_process_frames(2)
	assert_eq(Net.mode, Net.Mode.NONE)
	assert_eq(Net.steam_party.server_pid, 0, "no server process started")


func test_public_or_private_lobby_is_remembered() -> void:
	var before: bool = menu.call(&"lobby_public")
	menu.call(&"_set_public", true)
	assert_true(menu.call(&"lobby_public"))
	menu.call(&"_set_public", false)
	assert_false(menu.call(&"lobby_public"))
	menu.call(&"_set_public", before)
	var priv: Button = menu.find_child("Private", true, false) as Button
	var pub: Button = menu.find_child("Public", true, false) as Button
	assert_true(priv.toggle_mode and pub.toggle_mode)
	assert_eq(priv.button_group, pub.button_group, "one or the other")


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
	assert_eq(friends_list.find_children("Lobby*", "HBoxContainer", true, false).size(), 1, "two friends, one lobby row")
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
	assert_eq(SceneRouter.practice_settings, {"mode": MatchMode.CASINO}, "the normal casino match")
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
	assert_eq(how.page, 0)
	assert_true(how.back_button.disabled)
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
