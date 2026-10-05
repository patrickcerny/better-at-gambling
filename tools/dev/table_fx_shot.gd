extends Node3D
## Dev: a roulette table, a blackjack table and a slot machine playing a scripted round through
## `TableFx` (chips slide on, the ball spins and drops, reels stop, win/lose effects), for
## screenshots. Run with tools/screenshot.gd --scene res://tools/dev/table_fx_shot.tscn
## [--view roulette|wheel|blackjack|slots|wide] [--hot] [--frames N]; pass --fixed-fps 60 to the engine so N frames = N/60 s.

var fx: TableFx
var stations: Dictionary = {}


func _ready() -> void:
	var args: Cmdline = Cmdline.parse(OS.get_cmdline_user_args())
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Palette.CASINO_BLACK
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(1.0, 0.85, 0.65)
	env.environment.ambient_light_energy = 0.5
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment.glow_enabled = true
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, 20, 0)
	sun.light_energy = 0.4
	add_child(sun)
	GreyboxKit.lamp(self, Vector3(0, 5, 0), 3.0, 16.0)
	var floor_mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	floor_mesh.mesh = pm
	floor_mesh.material_override = GreyboxKit.material(Palette.CASINO_RED.darkened(0.6))
	add_child(floor_mesh)
	_station(&"roulette_1", RouletteStation.new(), Vector3(0, 0, 0))
	_station(&"blackjack_1", BlackjackStation.new(), Vector3(-6, 0, 0))
	_station(&"slots_1", SlotsStation.new(), Vector3(5, 0, -1))
	_station(&"plinko_1", PlinkoStation.new(), Vector3(0, 0, -7))
	fx = TableFx.new()
	add_child(fx)
	var juice := ScreenJuice.new()
	add_child(juice)
	fx.setup(stations, func(_pid: int) -> PlayerAvatar: return null, 1, juice, self)
	var cam := Camera3D.new()
	add_child(cam)
	match args.get_string("view", "roulette"):
		"wheel":
			cam.position = Vector3(-1.3, 2.1, 0.75)
			cam.look_at(Vector3(-1.3, 0.95, 0.0))
		"pocket":
			cam.position = Vector3(-1.3, 1.75, 0.2)
			cam.look_at(Vector3(-1.3, 0.95, -0.02))
		"blackjack":
			cam.position = Vector3(-6, 2.6, 3.4)
			cam.look_at(Vector3(-6, 0.9, 0.0))
		"slots":
			cam.position = Vector3(5, 1.7, 1.3)
			cam.look_at(Vector3(5, 1.4, -1))
		"plinko":
			cam.position = Vector3(0, 2.6, -2.2)
			cam.look_at(Vector3(0, 2.4, -7))
		"wide":
			cam.position = Vector3(0, 6, 9)
			cam.look_at(Vector3(-0.5, 0.8, 0))
		_:
			cam.position = Vector3(0.7, 2.3, 2.2)
			cam.look_at(Vector3(0.5, 0.9, 0.0))
	cam.current = true
	if args.has_flag("hot"):
		(stations[&"roulette_1"] as StationBase).set_hot(true)
	_play()


func _station(sid: StringName, st: StationBase, pos: Vector3) -> void:
	st.station_id = sid
	st.position = pos
	add_child(st)
	stations[sid] = st


func _ev(type: StringName, data: Dictionary) -> void:
	var ev: Dictionary = data.duplicate()
	ev["type"] = type
	fx.on_event(ev)


func _play() -> void:
	var bets: Array = [[1, &"straight", 32, 50], [2, &"red", 0, 100], [3, &"dozen", 2, 25], [1, &"black", 0, 40], [4, &"straight", 17, 200]]
	for b: Array in bets:
		_ev(&"bet_placed", {"player": b[0], "station": &"roulette_1", "amount": b[3], "details": {"game": "roulette", "type": b[1], "value": b[2]}})
	_ev(&"bet_placed", {"player": 1, "station": &"blackjack_1", "amount": 100, "details": {"game": "blackjack"}})
	_ev(&"bet_placed", {"player": 1, "station": &"slots_1", "amount": 25, "details": {"game": "slots"}})
	await get_tree().create_timer(0.5).timeout
	_ev(&"roulette_spin_started", {"station": &"roulette_1"})
	await get_tree().create_timer(2.0).timeout
	_ev(&"roulette_result", {"station": &"roulette_1", "number": 32})
	for b: Array in bets:
		var won: bool = RouletteLogic.wins(b[1], b[2], 32)
		var ret: int = int(b[3]) * (36 if b[1] == &"straight" else (3 if b[1] == &"dozen" else 2)) if won else 0
		_ev(&"round_result", {"player": b[0], "station": &"roulette_1", "stake": b[3], "returned": ret, "net": ret - int(b[3]), "details": {"type": b[1], "value": b[2], "number": 32}})
	_ev(&"round_result", {"player": 1, "station": &"blackjack_1", "stake": 100, "returned": 200, "net": 100, "details": {}})
	_drop_plinko(9, 4)
	_ev(&"round_result", {"player": 1, "station": &"plinko_1", "stake": 20, "returned": 60, "net": 40, "details": {"drop_id": 9, "slot": 4}})
	_ev(&"round_result", {"player": 1, "station": &"slots_1", "stake": 25, "returned": 1000, "net": 975, "details": {"line": [4, 4, 4]}})


## Same playback as `MatchScene._drop_plinko_chip`.
func _drop_plinko(drop_id: int, slot: int) -> void:
	var st: PlinkoStation = stations[&"plinko_1"]
	var rng := SeededRng.new(drop_id * 7919 + slot)
	var path: Array[float] = PlinkoSteering.path_to_slot(PlinkoStation.ROWS, PlinkoStation.SLOTS, slot, rng)
	var row_h: float = (PlinkoStation.BOARD_H - 1.2) / PlinkoStation.ROWS
	var pts: Array[Vector3] = PlinkoSteering.path_points(path, st.slot_xs, st.drop_y, row_h, 0.65)
	var chip := PlinkoChip.new()
	st.add_child(chip)
	chip.play(pts, 1.6, slot)
