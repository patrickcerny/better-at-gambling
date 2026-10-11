extends Node
## Dev: the Find the Lady stage with made-up players (screenshots), driven by the real logic.
## `-s tools/screenshot.gd -- --scene res://tools/dev/find_the_lady_shot.tscn --frames 60 --moment pick`
## Moments: show (the Queen glows), shuffle (mid-swap, `--t` seconds in), choose (the pick window,
## nothing picked yet), pick (you picked),
## reveal (chips on the cards), over (final scores). `--round N` (0..4, round 4 has four cards),
## `--players N` (2..8, default 6).

const NAMES: Array[String] = ["Patrick", "Chip", "Lena-Marie", "Dice", "Big Wendy", "Snake Eyes", "Ace", "Penny"]

var logic: FindTheLadyLogic
var stage: FindTheLadyStage
var moment: String = "pick"
var freeze_t: float = -1.0


func _ready() -> void:
	var c: Cmdline = Cmdline.parse(OS.get_cmdline_user_args())
	moment = c.get_string("moment", "pick")
	var target_round: int = clampi(c.get_int("round", 0), 0, FindTheLadyLogic.ROUNDS - 1)
	var n: int = clampi(c.get_int("players", 6), 2, 8)
	_environment()
	var st := ClientMatchState.new()
	var ids: Array[int] = []
	for i: int in n:
		st.players[i + 1] = {"id": i + 1, "name": NAMES[i], "color": i}
		ids.append(i + 1)
	logic = FindTheLadyLogic.new()
	logic.setup(ids, SeededRng.new(7), BalanceConfig.new(), {}, {})
	logic.drain_events()
	stage = FindTheLadyStage.new()
	stage.send_intent = func(i: Dictionary) -> Dictionary: return logic.submit(1, i, 1.0)
	add_child(stage)
	stage.begin(st, 1, {"minigame": &"find_the_lady", "players": ids}, {})
	logic.tick(FindTheLadyLogic.INTRO_TIME + 0.01, 0.0)
	_pump()
	# Earlier rounds: everyone picks something, some find her.
	while logic.round_index < target_round:
		_play_round(false)
		logic.tick(FindTheLadyLogic.REVEAL_TIME + 0.01, 0.0)
		_pump()
	stage._kill_deal()
	stage._deal_round(logic.card_count, logic.lady_start, false)
	if moment == "show":
		return
	logic.tick(FindTheLadyLogic.SHOW_TIME + 0.01, 0.0)
	_pump()
	if moment == "shuffle":
		freeze_t = c.get_float("t", logic.FLIP_TIME + FindTheLadyLogic.swap_time(target_round) * 2.5)
		return
	logic.tick(logic.timer + 0.01, 0.0)
	_pump()
	if moment == "choose":
		return
	stage.pick(logic.lady_slot if target_round % 2 == 0 else (logic.lady_slot + 1) % logic.card_count)
	for p: int in [3, 5]:
		if p <= n:
			logic.submit(p, {"slot": (logic.lady_slot + p) % logic.card_count}, 2.0)
	_pump()
	stage.time_left = 3.4
	if moment == "pick":
		return
	_play_round(true)
	if moment == "reveal":
		return
	while not logic.is_finished() and logic.phase != FindTheLadyLogic.Step.OUTRO:
		logic.tick(FindTheLadyLogic.REVEAL_TIME + 0.01, 0.0)
		if logic.phase == FindTheLadyLogic.Step.OUTRO:
			break
		_play_round(false)
	_pump()


## Everyone still to pick picks (every third player finds her), the window closes.
func _play_round(skip_to_pick_done: bool) -> void:
	if logic.phase == FindTheLadyLogic.Step.SHOW:
		logic.tick(FindTheLadyLogic.SHOW_TIME + 0.01, 0.0)
	if logic.phase == FindTheLadyLogic.Step.SHUFFLE:
		logic.tick(logic.timer + 0.01, 0.0)
	for p: int in logic.players:
		if not logic.picks.has(p):
			var slot: int = logic.lady_slot if (p + logic.round_index) % 3 != 0 else (logic.lady_slot + 1) % logic.card_count
			logic.submit(p, {"slot": slot}, 1.0 + 0.4 * p)
	logic.tick(0.01, 5.0)
	_pump()
	if skip_to_pick_done:
		stage._end_shuffle()


func _pump() -> void:
	for ev: Dictionary in logic.drain_events():
		stage.on_event(ev)
	stage.on_private({"minigame": logic.private_state(1)})


func _process(_delta: float) -> void:
	if freeze_t >= 0.0:
		stage.shuffle_t = -1.0
		stage.shuffle_pose(freeze_t)
	if moment != "shuffle":
		stage.time_left = maxf(stage.time_left, 3.4)


func _environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Palette.CASINO_BLACK
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1.0, 0.85, 0.65)
	e.ambient_light_energy = 0.35
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.4
	e.glow_bloom = 0.1
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.9, 0.75)
	sun.light_energy = 0.25
	sun.rotation_degrees = Vector3(-55, 30, 0)
	add_child(sun)
