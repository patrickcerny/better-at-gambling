class_name LastSeatStage
extends WalkableStage
## Client presentation of Last Seat at the Table in the parlor (`ParlorRoom`; a `WalkableStage`:
## real avatars, the normal camera). Lucky the cat stands by a gramophone on the dais and runs the
## show: while the record spins the floor music plays and the stools wait tucked under the table;
## when the music stops (a needle scratch, a whistle, Lucky's jump and a "GRAB A SEAT!" banner) the
## stools shoot out to where the server put them, each with a pulsing gold ring on the floor. A
## claimed stool's ring takes the sitter's colour and the bean sits (the avatar's seated pose, the
## camera eases behind the stool). Whoever is left standing is out: a red "OUT!" and off to the
## gallery. Between rounds the seated get up, a stool sinks into the floor and the record spins
## again. The overlay shows the round and stools left (clock plaque), who sits, stands or is out
## (top left), the feed, Lucky's lines (bottom left) and a context prompt.
##
## The server decides every claim; this side only sends `minigame_action {kind: "sit", target}`
## when E is pressed near a free stool (running onto one claims it on the server by itself).

const SIT_REACH: float = LastSeatLogic.SIT_REACH
## How fast the stools glide to where they belong (per second, exponential).
const STOOL_SPEED: float = 10.0
const FLOOR_MUSIC: String = "res://audio/music/casino_base.ogg"

var round_no: int = 0
var music_on: bool = false
var scramble: bool = false
var done: bool = false
var stool_count: int = 0
## This round's stools (world floor positions) once the music stopped.
var stool_spots: Array[Vector3] = []
## pid → stool index for the beans sitting now.
var seated: Dictionary[int, int] = {}
var out: Array[int] = []
var grace_left: float = 0.0
var winner: int = -1
var host: QuizHost = null
var stools: Array[Node3D] = []
var rings: Array[MeshInstance3D] = []
var _record: Node3D = null
var _music: AudioStreamPlayer = null
var _music_fade: Tween = null
## pid → [seat marker, camera anchor] while seated.
var _seat_nodes: Dictionary[int, Array] = {}
var _host_panel: PanelContainer = null
var _host_label: Label = null
var _t: float = 0.0


func _build_room() -> Node3D:
	return ParlorRoom.build(self)


func _build_game(_start: Dictionary) -> void:
	stool_count = maxi(roster.size() - 1, 1)
	for i: int in stool_count:
		var s: Node3D = ParlorRoom.make_stool()
		s.name = "Stool%d" % i
		add_child(s)
		s.position = _tuck_spot(i, stool_count)
		stools.append(s)
		var ring := MeshInstance3D.new()
		ring.name = "StoolRing%d" % i
		var tm := TorusMesh.new()
		tm.inner_radius = 0.42
		tm.outer_radius = 0.55
		tm.rings = 32
		tm.ring_segments = 4
		ring.mesh = tm
		ring.material_override = Vfx.glow_material(Palette.VIP_GOLD)
		ring.scale = Vector3(1.0, 0.08, 1.0)
		ring.visible = false
		add_child(ring)
		rings.append(ring)
	if room != null:
		_record = room.get_node_or_null(^"Gramophone/Record") as Node3D
	if _is_dedicated():
		return
	host = QuizHost.new()
	host.name = "LuckyHost"
	add_child(host)
	host.position = WalkableLogicBase.ROOM_ORIGIN + ParlorRoom.LUCKY_SPOT
	host.scale = Vector3.ONE * 1.1
	_music = AudioStreamPlayer.new()
	_music.name = "FloorMusic"
	_music.bus = &"Music"
	if ResourceLoader.exists(FLOOR_MUSIC):
		var stream: AudioStream = load(FLOOR_MUSIC)
		if stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
		_music.stream = stream
	add_child(_music)
	MusicMood.stage_music = true
	if overlay != null:
		_build_host_panel()
	_say("Welcome to my parlor! When the music stops, grab a stool. One short every round!", QuizHost.Pose.HAPPY)
	_refresh_hud()


func apply_state(st: Dictionary) -> void:
	super.apply_state(st)
	round_no = int(st.get("round", round_no))
	var s: String = str(st.get("state", ""))
	done = s == "done"
	scramble = s == "scramble"
	stool_count = int(st.get("stool_count", stool_count))
	grace_left = float(st.get("grace", 0.0))
	winner = int(st.get("winner", -1))
	out.clear()
	for g: Variant in st.get("out", []):
		for p: Variant in g:
			out.append(int(p))
	_read_stools(st.get("stools", []))
	_set_music(bool(st.get("music", false)) and going, false)
	var now: Dictionary = st.get("seated", {})
	for pid: int in seated.keys():
		if not now.has(pid) and not now.has(str(pid)):
			_unseat(pid)
	for k: Variant in now:
		var pid: int = int(k)
		var i: int = int(now[k])
		if seated.get(pid, -1) != i and i < stool_spots.size():
			_seat(pid, i)
	_refresh_hud()


func alive_players() -> Array[int]:
	var res: Array[int] = []
	for p: int in roster:
		if p not in out:
			res.append(p)
	return res


func action_kind() -> StringName:
	return &"sit"


func action_range() -> float:
	return SIT_REACH


func can_act() -> bool:
	return super.can_act() and scramble and not done and local_id in roster and local_id not in out and not seated.has(local_id)


## A seated local bean sits with a free cursor like at a casino table (Escape still pauses).
func input_mode() -> InputRouter.Mode:
	if going and not over and seated.has(local_id):
		return InputRouter.Mode.SEATED
	return super.input_mode()


## E: claim the free stool nearest to us in reach (the server checks with its own positions).
func on_action_pressed() -> bool:
	if not can_act():
		return going and not over
	var stool: int = local_stool()
	var payload: Dictionary = {"kind": &"sit"}
	if stool >= 0:
		payload["target"] = stool
	Net.send_intent(Intents.make(&"minigame_action", payload))
	return true


## The free stool nearest to the local bean within reach, or -1.
func local_stool() -> int:
	var me: PlayerAvatar = local_avatar()
	if me == null or not scramble:
		return -1
	var best: int = -1
	var best_d: float = SIT_REACH
	for i: int in stool_spots.size():
		if i in seated.values():
			continue
		var d: Vector3 = stool_spots[i] - me.global_position
		d.y = 0.0
		if d.length() <= best_d:
			best_d = d.length()
			best = i
	return best


# --- Events -------------------------------------------------------------------------------------

func on_event(ev: Dictionary) -> void:
	var type: StringName = StringName(ev["type"])
	if type == &"minigame_player_moved" and seated.has(int(ev["player"])):
		var pid: int = int(ev["player"])
		var to: Vector3 = Serializer.to_vec3(ev["pos"])
		if to.distance_to(_seat_pos(seated[pid])) < 0.6:
			return  # the server pinning a bean we already sat on that stool
		_unseat(pid)
	super.on_event(ev)
	match type:
		&"minigame_go":
			if not _is_dedicated():
				banner("LAST SEAT!", Palette.VIP_GOLD, 1.4)
				Audio.play(&"countdown_beep", &"SFX", -4.0, 1.2)
			_set_music(round_no > 0 and not scramble and not done, true)
		&"last_seat_round":
			_on_round(int(ev["round"]), int(ev["stools"]))
		&"last_seat_stop":
			_on_stop(ev.get("stools", []), float(ev.get("grace", LastSeatLogic.GRACE)))
		&"last_seat_sat":
			_on_sat(int(ev["player"]), int(ev["stool"]))
		&"last_seat_round_over":
			_on_round_over(ev.get("out", []))
		&"minigame_eliminated":
			for p: Variant in ev.get("players", []):
				if int(p) not in out:
					out.append(int(p))
				if seated.has(int(p)):
					_unseat(int(p))
				if StringName(ev.get("cause", &"")) == &"dropout":
					feed("%s left the game" % player_name(int(p)), Color(Palette.CREAM, 0.7))
		&"last_seat_winner":
			_on_winner(int(ev.get("player", -1)))
		&"rewards_started":
			_set_music(false, false)
			_stand_everyone()
	_refresh_hud()


func _on_round(n: int, count: int) -> void:
	round_no = n
	scramble = false
	stool_count = count
	stool_spots.clear()
	for pid: int in seated.keys():
		_unseat(pid)
	_set_music(going, true)
	if _is_dedicated():
		return
	if n > 1:
		feed("Round %d: %d stool%s left" % [n, count, "" if count == 1 else "s"], Palette.VIP_GOLD)
		_say("Round %d! %d stool%s for %d beans. Music!" % [n, count, "" if count == 1 else "s", alive_players().size()], QuizHost.Pose.HAPPY)
		Audio.play(&"thud", &"SFX", -6.0, 0.8)  # a stool sinks into the floor
	else:
		_say("%d stool%s for %d beans. Keep walking round the table..." % [count, "" if count == 1 else "s", alive_players().size()], QuizHost.Pose.IDLE)


func _on_stop(wire: Array, grace: float) -> void:
	_read_stools(wire)
	scramble = true
	grace_left = grace
	_set_music(false, true)
	if _is_dedicated():
		return
	banner("GRAB A SEAT!", Palette.VIP_GOLD, 1.6)
	Audio.play(&"whistle", &"SFX", -2.0)
	Audio.play(&"whoosh", &"SFX", -6.0, 0.8)
	_say("The music stopped! SIT DOWN!", QuizHost.Pose.SURPRISED)
	if scene != null:
		scene._juice(0.0, 0.25)


func _on_sat(pid: int, stool: int) -> void:
	_seat(pid, stool)
	if _is_dedicated():
		return
	var a: PlayerAvatar = avatar(pid)
	if a != null:
		Audio.play_at(&"thud", a, -4.0, 1.3)
		Vfx.floating_text(self, _seat_pos(stool) + Vector3(0, 1.9, 0), "SAFE!", Palette.MONEY_GREEN, 90, 0.7, 1.0)
	feed("%s grabbed a stool" % player_name(pid), player_color(pid))
	if pid == local_id:
		banner("SAFE!", Palette.MONEY_GREEN, 1.0)
		Audio.play(&"chime", &"SFX", -4.0, 1.2)


func _on_round_over(standing: Array) -> void:
	scramble = false
	if _is_dedicated():
		return
	if standing.is_empty():
		_say("Everyone found a seat! Again!", QuizHost.Pose.HAPPY)
		return
	var names: PackedStringArray = []
	for p: Variant in standing:
		var pid: int = int(p)
		names.append(player_name(pid))
		var a: PlayerAvatar = avatar(pid)
		if a != null:
			Vfx.floating_text(self, a.global_position + Vector3(0, 2.1, 0), "OUT!", Palette.LOSS_RED, 110, 0.9, 1.2)
			a.visuals.react(&"loss")
		if pid == local_id:
			banner("NO SEAT! YOU'RE OUT", Palette.LOSS_RED, 2.0)
	Audio.play(&"loss_sting", &"SFX", -6.0)
	feed("%s: no seat, out!" % ", ".join(names), Palette.LOSS_RED)
	_say("%s %s left standing. Out!" % [" and ".join(names), "is" if names.size() == 1 else "are"], QuizHost.Pose.DISAPPOINTED)


func _on_winner(pid: int) -> void:
	done = true
	scramble = false
	winner = pid
	_set_music(false, false)
	if _is_dedicated():
		return
	if pid < 0:
		banner("NOBODY SAT DOWN!", Palette.CREAM, 3.0)
		_say("Nobody sat? The house wins this one.", QuizHost.Pose.DISAPPOINTED)
		return
	var a: PlayerAvatar = avatar(pid)
	if a != null:
		a.visuals.react(&"big_win")
	banner("YOU GOT THE LAST SEAT!" if pid == local_id else "%s GETS THE LAST SEAT!" % player_name(pid).to_upper(), Palette.VIP_GOLD, 3.0)
	_say("The last seat at the table goes to %s!" % player_name(pid), QuizHost.Pose.HAPPY, 4.0)
	Audio.play(&"quiz_winner", &"SFX", -4.0)


# --- Stools and seats ---------------------------------------------------------------------------

func _read_stools(wire: Array) -> void:
	stool_spots.clear()
	for v: Variant in wire:
		stool_spots.append(Serializer.to_vec3(v))
	if not stool_spots.is_empty():
		stool_count = stool_spots.size()


## Under the table, evenly round the pedestal (a stool tucked in).
func _tuck_spot(i: int, count: int) -> Vector3:
	var a: float = TAU * float(i) / float(maxi(count, 1)) + 0.4
	return ParlorRoom.table_center() + Vector3(sin(a), 0.0, cos(a)) * ParlorRoom.TUCK_RADIUS


func _seat_pos(stool: int) -> Vector3:
	return stool_spots[stool] + Vector3(0, ParlorRoom.SEAT_HEIGHT, 0) if stool >= 0 and stool < stool_spots.size() else Vector3.INF


## Sits `pid` on stool `stool`: the avatar's seated pose on a marker at the seat, and (for us) the
## camera eased to a spot behind the stool looking over the table.
func _seat(pid: int, stool: int) -> void:
	if stool < 0 or stool >= stool_spots.size():
		return
	if seated.has(pid):
		_unseat(pid)
	seated[pid] = stool
	var a: PlayerAvatar = avatar(pid)
	if a == null:
		return
	var pos: Vector3 = _seat_pos(stool)
	var yaw: float = ParlorRoom.yaw_to_table(stool_spots[stool])
	var marker := Node3D.new()
	marker.name = "Seat%d" % pid
	add_child(marker)
	marker.global_position = pos
	marker.rotation.y = yaw
	var anchor := Node3D.new()
	anchor.name = "SeatCam%d" % pid
	add_child(anchor)
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	anchor.global_position = pos - fwd * 2.2 + Vector3(0, 1.5, 0)
	anchor.rotation = Vector3(deg_to_rad(-18.0), yaw, 0.0)
	anchor.set_meta(&"yaw_limit", 1.6)
	_seat_nodes[pid] = [marker, anchor]
	if a.state == PlayerAvatar.State.RAGDOLL:
		a.end_ragdoll(pos)
	elif a.state == PlayerAvatar.State.HELD:
		a.release_held()
	a.sit(marker, anchor)
	if a.drive == PlayerAvatar.Drive.PUPPET:
		a.target_position = pos
	if pid == local_id:
		_apply_input_mode()


## Gets `pid` off their stool where they are (the server's move puts them next to it).
func _unseat(pid: int) -> void:
	seated.erase(pid)
	var a: PlayerAvatar = avatar(pid)
	if a != null and a.state == PlayerAvatar.State.SEATED:
		var spot: Vector3 = a.global_position
		a.seat = null  # stand right here: the server says where to go next
		a.stand()
		var owned: bool = a.is_local or a.drive != PlayerAvatar.Drive.PUPPET
		if owned:
			a.teleport(Vector3(spot.x, 0.0, spot.z))
	if _seat_nodes.has(pid):
		for n: Variant in _seat_nodes[pid]:
			if is_instance_valid(n):
				(n as Node).queue_free()
		_seat_nodes.erase(pid)
	if pid == local_id:
		_apply_input_mode()


## The game is over: everyone stands up next to their stool (the rewards and the regroup take the
## bodies from there).
func _stand_everyone() -> void:
	for pid: int in seated.keys():
		var stool: int = seated[pid]
		_unseat(pid)
		if stool < stool_spots.size():
			var a: PlayerAvatar = avatar(pid)
			if a != null and (a.is_local or a.drive != PlayerAvatar.Drive.PUPPET):
				a.teleport(ParlorRoom.stand_spot(stool_spots[stool]))


func _update_stools(delta: float) -> void:
	var k: float = 1.0 - exp(-STOOL_SPEED * delta)
	var pulse: float = 0.5 + 0.5 * sin(_t * 7.0)
	var taken: Array = seated.values()
	for i: int in stools.size():
		var s: Node3D = stools[i]
		var target: Vector3
		var shown: bool = i < stool_count
		if not stool_spots.is_empty() and i < stool_spots.size():
			target = stool_spots[i]
		elif shown:
			target = _tuck_spot(i, stool_count)
		else:
			target = _tuck_spot(i, stools.size()) + Vector3(0, -0.7, 0)  # sunk away
		s.position = s.position.lerp(target, k) if s.position.distance_to(target) < 8.0 else target
		s.visible = shown or s.position.y > -0.6
		if not stool_spots.is_empty() and i < stool_spots.size():
			s.rotation.y = lerp_angle(s.rotation.y, ParlorRoom.yaw_to_table(stool_spots[i]), k)
		var ring: MeshInstance3D = rings[i]
		ring.visible = shown and i < stool_spots.size() and (scramble or i in taken)
		if ring.visible:
			ring.position = Vector3(s.position.x, 0.03, s.position.z)
			var sitter: int = seated.find_key(i) if i in taken else -1
			var mat: StandardMaterial3D = ring.material_override as StandardMaterial3D
			if sitter >= 0:
				mat.albedo_color = player_color(sitter)
				ring.scale = Vector3(1.0, 0.08, 1.0)
			else:
				mat.albedo_color = Palette.VIP_GOLD
				ring.scale = Vector3(1.0 + 0.12 * pulse, 0.08, 1.0 + 0.12 * pulse)


# --- Music --------------------------------------------------------------------------------------

## Starts (from a random bar) or stops the floor music; `scratch` stops it with a needle scratch.
func _set_music(on: bool, scratch: bool) -> void:
	if on == music_on:
		return
	music_on = on
	if host != null:
		host.set_pose(QuizHost.Pose.DRUMROLL if on else QuizHost.Pose.SURPRISED, 0.0 if on else 1.6)
	if _music == null or _music.stream == null:
		return
	if _music_fade != null and _music_fade.is_valid():
		_music_fade.kill()
	if on:
		_music.pitch_scale = 1.0
		_music.volume_db = 0.0
		_music.play(randf() * maxf(_music.stream.get_length() - 4.0, 0.0))
		return
	if not _music.playing:
		return
	if not scratch:
		_music_fade = _music.create_tween()
		_music_fade.tween_property(_music, "volume_db", -40.0, 0.6)
		_music_fade.tween_callback(_music.stop)
		return
	# The needle comes off: the record winds down in a blink, then silence.
	_music_fade = _music.create_tween().set_parallel(true)
	_music_fade.tween_property(_music, "pitch_scale", 0.35, 0.28).set_ease(Tween.EASE_IN)
	_music_fade.tween_property(_music, "volume_db", -30.0, 0.3).set_ease(Tween.EASE_IN)
	_music_fade.chain().tween_callback(_music.stop)
	Audio.play(&"slip", &"SFX", -6.0, 1.6)


# --- Per frame ----------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	if scramble and not done and not over:
		grace_left = maxf(grace_left - delta, 0.0)
	_update_stools(delta)
	if _record != null and music_on:
		_record.rotate_y(delta * 3.5)
	_update_clock()
	_update_prompt()


func _update_clock() -> void:
	if clock_label == null:
		return
	if done or over:
		clock_label.text = "FINAL"
		clock_label.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
	elif scramble:
		set_clock(grace_left)
		clock_label.add_theme_color_override(&"font_color", Palette.LOSS_RED)
	else:
		clock_label.text = "ROUND %d" % maxi(round_no, 1)
		clock_label.add_theme_color_override(&"font_color", Palette.CREAM)


func _update_prompt() -> void:
	if prompt_label == null:
		return
	if not going or over or done or local_id not in roster or local_id in out:
		set_prompt("")
	elif seated.has(local_id):
		set_prompt("SAFE ON YOUR STOOL")
	elif music_on:
		set_prompt("KEEP WALKING ROUND THE TABLE...")
	elif scramble and local_stool() >= 0:
		set_prompt("SIT!  [{interact}]")
	elif scramble:
		set_prompt("RUN FOR A STOOL!")
	else:
		set_prompt("")


func _refresh_hud() -> void:
	if status_label == null:
		return
	var free: int = stool_spots.size() - seated.size() if scramble else stool_count
	var lines: PackedStringArray = ["ROUND %d  ·  %d STOOL%s" % [maxi(round_no, 1), maxi(free, 0), "" if free == 1 else "S"]]
	for p: int in roster:
		var who: String = "YOU" if p == local_id else player_name(p)
		var tag: String = "OUT" if p in out else ("SEATED" if seated.has(p) else ("WINNER" if p == winner else "standing"))
		lines.append("%s  %s" % [who, tag])
	status_label.text = "\n".join(lines)
	status_label.add_theme_font_size_override(&"font_size", 26)


# --- Lucky ----------------------------------------------------------------------------------------

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


## Seated poses and the floor music live outside this stage's nodes: undo them when it goes.
func _exit_tree() -> void:
	MusicMood.stage_music = false
	for pid: int in seated.keys():
		var a: PlayerAvatar = avatar(pid)
		if a != null and is_instance_valid(a) and a.state == PlayerAvatar.State.SEATED:
			a.seat = null
			a.stand()
	seated.clear()
	if _music != null:
		_music.stop()
