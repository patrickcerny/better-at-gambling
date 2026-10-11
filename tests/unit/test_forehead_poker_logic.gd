extends GutTest
## Forehead Poker rules: the round flow, dealing, your own card never reaching you (private
## state, public state and events) before the showdown, STAY / FOLD as validated intents (no
## answer = fold), the showdown scoring incl. ties and everyone folding, ranking and ties,
## players dropping out, 2-player games and the late-join snapshot.

var logic: ForeheadPokerLogic


func _make(ids: Array[int], seed_value: int = 11) -> ForeheadPokerLogic:
	var g := ForeheadPokerLogic.new()
	g.setup(ids, SeededRng.new(seed_value), BalanceConfig.new(), {}, {})
	return g


func before_each() -> void:
	logic = _make([1, 2, 3])


func _types(evs: Array[Dictionary]) -> Array[StringName]:
	var out: Array[StringName] = []
	for e: Dictionary in evs:
		out.append(e["type"])
	return out


## Intro (or the last showdown) → deal → talk → decide.
func _to_decide(g: ForeheadPokerLogic) -> void:
	if g.phase == ForeheadPokerLogic.Step.INTRO:
		g.tick(ForeheadPokerLogic.INTRO_TIME + 0.01, 0.0)
	if g.phase == ForeheadPokerLogic.Step.SHOWDOWN:
		g.tick(ForeheadPokerLogic.SHOWDOWN_TIME + 0.01, 0.0)
	assert_eq(g.phase, ForeheadPokerLogic.Step.DEAL)
	g.tick(ForeheadPokerLogic.DEAL_TIME + 0.01, 0.0)
	assert_eq(g.phase, ForeheadPokerLogic.Step.TALK)
	g.tick(ForeheadPokerLogic.TALK_TIME + 0.01, 0.0)
	assert_eq(g.phase, ForeheadPokerLogic.Step.DECIDE)


func _act(g: ForeheadPokerLogic, p: int, action: String) -> Dictionary:
	return g.submit(p, {"action": action, "round": g.round_index}, 0.0)


## Plays the open decide window to the showdown with forced cards.
func _showdown_with(g: ForeheadPokerLogic, hand: Dictionary, picks: Dictionary) -> Dictionary:
	for p: Variant in hand:
		g.cards[int(p)] = int(hand[p])
	for p: Variant in picks:
		assert_true(_act(g, int(p), String(picks[p]))["ok"])
	g.tick(ForeheadPokerLogic.DECIDE_TIME + 0.01, 0.0)
	assert_eq(g.phase, ForeheadPokerLogic.Step.SHOWDOWN)
	return g.last_showdown


# --- Flow and dealing ----------------------------------------------------------------------------

func test_round_flow_and_five_rounds() -> void:
	assert_eq(_types(logic.drain_events()), [&"forehead_poker_started"] as Array[StringName])
	for r: int in ForeheadPokerLogic.ROUNDS:
		_to_decide(logic)
		assert_eq(logic.round_index, r)
		logic.tick(ForeheadPokerLogic.DECIDE_TIME + 0.01, 0.0)
		assert_eq(logic.phase, ForeheadPokerLogic.Step.SHOWDOWN)
	var types: Array[StringName] = _types(logic.drain_events())
	assert_eq(types.count(&"forehead_poker_deal"), 5)
	assert_eq(types.count(&"forehead_poker_talk"), 5)
	assert_eq(types.count(&"forehead_poker_decide"), 5)
	assert_eq(types.count(&"forehead_poker_showdown"), 5)
	logic.tick(ForeheadPokerLogic.SHOWDOWN_TIME + 0.01, 0.0)
	assert_eq(logic.phase, ForeheadPokerLogic.Step.OUTRO)
	assert_eq(_types(logic.drain_events()), [&"forehead_poker_over"] as Array[StringName])
	logic.tick(ForeheadPokerLogic.OUTRO_TIME + 0.01, 0.0)
	assert_true(logic.is_finished())


func test_every_player_gets_a_different_card_each_round() -> void:
	logic.tick(ForeheadPokerLogic.INTRO_TIME + 0.01, 0.0)
	assert_eq(logic.cards.size(), 3)
	var seen: Dictionary = {}
	for p: int in logic.cards:
		assert_between(logic.cards[p], 0, 51)
		seen[logic.cards[p]] = true
	assert_eq(seen.size(), 3, "one deck: no two foreheads show the same card")
	var first: Dictionary = logic.cards.duplicate()
	_to_decide(logic)
	logic.tick(ForeheadPokerLogic.DECIDE_TIME + 0.01, 0.0)
	logic.tick(ForeheadPokerLogic.SHOWDOWN_TIME + 0.01, 0.0)
	assert_eq(logic.round_index, 1)
	assert_ne(logic.cards, first, "a fresh deal every round")


func test_talk_lasts_fifteen_seconds_and_answers_wait_for_the_window() -> void:
	logic.tick(ForeheadPokerLogic.INTRO_TIME + 0.01, 0.0)
	assert_eq(_act(logic, 1, ForeheadPokerLogic.STAY)["error"], &"too_late", "no answers while dealing")
	logic.tick(ForeheadPokerLogic.DEAL_TIME + 0.01, 0.0)
	assert_eq(logic.phase, ForeheadPokerLogic.Step.TALK)
	assert_almost_eq(logic.timer, 15.0, 0.01)
	assert_eq(_act(logic, 1, ForeheadPokerLogic.STAY)["error"], &"too_late", "no answers while talking")
	logic.tick(14.0, 0.0)
	assert_eq(logic.phase, ForeheadPokerLogic.Step.TALK)


# --- Secrecy -------------------------------------------------------------------------------------

func test_private_state_shows_the_others_cards_but_never_your_own() -> void:
	logic.tick(ForeheadPokerLogic.INTRO_TIME + 0.01, 0.0)
	for me: int in [1, 2, 3]:
		var priv: Dictionary = logic.private_state(me)
		var seen: Dictionary = priv["cards"]
		assert_false(seen.has(me), "player %d never gets their own card" % me)
		assert_eq(seen.size(), 2)
		for p: Variant in seen:
			assert_eq(int(seen[p]), logic.cards[int(p)])
		assert_false(logic.cards[me] in seen.values(), "nor its value under another name")
		assert_eq(priv.keys().filter(func(k: Variant) -> bool: return k not in ["round", "cards", "can_act", "choice"]), [], "nothing else in it")


func test_no_card_in_public_state_or_events_before_the_showdown() -> void:
	var evs: Array[Dictionary] = logic.drain_events()
	logic.tick(ForeheadPokerLogic.INTRO_TIME + 0.01, 0.0)
	evs.append_array(logic.drain_events())
	var states: Array[Dictionary] = [logic.get_public_state()]
	logic.tick(ForeheadPokerLogic.DEAL_TIME + 0.01, 0.0)
	evs.append_array(logic.drain_events())
	states.append(logic.get_public_state())
	logic.tick(ForeheadPokerLogic.TALK_TIME + 0.01, 0.0)
	_act(logic, 1, ForeheadPokerLogic.STAY)
	_act(logic, 2, ForeheadPokerLogic.FOLD)
	evs.append_array(logic.drain_events())
	states.append(logic.get_public_state())
	for st: Dictionary in states:
		assert_false(st.has("cards"), "public state carries no cards")
		assert_false(st.has("showdown"))
		assert_false(st.has("choices"), "nor anyone's answer")
	for e: Dictionary in evs:
		assert_false(e.has("cards"), "%s carries no cards" % e["type"])
		assert_false(e.has("action"), "%s carries no answer" % e["type"])
	# The showdown names every card and every answer.
	logic.tick(ForeheadPokerLogic.DECIDE_TIME + 0.01, 0.0)
	var sd: Dictionary = logic.drain_events().back()
	assert_eq(sd["type"], &"forehead_poker_showdown")
	assert_eq((sd["cards"] as Dictionary).size(), 3)
	assert_eq(logic.get_public_state()["showdown"]["cards"], sd["cards"])


func test_spectator_private_state_has_every_card() -> void:
	logic.tick(ForeheadPokerLogic.INTRO_TIME + 0.01, 0.0)
	assert_eq((logic.private_state(99)["cards"] as Dictionary).size(), 3)
	assert_false(logic.private_state(99)["can_act"])


# --- Answers -------------------------------------------------------------------------------------

func test_answers_are_validated() -> void:
	_to_decide(logic)
	assert_eq(logic.submit(9, {"action": ForeheadPokerLogic.STAY}, 0.0)["error"], &"not_in_minigame")
	assert_eq(logic.submit(1, {"action": "raise"}, 0.0)["error"], &"bad_value")
	assert_eq(logic.submit(1, {"action": ForeheadPokerLogic.STAY, "round": 3}, 0.0)["error"], &"too_late", "an answer for another round")
	assert_true(_act(logic, 1, ForeheadPokerLogic.STAY)["ok"])
	assert_eq(_act(logic, 1, ForeheadPokerLogic.FOLD)["error"], &"already_picked", "once per round")
	assert_eq(logic.private_state(1)["choice"], ForeheadPokerLogic.STAY)
	assert_false(logic.private_state(1)["can_act"])
	assert_true(logic.private_state(2)["can_act"])
	var ev: Dictionary = logic.drain_events().back()
	assert_eq(ev["type"], &"forehead_poker_decided")
	assert_eq(int(ev["player"]), 1)


func test_window_closes_early_once_everyone_answered() -> void:
	_to_decide(logic)
	for p: int in [1, 2, 3]:
		_act(logic, p, ForeheadPokerLogic.FOLD)
	logic.tick(0.05, 0.0)
	assert_eq(logic.phase, ForeheadPokerLogic.Step.SHOWDOWN)


func test_no_answer_is_a_fold() -> void:
	_to_decide(logic)
	var sd: Dictionary = _showdown_with(logic, {1: Card.make(13), 2: Card.make(5), 3: Card.make(2)}, {2: ForeheadPokerLogic.STAY, 3: ForeheadPokerLogic.STAY})
	assert_eq(sd["choices"][1], ForeheadPokerLogic.FOLD, "player 1 never answered")
	assert_eq(sd["points"][1], 0)
	assert_eq(sd["winners"], [2])


# --- Scoring -------------------------------------------------------------------------------------

func test_highest_stayer_takes_one_point_per_stayer() -> void:
	_to_decide(logic)
	var sd: Dictionary = _showdown_with(logic, {1: Card.make(9), 2: Card.make(12), 3: Card.make(4)}, {1: ForeheadPokerLogic.STAY, 2: ForeheadPokerLogic.STAY, 3: ForeheadPokerLogic.STAY})
	assert_eq(sd["winners"], [2])
	assert_eq(sd["points"], {1: -1, 2: 3, 3: -1})
	assert_eq(logic.points, {1: -1, 2: 3, 3: -1} as Dictionary[int, int])


func test_folders_score_zero_even_with_the_best_card() -> void:
	_to_decide(logic)
	var sd: Dictionary = _showdown_with(logic, {1: Card.make(1), 2: Card.make(7), 3: Card.make(4)}, {1: ForeheadPokerLogic.FOLD, 2: ForeheadPokerLogic.STAY, 3: ForeheadPokerLogic.STAY})
	assert_eq(sd["points"], {1: 0, 2: 2, 3: -1})


func test_aces_are_high_and_suits_do_not_count() -> void:
	assert_gt(ForeheadPokerLogic.strength(Card.make(1, 0)), ForeheadPokerLogic.strength(Card.make(13, 0)))
	assert_eq(ForeheadPokerLogic.strength(Card.make(10, 0)), ForeheadPokerLogic.strength(Card.make(10, 3)))
	assert_eq(ForeheadPokerLogic.strength(Card.make(2, 2)), 2)


func test_a_lone_stayer_wins_one() -> void:
	_to_decide(logic)
	var sd: Dictionary = _showdown_with(logic, {1: Card.make(2), 2: Card.make(7), 3: Card.make(13)}, {1: ForeheadPokerLogic.STAY, 2: ForeheadPokerLogic.FOLD, 3: ForeheadPokerLogic.FOLD})
	assert_eq(sd["points"], {1: 1, 2: 0, 3: 0}, "a 2 wins when nobody else dares")


func test_equal_top_cards_split_the_pot_rounding_down() -> void:
	var g := _make([1, 2, 3, 4])
	_to_decide(g)
	# Three stayers, two share the top rank (different suits): 3 / 2 = 1 each, the third loses 1.
	var sd: Dictionary = _showdown_with(g, {1: Card.make(11, 0), 2: Card.make(11, 2), 3: Card.make(6), 4: Card.make(3)}, {1: ForeheadPokerLogic.STAY, 2: ForeheadPokerLogic.STAY, 3: ForeheadPokerLogic.STAY})
	assert_eq(sd["winners"], [1, 2])
	assert_eq(sd["points"], {1: 1, 2: 1, 3: -1, 4: 0})
	assert_eq(int(sd["pot"]), 3)
	assert_eq(int(sd["share"]), 1)


func test_everyone_folding_scores_nothing() -> void:
	_to_decide(logic)
	var sd: Dictionary = _showdown_with(logic, {1: Card.make(2), 2: Card.make(7), 3: Card.make(13)}, {1: ForeheadPokerLogic.FOLD, 2: ForeheadPokerLogic.FOLD, 3: ForeheadPokerLogic.FOLD})
	assert_eq(sd["winners"], [])
	assert_eq(sd["points"], {1: 0, 2: 0, 3: 0})


# --- Ranking -------------------------------------------------------------------------------------

func _finish(g: ForeheadPokerLogic) -> void:
	while g.phase != ForeheadPokerLogic.Step.OUTRO:
		g.tick(maxf(g.timer, 0.0) + 0.01, 0.0)


func test_ranking_by_total_points_with_shared_ranks() -> void:
	var g := _make([1, 2, 3, 4])
	_to_decide(g)
	_showdown_with(g, {1: Card.make(13), 2: Card.make(12), 3: Card.make(13, 1), 4: Card.make(2)}, {1: ForeheadPokerLogic.STAY, 2: ForeheadPokerLogic.STAY, 3: ForeheadPokerLogic.STAY})
	# 1 and 3 split (3 / 2 = 1 each), 2 loses 1, 4 folded.
	_finish(g)
	var rows: Array[Dictionary] = g.ranking()
	assert_eq(rows.size(), 4)
	assert_eq([rows[0]["player"], rows[1]["player"]], [1, 3])
	assert_eq([rows[0]["rank"], rows[1]["rank"]], [1, 1], "equal totals share the rank")
	assert_eq(rows[2]["player"], 4)
	assert_eq(rows[2]["rank"], 3)
	assert_eq(rows[3]["player"], 2)
	assert_eq(rows[3]["points"], -1)


func test_two_players() -> void:
	var g := _make([5, 6])
	_to_decide(g)
	assert_eq((g.private_state(5)["cards"] as Dictionary).keys(), [6])
	assert_eq((g.private_state(6)["cards"] as Dictionary).keys(), [5])
	var sd: Dictionary = _showdown_with(g, {5: Card.make(8), 6: Card.make(3)}, {5: ForeheadPokerLogic.STAY, 6: ForeheadPokerLogic.STAY})
	assert_eq(sd["points"], {5: 2, 6: -1})
	_finish(g)
	assert_eq(g.ranking()[0]["player"], 5)


func test_a_player_dropping_out_leaves_the_round_and_the_ranking() -> void:
	_to_decide(logic)
	logic.remove_player(2)
	assert_false(logic.cards.has(2), "their card is out of the open round")
	assert_false((logic.private_state(1)["cards"] as Dictionary).has(2))
	var sd: Dictionary = _showdown_with(logic, {1: Card.make(4), 3: Card.make(9)}, {1: ForeheadPokerLogic.STAY, 3: ForeheadPokerLogic.STAY})
	assert_false((sd["cards"] as Dictionary).has(2))
	assert_eq(sd["points"], {1: -1, 3: 2})
	_finish(logic)
	var ids: Array = []
	for row: Dictionary in logic.ranking():
		ids.append(row["player"])
	assert_eq(ids, [3, 1])


func test_everyone_dropping_out_ends_the_game() -> void:
	_to_decide(logic)
	for p: int in [1, 2, 3]:
		logic.remove_player(p)
	logic.tick(0.1, 0.0)
	assert_eq(logic.phase, ForeheadPokerLogic.Step.OUTRO)
	assert_eq(logic.ranking(), [] as Array[Dictionary])


func test_late_join_snapshot() -> void:
	_to_decide(logic)
	_act(logic, 3, ForeheadPokerLogic.STAY)
	var st: Dictionary = logic.get_public_state()
	assert_eq(st["minigame"], &"forehead_poker")
	assert_eq(st["phase"], "decide")
	assert_eq(int(st["round"]), 0)
	assert_eq(int(st["rounds"]), 5)
	assert_eq(st["decided"], [3])
	assert_eq(st["players"], [1, 2, 3])
	assert_almost_eq(float(st["phase_time"]), ForeheadPokerLogic.DECIDE_TIME, 0.001)
	assert_false(st.has("cards"))
	logic.tick(ForeheadPokerLogic.DECIDE_TIME + 0.01, 0.0)
	st = logic.get_public_state()
	assert_eq(st["phase"], "showdown")
	assert_eq(st["showdown"]["choices"][3], ForeheadPokerLogic.STAY)
	_finish(logic)
	st = logic.get_public_state()
	assert_eq(st["phase"], "over")
	assert_true(st.has("ranking"))
