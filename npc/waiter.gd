class_name Waiter
extends CharacterBody3D
## The waiter NPC (M7): a cream-jacketed bean with a bow tie carrying a tray of drinks around the
## casino floor on the navmesh (like `Guard`). Where he trips is decided by the server
## (`WaiterLogic`); this body only walks, reports its position there and plays the fall. On
## online clients it is a puppet that follows the world stream.

## World-stream state codes (sent in the guards list, after the guards: see `NetWorld`).
const NET_STATE: int = 10
const LAYER: int = 16
const SPEED: float = 2.1
const ARRIVE: float = 0.9
const PAUSE_SECONDS: float = 1.2
## Gives up on a waypoint after this long without getting any closer.
const STUCK_SECONDS: float = 4.0
## Tray held up on the right hand, above the shoulder (the classic waiter carry).
const TRAY_POS: Vector3 = Vector3(0.46, 1.5, -0.62)
const TRAY_ARM: float = 0.6
## Drinks on the tray (art direction palette: wine, champagne, lime).
const DRINKS: Array[Color] = [Color("#681F2C"), Color("#E3B95C"), Color("#68C26F")]

var route: Array[Vector3] = []
var yaw: float = 0.0
var visuals: AvatarVisuals = null
var agent: NavigationAgent3D
var tray: Node3D = null
## Online clients: follow the server's stream instead of walking.
var puppet: bool = false
## On the floor after a trip (set by whoever owns the server, or by the stream).
var down: bool = false

var _route_index: int = 0
var _wait: float = 0.0
var _stuck: float = 0.0
var _best_d: float = INF
var _net_pos: Vector3 = Vector3.INF
var _net_yaw: float = 0.0
var _headless: bool = false
var _fall: Tween = null


func _ready() -> void:
	collision_layer = LAYER
	collision_mask = 1
	add_to_group(&"npcs")
	_headless = DisplayServer.get_name() == "headless"
	if not _headless:
		_build_visuals()
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


func forward() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


## The fall: face-first onto the carpet, the tray and glasses flying ahead. Idempotent.
func trip() -> void:
	if down:
		return
	down = true
	velocity = Vector3.ZERO
	if visuals == null:
		return
	visuals.react(&"ko")
	if _fall != null and _fall.is_valid():
		_fall.kill()
	_fall = create_tween().set_parallel(true)
	_fall.tween_property(visuals, ^"rotation:x", -1.35, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	_fall.tween_property(visuals, ^"position:y", 0.35, 0.35)
	if tray != null:
		var t: Tween = tray.create_tween()
		t.tween_property(tray, ^"position", TRAY_POS + Vector3(-0.3, 0.4, -0.9), 0.22).set_ease(Tween.EASE_OUT)
		t.tween_property(tray, ^"position", Vector3(0.0, 0.05, -1.4), 0.25).set_ease(Tween.EASE_IN)
		t.parallel().tween_property(tray, ^"rotation", Vector3(2.6, 0.7, 0.4), 0.47)
		for i: int in tray.get_child_count():
			var g: Node3D = tray.get_child(i) as Node3D
			if g != null and g.name.begins_with("Glass"):
				var tg: Tween = g.create_tween()
				tg.tween_property(g, ^"position", g.position + Vector3((i - 2) * 0.35, 0.6, -0.4), 0.3).set_ease(Tween.EASE_OUT)
				tg.tween_property(g, ^"scale", Vector3.ONE * 0.01, 0.2)


## Back on his feet with a fresh tray.
func get_up() -> void:
	if not down:
		return
	down = false
	if visuals == null:
		return
	visuals.react(&"wake")
	if _fall != null and _fall.is_valid():
		_fall.kill()
	_fall = create_tween().set_parallel(true)
	_fall.tween_property(visuals, ^"rotation:x", 0.0, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_fall.tween_property(visuals, ^"position:y", 0.0, 0.4)
	_fall.chain().tween_callback(_new_tray)


## Puppet: the server's latest position/yaw/down state.
func apply_net(pos: Vector3, p_yaw: float, p_down: bool) -> void:
	if _net_pos == Vector3.INF:
		global_position = pos
	_net_pos = pos
	_net_yaw = p_yaw
	if p_down:
		trip()
	else:
		get_up()


func _physics_process(delta: float) -> void:
	if puppet:
		if _net_pos != Vector3.INF:
			var prev: Vector3 = global_position
			global_position = global_position.lerp(_net_pos, minf(1.0, 12.0 * delta))
			yaw = lerp_angle(yaw, _net_yaw, minf(1.0, 10.0 * delta))
			rotation.y = yaw
			_animate((global_position - prev) / maxf(delta, 0.0001), delta)
		return
	if down or route.is_empty():
		_move_toward(Vector3.ZERO, delta)
		_animate(velocity, delta)
		return
	_route_index = _route_index % route.size()
	var goal: Vector3 = route[_route_index]
	var d: float = Vector2(global_position.x - goal.x, global_position.z - goal.z).length()
	_stuck += delta
	if d < _best_d - 0.3:
		_best_d = d
		_stuck = 0.0
	if d < ARRIVE or _stuck > STUCK_SECONDS:
		_wait -= delta
		_move_toward(Vector3.ZERO, delta)
		_animate(velocity, delta)
		if _wait <= 0.0:
			_route_index = (_route_index + 1) % route.size()
			_wait = PAUSE_SECONDS
			_stuck = 0.0
			_best_d = INF
		return
	agent.target_position = goal
	var next: Vector3 = agent.get_next_path_position()
	var dir: Vector3 = next - global_position
	dir.y = 0.0
	if dir.length() > 0.05:
		dir = dir.normalized()
		yaw = lerp_angle(yaw, atan2(-dir.x, -dir.z), 6.0 * delta)
	_move_toward(dir * SPEED, delta)
	rotation.y = yaw
	_animate(velocity, delta)


func _move_toward(target_velocity: Vector3, delta: float) -> void:
	var h: Vector3 = Vector3(velocity.x, 0, velocity.z).move_toward(target_velocity, 12.0 * delta)
	velocity.x = h.x
	velocity.z = h.z
	velocity.y = -2.0 if not is_on_floor() else 0.0
	move_and_slide()


func _animate(v: Vector3, delta: float) -> void:
	if visuals != null and not down:
		visuals.update_motion(v, true, delta)
		visuals.arm_r.rotation.x = TRAY_ARM


func _build_visuals() -> void:
	visuals = AvatarVisuals.new()
	visuals.name = "Visuals"
	add_child(visuals)
	visuals.set_color(Palette.CREAM)
	# Bow tie and a burgundy waistcoat stripe.
	GreyboxKit.box(visuals.body, Vector3(0.3, 0.22, 0.05), Vector3(0, -0.4, -0.4), Palette.VIP_BURGUNDY, "Waistcoat", false)
	GreyboxKit.box(visuals.body, Vector3(0.11, 0.08, 0.05), Vector3(-0.065, -0.2, -0.43), Palette.CASINO_BLACK, "BowL", false)
	GreyboxKit.box(visuals.body, Vector3(0.11, 0.08, 0.05), Vector3(0.065, -0.2, -0.43), Palette.CASINO_BLACK, "BowR", false)
	_new_tray()


## A gold tray with three drinks, carried in both hands.
func _new_tray() -> void:
	if visuals == null:
		return
	if tray != null:
		tray.queue_free()
	tray = Node3D.new()
	tray.name = "Tray"
	tray.position = TRAY_POS
	add_child(tray)
	var plate := MeshInstance3D.new()
	plate.name = "Plate"
	var pm := CylinderMesh.new()
	pm.top_radius = 0.32
	pm.bottom_radius = 0.3
	pm.height = 0.03
	pm.radial_segments = 20
	plate.mesh = pm
	plate.material_override = GreyboxKit.gold()
	tray.add_child(plate)
	for i: int in DRINKS.size():
		var glass := MeshInstance3D.new()
		glass.name = "Glass%d" % i
		var gm := CylinderMesh.new()
		gm.top_radius = 0.055
		gm.bottom_radius = 0.04
		gm.height = 0.17
		gm.radial_segments = 10
		glass.mesh = gm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = DRINKS[i]
		mat.roughness = 0.15
		mat.metallic_specular = 0.9
		glass.material_override = mat
		var a: float = i * TAU / 3.0 + 0.4
		glass.position = Vector3(cos(a) * 0.17, 0.1, sin(a) * 0.17)
		tray.add_child(glass)
	tray.scale = Vector3.ONE * 0.01
	tray.create_tween().tween_property(tray, ^"scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
