extends Node
## Dev: the Roulette Royale stage mid-game with made-up players (screenshots).
## `scripts/screenshot.sh res://tools/dev/roulette_royale_shot.tscn rr_pick 90 -- --phase pick`
## Phases: intro, pick (locked in, others thinking), result (after the ball drops), finished.

const NAMES: Array[String] = ["Patrick", "Chip", "Lucky", "Dice", "Big Wendy", "Snake Eyes"]


func _ready() -> void:
	var phase: String = Cmdline.parse(OS.get_cmdline_user_args()).get_string("phase", "pick")
	var st := ClientMatchState.new()
	var ids: Array = []
	for i: int in NAMES.size():
		st.players[i + 1] = {"id": i + 1, "name": NAMES[i], "color": i}
		ids.append(i + 1)
	var stage := RouletteRoyaleStage.new()
	add_child(stage)
	stage.begin(st, 1, {"minigame": &"roulette_royale", "players": ids}, {})
	stage.on_event({"type": &"roulette_royale_started", "players": ids, "hearts": {1: 3, 2: 3, 3: 3, 4: 3, 5: 3, 6: 3}, "max_spins": 6, "pick_time": 5.0, "spin_time": 3.4})
	if phase == "intro":
		return
	var hearts: Dictionary = {1: 2, 2: 3, 3: 1, 4: 2, 5: 0, 6: 1}
	stage.on_event({"type": &"roulette_royale_pick_open", "spin": 2, "max_spins": 6, "seconds": 5.0, "alive": [1, 2, 3, 4, 6], "hearts": hearts})
	stage.on_event({"type": &"roulette_royale_picked", "player": 2, "spin": 2})
	stage.on_event({"type": &"roulette_royale_picked", "player": 4, "spin": 2})
	if phase == "pick":
		stage._pick(0)
		return
	stage.on_event({"type": &"roulette_royale_spin", "spin": 2, "seconds": 0.1})
	stage.on_event({"type": &"roulette_royale_result", "spin": 2, "number": 0, "color": &"green",
		"picks": {1: &"green", 2: &"red", 3: &"black", 4: &"green", 6: &""}, "deltas": {1: 1, 2: -1, 3: -1, 4: 1, 6: -1},
		"hearts": {1: 3, 2: 2, 3: 0, 4: 3, 5: 0, 6: 0}, "eliminated": [3, 6], "alive": [1, 2, 4]})
	if phase == "finished":
		stage.on_event({"type": &"roulette_royale_finished", "ranking": [
			{"player": 1, "rank": 1}, {"player": 4, "rank": 2}, {"player": 2, "rank": 3},
			{"player": 3, "rank": 4}, {"player": 6, "rank": 4}, {"player": 5, "rank": 6}]})
