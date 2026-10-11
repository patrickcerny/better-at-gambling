extends Node3D
## Dev: Roulette Sumo 20 s in: the wheel turned, the ball rolling across the deck, four beans
## with bats, Lucky on the dais and the overlay (render check).
## `xvfb-run -a tools/godot/godot --path . -s tools/screenshot.gd -- --scene
## res://tools/dev/roulette_sumo_shot.tscn --out /tmp/rs.png --frames 30 --pixel 1`.

const NAMES: Array[String] = ["Patrick", "Chip", "Lucky", "Dice"]

var stage: RouletteSumoStage


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
	var logic := RouletteSumoLogic.new()
	logic.setup(ids, SeededRng.new(3), BalanceConfig.new(), {}, {})
	stage = RouletteSumoStage.new()
	add_child(stage)
	stage.begin(st, 1, {"minigame": &"roulette_sumo", "players": ids, "room": logic.room_wire()}, {})
	stage.on_event({"type": &"minigame_go"})
	stage.on_event({"type": &"roulette_sumo_wheel", "clock": 20.0, "angle": RouletteSumoLogic.wheel_angle(20.0), "omega": RouletteSumoLogic.omega_at(20.0)})
	stage.on_event({"type": &"roulette_sumo_ball", "ball": {"p": [2.6, 2.2], "v": [4.0, -3.0], "t": 0.3}, "clock": 20.0})
	var c: Vector3 = WheelRoom.center() + Vector3(0, WheelRoom.WHEEL_TOP, 0)
	for b: Array in [[1, c + Vector3(0.8, 0, 4.6), 0.3], [2, c + Vector3(-3.6, 0, 2.2), -1.0], [3, c + Vector3(4.6, 0, -1.4), 2.0], [4, c + Vector3(-1.5, 0, -5.4), 3.0]]:
		var v := AvatarVisuals.new()
		add_child(v)
		v.position = b[1]
		v.rotation.y = b[2]
		v.set_color(Palette.player_color(int(b[0]) - 1))
		var bat: Node3D = ItemModels.make_held(&"baseball_bat")
		ItemModels.attach_to_hand(v, bat)
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 64
	cam.position = c + Vector3(0, 6.5, 12.5)
	cam.look_at(c + Vector3(0, -0.5, -1.5))
	cam.current = true
