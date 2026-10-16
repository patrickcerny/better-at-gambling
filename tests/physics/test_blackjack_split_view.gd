extends GutTest
## A split on the real blackjack table (Patrick: "actually make it 2 hands ... indicate somehow
## (with an outline) which hands youre playing"): the seat's cards become two groups side by side,
## the hand being played (the server's `active`) is outlined in gold with a "HAND n" marker over
## it, the outline moves to hand 2 when play moves on and is gone once the round settles. Each
## hand gets its own bet chips.

var st: BlackjackStation


func before_each() -> void:
	Vfx.force_enabled = true
	st = BlackjackStation.new()
	add_child_autofree(st)
	await wait_process_frames(1)


func after_each() -> void:
	Vfx.force_enabled = false


func _pub(state: int, h7: Dictionary, revealed: bool = false) -> Dictionary:
	# Seat 0: the splitter (7); seat 1: a neighbour (8) who never splits.
	return {"state": state, "seats": [7, 8, -1, -1], "dealer_revealed": revealed, "dealer": [Card.make(10, 1)],
		"hands": {7: h7, 8: {"stake": 20, "cards": [Card.make(9, 0), Card.make(9, 3)], "done": false, "total": 18}}}


## Seat-local x of a card (positive = to the seat's right as it faces the table).
func _side(n: Node3D) -> float:
	return (Basis(Vector3.UP, float(st.cards.spots[0][1])).inverse() * n.position).x


func _outlined(key: int) -> int:
	var count: int = 0
	for n: Node3D in st.cards.pile_nodes(key):
		if TableCards.is_outlined(n):
			count += 1
	return count


func test_split_shows_two_hands_and_outlines_the_active_one() -> void:
	var e8: int = Card.make(8, 0)
	var s8: int = Card.make(8, 2)
	st.show_round(_pub(BlackjackLogic.State.ACTING, {"stake": 50, "cards": [e8, s8], "done": false, "total": 16, "can_split": true}))
	await wait_seconds(1.0)
	assert_eq(st.cards.pile_nodes(0).size(), 2)
	assert_eq(_outlined(0), 0, "no outline before a split")
	var moved: Node3D = st.cards.pile_nodes(0)[1]
	var centre: float = _side(st.cards.pile_nodes(0)[0])
	# Split: hand 1 gets its second card, hand 2 waits with its one card.
	st.show_round(_pub(BlackjackLogic.State.ACTING, {"stake": 50, "cards": [e8, Card.make(3, 1)], "done": false, "total": 11, "active": 0, "first_done": false,
		"split": {"stake": 50, "cards": [s8], "done": false, "total": 8}}))
	await wait_seconds(1.0)
	var h1: Array[Node3D] = st.cards.pile_nodes(0)
	var h2: Array[Node3D] = st.cards.pile_nodes(BlackjackStation.SPLIT_KEY)
	assert_eq(h1.size(), 2)
	assert_eq(h2.size(), 1)
	assert_eq(h2[0], moved, "the split card slid over (not swept and dealt again)")
	assert_lt(_side(h1[0]), centre - 0.1, "hand 1 moved to the left")
	assert_gt(_side(h2[0]), centre + 0.1, "hand 2 on the right")
	var h1_right: float = _side(h1[1]) + TableCards.CARD_SIZE.x * 0.5
	var h2_left: float = _side(h2[0]) - TableCards.CARD_SIZE.x * 0.5
	assert_lt(h1_right, h2_left, "two separate card groups, not overlapping")
	assert_almost_eq(h1[0].position.y, h2[0].position.y, 0.001, "side by side at the same depth on the felt")
	assert_eq(_outlined(0), 2, "hand 1 outlined")
	assert_eq(_outlined(BlackjackStation.SPLIT_KEY), 0)
	assert_eq(_outlined(1), 0, "the neighbour's hand is never outlined")
	var marker: Label3D = st.hand_markers[0]
	assert_true(marker.visible)
	assert_eq(marker.text, "HAND 1")
	assert_lt(marker.position.distance_to(h1[0].position.lerp(h1[1].position, 0.5)), 0.5, "over hand 1")
	assert_gt(marker.position.y, h1[0].position.y)
	assert_eq(st.hand_tags[0].text, "11")
	assert_eq(st.hand_tags[BlackjackStation.SPLIT_KEY].text, "8")
	assert_true(st.hand_tags[BlackjackStation.SPLIT_KEY].visible)
	# Play moves on to hand 2 (hand 1 hit to 21; hand 2 got its second card).
	st.show_round(_pub(BlackjackLogic.State.ACTING, {"stake": 50, "cards": [e8, Card.make(3, 1), Card.make(10, 3)], "done": false, "total": 21, "active": 1, "first_done": true,
		"split": {"stake": 50, "cards": [s8, Card.make(9, 1)], "done": false, "total": 17}}))
	await wait_seconds(1.0)
	assert_eq(st.cards.pile_nodes(0).size(), 3)
	assert_eq(_outlined(0), 0, "hand 1 lost the outline")
	assert_eq(_outlined(BlackjackStation.SPLIT_KEY), 2, "hand 2 outlined, its new card too")
	assert_eq(marker.text, "HAND 2")
	var h2n: Array[Node3D] = st.cards.pile_nodes(BlackjackStation.SPLIT_KEY)
	assert_lt(marker.position.distance_to(h2n[0].position.lerp(h2n[1].position, 0.5)), 0.5, "over hand 2")
	assert_eq(st.hand_tags[0].text, "21")
	assert_eq(st.hand_tags[BlackjackStation.SPLIT_KEY].text, "17")
	# Settled: no outline, no marker; the value tags stay with the cards until the sweep.
	st.show_round(_pub(BlackjackLogic.State.PAYOUT, {"stake": 50, "cards": [e8, Card.make(3, 1), Card.make(10, 3)], "done": true, "total": 21, "active": 1, "first_done": true,
		"split": {"stake": 50, "cards": [s8, Card.make(9, 1)], "done": true, "total": 17}}, true))
	assert_eq(_outlined(0) + _outlined(BlackjackStation.SPLIT_KEY), 0, "outline gone after the settle")
	assert_false(marker.visible)
	assert_true(st.hand_tags[0].visible)
	st.show_round({"state": BlackjackLogic.State.IDLE, "seats": [7, 8, -1, -1], "dealer": [], "hands": {}})
	assert_false(st.hand_tags[0].visible)
	assert_false(st.hand_tags[BlackjackStation.SPLIT_KEY].visible)
	await wait_seconds(0.5)
	# Next round, no split: the seat's cards are back in the middle.
	st.show_round(_pub(BlackjackLogic.State.ACTING, {"stake": 50, "cards": [Card.make(5, 0), Card.make(6, 0)], "done": false, "total": 11}))
	await wait_seconds(1.0)
	assert_almost_eq(_side(st.cards.pile_nodes(0)[0]), centre, 0.01, "one hand in the middle again")
	assert_eq(_outlined(0), 0)


func test_outline_is_a_gold_rim_from_the_aim_shader() -> void:
	st.show_round(_pub(BlackjackLogic.State.ACTING, {"stake": 50, "cards": [Card.make(8, 0), Card.make(3, 1)], "done": false, "total": 11, "active": 0,
		"split": {"stake": 50, "cards": [Card.make(8, 2)], "done": false, "total": 8}}))
	var o: MeshInstance3D = st.cards.pile_nodes(0)[0].get_node(^"Outline")
	var m: ShaderMaterial = o.material_override
	assert_eq(m.shader, load("res://client/aim_outline.gdshader"))
	var aabb: AABB = o.mesh.get_aabb()
	assert_almost_eq(aabb.size.x, TableCards.CARD_SIZE.x, 0.001, "card sized; the shader grows it into a rim")
	assert_almost_eq(aabb.size.z, TableCards.CARD_SIZE.y, 0.001)
	var normals: PackedVector3Array = o.mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	for n: Vector3 in normals:
		assert_gt(Vector2(n.x, n.z).length(), 0.8, "normals lean outwards, so the hull grows sideways")


func test_split_bets_sit_in_front_of_each_hand_and_pay_per_hand() -> void:
	var w := Node3D.new()
	add_child_autofree(w)
	var fx := TableFx.new()
	add_child_autofree(fx)
	fx.setup({&"b": st}, func(_p: int) -> PlayerAvatar: return null, 1, null, w, Callable(), func(_sid: StringName) -> int: return 10)
	fx.on_event({"type": &"bet_placed", "player": 1, "station": &"b", "amount": 50, "details": {"game": "blackjack"}})
	await wait_seconds(0.6)
	fx.on_event({"type": &"bj_action", "station": &"b", "player": 1, "action": &"split", "cards": [], "hand": 0, "split_cards": []})
	await wait_seconds(0.6)
	var stacks: Array[ChipStack] = []
	for c: Node in st.get_children():
		if c is ChipStack:
			stacks.append(c)
	assert_eq(stacks.size(), 2, "a stack per hand")
	assert_eq(stacks[1].amount, 50, "the second stake matches the first")
	assert_lt(stacks[0].position.distance_to(st.hand_bet_spot(0, 0)), 0.03, "bet 1 in front of hand 1")
	assert_lt(stacks[1].position.distance_to(st.hand_bet_spot(0, 1)), 0.03, "bet 2 in front of hand 2")
	var side: Basis = Basis(Vector3.UP, float(st.cards.spots[0][1])).inverse()
	assert_lt((side * stacks[0].position).x, (side * stacks[1].position).x, "left and right, like the cards")
	assert_gt(stacks[0].position.distance_to(stacks[1].position), ChipStack.CHIP_RADIUS * 2.0, "apart")
	# Hand 2 loses, hand 1 wins: each stack goes its own way.
	fx.on_event({"type": &"round_result", "station": &"b", "player": 1, "stake": 50, "returned": 0, "net": -50, "details": {"hand": 1, "split": true}})
	fx.on_event({"type": &"round_result", "station": &"b", "player": 1, "stake": 50, "returned": 100, "net": 50, "details": {"hand": 0, "split": true}})
	await wait_seconds(2.0)
	var left: int = 0
	for c: Node in st.get_children():
		if c is ChipStack:
			left += 1
	assert_eq(left, 0, "both stacks settled")
