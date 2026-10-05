class_name PlayerAvatar
extends CharacterBody3D
## One player's body in the casino: a wobbly bean on a CharacterBody3D (§2.4). The local
## avatar reads the InputRouter and reports `move` intents at the server tick rate; remote
## avatars ease toward the position the server last told us. Ragdoll, held and seated states
## swap the body out for a RagdollBody / attach it to a holder / park it on a seat.
##
## Money, knockouts and hits are decided by the server; this node only moves and animates.

signal landed(fall_height: float)
signal ragdoll_impact(strength: float, wall: bool)
signal ragdoll_settled

enum State { STANDING, SEATED, HELD, RAGDOLL, STUNNED, AWAY }
## Who moves this body: local input, local simulation (test dummies, Practice), or a network stream.
enum Drive { INPUT, SIM, PUPPET }

const LAYER_PLAYERS: int = 2
const MASK: int = 1 | 2 | 8
const MOVE_SEND_INTERVAL: float = 1.0 / 20.0
const GRAVITY: float = 18.0
const REMOTE_LERP: float = 10.0
const PUPPET_LERP: float = 18.0
const HELD_OFFSET: Vector3 = Vector3(0.0, 1.0, -0.9)
## Height of a carried bean's feet line above the guard's feet (lying across the guard's head).
const CARRIED_HEIGHT: float = 1.62

var player_id: int = -1
var display_name: String = "Player"
var color: Color = Palette.CREAM
var skin: StringName = &"bean"
var is_local: bool = false
var state: State = State.STANDING
var drive: Drive = Drive.SIM
## PUPPET: the stream says we're in the air (for fall detection on the server).
var puppet_airborne: bool = false
## Disconnected (§2.12): stays where it was, "zzz", intangible.
var connection_away: bool = false
var cfg: BalanceConfig
## Walking/sprinting speed factor from items (Energy Drink).
var speed_multiplier: float = 1.0
var router: InputRouter
var visuals: AvatarVisuals
var cam: PlayerCamera
var nametag: Label3D
var bubble: Label3D
## Facing yaw in radians (the direction the bean looks).
var yaw: float = 0.0
## For remote avatars: where the server last placed us.
var target_position: Vector3 = Vector3.ZERO
var target_yaw: float = 0.0
## Extra horizontal velocity from shoves/door panels; decays on its own.
var push_velocity: Vector3 = Vector3.ZERO
## Horizontal push folded into `velocity` on the last INPUT frame.
var _applied_push: Vector3 = Vector3.ZERO
var stamina: float = 4.0
var soaked_until: float = -INF
var stunned_until: float = -INF
var ragdoll: RagdollBody = null
var holder: PlayerAvatar = null
## A guard carrying us out over their head (HELD state; see `set_carried`).
var carrier: Node3D = null
var seat: Node3D = null
## Last player that hurt us (for fountain/fall credit).
var last_attacker: int = -1
## Scripted drive target for autoplay: when set, walks there instead of reading input.
var auto_target: Vector3 = Vector3.INF

var _send_timer: float = 0.0
var _fall_start_y: float = INF
var _was_on_floor: bool = true
var _step_timer: float = 0.0
var _bubble_until: float = -INF
var _collision: CollisionShape3D
var _clock: float = 0.0


func _ready() -> void:
	collision_layer = LAYER_PLAYERS
	collision_mask = MASK
	floor_snap_length = 0.3
	wall_min_slide_angle = 0.0  # always slide along posts/tables instead of sticking
	add_to_group(&"players")
	set_meta(&"player_id", player_id)
	if is_local:
		drive = Drive.INPUT
	if cfg == null:
		cfg = BalanceConfig.new()
	stamina = cfg.sprint_stamina
	_collision = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.42
	cap.height = 1.7
	_collision.shape = cap
	_collision.position.y = 0.85
	add_child(_collision)
	visuals = AvatarVisuals.new()
	visuals.name = "Visuals"
	add_child(visuals)
	visuals.set_color(color)
	visuals.set_skin(skin)
	nametag = Label3D.new()
	nametag.name = "Nametag"
	nametag.text = display_name
	nametag.font_size = 48
	nametag.pixel_size = 0.004
	nametag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	nametag.modulate = Palette.CREAM
	nametag.outline_modulate = Palette.CASINO_BLACK
	nametag.outline_size = 10
	nametag.position.y = 2.15
	# Up close the tag would fill the screen: fade it out under ~2.5 m (you can see who it is).
	nametag.visibility_range_begin = 2.5
	nametag.visibility_range_begin_margin = 0.8
	nametag.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	nametag.visible = not is_local
	add_child(nametag)
	bubble = Label3D.new()
	bubble.name = "Bubble"
	bubble.font_size = 64
	bubble.pixel_size = 0.005
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.modulate = Palette.VIP_GOLD
	bubble.outline_modulate = Palette.CASINO_BLACK
	bubble.outline_size = 12
	bubble.position.y = 2.5
	bubble.visible = false
	add_child(bubble)
	if is_local:
		cam = PlayerCamera.new()
		cam.name = "PlayerCamera"
		add_child(cam)
		cam.yaw = yaw
	target_position = global_position
	target_yaw = yaw


## Puts on a character skin (`Cosmetics.SKINS`).
func set_skin(id: StringName) -> void:
	skin = id
	if visuals != null:
		visuals.set_skin(id)


## Sets the player colour on the bean.
func set_color(c: Color) -> void:
	color = c
	if visuals != null:
		visuals.set_color(c)


## Horizontal facing (camera yaw for the local player).
func facing() -> Vector3:
	if cam != null and state != State.SEATED:
		return cam.forward()
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


## Aim direction for throws (camera aim for the local player).
func aim() -> Vector3:
	if cam != null:
		return cam.aim()
	return facing()


func is_standing() -> bool:
	return state == State.STANDING or state == State.STUNNED


func is_soaked() -> bool:
	return _clock < soaked_until


## Applies a knockback impulse (shove, door panel). Puppets only flinch: their owner moves them.
func knockback(dir: Vector3, strength: float) -> void:
	var d: Vector3 = Vector3(dir.x, 0.0, dir.z)
	if d.length() < 0.01:
		return
	if drive == Drive.PUPPET:
		if visuals != null:
			visuals.react(&"loss")
		return
	push_velocity += d.normalized() * strength
	velocity.y = maxf(velocity.y, strength * 0.3)
	if visuals != null:
		visuals.react(&"loss")


## One-off impulse: vertical goes straight into the body, horizontal into the push buffer.
func hop(impulse: Vector3) -> void:
	if drive == Drive.PUPPET:
		return
	velocity.y = maxf(velocity.y, impulse.y)
	push_velocity += Vector3(impulse.x, 0.0, impulse.z)


## Brief stumble: no input for `seconds`.
func stun(seconds: float) -> void:
	if state == State.STANDING:
		state = State.STUNNED
	stunned_until = _clock + seconds


## Gets wet: slow for the configured duration.
func soak() -> void:
	soaked_until = _clock + cfg.soaked_seconds


## Shows a short speech bubble (emotes, "OW").
func say(text: String, seconds: float = 2.0) -> void:
	bubble.text = text
	bubble.visible = true
	_bubble_until = _clock + seconds


## Swaps the body for a ragdoll launched with `velocity`. Returns the ragdoll (parented to our parent).
## `puppet`: the server simulates the body and streams its pose (online clients).
func start_ragdoll(velocity: Vector3, max_time: float = 2.5, puppet: bool = false) -> RagdollBody:
	if state == State.RAGDOLL and ragdoll != null:
		ragdoll.launch(velocity)
		return ragdoll
	_detach_from_holder()
	if state == State.SEATED:
		_leave_seat()
	state = State.RAGDOLL
	ragdoll = RagdollBody.new()
	ragdoll.name = "Ragdoll%d" % player_id
	ragdoll.color = color
	ragdoll.skin = skin
	ragdoll.player_id = player_id
	ragdoll.max_time = max_time
	ragdoll.puppet = puppet
	ragdoll.position = global_position
	ragdoll.rotation.y = yaw
	get_parent().add_child(ragdoll)
	ragdoll.launch(velocity)
	ragdoll.impact.connect(func(s: float, w: bool) -> void: ragdoll_impact.emit(s, w))
	ragdoll.settled.connect(_on_ragdoll_settled)
	visuals.set_ragdoll(ragdoll)
	nametag.visible = false
	_collision.disabled = true
	velocity = Vector3.ZERO
	push_velocity = Vector3.ZERO
	_applied_push = Vector3.ZERO
	if cam != null:
		cam.follow = ragdoll.torso
	return ragdoll


## Gets up where the ragdoll came to rest (or at `at` if given).
func end_ragdoll(at: Vector3 = Vector3.INF) -> void:
	var pos: Vector3 = at
	if ragdoll != null:
		if pos == Vector3.INF:
			pos = ragdoll.body_position()
		visuals.set_ragdoll(null)
		visuals.get_up(ragdoll.torso.global_basis.y)
		ragdoll.queue_free()
		ragdoll = null
	if pos == Vector3.INF:
		pos = global_position
	pos.y = maxf(pos.y - 0.5, 0.0)
	global_position = pos
	target_position = pos
	velocity = Vector3.ZERO
	push_velocity = Vector3.ZERO
	_applied_push = Vector3.ZERO
	_collision.disabled = false
	visuals.visible = true
	nametag.visible = not is_local
	visuals.set_knocked_out(false)
	visuals.react(&"wake")
	state = State.STANDING
	if cam != null:
		cam.follow = null


## Picked up by `by`: we dangle in front of them until released.
func set_held(by: PlayerAvatar) -> void:
	if state == State.SEATED:
		_leave_seat()
	holder = by
	state = State.HELD
	_collision.disabled = true
	velocity = Vector3.ZERO
	visuals.react(&"loss")


## Carried out by a guard (`by`): we lie across their head, flailing, until they toss us.
func set_carried(by: Node3D) -> void:
	if state == State.SEATED:
		_leave_seat()
	holder = null
	carrier = by
	state = State.HELD
	_collision.disabled = true
	velocity = Vector3.ZERO
	push_velocity = Vector3.ZERO
	_applied_push = Vector3.ZERO
	visuals.set_carried(true)


## Dropped (not thrown): back on our feet where we are.
func release_held() -> void:
	if state != State.HELD:
		return
	holder = null
	if carrier != null:
		carrier = null
		visuals.set_carried(false)
	_collision.disabled = false
	var p: Vector3 = global_position
	p.y = maxf(p.y, 0.0)
	global_position = p
	target_position = p
	state = State.STANDING


## Parks the bean on a seat facing the table; the camera eases to `anchor`.
func sit(p_seat: Node3D, anchor: Node3D) -> void:
	seat = p_seat
	state = State.SEATED
	visuals.sitting = true
	velocity = Vector3.ZERO
	push_velocity = Vector3.ZERO
	_applied_push = Vector3.ZERO
	global_position = p_seat.global_position
	yaw = p_seat.global_rotation.y
	rotation.y = yaw
	target_position = global_position
	if cam != null:
		cam.set_anchor(anchor)
	if router != null:
		router.set_mode(InputRouter.Mode.SEATED)


## Stands up next to the seat.
func stand() -> void:
	if state != State.SEATED:
		return
	_leave_seat()
	state = State.STANDING


## Teleports (respawn, server correction).
func teleport(pos: Vector3, p_yaw: float = NAN) -> void:
	global_position = pos
	target_position = pos
	velocity = Vector3.ZERO
	push_velocity = Vector3.ZERO
	_applied_push = Vector3.ZERO
	if not is_nan(p_yaw):
		yaw = p_yaw
		target_yaw = p_yaw
		rotation.y = p_yaw
		if cam != null:
			cam.yaw = p_yaw


## Disconnected players (§2.12): a "zzz" statue nobody can grab or shove.
func set_connection_away(away: bool) -> void:
	connection_away = away
	if away:
		bubble.text = "zzz"
		bubble.visible = true
		_bubble_until = INF
		_collision.disabled = true
		visuals.set_ghost(true)
	else:
		bubble.visible = false
		_bubble_until = -INF
		_collision.disabled = state == State.RAGDOLL or state == State.HELD or state == State.AWAY
		visuals.set_ghost(false)


## Hides the player while they're outside (thrown out).
func set_away(away: bool) -> void:
	if carrier != null:
		carrier = null
		visuals.set_carried(false)
	if away:
		if ragdoll != null:
			end_ragdoll(global_position)
		state = State.AWAY
		visible = false
		_collision.disabled = true
	else:
		state = State.STANDING
		visible = true
		_collision.disabled = false
		nametag.visible = not is_local


func _physics_process(delta: float) -> void:
	_clock += delta
	if bubble.visible and _clock > _bubble_until:
		bubble.visible = false
	match state:
		State.RAGDOLL, State.AWAY:
			if ragdoll != null and is_instance_valid(ragdoll):
				global_position = ragdoll.body_position()
			if cam != null:
				cam.update_camera(0.0, true, true, delta)
			return
		State.HELD:
			_follow_holder(delta)
			return
		State.SEATED:
			visuals.update_motion(Vector3.ZERO, true, delta)
			if cam != null:
				cam.update_camera(0.0, true, false, delta)
			return
	if state == State.STUNNED and _clock >= stunned_until:
		state = State.STANDING
	match drive:
		Drive.INPUT:
			_local_move(delta)
			_track_fall()
		Drive.SIM:
			_remote_move(delta)
			_track_fall()
		Drive.PUPPET:
			_puppet_move(delta)
	visuals.update_motion(velocity, is_on_floor() if drive != Drive.PUPPET else not puppet_airborne, delta)
	_footsteps(delta)
	if cam != null:
		cam.update_camera(Vector3(velocity.x, 0, velocity.z).length(), is_on_floor(), false, delta)
		# First person: the bean would fill the view, so only show it in third person.
		visuals.visible = cam.mode == PlayerCamera.Mode.THIRD


func _local_move(delta: float) -> void:
	var input: Vector2 = Vector2.ZERO
	var sprint: bool = false
	if auto_target != Vector3.INF:
		var to: Vector3 = auto_target - global_position
		to.y = 0.0
		if to.length() > 0.3:
			# Face the target and walk forward: simpler than steering the camera.
			var f: Vector3 = to.normalized()
			yaw = atan2(-f.x, -f.z)
			if cam != null:
				cam.yaw = yaw
			input = Vector2(0.0, 1.0)
			sprint = to.length() > 6.0
		else:
			auto_target = Vector3.INF
	elif router != null:
		input = router.move_vector()
		sprint = router.sprint_held()
		var stick: Vector2 = router.stick_look() * delta
		if stick != Vector2.ZERO and cam != null:
			cam.look(stick.x, stick.y)
	if state == State.STUNNED:
		input = Vector2.ZERO
	if cam != null:
		yaw = cam.yaw
	var fwd: Vector3 = Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right: Vector3 = Vector3(cos(yaw), 0.0, -sin(yaw))
	var wish: Vector3 = (fwd * input.y + right * input.x)
	if wish.length() > 1.0:
		wish = wish.normalized()
	var speed: float = cfg.walk_speed
	if sprint and stamina > 0.0 and wish.length() > 0.1:
		speed = cfg.sprint_speed
		stamina = maxf(stamina - delta, 0.0)
	else:
		stamina = minf(stamina + cfg.stamina_regen_per_second * delta, cfg.sprint_stamina)
	speed *= speed_multiplier
	if is_soaked():
		speed *= cfg.soaked_speed_factor
	if holder == null and state == State.STANDING and _holding_someone():
		speed *= cfg.held_speed_factor
	# Last frame's push is part of `velocity`; take it out so it isn't added again (it compounded
	# into a 30 m/s slide whenever the local player was shoved).
	var horizontal: Vector3 = Vector3(velocity.x - _applied_push.x, 0.0, velocity.z - _applied_push.z)
	var target: Vector3 = wish * speed
	var rate: float = cfg.acceleration if wish.length() > 0.1 else cfg.deceleration
	horizontal = horizontal.move_toward(target, rate * delta)
	velocity.x = horizontal.x + push_velocity.x
	velocity.z = horizontal.z + push_velocity.z
	_applied_push = Vector3(push_velocity.x, 0.0, push_velocity.z)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = minf(velocity.y, 0.0)
		if router != null and state == State.STANDING and Input.is_action_just_pressed(&"jump") and router.mode == InputRouter.Mode.WALK:
			velocity.y = sqrt(2.0 * GRAVITY * cfg.jump_height)
			Audio.play(&"jump", &"SFX", -12.0, randf_range(0.95, 1.05))
	push_velocity = push_velocity.move_toward(Vector3.ZERO, 8.0 * delta)
	move_and_slide()
	rotation.y = yaw
	_send_timer += delta
	if _send_timer >= MOVE_SEND_INTERVAL:
		_send_timer = 0.0
		Net.send_intent(Intents.make(&"move", {"pos": Serializer.vec3(global_position), "yaw": snappedf(yaw, 0.001), "airborne": not is_on_floor()}))


func _remote_move(delta: float) -> void:
	var to: Vector3 = target_position - global_position
	var flat: Vector3 = Vector3(to.x, 0.0, to.z)
	if flat.length() > 4.0:
		global_position = target_position
		velocity = Vector3.ZERO
	else:
		var desired: Vector3 = flat * REMOTE_LERP
		velocity.x = desired.x + push_velocity.x
		velocity.z = desired.z + push_velocity.z
		if not is_on_floor():
			velocity.y -= GRAVITY * delta
		else:
			velocity.y = minf(velocity.y, 0.0)
		push_velocity = push_velocity.move_toward(Vector3.ZERO, 8.0 * delta)
		move_and_slide()
	yaw = lerp_angle(yaw, target_yaw, 10.0 * delta)
	rotation.y = yaw


func _puppet_move(delta: float) -> void:
	var prev: Vector3 = global_position
	if global_position.distance_to(target_position) > 3.0:
		global_position = target_position
	else:
		global_position = global_position.lerp(target_position, minf(1.0, PUPPET_LERP * delta))
	velocity = (global_position - prev) / maxf(delta, 0.0001)
	yaw = lerp_angle(yaw, target_yaw, minf(1.0, 15.0 * delta))
	rotation.y = yaw
	# Falls are detected from the stream's airborne flag (no floor contact on a puppet).
	if puppet_airborne:
		_fall_start_y = global_position.y if _was_on_floor else maxf(_fall_start_y, global_position.y)
	elif not _was_on_floor:
		var drop: float = _fall_start_y - global_position.y if _fall_start_y != INF else 0.0
		_fall_start_y = INF
		landed.emit(drop)
	_was_on_floor = not puppet_airborne


func _follow_holder(delta: float) -> void:
	if carrier != null:
		_follow_carrier(delta)
		return
	if holder == null or not is_instance_valid(holder):
		release_held()
		return
	var want: Vector3 = holder.global_position + Basis.from_euler(Vector3(0, holder.yaw, 0)) * HELD_OFFSET
	want.y += sin(_clock * 12.0) * 0.08
	global_position = global_position.lerp(want, 15.0 * delta)
	yaw = holder.yaw
	rotation.y = yaw + sin(_clock * 9.0) * 0.3
	visuals.update_motion(Vector3.ZERO, false, delta)
	if cam != null:
		cam.update_camera(0.0, false, false, delta)


## Lies across the guard's head, bouncing with their steps.
func _follow_carrier(delta: float) -> void:
	if not is_instance_valid(carrier):
		release_held()
		return
	var want: Vector3 = carrier.global_position + Vector3(0.0, CARRIED_HEIGHT + absf(sin(_clock * 9.0)) * 0.07, 0.0)
	global_position = global_position.lerp(want, minf(1.0, 12.0 * delta))
	yaw = carrier.global_rotation.y
	rotation.y = yaw
	visuals.update_motion(Vector3.ZERO, false, delta)
	if cam != null:
		cam.update_camera(0.0, false, false, delta)


func _track_fall() -> void:
	var on_floor: bool = is_on_floor()
	if _was_on_floor and not on_floor:
		_fall_start_y = global_position.y
	elif not _was_on_floor and on_floor:
		var drop: float = _fall_start_y - global_position.y if _fall_start_y != INF else 0.0
		_fall_start_y = INF
		landed.emit(drop)
		if drop > 0.6:
			Audio.play_at(&"thud", self, -10.0)
	elif not on_floor:
		_fall_start_y = maxf(_fall_start_y, global_position.y)
	_was_on_floor = on_floor


const FOOTSTEPS: Array[StringName] = [&"footstep"]  # recorded carpet steps, variants picked by Audio


func _footsteps(delta: float) -> void:
	var speed: float = Vector3(velocity.x, 0, velocity.z).length()
	if (is_on_floor() or (drive == Drive.PUPPET and not puppet_airborne)) and speed > 1.0:
		_step_timer += delta * speed
		if _step_timer > 2.6:
			_step_timer = 0.0
			# Soft carpet steps (recorded variants), gentle pitch spread, quieter for our own body
			# (it's right under the camera) and sprinting a touch louder.
			var clip: StringName = FOOTSTEPS[randi() % FOOTSTEPS.size()]
			var vol: float = (-26.0 if drive == Drive.INPUT else -22.0) + (2.0 if speed > 5.0 else 0.0)
			Audio.play_at(clip, self, vol, randf_range(0.92, 1.06))


func _holding_someone() -> bool:
	for p: Node in get_tree().get_nodes_in_group(&"players"):
		if p is PlayerAvatar and (p as PlayerAvatar).holder == self:
			return true
	return false


func _detach_from_holder() -> void:
	if carrier != null:
		carrier = null
		visuals.set_carried(false)
	if holder != null:
		holder = null
		_collision.disabled = false


func _leave_seat() -> void:
	if seat != null:
		var out: Vector3 = seat.global_position + seat.global_transform.basis.z * 0.9
		out.y = 0.0
		global_position = out
		target_position = out
	seat = null
	visuals.sitting = false
	if cam != null:
		cam.set_anchor(null)
	if router != null:
		router.set_mode(InputRouter.Mode.WALK)


func _on_ragdoll_settled() -> void:
	ragdoll_settled.emit()
