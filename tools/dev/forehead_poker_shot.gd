extends Node
## Dev: the Forehead Poker stage with made-up players (screenshots), driven by the real logic.
## `-s tools/screenshot.gd -- --scene res://tools/dev/forehead_poker_shot.tscn --frames 60 --moment talk`
## Moments: deal (Lucky dealing, `--t` seconds in), talk, decide (some decided, you not yet),
## showdown (`--t` seconds in, default all landed), over (final scores). `--round N` (0..4),
## `--players N` (2..8, default 6), `--yaw R` turns your head (radians, + = left),
## `--look P` turns it towards player P.

const NAMES: Array[String] = ["Patrick", "Chip", "Lena-Marie", "Dice", "Big Wendy", "Snake Eyes", "Ace", "Penny"]

var logic: ForeheadPokerLogic
var stage: ForeheadPokerStage
var moment: String = "talk"
var freeze_t: float = -1.0
var yaw: float = 0.0


func _ready() -> void:
	var c: Cmdline = Cmdline.parse(OS.get_cmdline_user_args())
	moment = c.get_string("moment", "talk")
	var target_round: int = clampi(c.get_int("round", 0), 0, ForeheadPokerLogic.ROUNDS - 1)
	var n: int = clampi(c.get_int("players", 6), 2, 8)
	_environment()
	var st := ClientMatchState.new()
	var ids: Array[int] = []
	for i: int in n:
		st.players[i + 1] = {"id": i + 1, "name": NAMES[i], "color": i}
		ids.append(i + 1)
	logic = ForeheadPokerLogic.new()
	logic.setup(ids, SeededRng.new(7), BalanceConfig.new(), {}, {})
	logic.drain_events()
	stage = ForeheadPokerStage.new()
	stage.send_intent = func(i: Dictionary) -> Dictionary: return logic.submit(1, i, 1.0)
	add_child(stage)
	stage.begin(st, 1, {"minigame": &"forehead_poker", "players": ids}, {})
	logic.tick(ForeheadPokerLogic.INTRO_TIME + 0.01, 0.0)
	_pump()
	while logic.round_index < target_round:
		_play_round()
		logic.tick(ForeheadPokerLogic.SHOWDOWN_TIME + 0.01, 0.0)
		_pump()
	yaw = c.get_float("yaw", 0.0)
	if c.get_int("look", 0) > 0:
		yaw = stage.yaw_towards(c.get_int("look", 0))
	if moment == "deal":
		freeze_t = c.get_float("t", 0.9)
		return
	logic.tick(ForeheadPokerLogic.DEAL_TIME + 0.01, 0.0)
	_pump()
	if moment == "talk":
		return
	logic.tick(ForeheadPokerLogic.TALK_TIME + 0.01, 0.0)
	_pump()
	for p: int in [2, 4, 5]:
		if p <= n:
			logic.submit(p, {"action": "stay" if p != 4 else "fold"}, 1.0)
	_pump()
	if moment == "decide":
		return
	_play_round()
	if moment == "showdown":
		freeze_t = c.get_float("t", 99.0)
		return
	while logic.phase != ForeheadPokerLogic.Step.OUTRO:
		logic.tick(ForeheadPokerLogic.SHOWDOWN_TIME + 0.01, 0.0)
		if logic.phase == ForeheadPokerLogic.Step.OUTRO:
			break
		_play_round()
	_pump()


## Everyone still to answer answers (some stay, some fold), then the showdown.
func _play_round() -> void:
	if logic.phase == ForeheadPokerLogic.Step.DEAL:
		logic.tick(ForeheadPokerLogic.DEAL_TIME + 0.01, 0.0)
	if logic.phase == ForeheadPokerLogic.Step.TALK:
		logic.tick(ForeheadPokerLogic.TALK_TIME + 0.01, 0.0)
	for p: int in logic.players:
		if not logic.choices.has(p):
			logic.submit(p, {"action": "stay" if (p + logic.round_index) % 3 != 0 else "fold"}, 1.0)
	logic.tick(0.01, 5.0)
	_pump()


func _pump() -> void:
	for ev: Dictionary in logic.drain_events():
		stage.on_event(ev)
	stage.on_private({"minigame": logic.private_state(1)})


func _process(_delta: float) -> void:
	if moment == "deal":
		stage.deal_t = -1.0
		stage.deal_pose(freeze_t)
	elif moment == "showdown":
		stage.show_t = -1.0
		stage.showdown_pose(minf(freeze_t, stage.showdown_length()))
		stage._clock = stage.showdown_length() + 0.9
	if moment != "showdown" and moment != "over":
		stage.time_left = maxf(stage.time_left, 9.4 if moment == "talk" else 4.4)
	stage.sit_back = 1.0 if moment == "showdown" or moment == "over" else 0.0
	stage.yaw = yaw
	stage.pitch = 0.0
	stage._apply_view()


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
