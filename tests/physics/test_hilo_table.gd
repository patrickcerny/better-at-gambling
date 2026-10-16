extends GutTest
## The Hi-Lo table in the real match scene: it stands on the casino floor clear of every other
## collider with its four stools and its dealer, you can walk up, sit down and ante, and the cards
## the server deals land face up on the felt in front of your seat (with the ladder and the pot).
## Every seat's camera sees its own cards, its ante ring and the dealer.

const SID: StringName = &"hilo_1"

var scene: MatchScene
var hl: HiLoStation


func before_each() -> void:
	Net.stop()
	scene = (load("res://match/match_scene.tscn") as PackedScene).instantiate()
	add_child_autofree(scene)
	scene.server.timescale = 1.0
	await wait_seconds(3.3)
	assert_eq(scene.server.phases.phase, Phase.Id.CASINO, "casino phase after the intro")
	hl = scene.map.stations[SID] as HiLoStation


func after_each() -> void:
	Vfx.force_enabled = false


## World AABBs of the colliders under `root` that are (or are not) part of the Hi-Lo table.
func _boxes(root: Node, mine: bool) -> Array[AABB]:
	var out: Array[AABB] = []
	for n: Node in root.find_children("*", "CollisionShape3D", true, false):
		var cs: CollisionShape3D = n
		if cs.shape == null or not cs.is_inside_tree():
			continue
		if hl.is_ancestor_of(cs) != mine or not cs.get_parent() is PhysicsBody3D:
			continue  # solid bodies only (not the interaction areas)
		out.append(cs.global_transform * cs.shape.get_debug_mesh().get_aabb())
	return out


func test_the_table_stands_clear_on_the_casino_floor() -> void:
	assert_not_null(hl, "the lounge builds a Hi-Lo table")
	var spot: Vector3 = LuckyLounge.STATIONS[SID][1]
	assert_almost_eq(hl.global_position, spot, Vector3.ONE * 0.001)
	assert_eq(hl.seats.size(), 4, "four seats")
	var own: Array[AABB] = _boxes(scene.map, true)
	assert_eq(own.size(), 5, "the table body and four stools")
	for other: AABB in _boxes(scene.map, false):
		for a: AABB in own:
			assert_false(a.grow(-0.02).intersects(other), "Hi-Lo collider %s overlaps %s" % [a, other])
	# The stations around it keep their distance (nobody's stools in anyone's lap). The craps
	# table west of it is 4.3 m long, so 4.5 m between the centres leaves its rail more than half
	# a metre from the Hi-Lo seats; the collider check above is the real overlap test.
	for sid: StringName in scene.map.stations:
		if sid == SID:
			continue
		var d: Vector3 = scene.map.stations[sid].global_position - hl.global_position
		assert_gt(Vector2(d.x, d.z).length(), 4.5, "%s keeps its distance" % sid)
	# The dealer stands on the floor behind the far side, facing the stools.
	var dealer: Node3D = scene.casino_floor.dealers.get(SID, null)
	assert_not_null(dealer, "a dealer at the table")
	if dealer != null:
		assert_almost_eq(dealer.global_position.y, 0.0, 0.05, "on the floor")
		var local: Vector3 = hl.to_local(dealer.global_position)
		assert_lt(local.z, -HiLoStation.RAIL_OUTER - 0.3, "behind the rail")
		assert_lt(absf(local.x), 0.3, "behind the middle")
	assert_true(scene.server.dealers.has(SID), "the server's dealer is there too")


func test_every_seat_is_reachable() -> void:
	var t: float = 0.0
	while not scene.map.navmesh_ready and t < 5.0:
		await wait_seconds(0.2)
		t += 0.2
	assert_true(scene.map.navmesh_ready)
	var nav: RID = scene.map.nav_region.get_navigation_map()
	for i: int in hl.seats.size():
		var stand: Vector3 = hl.to_global(Vector3(HiLoStation.SEAT_XS[i], 0.0, HiLoStation.SEAT_Z + 0.7))
		var path: PackedVector3Array = NavigationServer3D.map_get_path(nav, Vector3(0, 0, 0), stand, true)
		assert_gt(path.size(), 0, "a path to seat %d" % i)
		if path.size() > 0:
			var end: Vector3 = path[path.size() - 1]
			assert_lt(Vector2(end.x - stand.x, end.z - stand.z).length(), 0.6, "it ends behind seat %d" % i)


func test_sit_ante_and_the_cards_land_in_front_of_you() -> void:
	scene.local.teleport(hl.global_position + Vector3(0, 0, 2.3), 0.0)
	await wait_physics_frames(3)
	assert_eq(scene.nearest_station, hl, "the prompt targets the Hi-Lo table")
	assert_string_contains(hl.prompt_text(10), "Hi-Lo")
	scene._on_interact()
	await wait_physics_frames(2)
	assert_eq(scene.local.state, PlayerAvatar.State.SEATED)
	assert_true(scene.current_ui is HiLoUi, "the Hi-Lo panel opens")
	var logic: HiLoLogic = scene.server.stations.logics[SID]
	var seat: int = logic.seats.find(scene.local_id)
	assert_gte(seat, 0)
	var res: Dictionary = Net.send_intent(Intents.make(&"place_bet", {"station": SID, "bet": {"amount": 25}}))
	assert_true(res["ok"], "ante: %s" % res)
	await wait_seconds(0.8)
	var nodes: Array[Node3D] = hl.cards.pile_nodes(seat)
	assert_eq(nodes.size(), 1, "the dealer turned one card up for you")
	if nodes.size() == 1:
		assert_true(bool(nodes[0].get_meta(&"face_up")), "face up")
		assert_almost_eq(nodes[0].position, hl.cards.card_position(seat, 0), Vector3.ONE * 0.01, "on your spot on the felt")
		assert_lt(Vector2(nodes[0].position.x - HiLoStation.card_spot(seat).x, nodes[0].position.z - HiLoStation.card_spot(seat).z).length(), 0.2)
	var ui: HiLoUi = scene.current_ui as HiLoUi
	assert_true(ui.actions.visible, "your call")
	assert_string_contains(ui.higher_btn.text + ui.lower_btn.text, "%", "the buttons carry the odds")
	# Make the call the table would make; whatever comes, the second card lands next to the first.
	var hand: Dictionary = logic.hands[scene.local_id]
	var call: StringName = &"higher" if float(hand["odds"]["higher"]) >= float(hand["odds"]["lower"]) else &"lower"
	assert_true(Net.send_intent(Intents.make(&"action", {"station": SID, "action": call}))["ok"])
	await wait_seconds(0.8)
	assert_eq(hl.cards.pile_nodes(seat).size(), 2, "the next card is dealt beside it")
	# Standing up settles the hand; the result clears the felt a moment later.
	assert_true(Net.send_intent(Intents.make(&"leave"))["ok"])
	await wait_seconds(Registry.balance.hilo_result_time + 1.0)
	assert_eq(hl.cards.pile_nodes(seat).size(), 0, "the cards are swept")


func test_every_seat_camera_sees_its_cards_and_the_dealer() -> void:
	var view := SubViewport.new()
	view.size = Vector2i(1920, 1080)
	view.world_3d = scene.map.get_world_3d()
	add_child_autofree(view)
	var cam := Camera3D.new()
	cam.fov = 75.0
	view.add_child(cam)
	var rect := Rect2(Vector2.ZERO, Vector2(view.size))
	for i: int in hl.seats.size():
		cam.global_transform = hl.camera_for_seat(i).global_transform
		var points: Array[Vector3] = [
			HiLoStation.card_spot(i), HiLoStation.card_spot(i) + Vector3(0.6, 0, 0), HiLoStation.bet_spot(i),
			HiLoStation.DECK_POS, DealerLogic.OFFSETS[&"hilo"] + Vector3(0, 1.4, 0),
		]
		for p: Vector3 in points:
			var g: Vector3 = hl.to_global(p)
			assert_false(cam.is_position_behind(g), "seat %d faces %s" % [i, p])
			assert_true(rect.has_point(cam.unproject_position(g)), "seat %d sees %s" % [i, p])


## The client table on its own (art on): two hands on the felt, the ladder and the pot cards
## follow the state, the deck thins, and a reset clears it all.
func test_the_felt_mirrors_the_state() -> void:
	Vfx.force_enabled = true
	var view := SubViewport.new()
	view.size = Vector2i(640, 360)
	add_child_autofree(view)
	var t := HiLoStation.new()
	view.add_child(t)
	await wait_process_frames(1)
	var hands: Dictionary = {
		7: {"stake": 20, "cards": [Card.make(5), Card.make(9, 1), Card.make(3, 2)], "phase": "play", "rung": 2, "pot": 77, "outcome": ""},
		8: {"stake": 10, "cards": [Card.make(12, 3)], "phase": "play", "rung": 0, "pot": 10, "outcome": ""},
	}
	t.show_round({"seats": [-1, 7, -1, 8], "hands": hands, "deck_left": 26})
	await wait_seconds(1.0)
	assert_eq(t.cards.pile_nodes(1).size(), 3, "seat 2's run of three cards")
	assert_eq(t.cards.pile_nodes(3).size(), 1)
	assert_eq(t.cards.pile_nodes(0).size(), 0, "empty seats have none")
	for i: int in 3:
		var n: Node3D = t.cards.pile_nodes(1)[i]
		assert_almost_eq(n.position, t.cards.card_position(1, i), Vector3.ONE * 0.01, "card %d on the felt" % i)
		assert_almost_eq(n.position.y, HiLoStation.TABLE_TOP + 0.07, 0.07, "lying on the felt, tilted to the seat")
	var lit: Array[int] = []
	for s: int in 4:
		var on: int = 0
		for lamp: MeshInstance3D in t.ladder_lamps[s]:
			if lamp.material_override == t._lamp_on:
				on += 1
		lit.append(on)
	assert_eq(lit, [0, 2, 0, 0] as Array[int], "two steps lit for two right calls")
	assert_eq(t.pot_labels[1].text, "$77")
	assert_eq(t.pot_labels[3].text, "$10")
	assert_eq(t.pot_labels[0].text, "")
	assert_almost_eq(t.deck_stack.scale.y, 0.5, 0.001, "half the deck is gone")
	hands[7]["phase"] = "done"
	hands[7]["outcome"] = "cashed"
	t.show_round({"seats": [-1, 7, -1, 8], "hands": hands, "deck_left": 26})
	assert_eq(t.pot_labels[1].text, "+$77")
	t.reset_table()
	await wait_seconds(0.5)
	assert_eq(t.cards.card_count(), 0, "swept for the minigame")
	assert_eq(t.pot_labels[1].text, "")
	Vfx.force_enabled = false
