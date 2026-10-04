class_name MatchScene
extends Node3D
## The casino match as the player sees it: the Lucky Lounge, one avatar per player, HUD, station
## overlays, guards, hazards and loose chips. In Practice it also hosts the in-process
## MatchServer (through `Net`, so nothing here knows whether the server is local). Every money or
## knockout decision comes from server events; this scene only shows them and reports what the
## physics world did (`report_knockout`, `report_pickup`, `report_thrown_out`).

const MATCH_SCENE_PATH: String = "res://match/match_scene.tscn"
const RESULTS_PATH: String = "res://ui/menus/main_menu.tscn"

var map: LuckyLounge
var server: MatchServer = null
var view: ClientMatchView
var hud: Hud
var router: InputRouter
var emote_wheel: EmoteWheel
var ui_layer: CanvasLayer
var world_root: Node3D
var local: PlayerAvatar = null
var local_id: int = -1
var cfg: BalanceConfig
var avatars: Dictionary[int, PlayerAvatar] = {}
var piles: Dictionary[int, ChipPile] = {}
var guards: Array[Guard] = []
var station_uis: Dictionary[StringName, StationUi] = {}
var current_ui: StationUi = null
var nearest_station: StationBase = null
var results_panel: PanelContainer = null
## Scripted driver (--autoplay); null in normal play.
var autoplay: Node = null

var _ko_until: Dictionary[int, float] = {}
var _ragdoll_attacker: Dictionary[int, int] = {}
var _respawn_at: Dictionary[int, float] = {}
var _clock: float = 0.0
var _vip_toast_at: float = -INF
var _door_angle: float = 0.0
var _owns_server: bool = false
var _plinko_seen: Dictionary[int, bool] = {}


func _ready() -> void:
	cfg = Registry.balance
	var cmd: Cmdline = SceneRouter.cmdline if SceneRouter.cmdline != null else Cmdline.from_os()
	map = LuckyLounge.new()
	map.name = "LuckyLounge"
	add_child(map)
	world_root = Node3D.new()
	world_root.name = "World"
	add_child(world_root)
	router = InputRouter.new()
	router.name = "InputRouter"
	add_child(router)
	ui_layer = CanvasLayer.new()
	ui_layer.name = "UI"
	add_child(ui_layer)
	hud = Hud.new()
	hud.name = "Hud"
	ui_layer.add_child(hud)
	for pair: Array in [[&"blackjack", BlackjackUi.new()], [&"roulette", RouletteUi.new()], [&"slots", SlotsUi.new()], [&"plinko", PlinkoUi.new()]]:
		var ui: StationUi = pair[1]
		ui.name = String(pair[0]).capitalize() + "Ui"
		ui.visible = false
		ui.rejected.connect(func(err: StringName) -> void: hud.toast(StationUi.rejection_text(err), 1.5))
		ui_layer.add_child(ui)
		station_uis[pair[0]] = ui
	emote_wheel = EmoteWheel.new()
	emote_wheel.name = "EmoteWheel"
	emote_wheel.picked.connect(func(id: StringName) -> void: Net.send_intent(Intents.make(&"emote", {"id": id})))
	ui_layer.add_child(emote_wheel)
	if Net.mode == Net.Mode.NONE:
		_start_local(cmd)
	else:
		server = Net.local_server
	local_id = Net.local_player_id
	view = ClientMatchView.new()
	view.name = "ClientView"
	add_child(view)
	hud.bind(view.state, local_id)
	view.state.station_changed.connect(_on_station_state)
	Net.event_received.connect(_on_event)
	_spawn_avatars()
	_connect_router()
	if _owns_server:
		server.start_match()
	_spawn_guards()
	if cmd.has_flag("autoplay"):
		var driver: Script = load("res://client/autoplay_driver.gd")
		autoplay = driver.new()
		autoplay.name = "Autoplay"
		add_child(autoplay)
	Audio.play_music(&"casino_loop")
	if cmd.has_flag("third-person") and local != null:
		local.cam.toggle_mode()
	if cmd.has("autosit"):
		_autosit(StringName(cmd.get_string("autosit")))
	Log.info(&"match", "match scene ready: %d players, local=%d" % [avatars.size(), local_id])


func _exit_tree() -> void:
	if Net.event_received.is_connected(_on_event):
		Net.event_received.disconnect(_on_event)
	if _owns_server:
		Net.stop()


## Dev/screenshots: walk up to a station after the intro and sit down (`--autosit blackjack_1`).
func _autosit(sid: StringName) -> void:
	await get_tree().create_timer(3.4).timeout
	if not is_inside_tree() or local == null or not map.stations.has(sid):
		return
	var st: StationBase = map.stations[sid]
	var seat: Vector3 = st.seat_position(0)
	var out: Vector3 = seat + (seat - st.global_position).normalized() * 0.8
	out.y = st.global_position.y
	local.teleport(out, atan2(-(st.global_position.x - out.x), -(st.global_position.z - out.z)))
	_report_position(local_id)
	await get_tree().physics_frame
	Net.send_intent(Intents.make(&"sit", {"station": sid}))


## Practice: host the server in-process with bots standing around.
func _start_local(cmd: Cmdline) -> void:
	server = MatchServer.new()
	server.name = "MatchServer"
	add_child(server)
	var def: MapDefinition = Registry.maps[&"lucky_lounge"].duplicate() as MapDefinition
	def.station_positions = map.station_positions()
	def.spawn_points = map.spawn_points()
	var settings: Dictionary = {"duration": cmd.get_int("duration", 10), "seed": cmd.get_int("seed", randi() % 1000000), "items_enabled": true}
	server.configure(settings, cfg, Registry.presets, Registry.game_logic_scripts(), def)
	_owns_server = true
	var player_name: String = str(Settings.get_value("profile", "name", "You"))
	var id: int = Net.start_local(server, player_name)
	server.set_server_position(id, def.spawn_points[0])
	var bots: int = clampi(cmd.get_int("bots", 3), 0, 7)
	for i: int in bots:
		var bid: int = server.add_player("bot-%d" % (i + 1), ["Chip", "Lucky", "Dice", "Ace", "Penny", "Bluff", "Royal"][i % 7], true)
		server.set_server_position(bid, def.spawn_points[(i + 1) % def.spawn_points.size()] + Vector3(0, 0, -3.0))


func _spawn_avatars() -> void:
	view.resync()
	for pid: int in view.state.players:
		_spawn_avatar(pid, view.state.players[pid])
	local = avatars.get(local_id, null)
	if local != null:
		local.cam.activate()
		hud.set_crosshair_visible(true)


func _spawn_avatar(pid: int, p: Dictionary) -> PlayerAvatar:
	if avatars.has(pid):
		return avatars[pid]
	var a := PlayerAvatar.new()
	a.name = "Player%d" % pid
	a.player_id = pid
	a.display_name = str(p.get("name", "Player"))
	a.color = Palette.player_color(int(p.get("color", pid - 1)))
	a.is_local = pid == local_id
	a.cfg = cfg
	a.router = router if a.is_local else null
	var pos: Vector3 = Serializer.to_vec3(p.get("pos", [0, 0, 0]))
	if pos == Vector3.ZERO:
		pos = map.spawn_points()[(pid - 1) % map.spawn_points().size()]
	a.position = pos
	a.yaw = 0.0  # yaw 0 looks down −z: into the casino from the entrance
	a.target_yaw = 0.0
	world_root.add_child(a)
	a.target_position = pos
	a.landed.connect(func(drop: float) -> void: _on_landed(pid, drop))
	a.ragdoll_impact.connect(func(strength: float, wall: bool) -> void: _on_ragdoll_impact(pid, strength, wall))
	a.ragdoll_settled.connect(func() -> void: _on_ragdoll_settled(pid))
	avatars[pid] = a
	return a


func _spawn_guards() -> void:
	if not map.navmesh_ready:
		await map.get_tree().physics_frame
		while is_inside_tree() and not map.navmesh_ready:
			await get_tree().physics_frame
		if not is_inside_tree():
			return
	for i: int in LuckyLounge.GUARD_ROUTES.size():
		var g := Guard.new()
		g.name = "Guard%d" % (i + 1)
		g.guard_id = StringName("guard_%d" % (i + 1))
		var route: Array[Vector3] = []
		for p: Vector3 in LuckyLounge.GUARD_ROUTES[i]:
			route.append(p)
		g.route = route
		g.caught.connect(func(pid: int) -> void: _on_guard_caught(g, pid))
		world_root.add_child(g)
		guards.append(g)


func _connect_router() -> void:
	router.look.connect(func(rel: Vector2) -> void:
		if local != null and local.cam != null:
			local.cam.look(rel.x, rel.y))
	router.interact.connect(_on_interact)
	router.leave_station.connect(func() -> void:
		if local != null and local.state == PlayerAvatar.State.SEATED:
			Net.send_intent(Intents.make(&"leave")))
	router.grab_pressed.connect(_on_grab)
	router.grab_released.connect(func() -> void:
		if _local_holding() >= 0:
			Net.send_intent(Intents.make(&"release", {"throw": false})))
	router.shove.connect(func() -> void:
		if local == null:
			return
		if _local_holding() >= 0:
			Net.send_intent(Intents.make(&"release", {"throw": true, "aim": Serializer.vec3(local.aim())}))
		else:
			Net.send_intent(Intents.make(&"shove", {"aim": Serializer.vec3(local.facing())})))
	router.shake.connect(func() -> void:
		var res: Dictionary = Net.send_intent(Intents.make(&"shake"))
		if not res["ok"] and res["error"] != &"rate_limited":
			hud.toast(StationUi.rejection_text(res["error"]), 1.0))
	router.jump.connect(func() -> void:
		if local != null and local.state == PlayerAvatar.State.HELD:
			Net.send_intent(Intents.make(&"break_free")))
	router.toggle_camera.connect(func() -> void:
		if local != null and local.cam != null:
			local.cam.toggle_mode())
	router.emote_wheel_toggled.connect(func(open: bool) -> void:
		if open:
			emote_wheel.open()
		else:
			emote_wheel.close_and_pick())
	router.leaderboard_toggled.connect(hud.show_leaderboard)
	router.pause.connect(_on_pause)
	router.ping.connect(func() -> void:
		if local != null:
			local.say("!", 1.0))


func _process(delta: float) -> void:
	_clock += delta
	if _owns_server and server != null:
		server.advance(delta)
	# Remote avatars follow the server's last known position.
	for pid: int in avatars:
		if pid == local_id:
			continue
		var a: PlayerAvatar = avatars[pid]
		var p: Dictionary = view.state.players.get(pid, {})
		if p.has("pos") and a.is_standing():
			a.target_position = Serializer.to_vec3(p["pos"])
	# Kill floor: anything that falls out of the world comes back at the entrance.
	for pid: int in avatars:
		var a: PlayerAvatar = avatars[pid]
		if a.global_position.y < -5.0 and a.state != PlayerAvatar.State.AWAY:
			Log.warn(&"match", "player %d fell out of the world at %s, respawning" % [pid, a.global_position])
			if a.state == PlayerAvatar.State.RAGDOLL:
				a.end_ragdoll(LuckyLounge.RESPAWN_POS)
				_ko_until.erase(pid)
			a.teleport(LuckyLounge.RESPAWN_POS, 0.0)
			_report_position(pid)
	# Knockouts end on the server's clock; get up where the ragdoll stopped.
	for pid: int in _ko_until.keys():
		if _clock >= _ko_until[pid]:
			_ko_until.erase(pid)
			var a: PlayerAvatar = avatars.get(pid, null)
			if a != null and a.state == PlayerAvatar.State.RAGDOLL:
				a.end_ragdoll()
				_report_position(pid)
	for pid: int in _respawn_at.keys():
		if _clock >= _respawn_at[pid]:
			_respawn_at.erase(pid)
			var a: PlayerAvatar = avatars.get(pid, null)
			if a != null:
				a.set_away(false)
				a.teleport(LuckyLounge.RESPAWN_POS, 0.0)
				_report_position(pid)
				if pid == local_id:
					hud.toast("Back inside. Behave.", 2.0)
	_update_prompt()


func _physics_process(delta: float) -> void:
	_spin_door(delta)
	_check_fountain()
	_check_vip_gate()
	_check_pickups()
	_update_guards()


# --- Server events -----------------------------------------------------------------------------

func _on_event(ev: Dictionary) -> void:
	var type: StringName = ev["type"]
	match type:
		&"player_joined":
			_spawn_avatar(int(ev["player"]["id"]), ev["player"])
		&"player_shoved":
			var t: PlayerAvatar = avatars.get(int(ev["target"]), null)
			if t != null:
				var dir: Vector3 = Serializer.to_vec3(ev["dir"])
				t.knockback(dir, float(ev["knockback"]) * (2.5 if bool(ev.get("spring_glove", false)) else 1.6))
				Audio.play_at(&"bonk", t, -6.0, randf_range(0.9, 1.1))
			var at: PlayerAvatar = avatars.get(int(ev["attacker"]), null)
			if at != null:
				at.visuals.react(&"win")
		&"player_knocked_down":
			var t: PlayerAvatar = avatars.get(int(ev["target"]), null)
			if t != null:
				t.stun(cfg.knockdown_time)
				t.say("ow", 1.0)
				Audio.play_at(&"oof", t, -8.0)
		&"player_knocked_out":
			_knock_out(int(ev["target"]), int(ev["attacker"]), StringName(ev["cause"]))
		&"player_grabbed":
			var t: PlayerAvatar = avatars.get(int(ev["target"]), null)
			var h: PlayerAvatar = avatars.get(int(ev["attacker"]), null)
			if t != null and h != null:
				t.set_held(h)
				h.visuals.reaching = true
				h.visuals.reach_target = PlayerAvatar.HELD_OFFSET
				if int(ev["target"]) == local_id:
					hud.toast("Grabbed! Mash SPACE to break free", 2.0)
		&"player_released", &"player_broke_free":
			var t: PlayerAvatar = avatars.get(int(ev["target"]), null)
			var h: PlayerAvatar = avatars.get(int(ev["attacker"]), null)
			if t != null:
				t.release_held()
				_report_position(int(ev["target"]))
			if h != null:
				h.visuals.reaching = false
			if type == &"player_broke_free" and t != null:
				t.say("HA!", 1.0)
		&"player_thrown":
			var t: PlayerAvatar = avatars.get(int(ev["target"]), null)
			var h: PlayerAvatar = avatars.get(int(ev["attacker"]), null)
			if h != null:
				h.visuals.reaching = false
			if t != null:
				_ragdoll_attacker[int(ev["target"])] = int(ev["attacker"])
				t.start_ragdoll(Serializer.to_vec3(ev["velocity"]), 3.0)
				Audio.play_at(&"whoosh", t, -8.0)
		&"chips_dropped":
			_spawn_pile(int(ev["pile"]), int(ev["amount"]), Serializer.to_vec3(ev["pos"]))
		&"chips_collected":
			_remove_pile(int(ev["pile"]))
			var p: PlayerAvatar = avatars.get(int(ev["player"]), null)
			if p != null:
				Audio.play_at(&"pickup", p, -6.0)
				if int(ev["player"]) != local_id:
					p.say("+$%d" % int(ev["amount"]), 1.2)
		&"pickup_expired":
			_remove_pile(int(ev["pile"]))
		&"chips_shaken_out":
			var at: PlayerAvatar = avatars.get(int(ev["attacker"]), null)
			if at != null:
				at.visuals.react(&"win")
				Audio.play_at(&"coin", at, -4.0)
		&"player_sat":
			_seat(int(ev["player"]), StringName(ev["station"]))
		&"player_stood":
			_unseat(int(ev["player"]))
		&"player_thrown_out":
			_throw_out(int(ev["target"]), String(ev.get("guard", "guard")))
		&"emote":
			var p: PlayerAvatar = avatars.get(int(ev["player"]), null)
			if p != null:
				p.say(_emote_text(StringName(ev["id"])), 2.0)
				if p.is_standing():
					p.hop(Vector3(0, 3.5, 0))
		&"intent_rejected":
			if int(ev["player"]) == local_id:
				var err: StringName = StringName(ev["error"])
				if err == &"vip_denied":
					Audio.play(&"buzzer", &"SFX", -4.0)
					hud.toast("VIP ACCESS — $%d+" % _vip_threshold(), 2.0)
				elif err != &"rate_limited" and err != &"not_standing":
					hud.toast(StationUi.rejection_text(err), 1.5)
		&"round_result":
			var p: PlayerAvatar = avatars.get(int(ev["player"]), null)
			var net: int = int(ev["net"])
			if p != null and net != 0:
				p.visuals.react(&"win" if net > 0 else &"loss")
				if int(ev["player"]) != local_id:
					p.say(("+$%d" if net > 0 else "-$%d") % absi(net), 1.5)
			var details: Dictionary = ev.get("details", {})
			if details.has("drop_id") and details.has("slot"):
				_drop_plinko_chip(StringName(ev["station"]), int(ev["player"]), int(details["slot"]), int(details["drop_id"]))
		&"bet_placed":
			if ev.get("details", {}).get("game", "") == "plinko":
				_plinko_seen.clear()
		&"jackpot_won":
			Audio.play(&"jackpot_siren", &"SFX", -6.0)
		&"last_call":
			Audio.play(&"countdown_beep", &"SFX", -4.0)
		&"phase_changed":
			var phase: Phase.Id = int(ev["phase"]) as Phase.Id
			if phase == Phase.Id.INTRO:
				hud.toast("WELCOME TO THE LUCKY LOUNGE", 3.0)
			elif phase == Phase.Id.CASINO and int(ev.get("from", -1)) == Phase.Id.INTRO:
				hud.toast("Gamble. Shove. Don't get caught.", 3.0)
		&"match_ended":
			_show_results(ev["standings"])


func _knock_out(target: int, attacker: int, cause: StringName) -> void:
	var t: PlayerAvatar = avatars.get(target, null)
	if t == null:
		return
	_ko_until[target] = _clock + cfg.knockout_time
	_ragdoll_attacker[target] = attacker
	if t.state != PlayerAvatar.State.RAGDOLL:
		var dir: Vector3 = -t.facing()
		var at: PlayerAvatar = avatars.get(attacker, null)
		if at != null:
			dir = (t.global_position - at.global_position)
			dir.y = 0.0
			dir = dir.normalized() if dir.length() > 0.01 else -t.facing()
		t.start_ragdoll(dir * 3.0 + Vector3.UP * 2.5, cfg.knockout_time + 1.0)
	if t.ragdoll != null:
		t.ragdoll.max_time = cfg.knockout_time + 1.0
	t.visuals.set_knocked_out(true)
	Audio.play_at(&"bonk", t, -2.0, 0.8)
	if target == local_id:
		hud.toast("KNOCKED OUT" if cause != &"fountain" else "SPLASH! Knocked out", 2.0)


func _seat(pid: int, sid: StringName) -> void:
	var a: PlayerAvatar = avatars.get(pid, null)
	var st: StationBase = map.stations.get(sid, null)
	if a == null or st == null:
		return
	view.resync()
	var idx: int = _seat_index(sid, pid)
	a.sit(st.seats[clampi(idx, 0, st.seats.size() - 1)] if not st.seats.is_empty() else st, st.camera_anchor)
	if pid == local_id:
		hud.set_prompt("")
		hud.set_crosshair_visible(false)
		var ui: StationUi = station_uis.get(st.game_id, null)
		if ui != null:
			current_ui = ui
			ui.open(sid, local_id, view.state)
			_on_station_state(sid)
		Audio.play(&"ui_click", &"UI", -10.0)


func _unseat(pid: int) -> void:
	var a: PlayerAvatar = avatars.get(pid, null)
	if a == null:
		return
	a.stand()
	_report_position(pid)
	if pid == local_id:
		if current_ui != null:
			current_ui.close()
			current_ui = null
		hud.set_crosshair_visible(true)
		router.set_mode(InputRouter.Mode.WALK)


func _throw_out(pid: int, guard_name: String) -> void:
	var a: PlayerAvatar = avatars.get(pid, null)
	if a == null:
		return
	if a.state == PlayerAvatar.State.SEATED:
		a.stand()
	var dir: Vector3 = LuckyLounge.ENTRANCE_POS - a.global_position
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.BACK
	_ragdoll_attacker.erase(pid)
	_ko_until.erase(pid)
	a.start_ragdoll(dir * 9.0 + Vector3.UP * 4.0, 1.6)
	_respawn_at[pid] = _clock + cfg.throw_out_respawn_seconds
	Audio.play_at(&"whistle", a, -4.0)
	if pid == local_id:
		hud.toast("Security threw you out!", 3.0)


func _show_results(standings: Array) -> void:
	if results_panel != null:
		return
	router.set_mode(InputRouter.Mode.MENU)
	results_panel = PanelContainer.new()
	results_panel.set_anchors_preset(Control.PRESET_CENTER)
	results_panel.anchor_left = 0.5
	results_panel.anchor_right = 0.5
	results_panel.anchor_top = 0.5
	results_panel.anchor_bottom = 0.5
	results_panel.offset_left = -320
	results_panel.offset_right = 320
	results_panel.offset_top = -260
	results_panel.offset_bottom = 260
	ui_layer.add_child(results_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 10)
	results_panel.add_child(v)
	var t := Label.new()
	t.theme_type_variation = &"TitleLabel"
	t.text = "RESULTS"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	for row: Dictionary in standings:
		var l := Label.new()
		l.text = "%s   %s   $%s" % [Hud._ordinal(int(row["rank"])), str(row["name"]), Hud._thousands(int(row["money"]))]
		l.add_theme_font_size_override(&"font_size", 30)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if int(row["player"]) == local_id:
			l.add_theme_color_override(&"font_color", Palette.VIP_GOLD)
		v.add_child(l)
	var b := Button.new()
	b.text = "BACK TO MENU"
	b.pressed.connect(func() -> void: SceneRouter.goto(RESULTS_PATH))
	v.add_child(b)
	b.grab_focus()
	Audio.play(&"big_win", &"SFX", -4.0)


# --- Local input -------------------------------------------------------------------------------

func _on_interact() -> void:
	if local == null or not local.is_standing():
		return
	if nearest_station != null:
		var res: Dictionary = Net.send_intent(Intents.make(&"sit", {"station": nearest_station.station_id}))
		if not res["ok"] and res["error"] != &"vip_denied":
			hud.toast(StationUi.rejection_text(res["error"]), 1.5)
		return
	# Nothing to sit at: try grabbing whoever is in front.
	_on_grab()


func _on_grab() -> void:
	if local == null or not local.is_standing():
		return
	var target: int = _nearest_player_in_front(2.0)
	if target >= 0:
		Net.send_intent(Intents.make(&"grab", {"target": target}))


func _on_pause() -> void:
	if results_panel != null:
		return
	if router.mode == InputRouter.Mode.MENU:
		router.set_mode(InputRouter.Mode.SEATED if local != null and local.state == PlayerAvatar.State.SEATED else InputRouter.Mode.WALK)
		hud.toast("", 0.0)
	else:
		router.set_mode(InputRouter.Mode.MENU)
		hud.toast("PAUSED — Esc to resume, F10 to quit to menu", 60.0)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_F10:
		SceneRouter.goto(RESULTS_PATH)


# --- World checks ------------------------------------------------------------------------------

func _update_prompt() -> void:
	nearest_station = null
	if local == null or not local.is_standing() or _local_holding() >= 0:
		hud.set_prompt("")
		return
	var best_d: float = INF
	for sid: StringName in map.stations:
		var st: StationBase = map.stations[sid]
		var d: float = Vector3(st.global_position.x - local.global_position.x, 0.0, st.global_position.z - local.global_position.z).length()
		if absf(st.global_position.y - local.global_position.y) > 1.5:
			continue
		if d < best_d and d <= Registry.maps[&"lucky_lounge"].interact_range:
			best_d = d
			nearest_station = st
	if nearest_station != null:
		var min_bet: int = _min_bet(nearest_station)
		var text: String = nearest_station.prompt_text(min_bet)
		if nearest_station.is_vip:
			text += "   VIP ACCESS — $%d+" % _vip_threshold()
		hud.set_prompt(text)
	else:
		var target: int = _nearest_player_in_front(2.0)
		hud.set_prompt("[E / LMB] Grab %s   [RMB] Shove" % view.state.player_name(target) if target >= 0 else "")


func _spin_door(delta: float) -> void:
	_door_angle += delta * 0.9
	var spinner: AnimatableBody3D = map.revolving_door.get_node_or_null("Spinner")
	if spinner != null:
		spinner.rotation.y = _door_angle
	var area: Area3D = map.revolving_door.get_node_or_null("DoorArea")
	if area == null:
		return
	for body: Node3D in area.get_overlapping_bodies():
		if body is PlayerAvatar and (body as PlayerAvatar).is_standing():
			var rel: Vector3 = body.global_position - map.revolving_door.global_position
			var tangent: Vector3 = Vector3(-rel.z, 0.0, rel.x).normalized()
			(body as PlayerAvatar).push_velocity += tangent * 4.0 * delta


func _check_fountain() -> void:
	for body: Node3D in map.fountain_area.get_overlapping_bodies():
		if body is PlayerAvatar:
			var a: PlayerAvatar = body
			if not a.is_soaked():
				Audio.play_at(&"splash", a, -6.0)
			a.soak()
			if a.is_standing() and a.global_position.y < 0.9 and a.velocity.y < -2.0 and _owns_server:
				server.report_knockout(a.player_id, _ragdoll_attacker.get(a.player_id, -1), &"fountain")
		elif body is RigidBody3D and body.has_meta(&"ragdoll"):
			var rb: RagdollBody = body.get_meta(&"ragdoll")
			var pid: int = rb.player_id
			if _owns_server and not _ko_until.has(pid) and avatars.has(pid):
				if server.report_knockout(pid, _ragdoll_attacker.get(pid, -1), &"fountain"):
					Audio.play_at(&"splash", rb, -2.0)
					avatars[pid].soak()


func _check_vip_gate() -> void:
	var threshold: int = _vip_threshold()
	for body: Node3D in map.vip_gate_area.get_overlapping_bodies():
		if body is PlayerAvatar and (body as PlayerAvatar).is_standing():
			var a: PlayerAvatar = body
			if view.state.balance(a.player_id) >= threshold:
				continue
			# Bouncer pushes them back toward the stairs (+x) with a buzzer.
			a.knockback(Vector3(1.0, 0.0, 0.0), 7.0)
			a.stun(0.4)
			if a.player_id == local_id and _clock - _vip_toast_at > 1.0:
				_vip_toast_at = _clock
				Audio.play(&"buzzer", &"SFX", -4.0)
				hud.toast("VIP ACCESS — $%d+" % threshold, 1.5)


func _check_pickups() -> void:
	if not _owns_server or piles.is_empty():
		return
	for pile_id: int in piles.keys():
		var pile: ChipPile = piles[pile_id]
		for pid: int in avatars:
			var a: PlayerAvatar = avatars[pid]
			if a.is_standing() and a.global_position.distance_to(pile.global_position) < 0.9:
				server.report_pickup(pid, pile_id)
				break


func _update_guards() -> void:
	if not _owns_server or guards.is_empty():
		return
	var offences: Array[Dictionary] = server.interactions.recent_offences(server.match_time, 3.0)
	for g: Guard in guards:
		if g.state == Guard.State.CHASE:
			var t: PlayerAvatar = avatars.get(g.target_id, null)
			if t == null or t.state == PlayerAvatar.State.AWAY:
				g.stop_chase()
				continue
			g.update_target(t.global_position, _guard_sees(g, t.global_position))
			continue
		for o: Dictionary in offences:
			var attacker: int = int(o["attacker"])
			var a: PlayerAvatar = avatars.get(attacker, null)
			if a == null or not a.is_standing():
				continue
			if _guard_sees(g, a.global_position):
				g.chase(attacker, a.global_position)
				if attacker == local_id:
					hud.toast("SECURITY saw that!", 1.5)
				break


func _guard_sees(g: Guard, pos: Vector3) -> bool:
	return server.rules.guard_sees(g.global_position, g.forward(), pos, map.has_line_of_sight(g.global_position, pos))


func _on_guard_caught(g: Guard, pid: int) -> void:
	if _owns_server and avatars.has(pid) and avatars[pid].state != PlayerAvatar.State.AWAY:
		server.report_thrown_out(pid, g.guard_id)


func _on_landed(pid: int, drop: float) -> void:
	if _owns_server and drop >= cfg.mezzanine_fall_height:
		server.report_knockout(pid, -1, &"fall")


func _on_ragdoll_impact(pid: int, strength: float, wall: bool) -> void:
	var a: PlayerAvatar = avatars.get(pid, null)
	if a == null or a.ragdoll == null:
		return
	Audio.play_at(&"bonk", a.ragdoll, -4.0, randf_range(0.8, 1.0))
	if _owns_server and wall and strength > 5.5 and not _ko_until.has(pid):
		server.report_knockout(pid, _ragdoll_attacker.get(pid, -1), &"wall")


func _on_ragdoll_settled(pid: int) -> void:
	var a: PlayerAvatar = avatars.get(pid, null)
	if a == null or a.state != PlayerAvatar.State.RAGDOLL:
		return
	if _respawn_at.has(pid):
		a.set_away(true)
		return
	if _ko_until.has(pid):
		return  # still out cold; _process gets them up on the server's clock
	a.end_ragdoll()
	_report_position(pid)


# --- Stations ----------------------------------------------------------------------------------

func _on_station_state(sid: StringName) -> void:
	var st: Dictionary = view.state.stations.get(sid, {})
	var node: StationBase = map.stations.get(sid, null)
	if node != null:
		node.set_hot(bool(st.get("hot", false)))
	if current_ui != null and current_ui.station_id == sid:
		current_ui.update_state(st, Net.request_private_snapshot().get("station", {}))


func _drop_plinko_chip(sid: StringName, pid: int, slot: int, drop_id: int) -> void:
	# The result arrives when the server lands the chip; play the drop back now (ending exactly there).
	var st: PlinkoStation = map.stations.get(sid, null) as PlinkoStation
	if st == null or _plinko_seen.has(drop_id):
		return
	_plinko_seen[drop_id] = true
	var rng := SeededRng.new(drop_id * 7919 + slot)
	var path: Array[float] = PlinkoSteering.path_to_slot(PlinkoStation.ROWS, PlinkoStation.SLOTS, slot, rng)
	var row_h: float = (PlinkoStation.BOARD_H - 1.2) / PlinkoStation.ROWS
	var pts: Array[Vector3] = PlinkoSteering.path_points(path, st.slot_xs, st.drop_y, row_h, 0.65)
	var chip := PlinkoChip.new()
	chip.color = avatars[pid].color if avatars.has(pid) else Palette.CASINO_RED
	st.add_child(chip)
	chip.play(pts, 1.6, slot)


func _spawn_pile(id: int, amount: int, pos: Vector3) -> void:
	if piles.has(id):
		return
	var p := ChipPile.new()
	p.pile_id = id
	p.amount = amount
	p.position = Vector3(pos.x, maxf(pos.y, 0.0), pos.z)
	world_root.add_child(p)
	piles[id] = p
	Audio.play_at(&"chip_clack", p, -8.0)


func _remove_pile(id: int) -> void:
	if piles.has(id):
		piles[id].queue_free()
		piles.erase(id)


# --- Helpers -----------------------------------------------------------------------------------

func _report_position(pid: int) -> void:
	if _owns_server and avatars.has(pid):
		server.set_server_position(pid, avatars[pid].global_position)


func _local_holding() -> int:
	if local == null:
		return -1
	for pid: int in avatars:
		if avatars[pid].holder == local:
			return pid
	return -1


func _nearest_player_in_front(range_m: float) -> int:
	if local == null:
		return -1
	var best: int = -1
	var best_d: float = INF
	var fwd: Vector3 = local.facing()
	for pid: int in avatars:
		if pid == local_id:
			continue
		var a: PlayerAvatar = avatars[pid]
		if a.state == PlayerAvatar.State.AWAY:
			continue
		var to: Vector3 = a.global_position - local.global_position
		to.y = 0.0
		var d: float = to.length()
		if d > range_m or (d > 0.05 and fwd.dot(to.normalized()) < 0.3):
			continue
		if d < best_d:
			best_d = d
			best = pid
	return best


func _seat_index(sid: StringName, pid: int) -> int:
	var st: Dictionary = view.state.stations.get(sid, {})
	var list: Array = st.get("seats", st.get("players", []))
	var i: int = list.find(pid)
	return i if i >= 0 else 0


func _min_bet(st: StationBase) -> int:
	var mult: float = cfg.limits_multiplier(view.state.segment_index) * (3.0 if st.is_vip else 1.0)
	var base: int = 10
	match st.game_id:
		&"blackjack":
			base = cfg.bj_min_bet
		&"roulette":
			base = cfg.roulette_min_bet
		&"slots":
			base = cfg.slots_bet_sizes[0]
		&"plinko":
			base = cfg.plinko_bet_sizes[0]
	return int(floor(base * mult))


func _vip_threshold() -> int:
	return int(floor(cfg.vip_entry_money * cfg.limits_multiplier(view.state.segment_index)))


## Dev summary for tools/scene_probe.gd.
func probe() -> String:
	return "players=%d guards=%d hud=%s viewport=%s timer_at=%s local_pos=%s errors=%d" % [avatars.size(), guards.size(), hud.size, get_viewport().get_visible_rect().size, hud.timer_label.global_position, local.global_position if local != null else Vector3.INF, Log.error_count]


static func _emote_text(id: StringName) -> String:
	for e: Array in EmoteWheel.EMOTES:
		if e[0] == id:
			return String(e[1]).split(" ")[0]
	return "…"
