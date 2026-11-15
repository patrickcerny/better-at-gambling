extends Node
## Dev: look-dev shots for the cosmetics shop and the profile line.
## Run with scripts/screenshot.sh res://tools/dev/cosmetics_shot.tscn <name> 90 --view <view>:
## `shop` (the main menu with the shop open on Gold), `menu` (the main menu and its profile line),
## `pass` (the level pass, `--level N` to pretend), `results` (the results screen with YOUR PROGRESS). The profile is in memory only: nothing is
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
		"results":
			_results()
		_:
			var menu: Control = (load("res://ui/menus/main_menu.tscn") as PackedScene).instantiate()
			add_child(menu)
			if view == "pass":
				var lv: int = Cmdline.parse(OS.get_cmdline_user_args()).get_int("level", 0)
				if lv > 0:
					ProfileManager.profile.level = lv
					ProfileManager.profile.xp = ProfileManager.profile.config.xp_for_level(lv) + 120
				(menu.get("level_pass") as LevelPassPanel).open()
			if view == "shop":
				var shop: CosmeticsPanel = menu.get("cosmetics")
				shop.open(Cmdline.parse(OS.get_cmdline_user_args()).has_flag("inventory"))
				# --select a,b,c tries several on (they stack), the last one picked.
				for pick: String in Cmdline.parse(OS.get_cmdline_user_args()).get_string("select", "color_gold").split(","):
					var d: CosmeticDef = CosmeticShop.default().find(StringName(pick))
					if d != null:
						shop.show_kind(d.kind)
					shop.select(StringName(pick))
				# Report whether the shop fits the screen (Patrick: "the menu is bigger than the screen").
				await get_tree().process_frame
				await get_tree().process_frame
				var r: Rect2 = shop.get_global_rect()
				Log.info(&"shot", "shop rect %s in viewport %s, min %s" % [r, get_viewport().get_visible_rect().size, shop.get_combined_minimum_size()])


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
