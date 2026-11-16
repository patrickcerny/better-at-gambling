extends GutTest
## The animated cigarette mouth piece (`Cigarette`, Patrick 2026-11-16).


func after_each() -> void:
	AvatarVisuals.outfits_headless = false


func test_sold_for_red_coins_never_on_the_wheel_or_pass() -> void:
	var d: CosmeticDef = CosmeticShop.default().find(Cigarette.ID)
	assert_not_null(d)
	assert_eq(d.kind, CosmeticDef.KIND_MOUTH)
	assert_true(d.coin_buyable(), "bought with red Coins")
	assert_eq(d.level, 0, "no level wall")
	assert_false(d.wheel_only)
	assert_eq(d.achievement, &"")


func test_has_a_still_model_at_the_mouth() -> void:
	var m: ArrayMesh = OutfitMeshes.mesh(Cigarette.ID)
	assert_not_null(m, "ragdolls and thumbnails get the still model")
	var box: AABB = m.get_aabb()
	var my: float = OutfitMeshes._mouth_y()
	assert_between(box.get_center().y, my - 0.12, my + 0.05, "at mouth height")
	assert_lt(box.position.z, AvatarVisuals.face_z(my, 0.0) - 0.1, "it sticks out in front of the face")


func test_the_tip_stays_out_of_the_face() -> void:
	var p: Transform3D = Cigarette.pivot()
	var tip: Vector3 = p * Vector3(0, 0, -Cigarette.length())
	assert_lt(tip.z, AvatarVisuals.face_z(tip.y, tip.x) - 0.1, "the ember is well clear of the skin")
	assert_gt(tip.x, p.origin.x, "it points out of the corner of the mouth")


func test_worn_it_animates_and_comes_off() -> void:
	AvatarVisuals.outfits_headless = true
	var v := AvatarVisuals.new()
	add_child_autofree(v)
	v.wear(CosmeticDef.KIND_MOUTH, Cigarette.ID)
	var cig := v.body.find_child("Cigarette", false, false) as Cigarette
	assert_not_null(cig, "the cigarette rides the body")
	assert_not_null(cig.find_child("Ember", false, false))
	var b0: Basis = cig.basis
	await wait_process_frames(10)
	assert_ne(cig.basis, b0, "it bobs")
	v.wear(CosmeticDef.KIND_MOUTH, &"mouth_gold")
	await wait_process_frames(1)
	assert_null(v.body.find_child("Cigarette", false, false), "it comes off")
