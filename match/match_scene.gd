class_name MatchScene
extends Node3D
## The casino match as the player sees it: the Lucky Lounge, one avatar per player, HUD, station
## overlays, guards, hazards and loose chips. Every money or knockout decision comes from server
## events; this scene only shows them and reports what the physics world did
## (`report_knockout`, `report_pickup`, `report_thrown_out`, `report_got_up`).
##
## One scene, three roles (§3.5 "one code path"):
## - PRACTICE: hosts the MatchServer in-process; the local avatar is driven by input, everyone
##   else (only test dummies; the game has no bots) by local simulation.
## - SERVER: the dedicated room server (headless). Humans are puppets fed by their clients'
##   movement; the server simulates ragdolls, guards, props and test dummies and streams them.
## - CLIENT: online player. Own avatar from input while standing; everything else follows the
##   server's world stream (`NetWorld`).

const MATCH_SCENE_PATH: String = "res://match/match_scene.tscn"
const RESULTS_PATH: String = "res://ui/menus/main_menu.tscn"

enum Role { PRACTICE, SERVER, CLIENT }

const DUMMY_NAMES: Array[String] = ["Chip", "Lucky", "Dice", "Ace", "Penny", "Bluff", "Royal"]

## Practice dummies when no `--dummies` flag is given (scene tests set this; the game keeps 0).
static var test_dummies: int = 0

var map: LuckyLounge
var server: MatchServer = null
var view: ClientMatchView
var hud: Hud
var router: InputRouter
var emote_wheel: EmoteWheel
var ui_layer: CanvasLayer
## Everything 3D sits in here (the map, `world_root`, minigame stages, the results podium): the
## pixel look renders it at a lower resolution while `ui_layer` stays sharp (`PixelView`).
var pixel_view: PixelView
var world_root: Node3D
var local: PlayerAvatar = null
var local_id: int = -1
var cfg: BalanceConfig
var avatars: Dictionary[int, PlayerAvatar] = {}
## Player ids of test dummies this process simulates (server side only).
var dummies: Dictionary[int, bool] = {}
var piles: Dictionary[int, ChipPile] = {}
var guards: Array[Guard] = []
## Waiter NPC, puddles and the Megaphone (M7, npc/) and the event sounds (audio/event_sfx.gd).
var casino_floor: CasinoFloor = null
var event_sfx: EventSfx = null
var station_uis: Dictionary[StringName, StationUi] = {}
var current_ui: StationUi = null
var nearest_station: StationBase = null
## Results podium (also the "no other menu while results show" flag).
var results_panel: ResultsStage = null
var settings_panel: SettingsPanel = null
var _shown_jackpot: int = -1
## The running minigame's stage and the reward screen after it.
var stage: MinigameStage = null
var reward_panel: RewardPanel
## Scripted driver (--autoplay); null in normal play.
var autoplay: Node = null
var role: Role = Role.PRACTICE
var net_world: NetWorld
var lobby_panel: LobbyPanel
var shop_panel: ShopPanel
var connection_label: Label
## Proximity voice (clients only; the dedicated server just relays in `Net`).
var voice: VoiceChannel = null
## Table animations, win/lose VFX, screen shake / hit-stop, Last Call lighting (clients only).
var table_fx: TableFx = null
## Item keys, target picker, discard choice (M5).
var items_ctl: ItemController
## Banana peels on the floor (peel id → mesh) and item effect tags over heads (player → label).
var peel_nodes: Dictionary[int, Node3D] = {}
var effect_tags: Dictionary[int, Label3D] = {}
## Beer: full-screen wobble/blur under the HUD, and the money we had when we got drunk.
var drunk_overlay: ColorRect
var _drunk_money: int = -1
## Gold crown over the money leader (not on the dedicated server).
var crown: LeaderCrown = null

var _ko_until: Dictionary[int, float] = {}
var _ragdoll_attacker: Dictionary[int, int] = {}
var _respawn_at: Dictionary[int, float] = {}
var _clock: float = 0.0
var _vip_toast_at: float = -INF
var _door_angle: float = 0.0
var _owns_server: bool = false
var _plinko_seen: Dictionary[String, bool] = {}  # "station:drop_id" (ids count per board)
var _pad_timer: float = 0.0
var _countdown_shown: int = -1
var _match_over: bool = false
## Predicted local actions awaiting the server: intent type → give-up time.
var _predicted: Dictionary[StringName, float] = {}
const PREDICTION_TIMEOUT: float = 0.6
## Chip pickups: radius around a standing player's feet (floor plane) and the extra the server
## allows a remote body (its position arrives ~100-200 ms late), and how long a predicted pickup
## waits for the server before the chips drop back.
const PICKUP_RADIUS: float = 1.1
const PICKUP_LAG_SLACK: float = 0.6
const PICKUP_PREDICT_TIMEOUT: float = 1.5
## Knockback speed (m/s) per unit of the server's `knockback` (shoves slide ~1.7 m, hop a little).
const SHOVE_PUSH_SCALE: float = 2.6
const SHOVE_GLOVE_SCALE: float = 4.0
## Local shove: when the next one may swing (client gate over the server's cooldown) and when the
## last swing started (its contact moment syncs the impact).
var _shove_ready_at: float = -INF
var _swing_started: float = -INF
## Player → scene clock of a shove impact still to land (a knockout from it waits for the hit).
var _impact_at: Dictionary[int, float] = {}
## Player → push direction of the last shove impact (knockdowns fall that way).
var _impact_dir: Dictionary[int, Vector3] = {}
## Online: the target our own swing showed hitting (impact effects already played), and when.
var _predicted_hit: int = -1
var _predicted_hit_at: float = -INF
## Knocked down into a ragdoll: get up at this scene time (host only, like `_ko_until`).
var _down_until: Dictionary[int, float] = {}
var _pile_sync_timer: float = 0.0
## `--quit-after-results`: scripted clients exit once the digest is logged (network tests).
var cmd_quit_after_results: bool = false


func _ready() -> void:
	cfg = Registry.balance
	var cmd: Cmdline = SceneRouter.cmdline if SceneRouter.cmdline != null else Cmdline.from_os()
	cmd_quit_after_results = cmd.has_flag("quit-after-results")
	pixel_view = PixelView.new()
	pixel_view.name = "PixelView"
	add_child(pixel_view)
	pixel_view.setup(Net.mode == Net.Mode.SERVER)  # the dedicated server renders nothing
	map = LuckyLounge.new()
	map.name = "LuckyLounge"
	pixel_view.world.add_child(map)
	world_root = Node3D.new()
	world_root.name = "World"
	pixel_view.world.add_child(world_root)
	router = InputRouter.new()
	router.name = "InputRouter"
	add_child(router)
	ui_layer = CanvasLayer.new()
	ui_layer.name = "UI"
	add_child(ui_layer)
	drunk_overlay = ColorRect.new()
	drunk_overlay.name = "DrunkOverlay"
	drunk_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	drunk_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var drunk_mat := ShaderMaterial.new()
	drunk_mat.shader = load("res://ui/effects/drunk.gdshader")
	drunk_overlay.material = drunk_mat
	drunk_overlay.visible = false
	ui_layer.add_child(drunk_overlay)
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
	lobby_panel = LobbyPanel.new()
	lobby_panel.name = "LobbyPanel"
	lobby_panel.closed.connect(func() -> void:
		if router.mode == InputRouter.Mode.MENU and results_panel == null:
			router.set_play_mode(InputRouter.Mode.WALK))
	lobby_panel.leave_requested.connect(_leave_to_menu)
	ui_layer.add_child(lobby_panel)
	shop_panel = ShopPanel.new()
	shop_panel.name = "ShopPanel"
	shop_panel.closed.connect(func() -> void:
		if router.mode == InputRouter.Mode.MENU and results_panel == null:
			router.set_play_mode(InputRouter.Mode.WALK))
	ui_layer.add_child(shop_panel)
	reward_panel = RewardPanel.new()
	reward_panel.name = "RewardPanel"
	ui_layer.add_child(reward_panel)
	connection_label = Label.new()
	connection_label.name = "ConnectionLost"
	connection_label.theme_type_variation = &"HeadingLabel"
	connection_label.text = "Connection lost — reconnecting…"
	connection_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	connection_label.offset_top = 90
	connection_label.visible = false
	ui_layer.add_child(connection_label)
	match Net.mode:
		Net.Mode.NONE:
			_start_local(cmd)
		Net.Mode.SERVER:
			_start_room_server(cmd)
		Net.Mode.CLIENT:
			role = Role.CLIENT
			Net.position_forced.connect(_on_position_forced)
			Net.disconnected.connect(_on_disconnected)
		_:
			server = Net.local_server
	local_id = Net.local_player_id
	view = ClientMatchView.new()
	view.name = "ClientView"
	add_child(view)
	hud.bind(view.state, local_id)
	lobby_panel.bind(view.state, local_id)
	shop_panel.bind(view.state, local_id)
	reward_panel.bind(view.state, local_id)
	view.state.station_changed.connect(_on_station_state)
	view.state.players_changed.connect(_sync_avatars)
	view.state.lobby_changed.connect(_on_lobby_changed)
	view.state.peels_changed.connect(_sync_peels)
	view.state.effects_changed.connect(_refresh_effect_tag)
	items_ctl = ItemController.new(self)
	add_child(items_ctl)
	Net.event_received.connect(_on_event)
	net_world = NetWorld.new()
	net_world.name = "NetWorld"
	add_child(net_world)
	net_world.setup(self)
	if role == Role.SERVER:
		Net.world_provider = net_world.build
		Net.move_received.connect(_on_move_received)
	_spawn_avatars()
	if role != Role.SERVER:
		voice = VoiceChannel.new()
		voice.name = "VoiceChannel"
		voice.setup(view.state, local_id, func(pid: int) -> PlayerAvatar: return avatars.get(pid, null), ui_layer, role == Role.CLIENT)
		add_child(voice)
		_add_table_fx()
		crown = LeaderCrown.new()
		world_root.add_child(crown)
	_connect_router()
	if _owns_server and role == Role.PRACTICE:
		server.start_match()
		# Dev/screenshots: `--skip-to 100` fast-forwards to that casino time (100 = first quiz).
		var skip: float = cmd.get_float("skip-to", 0.0)
		while skip > 0.0 and server.running and server.phases.casino_time < skip - 0.01:
			server.advance(MatchServer.TICK)
		# Dev/tests: `--give-items lucky_clover,banana_peel` starts everyone with these items.
		for id: String in cmd.get_string("give-items", "").split(",", false):
			for pid: int in server.state.players:
				server.items.give(pid, StringName(id), server.match_time)
	if view.state.phase == Phase.Id.LOBBY and view.state.room_mode:
		map.set_lobby_open(false)
		if local != null:
			hud.toast("Welcome! Stand on your READY pad. TAB: lobby panel", 4.0)
	_spawn_guards()
	casino_floor = CasinoFloor.new()
	casino_floor.name = "CasinoFloor"
	add_child(casino_floor)
	casino_floor.setup(self)
	event_sfx = EventSfx.new(self)
	Loading.finish()
	if cmd.has_flag("autoplay"):
		var driver: Script = load("res://client/autoplay_driver.gd")
		autoplay = driver.new()
		autoplay.name = "Autoplay"
		add_child(autoplay)
	var music := MusicMood.new()
	music.name = "MusicMood"
	add_child(music)
	music.setup(view.state)
	if cmd.has_flag("third-person") and local != null:
		local.cam.toggle_mode()
	if cmd.has("autosit"):
		_autosit(StringName(cmd.get_string("autosit")))
	if cmd.has_flag("pause-menu"):
		_on_pause.call_deferred()
	_catch_up_phase()
	Log.info(&"match", "match scene ready: %d players, local=%d" % [avatars.size(), local_id])


func _exit_tree() -> void:
	if Net.event_received.is_connected(_on_event):
		Net.event_received.disconnect(_on_event)
	if Net.position_forced.is_connected(_on_position_forced):
		Net.position_forced.disconnect(_on_position_forced)
	if Net.disconnected.is_connected(_on_disconnected):
		Net.disconnected.disconnect(_on_disconnected)
	if Net.move_received.is_connected(_on_move_received):
		Net.move_received.disconnect(_on_move_received)
	if role == Role.PRACTICE and _owns_server:
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
	var bet: int = Cmdline.parse(OS.get_cmdline_user_args()).get_int("autobet", 0)
	if bet > 0:  # dev/screenshots: put a bet down so the cards get dealt
		await get_tree().create_timer(0.5).timeout
		Net.send_intent(Intents.make(&"place_bet", {"station": sid, "bet": {"amount": bet}}))


## Dedicated server: the authoritative MatchServer for this room, waiting in the lobby.
func _start_room_server(cmd: Cmdline) -> void:
	role = Role.SERVER
	server = MatchServer.new()
	server.name = "MatchServer"
	add_child(server)
	var def: MapDefinition = Registry.maps[&"lucky_lounge"].duplicate() as MapDefinition
	def.station_positions = map.station_positions()
	def.spawn_points = map.spawn_points()
	def.shop_position = LuckyLounge.SHOP_POS
	var settings: Dictionary = {"duration": cmd.get_int("duration", 10), "seed": cmd.get_int("seed", 0), "items_enabled": true}
	server.configure(settings, cfg, Registry.presets, Registry.game_logic_scripts(), def)
	server.world.obstacle_callback = _obstacle_between
	server.timescale = cmd.get_float("timescale", 1.0)
	server.lobby.min_participants = cmd.get_int("min-players", 2)
	server.lobby.settings["duration"] = cmd.get_int("duration", 10)  # dev/tests may go below the menu's 5
	server.open_lobby()
	_owns_server = true
	Net.attach_server(server)
	for i: int in clampi(cmd.get_int("dummies", 0), 0, 7):
		_add_dummy(i)


## Practice: host the server in-process. Just you in the casino (Patrick: no bots); tests and
## screenshots add standing dummies with `--dummies N`.
func _start_local(cmd: Cmdline) -> void:
	server = MatchServer.new()
	server.name = "MatchServer"
	add_child(server)
	var def: MapDefinition = Registry.maps[&"lucky_lounge"].duplicate() as MapDefinition
	def.station_positions = map.station_positions()
	def.spawn_points = map.spawn_points()
	def.shop_position = LuckyLounge.SHOP_POS
	var settings: Dictionary = {"duration": cmd.get_int("duration", 10), "seed": cmd.get_int("seed", randi() % 1000000), "items_enabled": true}
	server.configure(settings, cfg, Registry.presets, Registry.game_logic_scripts(), def)
	server.world.obstacle_callback = _obstacle_between
	_owns_server = true
	var player_name: String = str(Settings.get_value("profile", "name", "You"))
	var id: int = Net.start_local(server, player_name)
	server.set_server_position(id, def.spawn_points[0])
	if cmd.has("skin"):  # dev/screenshots
		(server.state.players[id] as PlayerState).skin = StringName(cmd.get_string("skin"))
	for i: int in clampi(cmd.get_int("dummies", test_dummies), 0, 7):
		# Dev/screenshots: `--dummy-skins` dresses the dummies in the character skins.
		var skin: StringName = Cosmetics.SKINS[(i + 1) % Cosmetics.SKINS.size()] if cmd.has_flag("dummy-skins") else &"bean"
		var did: int = _add_dummy(i, skin)
		server.set_server_position(did, def.spawn_points[(i + 1) % def.spawn_points.size()] + Vector3(0, 0, -3.0))


## Test/screenshot dummy: a ready player with no client that only stands where it is put (or
## where physics throws it). Simulated by whoever hosts the server.
func _add_dummy(i: int, skin: StringName = &"bean") -> int:
	var did: int = server.add_player("dummy-%d" % (i + 1), DUMMY_NAMES[i % DUMMY_NAMES.size()], -1, skin)
	server.lobby.set_panel_ready(did, true)
	dummies[did] = true
	return did


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
	# Dummies are simulated wherever the server runs; other players are network puppets.
	var dummy: bool = _owns_server and dummies.has(pid)
	if not a.is_local:
		a.drive = PlayerAvatar.Drive.SIM if dummy or role == Role.PRACTICE else PlayerAvatar.Drive.PUPPET
	var pos: Vector3 = Serializer.to_vec3(p.get("pos", [0, 0, 0]))
	if pos == Vector3.ZERO:
		var room: bool = server.room_mode if _owns_server else view.state.room_mode
		pos = map.lobby_spawn(pid) if room else map.spawn_points()[(pid - 1) % map.spawn_points().size()]
		if _owns_server:
			server.set_server_position(pid, pos)
	a.position = pos
	a.yaw = 0.0  # yaw 0 looks down −z: into the casino from the entrance
	a.target_yaw = 0.0
	world_root.add_child(a)
	a.target_position = pos
	a.landed.connect(func(drop: float) -> void: _on_landed(pid, drop))
	a.ragdoll_impact.connect(func(strength: float, wall: bool) -> void: _on_ragdoll_impact(pid, strength, wall))
	a.ragdoll_settled.connect(func() -> void: _on_ragdoll_settled(pid))
	avatars[pid] = a
	a.set_skin(StringName(p.get("skin", "bean")))
	if not bool(p.get("connected", true)):
		a.set_connection_away(true)
	# Already at a table when we learn about them (joining late, reconnecting): put them in their
	# own chair. They used to stand where they last walked, which is the same spot in front of the
	# table for everyone, so they piled up on top of each other.
	var sid: StringName = StringName(p.get("station", ""))
	if sid != &"" and map.stations.has(sid):
		_seat.call_deferred(pid, sid, int(p.get("seat", -1)))
	return a


## Spawns avatars for players we only learned about from a snapshot.
func _sync_avatars() -> void:
	for pid: int in view.state.players:
		if not avatars.has(pid):
			_spawn_avatar(pid, view.state.players[pid])
	for pid: int in avatars.keys():
		if not view.state.players.has(pid):
			avatars[pid].queue_free()
			avatars.erase(pid)


func _on_lobby_changed() -> void:
	var cd: int = ceili(view.state.countdown) if view.state.countdown > 0.0 else -1
	if cd != _countdown_shown:
		_countdown_shown = cd
		if cd > 0 and local != null:
			hud.toast("Everyone's ready! Doors open in %d…" % cd, 3.2)
			Audio.play(&"countdown_beep", &"SFX", -6.0)


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
		g.puppet = role == Role.CLIENT
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
	# Grab is a click, not a hold: the next click (LMB, RMB or E) throws where you aim, so
	# letting go of the button does nothing.
	router.shove.connect(func() -> void:
		if local == null:
			return
		if _local_holding() >= 0:
			_throw_held()
		else:
			_local_shove())
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
	router.leaderboard_toggled.connect(func(shown: bool) -> void:
		if view.state.phase == Phase.Id.LOBBY and view.state.room_mode:
			if shown:
				_open_lobby_panel(&"")
		else:
			hud.show_leaderboard(shown))
	router.pause.connect(_on_pause)
	router.item_used.connect(items_ctl.on_slot)
	router.ping.connect(func() -> void:
		if local != null:
			local.say("!", 1.0))


func _process(delta: float) -> void:
	_clock += delta
	_expire_predictions()
	_point_at_hot_table()
	if crown != null:
		crown.track(view.state.balances, avatars)
	if view.state.jackpot != _shown_jackpot:
		_shown_jackpot = view.state.jackpot
		for node: StationBase in map.stations.values():
			if node is PlinkoStation:
				(node as PlinkoStation).set_jackpot(_shown_jackpot, cfg.jackpot_seed)
	if stage != null:
		stage.on_private(Net.request_private_snapshot())
	if _owns_server and server != null:
		server.advance(ScreenJuice.unscaled(delta))  # a hit-stop slows the client, not the server
	# Simulated bodies (dummies) follow the server's last known position.
	for pid: int in avatars:
		if pid == local_id:
			continue
		var a: PlayerAvatar = avatars[pid]
		var p: Dictionary = view.state.players.get(pid, {})
		if p.has("pos") and a.is_standing() and a.drive == PlayerAvatar.Drive.SIM:
			if _owns_server and a.is_pushed():
				# Shoved: the body slides where the knockback takes it and the server follows
				# (otherwise the dummy rubber-bands straight back to where it stood).
				a.target_position = a.global_position
				_report_position(pid)
			else:
				a.target_position = Serializer.to_vec3(p["pos"])
	if role == Role.CLIENT:
		connection_label.visible = Net.silence() > Net.SILENCE_WARNING
		_pile_sync_timer += delta
		if _pile_sync_timer >= 0.5:
			_pile_sync_timer = 0.0
			_sync_piles()
	# Kill floor: anything we simulate that falls out of the world comes back at the entrance.
	for pid: int in avatars:
		var a: PlayerAvatar = avatars[pid]
		if a.global_position.y < -5.0 and a.state != PlayerAvatar.State.AWAY and _simulates(a):
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
				_got_up(pid)
	for pid: int in _down_until.keys():
		if _clock >= _down_until[pid]:
			_down_until.erase(pid)
			var a: PlayerAvatar = avatars.get(pid, null)
			if a != null and a.state == PlayerAvatar.State.RAGDOLL and not _ko_until.has(pid):
				a.end_ragdoll()
				_got_up(pid)
	for pid: int in _respawn_at.keys():
		if _clock >= _respawn_at[pid]:
			_respawn_at.erase(pid)
			var a: PlayerAvatar = avatars.get(pid, null)
			if a != null:
				a.set_away(false)
				a.teleport(LuckyLounge.RESPAWN_POS, 0.0)
				if _owns_server:
					server.report_respawned(pid, LuckyLounge.RESPAWN_POS)
				if pid == local_id:
					hud.toast("Back inside. Behave.", 2.0)
	_update_prompt()


func _physics_process(delta: float) -> void:
	_spin_door(delta)
	_check_fountain()
	_check_vip_gate()
	_check_pickups()
	_update_guards()
	if _owns_server:
		_report_simulated_positions()
		_pad_timer += delta
		if _pad_timer >= 0.1 and server.room_mode and server.phases.phase == Phase.Id.LOBBY:
			_pad_timer = 0.0
			_check_ready_pads()


## True if this process moves `a`'s body (so local hazards and pushes apply to it here).
func _simulates(a: PlayerAvatar) -> bool:
	if a.state == PlayerAvatar.State.RAGDOLL:
		return a.ragdoll != null and not a.ragdoll.puppet
	return a.drive != PlayerAvatar.Drive.PUPPET


## The server keeps its world query in step with the ragdolls it simulates. Standing dummies need
## nothing: their avatars follow the server's position, never the other way round.
func _report_simulated_positions() -> void:
	for pid: int in avatars:
		var a: PlayerAvatar = avatars[pid]
		if a.state == PlayerAvatar.State.RAGDOLL and a.ragdoll != null and not a.ragdoll.puppet:
			if server.state.players.has(pid):
				server.world.set_transform(pid, a.global_position, a.yaw)
				server.state.players[pid].position = a.global_position


## First-time tips (M6 contextual hints): each one shows once per profile, after `delay` s.
func _hint(id: StringName, text: String, delay: float) -> void:
	if role == Role.SERVER or local == null or bool(Settings.get_value("hints", String(id), false)):
		return
	Settings.set_value("hints", String(id), true)
	Settings.save()
	# A bound method (not await) so nothing fires once the scene is gone.
	get_tree().create_timer(delay).timeout.connect(hud.toast.bind(InputGlyphs.fill(text), 5.0))


## Lobby: standing on your own colored pad means ready (§2.2).
func _check_ready_pads() -> void:
	for pid: int in avatars:
		var p: PlayerState = server.state.players.get(pid, null)
		if p == null or dummies.has(pid):
			continue
		var a: PlayerAvatar = avatars[pid]
		var pad: Vector3 = map.ready_pad(p.color_index)
		var flat: float = Vector2(a.global_position.x - pad.x, a.global_position.z - pad.z).length()
		server.report_on_pad(pid, a.is_standing() and p.connected and flat <= LuckyLounge.PAD_RADIUS)


## SERVER: a client's own avatar moved.
func _on_move_received(pid: int, pos: Vector3, yaw: float, airborne: bool) -> void:
	var a: PlayerAvatar = avatars.get(pid, null)
	if a == null or a.drive != PlayerAvatar.Drive.PUPPET:
		return
	if pos.y < -2.5:
		# Fell out of the world: the server puts them back at the entrance.
		server.set_server_position(pid, LuckyLounge.RESPAWN_POS)
		a.teleport(LuckyLounge.RESPAWN_POS)
		Net.send_to(Net.room_host.peer_of(pid), Protocol.CHANNEL_STATE, true, Protocol.Msg.FORCE_POSITION, {"pos": Serializer.vec3(LuckyLounge.RESPAWN_POS), "yaw": 0.0})
		return
	a.target_position = pos
	a.target_yaw = yaw
	a.puppet_airborne = airborne


## CLIENT: the server refused our movement and put us somewhere else.
func _on_position_forced(pos: Vector3, yaw: float) -> void:
	if local != null and local.is_standing():
		local.teleport(pos, yaw)


## CLIENT: lost the server (or got refused): back to the menu, which shows the reason.
func _on_disconnected(_reason: String) -> void:
	if not is_inside_tree():
		return
	if SceneRouter.quit_on_disconnect():
		get_tree().quit(0 if _match_over else 4)
	else:
		SceneRouter.goto.call_deferred(RESULTS_PATH)


## Money and items per player ("id:money:item+item"), as this process knows them (authoritative
## on servers, the mirror on clients). Network tests compare these digests across processes.
func state_digest() -> String:
	var ids: Array = view.state.players.keys()
	ids.sort()
	var parts: PackedStringArray = []
	for pid: int in ids:
		var money: int = server.economy.balance(pid) if _owns_server else view.state.balance(pid)
		var items: Array = server.state.players[pid].inventory if _owns_server else view.state.players[pid].get("inventory", [])
		parts.append("%d:%d:%s" % [pid, money, "+".join(PackedStringArray(items.map(func(i: Variant) -> String: return str(i))))])
	return ",".join(parts)


func _log_digest() -> void:
	# Late events (the last payouts) are still in flight to clients for one RTT; wait a little.
	await get_tree().create_timer(1.5).timeout
	if not is_inside_tree():
		return
	var d: String = state_digest()
	Log.info(&"nettest", "NETTEST digest %s hash=%d role=%d" % [d, d.hash(), role])
	if role == Role.CLIENT:
		Log.info(&"nettest", "NETTEST bandwidth down=%.0f B/s ping=%d ms" % [Net.download_rate(), Net.ping_ms()])
	if cmd_quit_after_results and role != Role.SERVER:
		await get_tree().create_timer(0.5).timeout
		if role == Role.CLIENT:
			Net.stop()
		get_tree().quit(0)


func _leave_to_menu() -> void:
	if role == Role.CLIENT:
		Net.last_error = ""
		Net.stop()
	SceneRouter.goto(RESULTS_PATH)


func _open_lobby_panel(focus: StringName) -> void:
	if local == null:
		return
	router.set_play_mode(InputRouter.Mode.MENU)
	lobby_panel.open(focus)


## Ragdoll over: the server records it and hands the body back to its owner.
func _got_up(pid: int) -> void:
	var a: PlayerAvatar = avatars.get(pid, null)
	if a == null:
		return
	if _owns_server:
		server.report_got_up(pid, a.global_position)


# --- Server events -----------------------------------------------------------------------------

func _on_event(ev: Dictionary) -> void:
	var type: StringName = ev["type"]
	if stage != null:
		stage.on_event(ev)
	if table_fx != null:
		table_fx.on_event(ev)
	if casino_floor != null:
		casino_floor.on_event(ev)
	if event_sfx != null:
		event_sfx.on_event(ev)
	match type:
		&"player_joined":
			_spawn_avatar(int(ev["player"]["id"]), ev["player"])
		&"player_removed":
			var a: PlayerAvatar = avatars.get(int(ev["player"]), null)
			if a != null:
				a.queue_free()
				avatars.erase(int(ev["player"]))
		&"player_skin":
			var a: PlayerAvatar = avatars.get(int(ev["player"]), null)
			if a != null:
				a.set_skin(StringName(ev["skin"]))
		&"player_left", &"player_rejoined":
			var a: PlayerAvatar = avatars.get(int(ev["player"]), null)
			if a != null and int(ev["player"]) != local_id:
				a.set_connection_away(type == &"player_left")
		&"player_got_up":
			var pid: int = int(ev["player"])
			var a: PlayerAvatar = avatars.get(pid, null)
			_ko_until.erase(pid)
			_down_until.erase(pid)
			if a != null and a.state == PlayerAvatar.State.RAGDOLL:
				a.end_ragdoll(Serializer.to_vec3(ev["pos"]) + Vector3(0, 0.5, 0))
			if net_world != null:
				net_world.reset_player(pid)
		&"player_respawned":
			var pid: int = int(ev["player"])
			var a: PlayerAvatar = avatars.get(pid, null)
			_respawn_at.erase(pid)
			if a != null and (a.state == PlayerAvatar.State.AWAY or a.state == PlayerAvatar.State.RAGDOLL):
				a.set_away(false)
				a.teleport(Serializer.to_vec3(ev["pos"]), 0.0)
				if pid == local_id:
					hud.toast("Back inside. Behave.", 2.0)
			if net_world != null:
				net_world.reset_player(pid)
		&"match_started":
			map.set_lobby_open(true)
			_hint(&"sit", "Walk up to a table and press {interact} to sit.  {grab} grabs, {shove} shoves.", 5.0)
		&"player_shoved":
			_on_shoved(ev)
		&"player_knocked_down":
			var t: PlayerAvatar = avatars.get(int(ev["target"]), null)
			if t != null:
				t.stun(float(ev.get("seconds", cfg.knockdown_time)))
				t.say("whoa!" if ev.get("cause", &"") in [&"banana", &"puddle"] else "ow", 1.0)
				Audio.play_at(&"oof", t, -8.0)
				var down_id: int = int(ev["target"])
				var down_by: int = int(ev.get("attacker", -1))
				var down_s: float = float(ev.get("seconds", cfg.knockdown_time))
				if not StringName(ev.get("cause", &"")) in [&"banana", &"puddle"]:
					# Shoved over, slammed into a table, bonked: the bean goes flying as a ragdoll
					# when the hit lands and gets up when the knockdown ends.
					_after(_impact_at.get(down_id, _clock) - _clock, func() -> void: _knock_down(down_id, down_by, down_s))
		&"player_knocked_out":
			var ko_target: int = int(ev["target"])
			var ko_attacker: int = int(ev["attacker"])
			var ko_cause: StringName = StringName(ev["cause"])
			# A knockout by shove launches when the swing lands, not before it.
			_after(_impact_at.get(ko_target, _clock) - _clock, func() -> void: _knock_out(ko_target, ko_attacker, ko_cause))
			var ko: PlayerAvatar = avatars.get(int(ev["target"]), null)
			if local != null and ko != null and ko != local and ko.global_position.distance_to(local.global_position) < 8.0:
				_hint(&"shake", "Knocked out! Stand next to them and press {shake} to shake out their chips.", 0.5)
		&"player_grabbed":
			if int(ev["attacker"]) == local_id:
				_predicted.erase(&"grab")  # confirmed: the hold keeps the arms out
			var t: PlayerAvatar = avatars.get(int(ev["target"]), null)
			var h: PlayerAvatar = avatars.get(int(ev["attacker"]), null)
			if t != null and h != null:
				t.set_held(h)
				h.visuals.reaching = true
				h.visuals.reach_target = PlayerAvatar.HELD_OFFSET
				t.visuals.hit(t.global_position - h.global_position, 0.6)
				if int(ev["target"]) == local_id or int(ev["attacker"]) == local_id:
					_juice(0.0, 0.18 if int(ev["target"]) == local_id else 0.1)
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
				if not (int(ev["attacker"]) == local_id and _clock - _swing_started < 0.5):
					h.visuals.swing()
			if int(ev["attacker"]) == local_id or int(ev["target"]) == local_id:
				_juice(0.05, 0.25)
			if t != null:
				_ragdoll_attacker[int(ev["target"])] = int(ev["attacker"])
				t.start_ragdoll(Serializer.to_vec3(ev["velocity"]), 3.0, not _owns_server)
				if _owns_server:
					server.set_server_owned(int(ev["target"]), true)
				Audio.play_at(&"whoosh", t, -8.0)
		&"chips_dropped":
			_spawn_pile(int(ev["pile"]), int(ev["amount"]), Serializer.to_vec3(ev["pos"]), int(ev.get("source", -1)))
		&"chips_collected":
			_on_chips_collected(int(ev["pile"]), int(ev["player"]), int(ev["amount"]))
		&"pickup_expired":
			var gone: ChipPile = piles.get(int(ev["pile"]), null)
			piles.erase(int(ev["pile"]))
			if gone != null:
				gone.fade_out()
		&"chips_shaken_out":
			var at: PlayerAvatar = avatars.get(int(ev["attacker"]), null)
			if at != null:
				at.visuals.react(&"win")
				Audio.play_at(&"coin", at, -4.0)
		&"player_sat":
			_seat(int(ev["player"]), StringName(ev["station"]), int(ev.get("seat", -1)))
		&"player_stood":
			_unseat(int(ev["player"]))
		&"player_thrown_out":
			_throw_out(int(ev["target"]), String(ev.get("guard", "guard")))
		&"emote":
			EmoteWheel.present(avatars.get(int(ev["player"]), null), StringName(ev["id"]))
		&"intent_rejected":
			if int(ev["player"]) == local_id:
				_end_prediction(StringName(ev.get("intent", &"")), true)
				var err: StringName = StringName(ev["error"])
				if err == &"vip_denied":
					Audio.play(&"buzzer", &"SFX", -4.0)
					hud.toast("VIP ACCESS — $%d+" % _vip_threshold(), 2.0)
				elif ev.get("intent", &"") == &"use_item" or ev.get("intent", &"") == &"discard_item":
					hud.toast(ItemController.rejection_text(err), 1.5)
				elif ev.get("intent", &"") == &"shove" and err in [&"no_target", &"cooldown"]:
					pass  # a whiff: the swing already showed it
				elif err != &"rate_limited" and err != &"not_standing":
					hud.toast(StationUi.rejection_text(err), 1.5)
		&"round_result":
			var p: PlayerAvatar = avatars.get(int(ev["player"]), null)
			var net: int = int(ev["net"])
			if p != null and net != 0:
				p.visuals.react(AvatarVisuals.reaction_for_net(net))
			var details: Dictionary = ev.get("details", {})
			if details.has("drop_id") and details.has("slot"):  # missed the drop (joined late): quick fall
				_drop_plinko_chip(StringName(ev["station"]), int(ev["player"]), int(details["slot"]), int(details["drop_id"]), 0.9, StringName(details.get("risk", "")))
		&"plinko_dropped":  # the chip falls now and touches down as the server settles it
			_drop_plinko_chip(StringName(ev["station"]), int(ev["player"]), int(ev["slot"]), int(ev["drop_id"]), Registry.balance.plinko_flight_time, StringName(ev.get("risk", "")))
		&"jackpot_won":
			# Patrick's 8-bit prize fanfare: full volume for the winner, from the winner's spot for
			# everyone else, with the siren quietly announcing it across the floor.
			var winner: PlayerAvatar = avatars.get(int(ev["player"]), null)
			if int(ev["player"]) == local_id or winner == null:
				Audio.play(&"jackpot_prize", &"SFX", -2.0)
			else:
				Audio.play_at(&"jackpot_prize", winner, 0.0)
				Audio.play(&"jackpot_siren", &"SFX", -12.0)
			if winner != null:
				winner.visuals.react(&"big_win")
		&"last_call":
			Audio.play(&"last_call_announce", &"SFX", 0.0)
		&"phase_changed":
			var phase: Phase.Id = int(ev["phase"]) as Phase.Id
			if phase != Phase.Id.LOBBY:
				map.set_lobby_open(true)
				if lobby_panel.visible:
					lobby_panel.close()
			if phase == Phase.Id.INTRO:
				hud.toast("WELCOME TO THE LUCKY LOUNGE", 3.0)
			elif phase == Phase.Id.CASINO and int(ev.get("from", -1)) == Phase.Id.INTRO:
				hud.toast("Gamble. Shove. Don't get caught.", 3.0)
			elif phase == Phase.Id.CASINO and int(ev.get("from", -1)) == Phase.Id.REWARDS:
				_back_to_casino()
			elif phase == Phase.Id.PRE_MINIGAME:
				Audio.play(&"countdown_beep", &"SFX", -4.0, 0.8)
		&"minigame_started":
			_open_stage(ev, {})
		&"rewards_started":
			if role != Role.SERVER:
				reward_panel.open(ev["rewards"], float(ev["seconds"]))
		&"draft_result":
			if int(ev["player"]) == local_id:
				reward_panel.show_result(ev.get("items", []), ev.get("kept", []))
				if not (ev.get("items", []) as Array).is_empty():
					_hint(&"items", "New item! Press {item_1}, {item_2} or {item_3} to use it.", 3.0)
		&"hot_table":
			Audio.play(&"hot_table_announce", &"SFX", -2.0)
			hud.banner("%s IS HOT!  Winnings ×%.2f  (follow the arrow)" % [ClientMatchState.station_label(StringName(ev["station"])).to_upper(), float(ev["multiplier"])], Color(1.0, 0.55, 0.1), 4.0)
		&"house_comp":
			if int(ev["player"]) == local_id:
				hud.toast("The house feels sorry for you: +$%d" % int(ev["amount"]), 3.0)
				Audio.play(&"cash_register", &"SFX", -4.0)
		&"match_ended":
			_match_over = true
			_show_results(ev["standings"])
			_log_digest()
		&"match_reset":
			_on_match_reset()
		&"item_used":
			_on_item_used(ev)
		&"bodyguard_saved":
			var p: PlayerAvatar = avatars.get(int(ev["player"]), null)
			if p != null:
				p.say("BODYGUARD!", 1.5)
				Audio.play_at(&"bonk", p, -4.0, 0.7)
			if int(ev["player"]) == local_id:
				hud.banner("Your Bodyguard took the hit!", Palette.MONEY_GREEN)
		&"banana_slip":
			var v: PlayerAvatar = avatars.get(int(ev["victim"]), null)
			if v != null and ev["result"] != &"blocked":
				v.knockback(Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized(), 3.0)
				v.visuals.react(&"slip")
				Audio.play_at(&"slip", v, -4.0)
			if ev["result"] == &"blocked":
				var p: PlayerAvatar = avatars.get(int(ev["player"]), null)
				if p != null:
					p.say("BODYGUARD!", 1.5)
			if int(ev["victim"]) == local_id and ev["result"] != &"blocked":
				hud.banner("SLIPPED! −$%d" % int(ev["amount"]), Palette.LOSS_RED)
		&"monkey_passed":
			var to: PlayerAvatar = avatars.get(int(ev["to"]), null)
			if to != null:
				to.say("MONKEY!", 1.5)
			if int(ev["to"]) == local_id:
				hud.banner("%s passed you the Bad Luck Monkey!" % view.state.player_name(int(ev["from"])), Palette.LOSS_RED)
			elif int(ev["from"]) == local_id:
				hud.banner("Monkey passed to %s!" % view.state.player_name(int(ev["to"])), Palette.MONEY_GREEN)
		&"credit_repaid":
			if int(ev["player"]) == local_id:
				hud.banner("The bank collected $%d" % int(ev["amount"]), Palette.LOSS_RED)
		&"collar_cut":
			if int(ev["owner"]) == local_id:
				hud.toast("Collar cut from %s: +$%d" % [view.state.player_name(int(ev["player"])), int(ev["amount"])], 1.5)
		&"fake_cash_used":
			if int(ev["player"]) == local_id and not bool(ev["caught"]):
				hud.toast("The bouncer didn't notice the fake cash ($%d)" % int(ev["amount"]), 2.0)
		&"fake_cash_caught":
			var p: PlayerAvatar = avatars.get(int(ev["player"]), null)
			if p != null:
				p.say("FAKE?!", 1.5)
			if int(ev["player"]) == local_id:
				hud.banner("FAKE CASH! Fined $%d" % int(ev["fine"]), Palette.LOSS_RED, 3.0)
		&"rps_invite":
			if int(ev["to"]) == local_id:
				hud.banner("%s challenges you to Rock Paper Scissors!" % view.state.player_name(int(ev["from"])), Palette.VIP_GOLD)
				Audio.play(&"countdown_beep", &"UI", -6.0, 1.0)
		&"rps_start":
			if int(ev["a"]) == local_id or int(ev["b"]) == local_id:
				hud.banner("TIE! Go again" if bool(ev["replay"]) else "ROCK… PAPER… SCISSORS!", Palette.VIP_GOLD, 1.5)
		&"rps_result":
			for k: String in ["a", "b"]:
				var p: PlayerAvatar = avatars.get(int(ev[k]), null)
				if p != null:
					p.say(String(ev["pick_" + k]).to_upper() + "!", 2.0)
			if not bool(ev["replay"]) and (int(ev["a"]) == local_id or int(ev["b"]) == local_id):
				var w: int = int(ev["winner"])
				if w < 0:
					hud.banner("Tied twice: nobody pays", Palette.CREAM)
				elif w == local_id:
					hud.banner("YOU WIN! +$%d" % int(ev["amount"]), Palette.MONEY_GREEN)
				else:
					hud.banner("You lost the duel: −$%d" % int(ev["amount"]), Palette.LOSS_RED)
		&"rps_cancelled":
			if int(ev["a"]) == local_id:
				match StringName(ev["reason"]):
					&"declined":
						hud.toast("%s turned down your challenge" % view.state.player_name(int(ev["b"])), 2.0)
					&"no_answer":
						hud.toast("%s didn't answer your challenge" % view.state.player_name(int(ev["b"])), 2.0)
		&"shop_bought":
			if int(ev["player"]) == local_id:
				hud.banner("Bought %s" % RewardPanel.item_name(StringName(ev["item"])), Palette.MONEY_GREEN)
		&"shop_restocked":
			shop_panel.close_panel()
		&"discard_needed":
			if int(ev["player"]) == local_id:
				items_ctl.on_discard_needed()
				Audio.play(&"countdown_beep", &"UI", -8.0, 1.2)


## Item activation for everyone: the user calls it out, the target reacts, the local player gets a
## banner when they used it or were hit.
## While a table is hot and off screen, an arrow on the screen edge points the way to it.
func _point_at_hot_table() -> void:
	var node: StationBase = map.stations.get(view.state.hot_station, null) if view.state.hot_station != &"" else null
	if node == null or local == null or local.cam == null or results_panel != null:
		hud.set_hot_pointer(false)
		return
	var cam: Camera3D = local.cam.camera
	var target: Vector3 = node.global_position + Vector3(0, 2.0, 0)
	var size: Vector2 = get_viewport().get_visible_rect().size
	var on_screen: bool = not cam.is_position_behind(target)
	var p: Vector2 = PixelView.to_canvas(cam, cam.unproject_position(target), hud)
	if on_screen and Rect2(Vector2.ZERO, size).grow(-40.0).has_point(p):
		hud.set_hot_pointer(false)
		return
	var centre: Vector2 = size * 0.5
	var dir: Vector2 = (p - centre)
	if not on_screen:
		dir = -dir  # unproject mirrors points behind the camera
	if dir.length() < 1.0:
		dir = Vector2.DOWN
	dir = dir.normalized()
	var half: Vector2 = centre - Vector2(70, 90)
	var t: float = minf(absf(half.x / dir.x) if dir.x != 0.0 else INF, absf(half.y / dir.y) if dir.y != 0.0 else INF)
	hud.set_hot_pointer(true, centre + dir * t, dir.angle())


## The item's model (when it has one) pops up in front of the user for a moment.
func _hold_up_prop(u: PlayerAvatar, item: StringName) -> void:
	var id: StringName = PropModels.ITEM_PROPS.get(item, &"")
	if id == &"":
		return
	var prop: Node3D = PropModels.make(id, 0.3)
	prop.position = Vector3(0.3, 1.25, -0.45)
	u.add_child(prop)
	var t: Tween = prop.create_tween()
	t.tween_property(prop, ^"position:y", 1.6, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(1.0)
	t.tween_property(prop, ^"scale", Vector3.ONE * 0.01, 0.25)
	t.tween_callback(prop.queue_free)


func _on_item_used(ev: Dictionary) -> void:
	var user: int = int(ev["player"])
	var target: int = int(ev["target"])
	var result: StringName = StringName(ev["result"])
	var item: StringName = StringName(ev["item"])
	var def: ItemDefinition = Registry.items.get(item, null)
	var name: String = def.display_name if def != null else String(item).capitalize()
	var u: PlayerAvatar = avatars.get(user, null)
	var t: PlayerAvatar = avatars.get(target, null) if target != user else null
	if u != null:
		u.say(name.to_upper() + "!", 1.5)
		u.visuals.react(&"win")
		_hold_up_prop(u, item)
		Audio.play_at(&"whoosh", u, -8.0, 1.2)
	if user == local_id:
		items_ctl.on_local_use()
	var negative: bool = def != null and def.is_negative
	match result:
		&"blocked":
			if t != null:
				t.say("BODYGUARD!", 1.5)
				Audio.play_at(&"bonk", t, -4.0, 0.7)
			if user == local_id:
				hud.banner("%s blocked by a Bodyguard" % name, Palette.LOSS_RED)
			elif target == local_id:
				hud.banner("Your Bodyguard blocked %s!" % name, Palette.MONEY_GREEN)
			return
		&"reflected":
			if t != null:
				t.say("MIRROR!", 1.5)
			if user == local_id:
				hud.banner("MIRRORED! Your %s bounced back" % name, Palette.LOSS_RED)
			elif target == local_id:
				hud.banner("Your Mirror bounced %s back!" % name, Palette.MONEY_GREEN)
			return
	match item:
		&"scratch_ticket":
			if user == local_id:
				if ev.get("prize", &"") == &"cash":
					hud.banner("SCRATCH! You won $%d" % int(ev.get("amount", 0)), Palette.MONEY_GREEN)
				else:
					hud.banner("SCRATCH! You got %s" % RewardPanel.item_name(StringName(ev.get("won_item", ""))))
				Audio.play(&"coin", &"SFX", -2.0)
			return
		&"russian_roulette":
			if bool(ev.get("bang", false)):
				if u != null:
					u.say("BANG!", 2.0)
					u.visuals.react(&"loss")
					Audio.play_at(&"bonk", u, 0.0, 0.6)
				if user == local_id:
					hud.banner("BANG! −$%d into the jackpot" % int(ev.get("amount", 0)), Palette.LOSS_RED, 3.0)
			else:
				if u != null:
					u.say("*click*", 1.5)
				if user == local_id:
					hud.banner("*click*  +$%d   (next: %d%% bang)" % [int(ev.get("amount", 0)), roundi(float(ev.get("next_odds", 0.0)) * 100.0)], Palette.MONEY_GREEN)
			return
		&"credit_card":
			if user == local_id:
				hud.banner("+$%d on credit. Pay back $%d in %ds" % [int(ev.get("loan", 0)), int(ev.get("debt", 0)), int(ev.get("seconds", 0))], Palette.VIP_GOLD, 3.0)
			return
		&"baseball_bat", &"empty_bottle":
			if t != null:
				Audio.play_at(&"bonk", t, 0.0, 0.7 if item == &"baseball_bat" else 1.2)
			if target == local_id:
				hud.banner("%s got you with a %s! −$%d" % [view.state.player_name(user), name, int(ev.get("amount", 0))], Palette.LOSS_RED)
			elif user == local_id:
				hud.banner("BONK! %s dropped $%d" % [view.state.player_name(target), int(ev.get("amount", 0))], Palette.MONEY_GREEN)
			return
	if item == &"pickpocket" and bool(ev.get("caught", false)):
		var thief: PlayerAvatar = avatars.get(user, null)
		if thief != null:
			thief.say("oops", 1.5)
		if user == local_id:
			hud.banner("CAUGHT! You paid %s $%d" % [view.state.player_name(target), int(ev.get("paid", 0))], Palette.LOSS_RED)
		elif target == local_id:
			hud.banner("You caught %s's hand in your pocket: +$%d" % [view.state.player_name(user), int(ev.get("paid", 0))], Palette.MONEY_GREEN)
		return
	if item == &"pickpocket":
		var victim: PlayerAvatar = avatars.get(int(ev.get("victim", target)), null)
		if victim != null:
			victim.say("HEY!", 1.6)
			victim.visuals.react(&"loss")
			Audio.play_at(&"coin", victim, -4.0, 1.3)
		if int(ev.get("victim", target)) == local_id:
			hud.banner("PICKPOCKETED by %s! −$%d" % [view.state.player_name(user), int(ev.get("amount", 0))], Palette.LOSS_RED)
		elif user == local_id:
			hud.banner("Pickpocketed $%d!" % int(ev.get("amount", 0)), Palette.MONEY_GREEN)
		return
	if t != null and negative:
		t.visuals.react(&"loss")
	if user == local_id:
		hud.banner(name.to_upper() + (" → %s" % view.state.player_name(target) if target != user and target >= 0 else ""))
		Audio.play(&"chip_clack", &"UI", -4.0, 1.3)
	elif target == local_id and negative:
		hud.banner("%s hit you with %s!" % [view.state.player_name(user), name], Palette.LOSS_RED)


## Banana peel meshes follow the replicated peel list.
func _sync_peels() -> void:
	for id: int in peel_nodes.keys():
		if not view.state.peels.has(id):
			peel_nodes[id].queue_free()
			peel_nodes.erase(id)
	for id: int in view.state.peels:
		if peel_nodes.has(id):
			continue
		var n: Node3D = _make_peel()
		world_root.add_child(n)
		n.global_position = Serializer.to_vec3(view.state.peels[id]["pos"]) + Vector3(0, 0.04, 0)
		n.rotation.y = randf() * TAU
		peel_nodes[id] = n


static func _make_peel() -> Node3D:
	var root := Node3D.new()
	root.name = "BananaPeel"
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#F2D04B")
	mat.roughness = 0.6
	for i: int in 3:
		var leaf := MeshInstance3D.new()
		var m := CapsuleMesh.new()
		m.radius = 0.06
		m.height = 0.42
		leaf.mesh = m
		leaf.material_override = mat
		leaf.rotation = Vector3(PI / 2.0 - 0.25, i * TAU / 3.0, 0)
		leaf.position = Vector3(sin(i * TAU / 3.0), 0, cos(i * TAU / 3.0)) * 0.14
		root.add_child(leaf)
	return root


## Short tags over a player's head for their active effects ("LUCKY", "JINXED", "×2"…).
func _refresh_effect_tag(pid: int) -> void:
	var a: PlayerAvatar = avatars.get(pid, null)
	if a == null:
		return
	var parts: PackedStringArray = []
	for id: Variant in view.state.effects.get(pid, []):
		parts.append(_effect_tag_text(StringName(id)))
	var fx: Array = view.state.effects.get(pid, [])
	a.speed_multiplier = 1.4 if fx.has(&"energy_drink") else 1.0
	if pid == local_id:
		_set_drunk(fx.has(&"beer"))
	var held: Variant = effect_tags.get(pid, null)
	var tag: Label3D = held as Label3D if is_instance_valid(held) and (held as Node).get_parent() == a else null
	if tag == null:
		if parts.is_empty():
			return
		tag = Label3D.new()
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.font_size = 36
		tag.outline_size = 8
		tag.pixel_size = 0.004
		tag.position = Vector3(0, 2.15, 0)
		tag.modulate = Palette.VIP_GOLD
		a.add_child(tag)
		effect_tags[pid] = tag
	tag.text = " ".join(parts)
	tag.visible = not parts.is_empty()


## Beer on the local player: blurry screen, inverted look, hidden money; sobering up shows what
## happened to your money meanwhile.
func _set_drunk(on: bool) -> void:
	if on == drunk_overlay.visible:
		return
	drunk_overlay.visible = on
	router.drunk = on
	hud.money_hidden = on
	var mat: ShaderMaterial = drunk_overlay.material as ShaderMaterial
	if on:
		_drunk_money = view.state.balance(local_id)
		var t: Tween = create_tween()
		t.tween_method(func(v: float) -> void: mat.set_shader_parameter(&"strength", v), 0.0, 1.0, 1.5)
	else:
		mat.set_shader_parameter(&"strength", 0.0)
		if _drunk_money >= 0:
			var diff: int = view.state.balance(local_id) - _drunk_money
			hud.banner("Sobered up: %s$%d" % ["+" if diff >= 0 else "−", absi(diff)], Palette.MONEY_GREEN if diff >= 0 else Palette.LOSS_RED, 3.0)
		_drunk_money = -1


static func _effect_tag_text(id: StringName) -> String:
	match id:
		&"bad_luck_monkey":
			return "MONKEY"
		&"vip_pass":
			return "VIP PASS"
		&"energy_drink":
			return "WIRED"
		&"credit_card":
			return "IN DEBT"
		&"dog_collar":
			return "COLLARED"
		&"fake_cash":
			return "FAKE $"
		&"scissors":
			return "SCISSORS"
		&"beer":
			return "TIPSY"
		&"sunglasses":
			return "SHADES"
		&"lucky_clover":
			return "LUCKY"
		&"black_cat":
			return "JINXED"
		&"hot_hands":
			return "HOT HANDS"
		&"loaded_reels":
			return "LOADED"
		&"double_down":
			return "×2"
		&"golden_chip":
			return "GOLD CHIP"
		&"bodyguard":
			return "GUARDED"
		&"mirror":
			return "MIRROR"
		&"boxing_glove":
			return "GLOVE"
	return String(id).to_upper()


func _knock_out(target: int, attacker: int, cause: StringName) -> void:
	var t: PlayerAvatar = avatars.get(target, null)
	if t == null:
		return
	if _owns_server:
		_ko_until[target] = _clock + cfg.knockout_time
		server.set_server_owned(target, true)
	_ragdoll_attacker[target] = attacker
	if t.state != PlayerAvatar.State.RAGDOLL:
		var dir: Vector3 = -t.facing()
		var at: PlayerAvatar = avatars.get(attacker, null)
		if at != null:
			dir = (t.global_position - at.global_position)
			dir.y = 0.0
			dir = dir.normalized() if dir.length() > 0.01 else -t.facing()
		t.start_ragdoll(dir * 3.0 + Vector3.UP * 2.5, cfg.knockout_time + 1.0, not _owns_server)
	if t.ragdoll != null:
		t.ragdoll.max_time = cfg.knockout_time + 1.0
	t.visuals.set_knocked_out(true)
	if cause == &"fountain":
		FountainSplash.at_fountain(world_root, t.global_position, true)
	Audio.play_at(&"bonk", t, -2.0, 0.8)
	if target == local_id:
		hud.toast("KNOCKED OUT" if cause != &"fountain" else "SPLASH! Knocked out", 2.0)


func _seat(pid: int, sid: StringName, seat: int = -1) -> void:
	var a: PlayerAvatar = avatars.get(pid, null)
	var st: StationBase = map.stations.get(sid, null)
	if a == null or st == null:
		return
	view.resync()
	var idx: int = seat if seat >= 0 else _seat_index(sid, pid)
	a.sit(st.seats[clampi(idx, 0, st.seats.size() - 1)] if not st.seats.is_empty() else st, st.camera_for_seat(idx))
	if pid == local_id:
		router.set_play_mode(InputRouter.Mode.SEATED)
		if st is BlackjackStation:
			(st as BlackjackStation).set_viewer_seat(idx)
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
	if pid == local_id and a.seat != null and a.seat.get_parent() is BlackjackStation:
		(a.seat.get_parent() as BlackjackStation).set_viewer_seat(-1)
	a.stand()
	_report_position(pid)
	if pid == local_id:
		if current_ui != null:
			current_ui.close()
			current_ui = null
		hud.set_crosshair_visible(true)
		router.set_play_mode(InputRouter.Mode.WALK)


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
	# The guard who caught them carries them toward the door and tosses them (Guard.carry).
	var carrier: Guard = null
	for g: Guard in guards:
		if String(g.guard_id) == guard_name:
			carrier = g
	if carrier == null or not carrier.carry(a, LuckyLounge.ENTRANCE_POS):
		a.start_ragdoll(dir * 9.0 + Vector3.UP * 4.0, 1.6, not _owns_server)
	if _owns_server:
		_respawn_at[pid] = _clock + cfg.throw_out_respawn_seconds
		server.set_server_owned(pid, true)
	Audio.play_at(&"whistle", a, -4.0)
	if pid == local_id:
		hud.toast("Security threw you out!", 3.0)


func _show_results(_standings: Array) -> void:
	if results_panel != null or role == Role.SERVER:
		return
	_close_stage()
	reward_panel.close()
	router.set_mode(InputRouter.Mode.MENU)
	hud.visible = false
	results_panel = ResultsStage.new()
	results_panel.name = "Results"
	results_panel.ui_host = self  # its 2D stays sharp outside the pixelated world
	pixel_view.world.add_child(results_panel)
	results_panel.setup(view.state, local_id, view.state.room_mode)
	results_panel.play_again_pressed.connect(func() -> void:
		if view.state.room_mode:
			Net.send_intent(Intents.make(&"return_to_lobby"))
		else:
			SceneRouter.goto(SceneRouter.MATCH))
	results_panel.leave_pressed.connect(_leave_to_menu)


# --- Minigames ---------------------------------------------------------------------------------

## Opens the stage for a minigame (`minigame_started`, or the snapshot when joining mid-game).
func _open_stage(start: Dictionary, snapshot_state: Dictionary) -> void:
	if role == Role.SERVER:
		return
	_close_stage()
	var def: MinigameDefinition = Registry.minigames.get(StringName(start.get("minigame", "")), null)
	if def == null or def.stage_script == null:
		Log.warn(&"match", "no stage for minigame %s" % start.get("minigame", "?"))
		return
	stage = def.stage_script.new() as MinigameStage
	stage.name = "MinigameStage"
	stage.ui_host = self  # its 2D stays sharp outside the pixelated world
	pixel_view.world.add_child(stage)
	stage.begin(view.state, local_id, start, snapshot_state)
	# The minigame owns the screen: every table panel, menu and wheel goes away, and the cursor
	# stays put (STAGE mode ignores sit/stand/menu-closed mode changes until the stage is over).
	router.set_mode(InputRouter.Mode.STAGE)
	current_ui = null
	for ui: StationUi in station_uis.values():
		ui.close()
	emote_wheel.visible = false
	lobby_panel.close()
	shop_panel.close_panel()
	if settings_panel != null and settings_panel.visible:
		settings_panel.close()
	hud.visible = false
	if local != null:
		local.auto_target = Vector3.INF
	Audio.play(&"whoosh", &"SFX", -4.0)


func _close_stage() -> void:
	if stage != null:
		stage.queue_free()
		stage = null


## Rewards over: back on the casino floor with spawn protection.
func _back_to_casino() -> void:
	_close_stage()
	reward_panel.close()
	if role == Role.SERVER:
		return
	hud.visible = true
	if local != null:
		local.cam.activate()
		var seated: bool = local.state == PlayerAvatar.State.SEATED
		router.set_mode(InputRouter.Mode.SEATED if seated else InputRouter.Mode.WALK)
		if seated and current_ui == null:
			var sid: StringName = view.state.seat_of.get(local_id, &"")
			var st: StationBase = map.stations.get(sid, null)
			var ui: StationUi = station_uis.get(st.game_id, null) if st != null else null
			if ui != null:
				current_ui = ui
				ui.open(sid, local_id, view.state)
				_on_station_state(sid)
	hud.toast("Back to the tables! (%ds spawn protection)" % int(cfg.spawn_protection), 2.5)


## A view created mid-match (late join, reconnect) catches up with a minigame, rewards or results.
func _catch_up_phase() -> void:
	var st: ClientMatchState = view.state
	match st.phase:
		Phase.Id.MINIGAME:
			if not st.minigame.is_empty():
				_open_stage({"minigame": st.minigame.get("minigame", &"quiz"), "players": st.minigame.get("players", [])}, st.minigame)
		Phase.Id.REWARDS:
			if role != Role.SERVER:
				reward_panel.open(st.rewards, Registry.balance.draft_time)
				hud.visible = false
				router.set_mode(InputRouter.Mode.MENU)
		Phase.Id.RESULTS:
			_match_over = true
			_show_results(st.standings)


## Online room went back to its lobby for another match ("play again in the same room").
func _on_match_reset() -> void:
	if results_panel != null:
		results_panel.queue_free()
		results_panel = null
	_close_stage()
	reward_panel.close()
	_match_over = false
	_countdown_shown = -1
	_ko_until.clear()
	_respawn_at.clear()
	_ragdoll_attacker.clear()
	for id: int in piles.keys():
		_remove_pile(id)
	for pid: int in effect_tags.keys():
		_refresh_effect_tag(pid)
	items_ctl.cancel()
	map.set_lobby_open(false)
	for pid: int in avatars:
		var a: PlayerAvatar = avatars[pid]
		if a.state == PlayerAvatar.State.RAGDOLL:
			a.end_ragdoll(map.lobby_spawn(pid))
		elif a.state == PlayerAvatar.State.SEATED:
			a.stand()
		elif a.state == PlayerAvatar.State.HELD:
			a.release_held()
		if a.state == PlayerAvatar.State.AWAY:
			a.set_away(false)
		a.visuals.set_knocked_out(false)
		if _owns_server or pid == local_id:
			a.teleport(map.lobby_spawn(pid), 0.0)
			if _owns_server:
				server.set_server_position(pid, map.lobby_spawn(pid))
			else:
				_report_position(pid)
		if net_world != null:
			net_world.reset_player(pid)
	if current_ui != null:
		current_ui.close()
		current_ui = null
	if role == Role.SERVER:
		return
	hud.visible = true
	hud.reset_match()
	if local != null:
		local.cam.activate()
	router.set_mode(InputRouter.Mode.WALK)
	hud.toast("Back in the lobby! Stand on your READY pad for another round.", 4.0)
	Audio.play_music(&"casino_loop")


# --- Local input -------------------------------------------------------------------------------

func _on_interact() -> void:
	if local != null and _local_holding() >= 0:
		_throw_held()
		return
	if local == null or not local.is_standing():
		return
	var lobby_spot: StringName = _lobby_spot()
	if lobby_spot != &"":
		_open_lobby_panel(lobby_spot)
		return
	if casino_floor != null and casino_floor.interact():
		return
	if _near_shop():
		router.set_mode(InputRouter.Mode.MENU)
		shop_panel.open()
		return
	if nearest_station != null:
		var res: Dictionary = Net.send_intent(Intents.make(&"sit", {"station": nearest_station.station_id}))
		if not res["ok"] and res["error"] != &"vip_denied":
			hud.toast(StationUi.rejection_text(res["error"]), 1.5)
		return
	# Nothing to sit at: try grabbing whoever is in front.
	_on_grab()


func _throw_held() -> void:
	local.visuals.swing()
	_swing_started = _clock
	Audio.play_at(&"whoosh", local, -10.0, randf_range(0.9, 1.05))
	Net.send_intent(Intents.make(&"release", {"throw": true, "aim": Serializer.vec3(local.aim())}))


func _on_grab() -> void:
	if local != null and _local_holding() >= 0:
		_throw_held()
		return
	if local == null or not local.is_standing():
		return
	var target: int = _reach_target(true)
	if target >= 0:
		_predict(&"grab")
		Net.send_intent(Intents.make(&"grab", {"target": target}))


## Client-side prediction (§4.1): the arms go out the moment you press, before the server answers.
## A confirming event keeps (grab) or finishes (shove) the pose; a rejection or silence drops it.
func _predict(kind: StringName) -> void:
	if local == null:
		return
	local.visuals.reaching = true
	local.visuals.reach_target = PlayerAvatar.HELD_OFFSET
	_predicted[kind] = _clock + PREDICTION_TIMEOUT
	if kind == &"grab":
		Audio.play_at(&"whoosh", local, -16.0, randf_range(1.3, 1.5))


func _end_prediction(kind: StringName, _denied: bool) -> void:
	if not _predicted.has(kind):
		return
	_predicted.erase(kind)
	if local != null and _local_holding() < 0:
		local.visuals.reaching = false


## Shove press (§4.1 prediction): the swing and whoosh start now; the hit lands on the server's
## word, synced to the swing's contact moment. The server keeps the real cooldown; this gate just
## keeps the swing from promising a hit the server will refuse.
func _local_shove() -> void:
	if local == null or not local.is_standing() or _clock < _shove_ready_at:
		return
	_shove_ready_at = _clock + cfg.shove_cooldown + 0.1
	_swing_started = _clock
	local.visuals.swing()
	Audio.play_at(&"whoosh", local, -12.0, randf_range(1.15, 1.35))
	var payload: Dictionary = {"aim": Serializer.vec3(local.facing())}
	var target: int = _reach_target(false)
	if target >= 0:
		payload["target"] = target
		if role == Role.CLIENT:
			# Online the server's word is a round trip away: land the hit on the swing's contact
			# moment anyway (pop, bonk, flinch); the confirmation then only moves the body.
			_predicted_hit = target
			_predicted_hit_at = _clock
			var push: Vector3 = avatars[target].global_position - local.global_position
			push.y = 0.0
			push = push.normalized() if push.length() > 0.01 else local.facing()
			_after(AvatarVisuals.SWING_CONTACT, func() -> void: _impact_effects(local_id, target, push, false))
	Net.send_intent(Intents.make(&"shove", payload))


func _on_shoved(ev: Dictionary) -> void:
	var attacker: int = int(ev["attacker"])
	var target: int = int(ev["target"])
	var at: PlayerAvatar = avatars.get(attacker, null)
	var delay: float = AvatarVisuals.SWING_CONTACT
	if attacker == local_id and _clock - _swing_started < 0.6:
		delay = maxf(_swing_started + AvatarVisuals.SWING_CONTACT - _clock, 0.0)  # our swing is already out
	elif at != null:
		at.visuals.swing()
	_impact_at[target] = _clock + delay
	var dir: Vector3 = Serializer.to_vec3(ev["dir"])
	_impact_dir[target] = dir
	var glove: bool = bool(ev.get("spring_glove", false))
	var strength: float = float(ev["knockback"]) * (SHOVE_GLOVE_SCALE if glove else SHOVE_PUSH_SCALE)
	var shown: bool = attacker == local_id and _predicted_hit == target and _clock - _predicted_hit_at < 1.0
	if shown:
		_predicted_hit = -1
	_after(delay, func() -> void: _shove_impact(attacker, target, dir, strength, glove, not shown))


## The moment the hands land: knockback, flinch, bonk, a pop at the contact point, and hit-stop
## plus shake when it's us giving or taking it.
func _shove_impact(attacker: int, target: int, dir: Vector3, strength: float, glove: bool, effects: bool = true) -> void:
	_impact_at.erase(target)
	var t: PlayerAvatar = avatars.get(target, null)
	if t == null or not is_instance_valid(t):
		return
	if t.is_standing():
		t.knockback(dir, strength, 0.45)
		t.stun(0.3)
	if effects:
		_impact_effects(attacker, target, dir, glove or t.state == PlayerAvatar.State.STUNNED)


## Pop, bonk and (for us) hit-stop and shake where a shove lands.
func _impact_effects(attacker: int, target: int, dir: Vector3, heavy: bool) -> void:
	var t: PlayerAvatar = avatars.get(target, null)
	if t == null or not is_instance_valid(t):
		return
	if t.drive == PlayerAvatar.Drive.PUPPET and attacker == local_id:
		t.visuals.hit(dir, 1.0)  # predicted: the body moves when the server's stream says so
	Audio.play_at(&"bonk", t, -4.0 if heavy else -6.0, randf_range(0.9, 1.1))
	var contact: Vector3 = t.global_position + Vector3(0.0, 1.05, 0.0) - dir.normalized() * 0.4
	HitPop.at(world_root, contact, 2.0 if heavy else 1.0)
	if target == local_id:
		_juice(0.07, 0.45 if heavy else 0.3)
	elif attacker == local_id:
		_juice(0.06, 0.15)


## Knocked down by a shove, a wall slam or an item: a ragdoll launched along the hit until the
## knockdown ends. The host simulates it (and owns the body); clients show the streamed pose.
func _knock_down(pid: int, attacker: int, seconds: float) -> void:
	var t: PlayerAvatar = avatars.get(pid, null)
	if t == null or not (t.is_standing() or t.state == PlayerAvatar.State.SEATED or t.state == PlayerAvatar.State.HELD):
		return
	var dir: Vector3 = _impact_dir.get(pid, Vector3.ZERO)
	_impact_dir.erase(pid)
	var at: PlayerAvatar = avatars.get(attacker, null)
	if dir == Vector3.ZERO and at != null:
		dir = t.global_position - at.global_position
		dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else -t.facing()
	_ragdoll_attacker[pid] = attacker
	t.start_ragdoll(dir * 3.5 + Vector3.UP * 2.2, seconds + 1.5, not _owns_server)
	if _owns_server:
		server.set_server_owned(pid, true)
		_down_until[pid] = _clock + seconds
	if pid == local_id:
		_juice(0.0, 0.35)


func _juice(stop_seconds: float, shake: float) -> void:
	if table_fx == null or table_fx.juice == null:
		return
	if stop_seconds > 0.0:
		table_fx.juice.hit_stop(stop_seconds, 0.06)
	table_fx.juice.shake(shake)


## Runs `fn` after `seconds` of game time (right away when that's not positive).
func _after(seconds: float, fn: Callable) -> void:
	if seconds <= 0.001 or not is_inside_tree():
		fn.call()
		return
	get_tree().create_timer(seconds, false).timeout.connect(fn)


func _expire_predictions() -> void:
	for kind: StringName in _predicted.keys():
		if _clock >= _predicted[kind]:
			_end_prediction(kind, false)


func _on_pause() -> void:
	if results_panel != null or router.mode == InputRouter.Mode.STAGE:
		return  # the settings live on the HUD, which a minigame hides
	if settings_panel != null and settings_panel.visible:
		settings_panel.close()
	elif router.mode == InputRouter.Mode.MENU:
		_resume_play()
	else:
		if settings_panel == null:
			settings_panel = SettingsPanel.new()
			settings_panel.closed.connect(_resume_play)
			settings_panel.leave_requested.connect(_leave_to_menu)
			hud.add_child(settings_panel)
		router.set_mode(InputRouter.Mode.MENU)
		settings_panel.open(true)


func _resume_play() -> void:
	router.set_play_mode(InputRouter.Mode.SEATED if local != null and local.state == PlayerAvatar.State.SEATED else InputRouter.Mode.WALK)
	hud.toast("", 0.0)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_F10:
		_leave_to_menu()


# --- World checks ------------------------------------------------------------------------------

## &"wardrobe"/&"settings" when the local player stands at the mirror/settings board in the lobby.
func _lobby_spot() -> StringName:
	if local == null or not view.state.room_mode or view.state.phase != Phase.Id.LOBBY:
		return &""
	var p: Vector3 = local.global_position
	if Vector2(p.x - LuckyLounge.MIRROR_POS.x, p.z - LuckyLounge.MIRROR_POS.z).length() < 2.6:
		return &"wardrobe"
	if Vector2(p.x - LuckyLounge.SETTINGS_BOARD_POS.x, p.z - LuckyLounge.SETTINGS_BOARD_POS.z).length() < 2.6:
		return &"settings"
	return &""


func _update_prompt() -> void:
	nearest_station = null
	if local != null and _local_holding() >= 0:
		hud.set_prompt(InputGlyphs.fill("[{grab} / {shove} / {interact}] THROW %s") % view.state.player_name(_local_holding()))
		return
	if local == null or not local.is_standing():
		hud.set_prompt("")
		return
	match _lobby_spot():
		&"wardrobe":
			hud.set_prompt(InputGlyphs.fill("[{interact}] Wardrobe: pick your skin"))
			return
		&"settings":
			hud.set_prompt(InputGlyphs.fill("[{interact}] Party settings" if view.state.leader == local_id else "[{interact}] Party settings (only the leader ★ can change them)"))
			return
	var floor_prompt: String = casino_floor.prompt() if casino_floor != null else ""
	if floor_prompt != "":
		hud.set_prompt(floor_prompt)
		return
	if _near_shop():
		hud.set_prompt(InputGlyphs.fill("[{interact}] Gift Shop: one item per round"))
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
		var target: int = _reach_target(true)
		hud.set_prompt(InputGlyphs.fill("[{interact} / {grab}] Grab %s   [{shove}] Shove") % view.state.player_name(target) if target >= 0 else "")


## True when the local player stands at the Gift Shop counter while the casino is open.
func _near_shop() -> bool:
	if local == null or view.state.shop_offers.is_empty():
		return false
	var ph: Phase.Id = view.state.phase
	if ph != Phase.Id.CASINO and ph != Phase.Id.PRE_MINIGAME:
		return false
	var p: Vector3 = local.global_position
	return Vector2(p.x - LuckyLounge.SHOP_POS.x, p.z - LuckyLounge.SHOP_POS.z).length() < 2.2 and absf(p.y - LuckyLounge.SHOP_POS.y) < 1.5


func _spin_door(delta: float) -> void:
	_door_angle += delta * 0.9
	var spinner: AnimatableBody3D = map.revolving_door.get_node_or_null("Spinner")
	if spinner != null:
		spinner.rotation.y = _door_angle
	var area: Area3D = map.revolving_door.get_node_or_null("DoorArea")
	if area == null:
		return
	for body: Node3D in area.get_overlapping_bodies():
		if body is PlayerAvatar and (body as PlayerAvatar).is_standing() and _simulates(body):
			var rel: Vector3 = body.global_position - map.revolving_door.global_position
			var tangent: Vector3 = Vector3(-rel.z, 0.0, rel.x).normalized()
			(body as PlayerAvatar).push_velocity += tangent * 4.0 * delta


func _check_fountain() -> void:
	for body: Node3D in map.fountain_area.get_overlapping_bodies():
		if body is PlayerAvatar:
			var a: PlayerAvatar = body
			if not a.is_soaked():
				Audio.play_at(&"splash", a, -6.0)
				FountainSplash.at_fountain(world_root, a.global_position, false)
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
		if body is PlayerAvatar and (body as PlayerAvatar).is_standing() and _simulates(body):
			var a: PlayerAvatar = body
			if view.state.balance(a.player_id) >= threshold or (view.state.effects.get(a.player_id, []) as Array).has(&"vip_pass"):
				continue
			# Bouncer pushes them back toward the stairs (+x) with a buzzer.
			a.knockback(Vector3(1.0, 0.0, 0.0), 7.0)
			a.stun(0.4)
			if a.player_id == local_id and _clock - _vip_toast_at > 1.0:
				_vip_toast_at = _clock
				Audio.play(&"buzzer", &"SFX", -4.0)
				hud.toast("VIP ACCESS — $%d+" % threshold, 1.5)


## Chip pickups. The host (Practice or the room server) decides who touched a pile and reports it;
## the money is the server's alone. Online, our own client predicts its pickups: the chips fly into
## us with the clink and "+$X" right away, and drop back if the server gives no confirmation.
func _check_pickups() -> void:
	if piles.is_empty():
		return
	if _owns_server:
		for pile_id: int in piles.keys():
			var pile: ChipPile = piles[pile_id]
			if not pile.is_collectable(_clock):
				continue
			var best: int = -1
			var best_d: float = INF
			for pid: int in avatars:
				var a: PlayerAvatar = avatars[pid]
				if not a.is_standing() or a.connection_away:
					continue
				var reach: float = PICKUP_RADIUS + (PICKUP_LAG_SLACK if a.drive == PlayerAvatar.Drive.PUPPET else 0.0)
				var d: float = _pickup_distance(a, pile)
				if d <= reach and d < best_d:
					best_d = d
					best = pid
			if best >= 0:
				server.report_pickup(best, pile_id)
		return
	if local == null or not local.is_standing():
		return
	for pile_id: int in piles.keys():
		var pile: ChipPile = piles[pile_id]
		if pile.predicted_until > -INF:
			if _clock > pile.predicted_until:
				pile.restore()  # the server never confirmed: someone else got there first, or lag
			continue
		if pile.is_collectable(_clock) and _pickup_distance(local, pile) <= PICKUP_RADIUS:
			pile.predicted_until = _clock + PICKUP_PREDICT_TIMEOUT
			pile.fly_to(local, true)
			_pickup_feedback(local, pile.amount)


## Floor-plane distance from a player's feet to a pile (INF on another floor).
static func _pickup_distance(a: PlayerAvatar, pile: ChipPile) -> float:
	var to: Vector3 = pile.global_position - a.global_position
	if absf(to.y) > 1.2:
		return INF
	return Vector2(to.x, to.z).length()


func _pickup_feedback(who: PlayerAvatar, amount: int) -> void:
	Audio.play_at(&"chip_clack", who, -4.0, randf_range(1.05, 1.2))
	Audio.play_at(&"coin", who, -10.0, randf_range(1.0, 1.15))
	WinFx.money_delta(world_root, who.global_position + Vector3(0.0, 2.0, 0.0), amount)


func _on_chips_collected(pile_id: int, player: int, amount: int) -> void:
	var pile: ChipPile = piles.get(pile_id, null)
	piles.erase(pile_id)
	var who: PlayerAvatar = avatars.get(player, null)
	var predicted: bool = pile != null and pile.predicted_until > -INF
	if pile != null:
		if predicted and player == local_id:
			# Confirmed: the chips are already in our pocket (or finishing the flight).
			pile.predicted_until = INF
			get_tree().create_timer(ChipPile.FLY_SECONDS + 0.05).timeout.connect(pile.queue_free)
		else:
			if predicted:
				pile.restore()  # we guessed wrong: the chips go to whoever really got them
			pile.fly_to(who)
	if who != null and not (predicted and player == local_id):
		_pickup_feedback(who, amount)


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
	if _down_until.has(pid):
		return  # knocked down: up when the knockdown ends (_process)
	if _respawn_at.has(pid):
		a.set_away(true)
		return
	if _ko_until.has(pid):
		return  # still out cold; _process gets them up on the server's clock
	if not _owns_server:
		return  # online clients wait for the server's player_got_up
	a.end_ragdoll()
	_got_up(pid)


# --- Stations ----------------------------------------------------------------------------------

func _add_table_fx() -> void:
	var juice := ScreenJuice.new()
	juice.name = "ScreenJuice"
	juice.camera_viewport = pixel_view.world_viewport()  # the shake needs the camera that draws the world
	add_child(juice)
	table_fx = TableFx.new()
	table_fx.name = "TableFx"
	add_child(table_fx)
	table_fx.setup(map.stations, func(pid: int) -> PlayerAvatar: return avatars.get(pid, null), local_id, juice, world_root)
	var lc := LastCallLighting.new()
	lc.name = "LastCallLighting"
	lc.setup(view.state, map, map.stations)
	add_child(lc)


func _on_station_state(sid: StringName) -> void:
	var st: Dictionary = view.state.stations.get(sid, {})
	var node: StationBase = map.stations.get(sid, null)
	if node != null:
		node.set_hot(bool(st.get("hot", false)))
		node.set_out_of_order(float(st.get("out_of_order", 0.0)))
		if node is BlackjackStation:
			(node as BlackjackStation).show_round(st)
	if current_ui != null and current_ui.station_id == sid:
		current_ui.update_state(st, Net.request_private_snapshot().get("station", {}))


func _drop_plinko_chip(sid: StringName, pid: int, slot: int, drop_id: int, seconds: float, risk: StringName) -> void:
	var st: PlinkoStation = map.stations.get(sid, null) as PlinkoStation
	var key: String = "%s:%d" % [sid, drop_id]
	if st == null or _plinko_seen.has(key):
		return
	if _plinko_seen.size() > 256:
		_plinko_seen.erase(_plinko_seen.keys()[0])  # oldest first; long since landed
	_plinko_seen[key] = true
	st.drop_chip(slot, drop_id, avatars[pid].color if avatars.has(pid) else Palette.CASINO_RED, seconds, risk)


func _spawn_pile(id: int, amount: int, pos: Vector3, source: int = -1) -> void:
	if piles.has(id):
		return
	var p := ChipPile.new()
	p.pile_id = id
	p.amount = amount
	p.position = _floor_under(pos)
	world_root.add_child(p)
	piles[id] = p
	var from: PlayerAvatar = avatars.get(source, null)
	if from != null:
		# Shaken out of someone: the chips arc out of them and can't be grabbed mid-air.
		p.settles_at = _clock + ChipPile.SETTLE_SECONDS
		var origin: Vector3 = from.ragdoll.body_position() if from.ragdoll != null and is_instance_valid(from.ragdoll) else from.global_position + Vector3(0.0, 0.9, 0.0)
		p.arc_from(origin)
	Audio.play_at(&"chip_clack", p, -8.0)


func _remove_pile(id: int) -> void:
	if piles.has(id):
		piles[id].queue_free()
		piles.erase(id)


## Late joiners and resyncs: piles from the snapshot that we never saw dropped, and piles we still
## show that the server no longer has.
func _sync_piles() -> void:
	for id: int in view.state.piles:
		if not piles.has(id):
			var row: Dictionary = view.state.piles[id]
			_spawn_pile(id, int(row["amount"]), Serializer.to_vec3(row["pos"]))
	for id: int in piles.keys():
		if not view.state.piles.has(id) and not piles[id].is_leaving():
			_remove_pile(id)


## Server query: a wall, table or the fountain between two points at hip height (wall slams).
func _obstacle_between(from: Vector3, to: Vector3) -> bool:
	if not is_inside_tree():
		return false
	var q := PhysicsRayQueryParameters3D.create(from + Vector3(0.0, 0.6, 0.0), to + Vector3(0.0, 0.6, 0.0), 1)
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Where something dropped at `pos` comes to rest: the floor (or table top) below it.
func _floor_under(pos: Vector3) -> Vector3:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state if is_inside_tree() else null
	if space != null:
		var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0.0, 0.6, 0.0), pos + Vector3(0.0, -4.0, 0.0), 1)
		var hit: Dictionary = space.intersect_ray(q)
		if not hit.is_empty():
			return hit["position"]
	return Vector3(pos.x, maxf(pos.y, 0.0), pos.z)


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


## Who a shove (or grab) would hit right now: the same reach cone the server uses
## (`InteractionRules.reach_score`), over players we can see standing (not seated, away or out).
func _reach_target(for_grab: bool) -> int:
	if local == null:
		return -1
	var candidates: Dictionary = {}
	for pid: int in avatars:
		if pid == local_id:
			continue
		var a: PlayerAvatar = avatars[pid]
		if a.connection_away or not (a.is_standing() or (a.state == PlayerAvatar.State.HELD and not for_grab)):
			continue
		candidates[pid] = a.global_position
	return InteractionRules.pick_in_reach(local.global_position, local.facing(), candidates, local_id)


func _seat_index(sid: StringName, pid: int) -> int:
	var seat: int = int(view.state.players.get(pid, {}).get("seat", -1))
	if seat >= 0:
		return seat
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
