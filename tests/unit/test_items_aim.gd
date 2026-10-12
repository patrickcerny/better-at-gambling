extends GutTest
## The held-item client logic without a scene: who an aimed item hits (nearest player inside the
## forward cone and the item's reach), which items aim, the `use_item` intent payload, the duel
## stake preview and the item models helper.

const ME := Vector3(0, 0, 0)
const NORTH := Vector3(0, 0, -1)


func test_nearest_player_inside_the_cone_wins() -> void:
	var c: Dictionary = {2: Vector3(0, 0, -5), 3: Vector3(0.5, 0, -2), 4: Vector3(0, 0, 3)}
	assert_eq(ItemController.pick_aimed(ME, NORTH, c, 10.0), 3, "nearest in front")
	c.erase(3)
	assert_eq(ItemController.pick_aimed(ME, NORTH, c, 10.0), 2)
	assert_eq(ItemController.pick_aimed(ME, -NORTH, c, 10.0), 4, "turning round aims at the one behind")


func test_cone_edges() -> void:
	# 30° half-angle: 25° off is in, 35° off is out.
	var inside: Vector3 = Vector3(sin(deg_to_rad(25.0)), 0, -cos(deg_to_rad(25.0))) * 4.0
	var outside: Vector3 = Vector3(sin(deg_to_rad(35.0)), 0, -cos(deg_to_rad(35.0))) * 4.0
	assert_eq(ItemController.pick_aimed(ME, NORTH, {7: inside}, 10.0), 7)
	assert_eq(ItemController.pick_aimed(ME, NORTH, {7: outside}, 10.0), -1)
	assert_eq(ItemController.pick_aimed(ME, NORTH, {7: outside}, 10.0, 40.0), 7, "a wider cone takes it")
	assert_eq(ItemController.AIM_CONE_DEG, 30.0)


func test_range_height_and_ties() -> void:
	assert_eq(ItemController.pick_aimed(ME, NORTH, {5: Vector3(0, 0, -4.5)}, 4.0), -1, "out of reach")
	assert_eq(ItemController.pick_aimed(ME, NORTH, {5: Vector3(0, 0, -3.9)}, 4.0), 5)
	assert_eq(ItemController.pick_aimed(ME, NORTH + Vector3(0, -0.8, 0), {5: Vector3(0, 0, -3)}, 4.0), 5, "looking down still aims along the floor")
	assert_eq(ItemController.pick_aimed(ME, NORTH, {6: Vector3(1, 0, -3), 5: Vector3(-1, 0, -3)}, 10.0), 5, "a tie goes to the lower id")
	assert_eq(ItemController.pick_aimed(ME, NORTH, {5: Vector3(0, 0, 0.01)}, 10.0), 5, "standing on top of you counts")
	assert_eq(ItemController.pick_aimed(ME, Vector3.UP, {5: Vector3(0, 0, -3)}, 10.0), -1, "no direction, no aim")
	assert_eq(ItemController.pick_aimed(ME, NORTH, {}, 10.0), -1)


func test_which_items_aim_and_their_reach() -> void:
	assert_true(ItemController.aims(Registry.items[&"black_cat"]))
	assert_true(ItemController.aims(Registry.items[&"pickpocket"]))
	assert_true(ItemController.aims(Registry.items[&"bouncer"]))
	assert_false(ItemController.aims(Registry.items[&"lucky_clover"]), "self items apply at once")
	assert_false(ItemController.aims(Registry.items[&"banana_peel"]))
	assert_false(ItemController.aims(Registry.items[&"robin_hood"]), "the server picks the leader")
	assert_eq(ItemController.reach(Registry.items[&"pickpocket"]), Registry.items[&"pickpocket"].range_m)
	assert_eq(ItemController.reach(Registry.items[&"black_cat"]), ItemController.AIM_RANGE, "no range of its own")


func test_use_intent_payload_keeps_the_schema() -> void:
	var plain: Dictionary = ItemController.use_intent(1, -1, -1)
	assert_eq(plain, {"type": &"use_item", "slot": 1})
	assert_true(Intents.validate(plain).is_empty())
	var aimed: Dictionary = ItemController.use_intent(0, 3, -1)
	assert_eq(aimed, {"type": &"use_item", "slot": 0, "target": 3})
	var chosen: Dictionary = ItemController.use_intent(2, 4, 1)
	assert_eq(chosen, {"type": &"use_item", "slot": 2, "target": 4, "option": 1})
	assert_true(Intents.validate(chosen).is_empty())


func test_choice_items_and_stake_preview() -> void:
	assert_true(ItemController.CHOICES.has(&"pickpocket"))
	assert_true(ItemController.CHOICES.has(&"rock_paper_scissors"))
	for id: StringName in ItemController.CHOICES:
		assert_eq((ItemController.CHOICES[id]["options"] as Array).size(), 2, "two buttons for %s" % id)
	assert_eq(ItemController.stake_preview(1000, 3000, 0), 50, "5% of the poorer")
	assert_eq(ItemController.stake_preview(1000, 3000, 2), 150)
	assert_eq(ItemController.stake_preview(40, 3000, 0), RpsDuels.MIN_STAKE)


func test_rejections_for_the_new_items_read_well() -> void:
	for e: StringName in [&"not_seated", &"you_lead", &"bounced", &"no_tips_here", &"no_target"]:
		assert_false(ItemController.rejection_text(e).contains("_"), str(e))


func test_item_models_have_a_model_for_every_item() -> void:
	for id: StringName in Registry.items:
		assert_true(ResourceLoader.exists(ItemModels.path_for(id)), "model for %s" % id)
		assert_gt(ItemModels.size_for(id), 0.05)
	assert_true(ItemModels.has_own(&"baseball_bat"))
	assert_true(ItemModels.has_own(&"empty_bottle"), "PropModels.ITEM_PROPS")
	assert_false(ItemModels.has_own(&"lucky_clover"), "the coin placeholder")
	var bat: Node3D = ItemModels.make(&"baseball_bat")
	assert_eq(bat.get_meta(&"item"), &"baseball_bat")
	assert_eq(bat.get_child_count(), 1)
	bat.free()


## The bat's two ends in `space`'s coordinates: [barrel, knob]. The barrel is the thick end of the
## model (asserted, so a swapped model fails here rather than turning up in a hand upside down).
func _bat_ends(holder: Node3D, space: Node3D) -> Array:
	var pts: Array[Vector3] = []
	for n: Node in holder.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		var xf: Transform3D = holder.global_transform.affine_inverse() * mi.global_transform
		for p: Vector3 in mi.mesh.get_faces():
			pts.append(xf * p)
	var lo: float = INF
	var hi: float = -INF
	for p: Vector3 in pts:
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
	var r_lo: float = 0.0
	var r_hi: float = 0.0
	for p: Vector3 in pts:
		var r: float = Vector2(p.x, p.z).length()
		if p.y < lo + (hi - lo) * 0.2:
			r_lo = maxf(r_lo, r)
		elif p.y > hi - (hi - lo) * 0.2:
			r_hi = maxf(r_hi, r)
	assert_gt(r_lo, r_hi * 1.2, "the bat model's barrel (thick end) is its -y end")
	var to_space: Transform3D = space.global_transform.affine_inverse() * holder.global_transform
	return [to_space * Vector3(0, lo, 0), to_space * Vector3(0, hi, 0)]


func test_held_bat_points_barrel_up_and_forward() -> void:
	var v := AvatarVisuals.new()
	add_child_autofree(v)
	var held: Node3D = ItemModels.make_held(&"baseball_bat")
	ItemModels.attach_to_hand(v, held)
	var ends: Array = _bat_ends(held.get_child(0) as Node3D, v)
	var barrel: Vector3 = ends[0]
	var knob: Vector3 = ends[1]
	var hand: Vector3 = v.global_transform.affine_inverse() * ItemModels.hand_node(v).global_position
	assert_gt(barrel.y, knob.y + 0.5, "barrel above the grip, not the handle sticking up")
	assert_lt(barrel.z, knob.z, "barrel forward (-z) of the grip")
	assert_lt(knob.distance_to(hand), barrel.distance_to(hand), "the fist holds the handle end")
	var expected: float = ItemModels.size_for(&"baseball_bat") * ItemModels.hand_scale(&"baseball_bat")
	assert_almost_eq(barrel.distance_to(knob), expected, expected * 0.1, "bat 1.35x its plain size in hand")
	assert_lt(knob.distance_to(hand), 0.3, "knob in the fist")


func test_first_person_bat_points_barrel_up_and_away() -> void:
	var cam := Camera3D.new()
	add_child_autofree(cam)
	var view: Node3D = ItemModels.make_view(&"baseball_bat")
	cam.add_child(view)
	var ends: Array = _bat_ends(view.get_child(0) as Node3D, cam)
	var barrel: Vector3 = ends[0]
	var knob: Vector3 = ends[1]
	assert_gt(barrel.y, knob.y, "barrel above the grip in view")
	assert_lt(barrel.z, knob.z, "barrel further from the eye than the grip")


func test_aim_outline_grows_in_world_space() -> void:
	# The old outline was a StandardMaterial3D grow (model space): on a skin imported at scale 73.7
	# (warrior) the 0.035 grow became 2.6 m of gold shards around whoever you aimed at.
	var m: Material = ItemController.outline_material()
	assert_true(m is ShaderMaterial, "not a model-space BaseMaterial3D grow")
	var sm: ShaderMaterial = m as ShaderMaterial
	assert_eq(float(sm.get_shader_parameter(&"width")), ItemController.OUTLINE_WIDTH)
	assert_lt(ItemController.OUTLINE_WIDTH, 0.06, "a thin line, in metres")
	var code: String = sm.shader.code
	assert_true(code.contains("skip_vertex_transform"), "the vertex shader places the hull itself")
	assert_true(code.contains("MODEL_NORMAL_MATRIX"), "normals grown in world space")
	assert_true(code.contains("cull_front"))
	# Every mesh of a scaled skin takes the overlay without errors.
	var v := AvatarVisuals.new()
	add_child_autofree(v)
	v.set_skin(&"warrior")
	var n: int = 0
	for g: Node in v.find_children("*", "MeshInstance3D", true, false):
		(g as MeshInstance3D).material_overlay = sm
		n += 1
	assert_gt(n, 0)
