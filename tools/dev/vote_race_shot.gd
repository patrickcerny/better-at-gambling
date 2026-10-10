extends Node
## Dev: the Vote Race stage with made-up players (screenshots), driven by the real logic.
## `scripts/screenshot.sh res://tools/dev/vote_race_shot.tscn vote 60 -- --phase vote`
## Phases: vote (mid-vote, you voted), flying (chips in the air), reveal (the chips landed, the
## zero-vote cards stepped), result (race over). `--players N` (4..8, default 6).

const NAMES: Array[String] = ["Patrick", "Chip", "Lucky", "Dice", "Big Wendy", "Snake Eyes", "Ace", "Penny"]

var logic: VoteRaceLogic
var stage: VoteRaceStage


func _ready() -> void:
	var c: Cmdline = Cmdline.parse(OS.get_cmdline_user_args())
	var phase: String = c.get_string("phase", "vote")
	var n: int = clampi(c.get_int("players", 6), 4, 8)
	var st := ClientMatchState.new()
	var ids: Array[int] = []
	for i: int in n:
		st.players[i + 1] = {"id": i + 1, "name": NAMES[i], "color": i}
		ids.append(i + 1)
	logic = VoteRaceLogic.new()
	logic.setup(ids, SeededRng.new(1), BalanceConfig.new(), {}, {})
	logic.drain_events()
	stage = VoteRaceStage.new()
	stage.send_intent = func(i: Dictionary) -> Dictionary: return logic.submit(1, i, 0.0)
	add_child(stage)
	stage.begin(st, 1, {"minigame": &"vote_race", "players": ids}, {})
	# Two earlier rounds so the track has some spread.
	_round({1: 2, 2: 3, 3: 2, 4: 2, 5: 3, 6: 2, 7: 2, 8: 2})
	_round({1: 3, 2: 3, 3: 4, 4: 3, 5: 4, 6: 3, 7: 3, 8: 3})
	_pump()
	stage.skip_reveal()
	if phase == "result":
		while not logic.is_finished():
			logic.tick(VoteRaceLogic.VOTE_TIME + 0.01, 0.0)
			logic.tick(VoteRaceLogic.REVEAL_TIME + 0.01, 0.0)
		_pump()
		return
	stage._process(2.6)
	stage.on_private({"minigame": logic.private_state(1)})
	stage._on_vote_pressed(3)
	for v: int in [4, 6]:
		if v <= n:
			logic.submit(v, {"target": 1}, 0.0)
	_pump()
	if phase == "vote":
		return
	for v: int in ids:
		if not logic.votes.has(v):
			logic.submit(v, {"target": 3 if v != 3 else 2}, 0.0)
	_pump()
	if phase == "reveal":
		stage.skip_reveal()


func _round(ballot: Dictionary) -> void:
	for v: int in ballot:
		if logic.racing.has(v) and logic.racing.has(int(ballot[v])):
			logic.submit(v, {"target": ballot[v]}, 0.0)
	if logic.phase == VoteRaceLogic.RaceState.VOTING:
		logic.tick(VoteRaceLogic.VOTE_TIME + 0.01, 0.0)
	logic.tick(VoteRaceLogic.REVEAL_TIME + 0.01, 0.0)


func _pump() -> void:
	for ev: Dictionary in logic.drain_events():
		stage.on_event(ev)
	stage.on_private({"minigame": logic.private_state(1)})
