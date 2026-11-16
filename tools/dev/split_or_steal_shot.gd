extends Node
## Dev: the Split or Steal show set with made-up players (screenshots).
## `-s tools/screenshot.gd -- --scene res://tools/dev/split_or_steal_shot.tscn --frames 60 --moment reveal`
## Moments: decide (we are on stage), watch (we are in the audience), reveal, final.

const NAMES: Array[String] = ["Patrick", "Lena-Marie Hofbauer", "Max", "Sophie", "Jonas", "Big Wendy"]


func _ready() -> void:
	var moment: String = Cmdline.parse(OS.get_cmdline_user_args()).get_string("moment", "decide")
	var st := ClientMatchState.new()
	var ids: Array = []
	for i: int in NAMES.size():
		st.players[i + 1] = {"id": i + 1, "name": NAMES[i], "color": i}
		ids.append(i + 1)
	var stage := SplitOrStealStage.new()
	add_child(stage)
	stage.begin(st, 1, {"minigame": &"split_or_steal", "players": ids}, {})
	var duels: Array = [{"a": 1, "b": 2, "result": {}}, {"a": 3, "b": 4, "result": {}}, {"a": 5, "b": 6, "result": {}}]
	var watch_duels: Array = [{"a": 2, "b": 3, "result": {}}, {"a": 4, "b": 5, "result": {}}, {"a": 6, "b": 1, "result": {}}]
	var rounds: Array = [{"duels": duels, "bye": []}, {"duels": watch_duels, "bye": []}]
	stage.on_event({"type": &"split_or_steal_started", "players": ids, "rounds": rounds, "duels_each": 5, "round_time": 2.0, "decide_time": 12.0})
	if moment == "watch":
		# 7 players' worth of layout: we sit this round out.
		stage.on_event({"type": &"split_or_steal_round", "index": 1, "total": 5, "duels": [{"a": 2, "b": 3}, {"a": 4, "b": 5}], "bye": [1, 6]})
		stage.on_event({"type": &"split_or_steal_decide", "index": 1, "decide_time": 12.0})
		stage.on_event({"type": &"split_or_steal_locked", "index": 1, "player": 4})
		return
	stage.on_event({"type": &"split_or_steal_round", "index": 0, "total": 5, "duels": duels, "bye": []})
	stage.on_event({"type": &"split_or_steal_decide", "index": 0, "decide_time": 12.0})
	stage.on_event({"type": &"split_or_steal_locked", "index": 0, "player": 2})
	stage.on_event({"type": &"split_or_steal_locked", "index": 0, "player": 5})
	if moment == "decide":
		return
	stage.on_event({"type": &"split_or_steal_reveal", "index": 0, "results": [
		{"a": 1, "b": 2, "choice_a": "STEAL", "choice_b": "SPLIT", "points_a": 3, "points_b": 0},
		{"a": 3, "b": 4, "choice_a": "SPLIT", "choice_b": "SPLIT", "points_a": 1, "points_b": 1},
		{"a": 5, "b": 6, "choice_a": "STEAL", "choice_b": "STEAL", "points_a": 0, "points_b": 0}],
		"points": {1: 3, 2: 0, 3: 1, 4: 1, 5: 0, 6: 0}, "steals": {1: 1, 5: 1, 6: 1}})
	if moment == "reveal":
		return
	stage.on_event({"type": &"split_or_steal_finished", "ranking": [
		{"player": 1, "points": 3, "steals": 1, "rank": 1}, {"player": 4, "points": 3, "steals": 1, "rank": 1},
		{"player": 5, "points": 1, "steals": 0, "rank": 3}, {"player": 6, "points": 1, "steals": 0, "rank": 3},
		{"player": 2, "points": 0, "steals": 0, "rank": 5}, {"player": 3, "points": 0, "steals": 0, "rank": 5}]})
