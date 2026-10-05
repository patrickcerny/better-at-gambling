extends Node
## Dev: the results screen with made-up standings, money history and awards (screenshots).
## `-s tools/screenshot.gd -- --scene res://tools/dev/results_shot.tscn --frames 400`

const NAMES: Array[String] = ["Patrick", "Chip", "Lucky", "Dice", "Big Wendy", "Snake Eyes"]


func _ready() -> void:
	var st := ClientMatchState.new()
	st.duration_minutes = 10
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var rows: Array = []
	for i: int in NAMES.size():
		var pid: int = i + 1
		st.players[pid] = {"id": pid, "name": NAMES[i], "color": i}
		var series: Array = [1000]
		var m: int = 1000
		for k: int in 60:
			m = maxi(m + rng.randi_range(-120, 140) + (40 if i == 0 else 0) - (30 if i == 5 else 0), 0)
			series.append(m)
		rows.append({"player": pid, "name": NAMES[i], "money": m, "series": series, "quiz_points": 0, "biggest_win": 0})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["money"]) > int(b["money"]))
	for i: int in rows.size():
		rows[i]["rank"] = i + 1
	st.standings = rows
	var stats: Dictionary = {
		1: {"jackpot_won": 2500, "biggest_win": 2500}, 2: {"knockouts_dealt": 4, "quiz_points": 2100},
		3: {"loss_streak": 6}, 4: {"times_shoved": 9}, 5: {"biggest_bet": 800}, 6: {"thrown_out": 3},
	}
	var names: Dictionary = {}
	for pid: int in st.players:
		names[pid] = st.players[pid]["name"]
	st.awards = Awards.pick(stats, names, 4)
	var stage := ResultsStage.new()
	add_child(stage)
	stage.setup(st, 1, false)
