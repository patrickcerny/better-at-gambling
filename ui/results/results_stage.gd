class_name ResultsStage
extends Node3D
## The results screen (§2.11, art direction "podium results with ragdolls"; reworked in 0.9.81,
## Patrick: "rework it to look nicer"). A short show on a casino stage (`PodiumSet`: round stage,
## art-deco sunburst, curtains, a marquee with chasing bulbs): everyone below the top three drops
## in beside the stage, then the lacquered podium steps ride up out of the stage and the beans fall
## onto them in order (3rd, 2nd, 1st), each under its own spotlight with a name plate over its
## head; the winner celebrates under confetti, a coin shower and gold firework pops (`WinnerFx`)
## while the sunburst lights up; last place slumps under a little rain cloud. Standings (left) and the money-over-time graph (right) slide in, the
## fun awards pop up one by one, then Play again / Leave (greyed out with a countdown for the
## first `results_min_time` seconds, so nobody skips the screen by accident). Online, the party leader takes the room
## back to the lobby (or it goes back by itself after a minute); in Practice, Play again starts a
## fresh match. Every standings row shows the XP that player earned (the server's `progress` rows,
## the same numbers on every screen), and YOUR PROGRESS (the bottom corners) breaks down the
## local player's XP and Coins, then fills the XP bar ("LEVEL 7 → 8") as the profile takes them
## (docs/GDD.md "Progression").

signal play_again_pressed
signal leave_pressed

const ORIGIN: Vector3 = Vector3(0, 0, -400)
## The podium (0.9.72 rework): three lacquered steps standing together on the round stage, each
## capped in its medal's metal with a medal disc and the place on the front.
const PODIUM_HEIGHTS: Array[float] = [1.45, 1.02, 0.76]
const PODIUM_X: Array[float] = [0.0, -2.05, 2.05]
const PODIUM_W: float = 2.0
const PODIUM_D: float = 1.5
## Medal metals [face, dark rim] for 1st, 2nd and 3rd.
const MEDALS: Array[Color] = [Color("#F0C24F"), Color("#D3D8DF"), Color("#D08850")]
const MEDAL_RIMS: Array[Color] = [Color("#8C6418"), Color("#6C737C"), Color("#6D3F1F")]
## Spotlight tints over the three steps.
const SPOT_TINTS: Array[Color] = [Color("#FFE0A3"), Color("#E6EEFF"), Color("#FFD2B0")]
## Height of the name tag over a bean's feet.
const TAG_Y: float = 2.3
const NAMEPLATE_SHADER: Shader = preload("res://ui/results/nameplate.gdshader")
## Show timeline (seconds after the screen opens).
const T_FLOOR: float = 0.3
const T_PLACE: Array[float] = [3.6, 1.9, 0.9]  # 1st, 2nd, 3rd
## Patrick's announcer ("the wait is over", ~1.5 s) builds up to the 1st-place reveal.
const T_ANNOUNCE: float = 2.0
const T_AWARDS: float = 4.6
const AWARD_GAP: float = 0.4
## Everyone below the top three stands on the floor beside the podium, alternating sides: the first
## pair `FLOOR_X0` m out (clear of the 2nd / 3rd place tags), then every `FLOOR_GAP` m (a name tag
## wide, so tags never pile up). A big party (7–8) needs a third column: the camera then stands
## back far enough to keep the whole crowd in shot (`_fit_camera`).
const FLOOR_X0: float = 4.0
const FLOOR_GAP: float = 1.95
## Half a name tag plus a margin: how far past the outermost bean the shot must reach (m).
const FLOOR_MARGIN: float = 1.3
## The shot's aspect (the game renders 16:9) and the closest the camera ends up (m from the podium).
const SHOT_ASPECT: float = 16.0 / 9.0
const CAM_NEAR_Z: float = 9.0
## More rows than this: the standings list gets compact so it ends above the floor crowd's tags.
const COMPACT_ROWS: int = 6
## When the XP bar starts filling and how long it takes.
const T_XP: float = 2.4
const XP_FILL_SECONDS: float = 1.8
## Width of the two YOUR PROGRESS corner panels.
const XP_PANEL_W: float = 440.0

var state: ClientMatchState
var local_id: int = -1
var camera: Camera3D
var ui: CanvasLayer
## Where the UI layer goes: the match scene points it outside the 3D world's sub viewport
## (`PixelView`) onto the window's canvas; null keeps it under the stage. The stage frees it either way.
var ui_host: Node = null
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
## What the profile took from this match (`PlayerProfile.apply_match`: xp, coins, level_bonus,
## level_from, level_to, xp_from); set before `setup`. Empty (already counted, a reconnect): the
## panel shows the server's row and the profile as it is.
var progress_summary: Dictionary = {}
var xp_panel: PanelContainer
var xp_bar: ProgressBar
var level_label: Label
var xp_label: Label
var coins_line: Label
## The XP total the bar shows now (animates from `xp_from` to the profile's XP).
var xp_shown: float = 0.0
var _xp_from: float = 0.0
var _xp_to: float = 0.0
var _xp_t: float = -1.0
## The level the match started at.
var _level_from: int = 1
## [{at: float, fn: Callable}] still to run, by time.
var _cues: Array[Dictionary] = []
var _clock: float = 0.0
var _room: bool = false
var _key_light: SpotLight3D
var podium_set: PodiumSet
## Spotlight over each podium step (1st, 2nd, 3rd), off until its bean lands.
var _spots: Array[SpotLight3D] = []
var winner_fx: WinnerFx
var _cam_from: Vector3 = Vector3(0, 4.1, 12.5)
var _cam_to: Vector3 = Vector3(0, 3.3, 9.0)
## Seconds the screen stays up before Play again / Leave can be pressed (Patrick, 0.9.43: it got
## skipped straight away, a Space / Enter / pad A still held from the match pressed the focused
## button). Set before `setup`; 0 unlocks at once (tests, look-dev shots).
var lock_seconds: float = -1.0
var _unlocked: bool = false
var _play_text: String = ""
var _leave_text: String = ""


func setup(p_state: ClientMatchState, p_local_id: int, room: bool) -> void:
	state = p_state
	local_id = p_local_id
	_room = room
	if lock_seconds < 0.0:
		lock_seconds = Registry.balance.results_min_time
	position = ORIGIN
	_build_set()
	ui = CanvasLayer.new()
	ui.layer = 6
	(ui_host if ui_host != null else self).add_child(ui)
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
	if _xp_t >= 0.0 and _xp_t < 1.0:
		_xp_t = minf(_xp_t + delta / XP_FILL_SECONDS, 1.0)
		_show_xp(lerpf(_xp_from, _xp_to, 1.0 - pow(1.0 - _xp_t, 2.0)))
	_update_lock()
	if _room and wait_label != null:
		var leader: bool = state.leader == local_id
		if play_button.visible != leader:
			play_button.visible = leader
			# Hiding the focused button drops the focus, and a new leader's button appears without it:
			# keep a pad player on a button they can press.
			var owner_now: Control = get_viewport().gui_get_focus_owner()
			if _unlocked and (owner_now == null or not owner_now.is_visible_in_tree()):
				(play_button if leader else leave_button).grab_focus()
		var secs: int = ceili(maxf(state.results_return_in, 0.0))
		wait_label.text = ("Back to the lobby in %ds" % secs) if leader else ("Waiting for the lobby leader… back to the lobby in %ds" % secs)


## Keeps Play again / Leave greyed out with a countdown for the first `lock_seconds`, then
## enables them and puts the focus on the one this player can press.
func _update_lock() -> void:
	if _unlocked or play_button == null:
		return
	if _clock < lock_seconds:
		var left: int = ceili(lock_seconds - _clock)
		play_button.text = "%s (%d)" % [_play_text, left]
		leave_button.text = "%s (%d)" % [_leave_text, left]
		return
	_unlocked = true
	play_button.disabled = false
	leave_button.disabled = false
	play_button.text = _play_text
	leave_button.text = _leave_text
	(play_button if play_button.visible else leave_button).grab_focus()


## True once Play again / Leave can be pressed.
func is_unlocked() -> bool:
	return _unlocked


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(ui) and ui.get_parent() != self:
		ui.queue_free()  # hosted outside the stage: goes with it


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
	if _xp_t >= 0.0:
		_xp_t = 1.0
		_show_xp(_xp_to)


func _rank_of(pid: int) -> int:
	for row: Variant in state.standings:
		if int(row["player"]) == pid:
			return int(row["rank"])
	return 99


func _color_of(pid: int) -> Color:
	return Palette.player_color(int(state.players.get(pid, {}).get("color", pid - 1)))


func _build_set() -> void:
	podium_set = PodiumSet.new()
	podium_set.name = "Set"
	add_child(podium_set)
	var standings: Array = state.standings
	_fit_camera(standings.filter(func(r: Variant) -> bool: return int(r["rank"]) > 3).size())
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
			base = Vector3(x + (nth - (sharing - 1) * 0.5) * 0.95, PodiumSet.STAGE_H + h, 0)
			at = T_PLACE[place] + 0.35 + nth * 0.15
		else:
			# Everyone else cheers from the floor beside the stage, alternating sides.
			var side: float = -1.0 if on_floor % 2 == 0 else 1.0
			base = Vector3(side * (FLOOR_X0 + floorf(on_floor / 2.0) * FLOOR_GAP), 0, 0.6)
			at = T_FLOOR + on_floor * 0.15
			on_floor += 1
		var bean := AvatarVisuals.new()
		bean.position = base
		bean.visible = false
		add_child(bean)
		bean.set_color(Palette.bean_color(state.players.get(pid, {"color": pid - 1})))
		bean.set_outfit(Cosmetics.outfit_of(state.players.get(pid, {})))
		# The rig's front is -Z: half a turn faces the camera; the floor crowd turns a little in
		# towards the podium.
		bean.rotation.y = PI - (signf(base.x) * 0.3 if place < 0 else 0.0)
		beans[pid] = bean
		bean_y[pid] = base.y
		var puppet: BeanPuppet = BeanPuppet.attach(bean)
		puppets[pid] = puppet
		# Neighbours sharing a block get staggered tags so names never overlap.
		var nth_tag: int = 0 if place < 0 else standings.filter(func(r: Variant) -> bool: return int(r["rank"]) == rank and int(r["player"]) < pid).size()
		var is_last: bool = rank == last_rank and standings.size() > 2 and rank > 1
		var tag: Label3D = _name_tag(row as Dictionary, pid, rank)
		# Last place's tag sits higher: the rain cloud floats between it and the bean.
		# The winner jumps for joy: its tag floats a little higher.
		tag.position = base + Vector3(0, TAG_Y + (nth_tag % 2) * 0.62 + (0.5 if is_last else 0.0) + (0.35 if rank == 1 else 0.0), 0)
		tag.visible = false
		_cue(at, _land.bind(pid, tag, rank, is_last))
	_build_lights()
	camera = Camera3D.new()
	camera.fov = 52.0
	camera.far = 90.0  # the casino is 400 m away: keep its always-on-top labels out of shot
	add_child(camera)
	camera.position = _cam_from
	camera.look_at(global_position + Vector3(0, 2.0, 0))


## A bean's name and money over its head, on a walnut plate with a brass edge and a stripe in the
## player's colour (the winner's plate is gold-edged and a size bigger).
func _name_tag(row: Dictionary, pid: int, rank: int) -> Label3D:
	var tag := Label3D.new()
	tag.text = "%s\n$%s" % [str(row["name"]), Hud._thousands(int(row["money"]))]
	tag.font = TableSkin.heavy_font()
	tag.font_size = 46 if rank == 1 else 40
	tag.pixel_size = 0.006
	tag.line_spacing = -6.0
	tag.outline_size = 6
	tag.outline_modulate = Color(0, 0, 0, 0.6)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.modulate = Palette.VIP_GOLD if pid == local_id else Palette.CREAM
	tag.render_priority = 2
	tag.outline_render_priority = 1
	add_child(tag)
	# The text box from the font (the label builds its mesh later), in metres.
	var text_px: Vector2 = tag.font.get_multiline_string_size(tag.text, HORIZONTAL_ALIGNMENT_CENTER, -1, tag.font_size)
	text_px.y += tag.line_spacing
	var plate := MeshInstance3D.new()
	plate.name = "Plate"
	var qm := QuadMesh.new()
	var size := Vector2(text_px.x * tag.pixel_size + 0.34, text_px.y * tag.pixel_size + 0.16)
	qm.size = size
	plate.mesh = qm
	plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ShaderMaterial.new()
	m.shader = NAMEPLATE_SHADER
	m.render_priority = 0
	m.set_shader_parameter(&"size", size)
	m.set_shader_parameter(&"accent", _color_of(pid))
	if rank == 1:
		m.set_shader_parameter(&"border", Color("#F4CF6A"))
		m.set_shader_parameter(&"border_w", 0.03)
	elif rank > 3:
		m.set_shader_parameter(&"border", Color("#8A6D35"))
	plate.material_override = m
	tag.add_child(plate)
	return tag


## Stands the camera back until `floor_count` beans beside the podium (and their tags) fit the shot.
func _fit_camera(floor_count: int) -> void:
	var cols: int = ceili(floor_count / 2.0)
	if cols <= 0:
		return
	var reach: float = FLOOR_X0 + (cols - 1) * FLOOR_GAP + FLOOR_MARGIN
	var tan_half_w: float = tan(deg_to_rad(52.0 * 0.5)) * SHOT_ASPECT
	var z: float = maxf(CAM_NEAR_Z, reach / tan_half_w + 0.6)
	_cam_from.z += z - _cam_to.z
	_cam_to.z = z


## A podium step that rises out of the stage at its place's cue: a gold plinth, a burgundy
## lacquer body with gold corner strips, a cap in the medal's metal and, on the front, a medal disc
## with the place.
func _build_block(place: int, x: float, h: float, rank: int, sharing: int) -> void:
	var w: float = maxf(PODIUM_W, sharing * 0.95 + 0.3)
	var d: float = PODIUM_D
	var metal: Color = MEDALS[place]
	var pivot := Node3D.new()
	pivot.name = "Podium%d" % rank
	pivot.position = Vector3(x, PodiumSet.STAGE_H, 0)
	add_child(pivot)
	var gold: StandardMaterial3D = _mat(Palette.WARM_GOLD, 0.85)
	var cap_h: float = 0.11
	var plinth_h: float = 0.08
	# Plinth, body, cap.
	_block_box(pivot, Vector3(w + 0.08, plinth_h, d + 0.08), Vector3(0, plinth_h * 0.5, 0), gold)
	var body_mat: StandardMaterial3D = _mat(Color("#7C2433"), 0.0)
	body_mat.roughness = 0.35
	_block_box(pivot, Vector3(w, h - cap_h - plinth_h, d), Vector3(0, plinth_h + (h - cap_h - plinth_h) * 0.5, 0), body_mat)
	_block_box(pivot, Vector3(w + 0.1, cap_h, d + 0.1), Vector3(0, h - cap_h * 0.5, 0), _medal_mat(metal))
	# Thin gold strips down the front corners and under the cap.
	for sx: float in [-1.0, 1.0]:
		_block_box(pivot, Vector3(0.05, h - cap_h - plinth_h, 0.05), Vector3(sx * (w * 0.5 - 0.01), plinth_h + (h - cap_h - plinth_h) * 0.5, d * 0.5 - 0.01), gold)
	_block_box(pivot, Vector3(w, 0.035, 0.04), Vector3(0, h - cap_h - 0.03, d * 0.5 + 0.005), gold)
	# The medal on the front.
	var r: float = clampf(h * 0.28, 0.22, 0.36)
	var cy: float = plinth_h + (h - cap_h - plinth_h) * 0.5
	var rim := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = r
	rm.bottom_radius = r
	rm.height = 0.05
	rm.radial_segments = 32
	rim.mesh = rm
	rim.rotation = Vector3(PI * 0.5, 0, 0)
	rim.position = Vector3(0, cy, d * 0.5 + 0.025)
	rim.material_override = _medal_mat(MEDAL_RIMS[place])
	pivot.add_child(rim)
	var face := MeshInstance3D.new()
	var fm := CylinderMesh.new()
	fm.top_radius = r * 0.84
	fm.bottom_radius = r * 0.84
	fm.height = 0.05
	fm.radial_segments = 32
	face.mesh = fm
	face.rotation = Vector3(PI * 0.5, 0, 0)
	face.position = Vector3(0, cy, d * 0.5 + 0.04)
	face.material_override = _medal_mat(metal)
	pivot.add_child(face)
	var num := Label3D.new()
	num.name = "Place"
	num.text = str(rank)
	num.font = TableSkin.black_font()
	num.font_size = 128
	num.pixel_size = r * 0.0105
	num.outline_size = 0
	num.modulate = Color("#3A2410")
	num.position = Vector3(0, cy - r * 0.04, d * 0.5 + 0.07)
	num.shaded = false
	pivot.add_child(num)
	# Hidden in the stage until its cue, then it rides up like a lift.
	var sunk: float = PodiumSet.STAGE_H - h - 0.05
	pivot.position.y = sunk
	pivot.visible = false
	_cue(T_PLACE[place], func() -> void:
		pivot.visible = true
		Audio.play(&"whoosh", &"SFX", -6.0, 0.8 + place * 0.1)
		if DisplayServer.get_name() == "headless":
			pivot.position.y = PodiumSet.STAGE_H
			return
		var t: Tween = pivot.create_tween()
		t.tween_property(pivot, "position:y", PodiumSet.STAGE_H, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))


## Medal metal that still reads without reflections (Compatibility): a little metallic, a soft
## glow of its own colour.
func _medal_mat(c: Color) -> StandardMaterial3D:
	var m: StandardMaterial3D = _mat(c, 0.35)
	m.roughness = 0.35
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 0.32
	return m


func _block_box(parent: Node3D, size: Vector3, at: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = at
	mi.material_override = m
	parent.add_child(mi)
	return mi


## A bean drops onto its spot under its own spotlight; 1st celebrates, last sulks.
func _land(pid: int, tag: Label3D, rank: int, is_last: bool) -> void:
	var bean: AvatarVisuals = beans[pid]
	var puppet: BeanPuppet = puppets[pid]
	bean.visible = true
	puppet.drop_in(3.5 if rank <= 3 else 2.5)
	Audio.play(&"thud", &"SFX", -6.0)
	tag.visible = true
	_pop3d(tag)
	if rank <= 3:
		_spot_on(rank - 1)
	if rank == 1:
		puppet.set_mood(BeanPuppet.Mood.CHEER)
		ConfettiBurst.burst(self, Vector3(bean.position.x, bean_y[pid] + 2.0, bean.position.z), 160, 1.3)
		Audio.play(&"big_win", &"SFX", -4.0)
		if podium_set != null:
			podium_set.celebrate()
		if winner_fx == null:
			winner_fx = WinnerFx.start(self, Vector3(PODIUM_X[0], bean_y[pid], 0))
		if _key_light != null:
			_key_light.light_energy = 5.0
			_key_light.create_tween().tween_property(_key_light, "light_energy", 3.4, 1.2)
		_cue(_clock + 0.6, func() -> void: ConfettiBurst.rain(self, Vector3(0, 8.0, 0.5), Vector3(14, 0.2, 4), 90))
	elif is_last:
		puppet.set_mood(BeanPuppet.Mood.SAD)
		_cue(_clock + 0.8, _rain_cloud.bind(bean_y[pid], bean.position))
		Audio.play(&"loss_sting", &"SFX", -10.0)
	elif rank <= 3:
		puppet.hop(0.3)


## Switches on the spotlight over podium step `place` (0 = 1st).
func _spot_on(place: int) -> void:
	if place < 0 or place >= _spots.size():
		return
	var spot: SpotLight3D = _spots[place]
	var energy: float = 7.0 if place == 0 else 4.5
	if DisplayServer.get_name() == "headless":
		spot.light_energy = energy
		return
	spot.light_energy = energy * 1.6
	spot.create_tween().tween_property(spot, "light_energy", energy, 0.5)


## A small soft storm cloud drizzling on last place: rounded blue-grey puffs with a flat underside,
## bobbing a little.
func _rain_cloud(y: float, at: Vector3) -> void:
	var cloud := Node3D.new()
	cloud.name = "RainCloud"
	cloud.position = Vector3(at.x, y + 1.95, at.z)
	add_child(cloud)
	var top: StandardMaterial3D = _mat(Color("#C3CAD4"))
	top.emission_enabled = true
	top.emission = Color("#5E6672")
	var under: StandardMaterial3D = _mat(Color("#6F7886"))
	for p: Vector4 in [Vector4(-0.36, 0.0, 0.0, 0.24), Vector4(-0.12, 0.12, 0.02, 0.3), Vector4(0.16, 0.16, -0.02, 0.33), Vector4(0.42, 0.02, 0.0, 0.24), Vector4(0.02, -0.02, 0.12, 0.26)]:
		var puff := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = p.w
		sm.height = p.w * 2.0
		sm.radial_segments = 14
		sm.rings = 7
		puff.mesh = sm
		puff.position = Vector3(p.x, p.y, p.z)
		puff.material_override = top
		cloud.add_child(puff)
	# The flat dark underside.
	var base := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.62
	cm.bottom_radius = 0.58
	cm.height = 0.1
	cm.radial_segments = 20
	base.mesh = cm
	base.scale = Vector3(1, 1, 0.45)
	base.position = Vector3(0.03, -0.12, 0.02)
	base.material_override = under
	cloud.add_child(base)
	if DisplayServer.get_name() == "headless":
		return
	var drops := CPUParticles3D.new()
	drops.amount = 14
	drops.lifetime = 0.35
	drops.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	drops.emission_box_extents = Vector3(0.45, 0.03, 0.15)
	drops.direction = Vector3.DOWN
	drops.spread = 0.0
	drops.gravity = Vector3(0, -9.0, 0)
	drops.initial_velocity_min = 1.0
	drops.initial_velocity_max = 1.5
	var qm := QuadMesh.new()
	qm.size = Vector2(0.018, 0.11)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color("#A9C4DA", 0.75)
	qm.material = m
	drops.mesh = qm
	drops.position = Vector3(0, -0.2, 0)
	cloud.add_child(drops)
	cloud.scale = Vector3.ONE * 0.1
	var tw: Tween = cloud.create_tween()
	tw.tween_property(cloud, "scale", Vector3.ONE * 0.75, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var bob: Tween = cloud.create_tween().set_loops()
	bob.tween_property(cloud, "position:y", cloud.position.y + 0.07, 1.1).set_trans(Tween.TRANS_SINE)
	bob.tween_property(cloud, "position:y", cloud.position.y, 1.1).set_trans(Tween.TRANS_SINE)


func _build_lights() -> void:
	# A warm key from the front, a gold back light that makes the sunburst glow, and one spotlight
	# per podium step that switches on as its bean lands.
	_key_light = SpotLight3D.new()
	_key_light.name = "Key"
	_key_light.position = Vector3(0, 8.5, 8)
	_key_light.spot_range = 24.0
	_key_light.spot_angle = 50.0
	_key_light.light_energy = 3.4
	_key_light.light_color = Color("#FFE2B0")
	_key_light.shadow_enabled = true
	add_child(_key_light)
	_key_light.look_at_from_position(_key_light.position, Vector3(0, 1.2, 0))
	var fill := OmniLight3D.new()
	fill.position = Vector3(0, 3.5, 5)
	fill.omni_range = 14.0
	fill.light_energy = 0.9
	fill.light_color = Palette.VIP_GOLD
	add_child(fill)
	var back := OmniLight3D.new()
	back.name = "Back"
	back.position = Vector3(0, 2.6, PodiumSet.WALL_Z + 1.4)
	back.omni_range = 7.5
	back.light_energy = 1.2
	back.light_color = Color("#FFB866")
	add_child(back)
	for place: int in 3:
		var spot := SpotLight3D.new()
		spot.name = "Spot%d" % (place + 1)
		spot.position = Vector3(PODIUM_X[place], 8.2, 2.2)
		spot.spot_range = 12.0
		spot.spot_angle = 15.0 if place == 0 else 13.0
		spot.spot_attenuation = 0.4
		spot.light_energy = 0.0
		spot.light_color = SPOT_TINTS[place]
		add_child(spot)
		spot.look_at_from_position(spot.position, Vector3(PODIUM_X[place], PodiumSet.STAGE_H + PODIUM_HEIGHTS[place] + 0.6, 0))
		_spots.append(spot)


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
	# Standings, top left: the table look (walnut, brass frame), a medal per place.
	var panel := PanelContainer.new()
	panel.name = "Standings"
	panel.position = Vector2(28, 28)
	panel.custom_minimum_size = Vector2(450, 0)
	_skin_panel(panel, 18.0, 14.0)
	root.add_child(panel)
	standings_panel = panel
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 4)
	panel.add_child(v)
	# A big party gets a compact list, so it ends above the name tags of the crowd on the floor.
	var compact: bool = state.standings.size() > COMPACT_ROWS
	var row_font: int = 22 if compact else 28
	if compact:
		v.add_theme_constant_override(&"separation", 0)
	var t: Label = TableSkin.label("FINAL STANDINGS", 34 if compact else 42, Palette.VIP_GOLD)
	t.add_theme_font_override(&"font", TableSkin.black_font())
	v.add_child(t)
	for row: Variant in state.standings:
		var pid: int = int(row["player"])
		var rank: int = int(row["rank"])
		var me: bool = pid == local_id
		var band := PanelContainer.new()
		var bsb := StyleBoxFlat.new()
		bsb.bg_color = Color(Palette.VIP_GOLD, 0.14) if me else Color(0, 0, 0, 0.0)
		bsb.border_color = Color(Palette.VIP_GOLD, 0.55) if me else Color(0, 0, 0, 0.0)
		bsb.set_border_width_all(1)
		bsb.set_corner_radius_all(10)
		bsb.content_margin_left = 6
		bsb.content_margin_right = 8
		bsb.content_margin_top = 1
		bsb.content_margin_bottom = 1
		band.add_theme_stylebox_override(&"panel", bsb)
		var h := HBoxContainer.new()
		h.add_theme_constant_override(&"separation", 10)
		band.add_child(h)
		h.add_child(PlaceBadge.make(rank, 30.0 if compact else 40.0))
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(14, 14)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var dsb := StyleBoxFlat.new()
		dsb.bg_color = _color_of(pid)
		dsb.set_corner_radius_all(7)
		dsb.border_color = Color(0, 0, 0, 0.5)
		dsb.set_border_width_all(1)
		dsb.anti_aliasing = true
		dot.add_theme_stylebox_override(&"panel", dsb)
		h.add_child(dot)
		var n: Label = TableSkin.label(str(row["name"]), row_font, Palette.VIP_GOLD if me else Palette.CREAM)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		n.clip_text = true
		n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		h.add_child(n)
		var m: Label = TableSkin.label("$%s" % Hud._thousands(int(row["money"])), row_font + 2, Palette.MONEY_GREEN if rank == 1 else Palette.CREAM, true)
		m.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(m)
		var prow: Dictionary = _progress_row(pid)
		if not prow.is_empty():
			var xl: Label = TableSkin.label("+%d XP" % int(prow.get("xp", 0)), 18 if compact else 20, TableSkin.BRASS, true)
			xl.name = "Xp%d" % pid
			xl.custom_minimum_size.x = 80
			xl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			h.add_child(xl)
		v.add_child(band)
	_slide_in(panel, Vector2(-500, 0), 0.4)
	# Money over time, top right: the same frame, the graph on a dark inset.
	var colors: Dictionary = {}
	for row: Variant in state.standings:
		colors[int(row["player"])] = _color_of(int(row["player"]))
	var gp := PanelContainer.new()
	gp.name = "GraphPanel"
	gp.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	gp.anchor_left = 1.0
	gp.anchor_right = 1.0
	gp.offset_left = -620
	gp.offset_right = -28
	gp.offset_top = 28
	_skin_panel(gp, 18.0, 14.0)
	root.add_child(gp)
	graph_panel = gp
	var gv := VBoxContainer.new()
	gv.add_theme_constant_override(&"separation", 6)
	gp.add_child(gv)
	var gt: Label = TableSkin.label("MONEY OVER TIME", 30, Palette.VIP_GOLD)
	gt.add_theme_font_override(&"font", TableSkin.black_font())
	gt.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	gv.add_child(gt)
	var inset := PanelContainer.new()
	var isb := StyleBoxFlat.new()
	isb.bg_color = Color("#140D0B")
	isb.border_color = Color(TableSkin.BRASS, 0.35)
	isb.set_border_width_all(1)
	isb.set_corner_radius_all(10)
	isb.set_content_margin_all(6)
	isb.anti_aliasing = true
	inset.add_theme_stylebox_override(&"panel", isb)
	gv.add_child(inset)
	graph = MoneyGraph.new()
	graph.custom_minimum_size = Vector2(540, 196 if state.standings.size() > COMPACT_ROWS else 250)  # big party: clear of the crowd's tags
	graph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inset.add_child(graph)
	var start: int = 0
	if not state.standings.is_empty():
		var s0: Array = (state.standings[0] as Dictionary).get("series", [])
		start = int(s0[0]) if not s0.is_empty() else 0
	graph.setup(state.standings, colors, local_id, state.duration_s, start)
	gp.visible = graph.has_data()
	graph.set_process(false)
	_cue(1.0, func() -> void: graph.set_process(true))
	_cue(T_ANNOUNCE, func() -> void: Audio.play(&"announcer_results", &"UI", -2.0))
	_slide_in(gp, Vector2(660, 0), 0.6)
	_build_xp_panel(root)
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
	TableSkin.style_button(play_button, &"gold", 28)
	play_button.custom_minimum_size = Vector2(220, 56)
	buttons.add_child(play_button)
	leave_button = Button.new()
	leave_button.text = "MAIN MENU" if not _room else "LEAVE LOBBY"
	leave_button.pressed.connect(func() -> void: leave_pressed.emit())
	TableSkin.style_button(leave_button, &"ghost", 28)
	leave_button.custom_minimum_size = Vector2(200, 56)
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
	_play_text = play_button.text
	_leave_text = leave_button.text
	play_button.disabled = true
	leave_button.disabled = true
	if _room:
		play_button.visible = state.leader == local_id
	_update_lock()


## The server's XP/Coins row for `pid` ({} when the event carried none).
func _progress_row(pid: int) -> Dictionary:
	var row: Variant = state.progress.get(pid, null)
	return row as Dictionary if row is Dictionary else {}


## YOUR PROGRESS, in the two bottom corners under the awards (clear of the floor crowd's name
## tags): right, the level bar ("LEVEL 7 → 8"), the XP and the Coins (out-of-match money, for
## cosmetics only); left, where the XP came from.
func _build_xp_panel(root: Control) -> void:
	var row: Dictionary = _progress_row(local_id)
	if row.is_empty() or ProfileManager.profile == null:
		return
	var prof: PlayerProfile = ProfileManager.profile
	var cfg: ProgressionConfig = prof.config
	xp_panel = _corner_panel(root, "XpPanel", false)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 2)
	xp_panel.add_child(v)
	var lv := HBoxContainer.new()
	lv.add_theme_constant_override(&"separation", 10)
	v.add_child(lv)
	level_label = Label.new()
	level_label.name = "Level"
	level_label.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	lv.add_child(level_label)
	xp_bar = ProgressBar.new()
	xp_bar.name = "XpBar"
	xp_bar.show_percentage = false
	xp_bar.max_value = 1.0
	xp_bar.step = 0.0
	xp_bar.custom_minimum_size = Vector2(80, 14)
	xp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lv.add_child(xp_bar)
	xp_label = Label.new()
	xp_label.name = "XpLabel"
	xp_label.theme_type_variation = &"SmallLabel"
	lv.add_child(xp_label)
	var ch := HBoxContainer.new()
	ch.add_theme_constant_override(&"separation", 8)
	v.add_child(ch)
	var total := Label.new()
	total.name = "XpTotal"
	total.text = "+%d XP" % int(row.get("xp", 0))
	total.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	ch.add_child(total)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ch.add_child(gap)
	var coin := CoinIcon.make(24.0)
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ch.add_child(coin)
	coins_line = Label.new()
	coins_line.name = "Coins"
	coins_line.add_theme_color_override(&"font_color", Palette.COIN_RED)
	coins_line.tooltip_text = "Coins buy cosmetics in the main menu. Your $ stays here: it starts fresh next match."
	var summary: Dictionary = progress_summary
	var coins: int = int(summary.get("coins", row.get("coins", 0)))
	var bonus: int = int(summary.get("level_bonus", 0))
	coins_line.text = "+%d COINS" % coins + (" (+%d level-up bonus)" % bonus if bonus > 0 else " for cosmetics")
	ch.add_child(coins_line)
	# Where the XP came from, bottom left.
	var parts_panel: PanelContainer = _corner_panel(root, "XpParts", true)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override(&"separation", 0)
	parts_panel.add_child(pv)
	var t := Label.new()
	t.theme_type_variation = &"SmallLabel"
	t.text = "YOUR XP" + ("  ·  PRACTICE: HALF RATE" if bool(row.get("practice", false)) else "")
	t.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	pv.add_child(t)
	var line := PackedStringArray()
	for p: Variant in row.get("parts", []):
		if p is Dictionary:
			line.append("%s +%d" % [str((p as Dictionary).get("label", "")), int((p as Dictionary).get("xp", 0))])
	var bd := Label.new()
	bd.name = "Breakdown"
	bd.theme_type_variation = &"SmallLabel"
	bd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bd.text = "  ·  ".join(line)
	pv.add_child(bd)
	_xp_to = float(prof.xp)
	_xp_from = float(summary.get("xp_from", prof.xp)) if not summary.is_empty() else _xp_to
	_level_from = cfg.level_for_xp(int(_xp_from))
	_show_xp(_xp_from)
	_slide_in(xp_panel, Vector2(0, 160), 0.9)
	_slide_in(parts_panel, Vector2(0, 160), 0.9)
	_cue(T_XP, func() -> void:
		_xp_t = 0.0
		if _xp_to > _xp_from:
			Audio.play(&"ui_click", &"UI", -8.0, 1.4))


## A small panel in a bottom corner, under the awards row.
func _corner_panel(root: Control, node_name: String, left: bool) -> PanelContainer:
	var p := PanelContainer.new()
	p.name = node_name
	p.anchor_left = 0.0 if left else 1.0
	p.anchor_right = p.anchor_left
	p.anchor_top = 1.0
	p.anchor_bottom = 1.0
	p.offset_left = 28.0 if left else -28.0 - XP_PANEL_W
	p.offset_right = p.offset_left + XP_PANEL_W
	p.offset_top = -120.0
	p.offset_bottom = -16.0
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_skin_panel(p, 16.0, 10.0)
	root.add_child(p)
	return p


## The table overlays' panel look (walnut, brass border, inner hairline, corner studs).
func _skin_panel(p: PanelContainer, margin_x: float, margin_y: float) -> void:
	var sb: StyleBoxFlat = TableSkin.panel_box()
	sb.content_margin_left = margin_x
	sb.content_margin_right = margin_x
	sb.content_margin_top = margin_y
	sb.content_margin_bottom = margin_y
	sb.shadow_size = 14
	p.add_theme_stylebox_override(&"panel", sb)
	p.draw.connect(TableSkin.draw_frame.bind(p))


## Draws the bar at `total` XP: the level it reaches ("LEVEL 7 → 8" once it passes the one the
## match started at) and how far into it.
func _show_xp(total: float) -> void:
	if xp_bar == null:
		return
	xp_shown = total
	var cfg: ProgressionConfig = ProfileManager.profile.config
	var xp: int = int(round(total))
	var lvl: int = cfg.level_for_xp(xp)
	var into: int = xp - cfg.xp_for_level(lvl)
	var need: int = cfg.xp_to_next(lvl)
	xp_bar.value = 1.0 if need <= 0 else clampf(float(into) / float(need), 0.0, 1.0)
	level_label.text = ("LEVEL %d → %d" % [_level_from, lvl]) if lvl > _level_from else "LEVEL %d" % lvl
	xp_label.text = "%d / %d XP" % [into, need] if need > 0 else "MAX LEVEL"


func _award_card(a: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(330, 124)
	var sb: StyleBoxFlat = TableSkin.panel_box()
	sb.border_width_top = 6
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 12
	sb.shadow_size = 10
	card.add_theme_stylebox_override(&"panel", sb)
	card.draw.connect(TableSkin.draw_frame.bind(card))
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override(&"separation", 2)
	card.add_child(cv)
	var at: Label = TableSkin.label(str(a["title"]).to_upper(), 30, Palette.VIP_GOLD)
	at.add_theme_font_override(&"font", TableSkin.black_font())
	at.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	cv.add_child(at)
	var who := HBoxContainer.new()
	who.add_theme_constant_override(&"separation", 8)
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(14, 14)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var dsb := StyleBoxFlat.new()
	dsb.bg_color = _color_of(int(a.get("player", 0)))
	dsb.set_corner_radius_all(7)
	dsb.anti_aliasing = true
	dot.add_theme_stylebox_override(&"panel", dsb)
	who.add_child(dot)
	var an: Label = TableSkin.label(str(a["name"]), 28, Palette.VIP_GOLD if int(a.get("player", -1)) == local_id else Palette.CREAM)
	an.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	who.add_child(an)
	cv.add_child(who)
	var ad: Label = TableSkin.label(str(a["text"]), 21, TableSkin.TEXT_MUTED)
	ad.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
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
	m.roughness = 0.3 if metallic > 0.0 else 0.8
	return m
