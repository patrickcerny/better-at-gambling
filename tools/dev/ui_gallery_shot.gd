extends Control
## Dev: one 2D screen with made-up state for the theme screenshots (M7). Pick it with
## `--panel lobby|shop|rewards|settings|online` over the blurred casino panorama:
## `-s tools/screenshot.gd -- --scene res://tools/dev/ui_gallery_shot.tscn --frames 60 --panel shop`

const NAMES: Array[String] = ["Patrick", "Chip", "Lucky", "Big Wendy", "Snake Eyes"]


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
				rows.append({"player": i + 1, "placement": i + 1, "cash": [300, 200, 100, 0, 0][i], "draft": i < 3, "bonus_count": 1 if i == 4 else 0})
			p.open(rows, 8.0)
			p.set_process(false)
			p.timer_label.text = "6"
			p._show_offer({"choices": [&"lucky_clover", &"banana_peel", &"golden_chip"], "bonus": [&"beer"]})
		"settings":
			var p := SettingsPanel.new()
			add_child(p)
			p.open(true)
		"online":
			var menu: Control = (load("res://ui/menus/main_menu.tscn") as PackedScene).instantiate()
			add_child(menu)
			menu.call(&"_show_online")
			menu.call(&"_set_status", "Room codes have 5 letters.", true)


func _state() -> ClientMatchState:
	var st := ClientMatchState.new()
	st.room_mode = true
	st.leader = 1
	st.countdown = -1.0
	st.lobby_settings = {"duration": 10, "items_enabled": true}
	for i: int in NAMES.size():
		var pid: int = i + 1
		st.players[pid] = {"id": pid, "name": NAMES[i], "color": i, "ready": i % 2 == 0, "skin": "bean", "connected": i != 3, "inventory": []}
		st.balances[pid] = [2840, 1950, 1200, 640, 90][i]
	st.shop_offers = [
		{"item": "lucky_clover", "price": 150, "rarity": 0}, {"item": "bodyguard", "price": 300, "rarity": 1},
		{"item": "golden_chip", "price": 450, "rarity": 1}, {"item": "vip_pass", "price": 1200, "rarity": 2},
	]
	return st
