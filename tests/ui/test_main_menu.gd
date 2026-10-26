extends GutTest
## Main menu (Patrick's playtest notes): the logo and entries are centred; PLAY ONLINE, PRACTICE,
## TUTORIAL, QUIT; the settings sit behind a small gear in the bottom-right corner; no "Rejoin
## last party" and no LAN/IP hosting, only HOST ON THIS PC (STEAM) (host mode, Patrick: "like
## Pummel Party"), disabled with "Start Steam to host" when Steam isn't running (as in these
## headless tests); TUTORIAL opens the how-to-play pages and DONE returns. (The first-run
## tutorial gate is in test_tutorial.gd; here the tutorial counts as seen.)
## PLAY ONLINE has no join-by-address and a server browser (Browse Parties); PRACTICE goes
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


func test_entries_in_order_without_a_settings_entry() -> void:
	var box: VBoxContainer = menu.get_node("Center/Column/VBox")
	var names: PackedStringArray = []
	for b: Node in box.get_children():
		names.append((b as Button).text)
	assert_eq(names, PackedStringArray(["PLAY ONLINE", "PRACTICE", "TUTORIAL", "COSMETICS", "QUIT"]))


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
		assert_false(t.to_lower().contains("host on") and t != "Host on this PC (Steam)", "no LAN Host on this PC: %s" % t)
		assert_false(t.to_lower().contains("rejoin"), "no Rejoin last party: %s" % t)
	assert_false(menu.has_method(&"_host_local"))
	assert_false(menu.has_method(&"_rejoin_last"))
	assert_true("Create Lobby" in _texts(menu), "the online form is still there")


func test_host_on_this_pc_needs_steam() -> void:
	assert_false(SteamSvc.is_available(), "no Steam client in the headless tests")
	menu.call(&"_show_online")
	await wait_process_frames(1)
	var host: Button = menu.find_child("HostParty", true, false) as Button
	assert_not_null(host, "HOST ON THIS PC under PLAY ONLINE")
	if host == null:
		return
	assert_eq(host.text, "Host on this PC (Steam)")
	assert_true(host.disabled, "disabled without Steam")
	assert_eq(host.tooltip_text, "Start Steam to host")
	assert_true(host.is_visible_in_tree())
	assert_false((menu.find_child("JoinFriend", true, false) as Control).visible, "no friends list without Steam")
	host.pressed.emit()  # even if it fired: nothing starts, nothing breaks
	await wait_process_frames(2)
	assert_eq(Net.mode, Net.Mode.NONE)
	assert_eq(Net.steam_party.server_pid, 0, "no server process started")


func test_no_join_by_ip_and_port() -> void:
	menu.call(&"_show_online")
	await wait_process_frames(1)
	for e: Node in menu.find_children("*", "LineEdit", true, false):
		var hint: String = (e as LineEdit).placeholder_text.to_lower()
		assert_false(hint.contains("host") or hint.contains("port") or hint.contains(":"), "no address field: %s" % hint)
	for t: String in _texts(menu):
		assert_ne(t, "Connect", "no direct Connect button")
	assert_false(menu.has_method(&"_join_ip"))


func test_browse_parties_lists_name_players_phase_and_join() -> void:
	menu.call(&"_show_online")
	var browse: Button = menu.find_child("BrowseParties", true, false) as Button
	assert_not_null(browse, "Browse Lobbies under PLAY ONLINE")
	if browse == null:
		return
	browse.pressed.emit()
	await wait_process_frames(1)
	assert_true(menu.browser_box.visible)
	menu.fill_browser([
		{"room_id": "r1", "room_code": "ABCDE", "name": "Patrick's party", "players": 3, "max_players": 8, "phase": "match", "mode": "casino", "joinable": true},
		{"room_id": "r2", "room_code": "FGHJK", "name": "Chip's party", "players": 2, "max_players": 8, "phase": "results", "mode": "minigames", "joinable": false},
	])
	await wait_process_frames(1)
	assert_eq(menu.browser_list.get_child_count(), 2)
	var first: Node = menu.browser_list.get_node("PartyABCDE")
	var labels: PackedStringArray = []
	for l: Node in first.find_children("*", "Label", true, false):
		labels.append((l as Label).text)
	assert_true("Patrick's party" in labels, str(labels))
	assert_true("3/8" in labels, str(labels))
	assert_true("PLAYING" in labels, "running matches are listed (late join)")
	assert_false((first.find_child("Join", true, false) as Button).disabled)
	var second: Node = menu.browser_list.get_node("PartyFGHJK")
	assert_true((second.find_child("Join", true, false) as Button).disabled, "results screen: not joinable")
	assert_string_contains((second.find_child("Phase", true, false) as Label).text, "MINIGAMES")
	menu.fill_browser([])
	await wait_process_frames(1)
	assert_eq(menu.browser_list.get_child_count(), 0)
	assert_string_contains(menu.browser_status.text, "No public lobbies")


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
