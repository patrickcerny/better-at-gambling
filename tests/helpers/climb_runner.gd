class_name ClimbRunner
extends RefCounted
## Drives a real `PlayerAvatar` (the game's capsule, gravity, walking and sprint speeds, the jump
## from `BalanceConfig`) over the Jackpot Climb course with `ChipTowers.guide`, the way a player
## holding forward would: it faces where the guide points, walks (or sprints), and jumps only when
## the guide says a hop is right ahead or it has not moved for `STUCK_SECONDS`. Physics is stepped
## by hand at 60 Hz (the avatar's own `_physics_process`, so `move_and_slide` on the real
## collision), which lets a test run hundreds of climbs in seconds. The server's
## `JackpotClimbLogic` watches its positions every step: a fall below its checkpoint comes back as a
## respawn, which the runner applies like the client does (`teleport`).

## An input router that holds forward (and sprint) for the bean.
class Router:
	extends InputRouter
	var move: Vector2 = Vector2.ZERO
	var sprint: bool = false

	func move_vector() -> Vector2:
		return move

	func sprint_held() -> bool:
		return sprint

	func stick_look() -> Vector2:
		return Vector2.ZERO


const DT: float = 1.0 / 60.0
const PLAYER: int = 1
## Jump after standing (nearly) still this long while trying to move.
const STUCK_SECONDS: float = 0.6
const STUCK_MOVE: float = 0.3

var bean: PlayerAvatar
var router: Router
var logic: JackpotClimbLogic
## Per segment: take the bold lane at its fork.
var bold: Array[bool] = [false, false, false, false]
var jumps_allowed: bool = true
var sprint: bool = false
var clock: float = 0.0
var jumps: int = 0
var respawns: int = 0
var stuck_jumps: int = 0
## Where each jump happened: "clock lane theta" (for failure messages).
var jump_log: PackedStringArray = []
var _still_t: float = 0.0
var _still_at: Vector3 = Vector3.INF


func _init(parent: Node3D) -> void:
	bean = PlayerAvatar.new()
	bean.cfg = BalanceConfig.new()
	bean.name = "RunnerBean"
	parent.add_child(bean)
	bean.drive = PlayerAvatar.Drive.INPUT
	bean.set_physics_process(false)
	router = Router.new()
	bean.router = router


func free_bean() -> void:
	bean.router = null
	router.free()
	bean.queue_free()


## Puts the bean at world `at`, still, with checkpoint `cp` reached (0: none), and a fresh server
## game watching it.
func place(at: Vector3, cp: int = 0) -> void:
	bean.teleport(at, 0.0)
	clock = 0.0
	jumps = 0
	respawns = 0
	stuck_jumps = 0
	jump_log.clear()
	_still_t = 0.0
	_still_at = Vector3.INF
	logic = JackpotClimbLogic.new()
	logic.setup([PLAYER, 2], SeededRng.new(1), BalanceConfig.new(), {}, {})
	logic.world = WorldQuery.new()
	logic.world.set_transform(PLAYER, at, 0.0)
	logic.world.set_transform(2, logic.spawn_for(2), 0.0)
	logic.tick(DT, 0.0)
	logic.drain_events()
	if cp > 0:
		logic.checkpoint[PLAYER] = cp


## The bean's position in the room's frame (what `ChipTowers` speaks).
func local() -> Vector3:
	return bean.global_position - WalkableLogicBase.ROOM_ORIGIN


## The segment whose ring the bean is over (by its distance from the axis; -1 off the cake).
static func ring_of(p: Vector3) -> int:
	var rho: float = ChipTowers.flat_r(p)
	for seg: int in ChipTowers.SEGMENTS:
		if rho >= ChipTowers.ring_inner(seg) - 0.05 and rho <= ChipTowers.ring_outer(seg) + 0.05:
			return seg
	return -1


## Steers for one step; true if it should jump on it.
func plan() -> bool:
	var p: Vector3 = local()
	var seg: int = ring_of(p)
	var g: Dictionary = ChipTowers.guide(p, bold[seg] if seg >= 0 else false)
	var to: Vector3 = g["to"]
	var flat := Vector3(to.x - p.x, 0.0, to.z - p.z)
	if flat.length() > 0.1:
		var f: Vector3 = flat.normalized()
		bean.yaw = atan2(-f.x, -f.z)
		router.move = Vector2(0.0, 1.0)
	else:
		router.move = Vector2.ZERO
	router.sprint = sprint
	# Stuck: barely moved for a while although it wants to.
	if _still_at == Vector3.INF or bean.global_position.distance_to(_still_at) > STUCK_MOVE:
		_still_at = bean.global_position
		_still_t = 0.0
	else:
		_still_t += DT
	var stuck: bool = _still_t > STUCK_SECONDS and router.move != Vector2.ZERO
	var jump: bool = jumps_allowed and bean.is_on_floor() and (bool(g["hop"]) or stuck)
	if jump and stuck and not bool(g["hop"]):
		stuck_jumps += 1
		_still_t = 0.0
	if jump:
		var on: Dictionary = ChipTowers.lane_under(p)
		jump_log.append("%.1fs lane %s %s%s" % [clock, str(on.get("lane", -1)), str(snappedf(float(on.get("theta", 0.0)), 0.01)), " stuck" if not bool(g["hop"]) else ""])
	return jump


## Moves one 60 Hz step (pressing jump on it if `jump`), then lets the server look.
func move(jump: bool) -> void:
	if jump:
		Input.action_press(&"jump")
	bean._physics_process(DT)
	if jump:
		Input.action_release(&"jump")
		jumps += 1
	clock += DT
	logic.world.set_transform(PLAYER, bean.global_position, bean.yaw)
	logic.tick(DT, 0.0)
	logic.drain_events()
	if logic.pending_moves.has(PLAYER):
		bean.teleport(logic.pending_moves[PLAYER])
		logic.pending_moves.erase(PLAYER)
		respawns += 1


## Runs until `done` (Callable on this runner → bool) or `cap` seconds; true if done. A coroutine:
## the steps run inside a physics frame (so `move_and_slide` moves by the 60 Hz physics step),
## except a jump: `Input` only reports a press as fresh outside a physics frame, so that one step
## waits for a process frame (its slide then covers that frame's time), and the steps go on two
## physics frames later (the press still reads as fresh in the first physics frame after it).
func run_until(done: Callable, cap: float) -> bool:
	var tree: SceneTree = bean.get_tree()
	await tree.physics_frame
	await tree.physics_frame
	while clock < cap:
		if plan():
			await tree.process_frame
			move(true)
			await tree.physics_frame
			await tree.physics_frame
		else:
			move(false)
		if done.call(self):
			return true
	return false


## True once the bean stands on the pad (the server finished it).
func finished() -> bool:
	return logic.is_up(PLAYER)
