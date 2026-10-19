extends Node3D
## Dev: the Bat Heist vault arena with a few beans holding bats, one knocked flat with a "STEAL!"
## coin badge, one shimmering with immunity, and the overlay (render check). `xvfb-run -a
## tools/godot/godot --path . -s tools/screenshot.gd -- --scene res://tools/dev/bat_heist_shot.tscn
## --out /tmp/bh.png --frames 60`.

const NAMES: Array[String] = ["Patrick", "Chip", "Lucky", "Dice", "Big Wendy"]

var stage: BatHeistStage


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
	var logic := BatHeistLogic.new()
	logic.setup(ids, SeededRng.new(3), BalanceConfig.new(), {}, {})
	stage = BatHeistStage.new()
	add_child(stage)
	stage.begin(st, 1, {"minigame": &"bat_heist", "players": ids, "room": logic.room_wire()}, {})
	var o: Vector3 = WalkableLogicBase.ROOM_ORIGIN
	var spots: Array[Vector3] = [o + Vector3(-2.2, 0, 2.6), o + Vector3(0.9, 0, 0.6), o + Vector3(-0.4, 0, -0.5), o + Vector3(2.6, 0, -1.6), o + Vector3(-3.2, 0, -1.8)]
	var counts: Array[int] = [12, 15, 4, 9, 10]
	for p: int in ids:
		var v := AvatarVisuals.new()
		add_child(v)
		v.position = spots[p - 1]
		v.rotation.y = logic.spawn_yaw_for(p)
		v.set_color(Palette.player_color(p - 1))
		var bat: Node3D = ItemModels.make_held(&"baseball_bat")
		ItemModels.attach_to_hand(v, bat)
		if p == 2:
			bat.rotation += Vector3(0.25, 0.0, -1.5)  # mid swing
		if p == 3:
			v.rotation.z = PI * 0.5  # lying on the floor
			v.position.y = 0.4
		var badge := CoinBadge.new(counts[p - 1])
		add_child(badge)
		badge.position = spots[p - 1] + Vector3(0, BatHeistStage.BADGE_DOWN if p == 3 else BatHeistStage.BADGE_UP, 0)
		badge.set_stealable(p == 3)
		stage.coins[p] = counts[p - 1]
	var shimmer := ImmunityShimmer.new(60.0)  # long: the first frames of a render take seconds
	add_child(shimmer)
	shimmer.position = spots[3]
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 62
	cam.position = o + Vector3(0, 3.6, 7.0)
	cam.look_at(o + Vector3(0, 1.0, -1.0))
	cam.current = true
	stage.on_event({"type": &"minigame_go"})
	stage.on_event({"type": &"bat_heist_hit", "player": 2, "target": 3, "seconds": 3.0})
	stage.on_event({"type": &"bat_heist_stole", "player": 2, "target": 3, "coins": {2: 15, 3: 4}})
	stage.clock = 41.0
