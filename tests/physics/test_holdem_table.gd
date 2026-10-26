extends GutTest
## The Casino Hold'em table: on its own, every seat's camera frames the board, the dealer's cards,
## its own hole cards and betting spots and the dealer, all in the left two thirds of a 1920×1080
## screen (the overlay is a column down the right third) and big (0.9.14: "almost the whole screen
## should be the game"); the felt mirrors the public state (hole cards, a folded hand gone, the
## board, the dealer's backs then faces). In the real match scene: it stands on the casino floor
## clear of every other collider with its four stools and its dealer, every seat can be walked to,
## and you can sit down, ante and see your cards land.

const SID: StringName = &"holdem_1"

var view: SubViewport
var hs: HoldemStation


func _station() -> void:
	Vfx.force_enabled = true
	view = SubViewport.new()
	view.size = Vector2i(1920, 1080)
	add_child_autofree(view)
	hs = HoldemStation.new()
	view.add_child(hs)
	await wait_process_frames(1)


func after_each() -> void:
	Vfx.force_enabled = false


func test_every_seat_camera_frames_the_game_left_of_the_overlay() -> void:
	await _station()
	var cam := Camera3D.new()
	cam.fov = 85.0  # the default (Settings "video/fov")
	view.add_child(cam)
	var left := Rect2(Vector2.ZERO, Vector2(view.size.x * 2.0 / 3.0, view.size.y))
	var half: Vector2 = TableCards.CARD_SIZE * 0.5
	assert_eq(hs.seat_cameras.size(), 4, "a view per stool")
	for seat: int in hs.seat_count:
		cam.global_transform = hs.camera_for_seat(seat).global_transform
		var board: Array[Vector3] = []
		for k: int in 5:
			board.append(HoldemStation.board_spot(k) + Vector3(-half.x, 0, 0))
			board.append(HoldemStation.board_spot(k) + Vector3(half.x, 0.12, 0))
		var mine: Array[Vector3] = [HoldemStation.card_spot(seat) + Vector3(-half.x, 0, half.y * 0.5), HoldemStation.card_spot(seat) + Vector3(0.1 + half.x, 0.12, 0)]
		for t: StringName in [HoldemLogic.BONUS, HoldemLogic.ANTE, HoldemLogic.CALL_BET]:
			mine.append(HoldemStation.bet_spot(seat, t) + Vector3(0, 0, HoldemStation.SPOT_R))  # the near edge of every spot
		var dealer: Array[Vector3] = [
			HoldemStation.DEALER_SPOT + Vector3(-0.15, 0.0, 0), HoldemStation.DEALER_SPOT + Vector3(0.35, 0.4, 0),
			DealerLogic.OFFSETS[&"holdem"] + Vector3(0, 1.0, 0), DealerLogic.OFFSETS[&"holdem"] + Vector3(0, 1.75, 0),
		]
		var span := Vector2(INF, -INF)
		var span_y := Vector2(INF, -INF)
		for p: Vector3 in board + mine + dealer:
			var g: Vector3 = hs.to_global(p)
			assert_false(cam.is_position_behind(g), "seat %d faces %s" % [seat, p])
			var at: Vector2 = cam.unproject_position(g)
			assert_true(left.has_point(at), "seat %d sees %s in the left two thirds: %s" % [seat, p, at])
			span = Vector2(minf(span.x, at.x), maxf(span.y, at.x))
			span_y = Vector2(minf(span_y.x, at.y), maxf(span_y.y, at.y))
		var bl: Vector2 = cam.unproject_position(hs.to_global(board[0]))
		var br: Vector2 = cam.unproject_position(hs.to_global(board[9]))
		gut.p("seat %d: game spans %.0f%% × %.0f%% of the screen, the board %.0f%% of its width" % [seat, (span.y - span.x) / view.size.x * 100.0, (span_y.y - span_y.x) / view.size.y * 100.0, (br.x - bl.x) / view.size.x * 100.0])
		# The middle seats' own spots sit under the board, so their span is the narrowest (about a
		# third of the screen against 60 % for the end seats); the height is where the room is.
		assert_gt(span.y - span.x, view.size.x * 0.33, "seat %d: the game fills the left of the screen" % seat)
		assert_gt(span_y.y - span_y.x, view.size.y * 0.7, "seat %d: and most of its height" % seat)
		assert_gt(br.x - bl.x, view.size.x * 0.21, "seat %d: the board is big enough to read" % seat)
	cam.free()


func test_the_felt_mirrors_the_round() -> void:
	await _station()
	var pub: Dictionary = {
		"game": &"holdem", "state": HoldemLogic.State.DECIDING, "seats": [7, 8, -1, 9],
		"hands": {7: {"hole": [Card.make(1), Card.make(1, 2)], "decision": &"", "hand": "Pair of Aces", "ante": 10},
			8: {"hole": [Card.make(5), Card.make(9, 1)], "decision": &"fold", "hand": "Nine High", "ante": 10},
			9: {"hole": [Card.make(13), Card.make(12)], "decision": &"call", "hand": "King High", "ante": 10, "call": 20}},
		"board": [Card.make(2), Card.make(7, 3), Card.make(11, 1)], "dealer": [], "dealer_down": 2,
	}
	hs.show_round(pub)
	await wait_seconds(0.2)
	assert_eq(hs.cards.pile_nodes(0).size(), 2, "seat 1's hole cards")
	assert_eq(hs.cards.pile_nodes(1).size(), 0, "a folded hand goes to the muck")
	assert_eq(hs.cards.pile_nodes(3).size(), 2)
	assert_eq(hs.cards.pile_nodes(HoldemStation.BOARD_KEY).size(), 3, "the flop")
	var dealer: Array[Node3D] = hs.cards.pile_nodes(-1)
	assert_eq(dealer.size(), 2, "the dealer's two cards")
	for n: Node3D in dealer:
		assert_false(bool(n.get_meta(&"face_up")), "face down")
	assert_true(TableCards.is_outlined(hs.cards.pile_nodes(0)[0]), "the hand still deciding is outlined")
	assert_false(TableCards.is_outlined(hs.cards.pile_nodes(3)[0]), "a called hand is not")
	assert_true(hs.hand_labels[0].visible)
	assert_eq(hs.hand_labels[0].text, "Pair of Aces")
	assert_eq(hs.hand_labels[1].text, "FOLD")
	assert_false(hs.hand_labels[2].visible, "an empty seat shows nothing")
	# The showdown: the board fills up and the dealer turns over.
	pub["state"] = HoldemLogic.State.PAYOUT
	(pub["board"] as Array).append_array([Card.make(4), Card.make(4, 1)])
	pub["dealer"] = [Card.make(6), Card.make(8, 2)]
	pub["dealer_down"] = 0
	pub["dealer_hand"] = "Pair of Fours"
	pub["qualifies"] = true
	pub["hands"][9]["outcome"] = &"win"
	hs.show_round(pub)
	await wait_seconds(0.5)
	assert_eq(hs.cards.pile_nodes(HoldemStation.BOARD_KEY).size(), 5)
	for n: Node3D in hs.cards.pile_nodes(-1):
		assert_true(is_equal_approx(n.rotation.z, 0.0), "the dealer's cards turned over")
	assert_true(hs.dealer_label.visible)
	assert_string_contains(hs.dealer_label.text, "Pair of Fours")
	assert_false(TableCards.is_outlined(hs.cards.pile_nodes(0)[0]), "nobody decides any more")
	# The board's cards lie side by side, never on top of each other (once the deal tweens land).
	await wait_seconds(1.0)
	var board: Array[Node3D] = hs.cards.pile_nodes(HoldemStation.BOARD_KEY)
	for k: int in range(1, board.size()):
		assert_gt(board[k].position.x - board[k - 1].position.x, TableCards.CARD_SIZE.x, "card %d clear of card %d" % [k, k - 1])
	hs.reset_table()
	await wait_seconds(0.5)
	assert_eq(hs.cards.card_count(), 0, "swept for a minigame")


func test_in_the_casino_it_stands_clear_and_you_can_play() -> void:
	Net.stop()
	var scene: MatchScene = (load("res://match/match_scene.tscn") as PackedScene).instantiate()
	add_child_autofree(scene)
	scene.server.timescale = 1.0
	await wait_seconds(3.3)
	assert_eq(scene.server.phases.phase, Phase.Id.CASINO, "casino phase after the intro")
	var table: HoldemStation = scene.map.stations.get(SID, null) as HoldemStation
	assert_not_null(table, "the lounge builds a Casino Hold'em table")
	if table == null:
		return
	assert_almost_eq(table.global_position, LuckyLounge.STATIONS[SID][1] as Vector3, Vector3.ONE * 0.001)
	assert_eq(table.seats.size(), 4, "four seats")
	var own: Array[AABB] = []
	var others: Array[AABB] = []
	for n: Node in scene.map.find_children("*", "CollisionShape3D", true, false):
		var c: CollisionShape3D = n
		if c.shape == null or not c.is_inside_tree() or not c.get_parent() is PhysicsBody3D or c.get_parent() is CharacterBody3D or c.get_parent() is RigidBody3D:
			continue
		var box: AABB = c.global_transform * c.shape.get_debug_mesh().get_aabb()
		if table.is_ancestor_of(c):
			own.append(box)
		elif box.size.y >= 0.05:
			others.append(box)
	assert_eq(own.size(), 5, "the table body and four stools")
	for other: AABB in others:
		for a: AABB in own:
			assert_false(a.grow(-0.02).intersects(other), "Casino Hold'em collider %s overlaps %s" % [a, other])
	var dealer: Node3D = scene.casino_floor.dealers.get(SID, null)
	assert_not_null(dealer, "a dealer stands at the table")
	if dealer != null:
		assert_almost_eq(dealer.global_position.y, 0.0, 0.05, "on the floor")
		var local: Vector3 = table.to_local(dealer.global_position)
		assert_lt(local.z, -HoldemStation.RAIL_OUTER - 0.3, "behind the rail")
		assert_lt(absf(local.x), 0.3, "behind the middle")
	# Every stool can be walked to.
	var t: float = 0.0
	while not scene.map.navmesh_ready and t < 5.0:
		await wait_seconds(0.2)
		t += 0.2
	var nav: RID = scene.map.nav_region.get_navigation_map()
	for i: int in table.seats.size():
		var stand: Vector3 = table.to_global(Vector3(HoldemStation.SEAT_XS[i], 0.0, HoldemStation.SEAT_Z + 0.7))
		var path: PackedVector3Array = NavigationServer3D.map_get_path(nav, Vector3(0, 0, 0), stand, true)
		assert_gt(path.size(), 0, "a path to seat %d" % i)
		if path.size() > 0:
			var end: Vector3 = path[path.size() - 1]
			assert_lt(Vector2(end.x - stand.x, end.z - stand.z).length(), 0.6, "it ends behind seat %d" % i)
	# Sit down, ante, and the two hole cards land on your spot.
	scene.local.teleport(table.global_position + table.global_basis * Vector3(0.45, 0, 2.3), 0.0)
	await wait_physics_frames(3)
	assert_eq(scene.nearest_station, table, "the prompt targets the table")
	assert_string_contains(table.prompt_text(10), "Casino Hold'em")
	scene._on_interact()
	await wait_physics_frames(2)
	assert_eq(scene.local.state, PlayerAvatar.State.SEATED)
	assert_true(scene.current_ui is HoldemUi, "the Casino Hold'em overlay opens")
	var logic: HoldemLogic = scene.server.stations.logics[SID]
	var seat: int = logic.seats.find(scene.local_id)
	assert_gte(seat, 0)
	var res: Dictionary = Net.send_intent(Intents.make(&"place_bet", {"station": SID, "bet": {"amount": 20, "bonus": 10}}))
	assert_true(res["ok"], "ante: %s" % res)
	await wait_seconds(Registry.balance.holdem_betting_window + 1.0)
	var nodes: Array[Node3D] = table.cards.pile_nodes(seat)
	assert_eq(nodes.size(), 2, "two hole cards")
	for n: Node3D in nodes:
		assert_true(bool(n.get_meta(&"face_up")))
	assert_eq(table.cards.pile_nodes(HoldemStation.BOARD_KEY).size(), 3, "the flop")
	assert_eq(table.cards.pile_nodes(-1).size(), 2, "the dealer's two, face down")
	var ui: HoldemUi = scene.current_ui as HoldemUi
	assert_true(ui.actions.visible, "your decision")
	assert_ne(ui.hand_label.text, "", "your hand is named")
	assert_true(Net.send_intent(Intents.make(&"action", {"station": SID, "action": &"call"}))["ok"])
	await wait_seconds(1.0)
	assert_eq(table.cards.pile_nodes(HoldemStation.BOARD_KEY).size(), 5, "turn and river")
	assert_ne(ui.result_label.text, "", "the result line")
	assert_true(Net.send_intent(Intents.make(&"leave"))["ok"])
