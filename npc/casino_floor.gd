class_name CasinoFloor
extends Node3D
## The match scene's side of the waiter NPC, dealers at tables, and the Megaphone prop (M7, v0.8.4).
## Spawns the waiter on his route once the navmesh is ready, spawns dealers at blackjack and
## roulette tables, keeps the server's `WaiterLogic` and `DealerLogic` told where their bodies are
## (on the process that simulates the world), shows puddles and the megaphone from the replicated
## state, and plays their sounds. All decisions come from the server.

## Service loop: from the bar's service end out across the floor and back (navmesh points).
const WAITER_ROUTE: Array[Vector3] = [
	Vector3(14.0, 0, 1.6), Vector3(2.5, 0, 2.2), Vector3(-5.0, 0, 0.6), Vector3(-12.5, 0, -4.6),
	Vector3(-1.0, 0, -10.5), Vector3(9.0, 0, -9.0), Vector3(12.5, 0, -2.0),
]
const PUDDLE_COLOR: Color = Color("#7A3B22")

var scene: MatchScene
var waiter: Waiter = null
## Dealers at each blackjack and roulette table (v0.8.4): station_id → Dealer node.
var dealers: Dictionary[StringName, Dealer] = {}
var puddle_nodes: Dictionary[int, Node3D] = {}
var stand: Node3D = null
## The megaphone model (on the stand, or in the holder's hand).
var megaphone_model: Node3D = null
var _headless: bool = false
var _holder: int = -1
var _pulse: float = 1.0


func setup(p_scene: MatchScene) -> void:
	scene = p_scene
	_headless = DisplayServer.get_name() == "headless"
	if not _headless:
		_build_stand()
	scene.view.state.floor_changed.connect(_sync)
	_sync()
	_spawn_waiter()
	_spawn_dealers()


func _exit_tree() -> void:
	if scene != null and scene.view != null and scene.view.state.floor_changed.is_connected(_sync):
		scene.view.state.floor_changed.disconnect(_sync)


func _spawn_waiter() -> void:
	while is_inside_tree() and not scene.map.navmesh_ready:
		await get_tree().physics_frame
	if not is_inside_tree():
		return
	waiter = Waiter.new()
	waiter.name = "Waiter"
	var route: Array[Vector3] = []
	route.assign(WAITER_ROUTE)
	waiter.route = route
	waiter.puppet = scene.role == MatchScene.Role.CLIENT
	scene.world_root.add_child(waiter)


## Spawn dealers at each blackjack and roulette table (v0.8.4).
func _spawn_dealers() -> void:
	if scene.server == null or _headless:
		return
	dealers.clear()
	# Get dealer positions from stations
	for sid: StringName in scene.server.stations.logics:
		var logic: StationLogicBase = scene.server.stations.logics[sid]
		if logic.game_id != &"blackjack" and logic.game_id != &"roulette":
			continue
		var station: StationBase = scene.map.stations.get(sid, null) as StationBase
		if station == null:
			continue
		var dealer_pos: Vector3 = DealerLogic.OFFSETS[logic.game_id]
		var dealer := Dealer.new()
		dealer.name = "Dealer_%s" % sid
		dealer.station_id = sid
		dealer.position_offset = station.global_position + dealer_pos
		dealer.puppet = scene.role == MatchScene.Role.CLIENT
		scene.world_root.add_child(dealer)
		dealers[sid] = dealer


func _physics_process(_delta: float) -> void:
	if waiter == null or scene == null or scene.server == null or scene.role == MatchScene.Role.CLIENT:
		return
	var logic: WaiterLogic = scene.server.waiter
	logic.position = waiter.global_position
	logic.yaw = waiter.yaw
	if logic.is_down(scene.server.match_time):
		waiter.trip()
	else:
		waiter.get_up()
	# Update dealer positions (v0.8.4)
	for sid: StringName in dealers:
		var dealer: Dealer = dealers[sid]
		if dealer != null and scene.server.dealers.has(sid):
			var dealer_logic: DealerLogic = scene.server.dealers[sid]
			dealer_logic.position = dealer.global_position
			dealer_logic.yaw = dealer.yaw


## In a holder's hand: held up to their mouth, pulsing while they talk.
const HELD_POS: Vector3 = Vector3(0.12, 0.88, -0.55)
const HELD_TILT: float = 0.15


func _process(delta: float) -> void:
	if megaphone_model == null or _holder < 0:
		return
	var h: PlayerAvatar = scene.avatars.get(_holder, null)
	if h == null or not is_instance_valid(h) or h.visuals == null:
		return
	var talking: bool = scene.voice != null and scene.voice.is_talking(_holder)
	_pulse = lerpf(_pulse, 1.25 if talking else 1.0, minf(1.0, 12.0 * delta))
	megaphone_model.global_transform = h.visuals.global_transform * Transform3D(Basis.from_euler(Vector3(HELD_TILT, 0.0, 0.0)), HELD_POS)
	megaphone_model.scale = Vector3.ONE * _pulse


## True (and the intent sent) when E should pick up the megaphone.
func interact() -> bool:
	if prompt() == "":
		return false
	var res: Dictionary = Net.send_intent(Intents.make(&"megaphone"))
	if not res["ok"] and res["error"] != &"rate_limited":
		scene.hud.toast("The megaphone needs a moment" if res["error"] == &"megaphone_cooldown" else "Can't grab the megaphone right now", 1.5)
	return true


## Interaction prompt near the stand ("" when out of reach or taken).
func prompt() -> String:
	var local: PlayerAvatar = scene.local
	var ph: Phase.Id = scene.view.state.phase
	if local == null or scene.view.state.megaphone_holder >= 0 or (ph != Phase.Id.CASINO and ph != Phase.Id.PRE_MINIGAME):
		return ""
	var d: Vector3 = local.global_position - MegaphoneLogic.STAND_POS
	if Vector2(d.x, d.z).length() > MegaphoneLogic.RANGE - 0.2 or absf(d.y) > 1.5:
		return ""
	return "[E] Megaphone: everyone hears you for %ds" % int(MegaphoneLogic.SECONDS)


## Server events for the waiter, puddles and megaphone (called from MatchScene._on_event).
func on_event(ev: Dictionary) -> void:
	match StringName(ev["type"]):
		&"waiter_tripped":
			if waiter != null:
				waiter.trip()
				Audio.play_at(&"tray_crash", waiter, -3.0)
				_pop_label(waiter, "WHOA!" if int(ev["player"]) < 0 else "HEY!")
			var by: PlayerAvatar = scene.avatars.get(int(ev["player"]), null)
			if by != null:
				by.say("oops", 1.2)
		&"puddle_slip":
			var a: PlayerAvatar = scene.avatars.get(int(ev["player"]), null)
			if a != null:
				Audio.play_at(&"slip", a, -6.0, randf_range(0.95, 1.1))
				Audio.play_at(&"splash", a, -14.0, 1.3)
				if a.is_standing() or a.state == PlayerAvatar.State.HELD:
					a.knockback(a.facing(), 2.5)
			if int(ev["player"]) == scene.local_id:
				scene.hud.banner("SLIPPED in a puddle!", Palette.CREAM, 1.5)
		&"megaphone_taken":
			var h: PlayerAvatar = scene.avatars.get(int(ev["player"]), null)
			if h != null:
				Audio.play_at(&"megaphone", h, -4.0)
				h.say("*tap tap*", 1.2)
			if int(ev["player"]) == scene.local_id:
				scene.hud.banner("MEGAPHONE! Everyone hears you for %ds" % int(float(ev["seconds"])), Palette.VIP_GOLD, 2.5)
		&"megaphone_dropped":
			if int(ev["player"]) == scene.local_id:
				scene.hud.toast("Megaphone back on its stand", 1.5)
		&"dealer_attacked":
			# Dealer was attacked; player goes to jail (v0.8.4)
			var sid: StringName = StringName(ev.get("station", ""))
			var by: PlayerAvatar = scene.avatars.get(int(ev["player"]), null)
			if by != null:
				by.say("NO!", 1.2)
			var dealer: Dealer = dealers.get(sid, null)
			if dealer != null and dealer.visuals != null:
				Audio.play_at(&"tray_crash", dealer, -5.0)  # Reuse tray crash sound
				dealer.visuals.react(&"ko")  # Dealer reacts in shock


## Puddles and the megaphone follow the replicated state.
func _sync() -> void:
	var st: ClientMatchState = scene.view.state
	for id: int in puddle_nodes.keys():
		if not st.puddles.has(id):
			_dry_up(puddle_nodes[id])
			puddle_nodes.erase(id)
	if not _headless:
		for id: int in st.puddles:
			if not puddle_nodes.has(id):
				var n: Node3D = make_puddle(id)
				add_child(n)
				n.global_position = Serializer.to_vec3(st.puddles[id]["pos"]) + Vector3(0, 0.015, 0)
				puddle_nodes[id] = n
	if st.megaphone_holder != _holder:
		_holder = st.megaphone_holder
		_place_megaphone()


## On the stand when nobody holds it; otherwise `_process` keeps it in the holder's hand.
func _place_megaphone() -> void:
	if megaphone_model == null:
		return
	_pulse = 1.0
	megaphone_model.scale = Vector3.ONE
	if _holder < 0:
		megaphone_model.top_level = false
		megaphone_model.position = Vector3(0, 1.3, 0)
		megaphone_model.rotation = Vector3(0.0, PI * 0.5, 0.0)
		megaphone_model.scale = Vector3.ONE * 1.4
	else:
		megaphone_model.top_level = true


static func make_puddle(id: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Puddle%d" % id
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(PUDDLE_COLOR, 0.82)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.05
	mat.metallic_specular = 1.0
	var rng := RandomNumberGenerator.new()
	rng.seed = id * 7919
	# A few overlapping flat blobs read as a spill, not a disc.
	for i: int in 4:
		var blob := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		var r: float = rng.randf_range(0.35, 0.6) if i > 0 else WaiterLogic.PUDDLE_RADIUS * 0.7
		cm.top_radius = r
		cm.bottom_radius = r
		cm.height = 0.01
		cm.radial_segments = 18
		cm.rings = 1
		blob.mesh = cm
		blob.material_override = mat
		blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if i > 0:
			var a: float = rng.randf() * TAU
			blob.position = Vector3(cos(a), 0.002 * i, sin(a)) * Vector3(0.55, 1.0, 0.55)
		blob.scale = Vector3(1.0, 1.0, rng.randf_range(0.7, 1.0))
		root.add_child(blob)
	# Broken glass glinting in it.
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.9, 0.95, 1.0, 0.6)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.0
	glass.metallic_specular = 1.0
	for i: int in 5:
		var shard := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(0.08, 0.05, 0.02)
		shard.mesh = pm
		shard.material_override = glass
		var a: float = rng.randf() * TAU
		var d: float = rng.randf_range(0.1, 0.7)
		shard.position = Vector3(cos(a) * d, 0.02, sin(a) * d)
		shard.rotation = Vector3(PI * 0.5, rng.randf() * TAU, 0.0)
		root.add_child(shard)
	# A little "wet floor" sign.
	var tag := Label3D.new()
	tag.text = "WET FLOOR"
	tag.font_size = 40
	tag.pixel_size = 0.004
	tag.outline_size = 10
	tag.modulate = Palette.VIP_GOLD
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position = Vector3(0, 0.55, 0)
	root.add_child(tag)
	root.scale = Vector3(0.2, 1.0, 0.2)
	root.create_tween().tween_property(root, ^"scale", Vector3.ONE, 0.35).set_ease(Tween.EASE_OUT)
	return root


func _dry_up(n: Node3D) -> void:
	if not is_instance_valid(n):
		return
	var t: Tween = n.create_tween()
	t.tween_property(n, ^"scale", Vector3(0.05, 1.0, 0.05), 0.6).set_ease(Tween.EASE_IN)
	t.tween_callback(n.queue_free)


func _pop_label(at: Node3D, text: String) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 64
	l.pixel_size = 0.005
	l.outline_size = 12
	l.modulate = Palette.CREAM
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = Vector3(0, 2.2, 0)
	at.add_child(l)
	var t: Tween = l.create_tween()
	t.tween_property(l, ^"position:y", 2.7, 1.2)
	t.parallel().tween_property(l, ^"modulate:a", 0.0, 1.2).set_delay(0.5)
	t.tween_callback(l.queue_free)


## Megaphone on a brass stand in front of the bar.
func _build_stand() -> void:
	stand = Node3D.new()
	stand.name = "MegaphoneStand"
	add_child(stand)
	stand.global_position = MegaphoneLogic.STAND_POS
	GreyboxKit.cylinder(stand, 0.25, 0.05, Vector3(0, 0.025, 0), Palette.WARM_GOLD, "Base", false, 0.8)
	GreyboxKit.cylinder(stand, 0.035, 1.1, Vector3(0, 0.6, 0), Palette.WARM_GOLD, "Pole", false, 0.8)
	GreyboxKit.cylinder(stand, 0.12, 0.04, Vector3(0, 1.16, 0), Palette.WARM_GOLD, "Cradle", false, 0.8)
	megaphone_model = make_megaphone()
	stand.add_child(megaphone_model)
	var tag := Label3D.new()
	tag.text = "MEGAPHONE"
	tag.font_size = 44
	tag.pixel_size = 0.004
	tag.outline_size = 10
	tag.modulate = Palette.VIP_GOLD
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position = Vector3(0, 1.75, 0)
	stand.add_child(tag)
	_place_megaphone()


## A cream-and-red bullhorn pointing along −z.
static func make_megaphone() -> Node3D:
	var root := Node3D.new()
	root.name = "Megaphone"
	var cone := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 0.17
	cm.height = 0.38
	cm.radial_segments = 16
	cone.mesh = cm
	cone.material_override = GreyboxKit.material(Palette.CREAM, 0.0, 0.5)
	cone.rotation.x = -PI * 0.5
	cone.position = Vector3(0, 0, -0.12)
	root.add_child(cone)
	var rim := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.15
	tm.outer_radius = 0.19
	tm.rings = 16
	tm.ring_segments = 6
	rim.mesh = tm
	rim.material_override = GreyboxKit.material(Palette.CASINO_RED, 0.0, 0.5)
	rim.rotation.x = PI * 0.5
	rim.position = Vector3(0, 0, -0.31)
	root.add_child(rim)
	var grip := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.05, 0.14, 0.06)
	grip.mesh = bm
	grip.material_override = GreyboxKit.material(Palette.CASINO_BLACK)
	grip.position = Vector3(0, -0.1, 0.0)
	root.add_child(grip)
	return root
