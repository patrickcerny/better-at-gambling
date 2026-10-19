extends Node3D
## Dev: Dodge the Dice 20 s in: the tilted roulette board from the apron, beans on the rows, a
## ball, a coin and a die rolling down, Lucky by the WINNER rail and the overlay (render check).
## `xvfb-run -a tools/godot/godot --path . -s tools/screenshot.gd -- --scene
## res://tools/dev/dodge_the_dice_shot.tscn --out /tmp/dd.png --frames 30`.

const NAMES: Array[String] = ["Patrick", "Chip", "Lucky", "Dice"]

var stage: DodgeTheDiceStage


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
	var logic := DodgeTheDiceLogic.new()
	logic.setup(ids, SeededRng.new(3), BalanceConfig.new(), {}, {})
	stage = DodgeTheDiceStage.new()
	add_child(stage)
	stage.begin(st, 1, {"minigame": &"dodge_the_dice", "players": ids, "room": logic.room_wire()}, {})
	stage.on_event({"type": &"minigame_go"})
	stage.on_event({"type": &"dodge_the_dice_clock", "clock": 20.0})
	for h: Dictionary in [
		{"id": 1, "kind": "ball", "lane": -3.0, "speed": 9.5, "t0": 18.6, "seed": 11},
		{"id": 2, "kind": "coin", "lane": 2.0, "speed": 5.0, "t0": 16.5, "seed": 22},
		{"id": 3, "kind": "dice", "lane": 0.5, "speed": 6.0, "t0": 17.0, "seed": 33},
		{"id": 4, "kind": "dice", "lane": -4.5, "speed": 6.5, "t0": 19.8, "seed": 44},
	]:
		var ev: Dictionary = h.duplicate()
		ev["type"] = &"dodge_the_dice_hazard"
		stage.on_event(ev)
	var o: Vector3 = WalkableLogicBase.ROOM_ORIGIN
	for b: Array in [[1, Vector3(1.0, 0, -6.5), 0.0], [2, Vector3(-3.5, 0, -9.2), 0.2], [3, Vector3(4.6, 0, -14.0), -0.3], [4, Vector3(-1.2, 0, -19.0), 0.0]]:
		var v := AvatarVisuals.new()
		add_child(v)
		var at: Vector3 = o + (b[1] as Vector3)
		at.y = ClimbRoom.surface_y(at.z)
		v.position = at
		v.rotation.y = b[2]
		v.set_color(Palette.player_color(int(b[0]) - 1))
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 70
	cam.position = o + Vector3(0, 3.2, 6.0)
	cam.look_at(o + Vector3(0, 9.0, -16.0))
	cam.current = true

