extends Node
## Dev: a 2D minigame stage (quiz, lonely_number, bust_or_bank) driven by its real logic a few
## seconds in, for the minigame selector's pictures (tools/minigame_pictures.sh).
## `xvfb-run -a tools/godot/godot --path . -s tools/screenshot.gd -- --scene
## res://tools/dev/minigame_stage_shot.tscn --out /tmp/q.png --frames 30 --game quiz`.

const NAMES: Array[String] = ["Patrick", "Chip", "Lucky", "Dice"]

var logic: MinigameLogicBase
var stage: Node


func _ready() -> void:
	var c: Cmdline = Cmdline.parse(OS.get_cmdline_user_args())
	var game := StringName(c.get_string("game", "quiz"))
	var def: MinigameDefinition = Registry.minigames[game]
	var st := ClientMatchState.new()
	var ids: Array[int] = []
	for i: int in NAMES.size():
		st.players[i + 1] = {"id": i + 1, "name": NAMES[i], "color": i}
		ids.append(i + 1)
	logic = def.logic_script.new() as MinigameLogicBase
	logic.setup(ids, SeededRng.new(4), BalanceConfig.new(), def.params, {"bank": Registry.quiz_bank, "used": {}, "stats": {}})
	stage = def.stage_script.new()
	stage.set("send_intent", func(i: Dictionary) -> Dictionary: return logic.submit(1, i, 0.0))
	add_child(stage)
	stage.call(&"begin", st, 1, {"minigame": game, "players": ids}, {})
	match game:
		&"quiz":
			_run(8.0)
			logic.submit(2, {"question": 0, "index": 1}, 0.0)
			logic.submit(1, {"question": 0, "index": 2}, 0.0)
		&"lonely_number":
			_run(1.0)
			for p: int in [1, 2, 3]:
				logic.submit(p, {"number": [7, 7, 13][p - 1]}, 0.0)
		&"bust_or_bank":
			_run(1.0)
			for k: int in 4:
				for p: int in ids:
					logic.submit(p, {"action": "hit" if k < 2 else "stand"}, 0.0)
				_run(0.5)
	_pump()


func _run(seconds: float) -> void:
	var t: float = 0.0
	while t < seconds:
		logic.tick(0.1, t)
		t += 0.1
		_pump()


func _pump() -> void:
	for ev: Dictionary in logic.drain_events():
		stage.call(&"on_event", ev)
	if stage.has_method(&"on_private") and logic.has_method(&"private_state"):
		stage.call(&"on_private", {"minigame": logic.call(&"private_state", 1)})
