class_name LonelyNumberStage
extends MinigameStage
## Client presentation for Lonely Number: a 4×5 grid of numbers 1-20, a round counter and pick
## timer, the scoreboard (round wins, tiebreak total) and the last round's reveal showing who picked
## what and which number was lonely. Keyboard: type the number and press Enter. Everything shown
## comes from server events and snapshots; the local pick goes out as a `submit_answer` intent.

const ROUNDS: int = LonelyNumberLogic.ROUNDS

var root: Control
var round_label: Label
var timer_label: Label
var status_label: Label
var grid: GridContainer
var buttons: Array[Button] = []
var reveal_box: VBoxContainer
var reveal_title: Label
var reveal_rows: VBoxContainer
var score_rows: VBoxContainer

var players: Array[int] = []
var round: int = 0
var picking: bool = false
var timer: float = 0.0
var my_pick: int = -1
var picked: Array[int] = []
var wins: Dictionary = {}
var totals: Dictionary = {}
var ranking: Array = []
var _typed: String = ""


func _build(start: Dictionary) -> void:
	for p: Variant in start.get("players", []):
		players.append(int(p))
	_build_ui()
	picking = true
	timer = LonelyNumberLogic.PICK_SECONDS
	_refresh()


func _build_ui() -> void:
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)

	var bg := ColorRect.new()
	bg.color = Palette.CASINO_BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	root.add_child(margin)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override(&"separation", 32)
	margin.add_child(cols)

	# Left: title, rules, round info, number grid, status.
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.6
	left.add_theme_constant_override(&"separation", 12)
	cols.add_child(left)

	left.add_child(_label("LONELY NUMBER", 44, Palette.VIP_GOLD))
	var rules := _label("Pick 1-20 in secret. The HIGHEST number nobody else picked wins the round.", 20, Palette.CREAM.darkened(0.15))
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(rules)

	var info := HBoxContainer.new()
	round_label = _label("", 30, Palette.CREAM)
	round_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(round_label)
	timer_label = _label("", 30, Palette.WARM_GOLD)
	info.add_child(timer_label)
	left.add_child(info)

	grid = GridContainer.new()
	grid.columns = 5
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override(&"h_separation", 10)
	grid.add_theme_constant_override(&"v_separation", 10)
	left.add_child(grid)
	for num: int in range(LonelyNumberLogic.MIN_NUMBER, LonelyNumberLogic.MAX_NUMBER + 1):
		var btn := Button.new()
		btn.text = str(num)
		btn.custom_minimum_size = Vector2(96, 64)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override(&"font_size", 30)
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_pick.bind(num))
		buttons.append(btn)
		grid.add_child(btn)

	status_label = _label("", 24, Palette.CREAM)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(status_label)

	# Right: scoreboard and last round's reveal.
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override(&"separation", 10)
	cols.add_child(right)

	right.add_child(_label("SCORE  (wins / total)", 26, Palette.VIP_GOLD))
	score_rows = VBoxContainer.new()
	right.add_child(score_rows)

	reveal_box = VBoxContainer.new()
	reveal_box.add_theme_constant_override(&"separation", 6)
	right.add_child(reveal_box)
	reveal_title = _label("", 26, Palette.VIP_GOLD)
	reveal_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reveal_box.add_child(reveal_title)
	reveal_rows = VBoxContainer.new()
	reveal_box.add_child(reveal_rows)
	reveal_box.visible = false


func _process(delta: float) -> void:
	if picking and timer > 0.0:
		timer = maxf(timer - delta, 0.0)
		timer_label.text = "%ds" % ceili(timer)


func _unhandled_input(event: InputEvent) -> void:
	if not _can_pick():
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var digit: int = -1
	if key.keycode >= KEY_0 and key.keycode <= KEY_9:
		digit = key.keycode - KEY_0
	elif key.keycode >= KEY_KP_0 and key.keycode <= KEY_KP_9:
		digit = key.keycode - KEY_KP_0
	if digit >= 0:
		_typed = (_typed + str(digit)).right(2)
		_refresh()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
		var n: int = int(_typed) if _typed != "" else -1
		_typed = ""
		if n >= LonelyNumberLogic.MIN_NUMBER and n <= LonelyNumberLogic.MAX_NUMBER:
			_on_pick(n)
		else:
			_refresh()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_BACKSPACE:
		_typed = _typed.left(-1)
		_refresh()
		get_viewport().set_input_as_handled()


func _can_pick() -> bool:
	return picking and my_pick < 0 and local_id in players


func _on_pick(num: int) -> void:
	if not _can_pick():
		return
	my_pick = num
	_typed = ""
	Audio.play(&"ui_click", &"UI", -4.0)
	Net.send_intent(Intents.make(&"submit_answer", {"number": num}))
	_refresh()


# --- Server data -------------------------------------------------------------------------------

func apply_state(st: Dictionary) -> void:
	round = int(st.get("round", 0))
	picking = int(st.get("state", LonelyNumberLogic.State.PICKING)) == LonelyNumberLogic.State.PICKING
	timer = float(st.get("timer", 0.0))
	picked.clear()
	for p: Variant in st.get("picked", []):
		picked.append(int(p))
	wins = (st.get("wins", {}) as Dictionary).duplicate()
	totals = (st.get("totals", {}) as Dictionary).duplicate()
	for p: Variant in wins:
		if int(p) not in players:
			players.append(int(p))
	var hist: Array = st.get("history", [])
	if not hist.is_empty():
		_show_reveal(hist[hist.size() - 1])
	if st.has("ranking"):
		ranking = st["ranking"]
		picking = false
	_refresh()


func on_event(ev: Dictionary) -> void:
	match ev["type"]:
		&"lonely_number_round_started":
			round = int(ev.get("round", round))
			timer = float(ev.get("seconds", LonelyNumberLogic.PICK_SECONDS))
			picking = true
			my_pick = -1
			picked.clear()
			_refresh()
		&"lonely_number_picked":
			var p: int = int(ev.get("player", -1))
			if p not in picked:
				picked.append(p)
			_refresh()
		&"lonely_number_round_end":
			picking = false
			round = int(ev.get("round", round)) + 1
			wins = (ev.get("wins", wins) as Dictionary).duplicate()
			totals = (ev.get("totals", totals) as Dictionary).duplicate()
			_show_reveal(ev)
			_refresh()
		&"lonely_number_finished":
			ranking = ev.get("ranking", [])
			picking = false
			_refresh()


func on_private(priv: Dictionary) -> void:
	var mine: Dictionary = priv.get("minigame", {})
	if mine.is_empty() or int(mine.get("round", -1)) != round:
		return
	var server_pick: int = int(mine.get("my_pick", -1))
	if server_pick > 0 and server_pick != my_pick:
		my_pick = server_pick  # e.g. rejoined mid-round after picking
		_refresh()


# --- Presentation ------------------------------------------------------------------------------

func _refresh() -> void:
	var finished: bool = not ranking.is_empty()
	round_label.text = "Final results" if finished else "Round %d / %d" % [mini(round + 1, ROUNDS), ROUNDS]
	timer_label.visible = picking
	var can: bool = _can_pick()
	for i: int in buttons.size():
		var num: int = i + LonelyNumberLogic.MIN_NUMBER
		var btn: Button = buttons[i]
		btn.disabled = not can
		var hl: bool = num == my_pick or (_typed != "" and num == int(_typed))
		btn.modulate = Palette.WARM_GOLD if hl else Color.WHITE
	if finished:
		var me: Dictionary = {}
		for row: Variant in ranking:
			if int((row as Dictionary)["player"]) == local_id:
				me = row
		status_label.text = "You placed #%d" % int(me["rank"]) if not me.is_empty() else "Game over"
	elif local_id not in players:
		status_label.text = "Spectating"
	elif picking and my_pick > 0:
		status_label.text = "You picked %d - waiting for others (%d/%d)" % [my_pick, picked.size(), players.size()]
	elif picking:
		status_label.text = ("Typed: %s  (Enter to lock in)" % _typed) if _typed != "" else "Pick a number! (%d/%d picked)" % [picked.size(), players.size()]
	else:
		status_label.text = "Next round coming up..." if round < ROUNDS else "Tallying..."
	_refresh_scores()


func _refresh_scores() -> void:
	for c: Node in score_rows.get_children():
		c.queue_free()
	var rows: Array[Dictionary] = []
	if not ranking.is_empty():
		for r: Variant in ranking:
			rows.append(r)
	else:
		for p: int in players:
			rows.append({"player": p, "points": int(wins.get(p, 0)), "total": int(totals.get(p, 0))})
		rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if a["points"] != b["points"]:
				return a["points"] > b["points"]
			return a["total"] > b["total"])
	for i: int in rows.size():
		var r: Dictionary = rows[i]
		var pid: int = int(r["player"])
		var h := HBoxContainer.new()
		h.add_theme_constant_override(&"separation", 10)
		if r.has("rank"):
			h.add_child(_label("#%d" % int(r["rank"]), 24, Palette.VIP_GOLD if int(r["rank"]) == 1 else Palette.CREAM))
		h.add_child(_dot(_player_color(pid), 16))
		var name_lbl := _label(state.player_name(pid) if state != null else "Player %d" % pid, 24, Palette.VIP_GOLD if pid == local_id else Palette.CREAM)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.clip_text = true
		h.add_child(name_lbl)
		if picking and pid in picked:
			h.add_child(_label("picked", 18, Palette.MONEY_GREEN))
		h.add_child(_label("%d / %d" % [int(r.get("points", 0)), int(r.get("total", 0))], 24, Palette.CREAM))
		score_rows.add_child(h)


func _show_reveal(res: Dictionary) -> void:
	reveal_box.visible = true
	var lonely: int = int(res.get("lonely_number", -1))
	var winner: int = int(res.get("winner", -1))
	var rnd: int = int(res.get("round", 0)) + 1
	if winner >= 0:
		reveal_title.text = "Round %d: %s wins with %d!" % [rnd, _name(winner), lonely]
	else:
		reveal_title.text = "Round %d: no lonely number - nobody wins" % rnd
	for c: Node in reveal_rows.get_children():
		c.queue_free()
	var picks: Dictionary = res.get("picks", {})
	var order: Array = picks.keys()
	order.sort_custom(func(a: Variant, b: Variant) -> bool: return int(picks[a]) > int(picks[b]))
	for p: Variant in order:
		var n: int = int(picks[p])
		var h := HBoxContainer.new()
		h.add_theme_constant_override(&"separation", 10)
		h.add_child(_dot(_player_color(int(p)), 14))
		var who := _label(_name(int(p)), 20, Palette.CREAM)
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(who)
		h.add_child(_label(str(n), 22, Palette.MONEY_GREEN if n == lonely else Palette.LOSS_RED.lightened(0.2)))
		reveal_rows.add_child(h)
	for p: int in players:
		if not picks.has(p):
			var miss := _label("%s: no pick" % _name(p), 18, Palette.CREAM.darkened(0.4))
			reveal_rows.add_child(miss)


func _name(pid: int) -> String:
	return state.player_name(pid) if state != null else "Player %d" % pid


func _player_color(pid: int) -> Color:
	var info: Dictionary = state.players.get(pid, {}) if state != null else {}
	return Palette.player_color(int(info.get("color", pid - 1)))


func _label(text: String, size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override(&"font_size", size)
	lbl.add_theme_color_override(&"font_color", color)
	return lbl


func _dot(c: Color, px: int) -> ColorRect:
	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(px, px)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.color = c
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return dot
