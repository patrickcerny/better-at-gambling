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
	var schedule: Array = [{"a": 3, "b": 4, "house": -1, "result": {}}, {"a": 1, "b": 2, "house": -1, "result": {}}, {"a": 5, "b": 6, "house": -1, "result": {}}]
	stage.on_event({"type": &"split_or_steal_started", "players": ids, "schedule": schedule, "matches_each": 1, "announce_time": 2.5, "decide_time": 15.0})
	stage.on_event({"type": &"split_or_steal_pair", "index": 0, "total": 3, "a": 3, "b": 4, "house": -1})
	stage.on_event({"type": &"split_or_steal_decide", "index": 0, "decide_time": 15.0})
	stage.on_event({"type": &"split_or_steal_reveal", "index": 0, "a": 3, "b": 4, "house": -1, "choice_a": "SPLIT", "choice_b": "STEAL",
		"points_a": 0, "points_b": 3, "auto_a": false, "auto_b": false, "points": {3: 0, 4: 3}, "steals": {4: 1}})
	if moment == "watch":
		stage.on_event({"type": &"split_or_steal_pair", "index": 2, "total": 3, "a": 5, "b": 6, "house": -1})
		stage.on_event({"type": &"split_or_steal_decide", "index": 2, "decide_time": 15.0})
		stage.on_event({"type": &"split_or_steal_locked", "index": 2, "player": 6})
		return
	stage.on_event({"type": &"split_or_steal_pair", "index": 1, "total": 3, "a": 1, "b": 2, "house": -1})
	stage.on_event({"type": &"split_or_steal_decide", "index": 1, "decide_time": 15.0})
	stage.on_event({"type": &"split_or_steal_locked", "index": 1, "player": 2})
	if moment == "decide":
		return
	stage.on_event({"type": &"split_or_steal_reveal", "index": 1, "a": 1, "b": 2, "house": -1, "choice_a": "STEAL", "choice_b": "SPLIT",
		"points_a": 3, "points_b": 0, "auto_a": false, "auto_b": false, "points": {1: 3, 2: 0, 3: 0, 4: 3}, "steals": {1: 1, 4: 1}})
	if moment == "reveal":
		return
	stage.on_event({"type": &"split_or_steal_finished", "ranking": [
		{"player": 1, "points": 3, "steals": 1, "rank": 1}, {"player": 4, "points": 3, "steals": 1, "rank": 1},
		{"player": 5, "points": 1, "steals": 0, "rank": 3}, {"player": 6, "points": 1, "steals": 0, "rank": 3},
		{"player": 2, "points": 0, "steals": 0, "rank": 5}, {"player": 3, "points": 0, "steals": 0, "rank": 5}]})
