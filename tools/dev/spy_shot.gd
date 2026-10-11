extends Node
## Dev: the Spy stage with made-up players (screenshots), driven by the real logic.
## `scripts/screenshot.sh res://tools/dev/spy_shot.tscn spy 60 --phase vote`
## Phases: clue (your clue turn in round 2, a civilian), spy (the same as a spy, hint arrived),
## vote (a vote running, you voted), flying (the chips in the air), reveal (the verdict), over (the
## end screen). `--players N` (4..8, default 6).

const NAMES: Array[String] = ["Patrick", "Chip", "Lucky", "Dice", "Big Wendy", "Snake Eyes", "Ace", "Penny"]
const CLUES: Array[String] = ["steel", "combination", "heist", "deep", "locked", "gold bars", "safe", "guarded", "door", "keys", "alarm", "bank"]

var logic: SpyLogic
var stage: SpyStage
var me: int = 1


func _ready() -> void:
	var c: Cmdline = Cmdline.parse(OS.get_cmdline_user_args())
	var phase: String = c.get_string("phase", "clue")
	var n: int = clampi(c.get_int("players", 6), 4, 8)
	var st := ClientMatchState.new()
	var ids: Array[int] = []
	for i: int in n:
		st.players[i + 1] = {"id": i + 1, "name": NAMES[i], "color": i}
		ids.append(i + 1)
	logic = SpyLogic.new()
	logic.setup(ids, SeededRng.new(4), BalanceConfig.new(), {}, {})
	me = logic.spies[0] if phase == "spy" else _civilian(0)
	logic.drain_events()
	stage = SpyStage.new()
	stage.send_intent = func(i: Dictionary) -> Dictionary: return logic.submit(me, i, 0.0)
	add_child(stage)
	stage.begin(st, me, {"minigame": &"spy", "players": ids}, {})
	logic.tick(SpyLogic.INTRO_TIME + 0.01, 0.0)
	# One full round of clues, then round 2 up to the local player.
	var k: int = 0
	for i: int in n:
		logic.submit(logic.speaker, {"type": &"spy_clue", "text": CLUES[k % CLUES.size()]}, 0.0)
		k += 1
	while logic.speaker != me:
		logic.submit(logic.speaker, {"type": &"spy_clue", "text": CLUES[k % CLUES.size()]}, 0.0)
		k += 1
	logic.tick(5.0, 0.0)
	if phase == "spy":
		logic.clock_left = logic.clock_total - SpyLogic.HINT_AFTER + 0.5
		logic.tick(1.0, 0.0)
	_pump()
	stage._process(0.0)
	if phase in ["clue", "spy"]:
		stage.entry.text = "shiny" if phase == "clue" else "cards"
		return
	logic.submit(me, {"type": &"spy_clue", "text": "shiny"}, 0.0)
	var suspect: int = logic.spies[0]
	logic.submit(_civilian(1), {"type": &"spy_call_vote"}, 0.0)
	_pump()
	stage._on_card_pressed(suspect)
	var others: Array[int] = logic.alive()
	for i: int in others.size():
		var p: int = others[i]
		if p == me or (phase == "vote" and i % 2 == 0):
			continue
		var t: int = suspect if p != suspect else me
		logic.submit(p, {"type": &"spy_vote", "target": t}, 0.0)
	logic.tick(0.1, 0.0)
	_pump()
	stage._process(4.0)
	if phase == "vote":
		return
	if logic.phase == SpyLogic.Step.VOTE:
		logic.tick(SpyLogic.VOTE_TIME, 0.0)
		_pump()
	if phase == "flying":
		return
	stage.skip_reveal()
	if phase == "reveal":
		return
	if logic.winner == "":
		logic.clock_left = 0.0
	logic.tick(SpyLogic.REVEAL_TIME + 0.01, 0.0)
	_pump()


func _civilian(skip: int) -> int:
	var left: int = skip
	for p: int in logic.seats:
		if not logic.is_spy(p):
			if left == 0:
				return p
			left -= 1
	return 1


func _pump() -> void:
	for ev: Dictionary in logic.drain_events():
		stage.on_event(ev)
	stage.on_private({"minigame": logic.private_state(me)})
