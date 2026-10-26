extends Node
## Dev: look-dev shots for the cosmetics shop, the profile line and the pedestal colour panel.
## Run with scripts/screenshot.sh res://tools/dev/cosmetics_shot.tscn <name> 90 --view <view>:
## `shop` (the main menu with the shop open on Gold), `menu` (the main menu and its profile line),
## `plaque` (a ready pedestal and its colour panel close up, a bought colour worn and one hovered),
## `results` (the results screen with YOUR PROGRESS). The profile is in memory only: nothing is
## written to user://profile.cfg.


func _ready() -> void:
	ProfileManager.persist = false
	ProfileManager.reload()
	var p: PlayerProfile = ProfileManager.profile
	p.apply_match("shot-1", Progression.breakdown(p.config, 1, 2, 2400, 30))
	p.apply_match("shot-2", Progression.breakdown(p.config, 2, 1, 600, 20))
	p.coins = 640
	p.buy(&"color_mint")
	p.set_preferred_color(9)
	ProfileManager.changed.emit()
	var view: String = Cmdline.parse(OS.get_cmdline_user_args()).get_string("view", "shop")
	match view:
		"plaque":
			_plaque()
		"results":
			_results()
		_:
			var menu: Control = (load("res://ui/menus/main_menu.tscn") as PackedScene).instantiate()
			add_child(menu)
			if view == "shop":
				var shop: CosmeticsPanel = menu.get("cosmetics")
				shop.open()
				shop.select(&"color_gold")


func _plaque() -> void:
	var map := LuckyLounge.new()
	map.bake_navmesh = false
	add_child(map)
	var free: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7, 9]
	map.color_plaques[0].show_colors(free, 9, [1], true)
	map.color_plaques[0].set_hovered(4)
	map.color_plaques[1].show_colors([0, 1, 2, 3, 4, 5, 6, 7, 15], 15, [], false)
	map.set_pedestal(0, "Patrick", false)
	map.set_pedestal(1, "Chip", true)
	var bean := AvatarVisuals.new()
	add_child(bean)
	bean.set_color(Palette.player_color(9))
	bean.global_position = LuckyLounge.PEDESTALS[0] + Vector3(0.1, 0, -2.6)
	bean.rotation.y = PI * 0.85
	var other := AvatarVisuals.new()
	add_child(other)
	other.set_color(Palette.player_color(15))
	other.global_position = LuckyLounge.PEDESTALS[1] + Vector3(0, LuckyLounge.PEDESTAL_TOP, 0)
	other.rotation.y = PI
	var cam := Camera3D.new()
	add_child(cam)
	var plaque: Vector3 = map.color_plaques[0].global_position
	cam.global_position = plaque + Vector3(0.9, 1.35, -1.3)
	cam.look_at(plaque + Vector3(-0.2, 0.8, 0.0))
	cam.fov = 60.0
	cam.current = true


func _results() -> void:
	var st := ClientMatchState.new()
	st.duration_s = 300.0
	var rows: Array = []
	for i: int in 5:
		var pid: int = i + 1
		st.players[pid] = {"id": pid, "name": ["Patrick", "Chip", "Lucky", "Dice", "Ace"][i], "color": i, "bean_color": [9, 1, 15, 3, 4][i]}
		var money: int = 2600 - i * 450
		rows.append({"player": pid, "name": st.players[pid]["name"], "money": money, "rank": i + 1, "series": [1000, 1400, 1100, money]})
		st.progress[pid] = Progression.breakdown(ProfileManager.profile.config, i + 1, 1 if i < 2 else 0, money - 1000, 18 + i)
	st.standings = rows
	st.match_id = "shot-results"
	var summary: Dictionary = ProfileManager.apply_results({"progress": st.progress, "match_id": st.match_id}, 1)
	var stage := ResultsStage.new()
	stage.progress_summary = summary
	add_child(stage)
	stage.setup(st, 1, true)
	stage.finish_show()
