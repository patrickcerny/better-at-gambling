class_name ResultsStage
extends Node3D
## The results screen (§2.11, art direction "podium results with ragdolls"). A short show: everyone
## below the top three drops in by the podium, then the podium blocks rise and the beans fall onto
## them in order (3rd, 2nd, 1st), the winner floppily celebrates under confetti, last place slumps
## under a little rain cloud. Standings (left) and the money-over-time graph (right) slide in, the
## fun awards pop up one by one, then Play again / Leave. Online, the party leader takes the room
## back to the lobby (or it goes back by itself after a minute); in Practice, Play again starts a
## fresh match.

signal play_again_pressed
signal leave_pressed

const ORIGIN: Vector3 = Vector3(0, 0, -400)
const PODIUM_HEIGHTS: Array[float] = [1.3, 0.85, 0.5]
const PODIUM_X: Array[float] = [0.0, -2.0, 2.0]
const PODIUM_COLORS: Array[Color] = [Palette.VIP_GOLD, Color("#C9CED6"), Color("#C07A45")]
## Show timeline (seconds after the screen opens).
const T_FLOOR: float = 0.3
const T_PLACE: Array[float] = [3.6, 1.9, 0.9]  # 1st, 2nd, 3rd
## Patrick's announcer ("the wait is over", ~1.5 s) builds up to the 1st-place reveal.
const T_ANNOUNCE: float = 2.0
const T_AWARDS: float = 4.6
const AWARD_GAP: float = 0.4

var state: ClientMatchState
var local_id: int = -1
var camera: Camera3D
var ui: CanvasLayer
var play_button: Button
var leave_button: Button
var wait_label: Label
var beans: Dictionary[int, AvatarVisuals] = {}
var puppets: Dictionary[int, BeanPuppet] = {}
## Standing height of each bean (the podium top or the floor).
var bean_y: Dictionary[int, float] = {}
var graph: MoneyGraph
var standings_panel: Control
var graph_panel: Control
var award_cards: Array[Control] = []
## [{at: float, fn: Callable}] still to run, by time.
var _cues: Array[Dictionary] = []
var _clock: float = 0.0
var _room: bool = false
var _key_light: SpotLight3D
var _cam_from: Vector3 = Vector3(0, 3.9, 12.0)
var _cam_to: Vector3 = Vector3(0, 3.2, 9.0)


func setup(p_state: ClientMatchState, p_local_id: int, room: bool) -> void:
	state = p_state
	local_id = p_local_id
	_room = room
	position = ORIGIN
	_build_set()
	ui = CanvasLayer.new()
	ui.layer = 6
	add_child(ui)
	_build_ui()
	camera.make_current()
	Audio.play(&"whoosh", &"SFX", -6.0)


func _process(delta: float) -> void:
	_clock += delta
	while not _cues.is_empty() and _clock >= float(_cues[0]["at"]):
		var cue: Dictionary = _cues.pop_front()
		(cue["fn"] as Callable).call()
	# A slow dolly in while the podium fills.
	var k: float = clampf(_clock / 3.6, 0.0, 1.0)
	k = 1.0 - pow(1.0 - k, 3.0)
	camera.position = _cam_from.lerp(_cam_to, k)
	camera.look_at(global_position + Vector3(0, 2.0, 0))
	if _room and wait_label != null:
		var leader: bool = state.leader == local_id
		play_button.visible = leader
		var secs: int = ceili(maxf(state.results_return_in, 0.0))
		wait_label.text = ("Back to the lobby in %ds" % secs) if leader else ("Waiting for the party leader… back to the lobby in %ds" % secs)


## Runs `fn` `at` seconds into the show.
func _cue(at: float, fn: Callable) -> void:
	_cues.append({"at": at, "fn": fn})
	_cues.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["at"]) < float(b["at"]))


## Skips the show to its end state (late joiners, tests).
func finish_show() -> void:
	_clock = maxf(_clock, T_AWARDS + AWARD_GAP * award_cards.size() + 0.1)
	while not _cues.is_empty():
		var cue: Dictionary = _cues.pop_front()
		(cue["fn"] as Callable).call()


func _rank_of(pid: int) -> int:
	for row: Variant in state.standings:
		if int(row["player"]) == pid:
			return int(row["rank"])
	return 99


func _color_of(pid: int) -> Color:
	return Palette.player_color(int(state.players.get(pid, {}).get("color", pid - 1)))


func _build_set() -> void:
	var floor_mesh := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(24, 0.2, 16)
	floor_mesh.mesh = fm
	floor_mesh.position = Vector3(0, -0.1, 0)
	floor_mesh.material_override = _mat(Palette.CASINO_RED.darkened(0.35))
	add_child(floor_mesh)
	var carpet := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(3.2, 0.02, 16)
	carpet.mesh = cm
	carpet.position = Vector3(0, 0.01, 2)
	carpet.material_override = _mat(Palette.CASINO_RED.darkened(0.3))
	add_child(carpet)
	var wall := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(24, 9, 0.3)
	wall.mesh = wm
	wall.position = Vector3(0, 4.5, -4)
	wall.material_override = _mat(Palette.WARM_CHARCOAL)
	add_child(wall)
	for x: float in [-6.5, 6.5]:
		var curtain := MeshInstance3D.new()
		var cbm := BoxMesh.new()
		cbm.size = Vector3(2.4, 8.5, 0.2)
		curtain.mesh = cbm
		curtain.position = Vector3(x, 4.25, -3.7)
		curtain.material_override = _mat(Palette.VIP_BURGUNDY)
		add_child(curtain)
	var title := Label3D.new()
	title.text = "BETTER AT GAMBLING"
	title.font_size = 110
	title.pixel_size = 0.008
	title.outline_size = 14
	title.modulate = Palette.VIP_GOLD
	title.position = Vector3(0, 6.15, -3.8)  # clear of the name tags over a tied top step
	add_child(title)
	var standings: Array = state.standings
	var on_floor: int = 0
	var last_rank: int = int(standings[-1]["rank"]) if not standings.is_empty() else 0
	for row: Variant in standings:
		var pid: int = int(row["player"])
		var rank: int = int(row["rank"])
		var place: int = rank - 1 if rank <= 3 else -1
		var base: Vector3
		var at: float
		if place >= 0:
			var h: float = PODIUM_HEIGHTS[place]
			var x: float = PODIUM_X[place]
			# Shared places stand side by side on the same block.
			var sharing: int = standings.filter(func(r: Variant) -> bool: return int(r["rank"]) == rank).size()
			var nth: int = standings.filter(func(r: Variant) -> bool: return int(r["rank"]) == rank and int(r["player"]) < pid).size()
			if nth == 0:
				_build_block(place, x, h, rank, sharing)
			base = Vector3(x + (nth - (sharing - 1) * 0.5) * 0.95, h, 0)
			at = T_PLACE[place] + 0.35 + nth * 0.15
		else:
			# Everyone else cheers from the floor beside the podium, alternating sides.
			var side: float = -1.0 if on_floor % 2 == 0 else 1.0
			base = Vector3(side * (3.7 + floorf(on_floor / 2.0) * 1.3), 0, 0.6)
			at = T_FLOOR + on_floor * 0.15
			on_floor += 1
		var bean := AvatarVisuals.new()
		bean.position = base
		bean.visible = false
		add_child(bean)
		bean.set_color(_color_of(pid))
		bean.set_skin(StringName(state.players.get(pid, {}).get("skin", "bean")))
		bean.rotation.y = PI  # face the camera
		beans[pid] = bean
		bean_y[pid] = base.y
		var puppet: BeanPuppet = BeanPuppet.attach(bean)
		puppets[pid] = puppet
		var tag := Label3D.new()
		tag.text = "%s\n$%s" % [str(row["name"]), Hud._thousands(int(row["money"]))]
		tag.font_size = 40
		tag.pixel_size = 0.006
		tag.outline_size = 8
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.modulate = Palette.VIP_GOLD if pid == local_id else Palette.CREAM
		# Neighbours sharing a block get staggered tags so names never overlap.
		var nth_tag: int = 0 if place < 0 else standings.filter(func(r: Variant) -> bool: return int(r["rank"]) == rank and int(r["player"]) < pid).size()
		var is_last: bool = rank == last_rank and standings.size() > 2 and rank > 1
		# Last place's tag sits higher: the rain cloud floats between it and the bean.
		tag.position = base + Vector3(0, 2.5 + (nth_tag % 2) * 0.55 + (0.5 if is_last else 0.0), 0)
		tag.visible = false
		add_child(tag)
		_cue(at, _land.bind(pid, tag, rank, is_last))
	_build_lights()
	camera = Camera3D.new()
	camera.fov = 52.0
	camera.far = 90.0  # the casino is 400 m away: keep its always-on-top labels out of shot
	add_child(camera)
	camera.position = _cam_from
	camera.look_at(global_position + Vector3(0, 2.0, 0))


## A podium block that rises out of the floor at its place's cue.
func _build_block(place: int, x: float, h: float, rank: int, sharing: int) -> void:
	var w: float = maxf(1.8, sharing * 0.95 + 0.3)
	var pivot := Node3D.new()
	pivot.position = Vector3(x, 0, 0)
	pivot.scale = Vector3(1, 0.02, 1)
	add_child(pivot)
	var block := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, h, 1.4)
	block.mesh = bm
	block.position = Vector3(0, h * 0.5, 0)
	block.material_override = _mat(PODIUM_COLORS[place], 0.6)
	pivot.add_child(block)
	var trim := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(w + 0.1, 0.06, 1.5)
	trim.mesh = tm
	trim.position = Vector3(0, h, 0)
	trim.material_override = _mat(Palette.WARM_GOLD, 0.8)
	pivot.add_child(trim)
	var num := Label3D.new()
	num.text = str(rank)
	num.font_size = 120
	num.pixel_size = 0.006
	num.outline_size = 10
	num.modulate = Palette.CASINO_BLACK if place == 0 else Palette.CREAM
	num.outline_modulate = Palette.CREAM if place == 0 else Palette.CASINO_BLACK
	num.position = Vector3(0, h * 0.5, 0.72)
	pivot.add_child(num)
	_cue(T_PLACE[place], func() -> void:
		Audio.play(&"whoosh", &"SFX", -6.0, 0.8 + place * 0.1)
		if DisplayServer.get_name() == "headless":
			pivot.scale = Vector3.ONE
			return
		var t: Tween = pivot.create_tween()
		t.tween_property(pivot, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))


## A bean drops onto its spot; 1st celebrates, last sulks.
func _land(pid: int, tag: Label3D, rank: int, is_last: bool) -> void:
	var bean: AvatarVisuals = beans[pid]
	var puppet: BeanPuppet = puppets[pid]
	bean.visible = true
	puppet.drop_in(3.5 if rank <= 3 else 2.5)
	Audio.play(&"thud", &"SFX", -6.0)
	tag.visible = true
	_pop3d(tag)
	if rank == 1:
		puppet.set_mood(BeanPuppet.Mood.CHEER)
		ConfettiBurst.burst(self, Vector3(bean.position.x, bean_y[pid] + 2.0, bean.position.z), 160, 1.3)
		Audio.play(&"big_win", &"SFX", -4.0)
		if _key_light != null:
			_key_light.light_energy = 6.0
			_key_light.create_tween().tween_property(_key_light, "light_energy", 3.5, 1.2)
		_cue(_clock + 0.6, func() -> void: ConfettiBurst.rain(self, Vector3(0, 8.0, 0.5), Vector3(14, 0.2, 4), 90))
	elif is_last:
		puppet.set_mood(BeanPuppet.Mood.SAD)
		_cue(_clock + 0.8, _rain_cloud.bind(bean_y[pid], bean.position))
		Audio.play(&"loss_sting", &"SFX", -10.0)
	elif rank <= 3:
		puppet.hop(0.3)


## A small grey cloud drizzling on last place.
func _rain_cloud(y: float, at: Vector3) -> void:
	var cloud := Node3D.new()
	cloud.position = Vector3(at.x, y + 2.25, at.z)
	add_child(cloud)
	var grey: StandardMaterial3D = _mat(Color("#6B6560"))
	for p: Vector3 in [Vector3(-0.32, 0, 0), Vector3(0.0, 0.14, 0), Vector3(0.34, 0.02, 0), Vector3(0.12, -0.08, 0.15)]:
		var puff := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.32
		sm.height = 0.5
		puff.mesh = sm
		puff.position = p
		puff.material_override = grey
		cloud.add_child(puff)
	if DisplayServer.get_name() == "headless":
		return
	var drops := CPUParticles3D.new()
	drops.amount = 16
	drops.lifetime = 0.3
	drops.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	drops.emission_box_extents = Vector3(0.45, 0.05, 0.2)
	drops.direction = Vector3.DOWN
	drops.spread = 0.0
	drops.gravity = Vector3(0, -9.0, 0)
	drops.initial_velocity_min = 1.0
	drops.initial_velocity_max = 1.5
	var qm := QuadMesh.new()
	qm.size = Vector2(0.025, 0.14)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.albedo_color = Color("#9DB7C9")
	qm.material = m
	drops.mesh = qm
	drops.position = Vector3(0, -0.25, 0)
	cloud.add_child(drops)
	cloud.scale = Vector3.ONE * 0.1
	cloud.create_tween().tween_property(cloud, "scale", Vector3.ONE * 0.8, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _build_lights() -> void:
	_key_light = SpotLight3D.new()
	_key_light.position = Vector3(0, 9, 5)
	_key_light.rotation_degrees = Vector3(-55, 0, 0)
	_key_light.spot_range = 22.0
	_key_light.spot_angle = 45.0
	_key_light.light_energy = 3.5
	_key_light.light_color = Color("#FFE2B0")
	_key_light.shadow_enabled = true
	add_child(_key_light)
	var fill := OmniLight3D.new()
	fill.position = Vector3(0, 4, 4)
	fill.omni_range = 14.0
	fill.light_energy = 0.8
	fill.light_color = Palette.VIP_GOLD
	add_child(fill)


func _pop3d(n: Node3D) -> void:
	if DisplayServer.get_name() == "headless":
		return
	n.scale = Vector3.ONE * 0.3
	n.create_tween().tween_property(n, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = load("res://ui/theme/main_theme.tres") as Theme
	ui.add_child(root)
	# Standings, top left.
	var panel := PanelContainer.new()
	panel.position = Vector2(28, 28)
	panel.custom_minimum_size = Vector2(440, 0)
	root.add_child(panel)
	standings_panel = panel
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 4)
	panel.add_child(v)
	var t := Label.new()
	t.theme_type_variation = &"TitleLabel"
	t.add_theme_font_size_override(&"font_size", 56)
	t.text = "RESULTS"
	v.add_child(t)
	for row: Variant in state.standings:
		var h := HBoxContainer.new()
		h.add_theme_constant_override(&"separation", 12)
		var r := Label.new()
		r.text = Hud._ordinal(int(row["rank"]))
		r.custom_minimum_size = Vector2(56, 0)
		r.add_theme_font_size_override(&"font_size", 30)
		h.add_child(r)
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(18, 18)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.color = _color_of(int(row["player"]))
		h.add_child(dot)
		var n := Label.new()
		n.text = str(row["name"])
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		n.clip_text = true
		n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		n.add_theme_font_size_override(&"font_size", 30)
		h.add_child(n)
		var m := Label.new()
		m.add_theme_font_size_override(&"font_size", 34)
		m.text = "$%s" % Hud._thousands(int(row["money"]))
		m.add_theme_color_override(&"font_color", Palette.MONEY_GREEN if int(row["rank"]) == 1 else Palette.CREAM)
		h.add_child(m)
		if int(row["player"]) == local_id:
			n.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
			r.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
		v.add_child(h)
	_slide_in(panel, Vector2(-500, 0), 0.4)
	# Money over time, top right.
	var colors: Dictionary = {}
	for row: Variant in state.standings:
		colors[int(row["player"])] = _color_of(int(row["player"]))
	var gp := PanelContainer.new()
	gp.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	gp.anchor_left = 1.0
	gp.anchor_right = 1.0
	gp.offset_left = -620
	gp.offset_right = -28
	gp.offset_top = 28
	root.add_child(gp)
	graph_panel = gp
	var gv := VBoxContainer.new()
	gp.add_child(gv)
	var gt := Label.new()
	gt.theme_type_variation = &"HeadingLabel"
	gt.text = "MONEY OVER TIME"
	gv.add_child(gt)
	graph = MoneyGraph.new()
	graph.custom_minimum_size = Vector2(560, 280)
	graph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gv.add_child(graph)
	var start: int = 0
	if not state.standings.is_empty():
		var s0: Array = (state.standings[0] as Dictionary).get("series", [])
		start = int(s0[0]) if not s0.is_empty() else 0
	graph.setup(state.standings, colors, local_id, state.duration_minutes * 60.0, start)
	gp.visible = graph.has_data()
	graph.set_process(false)
	_cue(1.0, func() -> void: graph.set_process(true))
	_cue(T_ANNOUNCE, func() -> void: Audio.play(&"announcer_results", &"UI", -2.0))
	_slide_in(gp, Vector2(660, 0), 0.6)
	# Awards, bottom.
	var awards := HBoxContainer.new()
	awards.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	awards.anchor_left = 0.5
	awards.anchor_right = 0.5
	awards.anchor_top = 1.0
	awards.anchor_bottom = 1.0
	awards.offset_left = -900
	awards.offset_right = 900
	awards.offset_top = -268
	awards.offset_bottom = -128
	awards.alignment = BoxContainer.ALIGNMENT_CENTER
	awards.add_theme_constant_override(&"separation", 16)
	root.add_child(awards)
	var i: int = 0
	for a: Variant in state.awards:
		var card: Control = _award_card(a as Dictionary)
		awards.add_child(card)
		award_cards.append(card)
		card.modulate.a = 0.0
		_cue(T_AWARDS + i * AWARD_GAP, _show_award.bind(card))
		i += 1
	# Buttons, bottom.
	var buttons := HBoxContainer.new()
	buttons.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	buttons.anchor_left = 0.5
	buttons.anchor_right = 0.5
	buttons.anchor_top = 1.0
	buttons.anchor_bottom = 1.0
	buttons.offset_left = -500
	buttons.offset_right = 500
	buttons.offset_top = -110
	buttons.offset_bottom = -40
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override(&"separation", 24)
	root.add_child(buttons)
	play_button = Button.new()
	play_button.text = "PLAY AGAIN" if not _room else "PLAY AGAIN (BACK TO LOBBY)"
	play_button.pressed.connect(func() -> void: play_again_pressed.emit())
	buttons.add_child(play_button)
	leave_button = Button.new()
	leave_button.text = "MAIN MENU" if not _room else "LEAVE PARTY"
	leave_button.pressed.connect(func() -> void: leave_pressed.emit())
	buttons.add_child(leave_button)
	if _room:
		wait_label = Label.new()
		wait_label.theme_type_variation = &"SmallLabel"
		wait_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		wait_label.anchor_left = 0.5
		wait_label.anchor_right = 0.5
		wait_label.anchor_top = 1.0
		wait_label.anchor_bottom = 1.0
		wait_label.offset_left = -500
		wait_label.offset_right = 500
		wait_label.offset_top = -36
		wait_label.offset_bottom = -8
		wait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		root.add_child(wait_label)
	play_button.grab_focus()


func _award_card(a: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(330, 128)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.WARM_CHARCOAL
	sb.set_corner_radius_all(14)
	sb.set_border_width_all(3)
	sb.border_width_top = 8
	sb.border_color = Palette.WARM_GOLD
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 12
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = 8
	card.add_theme_stylebox_override(&"panel", sb)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override(&"separation", 2)
	card.add_child(cv)
	var at := Label.new()
	at.theme_type_variation = &"HeadingLabel"
	at.text = str(a["title"]).to_upper()
	at.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	cv.add_child(at)
	var who := HBoxContainer.new()
	who.add_theme_constant_override(&"separation", 8)
	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(16, 16)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.color = _color_of(int(a.get("player", 0)))
	who.add_child(dot)
	var an := Label.new()
	an.text = str(a["name"])
	an.add_theme_font_size_override(&"font_size", 30)
	if int(a.get("player", -1)) == local_id:
		an.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	who.add_child(an)
	cv.add_child(who)
	var ad := Label.new()
	ad.text = str(a["text"])
	ad.add_theme_font_size_override(&"font_size", 22)
	ad.add_theme_color_override(&"font_color", Palette.CREAM.darkened(0.15))
	cv.add_child(ad)
	return card


func _show_award(card: Control) -> void:
	card.modulate.a = 1.0
	Audio.play(&"chip_clack", &"SFX", -6.0, 1.1)
	if DisplayServer.get_name() == "headless":
		return
	card.pivot_offset = card.size * 0.5
	card.scale = Vector2(0.6, 0.6)
	card.create_tween().tween_property(card, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Slides a panel in from `offset` at `at` seconds.
func _slide_in(c: Control, offset: Vector2, at: float) -> void:
	c.modulate.a = 0.0
	_cue(at, func() -> void:
		c.modulate.a = 1.0
		if DisplayServer.get_name() == "headless":
			return
		var target: Vector2 = c.position
		c.position = target + offset
		c.create_tween().tween_property(c, "position", target, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT))


func _mat(c: Color, metallic: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metallic
	m.roughness = 0.4 if metallic > 0.0 else 0.8
	return m
