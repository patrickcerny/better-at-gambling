class_name SplitOrStealStage
extends MinigameStage
## Client presentation for the Split or Steal Tournament: pure 2D over an opaque backdrop.
##
## Layout (1920×1080 base): header with round + phase timer at the top; the matchup card in the
## middle (you vs. your opponent, both with a live "speaking" mic indicator); SPLIT / STEAL below
## it (keys 1 / 2, pad A / B); standings on the right; the other pairs of this round on the left;
## the payoff legend at the bottom. Everything shown comes from events, the public snapshot and
## our private state (`can_choose`, `my_choice`).

const SPLIT: String = SplitOrStealLogic.SPLIT
const STEAL: String = SplitOrStealLogic.STEAL
const BYE: int = SplitOrStealLogic.BYE
const SPLIT_COLOR: Color = Palette.FELT_GREEN
const STEAL_COLOR: Color = Palette.CASINO_RED
const PANEL_BG: Color = Color(0.09, 0.08, 0.08, 0.92)
const MUTED: Color = Color(0.95, 0.9, 0.79, 0.55)

enum Step { WAITING, TALK, PICK, REVEAL, OUTRO }

var players: Array[int] = []
var phase: Step = Step.WAITING
var round_index: int = -1
var total_rounds: int = 0
var talk_time: float = 8.0
var pick_time: float = 4.0
var time_left: float = 0.0
var phase_length: float = 1.0
var pairs: Array = []
var bye: int = BYE
var opponent: int = BYE
var points: Dictionary = {}
var steals: Dictionary = {}
var locked: Dictionary = {}
var can_choose: bool = false
var my_choice: String = ""
## player → points gained on the last reveal.
var last_gain: Dictionary = {}
var ranking_rows: Array = []

var header_label: Label
var phase_label: Label
var timer_bar: ProgressBar
var timer_fill: StyleBoxFlat
var me_name: Label
var me_mic: Label
var me_tag: Label
var opp_dot: ColorRect
var opp_name: Label
var opp_mic: Label
var opp_tag: Label
var vs_label: Label
var result_label: Label
var hint_label: Label
var choice_buttons: Dictionary[String, Button] = {}
var standings: VBoxContainer
var others: VBoxContainer
var _headless: bool = false
var _last_tick: int = -1


func _build(start: Dictionary) -> void:
	_headless = DisplayServer.get_name() == "headless"
	for p: Variant in start.get("players", []):
		players.append(int(p))
	for p: int in players:
		points[p] = 0
		steals[p] = 0
	_build_ui()
	_set_phase_text("SPLIT OR STEAL", Palette.WARM_GOLD)
	result_label.text = "Talk it out, then choose. Everyone plays everyone."
	_refresh_all()


func _process(delta: float) -> void:
	if phase == Step.TALK or phase == Step.PICK:
		time_left = maxf(time_left - delta, 0.0)
		timer_bar.value = time_left / maxf(phase_length, 0.01) * 100.0
		var t: int = ceili(time_left)
		if phase == Step.TALK:
			phase_label.text = "TALK IT OUT  %d" % t
		else:
			phase_label.text = "CHOOSE!  %d" % t
			if t <= 3 and t > 0 and t != _last_tick:
				_last_tick = t
				Audio.play(&"countdown_beep", &"UI", -10.0, 1.2)
	_update_mics()


# --- Server data ------------------------------------------------------------------------------

func on_event(ev: Dictionary) -> void:
	match ev.get("type", &""):
		&"split_or_steal_started":
			total_rounds = int(ev.get("total_rounds", 0))
			talk_time = float(ev.get("talk_time", talk_time))
			pick_time = float(ev.get("pick_time", pick_time))
			_refresh_header()
		&"split_or_steal_round":
			round_index = int(ev.get("round", 0))
			total_rounds = int(ev.get("total_rounds", total_rounds))
			_set_round(ev.get("pairs", []), int(ev.get("bye", BYE)))
			_enter_phase(Step.TALK, float(ev.get("talk_time", talk_time)))
			Audio.play(&"whoosh", &"UI", -8.0)
		&"split_or_steal_pick":
			_enter_phase(Step.PICK, float(ev.get("pick_time", pick_time)))
			can_choose = opponent != BYE and my_choice == ""
			_refresh_buttons()
		&"split_or_steal_locked":
			locked[int(ev.get("player", BYE))] = true
			_refresh_matchup()
			_refresh_others()
			_refresh_standings()
		&"split_or_steal_reveal":
			_show_reveal(ev.get("results", []))
			points = _int_keys(ev.get("points", {}))
			steals = _int_keys(ev.get("steals", {}))
			_refresh_standings()
		&"split_or_steal_finished":
			ranking_rows = ev.get("ranking", [])
			_show_final()


## Late join / reconnect: the public snapshot (see `SplitOrStealLogic.get_public_state`).
func apply_state(st: Dictionary) -> void:
	total_rounds = int(st.get("total_rounds", total_rounds))
	talk_time = float(st.get("talk_time", talk_time))
	pick_time = float(st.get("pick_time", pick_time))
	round_index = int(st.get("round", -1))
	points = _int_keys(st.get("points", {}))
	steals = _int_keys(st.get("steals", {}))
	locked.clear()
	for p: Variant in st.get("locked", []):
		locked[int(p)] = true
	if st.has("pairs"):
		_set_round(st["pairs"], int(st.get("bye", BYE)), false)
	var timer: float = float(st.get("timer", 0.0))
	match int(st.get("state", -1)):
		SplitOrStealLogic.State.TALK:
			_enter_phase(Step.TALK, talk_time, timer)
		SplitOrStealLogic.State.PICK:
			_enter_phase(Step.PICK, pick_time, timer)
		SplitOrStealLogic.State.REVEAL:
			_show_reveal(st.get("results", []), false)
		SplitOrStealLogic.State.OUTRO, SplitOrStealLogic.State.DONE:
			ranking_rows = st.get("ranking", [])
			_show_final()
	# Buttons from the snapshot alone: we can pick in PICK if we are paired and not locked in.
	can_choose = phase == Step.PICK and opponent != BYE and not locked.has(local_id)
	_refresh_all()


## Our private minigame state, every frame (the match scene passes the whole private snapshot).
func on_private(priv: Dictionary) -> void:
	var mine: Dictionary = priv.get("minigame", priv)
	if mine.is_empty() or int(mine.get("round", -2)) != round_index:
		return  # stale (or from before the round event reached us)
	# Once we picked locally, a lagging snapshot must not re-open the buttons.
	var choose: bool = bool(mine.get("can_choose", false)) and not locked.has(local_id)
	var chosen: String = str(mine.get("my_choice", ""))
	if choose != can_choose or (chosen != "" and chosen != my_choice):
		can_choose = choose
		if chosen != "":
			my_choice = chosen
		_refresh_buttons()
		_refresh_matchup()


# --- Input ------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not can_choose:
		return
	var pick: String = ""
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var k: Key = (event as InputEventKey).keycode
		if k == KEY_1 or k == KEY_KP_1:
			pick = SPLIT
		elif k == KEY_2 or k == KEY_KP_2:
			pick = STEAL
	elif event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		var b: JoyButton = (event as InputEventJoypadButton).button_index
		if b == JOY_BUTTON_A:
			pick = SPLIT
		elif b == JOY_BUTTON_B:
			pick = STEAL
	if pick != "":
		_on_choice(pick)
		get_viewport().set_input_as_handled()


func _on_choice(choice: String) -> void:
	if not can_choose:
		return
	var res: Dictionary = Net.send_intent(Intents.make(&"split_or_steal_pick", {"choice": choice}))
	if res.has("ok") and not bool(res["ok"]):
		return  # refused (e.g. the pick window just closed): the server's state will follow
	my_choice = choice
	can_choose = false
	locked[local_id] = true
	Audio.play(&"chip_clack", &"UI", -6.0)
	_refresh_buttons()
	_refresh_matchup()
	_refresh_standings()


# --- State changes ----------------------------------------------------------------------------

func _set_round(p_pairs: Variant, p_bye: int, fresh: bool = true) -> void:
	pairs = []
	for pair: Variant in p_pairs:
		pairs.append([int(pair[0]), int(pair[1])])
	bye = p_bye
	opponent = BYE
	for pair: Array in pairs:
		if pair[0] == local_id:
			opponent = pair[1]
		elif pair[1] == local_id:
			opponent = pair[0]
	if fresh:
		locked.clear()
		my_choice = ""
		can_choose = false
		last_gain.clear()
	_refresh_all()


func _enter_phase(p: Step, length: float, remaining: float = -1.0) -> void:
	phase = p
	phase_length = maxf(length, 0.01)
	time_left = remaining if remaining >= 0.0 else length
	_last_tick = -1
	timer_bar.visible = true
	timer_fill.bg_color = Palette.WARM_GOLD if p == Step.TALK else Palette.CASINO_RED
	if p == Step.TALK:
		_set_phase_text("TALK IT OUT  %d" % ceili(time_left), Palette.WARM_GOLD)
		if opponent == BYE:
			result_label.text = "You sit this round out. Listen in..."
		else:
			result_label.text = "Convince %s to split. Or don't." % state.player_name(opponent)
	else:
		_set_phase_text("CHOOSE!  %d" % ceili(time_left), Palette.LOSS_RED)
		result_label.text = "Lock in secretly: SPLIT or STEAL." if opponent != BYE else "Others are choosing..."
	result_label.add_theme_color_override(&"font_color", Palette.CREAM)
	_refresh_all()


func _show_reveal(results: Variant, sound: bool = true) -> void:
	phase = Step.REVEAL
	can_choose = false
	timer_bar.visible = false
	_set_phase_text("REVEAL", Palette.VIP_GOLD)
	last_gain.clear()
	var mine: Dictionary = {}
	for r: Variant in results:
		var row: Dictionary = r
		var a: int = int(row["player_a"])
		var b: int = int(row["player_b"])
		last_gain[a] = int(row["points_a"])
		last_gain[b] = int(row["points_b"])
		if a == local_id or b == local_id:
			mine = row
	_refresh_all()
	if mine.is_empty():
		result_label.text = "You sat out. Watch the carnage."
		result_label.add_theme_color_override(&"font_color", MUTED)
		return
	var i_am_a: bool = int(mine["player_a"]) == local_id
	var my_c: String = str(mine["choice_a"] if i_am_a else mine["choice_b"])
	var their_c: String = str(mine["choice_b"] if i_am_a else mine["choice_a"])
	var my_pts: int = int(mine["points_a"] if i_am_a else mine["points_b"])
	var timed_out: bool = bool(mine["auto_a"] if i_am_a else mine["auto_b"])
	my_choice = my_c
	_reveal_tags(my_c, their_c)
	var opp_name_s: String = state.player_name(opponent)
	var line: String
	var color: Color
	if my_c == SPLIT and their_c == SPLIT:
		line = "You both split. +%d each. How wholesome." % my_pts
		color = Palette.MONEY_GREEN
	elif my_c == STEAL and their_c == SPLIT:
		line = "You stole from %s! +%d" % [opp_name_s, my_pts]
		color = Palette.VIP_GOLD
	elif my_c == SPLIT and their_c == STEAL:
		line = "%s robbed you. +0" % opp_name_s
		color = Palette.LOSS_RED
	else:
		line = "Two thieves, nothing to steal. +0"
		color = Palette.LOSS_RED
	if timed_out:
		line += "  (too slow: counted as SPLIT)"
	result_label.text = line
	result_label.add_theme_color_override(&"font_color", color)
	_pop(result_label)
	if sound:
		Audio.play(&"card_flip", &"UI", -6.0)
		Audio.play(&"cash_register" if my_pts > 0 else &"buzzer", &"UI", -8.0)


func _show_final() -> void:
	phase = Step.OUTRO
	can_choose = false
	timer_bar.visible = false
	_set_phase_text("TOURNAMENT OVER", Palette.VIP_GOLD)
	for r: Variant in ranking_rows:
		var row: Dictionary = r
		points[int(row["player"])] = int(row["points"])
		steals[int(row["player"])] = int(row["steals"])
	var winners: Array[String] = []
	for r: Variant in ranking_rows:
		if int((r as Dictionary)["rank"]) == 1:
			winners.append(state.player_name(int((r as Dictionary)["player"])))
	result_label.text = ("%s wins!" % " & ".join(winners)) if not winners.is_empty() else "Tournament complete!"
	result_label.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	last_gain.clear()
	_refresh_all()
	_pop(result_label)


# --- Drawing ----------------------------------------------------------------------------------

func _refresh_all() -> void:
	if header_label == null:
		return
	_refresh_header()
	_refresh_matchup()
	_refresh_buttons()
	_refresh_standings()
	_refresh_others()


func _refresh_header() -> void:
	if header_label == null:
		return
	if round_index >= 0 and total_rounds > 0:
		header_label.text = "ROUND %d / %d" % [round_index + 1, total_rounds]
	else:
		header_label.text = "SPLIT OR STEAL TOURNAMENT"


func _set_phase_text(text: String, color: Color) -> void:
	phase_label.text = text
	phase_label.add_theme_color_override(&"font_color", color)


func _refresh_matchup() -> void:
	me_name.text = "%s (you)" % state.player_name(local_id)
	me_name.add_theme_color_override(&"font_color", _player_color(local_id))
	if opponent == BYE:
		opp_dot.visible = false
		opp_name.text = "nobody"
		opp_name.add_theme_color_override(&"font_color", MUTED)
		vs_label.text = "SITTING OUT"
		opp_tag.text = ""
	else:
		opp_dot.visible = true
		opp_dot.color = _player_color(opponent)
		opp_name.text = state.player_name(opponent)
		opp_name.add_theme_color_override(&"font_color", _player_color(opponent))
		vs_label.text = "VS"
	if phase == Step.REVEAL:
		return  # `_reveal_tags` owns the tags now
	_set_tag(me_tag, my_choice if my_choice != "" else ("LOCKED IN" if locked.has(local_id) else ""), _choice_color(my_choice))
	if opponent != BYE:
		_set_tag(opp_tag, "LOCKED IN" if locked.has(opponent) else ("thinking..." if phase == Step.PICK else ""), Palette.VIP_GOLD if locked.has(opponent) else MUTED)


func _reveal_tags(mine: String, theirs: String) -> void:
	_set_tag(me_tag, mine, _choice_color(mine))
	_set_tag(opp_tag, theirs, _choice_color(theirs))
	_pop(opp_tag, 1.0, 0.6)


func _set_tag(l: Label, text: String, color: Color) -> void:
	l.text = text
	l.add_theme_color_override(&"font_color", color)


func _choice_color(c: String) -> Color:
	if c == SPLIT:
		return Palette.MONEY_GREEN
	if c == STEAL:
		return Palette.LOSS_RED
	return Palette.VIP_GOLD


func _refresh_buttons() -> void:
	for c: String in choice_buttons:
		var b: Button = choice_buttons[c]
		b.disabled = not can_choose
		if my_choice == c:
			b.modulate = Color.WHITE
		elif my_choice != "" or opponent == BYE:
			b.modulate = Color(1, 1, 1, 0.35)
		else:
			b.modulate = Color.WHITE if can_choose else Color(1, 1, 1, 0.6)
	if opponent == BYE and phase != Step.OUTRO:
		hint_label.text = "No match for you this round"
	elif phase == Step.TALK:
		hint_label.text = "Choices open in %d s" % ceili(time_left)
	elif can_choose:
		hint_label.text = "Press 1 = SPLIT · 2 = STEAL"
	elif my_choice != "" and phase == Step.PICK:
		hint_label.text = "Locked in. Waiting for the others..."
	else:
		hint_label.text = ""


func _refresh_standings() -> void:
	for c: Node in standings.get_children():
		standings.remove_child(c)
		c.queue_free()
	var rows: Array = players.duplicate()
	rows.sort_custom(func(a: int, b: int) -> bool:
		if _pts(a) != _pts(b):
			return _pts(a) > _pts(b)
		if _stl(a) != _stl(b):
			return _stl(a) < _stl(b)
		return a < b)
	var place: int = 0
	for i: int in rows.size():
		var pid: int = rows[i]
		if i == 0 or _pts(pid) != _pts(rows[i - 1]) or _stl(pid) != _stl(rows[i - 1]):
			place = i + 1
		var h := HBoxContainer.new()
		h.add_theme_constant_override(&"separation", 10)
		h.add_child(_label(str(place), 26, Palette.VIP_GOLD if place == 1 else Palette.CREAM.darkened(0.25), 28))
		h.add_child(_dot(_player_color(pid), 16))
		var n: Label = _label(state.player_name(pid), 26, Palette.VIP_GOLD if pid == local_id else Palette.CREAM)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		n.clip_text = true
		n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		h.add_child(n)
		var tag: Label = _label("", 18, MUTED, 70)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		if phase == Step.REVEAL and last_gain.has(pid):
			tag.text = "+%d" % int(last_gain[pid])
			tag.add_theme_color_override(&"font_color", Palette.MONEY_GREEN if int(last_gain[pid]) > 0 else MUTED)
		elif phase == Step.PICK and locked.has(pid):
			tag.text = "LOCKED"
			tag.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
		elif pid == bye and phase != Step.OUTRO:
			tag.text = "bye"
		h.add_child(tag)
		var pts: Label = _label(str(_pts(pid)), 28, Palette.CREAM, 44)
		pts.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(pts)
		var st: Label = _label("%d stl" % _stl(pid), 18, Palette.LOSS_RED.lerp(MUTED, 0.4) if _stl(pid) > 0 else MUTED, 58)
		st.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(st)
		standings.add_child(h)


func _refresh_others() -> void:
	for c: Node in others.get_children():
		others.remove_child(c)
		c.queue_free()
	for pair: Array in pairs:
		var a: int = pair[0]
		var b: int = pair[1]
		if a == local_id or b == local_id:
			continue
		var h := HBoxContainer.new()
		h.add_theme_constant_override(&"separation", 8)
		h.add_child(_dot(_player_color(a), 12))
		h.add_child(_label(_side_text(a), 20, Palette.CREAM))
		h.add_child(_label("vs", 18, MUTED))
		h.add_child(_dot(_player_color(b), 12))
		h.add_child(_label(_side_text(b), 20, Palette.CREAM))
		others.add_child(h)
	if bye != BYE and bye != local_id:
		others.add_child(_label("%s sits out" % state.player_name(bye), 18, MUTED))
	if others.get_child_count() == 0:
		others.add_child(_label("Just you two.", 18, MUTED))


## "Name" plus a lock mark (pick) or the gained points (reveal).
func _side_text(pid: int) -> String:
	var s: String = state.player_name(pid)
	if phase == Step.REVEAL and last_gain.has(pid):
		return "%s +%d" % [s, int(last_gain[pid])]
	if phase == Step.PICK and locked.has(pid):
		return s + " [locked]"
	return s


## Lights the mic indicators of whoever is audibly talking (voice is global during minigames).
func _update_mics() -> void:
	if me_mic == null:
		return
	var vc: VoiceChannel = VoiceChannel.current
	_set_mic(me_mic, vc != null and vc.is_talking(local_id))
	_set_mic(opp_mic, vc != null and opponent != BYE and vc.is_talking(opponent))


func _set_mic(l: Label, talking: bool) -> void:
	l.text = "SPEAKING" if talking else ""
	l.add_theme_color_override(&"font_color", Palette.MONEY_GREEN)


func _pts(pid: int) -> int:
	return int(points.get(pid, 0))


func _stl(pid: int) -> int:
	return int(steals.get(pid, 0))


## Per-player tables from the wire may carry string keys: normalise to ints.
static func _int_keys(d: Variant) -> Dictionary:
	var out: Dictionary = {}
	if d is Dictionary:
		for k: Variant in d:
			out[int(k)] = int(d[k])
	return out


func _player_color(pid: int) -> Color:
	return Palette.player_color(int(state.players.get(pid, {}).get("color", pid - 1)))


# --- Construction -----------------------------------------------------------------------------

func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = load("res://ui/theme/main_theme.tres") as Theme
	ui.add_child(root)
	# No 3D set: an opaque backdrop hides the casino behind the UI.
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Palette.CASINO_BLACK
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	var felt := ColorRect.new()
	felt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	felt.offset_left = 40
	felt.offset_right = -40
	felt.offset_top = 40
	felt.offset_bottom = -40
	felt.color = Palette.FELT_GREEN.darkened(0.6)
	felt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(felt)

	# Header: round, phase + timer.
	var head := VBoxContainer.new()
	head.set_anchors_preset(Control.PRESET_CENTER_TOP)
	head.anchor_left = 0.5
	head.anchor_right = 0.5
	head.offset_left = -520
	head.offset_right = 520
	head.offset_top = 64
	head.add_theme_constant_override(&"separation", 6)
	root.add_child(head)
	header_label = _label("", 26, Palette.WARM_GOLD)
	header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(header_label)
	phase_label = _label("", 60, Palette.CREAM)
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(phase_label)
	timer_bar = ProgressBar.new()
	timer_bar.show_percentage = false
	timer_bar.custom_minimum_size = Vector2(0, 14)
	timer_bar.value = 100.0
	timer_bar.visible = false
	timer_fill = StyleBoxFlat.new()
	timer_fill.bg_color = Palette.WARM_GOLD
	timer_fill.set_corner_radius_all(7)
	timer_bar.add_theme_stylebox_override(&"fill", timer_fill)
	head.add_child(timer_bar)

	# Matchup card, centre.
	var card := PanelContainer.new()
	card.add_theme_stylebox_override(&"panel", _panel_style(Palette.WARM_GOLD))
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 0.5
	card.anchor_bottom = 0.5
	card.offset_left = -520
	card.offset_right = 520
	card.offset_top = -230
	card.offset_bottom = 60
	root.add_child(card)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override(&"separation", 14)
	card.add_child(cv)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 24)
	cv.add_child(row)
	var me_col: Array = _side_column(row, _player_color(local_id))
	me_name = me_col[0]
	me_mic = me_col[1]
	me_tag = me_col[2]
	vs_label = _label("VS", 44, Palette.VIP_GOLD, 200)
	vs_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vs_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vs_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(vs_label)
	var opp_col: Array = _side_column(row, Palette.CREAM)
	opp_name = opp_col[0]
	opp_mic = opp_col[1]
	opp_tag = opp_col[2]
	opp_dot = opp_col[3]
	result_label = _label("", 30, Palette.CREAM)
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_label.custom_minimum_size = Vector2(980, 84)
	result_label.pivot_offset = Vector2(490, 42)
	cv.add_child(result_label)

	# SPLIT / STEAL buttons under the card.
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_CENTER)
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.anchor_top = 0.5
	bar.anchor_bottom = 0.5
	bar.offset_left = -520
	bar.offset_right = 520
	bar.offset_top = 90
	bar.offset_bottom = 230
	bar.add_theme_constant_override(&"separation", 40)
	root.add_child(bar)
	for c: String in [SPLIT, STEAL]:
		var b := Button.new()
		b.text = ("1   " if c == SPLIT else "2   ") + c
		b.custom_minimum_size = Vector2(500, 130)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override(&"font_size", 52)
		b.focus_mode = Control.FOCUS_NONE
		_style_button(b, SPLIT_COLOR if c == SPLIT else STEAL_COLOR)
		b.pressed.connect(_on_choice.bind(c))
		b.disabled = true
		bar.add_child(b)
		choice_buttons[c] = b
	hint_label = _label("", 24, MUTED)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.set_anchors_preset(Control.PRESET_CENTER)
	hint_label.anchor_left = 0.5
	hint_label.anchor_right = 0.5
	hint_label.anchor_top = 0.5
	hint_label.anchor_bottom = 0.5
	hint_label.offset_left = -520
	hint_label.offset_right = 520
	hint_label.offset_top = 244
	hint_label.offset_bottom = 284
	root.add_child(hint_label)

	# Standings, right.
	var right := _side_panel(root, "STANDINGS", false)
	standings = VBoxContainer.new()
	standings.add_theme_constant_override(&"separation", 6)
	right.add_child(standings)
	right.add_child(_label("Ties: fewer steals wins", 18, MUTED))

	# Other pairs this round, left.
	var left := _side_panel(root, "THIS ROUND", true)
	others = VBoxContainer.new()
	others.add_theme_constant_override(&"separation", 8)
	left.add_child(others)

	# Payoff legend + voice hint, bottom.
	var foot := VBoxContainer.new()
	foot.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	foot.anchor_left = 0.5
	foot.anchor_right = 0.5
	foot.anchor_top = 1.0
	foot.anchor_bottom = 1.0
	foot.offset_left = -700
	foot.offset_right = 700
	foot.offset_top = -150
	foot.offset_bottom = -64
	foot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(foot)
	var legend := _label("Both SPLIT: +1 each     ·     STEAL vs SPLIT: stealer +3, splitter +0     ·     Both STEAL: +0", 22, Palette.CREAM.darkened(0.15))
	legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.add_child(legend)
	var voice := _label(_voice_hint(), 20, MUTED)
	voice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.add_child(voice)


## One side of the matchup: [name, mic, tag, dot].
func _side_column(parent: Control, color: Color) -> Array:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override(&"separation", 6)
	parent.add_child(col)
	var line := HBoxContainer.new()
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	line.add_theme_constant_override(&"separation", 10)
	col.add_child(line)
	var dot: ColorRect = _dot(color, 22)
	line.add_child(dot)
	var name_l: Label = _label("", 38, color)
	name_l.clip_text = true
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_l.custom_minimum_size = Vector2(0, 52)
	line.add_child(name_l)
	var mic: Label = _label("", 20, Palette.MONEY_GREEN)
	mic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mic.custom_minimum_size = Vector2(0, 28)
	col.add_child(mic)
	var tag: Label = _label("", 46, Palette.VIP_GOLD)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.custom_minimum_size = Vector2(0, 64)
	tag.pivot_offset = Vector2(200, 32)
	col.add_child(tag)
	return [name_l, mic, tag, dot]


func _side_panel(root: Control, title: String, left: bool) -> VBoxContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override(&"panel", _panel_style(Palette.WARM_CHARCOAL.lightened(0.15)))
	p.anchor_left = 0.0 if left else 1.0
	p.anchor_right = p.anchor_left
	p.anchor_top = 0.5
	p.anchor_bottom = 0.5
	p.offset_left = 72.0 if left else -452.0
	p.offset_right = 392.0 if left else -72.0
	p.offset_top = -230
	root.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 10)
	p.add_child(v)
	v.add_child(_label(title, 24, Palette.WARM_GOLD))
	return v


func _voice_hint() -> String:
	if VoiceChannel.current == null:
		return "Voice chat is off here: make your case with emotes."
	var mode: String = str(Settings.get_value("voice", "mode", "push_to_talk"))
	if mode == "off":
		return "Your mic is off (Settings → Voice). Everyone can still talk to you."
	if mode == "open_mic":
		return "Mic open: everyone hears everyone during the tournament."
	return "Hold T to talk: everyone hears everyone during the tournament."


func _label(text: String, size: int, color: Color, min_w: float = 0.0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if min_w > 0.0:
		l.custom_minimum_size = Vector2(min_w, 0)
	return l


func _dot(c: Color, px: int) -> ColorRect:
	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(px, px)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.color = c
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return dot


func _panel_style(border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.set_corner_radius_all(16)
	sb.set_border_width_all(3)
	sb.border_color = border
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 20
	sb.content_margin_bottom = 20
	return sb


func _style_button(b: Button, color: Color) -> void:
	for st: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = color.lightened(0.15) if st == "hover" else color.darkened(0.35) if st == "disabled" else color
		sb.set_corner_radius_all(14)
		sb.shadow_color = Color(0, 0, 0, 0.4)
		sb.shadow_size = 6
		sb.shadow_offset = Vector2(0, 3)
		if st == "pressed":
			sb.set_border_width_all(4)
			sb.border_color = Palette.CREAM
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_color_override(&"font_color", Palette.CREAM)
	b.add_theme_color_override(&"font_disabled_color", Palette.CREAM.darkened(0.3))
	b.add_theme_color_override(&"font_hover_color", Color.WHITE)


## A little scale "pop" on a control.
func _pop(c: Control, to: float = 1.0, from: float = 0.85) -> void:
	if c == null or _headless or not is_inside_tree():
		return
	c.scale = Vector2(from, from)
	var tw: Tween = create_tween()
	tw.tween_property(c, "scale", Vector2(to, to), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
