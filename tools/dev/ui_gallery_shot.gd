extends Control
## Dev: one 2D screen with made-up state for the theme screenshots (M7). Pick it with
## `--panel lobby|players|players_lobby|shop|rewards|settings|audio|controls|pause|pause_tutorial|tutorial|online|browser|practice|joining`
## over the blurred casino panorama:
## `-s tools/screenshot.gd -- --scene res://tools/dev/ui_gallery_shot.tscn --frames 60 --panel shop`

const NAMES: Array[String] = ["Patrick", "Chip", "Lucky", "Big Wendy", "Snake Eyes"]
const SKINS: Array[String] = ["king", "bean", "wizard", "business", "swat"]


func _ready() -> void:
	theme = load("res://ui/theme/main_theme.tres") as Theme
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Palette.CASINO_BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var pano := CasinoPanorama.new()
	pano.blur_px = 2.0
	pano.darken = 0.35
	pano.start_leg = 2.3
	add_child(pano)
	var st := _state()
	var which: String = Cmdline.parse(OS.get_cmdline_user_args()).get_string("panel", "shop")
	match which:
		"lobby":
			var p := LobbyPanel.new()
			add_child(p)
			p.bind(st, 1)
			p.open()
		"players", "players_lobby":
			# The Tab list: standings (match) or ready states (lobby), with a talking-free roster.
			st.phase = Phase.Id.LOBBY if which == "players_lobby" else Phase.Id.CASINO
			var p := PlayerList.new()
			add_child(p)
			p.bind(st, 2)
			p.show_list(true)
		"shop":
			var p := ShopPanel.new()
			add_child(p)
			p.bind(st, 1)
			p.open()
		"rewards":
			var p := RewardPanel.new()
			add_child(p)
			p.bind(st, 1)
			var rows: Array = []
			for i: int in NAMES.size():
				var row: Dictionary = {"player": i + 1, "placement": i + 1, "cash": [150, 100, 75, 50, 25][i], "item": [&"golden_chip", &"lucky_clover", &"banana_peel", &"beer", &"beer"][i]}
				if i == NAMES.size() - 1:
					row["bonus"] = &"lucky_clover"
					row["comp"] = 450
				rows.append(row)
			p.open(rows, 6.0, true)
			p.set_process(false)
			p.timer_label.text = "6"
		"settings", "audio", "controls":
			var p := SettingsPanel.new()
			add_child(p)
			p.current_tab = maxi(SettingsPanel.TABS.find(which.to_upper()), 0)
			p.open(true)
		"pause":
			var p := PauseMenu.new()
			add_child(p)
			p.open()
		"tutorial":
			var menu: Control = (load("res://ui/menus/main_menu.tscn") as PackedScene).instantiate()
			add_child(menu)
			menu.call(&"_show_tutorial", null)
			(menu.get("how_to_play") as HowToPlayPanel).show_page(2)
		"pause_tutorial":
			var p := PauseMenu.new()
			add_child(p)
			p.open()
			p.open_tutorial()
		"online":
			var menu: Control = (load("res://ui/menus/main_menu.tscn") as PackedScene).instantiate()
			add_child(menu)
			menu.call(&"_show_online")
			menu.call(&"_set_status", "Room codes have 5 letters.", true)
		"browser":
			var menu: Control = (load("res://ui/menus/main_menu.tscn") as PackedScene).instantiate()
			add_child(menu)
			menu.call(&"_hide_boxes")
			menu.browser_box.visible = true
			menu.call(&"fill_browser", [
				{"room_id": "a", "room_code": "KX7PQ", "name": "Patrick's lobby", "players": 5, "max_players": 8, "phase": "match", "mode": "casino", "joinable": true},
				{"room_id": "b", "room_code": "HN4TW", "name": "Big Wendy's lobby", "players": 2, "max_players": 8, "phase": "lobby", "mode": "minigames", "joinable": true},
				{"room_id": "c", "room_code": "M2RZD", "name": "Snake Eyes's lobby", "players": 8, "max_players": 8, "phase": "lobby", "mode": "casino", "joinable": false},
				{"room_id": "d", "room_code": "Q8VCE", "name": "Chip's lobby", "players": 3, "max_players": 8, "phase": "results", "mode": "casino", "joinable": false},
			])
		"practice":
			var menu: Control = (load("res://ui/menus/main_menu.tscn") as PackedScene).instantiate()
			add_child(menu)
			menu.call(&"_show_practice")
		"joining":
			Loading.begin("JOINING KX7PQ")


func _state() -> ClientMatchState:
	var st := ClientMatchState.new()
	st.room_mode = true
	st.leader = 1
	st.countdown = -1.0
	st.lobby_settings = {"minigames": 5, "gamble_minutes": 3, "items_enabled": true, "mode": &"casino", "public": true}
	for i: int in NAMES.size():
		var pid: int = i + 1
		st.players[pid] = {"id": pid, "name": NAMES[i], "color": i, "ready": i % 2 == 0, "skin": SKINS[i], "connected": i != 3, "inventory": []}
		st.balances[pid] = [2840, 1950, 1200, 640, 90][i]
	st.shop_offers = [
		{"item": "lucky_clover", "price": 150, "rarity": 0}, {"item": "bodyguard", "price": 300, "rarity": 1},
		{"item": "golden_chip", "price": 450, "rarity": 1}, {"item": "vip_pass", "price": 1200, "rarity": 2},
	]
	return st
