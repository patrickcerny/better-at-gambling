extends GutTest
## The hand-built item models (`ItemArt`) and their idle animation (`ItemIdle`).


func test_every_recipe_is_a_real_item_and_builds_an_animated_model() -> void:
	for id: StringName in ItemArt.RECIPES:
		assert_true(Registry.items.has(id), "%s is an item" % id)
		assert_false(ItemModels.MODELS.has(id), "%s has a model file too" % id)
		var m: Node3D = ItemArt.build(id)
		assert_not_null(m, str(id))
		var meshes: Array[Node] = m.find_children("*", "MeshInstance3D", true, false)
		assert_gt(meshes.size(), 3, "%s has parts" % id)
		var idle: ItemIdle = m.get_node_or_null(^"Idle") as ItemIdle
		assert_not_null(idle, "%s animates" % id)
		if idle != null:
			assert_gt(idle.track_count(), 0, "%s has a moving part" % id)
		m.free()


func test_idle_moves_parts_and_loops_back() -> void:
	var m: Node3D = ItemArt.build(&"loaded_reels")
	add_child_autofree(m)
	var idle: ItemIdle = m.get_node(^"Idle")
	var reel: Node3D = m.get_node(^"Reel0")
	idle.pose(0.0)
	var start: Basis = reel.basis
	idle.pose(0.2)
	assert_false(reel.basis.is_equal_approx(start), "the reel turns")
	idle.pose(TAU / 6.0)
	assert_true(reel.basis.is_equal_approx(start), "one full turn later it is back")


func test_held_models_sit_in_the_raised_hand_upright() -> void:
	var v := AvatarVisuals.new()
	add_child_autofree(v)
	for id: StringName in [&"lucky_clover", &"vip_pass", &"russian_roulette"]:
		v.hold_right_arm(ItemModels.arm_pose(id))
		v._animate_arms(0.0, {})  # headless runs don't animate on their own
		var held: Node3D = ItemModels.make_held(id)
		ItemModels.attach_to_hand(v, held)
		var up: Vector3 = held.global_basis.orthonormalized().y
		assert_almost_eq(up.dot(Vector3.UP), 1.0, 0.02, "%s stands upright in the hand" % id)
		var art: Node3D = held.get_child(0)
		assert_gt(art.get_meta(&"extent", Vector3.ZERO).y, 0.05, str(id))
		held.free()


func test_the_bat_keeps_the_arm_at_rest() -> void:
	assert_eq(ItemModels.arm_pose(&"baseball_bat"), Vector3.INF)
	assert_eq(ItemModels.arm_pose(&"lucky_clover"), ItemModels.HOLD_ARM)
