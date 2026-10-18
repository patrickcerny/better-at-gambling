extends Node3D
## Dev: a stand-in bean (the avatar's capsule, gravity, jump and walking speed, no sprint) runs the
## Jackpot Climb course on the real collision along one way up (`--bold=0,1,0,1`: per segment, 1
## takes the bold lane at the fork; default all steady), steered by `ChipTowers.guide`: it runs
## where the guide points and jumps when the guide says a hop is right ahead (or it has stood still
## for a while), and reports whether it reached the pad, how long it took, how often it jumped and
## fell. `tools/godot/godot --headless --path . res://tools/dev/jackpot_climb_bot.tscn -- --bold=1,1,1,1`

const GRAVITY: float = PlayerAvatar.GRAVITY
const TIME_CAP: float = 150.0
const STUCK_SECONDS: float = 0.6

var body: CharacterBody3D
var cfg := BalanceConfig.new()
var bold: Array[bool] = [false, false, false, false]
var t: float = 0.0
var jumps: int = 0
var falls: int = 0
var _still_t: float = 0.0
var _still_at: Vector3 = Vector3.INF
var _floor_y: float = 0.0


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--bold="):
			var parts: PackedStringArray = a.trim_prefix("--bold=").split(",")
			for i: int in mini(parts.size(), bold.size()):
				bold[i] = parts[i] == "1"
	ClimbRoom.build(self, "towers")
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
	print("JACKPOT BOT: bold %s" % [bold])


func _ring(p: Vector3) -> int:
	var rho: float = ChipTowers.flat_r(p)
	for seg: int in ChipTowers.SEGMENTS:
		if rho >= ChipTowers.ring_inner(seg) - 0.05 and rho <= ChipTowers.ring_outer(seg) + 0.05:
			return seg
	return 0


func _physics_process(delta: float) -> void:
	t += delta
	var pos: Vector3 = body.global_position
	var local: Vector3 = pos - WalkableLogicBase.ROOM_ORIGIN
	var on_floor: bool = body.is_on_floor()
	var g: Dictionary = ChipTowers.guide(local, bold[_ring(local)])
	var to: Vector3 = g["to"]
	var flat := Vector3(to.x - local.x, 0.0, to.z - local.z)
	var wish: Vector3 = flat.normalized() if flat.length() > 0.1 else Vector3.ZERO
	var horizontal := Vector3(body.velocity.x, 0.0, body.velocity.z).move_toward(wish * cfg.walk_speed, cfg.acceleration * delta)
	body.velocity.x = horizontal.x
	body.velocity.z = horizontal.z
	if _still_at == Vector3.INF or pos.distance_to(_still_at) > 0.3:
		_still_at = pos
		_still_t = 0.0
	else:
		_still_t += delta
	if not on_floor:
		body.velocity.y -= GRAVITY * delta
	else:
		if pos.y < _floor_y - 0.6:
			falls += 1
			print("JACKPOT BOT: fell to y %.2f" % pos.y)
		_floor_y = pos.y
		body.velocity.y = minf(body.velocity.y, 0.0)
		if bool(g["hop"]) or _still_t > STUCK_SECONDS:
			body.velocity.y = sqrt(2.0 * GRAVITY * cfg.jump_height)
			jumps += 1
			_still_t = 0.0
	body.move_and_slide()
	if ClimbRoom.on_top(body.global_position, "towers"):
		print("JACKPOT BOT: reached the pad in %.1f s, %d jumps, %d falls" % [t, jumps, falls])
		get_tree().quit(0)
	elif t > TIME_CAP:
		print("JACKPOT BOT: FAILED at %s, %d falls" % [body.global_position, falls])
		get_tree().quit(1)
