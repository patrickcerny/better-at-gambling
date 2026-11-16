extends GutTest
## Patrick: "Wenn man knocked out ist bei manchen minigames, kann die kamera aus dem raum
## rausglitchen und man sieht ins void." The knocked-out camera orbits the ragdoll's torso; it
## must stay inside the room's walls, ceiling and floor whichever way the player looks.

const STEP: float = 1.0 / 60.0
## A closed 8 x 3 x 8 room around the origin, walls 0.5 thick (like the minigame rooms).
const HALF: float = 4.0
const HEIGHT: float = 3.0

var _cam: PlayerCamera
var _torso: Node3D


func _box(size: Vector3, pos: Vector3) -> void:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	b.add_child(cs)
	b.position = pos
	add_child_autofree(b)


func before_each() -> void:
	var w: float = HALF * 2.0 + 1.0
	_box(Vector3(w, 0.5, w), Vector3(0, -0.25, 0))
	_box(Vector3(w, 0.5, w), Vector3(0, HEIGHT + 0.25, 0))
	_box(Vector3(0.5, HEIGHT, w), Vector3(-HALF - 0.25, HEIGHT * 0.5, 0))
	_box(Vector3(0.5, HEIGHT, w), Vector3(HALF + 0.25, HEIGHT * 0.5, 0))
	_box(Vector3(w, HEIGHT, 0.5), Vector3(0, HEIGHT * 0.5, -HALF - 0.25))
	_box(Vector3(w, HEIGHT, 0.5), Vector3(0, HEIGHT * 0.5, HALF + 0.25))
	_cam = PlayerCamera.new()
	add_child_autofree(_cam)
	_torso = Node3D.new()
	add_child_autofree(_torso)
	_cam.follow = _torso
	await wait_physics_frames(2)


func _inside(p: Vector3) -> bool:
	return absf(p.x) < HALF - 0.05 and absf(p.z) < HALF - 0.05 and p.y > 0.05 and p.y < HEIGHT - 0.05


## Runs the knocked-out camera for a second with the given look direction.
func _settle(yaw: float, pitch: float) -> void:
	_cam.yaw = yaw
	_cam.pitch = pitch
	for i: int in 60:
		_cam.update_camera(0.0, true, true, STEP)
		assert_true(_inside(_cam.camera.global_position), "frame %d: camera left the room at %s" % [i, _cam.camera.global_position])
		await wait_physics_frames(1)


func test_against_each_wall_the_camera_stays_in_the_room() -> void:
	# Torso 0.6 m from the +z wall; the camera sits behind the look direction, so yaw 0 puts it
	# straight into that wall, and the other yaws into the others once the torso moves there.
	var spots: Array[Vector3] = [Vector3(0, 0.3, HALF - 0.6), Vector3(HALF - 0.6, 0.3, 0), Vector3(0, 0.3, -HALF + 0.6), Vector3(-HALF + 0.6, 0.3, 0)]
	var yaws: Array[float] = [0.0, PI * 0.5, PI, -PI * 0.5]
	for i: int in spots.size():
		_torso.global_position = spots[i]
		await _settle(yaws[i], deg_to_rad(-20.0))


func test_in_a_corner_looking_down_and_up() -> void:
	_torso.global_position = Vector3(HALF - 0.5, 0.3, HALF - 0.5)
	await _settle(PI * 0.25, deg_to_rad(-80.0))  # camera up and back: ceiling and corner
	await _settle(PI * 0.25, deg_to_rad(80.0))  # camera down and back: floor


func test_torso_under_the_ceiling() -> void:
	_torso.global_position = Vector3(0, HEIGHT - 0.4, 0)  # thrown up against the ceiling
	await _settle(0.0, deg_to_rad(-60.0))


func test_open_space_keeps_the_full_distance() -> void:
	_torso.global_position = Vector3(0, 0.3, 0)
	await _settle(0.0, 0.0)
	var eye: Vector3 = _torso.global_position + Vector3(0, 1.0, 0)
	assert_almost_eq(_cam.camera.global_position.distance_to(eye), Vector3(0, 0.5, PlayerCamera.THIRD_DISTANCE).length(), 0.1, "nothing in the way: full orbit distance")
