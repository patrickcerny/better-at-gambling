extends Node3D
## Dev: Jackpot Climb 30 s in: the chip cake from the apron, beans on both lanes with their bats,
## one at checkpoint 2's flag, one on the pad, the JACKPOT sign, Lucky on his podium and the
## overlay (render check). `--cam`/`--look` give close-ups of the chips. `xvfb-run -a tools/godot/godot --path . -s tools/screenshot.gd -- --scene
## res://tools/dev/jackpot_climb_shot.tscn --out /tmp/jc.png --frames 30 --pixel 1`.

const NAMES: Array[String] = ["Patrick", "Chip", "Lucky", "Dice"]

var stage: JackpotClimbStage


func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Palette.CASINO_BLACK
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(1.0, 0.88, 0.75)
	env.environment.ambient_light_energy = 0.35
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(env)
	var st := ClientMatchState.new()
	var ids: Array[int] = []
	for i: int in NAMES.size():
		st.players[i + 1] = {"id": i + 1, "name": NAMES[i], "color": i}
		ids.append(i + 1)
	var logic := JackpotClimbLogic.new()
	logic.setup(ids, SeededRng.new(3), BalanceConfig.new(), {}, {})
	stage = JackpotClimbStage.new()
	add_child(stage)
	stage.begin(st, 1, {"minigame": &"jackpot_climb", "players": ids, "room": logic.room_wire()}, {})
	stage.on_event({"type": &"minigame_go"})
	stage.on_event({"type": &"jackpot_climb_clock", "clock": 30.0})
	stage.on_event({"type": &"jackpot_climb_top", "players": [4], "place": 1, "clock": 28.0})
	var o: Vector3 = WalkableLogicBase.ROOM_ORIGIN
	var stacks: Array[Dictionary] = ChipTowers.stacks()
	stage.on_event({"type": &"jackpot_climb_checkpoint", "player": 1, "index": 1})
	var cp2: Vector3 = (ChipTowers.checkpoints()[1]["spots"] as Array)[1]
	for b: Array in [[1, ChipTowers.lane(0, 1)[2], 0.6], [2, ChipTowers.lane(0, -1)[4], -0.6], [3, -1, 0.0]]:
		var v := AvatarVisuals.new()
		add_child(v)
		v.position = o + ((stacks[int(b[1])]["pos"] as Vector3) if int(b[1]) >= 0 else cp2)
		v.rotation.y = b[2]
		v.set_color(Palette.player_color(int(b[0]) - 1))
		var bat: Node3D = ItemModels.make_held(&"baseball_bat")
		ItemModels.attach_to_hand(v, bat)
	var w := AvatarVisuals.new()
	add_child(w)
	w.position = o + ChipTowers.pad_center()
	w.set_color(Palette.player_color(3))
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 70
	cam.position = o + Vector3(2.0, 4.0, 9.0)
	cam.look_at(o + Vector3(0, 11.0, -12.5))
	cam.current = true
