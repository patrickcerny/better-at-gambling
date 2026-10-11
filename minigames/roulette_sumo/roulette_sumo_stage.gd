class_name RouletteSumoStage
extends WalkableStage
## Client presentation of Roulette Sumo on the giant wheel (`WheelRoom`; a `WalkableStage`: real
## avatars, the normal camera). The rotor turns to the server's wheel angle and drags our own bean
## with it (`RouletteSumoLogic.drift` every physics frame, the same maths the server uses for
## frozen beans); ragdolls this process simulates are dragged by the deck too. A giant ivory ball
## rolls round the deck, predicted from the server's last segment (`step_ball`) and eased onto
## each update. Every bean carries the casino's bat; E swings it and a hit freezes the target: the
## bean goes icy blue inside a shell of ice shards with "FROZEN" over it, and its input is ignored
## (the avatar's stun) until the server thaws it. Falling off: an outward tumble into the pit,
## "OFF THE WHEEL!", then the gallery. Lucky runs the show from the croupier dais. The overlay
## shows the clock, a wheel-speed gauge (x1.0 to x4.8), who is still on, the feed, Lucky's lines
## and a context prompt (swing / edge warning / frozen).

const ICE: Color = Color("#A9D8F2")
const ICE_DEEP: Color = Color("#5FA8D3")
## Beans past this radius get an edge warning.
const EDGE_WARN: float = WheelRoom.RIM_RADIUS - 1.3
## How fast the shown ball catches up with the predicted one (1/s).
const BALL_EASE: float = 6.0
## Ragdoll parts near the deck take this share of the deck's speed per physics frame.
const DECK_GRIP: float = 0.25

var clock: float = 0.0
var done: bool = false
var winner: int = -1
var out: Array[int] = []
## pid → seconds left frozen / down (client estimates, corrected by the state).
var frozen_left: Dictionary[int, float] = {}
var down_left: Dictionary[int, float] = {}
var rotor: Node3D = null
var host: QuizHost = null
var bats: Dictionary[int, Node3D] = {}
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
var _ice: Dictionary[int, Node3D] = {}
var _cooldown: float = 0.0
var _predicted_swing: float = -1.0
var _view_bat: Node3D = null
var _gauge_fill: ColorRect = null
var _gauge_label: Label = null
var _gauge_panel: PanelContainer = null
var _host_panel: PanelContainer = null
var _host_label: Label = null
var _next_mark: int = 2
var _ice_mat: StandardMaterial3D = null


func _build_room() -> Node3D:
	var r: Node3D = WheelRoom.build(self)
	rotor = r.get_node_or_null(^"Wheel/Rotor") as Node3D
	return r


func _build_game(_start: Dictionary) -> void:
	_omega = RouletteSumoLogic.OMEGA_START
	_build_ball()
	if _is_dedicated():
		return
	_build_bats()
	host = QuizHost.new()
	host.name = "LuckyHost"
	add_child(host)
	host.position = WalkableLogicBase.ROOM_ORIGIN + WheelRoom.LUCKY_SPOT
	host.scale = Vector3.ONE * 1.2
	if overlay != null:
		_build_gauge()
		_build_host_panel()
	set_clock(RouletteSumoLogic.GAME_SECONDS)
	_say("Welcome to my wheel! Bat a bean to freeze it, dodge my ball, and don't fall off.", QuizHost.Pose.HAPPY)
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
	for p: int in out:
		_drop_player(p)
	var fz: Dictionary = st.get("frozen", {})
	for p: int in frozen_left.keys():
		if not fz.has(p) and not fz.has(str(p)):
			_thaw(p)
	for k: Variant in fz:
		_freeze(int(k), float(fz[k]))
	down_left.clear()
	var dn: Dictionary = st.get("down", {})
	for k: Variant in dn:
		down_left[int(k)] = float(dn[k])
	_refresh_status()


func alive_players() -> Array[int]:
	var res: Array[int] = []
	for p: int in roster:
		if p not in out:
			res.append(p)
	return res


func can_act() -> bool:
	return super.can_act() and not done and local_id in roster and local_id not in out and not frozen_left.has(local_id) and not down_left.has(local_id)


# --- Input --------------------------------------------------------------------------------------

## E swings the bat (cooldown shown at once; the server decides the hit).
func on_action_pressed() -> bool:
	if not can_act():
		return going and not over
	if _cooldown > 0.0:
		return true
	var target: int = swing_target()
	var payload: Dictionary = {"kind": &"swing"}
	if target >= 0:
		payload["target"] = target
	_cooldown = RouletteSumoLogic.SWING_COOLDOWN
	_predicted_swing = 0.35
	_swing_bat(local_id)
	Net.send_intent(Intents.make(&"minigame_action", payload))
	return true


## The bean the bat would freeze (the server's pick), or -1.
func swing_target() -> int:
	var me: PlayerAvatar = local_avatar()
	if me == null:
		return -1
	var candidates: Dictionary = {}
	for pid: int in alive_players():
		var a: PlayerAvatar = avatar(pid)
		if pid != local_id and a != null and not frozen_left.has(pid) and not down_left.has(pid):
			candidates[pid] = a.global_position
	return InteractionRules.pick_in_reach(me.global_position, me.facing(), candidates, local_id, RouletteSumoLogic.BAT_REACH)


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
		return  # the dedicated server only needs the room's floor (and the ragdoll pushes above)
	match StringName(ev["type"]):
		&"minigame_go":
			banner("SPIN!", Palette.VIP_GOLD, 1.4)
			Audio.play(&"countdown_beep", &"SFX", -4.0, 1.2)
			_say("No bumping, only bats. Spin it up!", QuizHost.Pose.DRUMROLL)
		&"roulette_sumo_begin":
			feed("Last bean on the wheel wins", Palette.VIP_GOLD)
		&"roulette_sumo_swing":
			var who: int = int(ev["player"])
			if who != local_id or _predicted_swing <= 0.0:
				_swing_bat(who)
			var res: StringName = StringName(ev.get("result", &""))
			if res in [&"frozen", &"thawing"]:
				var ta: PlayerAvatar = avatar(int(ev["target"]))
				if ta != null:
					Audio.play_at(&"boing", ta, -8.0, 1.4)
					Vfx.floating_text(self, ta.global_position + Vector3(0, 2.2, 0), "ALREADY ICED" if res == &"frozen" else "THAWING", Palette.CREAM, 80, 0.6, 0.8)
		&"roulette_sumo_frozen":
			_on_frozen(int(ev["player"]), int(ev["target"]), float(ev.get("seconds", RouletteSumoLogic.FREEZE_SECONDS)))
		&"roulette_sumo_thawed":
			_thaw(int(ev["player"]))
		&"roulette_sumo_ball_hit":
			_on_ball_hit(int(ev["player"]), float(ev.get("seconds", RouletteSumoLogic.KNOCK_SECONDS)))
		&"minigame_eliminated":
			_on_out(ev)
		&"roulette_sumo_over":
			done = true
			winner = int(ev.get("winner", -1))
			for p: int in frozen_left.keys():
				_thaw(p)
			_announce(ev.get("ranking", []), StringName(ev.get("reason", &"")))
	_refresh_status()


## The scene throws a downed bean's ragdoll along `_impact_dir`: away from the ball and along its
## roll for a ball hit, outward over the rim for a fall.
func _aim_knockdown(pid: int, cause: StringName) -> void:
	if scene == null or pid not in roster:
		return
	var a: PlayerAvatar = avatar(pid)
	if a == null:
		return
	var c: Vector3 = WheelRoom.center()
	var dir := Vector3.ZERO
	if cause == &"ball":
		var b: Vector3 = _ball_world()
		var away := Vector3(a.global_position.x - b.x, 0.0, a.global_position.z - b.z)
		dir = away.normalized() + Vector3(ball_vel.x, 0.0, ball_vel.y).normalized() * 1.2
	elif cause == &"fell":
		dir = Vector3(a.global_position.x - c.x, 0.0, a.global_position.z - c.z)
	if dir.length() > 0.01:
		scene._impact_dir[pid] = dir.normalized()


func _on_frozen(by: int, target: int, seconds: float) -> void:
	_freeze(target, seconds)
	var ta: PlayerAvatar = avatar(target)
	if ta != null:
		var at: Vector3 = ta.global_position + Vector3(0, 1.1, 0)
		HitPop.at(self, at, 1.2)
		Audio.play_at(&"bonk", ta, 0.0, randf_range(0.65, 0.75))
		Audio.play_at(&"chime", ta, -6.0, 1.6)
		Vfx.floating_text(self, at + Vector3(0, 0.6, 0), "FREEZE!", ICE, 110, 0.9, 1.0)
		var ba: PlayerAvatar = avatar(by)
		if ba != null:
			ta.visuals.hit(ta.global_position - ba.global_position, 0.8)
	feed("%s  froze  %s" % [player_name(by), player_name(target)], player_color(by))
	if target == local_id:
		banner("FROZEN!", ICE, 1.0)
		if scene != null:
			scene._juice(0.05, 0.35)
	elif by == local_id:
		banner("FROZE %s!" % player_name(target).to_upper(), ICE, 0.9)
		if scene != null:
			scene._juice(0.04, 0.15)


func _on_ball_hit(pid: int, seconds: float) -> void:
	down_left[pid] = seconds
	_thaw(pid)
	var a: PlayerAvatar = avatar(pid)
	if a != null:
		HitPop.at(self, a.global_position + Vector3(0, 1.0, 0), 1.6)
		Audio.play_at(&"bonk", a, 2.0, 0.5)
		Vfx.floating_text(self, a.global_position + Vector3(0, 2.0, 0), "BOWLED!", Palette.CREAM, 110, 0.9, 1.0)
	feed("The ball flattened %s" % player_name(pid), Palette.CREAM)
	if pid == local_id:
		banner("BOWLED OVER!", Palette.LOSS_RED, 1.0)
	elif randf() < 0.5:
		_say("Strike! Mind my ball, %s." % player_name(pid), QuizHost.Pose.SURPRISED)


func _on_out(ev: Dictionary) -> void:
	var cause: StringName = StringName(ev.get("cause", &""))
	var names: PackedStringArray = []
	for p: Variant in ev.get("players", []):
		var pid: int = int(p)
		if pid not in out:
			out.append(pid)
		names.append(player_name(pid))
		_drop_player(pid)
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


# --- Freeze -------------------------------------------------------------------------------------

func _freeze(pid: int, seconds: float) -> void:
	if pid in out or seconds <= 0.0:
		return
	frozen_left[pid] = seconds
	var a: PlayerAvatar = avatar(pid)
	if a == null:
		return
	a.stun(seconds)  # no input until the server thaws them (the server refuses moves anyway)
	if _is_dedicated() or (_ice.has(pid) and is_instance_valid(_ice[pid])):
		return
	if _ice_mat == null:
		_ice_mat = StandardMaterial3D.new()
		_ice_mat.albedo_color = Color(ICE, 0.45)
		_ice_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ice_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_ice_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for n: Node in a.visuals.find_children("*", "GeometryInstance3D", true, false):
		(n as GeometryInstance3D).material_overlay = _ice_mat
	var shell := Node3D.new()
	shell.name = "IceShell"
	add_child(shell)
	var shard_mat := StandardMaterial3D.new()
	shard_mat.albedo_color = Color(ICE.lightened(0.3), 0.42)
	shard_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shard_mat.roughness = 0.08
	shard_mat.metallic_specular = 1.0
	shard_mat.emission_enabled = true
	shard_mat.emission = ICE_DEEP
	shard_mat.emission_energy_multiplier = 0.25
	for i: int in 7:
		var s := MeshInstance3D.new()
		var pm := PrismMesh.new()
		var h: float = 0.7 + 0.25 * float(i % 3)
		pm.size = Vector3(0.32, h, 0.26)
		s.mesh = pm
		s.material_override = shard_mat
		var ang: float = TAU * float(i) / 7.0
		s.position = Vector3(sin(ang) * 0.42, h * 0.5 + 0.05 * float(i % 2), cos(ang) * 0.42)
		s.rotation = Vector3(0.25 * cos(ang), ang, 0.25 * sin(ang))
		shell.add_child(s)
	var tag := Label3D.new()
	tag.name = "FrozenTag"
	tag.text = "FROZEN"
	tag.font = Vfx.font()
	tag.font_size = 64
	tag.pixel_size = 0.006
	tag.modulate = ICE
	tag.outline_modulate = Palette.CASINO_BLACK
	tag.outline_size = 14
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.position = Vector3(0, 2.5, 0)
	shell.add_child(tag)
	shell.global_position = a.global_position
	shell.scale = Vector3.ONE * 0.2
	shell.create_tween().tween_property(shell, "scale", Vector3.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_ice[pid] = shell


func _thaw(pid: int) -> void:
	var was: bool = frozen_left.has(pid)
	frozen_left.erase(pid)
	var a: PlayerAvatar = avatar(pid)
	if a != null and is_instance_valid(a):
		for n: Node in a.visuals.find_children("*", "GeometryInstance3D", true, false):
			if (n as GeometryInstance3D).material_overlay == _ice_mat:
				(n as GeometryInstance3D).material_overlay = null
		if was and a.state == PlayerAvatar.State.STUNNED:
			a.stunned_until = -INF  # input back at once
	var shell: Node3D = _ice.get(pid, null)
	_ice.erase(pid)
	if shell != null and is_instance_valid(shell):
		if Vfx.enabled() and was and a != null:
			Audio.play_at(&"chip_clack", a, -6.0, 1.6)
		shell.queue_free()


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
	_predicted_swing = maxf(_predicted_swing - delta, 0.0) if _predicted_swing > 0.0 else -1.0
	for p: int in frozen_left.keys():
		frozen_left[p] -= delta
		if frozen_left[p] <= -1.0:
			_thaw(p)  # the server's thaw got lost
	for p: int in down_left.keys():
		down_left[p] -= delta
		if down_left[p] <= -1.0:
			down_left.erase(p)
	for p: int in _ice:
		var a: PlayerAvatar = avatar(p)
		if a != null and is_instance_valid(_ice[p]):
			_ice[p].global_position = a.global_position
	_update_view_bat()
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
		var t: float = clampf((_omega - RouletteSumoLogic.OMEGA_START) / (RouletteSumoLogic.OMEGA_MAX - RouletteSumoLogic.OMEGA_START), 0.0, 1.0)
		_gauge_fill.anchor_right = maxf(t, 0.02)
		_gauge_fill.color = Palette.VIP_GOLD.lerp(Palette.LOSS_RED, t * t)
		_gauge_label.text = "x%.1f" % f
		_gauge_label.add_theme_color_override(&"font_color", Palette.CREAM.lerp(Palette.LOSS_RED, t))
	_update_prompt()


## Lucky calls the speed-ups (x2, x3, x4, full speed).
func _speed_lines() -> void:
	if not going or done or over:
		return
	var f: float = RouletteSumoLogic.speed_factor(_omega)
	if _next_mark <= 4 and f >= float(_next_mark):
		_say("Faster! The wheel's at x%d." % _next_mark if _next_mark < 4 else "Full speed! Hold on to something!", QuizHost.Pose.SURPRISED)
		if _next_mark == 4:
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
	if frozen_left.has(local_id):
		set_prompt("FROZEN!  YOU'RE SLIDING...")
		return
	if down_left.has(local_id):
		set_prompt("")
		return
	var me: PlayerAvatar = local_avatar()
	var t: int = swing_target()
	if t >= 0 and _cooldown <= 0.0:
		set_prompt("FREEZE %s!  [{interact}]" % player_name(t).to_upper())
	elif me != null and RouletteSumoLogic.flat_radius(me.global_position) > EDGE_WARN:
		set_prompt("THE EDGE!  GET TO THE MIDDLE!")
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
		elif frozen_left.has(p):
			tag = "FROZEN"
		elif down_left.has(p):
			tag = "DOWN"
		lines.append("%s  %s" % [who, tag])
	status_label.text = "\n".join(lines)
	status_label.add_theme_font_size_override(&"font_size", 26)


func _drop_player(p: int) -> void:
	_thaw(p)
	down_left.erase(p)
	_remove_bat(p)


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


# --- Bats -----------------------------------------------------------------------------------------

func _build_bats() -> void:
	for p: int in roster:
		var a: PlayerAvatar = avatar(p)
		if a == null:
			continue
		var bat: Node3D = ItemModels.make_held(&"baseball_bat")
		bat.name = "SumoBat"
		ItemModels.attach_to_hand(a.visuals, bat)
		bats[p] = bat


## The bat whips round (the casino bat's swing, as in Bat Heist).
func _swing_bat(pid: int) -> void:
	var a: PlayerAvatar = avatar(pid)
	if a == null:
		return
	a.visuals.swing()
	Audio.play_at(&"whoosh", a, -8.0, randf_range(0.8, 0.95))
	if pid == local_id and _view_bat != null and is_instance_valid(_view_bat):
		var base: Vector3 = _view_bat.rotation
		var vt: Tween = _view_bat.create_tween()
		vt.tween_property(_view_bat, "rotation", base + Vector3(0.3, 0.0, 0.9), 0.08)
		vt.tween_property(_view_bat, "rotation", base + Vector3(-0.4, 0.0, -1.2), 0.13).set_ease(Tween.EASE_IN)
		vt.tween_property(_view_bat, "rotation", base, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var bat: Node3D = bats.get(pid, null)
	if bat == null or not is_instance_valid(bat):
		return
	var rest := Vector3(ItemModels.HAND_UPRIGHT, 0.0, 0.0)
	var t: Tween = bat.create_tween()
	t.tween_property(bat, "rotation", rest + Vector3(-0.5, 0.0, 1.1), 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(bat, "rotation", rest + Vector3(0.25, 0.0, -1.5), 0.13).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(bat, "rotation", rest, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _update_view_bat() -> void:
	var me: PlayerAvatar = local_avatar()
	var want: bool = me != null and me.cam != null and me.cam.mode == PlayerCamera.Mode.FIRST and bats.has(local_id) and not done and not over
	if want and (_view_bat == null or not is_instance_valid(_view_bat)):
		_view_bat = ItemModels.make_view(&"baseball_bat")
		_view_bat.name = "SumoViewBat"
		me.cam.camera.add_child(_view_bat)
	elif not want and _view_bat != null:
		if is_instance_valid(_view_bat):
			_view_bat.queue_free()
		_view_bat = null


func _remove_bat(pid: int) -> void:
	var bat: Node3D = bats.get(pid, null)
	if bat != null and is_instance_valid(bat):
		bat.queue_free()
	bats.erase(pid)


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


## Bats and ice live on avatars outside this stage: they go with it.
func _exit_tree() -> void:
	done = true
	for p: int in frozen_left.keys():
		_thaw(p)
	for p: int in bats.keys():
		_remove_bat(p)
	if _view_bat != null and is_instance_valid(_view_bat):
		_view_bat.queue_free()
	_view_bat = null
