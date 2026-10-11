extends GutTest
## Spy rules: spy counts, the secret word only in civilians' private state (category for spies,
## the hint after 60 s), clue turns in seat order with timeouts and sanitising, calling and
## casting votes (majority with at least half, ties), the group losing on a wrong vote and winning
## when every spy is out, the spies winning on the clock, the extra clue round, ranking tiers,
## dropouts, the late-join snapshot and 4- and 8-player tables (2-3 never happen but must not crash).

const WORDS: Array = [{"word": "Vault", "category": "Places", "hint": "A thick steel door"}]


func _make(n: int, seed_value: int = 5) -> SpyLogic:
	var ids: Array[int] = []
	for i: int in n:
		ids.append(i + 1)
	var g := SpyLogic.new()
	g.setup(ids, SeededRng.new(seed_value), BalanceConfig.new(), {}, {"spy_words": WORDS})
	return g


## Past the intro: the first clue turn is up.
func _started(n: int, seed_value: int = 5) -> SpyLogic:
	var g: SpyLogic = _make(n, seed_value)
	g.tick(SpyLogic.INTRO_TIME + 0.01, 0.0)
	assert_eq(g.phase, SpyLogic.Step.CLUES)
	return g


func _types(evs: Array[Dictionary]) -> Array[StringName]:
	var out: Array[StringName] = []
	for e: Dictionary in evs:
		out.append(e["type"])
	return out


func _civilians(g: SpyLogic) -> Array[int]:
	var out: Array[int] = []
	for p: int in g.alive():
		if not g.is_spy(p):
			out.append(p)
	return out


func _clue(g: SpyLogic, p: int, text: String) -> Dictionary:
	return g.submit(p, {"type": &"spy_clue", "text": text}, 0.0)


func _call(g: SpyLogic, p: int) -> Dictionary:
	return g.submit(p, {"type": &"spy_call_vote"}, 0.0)


func _vote(g: SpyLogic, p: int, target: int) -> Dictionary:
	return g.submit(p, {"type": &"spy_vote", "target": target}, 0.0)


## Everyone still in votes for `target` (who votes for someone else); resolves the vote.
func _vote_out(g: SpyLogic, target: int) -> void:
	assert_true(_call(g, _civilians(g)[0] if _civilians(g)[0] != target else _civilians(g)[1])["ok"])
	var other: int = -1
	for p: int in g.alive():
		if p != target:
			other = p
			break
	for p: int in g.alive():
		assert_true(_vote(g, p, target if p != target else other)["ok"], "vote by %d" % p)
	g.tick(0.05, 0.0)
	assert_eq(g.phase, SpyLogic.Step.REVEAL)


# --- Setup and secrecy ---------------------------------------------------------------------------

func test_spy_count_by_table_size() -> void:
	assert_eq(SpyLogic.spy_count_for(4), 1)
	assert_eq(SpyLogic.spy_count_for(5), 1)
	assert_eq(SpyLogic.spy_count_for(6), 2)
	assert_eq(SpyLogic.spy_count_for(8), 2)
	for n: int in [4, 5, 6, 7, 8]:
		var g: SpyLogic = _make(n)
		assert_eq(g.spies.size(), SpyLogic.spy_count_for(n), "%d players" % n)
		for s: int in g.spies:
			assert_true(s in g.players)


func test_spies_are_picked_by_the_seed() -> void:
	var seen: Dictionary = {}
	for s: int in 12:
		seen[_make(5, s).spies[0]] = true
	assert_gt(seen.size(), 1, "different seeds pick different spies")


func test_the_word_bank_loads() -> void:
	var bank: Array = SpyLogic.word_bank()
	assert_between(bank.size(), 55, 70)
	var cats: Dictionary = {}
	for row: Variant in bank:
		var d: Dictionary = row
		assert_ne(str(d.get("word", "")), "")
		assert_ne(str(d.get("hint", "")), "")
		cats[str(d.get("category", ""))] = true
	assert_eq(cats.keys().size(), 2, "places and jobs")
	var g := SpyLogic.new()
	g.setup([1, 2, 3, 4] as Array[int], SeededRng.new(1), BalanceConfig.new(), {}, {})
	assert_ne(str(g.secret.get("word", "")), "")


func test_civilians_get_the_word_spies_only_the_category() -> void:
	var g: SpyLogic = _make(6)
	for p: int in g.players:
		var priv: Dictionary = g.private_state(p)
		assert_eq(priv["category"], "Places")
		if g.is_spy(p):
			assert_eq(priv["role"], "spy")
			assert_false(priv.has("word"), "a spy never gets the word")
			assert_false(priv.has("hint"), "no hint before 60 s")
		else:
			assert_eq(priv["role"], "civilian")
			assert_eq(priv["word"], "Vault")
	assert_eq(g.private_state(99), {"role": ""})


func test_nothing_secret_in_events_or_public_state() -> void:
	var g: SpyLogic = _started(5)
	var spy: int = g.spies[0]
	_vote_out(g, _civilians(g)[0])  # a whole vote, before the end
	var texts: Array[String] = [JSON.stringify(g.get_public_state())]
	for e: Dictionary in g.drain_events():
		if e["type"] != &"spy_over":
			texts.append(JSON.stringify(e))
	g = _started(5)
	texts.append(JSON.stringify(g.get_public_state()))
	for e: Dictionary in g.drain_events():
		texts.append(JSON.stringify(e))
	for t: String in texts:
		assert_false(t.contains("Vault"), "the word leaked: " + t)
		assert_false(t.contains("Places"), "the category leaked")
		assert_false(t.contains("\"spies\":"), "the spies leaked")
	assert_false(g.get_public_state().has("spies"))
	assert_true(spy > 0)


func test_spies_get_the_hint_after_60_seconds_of_game_clock() -> void:
	var g: SpyLogic = _started(8)
	var spy: int = g.spies[0]
	g.drain_events()
	for i: int in 59:
		g.tick(1.0, 0.0)
	assert_false(g.private_state(spy).has("hint"))
	g.tick(1.05, 0.0)
	assert_eq(g.private_state(spy)["hint"], "A thick steel door")
	assert_true(&"spy_hint" in _types(g.drain_events()))
	assert_false(g.private_state(_civilians(g)[0]).has("hint"))


# --- Clue turns ----------------------------------------------------------------------------------

func test_clue_turns_go_round_the_table_in_seat_order() -> void:
	var g: SpyLogic = _started(4)
	var order: Array[int] = []
	for i: int in 4:
		var p: int = g.speaker
		order.append(p)
		assert_true(g.private_state(p)["my_turn"])
		var other: int = (p % 4) + 1
		assert_false(_clue(g, other, "steel")["ok"], "not their turn")
		assert_true(_clue(g, p, "word%d" % i)["ok"])
	var expect: Array[int] = []
	for i: int in 4:
		expect.append(g.seats[(g.start_seat + i) % 4])
	assert_eq(order, expect)
	assert_eq(g.round_index, 1, "second round")
	assert_eq(g.clues[order[0]].size(), 1)
	assert_eq(str(g.clues[order[0]][0]["text"]), "word0")
	assert_eq(g.get_public_state()["clues"][order[1]], ["word1"])


func test_a_clue_turn_times_out_with_no_clue() -> void:
	var g: SpyLogic = _started(4)
	var p: int = g.speaker
	g.drain_events()
	g.tick(SpyLogic.CLUE_TIME + 0.01, 0.0)
	var evs: Array[Dictionary] = g.drain_events()
	assert_eq(evs[0]["type"], &"spy_clue")
	assert_true(bool(evs[0]["timed_out"]))
	assert_eq(str(evs[0]["text"]), "")
	assert_ne(g.speaker, p)
	assert_eq(evs[1]["type"], &"spy_turn")


func test_clue_sanitising() -> void:
	assert_eq(SpyLogic.sanitize_clue("  steel  "), "steel")
	assert_eq(SpyLogic.sanitize_clue("big\ndoor"), "big door")
	assert_eq(SpyLogic.sanitize_clue("a\tb\r\nc"), "a b c")
	assert_eq(SpyLogic.sanitize_clue("abcdefghijklmnopqrstuvwxyz"), "abcdefghijklmnop")
	assert_eq(SpyLogic.sanitize_clue("abcdefghijklmno pq"), "abcdefghijklmno", "no trailing space")
	assert_eq(SpyLogic.sanitize_clue(null), "")
	assert_eq(SpyLogic.sanitize_clue(42), "42")
	assert_true(SpyLogic.mentions_word("the VAULT!", "Vault"))
	assert_true(SpyLogic.mentions_word("pokerroom", "Poker room"))
	assert_false(SpyLogic.mentions_word("poker", "Poker room"))
	var g: SpyLogic = _started(4)
	var p: int = g.speaker
	assert_eq(_clue(g, p, "   ")["error"], &"empty_clue")
	assert_eq(_clue(g, p, "\n\n")["error"], &"empty_clue")
	var long: String = "  a very long clue that goes on\n"
	assert_true(_clue(g, p, long)["ok"])
	assert_eq(str(g.clues[p][0]["text"]), "a very long clue")


func test_the_secret_word_itself_is_refused_for_civilians() -> void:
	var g: SpyLogic = _started(4)
	while g.is_spy(g.speaker):
		_clue(g, g.speaker, "hmm")
	var p: int = g.speaker
	assert_eq(_clue(g, p, "vault")["error"], &"is_the_word")
	assert_eq(_clue(g, p, "Big VAULT")["error"], &"is_the_word")
	assert_eq(g.speaker, p, "still their turn")
	assert_true(_clue(g, p, "steel door")["ok"])


func test_a_spy_typing_the_word_is_not_told_it_is_the_word() -> void:
	var g: SpyLogic = _started(4)
	while not g.is_spy(g.speaker):
		_clue(g, g.speaker, "door")
	assert_true(_clue(g, g.speaker, "vault")["ok"], "a refusal would give the word away")


func test_after_the_clue_rounds_the_floor_is_open() -> void:
	var g: SpyLogic = _started(4)
	for i: int in 4 * SpyLogic.CLUE_ROUNDS:
		assert_true(_clue(g, g.speaker, "c%d" % i)["ok"])
	assert_eq(g.phase, SpyLogic.Step.OPEN)
	assert_eq(g.speaker, -1)
	assert_eq(g.get_public_state()["phase"], "open")
	assert_true(g.private_state(1)["can_call"])


# --- Votes ---------------------------------------------------------------------------------------

func test_anyone_can_call_a_vote_and_everyone_in_votes() -> void:
	var g: SpyLogic = _started(5)
	var caller: int = g.players[2]
	assert_true(_call(g, caller)["ok"])
	assert_eq(g.phase, SpyLogic.Step.VOTE)
	assert_eq(_call(g, caller)["error"], &"not_now")
	assert_true(g.private_state(1)["can_vote"])
	assert_eq(_vote(g, 1, 1)["error"], &"bad_target", "not yourself")
	assert_eq(_vote(g, 1, 77)["error"], &"bad_target")
	assert_true(_vote(g, 1, 2)["ok"])
	assert_eq(_vote(g, 1, 3)["error"], &"already_voted")
	assert_eq(g.private_state(1)["voted_for"], 2)
	assert_false(g.private_state(1)["can_vote"])
	var pub: Dictionary = g.get_public_state()
	assert_eq(pub["vote"]["voted"], [1], "only THAT someone voted")
	assert_false(JSON.stringify(pub).contains("\"votes\""))


func test_vote_needs_at_least_half_and_a_unique_top() -> void:
	assert_eq(SpyLogic.votes_needed(4), 2)
	assert_eq(SpyLogic.votes_needed(5), 3)
	assert_eq(SpyLogic.votes_needed(8), 4)
	# 5 players: 2 votes for X is under half → nobody out.
	var g: SpyLogic = _started(5)
	var civ: Array[int] = _civilians(g)
	_call(g, civ[0])
	_vote(g, civ[0], civ[1])
	_vote(g, civ[2], civ[1])
	g.tick(SpyLogic.VOTE_TIME + 0.01, 0.0)
	assert_eq(g.phase, SpyLogic.Step.REVEAL)
	assert_eq(int(g.last_result["out"]), -1)
	assert_eq(str(g.last_result["why"]), "short")
	assert_eq(g.winner, "")


func test_a_tie_sends_nobody_out() -> void:
	var g: SpyLogic = _started(4)
	var a: Array[int] = g.alive()
	_call(g, a[0])
	_vote(g, a[0], a[1])
	_vote(g, a[1], a[0])
	_vote(g, a[2], a[1])
	_vote(g, a[3], a[0])
	g.tick(0.05, 0.0)
	assert_eq(g.phase, SpyLogic.Step.REVEAL, "ends early once everyone voted")
	assert_eq(int(g.last_result["out"]), -1)
	assert_eq(str(g.last_result["why"]), "tie")
	g.tick(SpyLogic.REVEAL_TIME + 0.01, 0.0)
	assert_eq(g.phase, SpyLogic.Step.CLUES, "back to the clue turns")
	assert_eq(g.rounds_planned, SpyLogic.CLUE_ROUNDS + 1, "one extra clue round")
	assert_eq(_call(g, a[0])["error"], &"cooldown")
	g.tick(SpyLogic.CALL_COOLDOWN + 0.01, 0.0)
	assert_true(_call(g, a[0])["ok"])
	g.tick(SpyLogic.VOTE_TIME + 0.01, 0.0)
	g.tick(SpyLogic.REVEAL_TIME + 0.01, 0.0)
	assert_eq(g.rounds_planned, SpyLogic.CLUE_ROUNDS + 1, "at most one extra round per game")


func test_the_vote_pauses_the_clue_turn_and_resumes_it() -> void:
	var g: SpyLogic = _started(4)
	var p: int = g.speaker
	_call(g, p)
	assert_eq(_clue(g, p, "steel")["error"], &"not_your_turn")
	g.tick(SpyLogic.VOTE_TIME + 0.01, 0.0)
	g.tick(SpyLogic.REVEAL_TIME + 0.01, 0.0)
	assert_eq(g.speaker, p)
	assert_almost_eq(g.timer, SpyLogic.CLUE_TIME, 0.01, "a fresh turn")


func test_voting_out_a_civilian_loses_the_game_for_the_group() -> void:
	var g: SpyLogic = _started(5)
	var victim: int = _civilians(g)[0]
	_vote_out(g, victim)
	assert_eq(int(g.last_result["out"]), victim)
	assert_false(bool(g.last_result["was_spy"]))
	assert_eq(g.winner, SpyLogic.SIDE_SPIES)
	assert_eq(g.reason, "wrong_vote")
	g.drain_events()
	g.tick(SpyLogic.REVEAL_TIME + 0.01, 0.0)
	var evs: Array[Dictionary] = g.drain_events()
	assert_eq(evs[0]["type"], &"spy_over")
	assert_eq(evs[0]["word"], "Vault")
	assert_eq(evs[0]["spies"], g.spies)
	var r: Array[Dictionary] = g.ranking()
	assert_true(bool(r[0]["spy"]))
	assert_eq(int(r[0]["rank"]), 1)
	for row: Dictionary in r.slice(1):
		assert_eq(int(row["rank"]), 2, "the group shares the losing rank")
		assert_eq(int(row["points"]), 0)
	g.tick(SpyLogic.OUTRO_TIME + 0.01, 0.0)
	assert_true(g.is_finished())


func test_the_group_wins_when_every_spy_is_out() -> void:
	var g: SpyLogic = _started(6)
	assert_eq(g.spies.size(), 2)
	var s1: int = g.spies[0]
	var s2: int = g.spies[1]
	_vote_out(g, s1)
	assert_true(bool(g.last_result["was_spy"]))
	assert_eq(g.winner, "", "one spy left")
	assert_eq(int(g.last_result["spies_left"]), 1)
	g.tick(SpyLogic.REVEAL_TIME + 0.01, 0.0)
	assert_false(s1 in g.alive())
	assert_eq(_call(g, s1)["error"], &"out")
	g.tick(SpyLogic.CALL_COOLDOWN + 0.01, 0.0)
	_vote_out(g, s2)
	assert_eq(g.winner, SpyLogic.SIDE_GROUP)
	assert_eq(g.reason, "caught")
	g.tick(SpyLogic.REVEAL_TIME + 0.01, 0.0)
	assert_eq(g.phase, SpyLogic.Step.OUTRO)


func test_spies_win_on_the_clock() -> void:
	var g: SpyLogic = _started(4)
	assert_almost_eq(g.clock_total, 120.0, 0.001)
	for i: int in 121:
		g.tick(1.0, 0.0)
		if g.winner != "":
			break
	assert_eq(g.winner, SpyLogic.SIDE_SPIES)
	assert_eq(g.reason, "clock")
	assert_eq(g.phase, SpyLogic.Step.OUTRO)
	assert_eq(int(g.ranking()[0]["player"]), g.spies[0])
	assert_eq(int(g.ranking()[0]["points"]), 3)


func test_a_vote_running_when_the_clock_ends_still_counts() -> void:
	var g: SpyLogic = _started(4)
	g.clock_left = 2.0
	_call(g, _civilians(g)[0])
	g.tick(3.0, 0.0)
	assert_eq(g.phase, SpyLogic.Step.VOTE)
	_vote_out_running(g, g.spies[0])
	assert_eq(g.winner, SpyLogic.SIDE_GROUP)


func _vote_out_running(g: SpyLogic, target: int) -> void:
	for p: int in g.alive():
		if p != target:
			_vote(g, p, target)
	g.tick(SpyLogic.VOTE_TIME, 0.0)


func test_the_clock_is_paused_in_the_reveal() -> void:
	var g: SpyLogic = _started(4)
	_call(g, 1)
	g.tick(SpyLogic.VOTE_TIME + 0.01, 0.0)
	var c: float = g.clock_left
	g.tick(2.0, 0.0)
	assert_eq(g.clock_left, c)


# --- Ranking -------------------------------------------------------------------------------------

func test_spies_never_voted_on_rank_above_spies_who_were() -> void:
	var g: SpyLogic = _started(6)
	var s1: int = g.spies[0]
	var s2: int = g.spies[1]
	var civ: Array[int] = _civilians(g)
	# A short vote that names s2 (not enough votes), then the clock runs out.
	_call(g, civ[0])
	_vote(g, civ[0], s2)
	g.tick(SpyLogic.VOTE_TIME + 0.01, 0.0)
	assert_eq(int(g.last_result["out"]), -1)
	g.clock_left = 0.0
	g.tick(SpyLogic.REVEAL_TIME + 0.01, 0.0)
	assert_eq(g.winner, SpyLogic.SIDE_SPIES)
	var r: Array[Dictionary] = g.ranking()
	assert_eq(int(r[0]["player"]), s1)
	assert_eq(int(r[0]["rank"]), 1)
	assert_eq(int(r[1]["player"]), s2)
	assert_eq(int(r[1]["rank"]), 2)
	assert_gt(int(r[0]["points"]), int(r[1]["points"]))
	for row: Dictionary in r.slice(2):
		assert_eq(int(row["rank"]), 3)
		assert_false(bool(row["won"]))


func test_a_caught_spy_still_wins_with_the_side_but_ranks_last_in_it() -> void:
	var g: SpyLogic = _started(6)
	var s1: int = g.spies[0]
	_vote_out(g, s1)
	g.tick(SpyLogic.REVEAL_TIME + 0.01, 0.0)
	g.tick(SpyLogic.CALL_COOLDOWN + 0.01, 0.0)
	_vote_out(g, _civilians(g)[0])
	assert_eq(g.winner, SpyLogic.SIDE_SPIES)
	g.tick(SpyLogic.REVEAL_TIME + 0.01, 0.0)
	var r: Array[Dictionary] = g.ranking()
	assert_eq(int(r[0]["player"]), g.spies[1])
	assert_eq(int(r[1]["player"]), s1)
	assert_true(bool(r[1]["won"]))
	assert_eq(int(r[1]["points"]), 1)


func test_civilians_who_voted_right_in_the_decisive_vote_rank_first() -> void:
	var g: SpyLogic = _started(5)
	var spy: int = g.spies[0]
	var civ: Array[int] = _civilians(g)
	_call(g, civ[0])
	_vote(g, civ[0], spy)
	_vote(g, civ[1], spy)
	_vote(g, civ[2], spy)
	_vote(g, civ[3], civ[0])
	_vote(g, spy, civ[0])
	g.tick(0.05, 0.0)
	assert_eq(g.winner, SpyLogic.SIDE_GROUP)
	g.tick(SpyLogic.REVEAL_TIME + 0.01, 0.0)
	var r: Array[Dictionary] = g.ranking()
	var by: Dictionary = {}
	for row: Dictionary in r:
		by[int(row["player"])] = row
	for p: int in [civ[0], civ[1], civ[2]]:
		assert_eq(int(by[p]["rank"]), 1)
		assert_eq(int(by[p]["points"]), 3)
	assert_eq(int(by[civ[3]]["rank"]), 4)
	assert_eq(int(by[civ[3]]["points"]), 2)
	assert_eq(int(by[spy]["rank"]), 5)
	assert_eq(int(by[spy]["points"]), 0)


# --- Dropouts ------------------------------------------------------------------------------------

func test_a_spy_dropping_out_counts_as_caught() -> void:
	var g: SpyLogic = _started(5)
	var spy: int = g.spies[0]
	g.remove_player(spy)
	assert_eq(g.winner, SpyLogic.SIDE_GROUP)
	assert_eq(g.reason, "spies_left")
	assert_eq(g.phase, SpyLogic.Step.OUTRO)
	for row: Dictionary in g.ranking():
		assert_ne(int(row["player"]), spy, "dropouts leave the ranking")
		assert_eq(int(row["rank"]), 1)


func test_a_civilian_dropping_out_just_leaves() -> void:
	var g: SpyLogic = _started(5)
	var civ: Array[int] = _civilians(g)
	while g.speaker != civ[0]:
		_clue(g, g.speaker, "hmm")
	g.remove_player(civ[0])
	assert_eq(g.winner, "")
	assert_ne(g.speaker, civ[0], "the turn moves on")
	assert_false(civ[0] in g.alive())
	# Mid-vote: a vote for someone who leaves is void.
	_call(g, civ[1])
	_vote(g, civ[1], civ[2])
	g.remove_player(civ[2])
	assert_false(g.votes.has(civ[1]))
	assert_true(_vote(g, civ[1], civ[3])["ok"])


func test_everyone_leaving_ends_the_game_without_crashing() -> void:
	var g: SpyLogic = _started(4)
	for p: int in [1, 2, 3, 4]:
		g.remove_player(p)
	g.tick(1.0, 0.0)
	g.tick(SpyLogic.OUTRO_TIME + 0.1, 0.0)
	assert_true(g.is_finished())
	assert_eq(g.ranking().size(), 0)


func test_two_and_three_players_do_not_crash() -> void:
	for n: int in [1, 2, 3]:
		var g: SpyLogic = _started(n)
		assert_eq(g.spies.size(), 1)
		for i: int in 400:
			if g.is_finished():
				break
			g.tick(1.0, 0.0)
		assert_true(g.is_finished(), "%d players finish" % n)
		assert_eq(g.ranking().size(), n)


# --- Snapshot and table sizes --------------------------------------------------------------------

func test_late_join_snapshot() -> void:
	var g: SpyLogic = _started(5)
	var first: int = g.speaker
	_clue(g, first, "steel")
	_call(g, g.speaker)
	_vote(g, first, g.speaker if g.speaker != first else 1)
	var st: Dictionary = g.get_public_state()
	assert_eq(st["minigame"], &"spy")
	assert_eq(st["phase"], "vote")
	assert_eq(st["seats"], g.seats)
	assert_eq(st["alive"], g.alive())
	assert_eq(st["clues"][first], ["steel"])
	assert_eq(st["vote"]["voted"], [first])
	assert_eq(int(st["spy_count"]), 1)
	assert_almost_eq(float(st["clock_total"]), 150.0, 0.01)
	assert_false(st.has("word"))
	assert_false(st.has("spies"))
	g.tick(SpyLogic.VOTE_TIME + 0.01, 0.0)
	assert_true(g.get_public_state().has("result"))
	g.clock_left = 0.0
	g.tick(SpyLogic.REVEAL_TIME + 0.01, 0.0)
	st = g.get_public_state()
	assert_eq(st["phase"], "over")
	assert_eq(st["word"], "Vault")
	assert_eq(st["spies"], g.spies)
	assert_eq((st["ranking"] as Array).size(), 5)


func test_eight_player_game_end_to_end() -> void:
	var g: SpyLogic = _started(8)
	assert_eq(g.spies.size(), 2)
	assert_almost_eq(g.clock_total, 240.0, 0.01)
	for i: int in 8:
		assert_true(_clue(g, g.speaker, "clue%d" % i)["ok"])
	assert_eq(g.round_index, 1)
	_vote_out(g, g.spies[0])
	g.tick(SpyLogic.REVEAL_TIME + 0.01, 0.0)
	g.tick(SpyLogic.CALL_COOLDOWN + 0.01, 0.0)
	_vote_out(g, g.spies[1])
	g.tick(SpyLogic.REVEAL_TIME + 0.01, 0.0)
	assert_eq(g.winner, SpyLogic.SIDE_GROUP)
	var r: Array[Dictionary] = g.ranking()
	assert_eq(r.size(), 8)
	assert_eq(int(r[0]["rank"]), 1)
	assert_false(bool(r[7]["won"]))
	assert_true(bool(r[7]["spy"]))
	g.tick(SpyLogic.OUTRO_TIME + 0.01, 0.0)
	assert_true(g.is_finished())


func test_wrong_intents_and_strangers_are_refused() -> void:
	var g: SpyLogic = _started(4)
	assert_eq(g.submit(9, {"type": &"spy_call_vote"}, 0.0)["error"], &"not_in_minigame")
	assert_eq(g.submit(1, {"type": &"nope"}, 0.0)["error"], &"bad_value")
	assert_eq(_vote(g, 1, 2)["error"], &"no_vote")
	_call(g, 1)
	assert_eq(g.submit(1, {"type": &"spy_vote", "target": "x"}, 0.0)["error"], &"bad_value")
