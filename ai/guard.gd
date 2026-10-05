class_name Guard
extends CharacterBody3D
## Casino security (§2.4.1): a dark bean with a gold cap patrolling a route; when it sees an
## offence (knockout, shake, throw) within range and sight cone it chases the attacker and, on
## reaching them, the match scene throws that player out. Sight uses InteractionRules.guard_sees
## and the map's raycast; chasing uses the navmesh.
##
## Throw-outs (M7): the guard named in `player_thrown_out` lifts the player over its head, carries
## them toward the door for a moment and tosses them out as a ragdoll. Where the scene owns the
## simulation (server, Practice) the guard does the toss itself; online clients show the same carry
## on the streamed guard and hand the body to the server's streamed ragdoll once the guard's state
## leaves CARRY. Money and the respawn clock are untouched: they stay with the server's event.

signal caught(player_id: int)

enum State { PATROL, CHASE, RETURN, CARRY }

const LAYER: int = 16
const PATROL_SPEED: float = 3.0
const CHASE_SPEED: float = 6.5
const CATCH_RANGE: float = 1.6
const GIVE_UP_SECONDS: float = 12.0
const LOSE_SIGHT_SECONDS: float = 4.0
## Carry-and-toss: how long the guard walks with the player overhead (the respawn clock keeps
## running: carry + ragdoll flight stays under `throw_out_respawn_seconds`), how close it has to be
## to pick someone up, and the toss.
const CARRY_SECONDS: float = 1.8
const CARRY_SPEED: float = 4.2
const CARRY_REACH: float = 4.0
const TOSS_SPEED: float = 7.5
const TOSS_UP: float = 4.5
const TOSS_RAGDOLL_SECONDS: float = 1.6
## Where the guard's hands go while carrying (local to its visuals).
const CARRY_HANDS: Vector3 = Vector3(0.0, 2.2, -0.25)

var guard_id: StringName = &"guard"
var route: Array[Vector3] = []
var state: State = State.PATROL
var target_id: int = -1
var visuals: AvatarVisuals
var agent: NavigationAgent3D
var yaw: float = 0.0

var _route_index: int = 0
var _chase_time: float = 0.0
var _since_seen: float = 0.0
var _target_pos: Vector3 = Vector3.ZERO
var _wait: float = 0.0
## Online clients: the server runs the guard; we follow its streamed position.
var puppet: bool = false
var _net_pos: Vector3 = Vector3.INF
var _net_yaw: float = 0.0
## The player being carried out (null when not carrying).
var carrying: PlayerAvatar = null
var _carry_time: float = 0.0
var _carry_door: Vector3 = Vector3.ZERO
var _net_carry_seen: bool = false


func _ready() -> void:
	collision_layer = LAYER
	collision_mask = 1
	add_to_group(&"guards")
	visuals = AvatarVisuals.new()
	visuals.name = "Visuals"
	add_child(visuals)
	visuals.set_color(Palette.WARM_CHARCOAL)
	var cap: Node3D = GreyboxKit.cylinder(visuals.hat_slot, 0.3, 0.12, Vector3(0, 0.05, 0), Palette.CASINO_BLACK, "Cap", false)
	GreyboxKit.box(cap, Vector3(0.5, 0.04, 0.3), Vector3(0, -0.02, -0.25), Palette.CASINO_BLACK, "Peak", false)
	GreyboxKit.box(cap, Vector3(0.18, 0.06, 0.02), Vector3(0, 0.03, -0.3), Palette.WARM_GOLD, "Badge", false)
	var shape := CollisionShape3D.new()
	var cs := CapsuleShape3D.new()
	cs.radius = 0.42
	cs.height = 1.7
	shape.shape = cs
	shape.position.y = 0.85
	add_child(shape)
	agent = NavigationAgent3D.new()
	agent.path_desired_distance = 0.6
	agent.target_desired_distance = 0.8
	agent.radius = 0.5
	agent.height = 2.0
	add_child(agent)
	if not route.is_empty():
		global_position = route[0]
		_route_index = 1 % route.size()


## Forward direction on the ground.
func forward() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


## Starts chasing a player seen at `pos`.
func chase(player_id: int, pos: Vector3) -> void:
	if carrying != null:
		return  # hands full
	if state == State.CHASE and target_id == player_id:
		_target_pos = pos
		_since_seen = 0.0
		return
	state = State.CHASE
	target_id = player_id
	_target_pos = pos
	_chase_time = 0.0
	_since_seen = 0.0
	visuals.react(&"win")
	Audio.play_at(&"whistle", self, -6.0)


## Updates the chased player's position if the guard still sees them.
func update_target(pos: Vector3, seen: bool) -> void:
	if seen:
		_target_pos = pos
		_since_seen = 0.0


func stop_chase() -> void:
	state = State.RETURN
	target_id = -1


## Lifts `a` overhead and heads for `door`. False (and nothing happens) when the player can't be
## carried right now (already flying, held, away) or is out of reach; the caller tosses them the
## old way then.
func carry(a: PlayerAvatar, door: Vector3) -> bool:
	if a == null or carrying != null:
		return false
	if not (a.state == PlayerAvatar.State.STANDING or a.state == PlayerAvatar.State.STUNNED):
		return false
	if Vector2(a.global_position.x - global_position.x, a.global_position.z - global_position.z).length() > CARRY_REACH:
		return false
	carrying = a
	_carry_time = 0.0
	_carry_door = door
	_net_carry_seen = false
	target_id = -1
	if not puppet:
		state = State.CARRY
	a.set_carried(self)
	visuals.reaching = true
	visuals.reach_target = CARRY_HANDS
	a.say("HEY!", 1.2)
	return true


func _end_carry() -> void:
	carrying = null
	visuals.reaching = false


## Owner side: throws the carried player toward the door as a ragdoll.
func _toss() -> void:
	var a: PlayerAvatar = carrying
	_end_carry()
	state = State.RETURN
	if a == null or not is_instance_valid(a) or a.carrier != self:
		return
	var dir: Vector3 = _carry_door - global_position
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else forward()
	a.start_ragdoll(dir * TOSS_SPEED + Vector3.UP * TOSS_UP, TOSS_RAGDOLL_SECONDS, false)
	visuals.react(&"win")
	Audio.play_at(&"whoosh", a, -6.0)


## Puppet side: the server tossed them; the streamed ragdoll takes the body from here.
func _release_puppet() -> void:
	var a: PlayerAvatar = carrying
	_end_carry()
	if a == null or not is_instance_valid(a) or a.carrier != self:
		return
	a.start_ragdoll(Vector3.ZERO, 60.0, true)
	visuals.react(&"win")
	Audio.play_at(&"whoosh", a, -6.0)


## Puppet: the server's latest position/yaw/state.
func apply_net(pos: Vector3, p_yaw: float, p_state: int) -> void:
	if _net_pos == Vector3.INF:
		global_position = pos
	_net_pos = pos
	_net_yaw = p_yaw
	if p_state == State.CHASE and state != State.CHASE:
		visuals.react(&"win")
		Audio.play_at(&"whistle", self, -6.0)
	state = p_state as State
	if carrying != null:
		if p_state == State.CARRY:
			_net_carry_seen = true
		elif _net_carry_seen:
			_release_puppet()


func _physics_process(delta: float) -> void:
	if puppet:
		if carrying != null:
			_carry_time += delta
			if _carry_time > CARRY_SECONDS + 1.0:
				_release_puppet()  # never saw the carry in the stream; don't hold on forever
		if _net_pos != Vector3.INF:
			var prev: Vector3 = global_position
			global_position = global_position.lerp(_net_pos, minf(1.0, 15.0 * delta))
			yaw = lerp_angle(yaw, _net_yaw, minf(1.0, 12.0 * delta))
			rotation.y = yaw
			visuals.update_motion((global_position - prev) / maxf(delta, 0.0001), true, delta)
		return
	var speed: float = PATROL_SPEED
	var goal: Vector3
	match state:
		State.PATROL:
			if route.is_empty():
				return
			_route_index = _route_index % route.size()
			goal = route[_route_index]
			if global_position.distance_to(goal) < 0.9:
				_wait -= delta
				if _wait <= 0.0:
					_route_index = (_route_index + 1) % route.size()
					_wait = 1.5
				_move_toward(Vector3.ZERO, delta)
				visuals.update_motion(velocity, true, delta)
				return
		State.CHASE:
			_chase_time += delta
			_since_seen += delta
			if _chase_time > GIVE_UP_SECONDS or _since_seen > LOSE_SIGHT_SECONDS:
				stop_chase()
				return
			goal = _target_pos
			speed = CHASE_SPEED
			if Vector3(global_position.x - goal.x, 0, global_position.z - goal.z).length() < CATCH_RANGE:
				var pid: int = target_id
				stop_chase()
				caught.emit(pid)
				return
		State.CARRY:
			_carry_time += delta
			if carrying == null or not is_instance_valid(carrying) or carrying.carrier != self:
				_end_carry()
				state = State.RETURN
				return
			goal = _carry_door
			speed = CARRY_SPEED
			if _carry_time >= CARRY_SECONDS or Vector2(goal.x - global_position.x, goal.z - global_position.z).length() < 2.5:
				_toss()
				return
		State.RETURN:
			goal = route[_route_index % route.size()] if not route.is_empty() else global_position
			if global_position.distance_to(goal) < 1.0:
				state = State.PATROL
	agent.target_position = goal
	var next: Vector3 = agent.get_next_path_position()
	var dir: Vector3 = next - global_position
	dir.y = 0.0
	if dir.length() > 0.05:
		dir = dir.normalized()
		yaw = lerp_angle(yaw, atan2(-dir.x, -dir.z), 10.0 * delta)
	_move_toward(dir * speed, delta)
	rotation.y = yaw
	visuals.update_motion(velocity, is_on_floor(), delta)


func _move_toward(target_velocity: Vector3, delta: float) -> void:
	var h: Vector3 = Vector3(velocity.x, 0, velocity.z).move_toward(target_velocity, 20.0 * delta)
	velocity.x = h.x
	velocity.z = h.z
	velocity.y = -2.0 if not is_on_floor() else 0.0
	move_and_slide()
