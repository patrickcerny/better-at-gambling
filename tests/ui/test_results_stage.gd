extends GutTest
## Results screen (§2.11): the podium show runs to its end state, awards and the money graph show.

var stage: ResultsStage


func _state(n: int) -> ClientMatchState:
	var st := ClientMatchState.new()
	st.duration_minutes = 5
	var rows: Array = []
	for i: int in n:
		var pid: int = i + 1
		st.players[pid] = {"id": pid, "name": "P%d" % pid, "color": i}
		var money: int = 2000 - i * 300
		rows.append({"player": pid, "name": "P%d" % pid, "money": money, "rank": i + 1, "series": [1000, 1200, money]})
	st.standings = rows
	st.awards = Awards.pick({1: {"jackpot_won": 500}, 2: {"loss_streak": 4}}, {1: "P1", 2: "P2"}, 4)
	return st


func _open(n: int) -> void:
	stage = ResultsStage.new()
	add_child_autofree(stage)
	stage.setup(_state(n), 1, false)


func test_show_ends_with_everyone_placed_and_awards_up() -> void:
	_open(5)
	stage.finish_show()
	assert_eq(stage.beans.size(), 5)
	for pid: int in stage.beans:
		assert_true(stage.beans[pid].visible, "P%d landed" % pid)
	assert_eq(stage.puppets[1].mood, BeanPuppet.Mood.CHEER, "the winner celebrates")
	assert_eq(stage.puppets[5].mood, BeanPuppet.Mood.SAD, "last place sulks")
	assert_eq(stage.puppets[3].mood, BeanPuppet.Mood.IDLE)
	assert_eq(stage.award_cards.size(), 2)
	for c: Control in stage.award_cards:
		assert_eq(c.modulate.a, 1.0)
	assert_true(stage.graph.has_data())
	assert_true(stage.graph_panel.visible)


func test_beans_arrive_in_podium_order() -> void:
	_open(4)
	assert_false(stage.beans[1].visible, "nobody is on the podium at first")
	await wait_seconds(ResultsStage.T_PLACE[2] + 0.6)
	assert_true(stage.beans[4].visible, "the floor first")
	assert_true(stage.beans[3].visible, "then 3rd")
	assert_false(stage.beans[1].visible, "1st comes last")


func test_no_graph_without_history() -> void:
	var st: ClientMatchState = _state(2)
	for row: Variant in st.standings:
		(row as Dictionary).erase("series")
	stage = ResultsStage.new()
	add_child_autofree(stage)
	stage.setup(st, 1, false)
	assert_false(stage.graph_panel.visible)


func test_name_tags_clamp_their_screen_size() -> void:
	# 0.19 m text at 70° fov: huge up close, a speck far away; clamped to MIN_PX..MAX_PX.
	var near: float = NameTag.size_factor(1.0, 70.0, 0.19)
	var far: float = NameTag.size_factor(40.0, 70.0, 0.19)
	var mid: float = NameTag.size_factor(7.0, 70.0, 0.19)
	assert_lt(near, 1.0, "shrinks up close")
	assert_gt(far, 1.0, "grows far away")
	assert_almost_eq(mid, 1.0, 0.001, "world size in between")
	var px_near: float = 0.19 * near / (2.0 * 1.0 * tan(deg_to_rad(35.0))) * 1080.0
	assert_almost_eq(px_near, NameTag.MAX_PX, 0.01)
