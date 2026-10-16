extends Node3D
## Dev: a stand-in bean (the avatar's capsule, gravity, jump and walking speed, no sprint) climbs
## the Jackpot Climb chip cake on the real collision along one way up (`--sides=-1,1,-1,1`: the
## lane round each tier; default all left), ledge by ledge: it walks at the next ledge and jumps
## when the rim is close or its own stack runs out under it, and reports whether it reached the
## pad, how long it took and how often it fell.
## `tools/godot/godot --headless --path . res://tools/dev/jackpot_climb_bot.tscn -- --sides=1,1,1,1`

const GRAVITY: float = PlayerAvatar.GRAVITY
const TIME_CAP: float = 150.0
## Jump when the next rim is this close, or when our own stack's rim is this close behind us.
const JUMP_AT: float = 0.9
const OWN_EDGE: float = 0.2

var body: CharacterBody3D
var cfg := BalanceConfig.new()
var route: Array[Dictionary] = []
var target: int = 0
var own: int = -1
var t: float = 0.0
var jumps: int = 0
var falls: int = 0
var _last_y: float = 0.0


func _ready() -> void:
	var sides: Array[int] = [-1, -1, -1, -1]
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--sides="):
			var parts: PackedStringArray = a.trim_prefix("--sides=").split(",")
			for i: int in mini(parts.size(), sides.size()):
				sides[i] = int(parts[i])
	ClimbRoom.build(self, "towers")
	route = ChipTowers.route(sides)
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
	print("JACKPOT BOT: sides %s, %d ledges" % [sides, route.size()])


## Where to aim for ledge `i` (world): a stack's centre, or a tier's rim where the lanes arrive.
func _goal(i: int) -> Vector3:
	var o: Vector3 = WalkableLogicBase.ROOM_ORIGIN
	var l: Dictionary = route[i]
	if String(l["kind"]) == "stack":
		return o + (l["pos"] as Vector3)
	var k: int = int(l["level"])
	var c: Vector3 = l["pos"]
	if k >= ChipTowers.SEGMENTS:
		return o + c
	return o + c + ChipTowers.dir(ChipTowers.start_angle(k)) * (float(l["r"]) - 0.9)


## Flat distance from `pos` to ledge `i`'s rim (negative: over it).
func _edge(i: int, pos: Vector3) -> float:
	var o: Vector3 = WalkableLogicBase.ROOM_ORIGIN
	var c: Vector3 = o + (route[i]["pos"] as Vector3)
	return Vector2(pos.x - c.x, pos.z - c.z).length() - float(route[i]["r"])


func _physics_process(delta: float) -> void:
	t += delta
	var pos: Vector3 = body.global_position
	var on_floor: bool = body.is_on_floor()
	if on_floor:
		_land(pos)
	var goal: Vector3 = _goal(target)
	var flat: Vector3 = goal - pos
	flat.y = 0.0
	var wish: Vector3 = flat.normalized() if flat.length() > 0.05 else Vector3.ZERO
	var horizontal := Vector3(body.velocity.x, 0.0, body.velocity.z).move_toward(wish * cfg.walk_speed, cfg.acceleration * delta)
	body.velocity.x = horizontal.x
	body.velocity.z = horizontal.z
	if not on_floor:
		body.velocity.y -= GRAVITY * delta
	else:
		body.velocity.y = minf(body.velocity.y, 0.0)
		var near: bool = _edge(target, pos) < JUMP_AT
		var running_out: bool = own >= 0 and String(route[own]["kind"]) == "stack" and _edge(own, pos) > -OWN_EDGE
		if (near or running_out) and goal.y > pos.y + 0.15:
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
		if absf(pos.y - c.y) < 0.15 and _edge(i, pos) < 0.3:
			on = i
	if pos.y < _last_y - 0.3:
		falls += 1
		print("JACKPOT BOT: fell to y %.2f going for ledge %d" % [pos.y, target])
	_last_y = pos.y
	if on >= 0 or pos.y < 0.2:
		own = on
		target = mini(on + 1, route.size() - 1)
