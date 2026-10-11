extends Node3D
## Dev: the Pass the Bomb vault arena with a few beans, one holding the lit bomb, and the overlay
## (render check). `xvfb-run -a tools/godot/godot --path . -s tools/screenshot.gd -- --scene
## res://tools/dev/pass_the_bomb_shot.tscn --out /tmp/ptb.png --frames 60 --pixel 1
## [--cam=x,y,z --look=x,y,z]`. `--boom` adds the explosion; `--mine` gives the bomb to "you".

const NAMES: Array[String] = ["Patrick", "Chip", "Lucky", "Dice", "Big Wendy"]

var stage: PassTheBombStage


func _ready() -> void:
	var c: Cmdline = Cmdline.parse(OS.get_cmdline_user_args())
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
	var logic := PassTheBombLogic.new()
	logic.setup(ids, SeededRng.new(3), BalanceConfig.new(), {}, {})
	stage = PassTheBombStage.new()
	add_child(stage)
	stage.begin(st, 1, {"minigame": &"pass_the_bomb", "players": ids, "room": logic.room_wire()}, {})
	var holder: int = 1 if c.has("mine") else 3
	var beans: Dictionary = {}
	for p: int in ids:
		var v := AvatarVisuals.new()
		add_child(v)
		v.position = logic.spawn_for(p)
		v.rotation.y = logic.spawn_yaw_for(p)
		v.set_color(Palette.player_color(p - 1))
		beans[p] = v
	# Two beans closing in on each other, the holder reaching out to tag.
	(beans[3] as Node3D).position = WalkableLogicBase.ROOM_ORIGIN + Vector3(0.6, 0, 0.8)
	(beans[2] as Node3D).position = WalkableLogicBase.ROOM_ORIGIN + Vector3(-0.5, 0, -0.3)
	(beans[3] as Node3D).look_at((beans[2] as Node3D).position, Vector3.UP, true)
	var grip := Node3D.new()
	grip.rotation.x = ItemModels.HAND_UPRIGHT
	var bomb := BombModel.new(0.16, true)
	bomb.position = PassTheBombStage.GRIP
	bomb.set_heat(0.6)
	grip.add_child(bomb)
	ItemModels.attach_to_hand(beans[holder], grip)
	var icon := BombModel.new(0.1, false)
	icon.position = (beans[holder] as Node3D).position + Vector3(0, 2.55, 0)
	add_child(icon)
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 62
	cam.position = WalkableLogicBase.ROOM_ORIGIN + Vector3(0, 4.6, 9.6)
	cam.look_at(WalkableLogicBase.ROOM_ORIGIN + Vector3(0, 1.4, -3.0))
	cam.current = true
	# Overlay as in play: the clock running, a bomb passed around, one player out.
	stage.on_event({"type": &"minigame_go"})
	stage.on_event({"type": &"pass_the_bomb_new", "bomb": 1, "holder": 4, "alive": ids})
	stage.on_event({"type": &"pass_the_bomb_passed", "bomb": 1, "from": 4, "to": 5})
	stage.on_event({"type": &"minigame_eliminated", "players": [5], "cause": &"bomb", "place": 5, "alive": [1, 2, 3, 4]})
	stage.on_event({"type": &"pass_the_bomb_new", "bomb": 2, "holder": holder, "alive": [1, 2, 3, 4]})
	stage.clock = 47.0
	if c.has("boom"):
		stage._explosion(WalkableLogicBase.ROOM_ORIGIN + Vector3(3.0, 1.0, -1.0))
