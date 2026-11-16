extends Control
## Dev: the LEADERBOARDS panel with made-up entries (no Steam needed): podium, rows, your own
## place pinned below. `--scope friends|global|rank`, `--stats` for MY STATS.
## scripts/screenshot.sh res://tools/dev/leaderboard_shot.tscn leaderboard 120 [--scope friends]

const NAMES: Array[String] = ["Моранге", "Fetus Deletus", "ChioDip", "Vinc", "Ekvimsa", "King Katić", "Stefafo", "Big Wendy", "Snake Eyes", "Lena-Marie"]


class ShotPanel:
	extends LeaderboardPanel

	func _name_of(r: Dictionary) -> String:
		return NAMES[int(r["steam_id"]) % NAMES.size()]

	func _steam_on() -> bool:
		return true


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#2A1D18")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var args: Cmdline = Cmdline.parse(OS.get_cmdline_user_args())
	var panel := ShotPanel.new()
	add_child(panel)
	panel.open(LeaderboardPanel.PAGE_STATS if args.has_flag("stats") else LeaderboardPanel.PAGE_BOARDS)
	if args.has_flag("stats"):
		return
	var scope: int = {"friends": LeaderboardRules.SCOPE_FRIENDS, "rank": LeaderboardRules.SCOPE_AROUND_ME}.get(args.get_string("scope", "global"), LeaderboardRules.SCOPE_GLOBAL)
	panel.select_scope(scope)
	var rows: Array[Dictionary] = []
	var shop: Array = CosmeticShop.default().items
	for i: int in 9:
		var outfit := PackedStringArray()
		for kind: StringName in CosmeticDef.OUTFIT_KINDS:
			var pick: String = ""
			var n: int = 0
			for d: CosmeticDef in shop:
				if d.kind == kind:
					n += 1
					if n == 1 + (i * 3) % 5 and (i + kind.length()) % 3 != 0:
						pick = String(d.id)
			outfit.append(pick)
		var rank: int = i + 1 if scope != LeaderboardRules.SCOPE_FRIENDS else i * 3 + 2
		if scope == LeaderboardRules.SCOPE_AROUND_ME:
			rank = 37 + i
		rows.append({"rank": rank, "steam_id": i, "score": 9200 - i * 870, "me": i == 1,
			"skin": LeaderboardRules.skin_from_details(LeaderboardRules.skin_details(i % Cosmetics.SLOT_COLORS, outfit))})
	panel._on_entries(panel.board, scope, rows, 412)
	panel._on_mine(panel.board, rows[1], 412)
