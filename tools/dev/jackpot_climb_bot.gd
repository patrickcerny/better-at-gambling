extends Node3D
## Dev: a stand-in bean (the avatar's capsule, gravity, jump and walking speed, no sprint) climbs
## the Jackpot Climb towers on the real collision, stack by stack, jumping near each rim toward
## the next one, and reports whether it reached the pad and how long it took.
## `tools/godot/godot --headless --path . res://tools/dev/jackpot_climb_bot.tscn`

const GRAVITY: float = PlayerAvatar.GRAVITY
const TIME_CAP: float = 120.0

var body: CharacterBody3D
var cfg := BalanceConfig.new()
var route: Array[Dictionary] = []
var target: int = 0
var t: float = 0.0
var jumps: int = 0
var falls: int = 0
var _last_y: float = 0.0


func _ready() -> void:
	ClimbRoom.build(self, "towers")
	route = ChipTowers.route()
	body = CharacterBody3D.new()
	body.floor_snap_length = 0.3
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.42
	cap.height = 1.7
	cs.shape = cap
	cs.position.y = 0.85
	body.add_child(cs)
	add_child(body)
	body.global_position = (ClimbRoom.layout("towers")["spawns"] as Array)[0]


func _physics_process(delta: float) -> void:
	t += delta
	var o: Vector3 = WalkableLogicBase.ROOM_ORIGIN
	var pos: Vector3 = body.global_position
	var goal: Vector3 = o + (route[target]["pos"] as Vector3)
	var flat: Vector3 = goal - pos
	flat.y = 0.0
	var wish: Vector3 = flat.normalized() if flat.length() > 0.05 else Vector3.ZERO
	var on_floor: bool = body.is_on_floor()
	if on_floor:
		_land(pos)
		goal = o + (route[target]["pos"] as Vector3)
		flat = goal - pos
		flat.y = 0.0
		wish = flat.normalized() if flat.length() > 0.05 else Vector3.ZERO
	var horizontal := Vector3(body.velocity.x, 0.0, body.velocity.z).move_toward(wish * cfg.walk_speed, cfg.acceleration * delta)
	body.velocity.x = horizontal.x
	body.velocity.z = horizontal.z
	if not on_floor:
		body.velocity.y -= GRAVITY * delta
	else:
		body.velocity.y = minf(body.velocity.y, 0.0)
		var edge: float = flat.length() - float(route[target]["r"])
		if edge < ChipTowers.MAX_GAP + 0.15 and goal.y > pos.y + 0.2:
			body.velocity.y = sqrt(2.0 * GRAVITY * cfg.jump_height)
			jumps += 1
	body.move_and_slide()
	if ClimbRoom.on_top(body.global_position, "towers"):
		print("JACKPOT BOT: reached the pad in %.1f s, %d jumps, %d falls" % [t, jumps, falls])
		get_tree().quit(0)
	elif t > TIME_CAP:
		print("JACKPOT BOT: FAILED at ledge %d/%d, y %.2f, %d falls" % [target, route.size(), body.global_position.y, falls])
		get_tree().quit(1)


## On a floor: work out which ledge we stand on and aim at the next one.
func _land(pos: Vector3) -> void:
	var o: Vector3 = WalkableLogicBase.ROOM_ORIGIN
	var on: int = -1
	for i: int in route.size():
		var c: Vector3 = o + (route[i]["pos"] as Vector3)
		if absf(pos.y - c.y) < 0.15 and Vector2(pos.x - c.x, pos.z - c.z).length() < float(route[i]["r"]) + 0.45:
			on = i
	if pos.y < _last_y - 0.3:
		falls += 1
	_last_y = pos.y
	target = mini(on + 1, route.size() - 1)
