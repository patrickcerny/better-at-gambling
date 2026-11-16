extends Control
## Dev: look-dev for the round results (`RewardPanel`) on a plain casino-dark backdrop.
## Run with scripts/screenshot.sh res://tools/dev/reward_panel_shot.tscn <name> 120 [args]
##   --players N    rows (default 4, up to 8)
##   --instant      everything revealed at once (otherwise the flips play)
##   --no-items     Minigames Only (no item cards)

const NAMES: Array[String] = ["Patrick", "Chip", "Lucky Lou", "Dealer Dan", "Rosa", "Max", "Vic", "Jo"]
const ITEMS: Array[StringName] = [&"baseball_bat", &"robin_hood", &"lucky_clover", &"", &"black_cat", &"sunglasses", &"bribe", &"double_down"]
const HATS: Array[String] = ["hat_crown", "hat_cowboy", "hat_bowler", "", "hat_chef", "hat_dice", "hat_cone", ""]


func _ready() -> void:
	var args: Cmdline = Cmdline.parse(OS.get_cmdline_user_args())
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.16, 0.11, 0.09)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var n: int = clampi(args.get_int("players", 4), 1, 8)
	var st := ClientMatchState.new()
	var rows: Array = []
	for i: int in n:
		var pid: int = i + 1
		st.players[pid] = {"id": pid, "name": NAMES[i], "color": i, "outfit": [HATS[i]]}
		var row: Dictionary = {"player": pid, "placement": i + 1, "cash": maxi(0, 450 - 150 * i), "item": ITEMS[i]}
		if i == n - 1 and n > 2:
			row["comp"] = 300
			row["bonus"] = &"lucky_clover"
		rows.append(row)
	st.lobby_settings = {"mode": MatchMode.MINIGAMES} if args.has("no-items") else {}
	var p := RewardPanel.new()
	add_child(p)
	p.bind(st, 1)
	p.open(rows, 6.0, args.has("instant"))
