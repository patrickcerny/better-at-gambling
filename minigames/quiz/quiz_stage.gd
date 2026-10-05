class_name QuizStage
extends MinigameStage
## The Casino Quiz set (§2.9): a game-show stage with one coloured podium per player, Lucky the
## dealer cat as host, a big screen, and the answer UI. Keys 1-4, mouse, or gamepad A/B/X/Y.

const ANSWER_COLORS: Array[Color] = [Palette.CASINO_RED, Palette.FELT_GREEN, Palette.WARM_GOLD, Color("#3E5C8A")]
const ANSWER_SHAPES: Array[ShapeIcon.Shape] = [ShapeIcon.Shape.TRIANGLE, ShapeIcon.Shape.CIRCLE, ShapeIcon.Shape.SQUARE, ShapeIcon.Shape.DIAMOND]
const PAD_BUTTONS: Array[JoyButton] = [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y]
const PAD_NAMES: Array[String] = ["A", "B", "X", "Y"]
const CATEGORY_NAMES: Dictionary = {
	"casino_trivia": "Casino trivia", "cards_and_dice": "Cards & dice", "luck_and_superstition": "Luck & superstition",
	"game_rules": "House rules", "silly": "Silly",
}

## player → {podium: Node3D, bean: AvatarVisuals, score: Label3D, mark: Label3D}
var podiums: Dictionary[int, Dictionary] = {}
var host: Node3D
var host_bubble: Label3D
var screen_label: Label3D

var card: PanelContainer
var header: Label
var question_label: Label
var timer_bar: ProgressBar
var answer_buttons: Array[Button] = []
var answer_texts: Array[Label] = []
var answer_voters: Array[HBoxContainer] = []
var banner: Label
var sub_banner: Label
var explanation: Label
var scoreboard: VBoxContainer
var answered_row: HBoxContainer

var index: int = -1
var count: int = 3
var answer_time: float = 12.0
var time_left: float = 0.0
var answering: bool = false
var my_answer: int = -1
var totals: Dictionary = {}
var players: Array[int] = []
var _clock: float = 0.0
var _last_tick: int = -1


func _build(start: Dictionary) -> void:
	for p: Variant in start.get("players", []):
		players.append(int(p))
	_build_set()
	_build_ui()
	_show_banner("CASINO QUIZ", "3 questions · answer fast · no changing answers")
	_host_say("Welcome to the show!")
	_refresh_scoreboard()


func _process(delta: float) -> void:
	_clock += delta
	if answering:
		time_left = maxf(time_left - delta, 0.0)
		timer_bar.value = time_left / answer_time * 100.0
		var t: int = ceili(time_left)
		if t <= 3 and t != _last_tick and t > 0:
			_last_tick = t
			Audio.play(&"countdown_beep", &"UI", -10.0, 1.2)
	if host != null:
		host.rotation.y = sin(_clock * 1.3) * 0.15
		host.position.y = absf(sin(_clock * 2.6)) * 0.05


# --- Events ------------------------------------------------------------------------------------

func on_event(ev: Dictionary) -> void:
	match ev["type"]:
		&"quiz_started":
			count = int(ev.get("questions", 3))
			answer_time = float(ev.get("answer_time", 12.0))
		&"quiz_get_ready":
			index = int(ev["index"])
			_clear_question()
			_show_banner("QUESTION %d / %d" % [index + 1, count], "Get ready…")
			_host_say("Last one! Make it count." if index == count - 1 else ["Here comes one!", "Ooh, I like this one."][mini(index, 1)])
			Audio.play(&"whoosh", &"UI", -8.0)
		&"quiz_question":
			_show_question(ev)
		&"quiz_answered":
			var pid: int = int(ev["player"])
			_mark_answered(pid)
		&"quiz_reveal":
			_reveal(ev)
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
		_reveal(st["reveal"])
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
	sub_banner.text = "Locked in!"


# --- Presentation ------------------------------------------------------------------------------

func _show_question(q: Dictionary) -> void:
	index = int(q.get("index", index))
	count = int(q.get("count", count))
	banner.visible = false
	my_answer = -1
	_last_tick = -1
	header.text = "QUESTION %d / %d  ·  %s%s" % [index + 1, count, CATEGORY_NAMES.get(str(q.get("category", "")), "Quiz").to_upper(), "  ·  LIVE" if bool(q.get("dynamic", false)) else ""]
	question_label.text = str(q["question"])
	# The question itself is on the card at the top; the big screen only shows the number, so
	# the same sentence isn't printed twice.
	screen_label.text = "QUESTION %d" % (index + 1)
	var answers: Array = q["answers"]
	for i: int in answer_buttons.size():
		answer_texts[i].text = str(answers[i]) if i < answers.size() else ""
		answer_buttons[i].disabled = not local_id in players
		answer_buttons[i].modulate = Color.WHITE
		_style_button(answer_buttons[i], ANSWER_COLORS[i], false)
		for c: Node in answer_voters[i].get_children():
			c.queue_free()
	for pid: int in podiums:
		(podiums[pid]["mark"] as Label3D).text = ""
	for c: Node in answered_row.get_children():
		c.queue_free()
	card.visible = true
	for b: Button in answer_buttons:
		b.visible = true
	explanation.visible = false
	time_left = float(q.get("seconds", answer_time))
	answering = true
	timer_bar.visible = true
	sub_banner.text = "" if local_id in players else "Watching: you were away when the quiz started"
	sub_banner.visible = sub_banner.text != ""
	_host_say("Tick tock!")
	Audio.play(&"card_flip", &"UI", -6.0)


func _clear_question() -> void:
	answering = false
	my_answer = -1
	card.visible = false
	for b: Button in answer_buttons:
		b.visible = false
	timer_bar.visible = false
	explanation.visible = false
	screen_label.text = "?"


func _mark_answered(pid: int) -> void:
	if podiums.has(pid):
		(podiums[pid]["mark"] as Label3D).text = "!"
		(podiums[pid]["bean"] as AvatarVisuals).react(&"win")
	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(18, 18)
	dot.color = _player_color(pid)
	dot.tooltip_text = state.player_name(pid)
	answered_row.add_child(dot)


func _reveal(ev: Dictionary) -> void:
	answering = false
	timer_bar.visible = false
	var correct: int = int(ev["correct_index"])
	var chosen: Dictionary = _int_keys(ev.get("answers", {}))
	var gained: Dictionary = _int_keys(ev.get("points", {}))
	_set_totals(ev.get("totals", totals))
	for i: int in answer_buttons.size():
		answer_buttons[i].disabled = true
		var right: bool = i == correct
		_style_button(answer_buttons[i], Palette.MONEY_GREEN if right else Palette.WARM_CHARCOAL, right)
		answer_buttons[i].modulate = Color.WHITE if right or i == my_answer else Color(1, 1, 1, 0.5)
	for pid: Variant in chosen:
		var choice: int = int(chosen[pid])
		if choice >= 0 and choice < answer_voters.size():
			var dot := ColorRect.new()
			dot.custom_minimum_size = Vector2(16, 16)
			dot.color = _player_color(int(pid))
			answer_voters[choice].add_child(dot)
	for pid: int in podiums:
		var pts: int = int(gained.get(pid, 0))
		var mark: Label3D = podiums[pid]["mark"]
		mark.text = ("+%d" % pts) if pts > 0 else ("X" if chosen.has(pid) else "-")
		mark.modulate = Palette.MONEY_GREEN if pts > 0 else Palette.LOSS_RED
		(podiums[pid]["bean"] as AvatarVisuals).react(&"win" if pts > 0 else &"loss")
	var mine: int = int(gained.get(local_id, 0))
	if local_id in players:
		sub_banner.visible = true
		sub_banner.text = ("Correct! +%d" % mine) if mine > 0 else ("Wrong!" if my_answer >= 0 else "Too slow!")
		Audio.play(&"coin" if mine > 0 else &"buzzer", &"UI", -4.0)
	var text: String = str(ev.get("explanation", ""))
	explanation.text = text
	explanation.visible = text != ""
	_host_say("Correct answer: %s!" % answer_texts[correct].text if correct < answer_texts.size() else "")
	_refresh_scoreboard()


func _finish(ranking: Array) -> void:
	answering = false
	card.visible = false
	for b: Button in answer_buttons:
		b.visible = false
	explanation.visible = false
	timer_bar.visible = false
	for c: Node in answered_row.get_children():
		c.queue_free()
	if ranking.is_empty():
		return
	var top: Dictionary = ranking[0]
	var winners: Array[String] = []
	for row: Variant in ranking:
		if int(row["rank"]) == 1:
			winners.append(state.player_name(int(row["player"])))
	screen_label.text = ""
	_show_banner("%s WIN%s THE QUIZ!" % [" & ".join(winners).to_upper(), "" if winners.size() > 1 else "S"], "%d points" % int(top["points"]))
	for row: Variant in ranking:
		var pid: int = int(row["player"])
		totals[pid] = int(row["points"])
		if podiums.has(pid):
			var bean: AvatarVisuals = podiums[pid]["bean"]
			bean.react(&"win" if int(row["rank"]) == 1 else &"loss" if int(row["rank"]) == int(ranking[-1]["rank"]) else &"idle")
			(podiums[pid]["mark"] as Label3D).text = Hud._ordinal(int(row["rank"]))
			(podiums[pid]["mark"] as Label3D).modulate = Palette.VIP_GOLD
	_host_say("What a show!")
	Audio.play(&"big_win", &"UI", -6.0)
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
		c.queue_free()
	var rows: Array = players.duplicate()
	rows.sort_custom(func(a: int, b: int) -> bool: return _total(a) > _total(b))
	for pid: int in rows:
		var h := HBoxContainer.new()
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(14, 14)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.color = _player_color(pid)
		h.add_child(dot)
		var n := Label.new()
		n.text = state.player_name(pid)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		n.clip_text = true
		if pid == local_id:
			n.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
		h.add_child(n)
		var pts := Label.new()
		pts.text = str(_total(pid))
		h.add_child(pts)
		scoreboard.add_child(h)
	for pid: int in podiums:
		(podiums[pid]["score"] as Label3D).text = str(_total(pid))


func _show_banner(title: String, sub: String) -> void:
	banner.text = title
	banner.visible = true
	sub_banner.text = sub
	sub_banner.visible = sub != ""
	banner.scale = Vector2(0.8, 0.8)
	banner.pivot_offset = banner.size * 0.5
	create_tween().tween_property(banner, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _host_say(text: String) -> void:
	if host_bubble != null:
		host_bubble.text = text


func _player_color(pid: int) -> Color:
	return Palette.player_color(int(state.players.get(pid, {}).get("color", pid - 1)))


func _style_button(b: Button, color: Color, outline: bool) -> void:
	for st: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = color.lightened(0.12) if st == "hover" else color
		sb.set_corner_radius_all(10)
		sb.content_margin_left = 16
		sb.content_margin_right = 16
		sb.content_margin_top = 10
		sb.content_margin_bottom = 10
		if outline or st == "focus":
			sb.set_border_width_all(4)
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
	# Big screen with a gold frame.
	var frame := MeshInstance3D.new()
	var frm := BoxMesh.new()
	frm.size = Vector3(9.2, 3.6, 0.15)
	frame.mesh = frm
	frame.position = Vector3(0, 5.2, -4.25)
	frame.material_override = _mat(Palette.WARM_GOLD, 0.8)
	add_child(frame)
	var screen := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(8.8, 3.2, 0.1)
	screen.mesh = sm
	screen.position = Vector3(0, 5.2, -4.15)
	screen.material_override = _mat(Palette.FELT_GREEN.darkened(0.5))
	add_child(screen)
	screen_label = Label3D.new()
	screen_label.text = ""  # the intro banner already says CASINO QUIZ
	screen_label.font_size = 96
	screen_label.pixel_size = 0.006
	screen_label.width = 1300
	screen_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	screen_label.modulate = Palette.CREAM
	screen_label.position = Vector3(0, 5.2, -4.05)
	add_child(screen_label)
	var title := Label3D.new()
	title.text = "CASINO QUIZ"
	title.font_size = 96
	title.pixel_size = 0.008
	title.modulate = Palette.VIP_GOLD
	title.outline_size = 12
	title.position = Vector3(0, 7.6, -4.2)
	add_child(title)
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
		bean.set_hat(StringName(state.players.get(pid, {}).get("hat", "none")))
		var name_l := Label3D.new()
		name_l.text = state.player_name(pid)
		name_l.font_size = 40
		name_l.pixel_size = 0.006
		name_l.outline_size = 8
		name_l.position = Vector3(0, 0.55, 0.52)
		root.add_child(name_l)
		var score := Label3D.new()
		score.text = "0"
		score.font_size = 56
		score.pixel_size = 0.006
		score.outline_size = 10
		score.modulate = Palette.CREAM
		score.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		score.position = Vector3(0, 2.85, -0.15)
		root.add_child(score)
		var mark := Label3D.new()
		mark.text = ""
		mark.font_size = 60
		mark.pixel_size = 0.006
		mark.outline_size = 12
		mark.modulate = Palette.VIP_GOLD
		mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		mark.position = Vector3(0, 3.2, -0.15)
		root.add_child(mark)
		podiums[pid] = {"podium": root, "bean": bean, "score": score, "mark": mark}
	host = _build_host()
	host.position = Vector3(-7.3, 0, -1.6)
	add_child(host)
	host_bubble = Label3D.new()
	host_bubble.font_size = 40
	host_bubble.pixel_size = 0.006
	host_bubble.outline_size = 8
	host_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	host_bubble.modulate = Palette.CREAM
	host_bubble.position = Vector3(-7.3, 2.6, -1.6)
	add_child(host_bubble)
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
	add_child(camera)
	camera.position = Vector3(0, 3.6, 10.5)
	camera.look_at(global_position + Vector3(0, 2.75, -1.0))


## Lucky the dealer cat: a black bean of a cat with yellow eyes and a gold bow tie.
func _build_host() -> Node3D:
	var cat := Node3D.new()
	cat.name = "LuckyTheCat"
	var black: StandardMaterial3D = _mat(Palette.CASINO_BLACK.lightened(0.08))
	var body := MeshInstance3D.new()
	var bm := CapsuleMesh.new()
	bm.radius = 0.45
	bm.height = 1.4
	body.mesh = bm
	body.position = Vector3(0, 0.7, 0)
	body.material_override = black
	cat.add_child(body)
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.42
	hm.height = 0.8
	head.mesh = hm
	head.position = Vector3(0, 1.65, 0)
	head.material_override = black
	cat.add_child(head)
	for sx: float in [-0.22, 0.22]:
		var ear := MeshInstance3D.new()
		var em := PrismMesh.new()
		em.size = Vector3(0.28, 0.32, 0.12)
		ear.mesh = em
		ear.position = Vector3(sx, 2.05, 0)
		ear.material_override = black
		cat.add_child(ear)
		var eye := MeshInstance3D.new()
		var eye_m := SphereMesh.new()
		eye_m.radius = 0.07
		eye_m.height = 0.14
		eye.mesh = eye_m
		eye.position = Vector3(sx * 0.7, 1.72, 0.37)
		eye.material_override = _mat(Color("#F2D04B"), 0.0, true)
		cat.add_child(eye)
	var tie := MeshInstance3D.new()
	var tm := PrismMesh.new()
	tm.size = Vector3(0.4, 0.18, 0.08)
	tie.mesh = tm
	tie.rotation_degrees = Vector3(0, 0, 90)
	tie.position = Vector3(0, 1.28, 0.42)
	tie.material_override = _mat(Palette.WARM_GOLD, 0.8)
	cat.add_child(tie)
	var tail := MeshInstance3D.new()
	var tlm := CapsuleMesh.new()
	tlm.radius = 0.07
	tlm.height = 1.0
	tail.mesh = tlm
	tail.rotation_degrees = Vector3(40, 0, 0)
	tail.position = Vector3(0, 0.6, -0.55)
	tail.material_override = black
	cat.add_child(tail)
	return cat


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
	# Question card, top centre.
	card = PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_CENTER_TOP)
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.offset_left = -560
	card.offset_right = 560
	card.offset_top = 24
	card.visible = false
	root.add_child(card)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override(&"separation", 8)
	card.add_child(cv)
	header = Label.new()
	header.theme_type_variation = &"SmallLabel"
	header.add_theme_color_override(&"font_color", Palette.WARM_GOLD)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(header)
	question_label = Label.new()
	question_label.add_theme_font_size_override(&"font_size", 40)
	question_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	question_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	question_label.custom_minimum_size = Vector2(1060, 0)
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
	explanation = Label.new()
	explanation.theme_type_variation = &"SmallLabel"
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	explanation.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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
	grid.offset_left = -560
	grid.offset_right = 560
	grid.offset_top = -230
	grid.offset_bottom = -24
	grid.add_theme_constant_override(&"h_separation", 16)
	grid.add_theme_constant_override(&"v_separation", 14)
	root.add_child(grid)
	for i: int in 4:
		var b := Button.new()
		b.custom_minimum_size = Vector2(540, 92)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		b.visible = false
		_style_button(b, ANSWER_COLORS[i], false)
		b.pressed.connect(_answer.bind(i))
		grid.add_child(b)
		var h := HBoxContainer.new()
		h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		h.offset_left = 16
		h.offset_right = -16
		h.add_theme_constant_override(&"separation", 14)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(h)
		var icon := ShapeIcon.new(ANSWER_SHAPES[i], Palette.CREAM)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(icon)
		var t := Label.new()
		t.add_theme_font_size_override(&"font_size", 30)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(t)
		var voters := HBoxContainer.new()
		voters.mouse_filter = Control.MOUSE_FILTER_IGNORE
		voters.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(voters)
		var key := Label.new()
		key.theme_type_variation = &"SmallLabel"
		key.text = "%d / %s" % [i + 1, PAD_NAMES[i]]
		key.add_theme_color_override(&"font_color", Palette.CREAM.darkened(0.2))
		key.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(key)
		answer_buttons.append(b)
		answer_texts.append(t)
		answer_voters.append(voters)
	# Scoreboard, right.
	var sb_panel := PanelContainer.new()
	sb_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	sb_panel.anchor_left = 1.0
	sb_panel.anchor_right = 1.0
	sb_panel.offset_left = -300
	sb_panel.offset_right = -24
	sb_panel.offset_top = 260
	root.add_child(sb_panel)
	var sbv := VBoxContainer.new()
	sb_panel.add_child(sbv)
	var sbt := Label.new()
	sbt.theme_type_variation = &"HeadingLabel"
	sbt.text = "SCORES"
	sbv.add_child(sbt)
	scoreboard = VBoxContainer.new()
	sbv.add_child(scoreboard)
	answered_row = HBoxContainer.new()
	answered_row.add_theme_constant_override(&"separation", 6)
	sbv.add_child(answered_row)
	# Banners, centre.
	banner = Label.new()
	banner.theme_type_variation = &"TitleLabel"
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.set_anchors_preset(Control.PRESET_CENTER)
	banner.anchor_left = 0.5
	banner.anchor_right = 0.5
	banner.anchor_top = 0.5
	banner.anchor_bottom = 0.5
	banner.offset_left = -700
	banner.offset_right = 700
	banner.offset_top = -260
	banner.offset_bottom = -160
	banner.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	root.add_child(banner)
	sub_banner = Label.new()
	sub_banner.theme_type_variation = &"HeadingLabel"
	sub_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_banner.set_anchors_preset(Control.PRESET_CENTER)
	sub_banner.anchor_left = 0.5
	sub_banner.anchor_right = 0.5
	sub_banner.anchor_top = 0.5
	sub_banner.anchor_bottom = 0.5
	sub_banner.offset_left = -480
	sub_banner.offset_right = 480
	sub_banner.offset_top = -150
	sub_banner.offset_bottom = -60
	sub_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(sub_banner)
