extends GutTest
## Grab Your Hand (MINIGAME_IDEAS #8): a server-shuffled deck feeds giant cards onto the card hall
## floor (alive + 3, respawned 2 s after the floor runs short), a bean within 0.8 m of a card takes
## it (nearest first, 5 max), the action button drops one (the chosen slot, else the worst card),
## a shove makes the target drop a random card, and after 50 s the best poker hand wins (equal
## hands share a rank).

const STEP: float = 0.05

var cfg: BalanceConfig = BalanceConfig.new()


func _game(players: Array[int], seed_value: int = 7) -> GrabYourHandLogic:
	var g := GrabYourHandLogic.new()
	g.setup(players, SeededRng.new(seed_value), cfg, {}, {})
	g.world = WorldQuery.new()
	_park(g)
	return g


func _run(g: GrabYourHandLogic, seconds: float) -> Array[Dictionary]:
	var seen: Array[Dictionary] = []
	var t: float = 0.0
	while t < seconds - 0.0001:
		g.tick(STEP, 0.0)
		t += STEP
		seen.append_array(g.drain_events())
	return seen


func _of(evs: Array[Dictionary], type: StringName) -> Array[Dictionary]:
	return evs.filter(func(e: Dictionary) -> bool: return e["type"] == type)


## Everyone stands on a row of spots by the gallery rail, far from where we test.
func _park(g: GrabYourHandLogic) -> void:
	var o: Vector3 = WalkableLogicBase.ROOM_ORIGIN
	for i: int in g.players.size():
		g.world.set_transform(g.players[i], o + Vector3(-7.0 + 1.5 * float(i), 0, 6.85), 0.0)


## Clears the floor and lays exactly the given cards ([card, local pos]) for a controlled test.
func _lay(g: GrabYourHandLogic, cards: Array) -> Array[int]:
	for fid: int in g.floor_cards.keys():
		g.deck.append(int(g.floor_cards[fid]["card"]))
	g.floor_cards.clear()
	g.respawns.clear()
	var ids: Array[int] = []
	for c: Array in cards:
		g.deck.erase(int(c[0]))
		var f: Dictionary = g._put_on_floor(int(c[0]), WalkableLogicBase.ROOM_ORIGIN + (c[1] as Vector3), -1)
		ids.append(int(f["id"]))
	return ids


func _at(g: GrabYourHandLogic, p: int, local: Vector3, yaw: float = 0.0) -> void:
	g.world.set_transform(p, WalkableLogicBase.ROOM_ORIGIN + local, yaw)


func _drop(g: GrabYourHandLogic, p: int, slot: int = -1) -> Dictionary:
	var intent: Dictionary = {"type": &"minigame_action", "kind": "drop"}
	if slot >= 0:
		intent["target"] = slot
	return g.submit(p, intent, 0.0)


func _all_cards(g: GrabYourHandLogic) -> Array[int]:
	var all: Array[int] = []
	all.append_array(g.deck)
	for f: Dictionary in g.floor_cards.values():
		all.append(int(f["card"]))
	for p: int in g.hands:
		all.append_array(g.hand_of(p))
	return all


func test_setup_in_the_card_hall_and_first_tick_deals_the_floor() -> void:
	var g: GrabYourHandLogic = _game([1, 2, 3, 4])
	assert_eq(g.id, &"grab_your_hand")
	assert_eq(g.blocked_intents(), [&"grab"] as Array[StringName], "grab is off, shove stays")
	for p: int in [1, 2, 3, 4]:
		assert_true(g.arena.has_point(g.spawn_for(p)), "spawn in the hall")
	assert_eq(g.deck.size(), 52)
	var evs: Array[Dictionary] = _run(g, STEP)
	assert_eq(_of(evs, &"grab_your_hand_begin").size(), 1, "announced on the first tick")
	var spawned: Array[Dictionary] = _of(evs, &"grab_your_hand_spawned")
	assert_eq(spawned.size(), 1)
	assert_eq((spawned[0]["cards"] as Array).size(), 7, "players + 3 on the floor")
	assert_eq(g.floor_cards.size(), 7)
	assert_eq(g.deck.size(), 45)
	for f: Dictionary in g.floor_cards.values():
		assert_true(CardHall.in_field(f["pos"]), "cards land in the field: %s" % f["pos"])
	var all: Array[int] = _all_cards(g)
	all.sort()
	var full: Array[int] = []
	for c: int in 52:
		full.append(c)
	assert_eq(all, full, "every card exactly once")
	var st: Dictionary = g.get_public_state()
	for key: String in ["clock", "seconds", "floor", "hands", "names", "alive", "room", "state"]:
		assert_true(st.has(key), "state carries %s for a late stage" % key)


func test_deck_is_shuffled_by_the_seed() -> void:
	var a: GrabYourHandLogic = _game([1, 2], 3)
	var b: GrabYourHandLogic = _game([1, 2], 3)
	var c: GrabYourHandLogic = _game([1, 2], 4)
	assert_eq(a.deck, b.deck, "same seed, same deck")
	assert_ne(a.deck, c.deck, "another seed, another deck")


func test_pickup_needs_reach() -> void:
	var g: GrabYourHandLogic = _game([1, 2])
	_run(g, STEP)
	var card: int = g.deck[0]
	var ids: Array[int] = _lay(g, [[card, Vector3(4, 0, 3)]])
	_at(g, 1, Vector3(4 + GrabYourHandLogic.PICK_REACH + 0.1, 0, 3))
	_run(g, STEP)
	assert_true(g.floor_cards.has(ids[0]), "just out of reach: still on the floor")
	_at(g, 1, Vector3(4 + 0.6, 0, 3))
	var evs: Array[Dictionary] = _run(g, STEP)
	assert_false(g.floor_cards.has(ids[0]))
	assert_eq(g.hand_of(1), [card] as Array[int])
	var picked: Array[Dictionary] = _of(evs, &"grab_your_hand_picked")
	assert_eq(picked.size(), 1)
	assert_eq(int(picked[0]["player"]), 1)
	assert_eq(int(picked[0]["card"]), card)
	assert_eq(int(g.get_public_state()["hands"][1][0]), card, "hands are public")


func test_nearest_bean_wins_the_card() -> void:
	var g: GrabYourHandLogic = _game([1, 2, 3])
	_run(g, STEP)
	var ids: Array[int] = _lay(g, [[g.deck[0], Vector3(-4, 0, 3)]])
	_at(g, 1, Vector3(-4 + 0.7, 0, 3))
	_at(g, 2, Vector3(-4 - 0.3, 0, 3))
	_at(g, 3, Vector3(-4, 0, 3 + 0.5))
	_run(g, STEP)
	assert_false(g.floor_cards.has(ids[0]))
	assert_eq(g.hand_of(2).size(), 1, "the nearest bean takes it")
	assert_eq(g.hand_of(1).size(), 0)
	assert_eq(g.hand_of(3).size(), 0)


func test_hand_limit_is_five() -> void:
	var g: GrabYourHandLogic = _game([1, 2])
	_run(g, STEP)
	var cards: Array = []
	for i: int in 6:
		cards.append([g.deck[i], Vector3(-5 + 0.25 * float(i), 0, -3)])
	_lay(g, cards)
	_at(g, 1, Vector3(-4.4, 0, -3))
	_run(g, STEP)
	assert_eq(g.hand_of(1).size(), GrabYourHandLogic.HAND_MAX, "five cards, no more")
	assert_eq(g.floor_cards.size(), 1, "the sixth stays on the floor")
	_run(g, 0.5)
	assert_eq(g.hand_of(1).size(), 5, "a full hand walks over cards")


func test_drop_lays_the_chosen_card_in_front_and_anyone_can_take_it() -> void:
	var g: GrabYourHandLogic = _game([1, 2])
	_run(g, STEP)
	g.hands[1] = [Card.make(13, 0), Card.make(4, 1), Card.make(13, 2)]
	g.floor_cards.clear()
	g.respawns.clear()
	_at(g, 1, Vector3(-4, 0, 3), 0.0)  # yaw 0 faces -z
	var res: Dictionary = _drop(g, 1, 0)
	assert_true(res["ok"], "drop: %s" % res)
	assert_eq(int(res["card"]), Card.make(13, 0), "the chosen slot")
	assert_eq(g.hand_of(1), [Card.make(4, 1), Card.make(13, 2)] as Array[int])
	var f: Dictionary = g.floor_cards[int(res["id"])]
	var at: Vector3 = f["pos"]
	assert_almost_eq(at.z - WalkableLogicBase.ROOM_ORIGIN.z, 3.0 - GrabYourHandLogic.DROP_DISTANCE, 0.01, "in front of the bean")
	var evs: Array[Dictionary] = g.drain_events()
	assert_eq(_of(evs, &"grab_your_hand_dropped").size(), 1)
	# The dropper can't take it straight back, anyone else can.
	_at(g, 1, at - WalkableLogicBase.ROOM_ORIGIN)
	_run(g, STEP)
	assert_true(g.floor_cards.has(int(res["id"])), "no instant pick-back")
	_park(g)
	_at(g, 2, at - WalkableLogicBase.ROOM_ORIGIN + Vector3(0.3, 0, 0))
	_run(g, STEP)
	assert_eq(g.hand_of(2), [Card.make(13, 0)] as Array[int], "the other bean takes it")


func test_drop_defaults_to_the_worst_card_and_needs_a_card() -> void:
	var g: GrabYourHandLogic = _game([1, 2])
	_run(g, STEP)
	assert_eq(_drop(g, 1)["error"], &"empty_hand")
	g.hands[1] = [Card.make(9, 0), Card.make(2, 1), Card.make(9, 2)]
	var res: Dictionary = _drop(g, 1)
	assert_true(res["ok"])
	assert_eq(int(res["card"]), Card.make(2, 1), "the pair stays, the 2 goes")
	assert_eq(_drop(g, 1, 9)["ok"], true, "a stale slot falls back to the worst card")
	assert_eq(g.submit(1, {"type": &"minigame_action", "kind": "steal"}, 0.0)["error"], &"bad_value")


func test_shove_drops_a_random_card_away_from_the_attacker() -> void:
	var g: GrabYourHandLogic = _game([1, 2])
	_run(g, STEP)
	g.floor_cards.clear()
	g.respawns.clear()
	g.hands[2] = [Card.make(1, 0), Card.make(1, 1)]
	_at(g, 1, Vector3(0, 0, 4))
	_at(g, 2, Vector3(0, 0, 3))
	g.on_shoved(2, 1)
	assert_eq(g.hand_of(2).size(), 1, "one card out")
	assert_eq(g.floor_cards.size(), 1)
	var f: Dictionary = g.floor_cards.values()[0]
	assert_true(int(f["card"]) in [Card.make(1, 0), Card.make(1, 1)])
	assert_lt((f["pos"] as Vector3).z - WalkableLogicBase.ROOM_ORIGIN.z, 3.0, "flung away from the attacker")
	var ev: Dictionary = _of(g.drain_events(), &"grab_your_hand_dropped")[0]
	assert_eq(StringName(ev["how"]), &"shove")
	assert_eq(int(ev["attacker"]), 1)
	g.on_shoved(1, 2)
	assert_eq(g.floor_cards.size(), 1, "an empty hand drops nothing")


func test_floor_respawns_after_a_pickup() -> void:
	var g: GrabYourHandLogic = _game([1, 2])
	_run(g, STEP)
	assert_eq(g.floor_cards.size(), 5)
	var fid: int = g.floor_cards.keys()[0]
	_at(g, 1, g.floor_cards[fid]["pos"] - WalkableLogicBase.ROOM_ORIGIN)
	_run(g, STEP)
	assert_eq(g.floor_cards.size(), 4, "picked up")
	_park(g)
	_run(g, GrabYourHandLogic.RESPAWN_DELAY - 0.3)
	assert_eq(g.floor_cards.size(), 4, "not yet")
	var evs: Array[Dictionary] = _run(g, 0.5)
	assert_eq(g.floor_cards.size(), 5, "a new card after the delay")
	assert_eq(_of(evs, &"grab_your_hand_spawned").size(), 1)
	var all: Array[int] = _all_cards(g)
	var uniq: Dictionary = {}
	for c: int in all:
		uniq[c] = true
	assert_eq(uniq.size(), 52, "still no card twice")
	assert_eq(all.size(), 52)


func test_ends_after_fifty_seconds_best_hand_wins() -> void:
	var g: GrabYourHandLogic = _game([1, 2, 3])
	_run(g, STEP)
	g.floor_cards.clear()
	g.deck.clear()  # nothing more on the floor: the hands stay as set
	g.respawns.clear()
	g.hands[1] = [Card.make(5, 0), Card.make(5, 1)]
	g.hands[2] = [Card.make(9, 0), Card.make(9, 1), Card.make(9, 2)]
	g.hands[3] = [Card.make(1, 0), Card.make(13, 1)]
	var evs: Array[Dictionary] = _run(g, GrabYourHandLogic.GAME_SECONDS - 1.0)
	assert_eq(_of(evs, &"grab_your_hand_over").size(), 0, "still playing")
	evs = _run(g, 1.2)
	var over: Array[Dictionary] = _of(evs, &"grab_your_hand_over")
	assert_eq(over.size(), 1, "time")
	assert_eq(g.state, GrabYourHandLogic.State.REVEAL)
	assert_eq(_drop(g, 1)["error"], &"game_over")
	var r: Array[Dictionary] = g.ranking()
	assert_eq(int(r[0]["player"]), 2, "trips win")
	assert_eq(str(r[0]["name"]), "THREE OF A KIND")
	assert_eq(int(r[1]["player"]), 1, "a pair beats ace-king high")
	assert_eq(int(r[2]["player"]), 3)
	assert_eq([int(r[0]["rank"]), int(r[1]["rank"]), int(r[2]["rank"])], [1, 2, 3])
	assert_eq(int(r[0]["points"]), 2, "points = players beaten")
	assert_false(g.finished, "the hands stay up a moment")
	evs = _run(g, GrabYourHandLogic.END_HOLD + 0.1)
	assert_true(g.finished)
	assert_eq(_of(evs, &"grab_your_hand_finished").size(), 1)


func test_highest_card_breaks_and_equal_hands_tie() -> void:
	var g: GrabYourHandLogic = _game([1, 2, 3, 4])
	g.hands[1] = [Card.make(8, 0), Card.make(8, 1), Card.make(12, 2)]
	g.hands[2] = [Card.make(8, 2), Card.make(8, 3), Card.make(13, 0)]
	g.hands[3] = [Card.make(8, 2), Card.make(8, 3), Card.make(12, 0)]  # same ranks as 1
	g.hands[4] = []
	var r: Array[Dictionary] = g.ranking()
	assert_eq(int(r[0]["player"]), 2, "pair of 8s with a king beats with a queen")
	assert_eq(int(r[0]["rank"]), 1)
	assert_eq(int(r[1]["rank"]), 2)
	assert_eq(int(r[2]["rank"]), 2, "equal hands share a rank")
	assert_eq([int(r[1]["player"]), int(r[2]["player"])], [1, 3])
	assert_eq(int(r[3]["player"]), 4, "no cards is last")
	assert_eq(int(r[3]["rank"]), 4)
	assert_eq(int(r[1]["points"]), int(r[2]["points"]))


func test_dropout_returns_cards_to_the_deck() -> void:
	var g: GrabYourHandLogic = _game([1, 2, 3])
	_run(g, STEP)
	var ids: Array[int] = _lay(g, [[g.deck[0], Vector3(5, 0, -3)]])
	var card: int = int(g.floor_cards[ids[0]]["card"])
	_at(g, 3, Vector3(5, 0, -3))
	_run(g, STEP)
	assert_eq(g.hand_of(3), [card] as Array[int])
	g.remove_player(3)
	assert_false(3 in g.players)
	assert_false(g.hands.has(3))
	assert_true(card in g.deck, "back in the deck")
	var evs: Array[Dictionary] = g.drain_events()
	assert_eq(_of(evs, &"minigame_eliminated").size(), 1)
	for row: Dictionary in g.ranking():
		assert_ne(int(row["player"]), 3, "out of the ranking")
	assert_eq(g.state, GrabYourHandLogic.State.PLAYING, "two left: play on")
	g.remove_player(2)
	assert_eq(g.state, GrabYourHandLogic.State.REVEAL, "one left: the hands are shown")


func test_two_player_game() -> void:
	var g: GrabYourHandLogic = _game([5, 9], 11)
	var evs: Array[Dictionary] = _run(g, STEP)
	assert_eq(g.floor_cards.size(), 5, "2 + 3 on the floor")
	assert_eq(_of(evs, &"grab_your_hand_spawned").size(), 1)
	# 5 walks over every card on the floor in turn.
	for fid: int in g.floor_cards.keys():
		if g.floor_cards.has(fid):
			_at(g, 5, g.floor_cards[fid]["pos"] - WalkableLogicBase.ROOM_ORIGIN)
			_run(g, STEP)
	assert_eq(g.hand_of(5).size(), 5)
	_park(g)
	_run(g, GrabYourHandLogic.GAME_SECONDS + GrabYourHandLogic.END_HOLD + 0.5)
	assert_true(g.finished)
	var r: Array[Dictionary] = g.ranking()
	assert_eq(int(r[0]["player"]), 5, "five cards beat none")
	assert_eq(int(r[1]["player"]), 9)
