extends GutTest
## Sunglasses x-ray on the blackjack felt: the dealer's face-down card shows the peeked card in a
## green see-through look for the wearer only, and goes back to a plain back when it's over.


func test_hole_card_is_xrayed_and_restored() -> void:
	var st := BlackjackStation.new()
	add_child_autofree(st)
	st.show_round({"state": BlackjackLogic.State.ACTING, "seats": [1, -1, -1, -1], "dealer_revealed": false, "dealer": [Card.make(10, 1)],
		"hands": {1: {"cards": [Card.make(8, 0), Card.make(3, 2)]}}})
	await wait_process_frames(2)
	var dealer: Array[Node3D] = st.cards.pile_nodes(-1)
	assert_eq(dealer.size(), 2, "up card and hole card")
	var back: MeshInstance3D = dealer[1].get_node(^"Back")
	var plain: Texture2D = (back.material_override as StandardMaterial3D).albedo_texture
	var king: int = Card.make(13, 0)
	st.cards.set_xray(king)
	assert_eq(st.cards.xray_card(), king)
	var mat: StandardMaterial3D = back.material_override
	assert_ne(mat.albedo_texture, plain, "the hole card's face shows through")
	assert_true(mat.emission_enabled, "x-ray glow")
	assert_gt(mat.albedo_color.g, mat.albedo_color.r, "green tint")
	var up_back: MeshInstance3D = dealer[0].get_node(^"Back")
	assert_eq((up_back.material_override as StandardMaterial3D).albedo_texture, plain, "only the face-down card")
	st.cards.set_xray(-1)
	assert_eq((back.material_override as StandardMaterial3D).albedo_texture, plain, "plain back again")
	assert_false((back.material_override as StandardMaterial3D).emission_enabled)
