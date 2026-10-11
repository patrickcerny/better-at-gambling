class_name PassTheBombStage
extends WalkableStage
## Client presentation of Pass the Bomb in the vault arena (a `WalkableStage`: real avatars, the
## normal camera). The bomb sits in the holder's right hand with a sputtering fuse, and a small lit
## bomb floats over their name tag; it ticks faster as it ages (the fuse itself is a server secret)
## and hisses when the server says the end is near. A blast throws the holder down (the scene's
## knockdown ragdoll), then the server walks them to the gallery. The overlay shows the game clock,
## who holds the bomb, how many are left, the elimination feed and a "TAG" prompt for the holder.

const TAG_REACH: float = PassTheBombLogic.TAG_REACH
## Tick interval when the bomb is lit, at `TICK_FULL_AGE` seconds old and after the hiss.
const TICK_SLOW: float = 0.85
const TICK_FAST: float = 0.22
const TICK_HISS: float = 0.11
const TICK_FULL_AGE: float = 18.0
## How the bomb sits in the bean's hand (upright space: y up, -z forward).
const GRIP: Vector3 = Vector3(0.0, 0.2, -0.18)

var alive: Array[int] = []
var holder: int = -1
var bomb_age: float = 0.0
var clock: float = 0.0
var hissed: bool = false
var done: bool = false
var hand_bomb: BombModel = null
var head_bomb: BombModel = null
var vignette: TextureRect = null
var _tick_in: float = 0.0
var _vignette_flash: float = 0.0


func _build_game(_start: Dictionary) -> void:
	alive = roster.duplicate()
	if overlay != null:
		vignette = TextureRect.new()
		vignette.name = "BombVignette"
		vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vignette.stretch_mode = TextureRect.STRETCH_SCALE
		var g := Gradient.new()
		g.set_color(0, Color(0.55, 0.05, 0.02, 0.0))
		g.set_color(1, Color(0.6, 0.06, 0.02, 0.7))
		g.add_point(0.6, Color(0.55, 0.05, 0.02, 0.0))
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)  # radius: the middle of each edge; the corners are deepest
		tex.width = 256
		tex.height = 256
		vignette.texture = tex
		vignette.visible = false
		overlay.add_child(vignette)
		overlay.move_child(vignette, 0)
	set_clock(PassTheBombLogic.CAP_SECONDS)
	_refresh_status()


func apply_state(st: Dictionary) -> void:
	super.apply_state(st)
	alive.assign((st.get("alive", alive) as Array).map(func(v: Variant) -> int: return int(v)))
	clock = float(st.get("clock", 0.0))
	bomb_age = float(st.get("bomb_age", 0.0))
	done = str(st.get("state", "")) == "done"
	_set_holder(int(st.get("holder", -1)))
	_refresh_status()


func alive_players() -> Array[int]:
	return alive


func action_kind() -> StringName:
	return &"tag"


func action_range() -> float:
	return TAG_REACH


func can_act() -> bool:
	return super.can_act() and holder == local_id and not done


func _on_action_sent(_kind: StringName, _target: int) -> void:
	var me: PlayerAvatar = local_avatar()
	if me != null:
		me.visuals.swing()
		Audio.play_at(&"whoosh", me, -12.0, randf_range(1.2, 1.4))


func on_event(ev: Dictionary) -> void:
	super.on_event(ev)
	if _is_dedicated():
		return  # the dedicated server only needs the room's floor
	match StringName(ev["type"]):
		&"minigame_go":
			banner("PASS THE BOMB!", Palette.VIP_GOLD, 1.6)
			Audio.play(&"countdown_beep", &"SFX", -4.0, 1.2)
		&"pass_the_bomb_new":
			alive.assign((ev.get("alive", alive) as Array).map(func(v: Variant) -> int: return int(v)))
			bomb_age = 0.0
			hissed = false
			_set_holder(int(ev["holder"]))
			if int(ev["holder"]) == local_id:
				banner("YOU HAVE THE BOMB!", Palette.LOSS_RED, 1.4)
			elif int(ev.get("bomb", 1)) > 1:
				banner("NEW BOMB!", Palette.VIP_GOLD, 1.2)
			feed("%s has the bomb" % player_name(holder), Palette.CREAM)
			Audio.play(&"chime", &"SFX", -6.0, 0.8)
		&"pass_the_bomb_passed":
			var from: int = int(ev["from"])
			var to: int = int(ev["to"])
			_set_holder(to)
			var ta: PlayerAvatar = avatar(to)
			var fa: PlayerAvatar = avatar(from)
			if fa != null and from != local_id:
				fa.visuals.swing()
			if ta != null:
				HitPop.at(self, ta.global_position + Vector3(0, 1.2, 0), 1.0)
				ta.visuals.hit(ta.global_position - (fa.global_position if fa != null else ta.global_position), 0.6)
				Audio.play_at(&"bonk", ta, -6.0, 1.3)
			feed("%s  >  %s" % [player_name(from), player_name(to)], player_color(to))
			if to == local_id:
				banner("TAGGED! PASS IT ON!", Palette.LOSS_RED, 0.9)
				if scene != null:
					scene._juice(0.03, 0.15)
			elif from == local_id:
				banner("PASSED!", Palette.MONEY_GREEN, 0.7)
		&"pass_the_bomb_hiss":
			hissed = true
			_tick_in = 0.0
			var ha: PlayerAvatar = avatar(holder)
			if ha != null:
				Audio.play_at(&"whoosh", ha, -4.0, 2.2)
				ha.say("!!", 0.8)
		&"pass_the_bomb_exploded":
			var victim: int = int(ev["player"])
			var va: PlayerAvatar = avatar(victim)
			var at: Vector3 = va.global_position if va != null else Serializer.to_vec3(ev["pos"])
			_set_holder(-1)
			_explosion(at + Vector3(0, 1.0, 0))
			banner("BOOM!  %s IS OUT" % player_name(victim).to_upper() if victim != local_id else "BOOM!  YOU'RE OUT", Palette.LOSS_RED, 1.8)
			var me: PlayerAvatar = local_avatar()
			if scene != null and me != null:
				var d: float = me.global_position.distance_to(at)
				scene._juice(0.08 if victim == local_id else 0.0, clampf(0.7 - d * 0.06, 0.1, 0.7))
		&"minigame_eliminated":
			alive.assign((ev.get("alive", alive) as Array).map(func(v: Variant) -> int: return int(v)))
			var place: int = int(ev.get("place", 0))
			for p: Variant in ev.get("players", []):
				if StringName(ev.get("cause", &"")) == &"dropout":
					feed("%s left the game" % player_name(int(p)), Color(Palette.CREAM, 0.7))
				else:
					feed("%s is out  ·  %s" % [player_name(int(p)), _ordinal(place)], Palette.LOSS_RED)
		&"pass_the_bomb_fizzled":
			_set_holder(-1)
			feed("The bomb fizzled out", Color(Palette.CREAM, 0.7))
		&"pass_the_bomb_over":
			done = true
			_set_holder(-1)
			var winners: Array = ev.get("winners", [])
			if StringName(ev.get("reason", &"")) == &"time":
				banner("TIME!  %d SURVIVORS SHARE THE WIN" % winners.size() if winners.size() != 1 else "TIME!  %s WINS" % player_name(int(winners[0])).to_upper(), Palette.VIP_GOLD, 3.0)
			elif winners.size() == 1:
				var w: int = int(winners[0])
				banner("YOU WIN!" if w == local_id else "%s WINS!" % player_name(w).to_upper(), Palette.VIP_GOLD, 3.0)
				var wa: PlayerAvatar = avatar(w)
				if wa != null:
					wa.visuals.react(&"big_win")
				Audio.play(&"quiz_winner", &"SFX", -4.0)
	_refresh_status()


func _process(delta: float) -> void:
	if going and not done and not over:
		clock = minf(clock + delta, PassTheBombLogic.CAP_SECONDS)
		set_clock(PassTheBombLogic.CAP_SECONDS - clock)
	if holder >= 0 and not done:
		bomb_age += delta
		var heat: float = 1.0 if hissed else clampf(bomb_age / TICK_FULL_AGE, 0.0, 0.85)
		for b: BombModel in [hand_bomb, head_bomb]:
			if b != null:
				b.set_heat(heat)
		_tick_in -= delta
		if _tick_in <= 0.0:
			_tick_in = TICK_HISS if hissed else lerpf(TICK_SLOW, TICK_FAST, heat / 0.85)
			_tick(heat)
	_vignette_flash = maxf(_vignette_flash - delta * 3.0, 0.0)
	if vignette != null:
		vignette.visible = holder == local_id and holder >= 0 and not done
		vignette.modulate.a = 0.6 + 0.4 * _vignette_flash
	_update_prompt()


func _tick(heat: float) -> void:
	for b: BombModel in [hand_bomb, head_bomb]:
		if b != null:
			b.pulse()
	var ha: PlayerAvatar = avatar(holder)
	if ha == null or scene == null:
		return
	if holder == local_id:
		Audio.play(&"chip_clack", &"SFX", -6.0, 1.5 + heat * 0.5)
		_vignette_flash = 1.0
	else:
		Audio.play_at(&"chip_clack", ha, -8.0, 1.5 + heat * 0.5)


func _update_prompt() -> void:
	if prompt_label == null:
		return
	if not going or over or done or holder != local_id:
		set_prompt("")
		return
	var t: int = local_target(TAG_REACH)
	set_prompt("TAG %s!  [{interact}]" % player_name(t).to_upper() if t >= 0 else "RUN AT SOMEONE TO TAG THEM!")


func _refresh_status() -> void:
	if status_label == null:
		return
	var who: String = "—"
	if holder == local_id:
		who = "YOU!"
	elif holder >= 0:
		who = player_name(holder)
	var lines: String = "BOMB: %s\nLEFT: %d / %d" % [who, alive.size(), roster.size()]
	if local_id in roster and local_id not in alive:
		lines += "\nYou're out: watch from the gallery"
	status_label.text = lines
	status_label.add_theme_color_override(&"font_color", Palette.LOSS_RED if holder == local_id else Palette.CREAM)


## Moves the bomb (hand model and the lit icon over the name tag) to `pid` (-1: nobody).
func _set_holder(pid: int) -> void:
	holder = pid
	for b: BombModel in [hand_bomb, head_bomb]:
		if b != null and is_instance_valid(b):
			var held: Node = b.get_parent()
			if held != null and held.name == "BombGrip":
				held.queue_free()
			else:
				b.queue_free()
	hand_bomb = null
	head_bomb = null
	var a: PlayerAvatar = avatar(pid)
	if a == null or done:
		return
	var grip := Node3D.new()
	grip.name = "BombGrip"
	grip.rotation.x = ItemModels.HAND_UPRIGHT
	hand_bomb = BombModel.new(0.16, true)
	hand_bomb.position = GRIP
	grip.add_child(hand_bomb)
	ItemModels.attach_to_hand(a.visuals, grip)
	if pid != local_id:
		head_bomb = BombModel.new(0.1, false)
		head_bomb.position = Vector3(0, 2.55, 0)
		a.add_child(head_bomb)


## The blast: a flash of light, a fireball, sparks and smoke, a comic word and a big bang.
func _explosion(at: Vector3) -> void:
	var root := Node3D.new()
	root.name = "BombBlast"
	add_child(root)
	root.global_position = at
	Vfx.free_after(root, 2.5)
	Audio.play_at(&"thud", root, 2.0, 0.6)
	Audio.play_at(&"tray_crash", root, -2.0, 0.8)
	if not Vfx.enabled():
		return
	HitPop.at(self, at, 2.5)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.25)
	light.light_energy = 8.0
	light.omni_range = 9.0
	root.add_child(light)
	var lt: Tween = light.create_tween()
	lt.tween_property(light, "light_energy", 0.0, 0.45)
	for layer: Array in [[Color(1.0, 0.88, 0.55, 0.95), 1.6, 0.32], [Color(0.95, 0.42, 0.12, 0.8), 2.3, 0.5]]:
		var ball := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.5
		sm.height = 1.0
		sm.radial_segments = 14
		sm.rings = 7
		ball.mesh = sm
		var m: StandardMaterial3D = Vfx.glow_material(layer[0], true)
		ball.material_override = m
		ball.scale = Vector3.ONE * 0.2
		root.add_child(ball)
		var t: Tween = ball.create_tween()
		t.set_parallel(true)
		t.tween_property(ball, "scale", Vector3.ONE * float(layer[1]) * 2.0, float(layer[2])).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_property(m, "albedo_color:a", 0.0, float(layer[2]) + 0.1).set_delay(0.08)
	_particles(root, 40, 0.9, Color(1.0, 0.85, 0.4), Color(0.9, 0.3, 0.05, 0.0), 0.11, 4.0, 9.0, Vector3(0, -9.0, 0))
	_particles(root, 14, 1.6, Color(0.42, 0.36, 0.32, 0.75), Color(0.25, 0.22, 0.2, 0.0), 0.7, 0.8, 2.2, Vector3(0, 1.2, 0))
	Vfx.floating_text(self, at + Vector3(0, 1.4, 0), "KABOOM!", Palette.CASINO_RED, 140, 1.2, 1.3)


func _particles(parent: Node3D, amount: int, life: float, from: Color, to: Color, size: float, v_min: float, v_max: float, gravity: Vector3) -> void:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE * size
	p.mesh = q
	var m: StandardMaterial3D = Vfx.glow_material(Color.WHITE, false, true)
	m.albedo_texture = Vfx.soft_dot()
	p.material_override = m
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = v_min
	p.initial_velocity_max = v_max
	p.gravity = gravity
	p.damping_min = 1.0
	p.damping_max = 3.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.6
	var g := Gradient.new()
	g.set_color(0, from)
	g.set_color(g.get_point_count() - 1, to)
	p.color_ramp = g
	p.local_coords = false
	parent.add_child(p)
	p.emitting = true


static func _ordinal(n: int) -> String:
	if n % 100 in [11, 12, 13]:
		return "%dth" % n
	match n % 10:
		1:
			return "%dst" % n
		2:
			return "%dnd" % n
		3:
			return "%drd" % n
	return "%dth" % n


## The bomb lives on an avatar outside this stage: it goes with the stage.
func _exit_tree() -> void:
	done = true
	_set_holder(-1)
