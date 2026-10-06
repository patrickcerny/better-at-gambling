class_name QuizStage
extends MinigameStage
## The Casino Quiz set (§2.9): a game-show stage with one coloured podium per player, Lucky the
## dealer cat as host (who reacts to every reveal), a big screen, and the answer UI. Keys 1-4,
## mouse, or gamepad A/B/X/Y.
##
## Screen layout (1920×1080 base, scaled down for 1280×720): the question card is the only place
## the question is printed (top centre); the big 3D screen shows the countdown / status; the 2×2
## answers sit at the bottom; the scoreboard is on the right; the host's speech bubble on the left.
## Reveals get a short drum roll first (presentation only: the server already decided).

const ANSWER_COLORS: Array[Color] = [Palette.CASINO_RED, Palette.FELT_GREEN, Palette.WARM_GOLD, Color("#3E5C8A")]
const ANSWER_SHAPES: Array[ShapeIcon.Shape] = [ShapeIcon.Shape.TRIANGLE, ShapeIcon.Shape.CIRCLE, ShapeIcon.Shape.SQUARE, ShapeIcon.Shape.DIAMOND]
const PAD_BUTTONS: Array[JoyButton] = [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y]
const PAD_NAMES: Array[String] = ["A", "B", "X", "Y"]
const CATEGORY_NAMES: Dictionary = {
	"casino_trivia": "Casino trivia", "cards_and_dice": "Cards & dice", "luck_and_superstition": "Luck & superstition",
	"game_rules": "House rules", "silly": "Silly",
}
## Seconds of drum roll before a reveal is shown (the server's reveal phase lasts 2.5 s).
const DRUMROLL_TIME: float = 1.2
const GET_READY_LINES: Array[String] = ["Here comes one!", "Ooh, I like this one.", "Paws on the buttons!"]
const ALL_RIGHT_LINES: Array[String] = ["Everybody got it! Too easy?", "A full house of geniuses!"]
const NONE_RIGHT_LINES: Array[String] = ["Nobody? Really?", "Not a single one... *sigh*"]
const SOME_RIGHT_LINES: Array[String] = ["Ooh, a split room!", "Some of you know your stuff!"]

## player → {podium: Node3D, bean: AvatarVisuals, puppet: BeanPuppet, score: Label3D, mark: Label3D}
var podiums: Dictionary[int, Dictionary] = {}
var host: QuizHost
var screen_label: Label3D
var screen_sub: Label3D
var title_3d: Label3D

var card: PanelContainer
var header: Label
var question_label: Label
var status_label: Label
var timer_bar: ProgressBar
var answer_buttons: Array[Button] = []
var answer_texts: Array[Label] = []
var answer_voters: Array[HBoxContainer] = []
var banner: Label
var sub_banner: Label
var explanation: Label
var scoreboard: VBoxContainer
var bubble: PanelContainer
var bubble_label: Label

var index: int = -1
var count: int = 3
var answer_time: float = 12.0
var time_left: float = 0.0
var answering: bool = false
var my_answer: int = -1
var totals: Dictionary = {}
var players: Array[int] = []
## Players who answered the current question (scoreboard "LOCKED IN" tags).
var answered: Dictionary = {}
## Points each player gained on the last reveal (scoreboard "+850").
var last_gain: Dictionary = {}
## A reveal waiting for the drum roll to finish ({} = none).
var pending_reveal: Dictionary = {}
## Index of the last question whose reveal was shown (-1 = none yet).
var revealed_index: int = -1
var _drum_t: float = 0.0
var _drum_next: float = 0.0
var _clock: float = 0.0
var _last_tick: int = -1
var _headless: bool = false


func _build(start: Dictionary) -> void:
	_headless = DisplayServer.get_name() == "headless"
	for p: Variant in start.get("players", []):
		players.append(int(p))
	_build_set()
	_build_ui()
	_show_banner("CASINO QUIZ", "3 questions · answer fast · no changing answers")
	_set_screen("?", "")
	_host_say("Welcome to the show!", QuizHost.Pose.HAPPY)
	_refresh_scoreboard()


func _process(delta: float) -> void:
	_clock += delta
	if answering:
		time_left = maxf(time_left - delta, 0.0)
		timer_bar.value = time_left / answer_time * 100.0
		var t: int = ceili(time_left)
		screen_label.text = str(t)
		screen_label.modulate = Palette.LOSS_RED if t <= 3 else Palette.CREAM
		if t <= 3 and t != _last_tick and t > 0:
			_last_tick = t
			Audio.play(&"countdown_beep", &"UI", -10.0, 1.2)
	if not pending_reveal.is_empty():
		_tick_drumroll(delta)
	_place_bubble()
	title_3d.visible = not card.visible and not banner.visible  # never behind the card or banner


# --- Events ------------------------------------------------------------------------------------

func on_event(ev: Dictionary) -> void:
	if ev["type"] != &"quiz_reveal":
		_flush_reveal()  # anything newer than a pending reveal shows it first
	match ev["type"]:
		&"quiz_started":
			count = int(ev.get("questions", 3))
			answer_time = float(ev.get("answer_time", 12.0))
		&"quiz_get_ready":
			index = int(ev["index"])
			_clear_question()
			banner.visible = false
			sub_banner.visible = false
			_set_screen("QUESTION %d / %d" % [index + 1, count], "Get ready…")
			_host_say("Last one! Make it count." if index == count - 1 else GET_READY_LINES[mini(index, GET_READY_LINES.size() - 1)], QuizHost.Pose.SURPRISED if index == count - 1 else QuizHost.Pose.IDLE)
			for pid: int in podiums:
				(podiums[pid]["puppet"] as BeanPuppet).set_mood(BeanPuppet.Mood.IDLE)
				(podiums[pid]["mark"] as Label3D).text = ""
			Audio.play(&"whoosh", &"UI", -8.0)
		&"quiz_question":
			_show_question(ev)
		&"quiz_answered":
			_mark_answered(int(ev["player"]))
		&"quiz_reveal":
			_begin_reveal(ev)
		&"quiz_finished":
			_finish(ev["ranking"])


func on_private(priv: Dictionary) -> void:
	var mine: Dictionary = priv.get("minigame", {})
	if mine.has("answer") and int(mine.get("question", -1)) == index and my_answer < 0:
		_lock(int(mine["answer"]))


func apply_state(st: Dictionary) -> void:
	count = int(st.get("count", count))
	index = int(st.get("index", -1))
	_set_totals(st.get("totals", {}))
	if st.has("question"):
		var q: Dictionary = st["question"]
		q["seconds"] = float(st.get("timer", 0.0))
		_show_question(q)
		for p: Variant in st.get("answered", []):
			_mark_answered(int(p))
	if st.has("reveal") and int(st.get("state", 0)) >= QuizLogic.State.REVEAL:
		_reveal(st["reveal"], false)  # catching up: no drum roll
	if st.has("ranking"):
		_finish(st["ranking"])
	_refresh_scoreboard()


func _unhandled_input(event: InputEvent) -> void:
	if not answering or my_answer >= 0:
		return
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var k: Key = (event as InputEventKey).keycode
		for i: int in 4:
			if k == KEY_1 + i or k == KEY_KP_1 + i:
				_answer(i)
				get_viewport().set_input_as_handled()
				return
	if event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		var b: JoyButton = (event as InputEventJoypadButton).button_index
		var i: int = PAD_BUTTONS.find(b)
		if i >= 0:
			_answer(i)
			get_viewport().set_input_as_handled()


func _answer(i: int) -> void:
	if not answering or my_answer >= 0 or not local_id in players:
		return
	_lock(i)
	Audio.play(&"ui_click", &"UI", -4.0)
	Net.send_intent(Intents.make(&"submit_answer", {"question": index, "index": i}))


func _lock(i: int) -> void:
	my_answer = i
	for j: int in answer_buttons.size():
		answer_buttons[j].modulate = Color.WHITE if j == i else Color(1, 1, 1, 0.45)
		answer_buttons[j].disabled = true
	_pop(answer_buttons[i], 1.05)
	_set_status("Locked in! Waiting for the others…", Palette.VIP_GOLD)


# --- Presentation ------------------------------------------------------------------------------

func _show_question(q: Dictionary) -> void:
	index = int(q.get("index", index))
	count = int(q.get("count", count))
	banner.visible = false
	sub_banner.visible = false
	my_answer = -1
	_last_tick = -1
	answered.clear()
	last_gain.clear()
	header.text = "QUESTION %d / %d  ·  %s%s" % [index + 1, count, CATEGORY_NAMES.get(str(q.get("category", "")), "Quiz").to_upper(), "  ·  LIVE" if bool(q.get("dynamic", false)) else ""]
	question_label.text = str(q["question"])
	# The question is printed once, on the card; the big screen shows the countdown.
	_set_screen(str(ceili(float(q.get("seconds", answer_time)))), CATEGORY_NAMES.get(str(q.get("category", "")), "Quiz"))
	var answers: Array = q["answers"]
	for i: int in answer_buttons.size():
		answer_texts[i].text = str(answers[i]) if i < answers.size() else ""
		answer_buttons[i].disabled = not local_id in players
		answer_buttons[i].modulate = Color.WHITE
		answer_buttons[i].scale = Vector2.ONE
		_style_button(answer_buttons[i], ANSWER_COLORS[i], false)
		for c: Node in answer_voters[i].get_children():
			c.queue_free()
	for pid: int in podiums:
		(podiums[pid]["mark"] as Label3D).text = ""
	card.visible = true
	for b: Button in answer_buttons:
		b.visible = true
	explanation.visible = false
	time_left = float(q.get("seconds", answer_time))
	answering = true
	timer_bar.visible = true
	if local_id in players:
		_set_status("", Palette.CREAM)
	else:
		_set_status("Watching: you were away when the quiz started", Palette.CREAM.darkened(0.2))
	_host_say("Tick tock!", QuizHost.Pose.IDLE)
	_refresh_scoreboard()
	Audio.play(&"card_flip", &"UI", -6.0)


func _clear_question() -> void:
	answering = false
	my_answer = -1
	card.visible = false
	for b: Button in answer_buttons:
		b.visible = false
	timer_bar.visible = false
	explanation.visible = false
	answered.clear()
	last_gain.clear()
	_refresh_scoreboard()


func _mark_answered(pid: int) -> void:
	answered[pid] = true
	if podiums.has(pid):
		var mark: Label3D = podiums[pid]["mark"]
		mark.text = "!"
		mark.modulate = Palette.VIP_GOLD
		(podiums[pid]["puppet"] as BeanPuppet).hop(0.25)
	_refresh_scoreboard()


## The answer window closed: drum roll, then the reveal.
func _begin_reveal(ev: Dictionary) -> void:
	answering = false
	timer_bar.visible = false
	_set_totals(ev.get("totals", totals))  # the data is final now; only the show waits
	pending_reveal = ev
	_drum_t = 0.0
	_drum_next = 0.0
	for b: Button in answer_buttons:
		b.disabled = true
	_set_screen("…", "And the answer is…")
	screen_label.modulate = Palette.VIP_GOLD
	_host_say("And the answer is…", QuizHost.Pose.DRUMROLL)
	if my_answer < 0 and local_id in players:
		_set_status("Time's up!", Palette.LOSS_RED)


func _tick_drumroll(delta: float) -> void:
	_drum_t += delta
	var k: float = clampf(_drum_t / DRUMROLL_TIME, 0.0, 1.0)
	_drum_next -= delta
	if _drum_next <= 0.0:
		# A roll of chip clacks that speeds up and rises in pitch.
		_drum_next = lerpf(0.13, 0.04, k)
		Audio.play(&"chip_clack", &"UI", -12.0 + k * 4.0, 0.8 + k * 0.5)
	# The highlight races over the answers like a roulette ball.
	var lit: int = int(_drum_t * lerpf(8.0, 20.0, k)) % answer_buttons.size()
	for i: int in answer_buttons.size():
		var base: Color = Color.WHITE if my_answer < 0 or i == my_answer else Color(1, 1, 1, 0.45)
		answer_buttons[i].modulate = base.lightened(0.35) if i == lit else base
	screen_label.text = ".".repeat(1 + int(_drum_t * 5.0) % 3)
	if _drum_t >= DRUMROLL_TIME:
		_flush_reveal()


func _flush_reveal() -> void:
	if pending_reveal.is_empty():
		return
	var ev: Dictionary = pending_reveal
	pending_reveal = {}
	_reveal(ev, true)


func _reveal(ev: Dictionary, live: bool) -> void:
	answering = false
	timer_bar.visible = false
	revealed_index = int(ev.get("index", index))
	var correct: int = int(ev["correct_index"])
	var chosen: Dictionary = _int_keys(ev.get("answers", {}))
	var gained: Dictionary = _int_keys(ev.get("points", {}))
	last_gain = gained
	_set_totals(ev.get("totals", totals))
	for i: int in answer_buttons.size():
		answer_buttons[i].disabled = true
		var right: bool = i == correct
		_style_button(answer_buttons[i], Palette.MONEY_GREEN if right else Palette.WARM_CHARCOAL, right)
		answer_buttons[i].modulate = Color.WHITE if right or i == my_answer else Color(1, 1, 1, 0.5)
	if correct >= 0 and correct < answer_buttons.size():
		_pop(answer_buttons[correct], 1.06)
	for c: HBoxContainer in answer_voters:
		for n: Node in c.get_children():
			n.queue_free()
	for pid: Variant in chosen:
		var choice: int = int(chosen[pid])
		if choice >= 0 and choice < answer_voters.size():
			answer_voters[choice].add_child(_dot(_player_color(int(pid)), 18))
	var right_count: int = 0
	for pid: int in podiums:
		var pts: int = int(gained.get(pid, 0))
		var mark: Label3D = podiums[pid]["mark"]
		mark.text = ("+%d" % pts) if pts > 0 else ("X" if chosen.has(pid) else "-")
		mark.modulate = Palette.MONEY_GREEN if pts > 0 else Palette.LOSS_RED
		var puppet: BeanPuppet = podiums[pid]["puppet"]
		puppet.set_mood(BeanPuppet.Mood.CHEER if pts > 0 else BeanPuppet.Mood.SAD)
		if pts > 0:
			right_count += 1
			if live:
				_float_mark(mark)
				ConfettiBurst.burst(podiums[pid]["podium"] as Node3D, Vector3(0, 2.6, 0), 60, 0.8)
	var n: int = podiums.size()
	_set_screen("%d / %d" % [right_count, n], "got it right!")
	screen_label.modulate = Palette.MONEY_GREEN if right_count > 0 else Palette.LOSS_RED
	var answer_text: String = answer_texts[correct].text if correct >= 0 and correct < answer_texts.size() else ""
	if right_count == 0:
		_host_say("%s It was \"%s\"." % [NONE_RIGHT_LINES[revealed_index % NONE_RIGHT_LINES.size()], answer_text], QuizHost.Pose.DISAPPOINTED)
	elif right_count == n:
		_host_say(ALL_RIGHT_LINES[revealed_index % ALL_RIGHT_LINES.size()], QuizHost.Pose.HAPPY)
	else:
		_host_say("%s It's \"%s\"!" % [SOME_RIGHT_LINES[revealed_index % SOME_RIGHT_LINES.size()], answer_text], QuizHost.Pose.SURPRISED)
	var mine: int = int(gained.get(local_id, 0))
	if local_id in players:
		_set_status(("CORRECT!  +%d" % mine) if mine > 0 else ("WRONG!" if my_answer >= 0 else "TOO SLOW!"), Palette.MONEY_GREEN if mine > 0 else Palette.LOSS_RED)
		_pop(status_label, 1.25)
		if live:
			Audio.play(&"coin" if mine > 0 else &"buzzer", &"UI", -4.0)
	var text: String = str(ev.get("explanation", ""))
	explanation.text = text
	explanation.visible = text != ""
	_refresh_scoreboard()


func _finish(ranking: Array) -> void:
	answering = false
	pending_reveal = {}
	card.visible = false
	for b: Button in answer_buttons:
		b.visible = false
	explanation.visible = false
	timer_bar.visible = false
	answered.clear()
	last_gain.clear()
	if ranking.is_empty():
		return
	var top: Dictionary = ranking[0]
	var winners: Array[String] = []
	for row: Variant in ranking:
		if int(row["rank"]) == 1:
			winners.append(state.player_name(int(row["player"])))
	_set_screen("WINNER" if winners.size() == 1 else "WINNERS", " & ".join(winners))
	screen_label.modulate = Palette.VIP_GOLD
	_show_banner("%s WIN%s THE QUIZ!" % [" & ".join(winners).to_upper(), "" if winners.size() > 1 else "S"], "%s points" % Hud._thousands(int(top["points"])))
	var last_rank: int = int(ranking[-1]["rank"])
	for row: Variant in ranking:
		var pid: int = int(row["player"])
		totals[pid] = int(row["points"])
		if podiums.has(pid):
			var rank: int = int(row["rank"])
			var puppet: BeanPuppet = podiums[pid]["puppet"]
			puppet.set_mood(BeanPuppet.Mood.CHEER if rank == 1 else BeanPuppet.Mood.SAD if rank == last_rank and ranking.size() > 1 else BeanPuppet.Mood.IDLE)
			var mark: Label3D = podiums[pid]["mark"]
			mark.text = Hud._ordinal(rank)
			mark.modulate = Palette.VIP_GOLD if rank == 1 else Palette.CREAM
			if rank == 1:
				ConfettiBurst.burst(podiums[pid]["podium"] as Node3D, Vector3(0, 2.8, 0), 140, 1.2)
	ConfettiBurst.rain(self, Vector3(0, 9.0, 0.5), Vector3(16, 0.2, 4), 160)
	_host_say("What a show! Give it up for %s!" % " & ".join(winners), QuizHost.Pose.HAPPY, 0.0)
	Audio.play(&"quiz_winner", &"UI", -3.0)
	_refresh_scoreboard()


## Copies points per player into an int-keyed table (wire dictionaries may carry string keys).
func _set_totals(d: Dictionary) -> void:
	totals = _int_keys(d)


## Plain copy of a per-player table with int keys (events may hold typed or string-keyed ones).
static func _int_keys(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k: Variant in d:
		out[int(k)] = int(d[k])
	return out


func _total(pid: int) -> int:
	return int(totals.get(pid, 0))


func _refresh_scoreboard() -> void:
	if scoreboard == null:
		return
	for c: Node in scoreboard.get_children():
		scoreboard.remove_child(c)
		c.queue_free()
	var rows: Array = players.duplicate()
	rows.sort_custom(func(a: int, b: int) -> bool: return _total(a) > _total(b) or (_total(a) == _total(b) and a < b))
	var place: int = 0
	var prev: int = -1
	for i: int in rows.size():
		var pid: int = rows[i]
		if i == 0 or _total(pid) != prev:
			place = i + 1
		prev = _total(pid)
		var h := HBoxContainer.new()
		h.add_theme_constant_override(&"separation", 10)
		var r := Label.new()
		r.text = str(place)
		r.custom_minimum_size = Vector2(26, 0)
		r.add_theme_font_size_override(&"font_size", 28)
		r.add_theme_color_override(&"font_color", Palette.VIP_GOLD if place == 1 else Palette.CREAM.darkened(0.25))
		h.add_child(r)
		h.add_child(_dot(_player_color(pid), 18))
		var n := Label.new()
		n.text = state.player_name(pid)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		n.clip_text = true
		n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		n.add_theme_font_size_override(&"font_size", 28)
		if pid == local_id:
			n.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
		h.add_child(n)
		var tag := Label.new()
		tag.add_theme_font_size_override(&"font_size", 20)
		tag.custom_minimum_size = Vector2(64, 0)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		if last_gain.has(pid) and int(last_gain[pid]) > 0:
			tag.text = "+%d" % int(last_gain[pid])
			tag.add_theme_color_override(&"font_color", Palette.MONEY_GREEN)
		elif answering and answered.has(pid):
			tag.text = "LOCKED"
			tag.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
		elif answering:
			tag.text = "…"
			tag.add_theme_color_override(&"font_color", Palette.CREAM.darkened(0.4))
		h.add_child(tag)
		var pts := Label.new()
		pts.text = Hud._thousands(_total(pid))
		pts.custom_minimum_size = Vector2(70, 0)
		pts.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		pts.add_theme_font_size_override(&"font_size", 28)
		h.add_child(pts)
		scoreboard.add_child(h)
	for pid: int in podiums:
		(podiums[pid]["score"] as Label3D).text = Hud._thousands(_total(pid))


func _show_banner(title: String, sub: String) -> void:
	banner.text = title
	banner.visible = true
	sub_banner.text = sub
	sub_banner.visible = sub != ""
	_pop(banner, 1.0, 0.75)


func _set_screen(main: String, sub: String) -> void:
	screen_label.text = main
	screen_label.modulate = Palette.CREAM
	screen_sub.text = sub


func _set_status(text: String, color: Color) -> void:
	status_label.text = text
	status_label.visible = text != ""
	status_label.add_theme_color_override(&"font_color", color)


## The host speaks (speech bubble) and strikes a pose (`hold` 0 = keep the pose).
func _host_say(text: String, pose: QuizHost.Pose = QuizHost.Pose.IDLE, hold: float = 2.2) -> void:
	if host == null:
		return
	host.say(text)
	host.set_pose(pose, hold)
	if bubble_label != null:
		bubble_label.text = text
		bubble.visible = text != ""
		_pop(bubble, 1.0, 0.85)


## Keeps the speech bubble next to Lucky's head on screen.
func _place_bubble() -> void:
	if bubble == null or not bubble.visible or camera == null or host == null:
		return
	var p: Vector2 = camera.unproject_position(host.bubble_anchor())
	var vp: Vector2 = get_viewport().get_visible_rect().size
	bubble.reset_size()
	# The bubble grows up and to the left of Lucky's head, away from the contestants' podiums.
	bubble.pivot_offset = Vector2(bubble.size.x, bubble.size.y)
	bubble.position = Vector2(clampf(p.x - bubble.size.x + 90.0, 16.0, vp.x - bubble.size.x - 16.0), clampf(p.y - bubble.size.y, 16.0, vp.y - bubble.size.y - 260.0))


## A little scale "pop" on a control.
func _pop(c: Control, to: float = 1.0, from: float = 0.85) -> void:
	if c == null or _headless:
		return
	c.pivot_offset = c.size * 0.5 if c != bubble else c.size
	c.scale = Vector2(from, from)
	var t: Tween = c.create_tween()
	t.tween_property(c, "scale", Vector2(to, to), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if to != 1.0:
		t.tween_property(c, "scale", Vector2.ONE, 0.2)


## The "+850" over a podium floats up and settles back.
func _float_mark(mark: Label3D) -> void:
	if _headless:
		return
	var y0: float = 3.3
	mark.position.y = y0 - 0.4
	mark.scale = Vector3.ONE * 0.6
	var t: Tween = mark.create_tween().set_parallel(true)
	t.tween_property(mark, "position:y", y0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(mark, "scale", Vector3.ONE * 1.25, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.chain().tween_property(mark, "scale", Vector3.ONE, 0.25)


func _player_color(pid: int) -> Color:
	return Palette.player_color(int(state.players.get(pid, {}).get("color", pid - 1)))


func _dot(c: Color, px: int) -> ColorRect:
	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(px, px)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.color = c
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return dot


func _style_button(b: Button, color: Color, outline: bool) -> void:
	for st: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = color.lightened(0.12) if st == "hover" else color
		sb.set_corner_radius_all(12)
		sb.content_margin_left = 16
		sb.content_margin_right = 16
		sb.content_margin_top = 10
		sb.content_margin_bottom = 10
		sb.shadow_color = Color(0, 0, 0, 0.35)
		sb.shadow_size = 6
		sb.shadow_offset = Vector2(0, 3)
		if outline or st == "focus":
			sb.set_border_width_all(5)
			sb.border_color = Palette.VIP_GOLD
		b.add_theme_stylebox_override(st, sb)


# --- Building ----------------------------------------------------------------------------------

func _build_set() -> void:
	var floor_mesh := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(34, 0.2, 24)
	floor_mesh.mesh = fm
	floor_mesh.position = Vector3(0, -0.1, 0)
	floor_mesh.material_override = _mat(Palette.VIP_BURGUNDY.darkened(0.25))
	add_child(floor_mesh)
	var wall := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(34, 14, 0.3)
	wall.mesh = wm
	wall.position = Vector3(0, 7.0, -4.5)
	wall.material_override = _mat(Palette.WARM_CHARCOAL)
	add_child(wall)
	for x: float in [-8.6, 8.6]:
		var pillar := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.3
		pm.bottom_radius = 0.35
		pm.height = 9.0
		pillar.mesh = pm
		pillar.position = Vector3(x, 4.5, -4.1)
		pillar.material_override = _mat(Palette.WARM_GOLD, 0.7)
		add_child(pillar)
	# Marquee bulbs along the screen frame (warm glow, no neon).
	var bulb_mat: StandardMaterial3D = _mat(Color("#FFE2B0"), 0.0, true)
	for i: int in 15:
		for y: float in [7.08, 3.32]:
			var bulb := MeshInstance3D.new()
			var bmesh := SphereMesh.new()
			bmesh.radius = 0.07
			bmesh.height = 0.14
			bulb.mesh = bmesh
			bulb.material_override = bulb_mat
			bulb.position = Vector3(-4.55 + i * 0.65, y, -4.12)
			add_child(bulb)
	# Big screen with a gold frame.
	var frame := MeshInstance3D.new()
	var frm := BoxMesh.new()
	frm.size = Vector3(9.4, 3.9, 0.15)
	frame.mesh = frm
	frame.position = Vector3(0, 5.2, -4.25)
	frame.material_override = _mat(Palette.WARM_GOLD, 0.8)
	add_child(frame)
	var screen := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(8.8, 3.3, 0.1)
	screen.mesh = sm
	screen.position = Vector3(0, 5.2, -4.15)
	screen.material_override = _mat(Palette.FELT_GREEN.darkened(0.5))
	add_child(screen)
	screen_label = Label3D.new()
	screen_label.font_size = 140
	screen_label.pixel_size = 0.006
	screen_label.width = 1400
	screen_label.outline_size = 0
	screen_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	screen_label.modulate = Palette.CREAM
	screen_label.position = Vector3(0, 5.45, -4.05)
	add_child(screen_label)
	screen_sub = Label3D.new()
	screen_sub.font_size = 64
	screen_sub.pixel_size = 0.006
	screen_sub.width = 1400
	screen_sub.outline_size = 0
	screen_sub.modulate = Palette.WARM_GOLD
	screen_sub.position = Vector3(0, 4.2, -4.05)
	add_child(screen_sub)
	title_3d = Label3D.new()
	title_3d.text = "CASINO QUIZ"
	title_3d.font_size = 96
	title_3d.pixel_size = 0.008
	title_3d.modulate = Palette.VIP_GOLD
	title_3d.outline_size = 12
	title_3d.position = Vector3(0, 7.75, -4.2)
	add_child(title_3d)
	# Podiums.
	var n: int = players.size()
	var spacing: float = minf(2.0, 13.0 / maxf(n, 1))
	for i: int in n:
		var pid: int = players[i]
		var x: float = (i - (n - 1) * 0.5) * spacing
		var root := Node3D.new()
		root.position = Vector3(x, 0, 0.8)
		add_child(root)
		var box := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.3, 1.0, 1.0)
		box.mesh = bm
		box.position = Vector3(0, 0.5, 0)
		box.material_override = _mat(_player_color(pid).darkened(0.15))
		root.add_child(box)
		var trim := MeshInstance3D.new()
		var tm := BoxMesh.new()
		tm.size = Vector3(1.4, 0.08, 1.1)
		trim.mesh = tm
		trim.position = Vector3(0, 1.02, 0)
		trim.material_override = _mat(Palette.WARM_GOLD, 0.8)
		root.add_child(trim)
		var bean := AvatarVisuals.new()
		bean.position = Vector3(0, 1.06, -0.15)
		bean.rotation.y = PI  # face the camera
		root.add_child(bean)
		bean.set_color(_player_color(pid))
		bean.set_skin(StringName(state.players.get(pid, {}).get("skin", "bean")))
		var puppet: BeanPuppet = BeanPuppet.attach(bean)
		puppet.cheer_height = 0.22  # stays under the "+850" over the head
		var name_l := Label3D.new()
		var nm: String = state.player_name(pid)
		name_l.text = nm if nm.length() <= 12 else nm.left(11) + "…"
		name_l.font_size = 40 if n <= 6 else 32
		name_l.pixel_size = 0.006
		name_l.outline_size = 8
		name_l.position = Vector3(0, 0.7, 0.52)
		root.add_child(name_l)
		var score := Label3D.new()
		score.text = "0"
		score.font_size = 52
		score.pixel_size = 0.006
		score.outline_size = 10
		score.modulate = Palette.VIP_GOLD
		score.position = Vector3(0, 0.3, 0.52)  # on the podium front, under the name
		root.add_child(score)
		var mark := Label3D.new()
		mark.text = ""
		mark.font_size = 64
		mark.pixel_size = 0.006
		mark.outline_size = 12
		mark.modulate = Palette.VIP_GOLD
		mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		mark.position = Vector3(0, 3.3, -0.15)
		root.add_child(mark)
		podiums[pid] = {"podium": root, "bean": bean, "puppet": puppet, "score": score, "mark": mark}
	# Lucky behind a gold-trimmed lectern, left of the podiums.
	var half_span: float = (n - 1) * 0.5 * spacing + 0.7
	var host_x: float = -maxf(6.0, half_span + 1.7)
	var host_root := Node3D.new()
	host_root.position = Vector3(host_x, 0, 0.4)
	host_root.rotation.y = 0.35  # turned a little towards the contestants
	host_root.scale = Vector3.ONE * 1.25
	add_child(host_root)
	host = QuizHost.new()
	host_root.add_child(host)
	var lectern := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(1.3, 0.8, 0.6)
	lectern.mesh = lm
	lectern.position = Vector3(0, 0.4, 0.8)
	lectern.material_override = _mat(Palette.VIP_BURGUNDY)
	host_root.add_child(lectern)
	var ltrim := MeshInstance3D.new()
	var ltm := BoxMesh.new()
	ltm.size = Vector3(1.4, 0.07, 0.7)
	ltrim.mesh = ltm
	ltrim.position = Vector3(0, 0.83, 0.8)
	ltrim.material_override = _mat(Palette.WARM_GOLD, 0.8)
	host_root.add_child(ltrim)
	var host_light := SpotLight3D.new()
	host_light.position = Vector3(host_x + 1.5, 6.5, 4.0)
	add_child(host_light)
	host_light.look_at(to_global(Vector3(host_x, 1.4, 0.4)))
	host_light.spot_range = 12.0
	host_light.spot_angle = 22.0
	host_light.light_energy = 4.0
	host_light.light_color = Color("#FFE2B0")
	# Light and camera.
	var key := SpotLight3D.new()
	key.position = Vector3(0, 8, 6)
	key.rotation_degrees = Vector3(-50, 0, 0)
	key.spot_range = 20.0
	key.spot_angle = 50.0
	key.light_energy = 3.0
	key.light_color = Color("#FFE2B0")
	key.shadow_enabled = true
	add_child(key)
	for sx: float in [-6.0, 6.0]:
		var fill := OmniLight3D.new()
		fill.position = Vector3(sx, 4, 2)
		fill.omni_range = 10.0
		fill.light_energy = 1.2
		fill.light_color = Palette.VIP_GOLD
		add_child(fill)
	camera = Camera3D.new()
	camera.fov = 55.0
	camera.far = 90.0  # the casino floor is 400 m away: keep its always-on-top labels out
	add_child(camera)
	camera.position = Vector3(0, 3.6, 10.5)
	camera.look_at(global_position + Vector3(0, 2.75, -1.0))


func _mat(c: Color, metallic: float = 0.0, emissive: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metallic
	m.roughness = 0.45 if metallic > 0.0 else 0.8
	if emissive:
		m.emission_enabled = true
		m.emission = c
	return m


func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = load("res://ui/theme/main_theme.tres") as Theme
	ui.add_child(root)
	# Question card, top centre: the only place the question is printed.
	card = PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_CENTER_TOP)
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.offset_left = -580
	card.offset_right = 580
	card.offset_top = 20
	card.visible = false
	root.add_child(card)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override(&"separation", 6)
	card.add_child(cv)
	header = Label.new()
	header.add_theme_font_size_override(&"font_size", 24)
	header.add_theme_color_override(&"font_color", Palette.WARM_GOLD)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(header)
	question_label = Label.new()
	question_label.add_theme_font_size_override(&"font_size", 44)
	question_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	question_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	question_label.custom_minimum_size = Vector2(1100, 0)
	cv.add_child(question_label)
	timer_bar = ProgressBar.new()
	timer_bar.show_percentage = false
	timer_bar.custom_minimum_size = Vector2(0, 12)
	timer_bar.value = 100.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = Palette.WARM_GOLD
	fill.set_corner_radius_all(6)
	timer_bar.add_theme_stylebox_override(&"fill", fill)
	cv.add_child(timer_bar)
	status_label = Label.new()
	status_label.add_theme_font_size_override(&"font_size", 34)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.visible = false
	cv.add_child(status_label)
	explanation = Label.new()
	explanation.add_theme_font_size_override(&"font_size", 24)
	explanation.add_theme_color_override(&"font_color", Palette.CREAM.darkened(0.12))
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	explanation.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	explanation.custom_minimum_size = Vector2(1100, 0)
	explanation.visible = false
	cv.add_child(explanation)
	# Answers, bottom centre, 2 × 2.
	var grid := GridContainer.new()
	grid.columns = 2
	grid.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	grid.anchor_left = 0.5
	grid.anchor_right = 0.5
	grid.anchor_top = 1.0
	grid.anchor_bottom = 1.0
	grid.offset_left = -580
	grid.offset_right = 580
	grid.offset_top = -224
	grid.offset_bottom = -20
	grid.grow_vertical = Control.GROW_DIRECTION_BEGIN
	grid.add_theme_constant_override(&"h_separation", 16)
	grid.add_theme_constant_override(&"v_separation", 12)
	root.add_child(grid)
	for i: int in 4:
		var b := Button.new()
		b.custom_minimum_size = Vector2(560, 92)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		b.visible = false
		b.clip_contents = true
		_style_button(b, ANSWER_COLORS[i], false)
		b.pressed.connect(_answer.bind(i))
		grid.add_child(b)
		var h := HBoxContainer.new()
		h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		h.offset_left = 18
		h.offset_right = -16
		h.add_theme_constant_override(&"separation", 14)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(h)
		var icon := ShapeIcon.new(ANSWER_SHAPES[i], Palette.CREAM)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(icon)
		var t := Label.new()
		t.add_theme_font_size_override(&"font_size", 32)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		t.max_lines_visible = 2
		t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(t)
		var voters := HBoxContainer.new()
		voters.mouse_filter = Control.MOUSE_FILTER_IGNORE
		voters.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		voters.add_theme_constant_override(&"separation", 4)
		h.add_child(voters)
		var key := Label.new()
		key.add_theme_font_size_override(&"font_size", 22)
		key.text = "%d / %s" % [i + 1, PAD_NAMES[i]]
		key.add_theme_color_override(&"font_color", Palette.CREAM.darkened(0.15))
		key.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(key)
		answer_buttons.append(b)
		answer_texts.append(t)
		answer_voters.append(voters)
	# Scoreboard, right (below the card's height, above the answers).
	var sb_panel := PanelContainer.new()
	sb_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	sb_panel.anchor_left = 1.0
	sb_panel.anchor_right = 1.0
	sb_panel.offset_left = -400
	sb_panel.offset_right = -20
	sb_panel.offset_top = 250
	root.add_child(sb_panel)
	var sbv := VBoxContainer.new()
	sbv.add_theme_constant_override(&"separation", 4)
	sb_panel.add_child(sbv)
	var sbt := Label.new()
	sbt.theme_type_variation = &"HeadingLabel"
	sbt.text = "SCORES"
	sbv.add_child(sbt)
	scoreboard = VBoxContainer.new()
	scoreboard.add_theme_constant_override(&"separation", 2)
	sbv.add_child(scoreboard)
	# Banners, top centre (only while the question card is hidden).
	banner = Label.new()
	banner.theme_type_variation = &"TitleLabel"
	banner.add_theme_font_size_override(&"font_size", 76)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner.anchor_left = 0.5
	banner.anchor_right = 0.5
	banner.offset_left = -760
	banner.offset_right = 760
	banner.offset_top = 14
	banner.offset_bottom = 110
	banner.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	banner.add_theme_color_override(&"font_outline_color", Palette.CASINO_BLACK)
	banner.add_theme_constant_override(&"outline_size", 14)
	root.add_child(banner)
	sub_banner = Label.new()
	sub_banner.theme_type_variation = &"HeadingLabel"
	sub_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	sub_banner.anchor_left = 0.5
	sub_banner.anchor_right = 0.5
	sub_banner.offset_left = -640
	sub_banner.offset_right = 640
	sub_banner.offset_top = 104
	sub_banner.offset_bottom = 150
	sub_banner.add_theme_color_override(&"font_color", Palette.CREAM)
	sub_banner.add_theme_color_override(&"font_outline_color", Palette.CASINO_BLACK)
	sub_banner.add_theme_constant_override(&"outline_size", 10)
	root.add_child(sub_banner)
	# Lucky's speech bubble (follows the host on screen).
	bubble = PanelContainer.new()
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Palette.CREAM
	bsb.set_corner_radius_all(18)
	bsb.corner_radius_bottom_right = 2
	bsb.set_border_width_all(3)
	bsb.border_color = Palette.WARM_GOLD
	bsb.content_margin_left = 18
	bsb.content_margin_right = 18
	bsb.content_margin_top = 8
	bsb.content_margin_bottom = 10
	bsb.shadow_color = Color(0, 0, 0, 0.4)
	bsb.shadow_size = 8
	bubble.add_theme_stylebox_override(&"panel", bsb)
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.visible = false
	root.add_child(bubble)
	bubble_label = Label.new()
	bubble_label.add_theme_font_size_override(&"font_size", 28)
	bubble_label.add_theme_color_override(&"font_color", Palette.CASINO_BLACK)
	bubble_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bubble_label.custom_minimum_size = Vector2(290, 0)
	bubble.add_child(bubble_label)
