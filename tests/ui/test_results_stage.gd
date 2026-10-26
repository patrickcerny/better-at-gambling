extends GutTest
## Results screen (§2.11): the podium show runs to its end state, awards and the money graph show,
## every standings row shows the XP that player earned and YOUR PROGRESS fills the level bar.

var stage: ResultsStage


func _state(n: int) -> ClientMatchState:
	var st := ClientMatchState.new()
	st.duration_s = 300.0
	var rows: Array = []
	for i: int in n:
		var pid: int = i + 1
		st.players[pid] = {"id": pid, "name": "P%d" % pid, "color": i}
		var money: int = 2000 - i * 300
		rows.append({"player": pid, "name": "P%d" % pid, "money": money, "rank": i + 1, "series": [1000, 1200, money]})
	st.standings = rows
	st.awards = Awards.pick({1: {"jackpot_won": 500}, 2: {"loss_streak": 4}}, {1: "P1", 2: "P2"}, 4)
	for row: Variant in rows:
		st.progress[int(row["player"])] = Progression.breakdown(ProgressionConfig.default(), int(row["rank"]), 1, int(row["money"]) - 1000, 12)
	st.match_id = "results-test"
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


## Screen rect (0..1 of the view) a name tag covers, from its text box in the world.
func _tag_rect(tag: Label3D) -> Rect2:
	var box: AABB = tag.get_aabb()
	var cam: Camera3D = stage.camera
	var view: Vector2 = stage.get_viewport().get_visible_rect().size
	var rect := Rect2()
	var first: bool = true
	for i: int in 8:
		var corner: Vector3 = tag.global_transform * box.get_endpoint(i)
		var p: Vector2 = cam.unproject_position(corner) / view
		if first:
			rect = Rect2(p, Vector2.ZERO)
			first = false
		else:
			rect = rect.expand(p)
	return rect


## Screen rect (0..1) of a 2D panel.
func _panel_rect(c: Control) -> Rect2:
	var canvas: Vector2 = (stage.standings_panel.get_parent() as Control).size
	var r: Rect2 = c.get_global_rect()
	return Rect2(r.position / canvas, r.size / canvas)


func _tags() -> Array[Label3D]:
	var out: Array[Label3D] = []
	for c: Node in stage.get_children():
		if c is Label3D and (c as Label3D).billboard == BaseMaterial3D.BILLBOARD_ENABLED and (c as Label3D).text.contains("$"):
			out.append(c)
	return out


func test_a_full_party_of_eight_fits_the_screen() -> void:
	# Old fix batch: "results screen with 7-8 players": the beans beside the podium ran off under the
	# standings and the graph, and their name tags piled up on each other.
	for n: int in [7, 8]:
		# A 1920×1080 view, like the game's (the headless window is square).
		var view := SubViewport.new()
		view.size = Vector2i(1920, 1080)
		add_child_autofree(view)
		var st: ClientMatchState = _state(n)
		for row: Variant in st.standings:
			(row as Dictionary)["name"] = "Player %d long" % int(row["player"])
		stage = ResultsStage.new()
		view.add_child(stage)
		stage.setup(st, 1, true)
		stage.finish_show()
		await wait_process_frames(3)
		var tags: Array[Label3D] = _tags()
		assert_eq(tags.size(), n, "%d name tags" % n)
		var panels: Array[Rect2] = [_panel_rect(stage.standings_panel), _panel_rect(stage.graph_panel), _panel_rect(stage.xp_panel), _panel_rect(stage.find_child("XpParts", true, false) as Control)]
		var rects: Array[Rect2] = []
		for t: Label3D in tags:
			var r: Rect2 = _tag_rect(t)
			rects.append(r)
			assert_true(r.position.x >= 0.0 and r.end.x <= 1.0 and r.position.y >= 0.0 and r.end.y <= 1.0, "%d players: %s on screen (%s)" % [n, t.text.get_slice("\n", 0), r])
			for pr: Rect2 in panels:
				assert_false(r.intersects(pr), "%d players: %s clear of the panels (%s vs %s)" % [n, t.text.get_slice("\n", 0), r, pr])
		for i: int in rects.size():
			for j: int in range(i + 1, rects.size()):
				assert_false(rects[i].intersects(rects[j]), "%d players: tags %s and %s do not overlap" % [n, tags[i].text.get_slice("\n", 0), tags[j].text.get_slice("\n", 0)])
		for pid: int in stage.beans:
			var feet: Vector2 = stage.camera.unproject_position(stage.beans[pid].global_position) / stage.get_viewport().get_visible_rect().size
			assert_between(feet.x, 0.02, 0.98, "%d players: bean %d in shot" % [n, pid])
		var standings_bottom: float = _panel_rect(stage.standings_panel).end.y
		assert_lt(standings_bottom, _panel_rect(stage.award_cards[0].get_parent() as Control).position.y, "%d players: the standings end above the awards" % n)
		view.queue_free()
		await wait_process_frames(1)


func test_xp_rows_and_the_level_bar() -> void:
	ProfileManager.reload()
	var st: ClientMatchState = _state(4)
	var cfg: ProgressionConfig = ProgressionConfig.default()
	var row: Dictionary = st.progress[1]
	ProfileManager.profile.xp = cfg.xp_for_level(2) - 20  # 20 XP short of level 2
	ProfileManager.profile.sanitize()
	var summary: Dictionary = ProfileManager.apply_results({"progress": st.progress, "match_id": st.match_id}, 1)
	assert_eq(summary["level_from"], 1)
	assert_gt(int(summary["level_to"]), 1)
	stage = ResultsStage.new()
	stage.progress_summary = summary
	add_child_autofree(stage)
	stage.setup(st, 1, false)
	for pid: int in [1, 2, 3, 4]:
		var xl: Label = stage.standings_panel.find_child("Xp%d" % pid, true, false) as Label
		assert_not_null(xl, "P%d's row shows its XP" % pid)
		if xl != null:
			assert_eq(xl.text, "+%d XP" % int(st.progress[pid]["xp"]), "the server's number, the same on every screen")
	assert_not_null(stage.xp_panel, "YOUR PROGRESS")
	assert_eq((stage.xp_panel.find_child("XpTotal", true, false) as Label).text, "+%d XP" % int(row["xp"]))
	var breakdown: String = (stage.find_child("Breakdown", true, false) as Label).text
	assert_string_contains(breakdown, "1st place +120")
	assert_string_contains(breakdown, "Match played +100")
	assert_string_contains(stage.coins_line.text, "+%d COINS" % int(summary["coins"]))
	assert_string_contains(stage.coins_line.text, "level-up bonus")
	assert_not_null(stage.find_child("XpParts", true, false), "where the XP came from")
	assert_eq(stage.level_label.text, "LEVEL 1", "the bar starts where the match began")
	assert_almost_eq(stage.xp_shown, float(summary["xp_from"]), 0.5)
	await wait_seconds(ResultsStage.T_XP + 0.6)
	assert_gt(stage.xp_shown, float(summary["xp_from"]), "the bar fills")
	stage.finish_show()
	assert_almost_eq(stage.xp_shown, float(ProfileManager.profile.xp), 0.5, "ends at the profile's XP")
	assert_eq(stage.level_label.text, "LEVEL 1 → %d" % int(summary["level_to"]))
	ProfileManager.reload()


func test_no_rows_no_progress_panel() -> void:
	var st: ClientMatchState = _state(3)
	st.progress = {}
	stage = ResultsStage.new()
	add_child_autofree(stage)
	stage.setup(st, 1, false)
	assert_null(stage.xp_panel)
	assert_null(stage.standings_panel.find_child("Xp1", true, false))
