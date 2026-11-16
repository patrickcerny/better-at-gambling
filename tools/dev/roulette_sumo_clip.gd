extends Node3D
## Dev: the scripted preview clip of Roulette Sumo (tools/minigame_clips.sh roulette_sumo, picked up
## by tools/dev/minigame_clip.gd). Patrick 2026-11-16: the old clip ("super ass") was beans
## wobbling in little circles while the wheel turned under them. This one tells the game in 6 s:
## five beans ride the spinning wheel and lean inward against the drag, the roulette ball rolls
## across the deck and bowls one bean over the rim (OUT!), one bean shoves another toward the
## edge and it scrambles back, a second shove near the end. The real stage draws the room, the
## wheel, the ball, Lucky and the overlay; this scene only moves the beans and the camera.

const NAMES: Array[String] = ["Patrick", "Chip", "Lucky", "Dice", "Big Wendy"]
## Seconds before the story starts (minigame_clip.gd records after its warmup, 1 s).
const LEAD: float = 1.0
const WHEEL_CLOCK: float = 14.0

var stage: RouletteSumoStage
var cam: Camera3D
var t: float = -LEAD
var _c: Vector3
## id → {vis, p (flat, rel. centre), y (height above the deck), vel, state, ...}
var beans: Dictionary = {}
var _cam_base: Vector3
var _ball_started: bool = false
var _fired: Dictionary = {}


func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Palette.CASINO_BLACK
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1.0, 0.88, 0.75)
	e.ambient_light_energy = 0.4
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
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
	stage.on_event({"type": &"roulette_sumo_spin"})
	stage.on_event({"type": &"roulette_sumo_wheel", "clock": WHEEL_CLOCK, "angle": RouletteSumoLogic.wheel_angle(WHEEL_CLOCK), "omega": RouletteSumoLogic.omega_at(WHEEL_CLOCK)})
	_park_ball()
	_c = WheelRoom.center() + Vector3(0, WheelRoom.WHEEL_TOP, 0)
	# Where everyone stands (flat, relative to the centre; +z towards the camera).
	var spots: Array[Vector2] = [Vector2(-1.9, 3.3), Vector2(-3.4, 1.4), Vector2(2.2, 2.4), Vector2(1.2, -3.4), Vector2(3.6, -0.9)]
	for i: int in ids.size():
		var v := AvatarVisuals.new()
		add_child(v)
		v.set_color(Palette.player_color(i))
		beans[ids[i]] = {"vis": v, "p": spots[i], "home": spots[i], "y": 0.0, "vy": 0.0, "push": Vector2.ZERO, "state": &"ride", "phase": i * 1.3, "prev": spots[i]}
		_place(ids[i], 0.0)
	cam = Camera3D.new()
	add_child(cam)
	cam.fov = 58
	_cam_base = Vector3(0, 6.1, 11.2)  # under the ceiling (about 7 m up)
	cam.current = true
	_update_cam()


func _park_ball() -> void:
	stage.ball_pos = Vector2(-5.7, 2.4)
	stage.ball_vel = Vector2.ZERO
	stage.ball_turn = 0.0


func _process(delta: float) -> void:
	t += delta
	if t < 0.0:
		_park_ball()
	elif not _ball_started:
		_ball_started = true
		stage.ball_pos = Vector2(-5.7, 2.4)
		stage.ball_vel = Vector2(3.7, 0.15)
		stage.ball_turn = 0.0
	_story()
	for id: int in beans:
		_place(id, delta)
	_update_cam()


## The beats: shoves and the ball's victim.
func _story() -> void:
	if _once(&"shove1", 0.9):
		_swing_at(1, 2)
	if _once(&"shove1_land", 0.9 + AvatarVisuals.SWING_CONTACT):
		_shoved(2, 1, 4.6)
	# The ball reaches Lucky (bean 3) at about 1.95 s.
	if t >= 0.0 and not _fired.has(&"ball") and beans[3]["state"] == &"ride":
		var off: Vector2 = (beans[3]["p"] as Vector2) - stage.ball_pos
		if off.length() <= RouletteSumoLogic.BALL_HIT:
			_fired[&"ball"] = true
			var roll: Vector2 = stage.ball_vel.normalized()
			var dir: Vector2 = (roll * 1.2 + off.normalized()).normalized()
			beans[3]["state"] = &"flung"
			beans[3]["push"] = dir * 6.2
			(beans[3]["vis"] as AvatarVisuals).hit(Vector3(dir.x, 0, dir.y), 1.0)
			Vfx.floating_text(self, _world(beans[3]["p"]) + Vector3(0, 2.0, 0), "BUMPED!", Palette.CREAM, 90, 0.8, 1.0)
	if _once(&"shove2", 3.7):
		_swing_at(4, 5)
	if _once(&"shove2_land", 3.7 + AvatarVisuals.SWING_CONTACT):
		_shoved(5, 4, 4.0)


func _once(key: StringName, at: float) -> bool:
	if t < at or _fired.has(key):
		return false
	_fired[key] = true
	return true


func _swing_at(by: int, target: int) -> void:
	var v: AvatarVisuals = beans[by]["vis"]
	var to: Vector3 = _world(beans[target]["p"])
	v.look_at(Vector3(to.x, v.global_position.y, to.z), Vector3.UP, true)
	beans[by]["face"] = 0.6
	v.swing()


func _shoved(target: int, by: int, strength: float) -> void:
	var dir: Vector2 = ((beans[target]["p"] as Vector2) - (beans[by]["p"] as Vector2)).normalized()
	beans[target]["push"] = dir * strength
	beans[target]["vy"] = strength * RouletteSumoStage.PUSH_LIFT * 2.0
	(beans[target]["vis"] as AvatarVisuals).hit(Vector3(dir.x, 0, dir.y), 0.8)
	Vfx.floating_text(self, _world(beans[target]["p"]) + Vector3(0, 2.0, 0), "PUSH!", Palette.VIP_GOLD, 90, 0.8, 0.9)


func _place(id: int, delta: float) -> void:
	var b: Dictionary = beans[id]
	var v: AvatarVisuals = b["vis"]
	var p: Vector2 = b["p"]
	var prev: Vector2 = p
	var omega: float = RouletteSumoLogic.omega_at(WHEEL_CLOCK)
	match b["state"]:
		&"ride":
			# Carried round a little by the deck, walking back toward home against the drag.
			var drift: Vector2 = Vector2(p.y, -p.x) * omega * 0.35 + p.normalized() * 0.5
			var home: Vector2 = (b["home"] as Vector2) + Vector2(sin(t * 1.7 + float(b["phase"])), cos(t * 1.3 + float(b["phase"]))) * 0.35
			var walk: Vector2 = (home - p).limit_length(1.0) * 2.4
			p += (drift + walk + (b["push"] as Vector2)) * delta
			b["push"] = (b["push"] as Vector2).move_toward(Vector2.ZERO, 9.0 * delta)
		&"flung":
			p += (b["push"] as Vector2) * delta
			b["push"] = (b["push"] as Vector2) * maxf(1.0 - 0.6 * delta, 0.0)
			if p.length() > RouletteSumoLogic.FALL_RADIUS:
				b["state"] = &"falling"
				b["vy"] = 1.5
				stage.on_event({"type": &"minigame_eliminated", "players": [id], "cause": &"fell", "place": 5})
				Vfx.floating_text(self, _world(p) + Vector3(0, 2.2, 0), "OUT!", Palette.LOSS_RED, 120, 1.0, 1.2)
		&"falling":
			p += (b["push"] as Vector2) * delta * 0.6
			v.rotation.z = move_toward(v.rotation.z, -1.4, 3.0 * delta)
	# Height: hops after a shove, a fall into the pit.
	if b["state"] == &"falling":
		b["vy"] = float(b["vy"]) - 14.0 * delta
		b["y"] = maxf(float(b["y"]) + float(b["vy"]) * delta, -WheelRoom.WHEEL_TOP + 0.1)
	elif float(b["y"]) > 0.0 or float(b["vy"]) > 0.0:
		b["vy"] = float(b["vy"]) - 14.0 * delta
		b["y"] = maxf(float(b["y"]) + float(b["vy"]) * delta, 0.0)
		if float(b["y"]) <= 0.0:
			b["vy"] = 0.0
	b["p"] = p
	var at: Vector3 = _world(p) + Vector3(0, float(b["y"]), 0)
	var vel: Vector3 = (at - v.global_position) / maxf(delta, 0.001) if delta > 0.0 else Vector3.ZERO
	v.global_position = at
	b["face"] = maxf(float(b.get("face", 0.0)) - delta, 0.0)
	if b["state"] == &"ride" and float(b["face"]) <= 0.0:
		# Lean into the walk toward the middle, like a player fighting the wheel.
		var look: Vector2 = -p.normalized() + (p - prev) * 0.3
		v.look_at(at + Vector3(look.x, 0, look.y), Vector3.UP, true)
	if delta > 0.0 and b["state"] != &"falling":
		v.update_motion(vel, float(b["y"]) <= 0.0, delta)


func _world(p: Vector2) -> Vector3:
	return _c + Vector3(p.x, 0, p.y)


func _update_cam() -> void:
	var a: float = sin(maxf(t, 0.0) / 6.0 * PI) * deg_to_rad(9.0)
	cam.global_position = _c + _cam_base.rotated(Vector3.UP, a)
	cam.look_at(_c + Vector3(0, -0.4, -0.6))
