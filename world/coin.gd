class_name Coin
extends Node3D
## A single shiny gold coin on the floor. Coins burst out when dropped, spin, and can be collected
## by walking through them. Server controls amounts; this is purely visual/physics.

const COIN_RADIUS: float = 0.04  # Coin radius for mesh
const COIN_THICKNESS: float = 0.008  # Thin coin
const SPIN_SPEED: float = 8.0  # Rotation speed rad/s

## Physics: burst momentum and settling
var burst_velocity: Vector3 = Vector3.ZERO
var angular_velocity: Vector3 = Vector3.ZERO
var gravity: float = 9.8
var bounce: float = 0.6  # Energy retained after bounce
var friction: float = 0.98  # Velocity decay per frame
var _collected: bool = false
var _tween: Tween
var _mesh_instance: MeshInstance3D


func _ready() -> void:
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "CoinMesh"
	add_child(_mesh_instance)

	# Create a golden coin using a cylinder mesh
	var coin_mesh := CylinderMesh.new()
	coin_mesh.top_radius = COIN_RADIUS
	coin_mesh.bottom_radius = COIN_RADIUS
	coin_mesh.height = COIN_THICKNESS
	coin_mesh.radial_segments = 16
	coin_mesh.rings = 1
	_mesh_instance.mesh = coin_mesh

	# Shiny gold material
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#FFD700")  # Gold
	material.metallic = 0.8
	material.roughness = 0.2
	material.emission = Color("#CCAA00")
	material.emission_energy_multiplier = 0.3
	_mesh_instance.material_override = material

	# No shadow casting for coins
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _physics_process(delta: float) -> void:
	if _collected:
		return

	# Apply gravity
	burst_velocity.y -= gravity * delta

	# Apply velocity
	position += burst_velocity * delta

	# Apply friction
	burst_velocity *= friction

	# Apply angular velocity (spinning)
	rotation += angular_velocity * delta
	angular_velocity *= friction

	# Ground collision: bounce and dampen (check world position)
	if global_position.y <= 0.01:
		# Adjust local position so we rest on the ground
		var floor_y: float = -global_position.y
		position.y += floor_y
		if burst_velocity.y < -0.5:
			burst_velocity.y *= -bounce
		else:
			burst_velocity.y = 0.0
		burst_velocity.x *= 0.95
		burst_velocity.z *= 0.95


## Called when coin is dropped to initialize burst physics
func burst(initial_velocity: Vector3, spin: Vector3) -> void:
	burst_velocity = initial_velocity
	angular_velocity = spin
	position.y = maxf(position.y, 0.01)


## Collect coin: fly to the player
func fly_to(who: Node3D, keep: bool = false) -> void:
	if _collected:
		return
	_collected = true

	if not Vfx.enabled() or who == null or not is_instance_valid(who) or not who.is_inside_tree():
		if keep:
			visible = false
		else:
			queue_free()
		return

	visible = true
	var start: Vector3 = global_position
	var t: Tween = create_tween()
	_tween = t
	const FLY_SECONDS: float = 0.28
	t.tween_method(func(k: float) -> void:
		if not is_instance_valid(who) or not who.is_inside_tree():
			return
		var end: Vector3 = who.global_position + Vector3(0.0, 1.0, 0.0)
		var p: Vector3 = start.lerp(end, k * k)
		p.y += sin(k * PI) * 0.5
		global_position = p
		scale = Vector3.ONE * lerpf(1.0, 0.35, k)
	, 0.0, 1.0, FLY_SECONDS)

	if keep:
		t.tween_callback(func() -> void: visible = false)
	else:
		t.tween_callback(queue_free)


## Restore a predicted pickup that was denied
func restore() -> void:
	_kill_tween()
	_collected = false
	visible = true
	scale = Vector3.ONE


## Fade out coin (expired)
func fade_out() -> void:
	if _collected:
		return
	_collected = true
	if not Vfx.enabled():
		queue_free()
		return
	_kill_tween()
	var t: Tween = create_tween()
	_tween = t
	t.tween_property(self, "scale", Vector3(1.4, 0.05, 1.4), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.tween_callback(queue_free)


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
