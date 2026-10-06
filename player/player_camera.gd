class_name PlayerCamera
extends Node3D
## First-person by default with a third-person toggle (§2.4.2). Eases to a station's camera
## anchor while seated, where the head follows `seated_look` (the cursor's offset from the middle
## of the screen, or the right stick) a little: ±25° yaw, ±15° pitch, smoothed. The mouse stays
## free while seated so the station overlay can be clicked. Auto third-person while ragdolled.

enum Mode { FIRST, THIRD }

const EYE_HEIGHT: float = 1.35
const SEATED_YAW_LIMIT: float = deg_to_rad(40.0)
const THIRD_DISTANCE: float = 3.5
## Seated head turn at the edge of the screen, and how fast the head catches up (1/s).
const SEATED_LOOK_YAW: float = deg_to_rad(25.0)
const SEATED_LOOK_PITCH: float = deg_to_rad(15.0)
const SEATED_LOOK_SPEED: float = 7.0

var mode: Mode = Mode.FIRST
var camera: Camera3D
var spring: SpringArm3D
var yaw: float = 0.0
var pitch: float = 0.0
var sensitivity: float = 0.0025
var fov: float = 85.0
## Set while seated: the anchor to ease to.
var anchor: Node3D = null
## Set while ragdolled: node to follow.
var follow: Node3D = null
var head_bob: bool = true
## Seated: where the head wants to turn, [-1, 1] per axis (x right, y down). Set every frame by the owner.
var seated_look: Vector2 = Vector2.ZERO
## Seated: the smoothed head turn in radians (x yaw, y pitch), added on top of the station view.
var seated_offset: Vector2 = Vector2.ZERO

var _seated_yaw_center: float = 0.0
## How far you can turn from the station view (an anchor's "yaw_limit" meta overrides it).
var seated_yaw_limit: float = SEATED_YAW_LIMIT
var _bob_time: float = 0.0
var _anchor_blend: float = 0.0


func _ready() -> void:
	spring = SpringArm3D.new()
	spring.name = "SpringArm"
	spring.spring_length = THIRD_DISTANCE
	spring.collision_mask = 1
	spring.margin = 0.2
	spring.position = Vector3(0.0, EYE_HEIGHT + 0.3, 0.0)
	add_child(spring)
	camera = Camera3D.new()
	camera.name = "Camera"
	fov = float(Settings.get_value("video", "fov"))
	camera.fov = fov
	camera.near = 0.05
	add_child(camera)
	Settings.changed.connect(_apply_fov)
	camera.position = Vector3(0.0, EYE_HEIGHT, 0.0)


## Makes this the active camera.
func activate() -> void:
	camera.current = true


func toggle_mode() -> void:
	mode = Mode.THIRD if mode == Mode.FIRST else Mode.FIRST


## Mouse/stick look.
func look(delta_yaw: float, delta_pitch: float) -> void:
	yaw -= delta_yaw
	pitch = clampf(pitch - delta_pitch, deg_to_rad(-80.0), deg_to_rad(80.0))
	if anchor != null:
		yaw = clampf(yaw, _seated_yaw_center - seated_yaw_limit, _seated_yaw_center + seated_yaw_limit)


## Eases to a station view. `null` returns to the body.
func set_anchor(a: Node3D) -> void:
	anchor = a
	_anchor_blend = 0.0
	seated_look = Vector2.ZERO
	seated_offset = Vector2.ZERO
	if a != null:
		_seated_yaw_center = a.global_rotation.y
		seated_yaw_limit = float(a.get_meta(&"yaw_limit", SEATED_YAW_LIMIT))
		yaw = _seated_yaw_center
		pitch = a.global_rotation.x


## Forward direction on the ground plane.
func forward() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


## Aim direction (with pitch).
func aim() -> Vector3:
	return -camera.global_transform.basis.z


func update_camera(speed: float, on_floor: bool, ragdolled: bool, delta: float) -> void:
	var third: bool = mode == Mode.THIRD or ragdolled
	var up_rot := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	if anchor != null:
		_anchor_blend = minf(_anchor_blend + delta / 0.4, 1.0)
		var want := Vector2(-seated_look.x * SEATED_LOOK_YAW, -seated_look.y * SEATED_LOOK_PITCH)
		seated_offset = seated_offset.lerp(want, 1.0 - exp(-SEATED_LOOK_SPEED * delta))
		var target: Transform3D = anchor.global_transform
		target.basis = Basis.from_euler(Vector3(clampf(pitch + seated_offset.y, deg_to_rad(-85.0), deg_to_rad(60.0)), yaw + seated_offset.x, 0.0))
		camera.global_transform = camera.global_transform.interpolate_with(target, _anchor_blend)
		return
	if ragdolled and follow != null:
		var eye: Vector3 = follow.global_position + Vector3(0, 1.0, 0)
		var offset: Vector3 = up_rot * Vector3(0, 0.5, THIRD_DISTANCE)
		camera.global_position = camera.global_position.lerp(eye + offset, 8.0 * delta)
		camera.look_at(eye, Vector3.UP)
		return
	if third:
		spring.global_rotation = Vector3(pitch, yaw, 0.0)
		var base: Vector3 = global_position + Vector3(0, EYE_HEIGHT + 0.3, 0)
		var dir: Vector3 = up_rot * Vector3(0.6, 0.0, 1.0).normalized()
		var dist: float = spring.get_hit_length()
		camera.global_position = base + dir * dist
		camera.look_at(base + up_rot * Vector3(0, 0, -5), Vector3.UP)
		return
	_bob_time += delta * clampf(speed, 0.0, 8.0)
	var bob: Vector3 = Vector3(0, sin(_bob_time * 1.6) * 0.03, 0) if head_bob and on_floor and speed > 0.5 else Vector3.ZERO
	camera.global_position = global_position + Vector3(0, EYE_HEIGHT, 0) + bob
	camera.global_rotation = Vector3(pitch, yaw, 0.0)


func _apply_fov() -> void:
	fov = float(Settings.get_value("video", "fov"))
	camera.fov = fov
