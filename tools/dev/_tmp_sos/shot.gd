extends Node

const OUT: String = "/tmp/claude-0/-home-user-better-at-gambling/815afdd0-1dfb-59bb-8ae0-c21c43e4b96a/scratchpad/shot/"

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var st := ClientMatchState.new()
	var names: Array[String] = ["Patrick", "Lena-Marie Hofbauer", "Max", "Sophie", "Jonas"]
	for i: int in 5:
		st.players[i + 1] = {"id": i + 1, "name": names[i], "color": i}
	var stage := SplitOrStealStage.new()
	add_child(stage)
	stage.begin(st, 1, {"minigame": &"split_or_steal", "players": [1, 2, 3, 4, 5]}, {})
	stage.on_event({"type": &"split_or_steal_started", "players": [1, 2, 3, 4, 5], "total_rounds": 5, "talk_time": 8.0, "pick_time": 4.0})
	stage.on_event({"type": &"split_or_steal_round", "round": 2, "total_rounds": 5, "pairs": [[1, 2], [3, 4]], "bye": 5, "talk_time": 8.0})
	stage.points = {1: 3, 2: 1, 3: 4, 4: 1, 5: 3}
	stage.steals = {1: 1, 3: 1, 5: 0}
	stage.on_event({"type": &"split_or_steal_pick", "round": 2, "pick_time": 4.0})
	stage.on_private({"minigame": {"round": 2, "can_choose": true, "my_choice": ""}})
	stage.on_event({"type": &"split_or_steal_locked", "round": 2, "player": 2})
	stage.on_event({"type": &"split_or_steal_locked", "round": 2, "player": 3})
	for i: int in 10:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OUT + "pick.png")
	stage.on_event({"type": &"split_or_steal_reveal", "round": 2, "results": [
		{"player_a": 1, "player_b": 2, "choice_a": "SPLIT", "choice_b": "STEAL", "points_a": 0, "points_b": 3, "auto_a": false, "auto_b": false},
		{"player_a": 3, "player_b": 4, "choice_a": "SPLIT", "choice_b": "SPLIT", "points_a": 1, "points_b": 1, "auto_a": false, "auto_b": false}],
		"points": {1: 3, 2: 4, 3: 5, 4: 2, 5: 3}, "steals": {1: 1, 2: 1, 3: 1}})
	for i: int in 30:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OUT + "reveal.png")
	pass
