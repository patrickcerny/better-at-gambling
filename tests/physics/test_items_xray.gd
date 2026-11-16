extends GutTest
## Sunglasses on the card tables: the dealer's face-down cards show their faces half see-through
## for the wearer only (felt and overlay), and go back to plain backs when it's over.


func test_hole_card_shows_see_through_and_is_restored() -> void:
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
	st.cards.set_peek([king])
	assert_eq(st.cards.peek_cards(), [king] as Array[int])
	var mat: StandardMaterial3D = back.material_override
	assert_ne(mat.albedo_texture, plain, "the hole card's face shows")
	assert_eq(mat.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA)
	assert_lt(mat.albedo_color.a, 0.8, "half see-through")
	var up_back: MeshInstance3D = dealer[0].get_node(^"Back")
	assert_eq((up_back.material_override as StandardMaterial3D).albedo_texture, plain, "only the face-down card")
	st.cards.set_peek([])
	assert_eq((back.material_override as StandardMaterial3D).albedo_texture, plain, "plain back again")
	assert_false((back.material_override as StandardMaterial3D).emission_enabled)


func test_a_new_hole_card_keeps_the_peek() -> void:
	var st := BlackjackStation.new()
	add_child_autofree(st)
	var king: int = Card.make(13, 0)
	st.cards.set_peek([king])
	st.show_round({"state": BlackjackLogic.State.ACTING, "seats": [1, -1, -1, -1], "dealer_revealed": false, "dealer": [Card.make(10, 1)],
		"hands": {1: {"cards": [Card.make(8, 0), Card.make(3, 2)]}}})
	await wait_process_frames(2)
	var back: MeshInstance3D = st.cards.pile_nodes(-1)[1].get_node(^"Back")
	assert_eq((back.material_override as StandardMaterial3D).transparency, BaseMaterial3D.TRANSPARENCY_ALPHA, "dealt straight in see-through")


func test_holdem_dealers_two_show_see_through() -> void:
	var st := HoldemStation.new()
	add_child_autofree(st)
	st.show_round({"state": HoldemLogic.State.RIVER, "seats": [1, -1, -1, -1], "dealer": [], "dealer_down": 2, "board": [1, 2, 3, 4],
		"hands": {1: {"hole": [20, 21], "decision": HoldemLogic.CALL, "river_decision": &""}}})
	await wait_process_frames(2)
	st.cards.set_peek([30, 31])
	var dealer: Array[Node3D] = st.cards.pile_nodes(-1)
	assert_eq(dealer.size(), 2)
	for n: Node3D in dealer:
		var mat: StandardMaterial3D = (n.get_node(^"Back") as MeshInstance3D).material_override
		assert_eq(mat.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA)


func test_overlay_row_draws_peeked_cards_half_see_through() -> void:
	var row := CardRow.new(58.0)
	add_child_autofree(row)
	row.show_cards([Card.make(10, 1), -1], false, [Card.make(13, 0)])
	var faces: Array[Node] = row.get_children()
	assert_eq(faces.size(), 2)
	var peeked: CardFace = faces[1] as CardFace
	assert_eq(peeked.card, Card.make(13, 0), "the face, not the back")
	assert_lt(peeked.modulate.a, 1.0, "see-through")
	assert_eq((faces[0] as CardFace).modulate.a, 1.0)
	row.show_cards([Card.make(10, 1), -1])
	assert_eq((row.get_child(1) as CardFace).card, -1, "a back again without the peek")
