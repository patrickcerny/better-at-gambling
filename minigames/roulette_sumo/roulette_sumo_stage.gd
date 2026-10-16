class_name RouletteSumoStage
extends WalkableStage
## Client presentation of Roulette Sumo on the giant wheel (`WheelRoom`; a `WalkableStage`: real
## avatars, the normal camera). The rotor turns to the server's wheel angle and drags our own bean
## with it (`RouletteSumoLogic.drift` every physics frame); ragdolls this process simulates (the
## tumble over the rim) are dragged by the deck too. A giant ivory ball rolls round the deck,
## predicted from the server's last segment (`step_ball`) and eased onto each update; when it
## touches a bean that bean slides away (a push, no knockdown). No bats: the action, shove and
## grab buttons all push the bean in front (`minigame_action push`); the server decides, and the
## pushed bean's own client slides it about a metre. Falling off: an outward tumble into the pit,
## "OFF THE WHEEL!", then the gallery. Lucky runs the show from the croupier dais. The overlay
## shows the clock, a wheel-speed gauge, who is still on, the feed, Lucky's lines and a context
## prompt (push / edge warning).

## Beans past this radius get an edge warning.
const EDGE_WARN: float = WheelRoom.RIM_RADIUS - 2.0
## How fast the shown ball catches up with the predicted one (1/s).
const BALL_EASE: float = 6.0
## Ragdoll parts near the deck take this share of the deck's speed per physics frame.
const DECK_GRIP: float = 0.25
## A push lifts the bean this share of its strength (a little hop).
const PUSH_LIFT: float = 0.12

var clock: float = 0.0
var done: bool = false
var winner: int = -1
var out: Array[int] = []
var rotor: Node3D = null
var host: QuizHost = null
## Ball: predicted state (flat, relative to the centre), the shown offset that eases out.
var ball_pos: Vector2 = Vector2.ZERO
var ball_vel: Vector2 = Vector2.ZERO
var ball_turn: float = 0.0
var ball_node: Node3D = null
var _ball_offset: Vector2 = Vector2.ZERO
var _ball_spin: Node3D = null
## Shown wheel speed (eases to 0 after the end), the shown angle.
var _omega: float = 0.0
var _angle: float = 0.0
var _cooldown: float = 0.0
var _predicted_push: float = -1.0
var _gauge_fill: ColorRect = null
var _gauge_label: Label = null
var _gauge_panel: PanelContainer = null
var _host_panel: PanelContainer = null
var _host_label: Label = null
## Lucky's speed calls: the next ramp fraction to call out (1/3, 2/3, full speed).
var _next_mark: int = 1


func _build_room() -> Node3D:
	var r: Node3D = WheelRoom.build(self)
	rotor = r.get_node_or_null(^"Wheel/Rotor") as Node3D
	return r


func _build_game(_start: Dictionary) -> void:
	_omega = RouletteSumoLogic.OMEGA_START
	_build_ball()
	if _is_dedicated():
		return
	host = QuizHost.new()
	host.name = "LuckyHost"
	add_child(host)
	host.position = WalkableLogicBase.ROOM_ORIGIN + WheelRoom.LUCKY_SPOT
	host.scale = Vector3.ONE * 1.2
	if overlay != null:
		_build_gauge()
		_build_host_panel()
	set_clock(RouletteSumoLogic.GAME_SECONDS)
	_say("Welcome to my wheel! Push the others off, dodge my ball, and don't fall off.", QuizHost.Pose.HAPPY)
	_refresh_status()


func apply_state(st: Dictionary) -> void:
	super.apply_state(st)
	clock = float(st.get("clock", clock))
	done = str(st.get("state", "")) == "done"
	winner = int(st.get("winner", -1))
	_omega = float(st.get("omega", _omega))
	_angle = float(st.get("angle", _angle))
	_read_ball(st.get("ball", {}), true)
	out.clear()
	for g: Variant in st.get("out", []):
		for p: Variant in g:
			out.append(int(p))
	_refresh_status()


func alive_players() -> Array[int]:
	var res: Array[int] = []
	for p: int in roster:
		if p not in out:
			res.append(p)
	return res


func can_act() -> bool:
	if not super.can_act() or done or local_id not in roster or local_id in out:
		return false
	var me: PlayerAvatar = local_avatar()
	return me == null or me.is_standing()


# --- Input --------------------------------------------------------------------------------------

## E pushes the bean in front (the server decides who, and how hard).
func on_action_pressed() -> bool:
	return _push()


## The shove click pushes too (the casino's shove, with its knockdowns, is off here).
func on_shove_pressed() -> bool:
	return _push()


## So does the grab click (no grabbing on the wheel).
func on_grab_pressed() -> bool:
	return _push()


func _push() -> bool:
	if not can_act():
		return going and not over
	if _cooldown > 0.0:
		return true
	var target: int = push_target()
	var payload: Dictionary = {"kind": &"push"}
	if target >= 0:
		payload["target"] = target
	_cooldown = RouletteSumoLogic.PUSH_COOLDOWN
	_predicted_push = 0.6
	_push_swing(local_id)
	Net.send_intent(Intents.make(&"minigame_action", payload))
	return true


## The bean a push would reach (the server's pick), or -1.
func push_target() -> int:
	return local_target(RouletteSumoLogic.PUSH_REACH)


# --- Events -------------------------------------------------------------------------------------

func on_event(ev: Dictionary) -> void:
	super.on_event(ev)
	match StringName(ev["type"]):
		&"roulette_sumo_wheel":
			clock = float(ev.get("clock", clock))
			_angle = float(ev.get("angle", _angle))
			_omega = float(ev.get("omega", _omega))
		&"roulette_sumo_ball":
			_read_ball(ev.get("ball", {}), false)
			if ball_node != null and not _is_dedicated() and Vfx.enabled():
				Audio.play_at(&"ball_roll", ball_node, -14.0, randf_range(0.8, 1.0))
		&"player_knocked_down":
			_aim_knockdown(int(ev["target"]), StringName(ev.get("cause", &"")))
	if _is_dedicated():
		return  # the dedicated server only needs the room's floor (and the tumble's direction)
	match StringName(ev["type"]):
		&"minigame_go":
			banner("SPIN!", Palette.VIP_GOLD, 1.4)
			Audio.play(&"countdown_beep", &"SFX", -4.0, 1.2)
			_say("Push them off and keep walking. Spin it up!", QuizHost.Pose.DRUMROLL)
		&"roulette_sumo_begin":
			feed("Last bean on the wheel wins", Palette.VIP_GOLD)
		&"roulette_sumo_push":
			_on_push(ev)
		&"roulette_sumo_ball_hit":
			_on_ball_hit(ev)
		&"minigame_eliminated":
			_on_out(ev)
		&"roulette_sumo_over":
			done = true
			winner = int(ev.get("winner", -1))
			_announce(ev.get("ranking", []), StringName(ev.get("reason", &"")))
	_refresh_status()


## The scene throws a bean that went over the rim outward into the pit (`_impact_dir`).
func _aim_knockdown(pid: int, cause: StringName) -> void:
	if scene == null or pid not in roster or cause != &"fell":
		return
	var a: PlayerAvatar = avatar(pid)
	if a == null:
		return
	var c: Vector3 = WheelRoom.center()
	var dir := Vector3(a.global_position.x - c.x, 0.0, a.global_position.z - c.z)
	if dir.length() > 0.01:
		scene._impact_dir[pid] = dir.normalized()


## A push went out: the pusher's arms thrust, and on contact the target slides a little.
func _on_push(ev: Dictionary) -> void:
	var by: int = int(ev["player"])
	var target: int = int(ev.get("target", -1))
	if by != local_id or _predicted_push <= 0.0:
		_push_swing(by)
	if target < 0:
		return
	var dir: Vector3 = _wire_dir(ev.get("dir", []))
	var strength: float = float(ev.get("strength", RouletteSumoLogic.PUSH_STRENGTH))
	create_tween().tween_callback(func() -> void: _shoved(target, dir, strength, false)).set_delay(AvatarVisuals.SWING_CONTACT)
	if target == local_id:
		feed("%s pushed you" % player_name(by), player_color(by))
	elif by == local_id:
		feed("You pushed %s" % player_name(target), player_color(by))


func _on_ball_hit(ev: Dictionary) -> void:
	var pid: int = int(ev["player"])
	_shoved(pid, _wire_dir(ev.get("dir", [])), float(ev.get("strength", RouletteSumoLogic.BALL_PUSH)), true)
	feed("The ball bumped %s" % player_name(pid), Palette.CREAM)
	if pid == local_id:
		banner("BUMPED!", Palette.CREAM, 0.8)
	elif randf() < 0.4:
		_say("Mind my ball, %s!" % player_name(pid), QuizHost.Pose.SURPRISED)


## Slides `pid` along `dir` (our own bean moves; a puppet only flinches, its owner moves it).
func _shoved(pid: int, dir: Vector3, strength: float, heavy: bool) -> void:
	var a: PlayerAvatar = avatar(pid)
	if a == null or not is_instance_valid(a) or pid in out or dir == Vector3.ZERO:
		return
	if a.is_standing():
		a.knockback(dir, strength, PUSH_LIFT)
	HitPop.at(self, a.global_position + Vector3(0, 1.0, 0) - dir * 0.3, 1.3 if heavy else 0.8)
	Audio.play_at(&"boing" if heavy else &"bonk", a, -6.0, randf_range(0.9, 1.1))
	if pid == local_id and scene != null:
		scene._juice(0.03, 0.25 if heavy else 0.15)


static func _wire_dir(v: Variant) -> Vector3:
	if not (v is Array) or (v as Array).size() < 2:
		return Vector3.ZERO
	var d := Vector3(float(v[0]), 0.0, float(v[1]))
	return d.normalized() if d.length() > 0.01 else Vector3.ZERO


func _on_out(ev: Dictionary) -> void:
	var cause: StringName = StringName(ev.get("cause", &""))
	var names: PackedStringArray = []
	for p: Variant in ev.get("players", []):
		var pid: int = int(p)
		if pid not in out:
			out.append(pid)
		names.append(player_name(pid))
		var a: PlayerAvatar = avatar(pid)
		if a != null and cause == &"fell":
			Audio.play_at(&"whoosh", a, -2.0, 0.7)
			Vfx.floating_text(self, a.global_position + Vector3(0, 1.8, 0), "OUT!", Palette.LOSS_RED, 120, 1.0, 1.2)
	if names.is_empty():
		return
	var place: int = int(ev.get("place", 0))
	if cause == &"dropout":
		feed("%s left the game" % " & ".join(names), Color(Palette.CREAM, 0.7))
		return
	feed("%s fell off  (#%d)" % [" & ".join(names), place], Palette.LOSS_RED)
	if local_id in ev.get("players", []):
		banner("OFF THE WHEEL!", Palette.LOSS_RED, 1.6)
		Audio.play(&"loss_sting", &"SFX", -6.0)
	var left: int = alive_players().size()
	if left > 1:
		_say("%s %s off my wheel! %d left." % [" and ".join(names), "is" if names.size() == 1 else "are", left], QuizHost.Pose.DISAPPOINTED)


func _announce(ranking: Array, reason: StringName) -> void:
	var top: Array[int] = []
	for row: Variant in ranking:
		if int(row["rank"]) == 1:
			top.append(int(row["player"]))
	if top.size() == 1:
		var w: int = top[0]
		var how: String = "CLOSEST TO THE MIDDLE" if reason == &"time" else "LAST ON THE WHEEL"
		banner("YOU WIN!" if w == local_id else "%s WINS!" % player_name(w).to_upper(), Palette.VIP_GOLD, 3.0)
		feed("%s: %s" % [player_name(w), how.to_lower()], Palette.VIP_GOLD)
		_say("%s stays on my wheel. The winner!" % player_name(w) if reason != &"time" else "Time! %s held the middle. The winner!" % player_name(w), QuizHost.Pose.HAPPY, 4.0)
		var wa: PlayerAvatar = avatar(w)
		if wa != null:
			wa.visuals.react(&"big_win")
	else:
		banner("NOBODY STAYED ON!", Palette.VIP_GOLD, 3.0)
		_say("Everyone off at once? The house keeps the wheel.", QuizHost.Pose.DISAPPOINTED, 4.0)
	Audio.play(&"quiz_winner", &"SFX", -4.0)


## The two-handed shove thrust (no bat), with a whoosh.
func _push_swing(pid: int) -> void:
	var a: PlayerAvatar = avatar(pid)
	if a == null:
		return
	a.visuals.swing()
	Audio.play_at(&"whoosh", a, -12.0, randf_range(1.15, 1.35))


# --- Per frame ----------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not going or over:
		return
	var omega: float = _omega  # eases to 0 after the end, like the rotor
	if omega <= 0.0:
		return
	var me: PlayerAvatar = local_avatar()
	if me != null and local_id in roster and local_id not in out and (me.state == PlayerAvatar.State.STANDING or me.state == PlayerAvatar.State.STUNNED):
		me.global_position = RouletteSumoLogic.drift(me.global_position, omega, delta)
	# Ragdolls this process simulates: the deck drags the parts that lie on it.
	for pid: int in roster:
		var a: PlayerAvatar = avatar(pid)
		if a == null or a.state != PlayerAvatar.State.RAGDOLL or a.ragdoll == null or not is_instance_valid(a.ragdoll) or a.ragdoll.puppet:
			continue
		for b: RigidBody3D in [a.ragdoll.torso, a.ragdoll.head, a.ragdoll.hand_l, a.ragdoll.hand_r, a.ragdoll.hips]:
			if b == null or not RouletteSumoLogic.on_deck(b.global_position) or b.global_position.y > WheelRoom.center().y + WheelRoom.WHEEL_TOP + 0.8:
				continue
			var deck_v: Vector3 = (RouletteSumoLogic.drift(b.global_position, omega, delta) - b.global_position) / delta
			var v: Vector3 = b.linear_velocity
			v.x = lerpf(v.x, deck_v.x, DECK_GRIP)
			v.z = lerpf(v.z, deck_v.z, DECK_GRIP)
			b.linear_velocity = v


func _process(delta: float) -> void:
	if going and not over and not done:
		clock = minf(clock + delta, RouletteSumoLogic.GAME_SECONDS)
		_omega = RouletteSumoLogic.omega_at(clock)
		_angle = RouletteSumoLogic.wheel_angle(clock)
	elif done or over:
		_omega = move_toward(_omega, 0.0, delta * 1.5)
		_angle += _omega * delta
	if rotor != null:
		rotor.rotation.y = wrapf(_angle, -PI, PI)
	_update_ball(delta)
	if _is_dedicated():
		return
	_cooldown = maxf(_cooldown - delta, 0.0)
	_predicted_push = maxf(_predicted_push - delta, 0.0) if _predicted_push > 0.0 else -1.0
	_update_hud()
	_speed_lines()


func _update_hud() -> void:
	if done or over:
		if clock_label != null:
			clock_label.text = "FINAL"
			clock_label.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	else:
		set_clock(RouletteSumoLogic.GAME_SECONDS - clock)
	if _gauge_fill != null:
		var f: float = RouletteSumoLogic.speed_factor(_omega)
		var t: float = RouletteSumoLogic.ramp_fraction(_omega)
		_gauge_fill.anchor_right = maxf(t, 0.02)
		_gauge_fill.color = Palette.VIP_GOLD.lerp(Palette.LOSS_RED, t * t)
		_gauge_label.text = "x%.1f" % f
		_gauge_label.add_theme_color_override(&"font_color", Palette.CREAM.lerp(Palette.LOSS_RED, t))
	_update_prompt()


## Lucky calls the speed-ups (a third, two thirds, full speed).
func _speed_lines() -> void:
	if not going or done or over or _next_mark > 3:
		return
	if RouletteSumoLogic.ramp_fraction(_omega) * 3.0 < float(_next_mark) - 0.001:
		return
	if _next_mark < 3:
		_say("Faster! The wheel's at x%.1f." % RouletteSumoLogic.speed_factor(_omega), QuizHost.Pose.SURPRISED)
	else:
		_say("Full speed! Hold on to something!", QuizHost.Pose.SURPRISED)
		banner("FULL SPEED!", Palette.LOSS_RED, 1.2)
	_next_mark += 1


func _update_prompt() -> void:
	if prompt_label == null:
		return
	if not going or over or done or local_id not in roster:
		set_prompt("")
		return
	if local_id in out:
		set_prompt("OFF THE WHEEL")
		return
	var me: PlayerAvatar = local_avatar()
	var t: int = push_target()
	if me != null and RouletteSumoLogic.flat_radius(me.global_position) > EDGE_WARN:
		set_prompt("THE EDGE!  WALK TO THE MIDDLE!")
	elif t >= 0 and _cooldown <= 0.0:
		set_prompt("PUSH %s!  [{shove}]" % player_name(t).to_upper())
	else:
		set_prompt("")


func _refresh_status() -> void:
	if status_label == null:
		return
	var on: Array[int] = alive_players()
	var lines: PackedStringArray = ["ON THE WHEEL  %d/%d" % [on.size(), roster.size()]]
	for p: int in roster:
		var who: String = "YOU" if p == local_id else player_name(p)
		var tag: String = "on"
		if p in out:
			tag = "OUT"
		elif p == winner:
			tag = "WINNER"
		lines.append("%s  %s" % [who, tag])
	status_label.text = "\n".join(lines)
	status_label.add_theme_font_size_override(&"font_size", 26)


# --- The ball -------------------------------------------------------------------------------------

func _build_ball() -> void:
	ball_node = Node3D.new()
	ball_node.name = "RouletteBall"
	add_child(ball_node)
	_ball_spin = Node3D.new()
	ball_node.add_child(_ball_spin)
	var ivory := StandardMaterial3D.new()
	ivory.albedo_color = Color(0.97, 0.95, 0.9)
	ivory.roughness = 0.18
	ivory.metallic_specular = 0.9
	ivory.clearcoat_enabled = true
	ivory.clearcoat = 0.6
	var s: MeshInstance3D = VaultArena._sphere(_ball_spin, RouletteSumoLogic.BALL_RADIUS, Vector3.ZERO, ivory)
	(s.mesh as SphereMesh).radial_segments = 32
	(s.mesh as SphereMesh).rings = 16
	s.name = "Ball"
	# A faint seam so the roll reads.
	var seam := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = RouletteSumoLogic.BALL_RADIUS - 0.012
	tm.outer_radius = RouletteSumoLogic.BALL_RADIUS + 0.012
	tm.rings = 48
	tm.ring_segments = 6
	seam.mesh = tm
	seam.material_override = GreyboxKit.material(Color(0.82, 0.78, 0.7), 0.0, 0.4)
	_ball_spin.add_child(seam)
	ball_node.global_position = _ball_world()


func _read_ball(w: Variant, snap: bool) -> void:
	if not (w is Dictionary) or not (w as Dictionary).has("p"):
		return
	var d: Dictionary = w
	var shown: Vector2 = ball_pos + _ball_offset
	ball_pos = Vector2(float(d["p"][0]), float(d["p"][1]))
	ball_vel = Vector2(float(d["v"][0]), float(d["v"][1]))
	ball_turn = float(d.get("t", 0.0))
	_ball_offset = Vector2.ZERO if snap else (shown - ball_pos).limit_length(3.0)


func _update_ball(delta: float) -> void:
	if going and not done and not over:
		var res: Array[Vector2] = RouletteSumoLogic.step_ball(ball_pos, ball_vel, ball_turn, delta)
		ball_pos = res[0]
		ball_vel = res[1]
	_ball_offset = _ball_offset.lerp(Vector2.ZERO, minf(1.0, BALL_EASE * delta))
	if ball_node == null:
		return
	ball_node.global_position = _ball_world()
	if _ball_spin != null and going and not done and not over and ball_vel.length() > 0.01:
		var axis := Vector3(ball_vel.y, 0.0, -ball_vel.x).normalized()
		_ball_spin.global_rotate(axis, ball_vel.length() * delta / RouletteSumoLogic.BALL_RADIUS)


func _ball_world() -> Vector3:
	var p: Vector2 = ball_pos + _ball_offset
	return WheelRoom.center() + Vector3(p.x, WheelRoom.WHEEL_TOP + RouletteSumoLogic.BALL_RADIUS, p.y)


# --- Overlay: the speed gauge and Lucky's line ---------------------------------------------------

func _build_gauge() -> void:
	_gauge_panel = PanelContainer.new()
	_gauge_panel.name = "SpeedGauge"
	var sb: StyleBoxFlat = plaque_style()
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 8
	sb.content_margin_bottom = 10
	_gauge_panel.add_theme_stylebox_override(&"panel", sb)
	_gauge_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_gauge_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_gauge_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_gauge_panel.offset_left = -24
	_gauge_panel.offset_right = -24
	_gauge_panel.offset_top = -36
	_gauge_panel.offset_bottom = -36
	_gauge_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gauge_panel.add_child(col)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(row)
	var tag: Label = label("WHEEL SPEED", 24, Palette.CREAM)
	tag.size_flags_vertical = Control.SIZE_SHRINK_END
	tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(tag)
	_gauge_label = label("x1.0", 44, Palette.CREAM)
	row.add_child(_gauge_label)
	var track := Panel.new()
	track.custom_minimum_size = Vector2(300, 16)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ts := StyleBoxFlat.new()
	ts.bg_color = Color(Palette.WARM_CHARCOAL, 0.9)
	ts.border_color = Color(Palette.WARM_GOLD, 0.7)
	ts.set_border_width_all(2)
	ts.set_corner_radius_all(8)
	track.add_theme_stylebox_override(&"panel", ts)
	col.add_child(track)
	_gauge_fill = ColorRect.new()
	_gauge_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gauge_fill.anchor_left = 0.0
	_gauge_fill.anchor_top = 0.0
	_gauge_fill.anchor_bottom = 1.0
	_gauge_fill.anchor_right = 0.02
	_gauge_fill.offset_left = 3
	_gauge_fill.offset_top = 3
	_gauge_fill.offset_right = -3
	_gauge_fill.offset_bottom = -3
	_gauge_fill.color = Palette.VIP_GOLD
	track.add_child(_gauge_fill)
	overlay.add_child(_gauge_panel)


func _build_host_panel() -> void:
	_host_panel = PanelContainer.new()
	_host_panel.name = "LuckyLine"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.CREAM
	sb.set_corner_radius_all(16)
	sb.set_border_width_all(3)
	sb.border_color = Palette.WARM_GOLD
	sb.content_margin_left = 16
	sb.content_margin_right = 18
	sb.content_margin_top = 6
	sb.content_margin_bottom = 8
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = 6
	_host_panel.add_theme_stylebox_override(&"panel", sb)
	_host_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_host_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_host_panel.position = Vector2(24, -40)
	_host_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_host_panel.visible = false
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_host_panel.add_child(row)
	var tag: Label = label("LUCKY", 24, Palette.VIP_BURGUNDY)
	tag.remove_theme_color_override(&"font_shadow_color")
	tag.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(tag)
	_host_label = label("", 24, Palette.CASINO_BLACK)
	_host_label.remove_theme_color_override(&"font_shadow_color")
	_host_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_host_label.custom_minimum_size = Vector2(420, 0)
	row.add_child(_host_label)
	overlay.add_child(_host_panel)


## Lucky says `text` (bottom-left line) and strikes `pose`.
func _say(text: String, pose: QuizHost.Pose = QuizHost.Pose.IDLE, hold: float = 2.2) -> void:
	if host != null:
		host.say(text)
		if pose != QuizHost.Pose.IDLE:
			host.set_pose(pose, hold)
	if _host_label == null:
		return
	_host_label.text = text
	_host_panel.visible = text != ""
	_host_panel.pivot_offset = Vector2(0, _host_panel.size.y)
	_host_panel.scale = Vector2.ONE * 0.85
	_host_panel.create_tween().tween_property(_host_panel, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
