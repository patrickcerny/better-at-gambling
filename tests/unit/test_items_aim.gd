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
