class_name DodgeTheDiceStage
extends WalkableStage
## Client presentation of Dodge the Dice on the tilted roulette board (`ClimbRoom` "board"; a
## `WalkableStage`: real avatars, the normal camera). Our own bean climbs slower uphill
## (`SLOPE_UPHILL`) and is pushed down while it stands in a brass slide chute (`CHUTE_SPEED`, the
## same idea as Roulette Sumo's drift: the reported positions carry the slide). Hazards are
## announced once by the server and rolled here with the shared `DodgeTheDiceLogic.path_at`: ivory
## roulette balls, big gold coins rolling on edge and red casino dice tumbling row by row, each
## with a soft shadow on the felt. A hit throws the ragdoll downhill (the slide-back); the server
## moves the bean to where the slide ends. Lucky hosts from the podium by the WINNER rail. The
## overlay: the clock, a vertical progress ladder with every bean's marker, the finish order, the
## feed, Lucky's line and a context prompt.

## Uphill walking speed factor on the board.
const SLOPE_UPHILL: float = 0.6
## Flat speed a chute pushes a bean downhill (m/s).
const CHUTE_SPEED: float = 7.5
## How fast a hazard's shown height follows a drop down a ledge (1/s).
const DROP_EASE: float = 16.0
const LADDER_H: float = 420.0
const MARKER: float = 30.0
const DIE_RED: Color = Color("#B3262B")

var clock: float = 0.0
var done: bool = false
var winner: int = -1
var finish_groups: Array = []
var down_left: Dictionary[int, float] = {}
var last_call_left: float = -1.0
var host: QuizHost = null
## id → hazard wire dict, id → its node, id → shown height and last row (sound per hop).
var hazards: Dictionary[int, Dictionary] = {}
var hazard_nodes: Dictionary[int, Node3D] = {}
var _shown_y: Dictionary[int, float] = {}
var _last_row: Dictionary[int, int] = {}
var _models: Node3D = null
var _ladder: PanelContainer = null
var _ladder_track: Control = null
var _markers: Dictionary[int, Control] = {}
var _host_panel: PanelContainer = null
var _host_label: Label = null
var _status_left: float = 0.0
var _said_halfway: bool = false
var _ivory: StandardMaterial3D = null
var _gold: StandardMaterial3D = null
var _die_mat: StandardMaterial3D = null
var _pip_mat: StandardMaterial3D = null
var _shadow_mat: StandardMaterial3D = null


func _build_room() -> Node3D:
	return ClimbRoom.build(self, "board")


func _build_game(_start: Dictionary) -> void:
	_models = Node3D.new()
	_models.name = "Hazards"
	add_child(_models)
	if _is_dedicated():
		return
	host = QuizHost.new()
	host.name = "LuckyHost"
	add_child(host)
	host.position = WalkableLogicBase.ROOM_ORIGIN + ClimbRoom.lucky_spot() + Vector3(0, 0.3, 0)
	host.scale = Vector3.ONE * 1.3
	if overlay != null:
		_build_ladder()
		_build_host_panel()
	set_clock(DodgeTheDiceLogic.GAME_SECONDS)
	_say("Welcome to my board! First to the top wins. Jump the ledges and dodge what I roll.", QuizHost.Pose.HAPPY)
	_refresh_status()


func apply_state(st: Dictionary) -> void:
	super.apply_state(st)
	clock = float(st.get("clock", clock))
	done = str(st.get("state", "")) == "done"
	winner = int(st.get("winner", -1))
	finish_groups.clear()
	for g: Variant in st.get("finish", []):
		var grp: Array[int] = []
		for p: Variant in g:
			grp.append(int(p))
		finish_groups.append(grp)
	var live: Dictionary = {}
	for h: Variant in st.get("hazards", []):
		var d: Dictionary = h
		live[int(d["id"])] = true
		_add_hazard(d)
	for hid: int in hazards.keys():
		if not live.has(hid):
			_remove_hazard(hid, false)
	down_left.clear()
	var dn: Dictionary = st.get("down", {})
	for k: Variant in dn:
		down_left[int(k)] = float(dn[k])
	last_call_left = float(st.get("last_call", -1.0))
	_refresh_status()


func is_up(pid: int) -> bool:
	for g: Array in finish_groups:
		if pid in g:
			return true
	return false


func finish_place(pid: int) -> int:
	var place: int = 1
	for g: Array in finish_groups:
		if pid in g:
			return place
		place += g.size()
	return 0


## Height of a bean (0..1): finishers 1, else from the body we see.
func height_of(pid: int) -> float:
	if is_up(pid):
		return 1.0
	var a: PlayerAvatar = avatar(pid)
	return ClimbRoom.progress(a.global_position) if a != null else 0.0


func alive_players() -> Array[int]:
	return roster


func can_act() -> bool:
	return false  # no action button: climb, jump, shove


# --- Events -------------------------------------------------------------------------------------

func on_event(ev: Dictionary) -> void:
	super.on_event(ev)
	match StringName(ev["type"]):
		&"dodge_the_dice_clock":
			clock = float(ev.get("clock", clock))
		&"dodge_the_dice_hazard":
			_add_hazard(ev)
		&"player_knocked_down":
			_aim_knockdown(int(ev["target"]), StringName(ev.get("cause", &"")))
	if _is_dedicated():
		return  # the dedicated server only needs the board's collision (and the pushes above)
	match StringName(ev["type"]):
		&"minigame_go":
			banner("CLIMB!", Palette.VIP_GOLD, 1.4)
			Audio.play(&"countdown_beep", &"SFX", -4.0, 1.2)
			_say("Roll 'em! Balls, coins and dice, coming down.", QuizHost.Pose.DRUMROLL)
		&"dodge_the_dice_begin":
			feed("First to the top wins", Palette.VIP_GOLD)
		&"dodge_the_dice_hit":
			_on_hit(int(ev["player"]), StringName(ev.get("kind", &"")), float(ev.get("seconds", DodgeTheDiceLogic.KNOCK_SECONDS)))
		&"dodge_the_dice_top":
			_on_top(ev)
		&"dodge_the_dice_last_call":
			last_call_left = float(ev.get("seconds", DodgeTheDiceLogic.LAST_CALL))
			banner("LAST CALL!", Palette.LOSS_RED, 1.4)
			Audio.play(&"last_call_bell", &"SFX", -6.0)
			var left: Array[int] = []
			for p: int in roster:
				if not is_up(p):
					left.append(p)
			if left.size() == 1:
				_say("Last call, %s! Ten seconds to the top!" % player_name(left[0]), QuizHost.Pose.SURPRISED)
		&"minigame_eliminated":
			if StringName(ev.get("cause", &"")) == &"dropout":
				for p: Variant in ev.get("players", []):
					feed("%s left the game" % player_name(int(p)), Color(Palette.CREAM, 0.7))
		&"dodge_the_dice_over":
			done = true
			winner = int(ev.get("winner", -1))
			_announce(ev.get("ranking", []), StringName(ev.get("reason", &"")))
	_refresh_status()


## A hazard hit throws the ragdoll downhill (the slide back), a little to the side it rolled.
func _aim_knockdown(pid: int, cause: StringName) -> void:
	if scene == null or pid not in roster or cause not in DodgeTheDiceLogic.KINDS:
		return
	scene._impact_dir[pid] = Vector3(randf_range(-0.25, 0.25), 0.0, 1.0).normalized()


func _on_hit(pid: int, kind: StringName, seconds: float) -> void:
	down_left[pid] = seconds
	var a: PlayerAvatar = avatar(pid)
	var word: String = {&"ball": "ROLLED!", &"coin": "FLATTENED!", &"dice": "SNAKE EYES!"}.get(kind, "BONK!")
	if a != null:
		HitPop.at(self, a.global_position + Vector3(0, 1.0, 0), 1.5)
		Audio.play_at(&"bonk", a, 1.0, 0.55 if kind == &"coin" else 0.8)
		if kind == &"coin":
			Audio.play_at(&"coin", a, -4.0, 0.7)
		Vfx.floating_text(self, a.global_position + Vector3(0, 2.0, 0), word, Palette.CREAM, 100, 0.9, 1.0)
	var what: String = {&"ball": "a roulette ball", &"coin": "a giant coin", &"dice": "a die"}.get(kind, "something")
	feed("%s got hit by %s" % [player_name(pid), what], player_color(pid))
	if pid == local_id:
		banner("SLIDING BACK!", Palette.LOSS_RED, 1.0)
		if scene != null:
			scene._juice(0.05, 0.4)
	elif randf() < 0.35:
		_say("Down you go, %s!" % player_name(pid), QuizHost.Pose.SURPRISED)


func _on_top(ev: Dictionary) -> void:
	var place: int = int(ev.get("place", 1))
	var names: PackedStringArray = []
	for p: Variant in ev.get("players", []):
		var pid: int = int(p)
		var placed: bool = false
		for g: Array in finish_groups:
			if pid in g:
				placed = true
		if not placed:
			var grp: Array[int] = []
			for q: Variant in ev.get("players", []):
				grp.append(int(q))
			finish_groups.append(grp)
		names.append(player_name(pid))
		var a: PlayerAvatar = avatar(pid)
		if a != null:
			HitPop.at(self, a.global_position + Vector3(0, 1.2, 0), 1.2)
			Vfx.floating_text(self, a.global_position + Vector3(0, 2.3, 0), "#%d" % place, Palette.VIP_GOLD, 130, 1.2, 1.4)
			a.visuals.react(&"big_win" if place == 1 else &"win")
		if pid == local_id:
			banner("YOU MADE IT!  #%d" % place, Palette.VIP_GOLD, 2.0)
			Audio.play(&"big_win" if place == 1 else &"minor_win", &"SFX", -4.0)
	feed("%s reached the top  (#%d)" % [" & ".join(names), place], Palette.VIP_GOLD)
	if place == 1:
		_say("%s is first to the top!" % " and ".join(names), QuizHost.Pose.HAPPY)
		if local_id not in ev.get("players", []):
			banner("%s IS UP!" % " & ".join(names).to_upper(), Palette.VIP_GOLD, 1.4)
		Audio.play(&"chime", &"SFX", -4.0)
	elif randf() < 0.6:
		_say("%s made it! Number %d." % [" and ".join(names), place], QuizHost.Pose.HAPPY)


func _announce(ranking: Array, reason: StringName) -> void:
	var top: Array[int] = []
	for row: Variant in ranking:
		if int(row["rank"]) == 1:
			top.append(int(row["player"]))
	if top.size() == 1:
		var w: int = top[0]
		banner("YOU WIN!" if w == local_id else "%s WINS!" % player_name(w).to_upper(), Palette.VIP_GOLD, 3.0)
		var how: String = "first to the top" if is_up(w) else "highest on the board"
		feed("%s: %s" % [player_name(w), how], Palette.VIP_GOLD)
		if is_up(w):
			_say("%s climbed my board first. The winner!" % player_name(w), QuizHost.Pose.HAPPY, 4.0)
		else:
			_say("Time! Nobody made it, but %s got highest. The winner!" % player_name(w), QuizHost.Pose.HAPPY, 4.0)
		var wa: PlayerAvatar = avatar(w)
		if wa != null:
			wa.visuals.react(&"big_win")
	else:
		banner("A TIE AT THE TOP!", Palette.VIP_GOLD, 3.0)
		_say("Dead heat! %s share it." % " and ".join(top.map(func(p: int) -> String: return player_name(p))), QuizHost.Pose.SURPRISED, 4.0)
	if reason == &"time":
		Audio.play(&"buzzer", &"SFX", -8.0)
	Audio.play(&"quiz_winner", &"SFX", -4.0)


# --- Per frame ------------------------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	var me: PlayerAvatar = local_avatar()
	if me == null or local_id not in roster:
		return
	if not going or over or done or me.state != PlayerAvatar.State.STANDING:
		me.speed_multiplier = 1.0
		return
	var at: Vector3 = me.global_position
	var on_board: bool = ClimbKit.over_flight(ClimbRoom.flight(), at)
	me.speed_multiplier = SLOPE_UPHILL if on_board and me.velocity.z < -0.2 else 1.0
	if on_board and me.is_on_floor() and ClimbRoom.in_chute(at):
		me.push_velocity = Vector3(0.0, 0.0, CHUTE_SPEED)


func _process(delta: float) -> void:
	if going and not over and not done:
		clock = minf(clock + delta, DodgeTheDiceLogic.GAME_SECONDS)
	_update_hazards(delta)
	if _is_dedicated():
		return
	for p: int in down_left.keys():
		down_left[p] -= delta
		if down_left[p] <= -1.0:
			down_left.erase(p)
	if last_call_left > 0.0 and not done:
		last_call_left = maxf(last_call_left - delta, 0.0)
	if done or over:
		if clock_label != null:
			clock_label.text = "FINAL"
			clock_label.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	elif last_call_left > 0.0:
		set_clock(minf(last_call_left, DodgeTheDiceLogic.GAME_SECONDS - clock))
	else:
		set_clock(DodgeTheDiceLogic.GAME_SECONDS - clock)
	if not _said_halfway and going and clock >= DodgeTheDiceLogic.GAME_SECONDS * 0.5 and not done:
		_said_halfway = true
		_say("Halfway! I'm rolling them faster now.", QuizHost.Pose.DRUMROLL)
	_update_ladder()
	_update_prompt()
	_status_left -= delta
	if _status_left <= 0.0:
		_status_left = 0.3
		_refresh_status()


func _update_prompt() -> void:
	if prompt_label == null:
		return
	if not going or over or done or local_id not in roster:
		set_prompt("")
		return
	if is_up(local_id):
		set_prompt("YOU'RE UP!  #%d" % finish_place(local_id))
		return
	if down_left.has(local_id):
		set_prompt("")
		return
	var me: PlayerAvatar = local_avatar()
	if me == null:
		set_prompt("")
		return
	var at: Vector3 = me.global_position
	if ClimbRoom.in_chute(at):
		set_prompt("SLIDE CHUTE!  JUMP OUT  [{jump}]")
	elif _incoming(at):
		set_prompt("INCOMING!  DODGE OR JUMP  [{jump}]")
	elif ClimbRoom.progress(at) < 0.02 and clock < 10.0:
		set_prompt("CLIMB!  JUMP THE LEDGES  [{jump}]")
	elif ClimbRoom.progress(at) > 0.9:
		set_prompt("ALMOST THERE!")
	else:
		set_prompt("")


## True if a hazard is rolling at `at` from up to 7 m uphill, in its lane.
func _incoming(at: Vector3) -> bool:
	for hid: int in hazards:
		var hp: Vector3 = DodgeTheDiceLogic.path_at(hazards[hid], clock)
		var dz: float = at.z - hp.z
		if dz > 0.0 and dz < 7.0 and absf(at.x - hp.x) < DodgeTheDiceLogic.radius_of(StringName(hazards[hid]["kind"])) + 0.9:
			return true
	return false


func _refresh_status() -> void:
	if status_label == null:
		return
	var lines: PackedStringArray = ["TO THE TOP"]
	var place: int = 1
	for g: Array in finish_groups:
		for p: int in g:
			lines.append("#%d  %s" % [place, "YOU" if p == local_id else player_name(p)])
		place += g.size()
	var rest: Array[int] = []
	for p: int in roster:
		if not is_up(p):
			rest.append(p)
	rest.sort_custom(func(a: int, b: int) -> bool: return height_of(a) > height_of(b))
	for p: int in rest:
		var tag: String = "DOWN" if down_left.has(p) else "%d%%" % roundi(height_of(p) * 100.0)
		lines.append("%s  %s" % ["YOU" if p == local_id else player_name(p), tag])
	status_label.text = "\n".join(lines)
	status_label.add_theme_font_size_override(&"font_size", 26)


# --- Hazards --------------------------------------------------------------------------------------

func _add_hazard(w: Dictionary) -> void:
	if not w.has("id"):
		return
	var hid: int = int(w["id"])
	if hazards.has(hid):
		return
	var h: Dictionary = {"id": hid, "kind": str(w["kind"]), "lane": float(w["lane"]), "speed": float(w["speed"]), "t0": float(w["t0"]), "seed": int(w["seed"])}
	if clock >= DodgeTheDiceLogic.end_time(h):
		return
	hazards[hid] = h
	if _is_dedicated():
		return
	var n: Node3D = _make_hazard(StringName(h["kind"]), int(h["seed"]))
	_models.add_child(n)
	hazard_nodes[hid] = n
	var p: Vector3 = DodgeTheDiceLogic.path_at(h, clock)
	n.global_position = p
	_shown_y[hid] = p.y
	_last_row[hid] = -2
	if Vfx.enabled():
		Audio.play_at(&"chip_clack", n, -6.0, 0.6)


func _remove_hazard(hid: int, gutter: bool) -> void:
	hazards.erase(hid)
	_shown_y.erase(hid)
	_last_row.erase(hid)
	var n: Node3D = hazard_nodes.get(hid, null)
	hazard_nodes.erase(hid)
	if n == null or not is_instance_valid(n):
		return
	if gutter and Vfx.enabled():
		# Down through the grate.
		var t: Tween = n.create_tween()
		t.tween_property(n, "position:y", n.position.y - 1.2, 0.3).set_ease(Tween.EASE_IN)
		t.tween_callback(n.queue_free)
	else:
		n.queue_free()


func _update_hazards(delta: float) -> void:
	var me: PlayerAvatar = local_avatar()
	for hid: int in hazards.keys():
		var h: Dictionary = hazards[hid]
		if clock >= DodgeTheDiceLogic.end_time(h):
			_remove_hazard(hid, true)
			continue
		var n: Node3D = hazard_nodes.get(hid, null)
		if n == null or not is_instance_valid(n):
			continue
		var p: Vector3 = DodgeTheDiceLogic.path_at(h, clock)
		var y: float = _shown_y.get(hid, p.y)
		y = p.y if p.y >= y else lerpf(y, p.y, minf(1.0, DROP_EASE * delta))
		_shown_y[hid] = y
		var prev: Vector3 = n.global_position
		n.global_position = Vector3(p.x, y, p.z)
		_spin(n, StringName(h["kind"]), n.global_position - prev, int(h["seed"]))
		var sh: Node3D = n.get_node_or_null(^"Shadow") as Node3D
		if sh != null:
			sh.global_position = Vector3(p.x, ClimbRoom.surface_y(p.z) + 0.04, p.z)
		var row: int = ClimbKit.row_at(ClimbRoom.flight(), p.z)
		if row != int(_last_row.get(hid, row)) and me != null and Vfx.enabled() and me.global_position.distance_to(p) < 14.0:
			match StringName(h["kind"]):
				&"dice":
					Audio.play_at(&"chip_clack", n, -8.0, randf_range(0.5, 0.65))
				&"coin":
					Audio.play_at(&"coin", n, -14.0, randf_range(0.6, 0.7))
				_:
					Audio.play_at(&"plink", n, -14.0, randf_range(0.7, 0.8))
		_last_row[hid] = row


## Rolls the model along its motion: balls and coins roll downhill, dice tumble.
func _spin(n: Node3D, kind: StringName, moved: Vector3, seed_value: int) -> void:
	var body: Node3D = n.get_node_or_null(^"Body") as Node3D
	if body == null:
		return
	var dist: float = Vector2(moved.x, moved.z).length()
	if dist < 0.0001 or dist > 3.0:
		return
	var r: float = DodgeTheDiceLogic.radius_of(kind)
	match kind:
		&"ball":
			var axis := Vector3(moved.z, 0.0, -moved.x).normalized()
			body.global_rotate(axis, dist / r)
		&"coin":
			body.rotate_object_local(Vector3.RIGHT, dist / r)
			n.rotation.z = clampf(-moved.x / maxf(dist, 0.001) * 0.5, -0.45, 0.45)
		&"dice":
			body.rotate_object_local(Vector3.RIGHT, dist / r * 0.8)
			body.rotate_object_local(Vector3.UP, dist * (0.6 if seed_value % 2 == 0 else -0.6))


func _make_hazard(kind: StringName, seed_value: int) -> Node3D:
	_ensure_materials()
	var n := Node3D.new()
	n.name = "Hazard"
	var body := Node3D.new()
	body.name = "Body"
	n.add_child(body)
	var r: float = DodgeTheDiceLogic.radius_of(kind)
	match kind:
		&"ball":
			var s: MeshInstance3D = VaultArena._sphere(body, r, Vector3.ZERO, _ivory)
			(s.mesh as SphereMesh).radial_segments = 24
			(s.mesh as SphereMesh).rings = 12
			var seam := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = r - 0.008
			tm.outer_radius = r + 0.008
			tm.rings = 32
			tm.ring_segments = 4
			seam.mesh = tm
			seam.material_override = GreyboxKit.material(Color(0.82, 0.78, 0.7), 0.0, 0.4)
			body.add_child(seam)
		&"coin":
			# On its edge: the disc's axis along x, rolling about it.
			var disc := Node3D.new()
			disc.rotation.z = PI * 0.5
			body.add_child(disc)
			ParlorRoom._cyl(disc, r, 0.16, Vector3.ZERO, _gold, 36)
			for side: float in [-1.0, 1.0]:
				var rim := MeshInstance3D.new()
				var tm := TorusMesh.new()
				tm.inner_radius = r - 0.09
				tm.outer_radius = r - 0.02
				tm.rings = 36
				tm.ring_segments = 6
				rim.mesh = tm
				rim.material_override = _gold
				rim.position.y = side * 0.08
				disc.add_child(rim)
				var face := Label3D.new()
				face.text = "$"
				face.font = Vfx.font()
				face.font_size = 160
				face.pixel_size = 0.005
				face.modulate = Palette.WARM_GOLD.darkened(0.35)
				face.outline_size = 0
				face.shaded = true
				face.double_sided = false
				face.position.y = side * 0.085
				face.rotation = Vector3(-side * PI * 0.5, 0.0, 0.0)
				disc.add_child(face)
		_:
			var cube := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3.ONE * r * 2.0
			cube.mesh = bm
			cube.material_override = _die_mat
			body.add_child(cube)
			_pips(body, r)
			body.rotation = Vector3(float(seed_value % 4) * PI * 0.5, float((seed_value / 4) % 4) * PI * 0.5, 0.0)
	var shadow := MeshInstance3D.new()
	shadow.name = "Shadow"
	var cm := CylinderMesh.new()
	cm.top_radius = r * 1.05
	cm.bottom_radius = r * 1.05
	cm.height = 0.01
	cm.radial_segments = 20
	shadow.mesh = cm
	shadow.material_override = _shadow_mat
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shadow.rotation.x = ClimbKit.tread_angle(ClimbRoom.flight())
	shadow.top_level = true
	n.add_child(shadow)
	return n


## Cream pips on the die's six faces (opposite faces sum to seven).
func _pips(body: Node3D, r: float) -> void:
	var faces: Array = [[Vector3.UP, 1], [Vector3.DOWN, 6], [Vector3.RIGHT, 3], [Vector3.LEFT, 4], [Vector3.BACK, 2], [Vector3.FORWARD, 5]]
	var spots: Dictionary = {
		1: [Vector2.ZERO], 2: [Vector2(-1, -1), Vector2(1, 1)], 3: [Vector2(-1, -1), Vector2.ZERO, Vector2(1, 1)],
		4: [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)],
		5: [Vector2(-1, -1), Vector2(1, -1), Vector2.ZERO, Vector2(-1, 1), Vector2(1, 1)],
		6: [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 0), Vector2(1, 0), Vector2(-1, 1), Vector2(1, 1)],
	}
	for f: Array in faces:
		var normal: Vector3 = f[0]
		var u: Vector3 = Vector3.RIGHT if absf(normal.x) < 0.5 else Vector3.BACK
		var v: Vector3 = normal.cross(u)
		for s: Vector2 in spots[int(f[1])]:
			var pip: MeshInstance3D = VaultArena._sphere(body, r * 0.15, normal * r + (u * s.x + v * s.y) * r * 0.5, _pip_mat)
			pip.scale = Vector3.ONE - normal.abs() * 0.7


func _ensure_materials() -> void:
	if _ivory != null:
		return
	_ivory = StandardMaterial3D.new()
	_ivory.albedo_color = Color(0.97, 0.95, 0.9)
	_ivory.roughness = 0.18
	_ivory.metallic_specular = 0.9
	_ivory.clearcoat_enabled = true
	_ivory.clearcoat = 0.6
	_gold = StandardMaterial3D.new()
	_gold.albedo_color = Palette.VIP_GOLD
	_gold.metallic = 0.4
	_gold.roughness = 0.3
	_gold.emission_enabled = true
	_gold.emission = Palette.WARM_GOLD
	_gold.emission_energy_multiplier = 0.18
	_die_mat = StandardMaterial3D.new()
	_die_mat.albedo_color = DIE_RED
	_die_mat.roughness = 0.2
	_die_mat.clearcoat_enabled = true
	_die_mat.clearcoat = 0.8
	_pip_mat = GreyboxKit.material(Palette.CREAM, 0.0, 0.4)
	_shadow_mat = StandardMaterial3D.new()
	_shadow_mat.albedo_color = Color(0.0, 0.0, 0.0, 0.32)
	_shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


# --- Overlay: the progress ladder and Lucky's line ----------------------------------------------

func _build_ladder() -> void:
	_ladder = PanelContainer.new()
	_ladder.name = "ClimbLadder"
	var sb: StyleBoxFlat = plaque_style()
	sb.content_margin_top = 10
	sb.content_margin_bottom = 12
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	_ladder.add_theme_stylebox_override(&"panel", sb)
	_ladder.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_ladder.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_ladder.grow_vertical = Control.GROW_DIRECTION_BOTH
	_ladder.offset_left = -24
	_ladder.offset_right = -24
	_ladder.offset_top = 40
	_ladder.offset_bottom = 40
	_ladder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ladder.add_child(col)
	var top: Label = label("TOP", 24, Palette.VIP_GOLD)
	top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(top)
	_ladder_track = Control.new()
	_ladder_track.custom_minimum_size = Vector2(96, LADDER_H)
	_ladder_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_ladder_track)
	# The rail with a rung per row and a gold band for the landing.
	var rail := ColorRect.new()
	rail.color = Color(Palette.WARM_GOLD, 0.8)
	rail.position = Vector2(46, 0)
	rail.size = Vector2(4, LADDER_H)
	rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ladder_track.add_child(rail)
	for i: int in ClimbRoom.ROWS + 1:
		var rung := ColorRect.new()
		rung.color = Color(Palette.CREAM, 0.35 if i > 0 and i < ClimbRoom.ROWS else 0.9)
		rung.size = Vector2(28 if i > 0 and i < ClimbRoom.ROWS else 56, 2)
		rung.position = Vector2(48 - rung.size.x * 0.5, LADDER_H * (1.0 - float(i) / float(ClimbRoom.ROWS)) - 1.0)
		rung.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ladder_track.add_child(rung)
	var start: Label = label("START", 18, Color(Palette.CREAM, 0.7))
	start.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(start)
	for p: int in roster:
		var m := Panel.new()
		var ms := StyleBoxFlat.new()
		ms.bg_color = player_color(p)
		ms.set_corner_radius_all(int(MARKER * 0.5))
		ms.set_border_width_all(3 if p == local_id else 2)
		ms.border_color = Palette.CREAM if p == local_id else Palette.CASINO_BLACK
		m.add_theme_stylebox_override(&"panel", ms)
		var size_px: float = MARKER + (6.0 if p == local_id else 0.0)
		m.size = Vector2(size_px, size_px)
		m.position = Vector2(48.0 - size_px * 0.5, LADDER_H - size_px * 0.5)
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var initial: Label = label(player_name(p).left(1).to_upper(), 18, Palette.CASINO_BLACK)
		initial.remove_theme_color_override(&"font_shadow_color")
		initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		initial.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		m.add_child(initial)
		_ladder_track.add_child(m)
		_markers[p] = m
	overlay.add_child(_ladder)


func _update_ladder() -> void:
	if _ladder_track == null:
		return
	# Markers at the same height fan out sideways so every head shows.
	var order: Array[int] = roster.duplicate()
	order.sort_custom(func(a: int, b: int) -> bool: return height_of(a) > height_of(b))
	var prev_y: float = -INF
	var shift: int = 0
	for p: int in order:
		var m: Control = _markers.get(p, null)
		if m == null:
			continue
		var y: float = LADDER_H * (1.0 - height_of(p)) - m.size.y * 0.5
		shift = shift + 1 if absf(y - prev_y) < MARKER * 0.6 else 0
		prev_y = y
		var x: float = 48.0 - m.size.x * 0.5 + (float((shift + 1) / 2) * MARKER * 0.7 * (1.0 if shift % 2 == 1 else -1.0))
		m.position = m.position.lerp(Vector2(x, y), 0.25)
		m.modulate.a = 0.55 if down_left.has(p) else 1.0
		if p == local_id:
			m.move_to_front()


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


## The local bean's speed factor lives on the avatar outside this stage: reset it.
func _exit_tree() -> void:
	done = true
	var me: PlayerAvatar = local_avatar()
	if me != null and is_instance_valid(me):
		me.speed_multiplier = 1.0
