extends GutTest
## Online clients show the server's ragdoll pose. The streamed rotation is the torso's world
## rotation, but the puppet's node is turned by the bean's yaw when it starts: the pose has to land
## in world space, or the bean lies turned the wrong way on everybody else's screen.


func test_puppet_takes_the_streamed_world_rotation() -> void:
	var rb := RagdollBody.new()
	rb.puppet = true
	rb.rotation.y = 1.3  # the bean's yaw when it went down
	add_child_autofree(rb)
	var want := Quaternion(Vector3(1, 0, 0), PI * 0.5)  # lying on its face, facing world -Z
	rb.apply_pose(Vector3(2.0, 0.4, -1.0), want, [Vector3(2.0, 0.4, -1.8), Vector3(1.4, 0.4, -1.0), Vector3(2.6, 0.4, -1.0), Vector3(2.0, 0.4, -0.5)])
	await wait_physics_frames(2)
	var got: Quaternion = rb.torso.global_basis.get_rotation_quaternion()
	assert_almost_eq(absf(got.dot(want)), 1.0, 0.001, "torso world rotation = streamed rotation")
	assert_almost_eq(rb.torso.global_position, Vector3(2.0, 0.4, -1.0), Vector3.ONE * 0.001)
