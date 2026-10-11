extends Node3D
## Dev: the Grab Your Hand card hall mid-game: cards on the floor, four beans with hands fanned
## over their heads, Lucky at the dealer's table and the overlay with our hand bar (render check).
## `GYH_REVEAL=1` shows the showdown instead.
## `xvfb-run -a tools/godot/godot --path . -s tools/screenshot.gd -- --scene
## res://tools/dev/grab_your_hand_shot.tscn --out /tmp/gyh.png --frames 60 --pixel 1`.

const NAMES: Array[String] = ["Patrick", "Chip", "Lucky", "Dice"]

var stage: GrabYourHandStage


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
	var logic := GrabYourHandLogic.new()
	logic.setup(ids, SeededRng.new(3), BalanceConfig.new(), {}, {})
	logic.tick(0.05, 0.0)
	stage = GrabYourHandStage.new()
	add_child(stage)
	stage.begin(st, 1, {"minigame": &"grab_your_hand", "players": ids, "room": logic.room_wire()}, {})
	stage.on_event({"type": &"minigame_go"})
	var hands: Dictionary = {
		1: [Card.make(9, 0), Card.make(9, 1), Card.make(4, 2)],
		2: [Card.make(1, 3), Card.make(13, 3), Card.make(7, 3), Card.make(2, 3)],
		3: [Card.make(12, 1)],
		4: [Card.make(5, 0), Card.make(5, 2), Card.make(11, 1), Card.make(11, 0), Card.make(3, 3)],
	}
	for ev: Dictionary in logic.drain_events():
		stage.on_event(ev)
	for p: int in hands:
		stage._set_hand(p, hands[p])
	var c: Vector3 = CardHall.center()
	var bodies: Array = [[1, c + Vector3(0.6, 0, 3.6)], [2, c + Vector3(-3.4, 0, 1.8)], [3, c + Vector3(3.6, 0, 0.6)], [4, c + Vector3(-1.6, 0, -3.2)]]
	for b: Array in bodies:
		var v := AvatarVisuals.new()
		add_child(v)
		v.position = b[1]
		v.rotation.y = 0.4
		v.set_color(Palette.player_color(int(b[0]) - 1))
		var fan := HandFan.new()
		add_child(fan)
		fan.position = (b[1] as Vector3) + Vector3(0, GrabYourHandStage.FAN_UP, 0)
		var t: Array[int] = PokerHand.evaluate(hands[b[0]])
		fan.set_cards(hands[b[0]], PokerHand.name_of(t))
	if OS.get_environment("GYH_REVEAL") == "1":
		logic.hands.clear()
		for p: int in hands:
			logic.hands[p] = hands[p]
		stage.on_event({"type": &"grab_your_hand_over", "hands": hands, "ranking": logic.ranking()})
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 64
	cam.position = c + Vector3(0, 4.2, 9.4)
	cam.look_at(c + Vector3(0, 0.8, -2.0))
	cam.current = true
