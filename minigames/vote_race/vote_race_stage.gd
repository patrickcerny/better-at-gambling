class_name VoteRaceStage
extends MinigameStage
## Client presentation for Vote Race. While a round is voting it only ever shows the track
## (positions), the countdown and how many racers have voted; who voted for whom appears only
## when the server resolves the round (`vote_race_reveal`).

const TRACK_LENGTH: int = 5

var root: PanelContainer
var title_label: Label
var round_label: Label
var timer_label: Label
var track_box: VBoxContainer
var vote_title: Label
var vote_row: HBoxContainer
var reveal_label: Label
var status_label: Label

var players_list: Array[int] = []
var racing: Array[int] = []
var positions: Dictionary[int, int] = {}
var finish_place: Dictionary[int, int] = {}  # player → finishing place
var lane_bars: Dictionary[int, ProgressBar] = {}
var lane_labels: Dictionary[int, Label] = {}
var vote_buttons: Dictionary[int, Button] = {}
var round_num: int = 0
var voted_count: int = 0
var voted_this_round: Dictionary[int, bool] = {}
var time_left: float = 0.0
var voting: bool = false
var my_vote: int = -1
var can_vote: bool = false


func _build(start: Dictionary) -> void:
	_set_players(start.get("players", []))
	_build_ui()
	_rebuild_track()
	_rebuild_vote_buttons()


func _set_players(list: Array) -> void:
	players_list.clear()
	for p: Variant in list:
		players_list.append(int(p))
	players_list.sort()
	for p: int in players_list:
		if not positions.has(p):
			positions[p] = 0


func _build_ui() -> void:
	root = PanelContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(root)
	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	root.add_child(margin)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)

	title_label = _label("Vote Race", 32)
	col.add_child(title_label)
	col.add_child(_label("Vote for another racer. Everyone with ZERO votes steps toward the cashier. First to step %d wins." % TRACK_LENGTH, 16))
	var info: HBoxContainer = HBoxContainer.new()
	info.add_theme_constant_override("separation", 24)
	round_label = _label("Round 1", 20)
	timer_label = _label("", 20)
	info.add_child(round_label)
	info.add_child(timer_label)
	col.add_child(info)

	track_box = VBoxContainer.new()
	track_box.add_theme_constant_override("separation", 6)
	track_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(track_box)

	vote_title = _label("Cast your secret vote:", 22)
	col.add_child(vote_title)
	vote_row = HBoxContainer.new()
	vote_row.add_theme_constant_override("separation", 8)
	col.add_child(vote_row)

	reveal_label = _label("", 16)
	reveal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(reveal_label)
	status_label = _label("", 18)
	col.add_child(status_label)


func _label(text: String, size: int) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	return l


func _name(p: int) -> String:
	if p == local_id:
		return "You"
	if state != null:
		return state.player_name(p)
	return "Player %d" % p


func _rebuild_track() -> void:
	for child: Node in track_box.get_children():
		child.queue_free()
	lane_bars.clear()
	lane_labels.clear()
	for p: int in players_list:
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var name_lbl: Label = _label("", 16)
		name_lbl.custom_minimum_size = Vector2(260, 0)
		row.add_child(name_lbl)
		var bar: ProgressBar = ProgressBar.new()
		bar.min_value = 0
		bar.max_value = TRACK_LENGTH
		bar.step = 1
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(320, 26)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(bar)
		track_box.add_child(row)
		lane_bars[p] = bar
		lane_labels[p] = name_lbl
	_update_track()


func _update_track() -> void:
	for p: int in lane_bars:
		var steps: int = positions.get(p, 0)
		lane_bars[p].value = steps
		var tag: String = "%s  %d/%d" % [_name(p), steps, TRACK_LENGTH]
		if finish_place.has(p):
			tag += "  - finished #%d" % finish_place[p]
		elif voting and voted_this_round.has(p):
			tag += "  (voted)"
		lane_labels[p].text = tag


func _rebuild_vote_buttons() -> void:
	for child: Node in vote_row.get_children():
		child.queue_free()
	vote_buttons.clear()
	for p: int in racing:
		if p == local_id:
			continue
		var btn: Button = Button.new()
		btn.text = _name(p)
		btn.custom_minimum_size = Vector2(120, 44)
		btn.pressed.connect(_on_vote_pressed.bind(p))
		vote_row.add_child(btn)
		vote_buttons[p] = btn
	_update_vote_buttons()


func _update_vote_buttons() -> void:
	var active: bool = voting and can_vote and my_vote < 0
	for p: int in vote_buttons:
		var btn: Button = vote_buttons[p]
		btn.disabled = not active
		btn.modulate = Color(0.5, 1.0, 0.5) if my_vote == p else (Color.WHITE if active else Color(0.6, 0.6, 0.6))
	var me_racing: bool = local_id in racing
	vote_title.visible = me_racing
	vote_row.visible = me_racing


func _process(delta: float) -> void:
	if voting and time_left > 0.0:
		time_left = maxf(time_left - delta, 0.0)
		timer_label.text = "%d s to vote  -  %d/%d voted" % [ceili(time_left), voted_count, racing.size()]


## Late join: positions, racers, and the last RESOLVED round only.
func apply_state(st: Dictionary) -> void:
	if st.has("players"):
		_set_players(st["players"])
	for k: Variant in (st.get("positions", {}) as Dictionary):
		positions[int(k)] = int(st["positions"][k])
	racing.clear()
	for p: Variant in st.get("racing", []):
		racing.append(int(p))
	finish_place.clear()
	var place: int = 1
	for group: Variant in st.get("finish_order", []):
		for p: Variant in group:
			finish_place[int(p)] = place
		place += (group as Array).size()
	round_num = int(st.get("round", 0))
	voting = String(st.get("phase", "")) == "voting"
	time_left = float(st.get("time_left", 0.0))
	voted_count = int(st.get("votes_cast", 0))
	voted_this_round.clear()
	round_label.text = "Round %d" % (round_num + 1)
	var reveal: Dictionary = st.get("last_reveal", {})
	if not reveal.is_empty():
		_show_reveal(reveal)
	_rebuild_track()
	_rebuild_vote_buttons()


func on_event(ev: Dictionary) -> void:
	match ev["type"]:
		&"vote_race_started":
			_set_players(ev.get("players", []))
			racing = players_list.duplicate()
			finish_place.clear()
			_rebuild_track()
		&"vote_race_round":
			round_num = int(ev.get("round", 0))
			racing.clear()
			for p: Variant in ev.get("racing", []):
				racing.append(int(p))
			voting = true
			voted_count = 0
			voted_this_round.clear()
			my_vote = -1
			time_left = float(ev.get("time_left", 8.0))
			round_label.text = "Round %d" % (round_num + 1)
			status_label.text = "Vote now - who should NOT move?" if local_id in racing else "You're done - watch the rest race."
			_update_track()
			_rebuild_vote_buttons()
		&"vote_race_voted":
			var who: int = int(ev.get("player", -1))
			if not voted_this_round.has(who):
				voted_this_round[who] = true
				voted_count += 1
			_update_track()
		&"vote_race_reveal":
			voting = false
			timer_label.text = ""
			for k: Variant in (ev.get("positions", {}) as Dictionary):
				positions[int(k)] = int(ev["positions"][k])
			var place: int = finish_place.size() + 1
			for p: Variant in ev.get("finished", []):
				finish_place[int(p)] = place
			racing.clear()
			for p: Variant in ev.get("racing", []):
				racing.append(int(p))
			_show_reveal(ev)
			_update_track()
			_update_vote_buttons()
		&"vote_race_over":
			voting = false
			timer_label.text = ""
			vote_title.visible = false
			vote_row.visible = false
			var ranking: Array = ev.get("ranking", [])
			if not ranking.is_empty():
				var top: int = int((ranking[0] as Dictionary).get("player", -1))
				status_label.text = "YOU WIN!" if top == local_id else "%s wins the race!" % _name(top)


func _show_reveal(rev: Dictionary) -> void:
	var lines: PackedStringArray = ["Round %d reveal:" % (int(rev.get("round", 0)) + 1)]
	var cast: Dictionary = rev.get("votes", {})
	for voter: Variant in cast:
		lines.append("%s voted for %s" % [_name(int(voter)), _name(int(cast[voter]))])
	if cast.is_empty():
		lines.append("Nobody voted.")
	var moved: Array = rev.get("moved", [])
	if moved.is_empty():
		lines.append("Everyone got a vote - nobody moves.")
	else:
		var names: PackedStringArray = []
		for p: Variant in moved:
			names.append(_name(int(p)))
		lines.append("Step forward: " + ", ".join(names))
	reveal_label.text = "\n".join(lines)
	var me_moved: bool = local_id in moved.map(func(x: Variant) -> int: return int(x))
	if finish_place.has(local_id) and local_id in (rev.get("finished", []) as Array).map(func(x: Variant) -> int: return int(x)):
		status_label.text = "You reached the cashier - finished #%d!" % finish_place[local_id]
	elif me_moved:
		status_label.text = "Nobody voted for you - you step forward!"
	elif local_id in racing:
		status_label.text = "You got votes - you stay put."


func _on_vote_pressed(target: int) -> void:
	if not voting or not can_vote or my_vote >= 0:
		return
	my_vote = target
	status_label.text = "You secretly voted for %s" % _name(target)
	Net.send_intent(Intents.make(&"vote_race_vote", {"target": target}))
	_update_vote_buttons()


## Called every frame with the local private snapshot.
func on_private(priv: Dictionary) -> void:
	var mg: Dictionary = priv.get("minigame", priv)
	var cv: bool = bool(mg.get("can_vote", false))
	var vf: int = int(mg.get("voted_for", -1))
	if cv == can_vote and (vf < 0 or vf == my_vote):
		return
	can_vote = cv
	if vf >= 0:
		my_vote = vf
	_update_vote_buttons()
