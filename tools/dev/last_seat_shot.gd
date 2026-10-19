extends Node3D
## Dev: the Last Seat parlor right after the music stopped: three stools out round the table, two
## beans already seated, two running, Lucky by the gramophone and the overlay (render check).
## `xvfb-run -a tools/godot/godot --path . -s tools/screenshot.gd -- --scene
## res://tools/dev/last_seat_shot.tscn --out /tmp/ls.png --frames 60`.

const NAMES: Array[String] = ["Patrick", "Chip", "Lucky", "Dice"]

var stage: LastSeatStage


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
	var logic := LastSeatLogic.new()
	logic.setup(ids, SeededRng.new(3), BalanceConfig.new(), {}, {})
	stage = LastSeatStage.new()
	add_child(stage)
	stage.begin(st, 1, {"minigame": &"last_seat", "players": ids, "room": logic.room_wire()}, {})
	var spots: Array[Vector3] = ParlorRoom.stool_ring(3, 0.5)
	var wire: Array = []
	for s: Vector3 in spots:
		wire.append(Serializer.vec3(s))
	stage.on_event({"type": &"minigame_go"})
	stage.on_event({"type": &"last_seat_round", "round": 1, "stools": 3})
	stage.on_event({"type": &"last_seat_stop", "stools": wire, "grace": 10.0})
	stage.on_event({"type": &"last_seat_sat", "player": 2, "stool": 0})
	stage.on_event({"type": &"last_seat_sat", "player": 3, "stool": 2})
	var c: Vector3 = ParlorRoom.table_center()
	var bodies: Array = [[2, spots[0] + Vector3(0, 0.5, 0), true], [3, spots[2] + Vector3(0, 0.5, 0), true], [1, c + Vector3(1.2, 0, 3.4), false], [4, c + Vector3(-3.4, 0, 1.5), false]]
	for b: Array in bodies:
		var v := AvatarVisuals.new()
		add_child(v)
		v.position = b[1]
		v.sitting = b[2]
		v.rotation.y = ParlorRoom.yaw_to_table(b[1]) if b[2] else 0.6
		v.set_color(Palette.player_color(int(b[0]) - 1))
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 64
	cam.position = c + Vector3(0, 3.4, 7.2)
	cam.look_at(c + Vector3(0, 0.6, -1.5))
	cam.current = true
