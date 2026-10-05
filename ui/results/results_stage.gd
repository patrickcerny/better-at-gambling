class_name ResultsStage
extends Node3D
## The results screen (§2.11, art direction "podium results with ragdolls"): the top three on a
## gold/silver/bronze podium, everyone else cheering below, confetti, final money, fun awards and
## Play again / Leave. Online, the party leader takes the room back to the lobby (or it goes back
## by itself after a minute); in Practice, Play again starts a fresh match.

signal play_again_pressed
signal leave_pressed

const ORIGIN: Vector3 = Vector3(0, 0, -400)
const PODIUM_HEIGHTS: Array[float] = [1.3, 0.85, 0.5]
const PODIUM_X: Array[float] = [0.0, -2.0, 2.0]
const PODIUM_COLORS: Array[Color] = [Palette.VIP_GOLD, Color("#C9CED6"), Color("#C07A45")]

var state: ClientMatchState
var local_id: int = -1
var camera: Camera3D
var ui: CanvasLayer
var play_button: Button
var leave_button: Button
var wait_label: Label
var beans: Dictionary[int, AvatarVisuals] = {}
## Standing height of each bean (the podium top or the floor).
var bean_y: Dictionary[int, float] = {}
var _clock: float = 0.0
var _room: bool = false


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
	Audio.play(&"big_win", &"SFX", -4.0)


func _process(delta: float) -> void:
	_clock += delta
	var i: int = 0
	for pid: int in beans:
		var b: AvatarVisuals = beans[pid]
		b.position.y = bean_y.get(pid, 0.0) + (absf(sin(_clock * 4.0 + i)) * 0.25 if _rank_of(pid) == 1 else 0.0)
		i += 1
	if _room and wait_label != null:
		var leader: bool = state.leader == local_id
		play_button.visible = leader
		var secs: int = ceili(maxf(state.results_return_in, 0.0))
		wait_label.text = ("Back to the lobby in %ds" % secs) if leader else ("Waiting for the party leader… back to the lobby in %ds" % secs)


func _rank_of(pid: int) -> int:
	for row: Variant in state.standings:
		if int(row["player"]) == pid:
			return int(row["rank"])
	return 99


func _build_set() -> void:
	var floor_mesh := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(20, 0.2, 14)
	floor_mesh.mesh = fm
	floor_mesh.position = Vector3(0, -0.1, 0)
	floor_mesh.material_override = _mat(Palette.CASINO_RED.darkened(0.35))
	add_child(floor_mesh)
	var wall := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(20, 8, 0.3)
	wall.mesh = wm
	wall.position = Vector3(0, 4, -4)
	wall.material_override = _mat(Palette.WARM_CHARCOAL)
	add_child(wall)
	var title := Label3D.new()
	title.text = "BETTER AT GAMBLING"
	title.font_size = 110
	title.pixel_size = 0.008
	title.outline_size = 14
	title.modulate = Palette.VIP_GOLD
	title.position = Vector3(0, 5.4, -3.8)
	add_child(title)
	var standings: Array = state.standings
	var on_floor: int = 0
	for row: Variant in standings:
		var pid: int = int(row["player"])
		var rank: int = int(row["rank"])
		var place: int = -1
		for k: int in 3:
			if rank == k + 1:
				place = k
		var base: Vector3
		if place >= 0:
			var h: float = PODIUM_HEIGHTS[place]
			var x: float = PODIUM_X[place]
			# Shared places stand side by side on the same block.
			var sharing: int = standings.filter(func(r: Variant) -> bool: return int(r["rank"]) == rank).size()
			var nth: int = standings.filter(func(r: Variant) -> bool: return int(r["rank"]) == rank and int(r["player"]) < pid).size()
			var block := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(1.8, h, 1.4)
			block.mesh = bm
			block.position = Vector3(x, h * 0.5, 0)
			block.material_override = _mat(PODIUM_COLORS[place], 0.6)
			add_child(block)
			var num := Label3D.new()
			num.text = str(rank)
			num.font_size = 120
			num.pixel_size = 0.006
			num.outline_size = 10
			num.position = Vector3(x, h * 0.5, 0.72)
			add_child(num)
			base = Vector3(x + (nth - (sharing - 1) * 0.5) * 0.7, h, 0)
		else:
			# Everyone else cheers from the floor beside the podium, alternating sides.
			var side: float = -1.0 if on_floor % 2 == 0 else 1.0
			base = Vector3(side * (3.7 + floorf(on_floor / 2.0) * 1.1), 0, 0.6)
			on_floor += 1
		var bean := AvatarVisuals.new()
		bean.position = base
		add_child(bean)
		bean.set_color(Palette.player_color(int(state.players.get(pid, {}).get("color", pid - 1))))
		bean.set_hat(StringName(state.players.get(pid, {}).get("hat", "none")))
		bean.rotation.y = PI  # face the camera
		beans[pid] = bean
		bean_y[pid] = base.y
		if rank == 1:
			bean.react(&"win")
		elif row == standings[-1] and standings.size() > 2:
			bean.react(&"loss")
		var tag := Label3D.new()
		tag.text = "%s\n$%s" % [str(row["name"]), Hud._thousands(int(row["money"]))]
		tag.font_size = 40
		tag.pixel_size = 0.006
		tag.outline_size = 8
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.modulate = Palette.VIP_GOLD if pid == local_id else Palette.CREAM
		tag.position = base + Vector3(0, 2.15, 0)
		add_child(tag)
	var confetti := CPUParticles3D.new()
	confetti.amount = 160
	confetti.lifetime = 4.0
	confetti.position = Vector3(0, 7, 0)
	confetti.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	confetti.emission_box_extents = Vector3(7, 0.2, 2)
	confetti.direction = Vector3.DOWN
	confetti.spread = 25.0
	confetti.gravity = Vector3(0, -2.0, 0)
	confetti.initial_velocity_min = 0.5
	confetti.initial_velocity_max = 1.5
	confetti.angular_velocity_min = -180.0
	confetti.angular_velocity_max = 180.0
	var quad := QuadMesh.new()
	quad.size = Vector2(0.08, 0.12)
	var qm := StandardMaterial3D.new()
	qm.vertex_color_use_as_albedo = true
	qm.cull_mode = BaseMaterial3D.CULL_DISABLED
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad.material = qm
	confetti.mesh = quad
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Palette.VIP_GOLD, Palette.CASINO_RED, Palette.MONEY_GREEN, Palette.CREAM])
	grad.offsets = PackedFloat32Array([0.0, 0.33, 0.66, 1.0])
	confetti.color_initial_ramp = grad
	add_child(confetti)
	var key := SpotLight3D.new()
	key.position = Vector3(0, 9, 5)
	key.rotation_degrees = Vector3(-55, 0, 0)
	key.spot_range = 22.0
	key.spot_angle = 45.0
	key.light_energy = 3.5
	key.light_color = Color("#FFE2B0")
	key.shadow_enabled = true
	add_child(key)
	var fill := OmniLight3D.new()
	fill.position = Vector3(0, 4, 4)
	fill.omni_range = 14.0
	fill.light_energy = 0.8
	fill.light_color = Palette.VIP_GOLD
	add_child(fill)
	camera = Camera3D.new()
	camera.fov = 52.0
	add_child(camera)
	camera.position = Vector3(0, 3.2, 9.0)
	camera.look_at(global_position + Vector3(0, 2.0, 0))


func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = load("res://ui/theme/main_theme.tres") as Theme
	ui.add_child(root)
	# Standings, left.
	var panel := PanelContainer.new()
	panel.position = Vector2(28, 28)
	panel.custom_minimum_size = Vector2(420, 0)
	root.add_child(panel)
	var v := VBoxContainer.new()
	panel.add_child(v)
	var t := Label.new()
	t.theme_type_variation = &"TitleLabel"
	t.text = "RESULTS"
	v.add_child(t)
	for row: Variant in state.standings:
		var h := HBoxContainer.new()
		h.add_theme_constant_override(&"separation", 12)
		var r := Label.new()
		r.text = Hud._ordinal(int(row["rank"]))
		r.custom_minimum_size = Vector2(60, 0)
		h.add_child(r)
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(16, 16)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.color = Palette.player_color(int(state.players.get(int(row["player"]), {}).get("color", 0)))
		h.add_child(dot)
		var n := Label.new()
		n.text = str(row["name"])
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		n.clip_text = true
		h.add_child(n)
		var m := Label.new()
		m.theme_type_variation = &"MoneyLabel"
		m.text = "$%s" % Hud._thousands(int(row["money"]))
		h.add_child(m)
		if int(row["player"]) == local_id:
			n.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
			r.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
		v.add_child(h)
	# Awards, bottom.
	var awards := HBoxContainer.new()
	awards.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	awards.anchor_left = 0.5
	awards.anchor_right = 0.5
	awards.anchor_top = 1.0
	awards.anchor_bottom = 1.0
	awards.offset_left = -640
	awards.offset_right = 640
	awards.offset_top = -250
	awards.offset_bottom = -130
	awards.alignment = BoxContainer.ALIGNMENT_CENTER
	awards.add_theme_constant_override(&"separation", 14)
	root.add_child(awards)
	for a: Variant in state.awards:
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(290, 110)
		var cv := VBoxContainer.new()
		card.add_child(cv)
		var at := Label.new()
		at.theme_type_variation = &"HeadingLabel"
		at.text = str(a["title"])
		at.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
		cv.add_child(at)
		var an := Label.new()
		an.text = str(a["name"])
		cv.add_child(an)
		var ad := Label.new()
		ad.theme_type_variation = &"SmallLabel"
		ad.text = str(a["text"])
		cv.add_child(ad)
		awards.add_child(card)
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


func _mat(c: Color, metallic: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metallic
	m.roughness = 0.4 if metallic > 0.0 else 0.8
	return m
