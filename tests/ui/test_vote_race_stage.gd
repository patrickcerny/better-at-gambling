extends GutTest
## Vote Race stage fed by the real logic's events and private state (the schema contract), built
## the way the match scene builds it: AFTER the opening events (`vote_race_started`, the first
## `vote_race_round`) already went out behind the curtain. The first vote must still count; the
## reveal shows every voter's name chip on the card they picked; the result names the winner.

var logic: VoteRaceLogic
var stage: VoteRaceStage
var st: ClientMatchState
## Intents the stage sent (instead of the network).
var sent: Array[Dictionary] = []
const NAMES: Array[String] = ["Me", "Bo", "Cy", "Di", "Ed", "Flo", "Gus", "Hal"]


func before_each() -> void:
	_make(5, {})


## A table of `n` players, local player 1. The opening events are dropped, as they are in the
## match scene where the stage only exists once the curtain has closed.
func _make(n: int, start_extra: Dictionary) -> void:
	sent.clear()
	if stage != null and is_instance_valid(stage):
		stage.free()
	st = ClientMatchState.new()
	var ids: Array[int] = []
	for i: int in n:
		st.players[i + 1] = {"id": i + 1, "name": NAMES[i], "color": i}
		ids.append(i + 1)
	logic = VoteRaceLogic.new()
	logic.setup(ids, SeededRng.new(3), BalanceConfig.new(), {}, {})
	logic.drain_events()  # sent before the stage existed
	stage = VoteRaceStage.new()
	stage.send_intent = func(i: Dictionary) -> Dictionary:
		sent.append(i)
		return logic.submit(1, i, 0.0)
	add_child_autofree(stage)
	var start: Dictionary = {"minigame": &"vote_race", "players": ids}
	start.merge(start_extra)
	stage.begin(st, 1, start, {})
	_priv()


## What the match scene does every frame.
func _priv() -> void:
	stage.on_private({"minigame": logic.private_state(1)})


func _pump() -> void:
	for ev: Dictionary in logic.drain_events():
		stage.on_event(ev)
	_priv()


func _key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	stage._unhandled_input(ev)


func _chips(p: int) -> Array[Dictionary]:
	return (stage.cards[p] as VoteRaceCard).chips


func _chip_names(p: int) -> Array[String]:
	var out: Array[String] = []
	for c: Dictionary in _chips(p):
		out.append(str((c["chip"] as Control).get_meta(&"voter")))
	return out


## Everyone else votes (the local vote already went in through the stage).
func _others_vote(ballot: Dictionary) -> void:
	for voter: int in ballot:
		assert_true(logic.submit(voter, {"target": ballot[voter]}, 0.0)["ok"], "vote %d" % voter)
	_pump()


# --- The first vote ----------------------------------------------------------------------------

func test_starts_in_the_first_vote_without_the_opening_events() -> void:
	assert_true(stage.voting, "round 1 is voting")
	assert_eq(stage.racing, [1, 2, 3, 4, 5] as Array[int], "everyone is racing")
	assert_eq(stage.cards.size(), 5, "a card per player")
	assert_eq(stage.vote_targets(), [2, 3, 4, 5] as Array[int])
	assert_true(stage.can_act())
	assert_false((stage.cards[2] as VoteRaceCard).disabled, "the other racers' cards are open")
	assert_true((stage.cards[1] as VoteRaceCard).disabled, "no voting for yourself")


func test_first_click_counts() -> void:
	(stage.cards[3] as VoteRaceCard).pressed.emit()
	assert_eq(sent.size(), 1, "one intent")
	assert_eq(sent[0]["type"], &"vote_race_vote")
	assert_eq(logic.votes.get(1, -1), 3, "the server has the first vote")
	_pump()
	assert_eq(stage.my_vote, 3)
	assert_false(stage.can_act(), "one vote per round")
	assert_true((stage.cards[3] as VoteRaceCard).is_my_vote)
	assert_string_contains(stage.status_label.text, "Cy")


func test_first_key_counts() -> void:
	_key(KEY_1)
	assert_eq(logic.votes.get(1, -1), 2, "1 = the first card you can vote for")
	_key(KEY_2)
	assert_eq(sent.size(), 1, "the second key does nothing")


func test_briefing_holds_the_vote_until_go() -> void:
	_make(5, {"briefing": 30.0})
	assert_true(stage.held)
	assert_false(stage.can_act(), "no voting under the rules screen")
	var left: float = stage.time_left
	stage._process(2.0)
	assert_eq(stage.time_left, left, "the clock waits for the start")
	stage.on_event({"type": &"minigame_go"})
	assert_true(stage.can_act())
	(stage.cards[2] as VoteRaceCard).pressed.emit()
	assert_eq(logic.votes.get(1, -1), 2)


func test_a_refused_vote_gives_the_cards_back() -> void:
	stage.send_intent = func(i: Dictionary) -> Dictionary:
		sent.append(i)
		return StationLogicBase.fail(&"too_early")
	(stage.cards[2] as VoteRaceCard).pressed.emit()
	assert_eq(stage.my_vote, -1, "not counted, so not shown as cast")
	assert_true(stage.can_act(), "vote again")


func test_an_unconfirmed_vote_is_given_back() -> void:
	stage.send_intent = func(i: Dictionary) -> Dictionary:
		sent.append(i)
		return {"ok": true, "error": &"", "pending": true}  # lost on the way
	(stage.cards[2] as VoteRaceCard).pressed.emit()
	assert_eq(stage.my_vote, 2)
	stage._process(VoteRaceStage.VOTE_CONFIRM_TIMEOUT + 0.1)
	_priv()
	assert_eq(stage.my_vote, -1)
	assert_true(stage.can_act())


func test_voted_badges_while_voting() -> void:
	_others_vote({2: 1, 3: 1})
	assert_true((stage.cards[2] as VoteRaceCard).has_voted)
	assert_false((stage.cards[4] as VoteRaceCard).has_voted)
	assert_eq(stage.voted_label.text, "2/5 VOTED")
	assert_eq(_chips(1).size(), 0, "nobody sees who voted for whom yet")


# --- The reveal --------------------------------------------------------------------------------

func test_reveal_puts_each_voters_chip_on_the_card_they_chose() -> void:
	(stage.cards[2] as VoteRaceCard).pressed.emit()
	_others_vote({2: 3, 3: 2, 4: 5, 5: 2})
	assert_false(stage.voting, "revealed")
	assert_eq(_chip_names(2), ["YOU", "Cy", "Ed"] as Array[String], "you, Cy and Ed voted for Bo")
	assert_eq(_chip_names(3), ["Bo"] as Array[String])
	assert_eq(_chip_names(5), ["Di"] as Array[String])
	assert_eq(_chips(1).size(), 0)
	assert_eq(_chips(4).size(), 0)
	var mine: Control = _chips(2)[0]["chip"]
	assert_true(bool(mine.get_meta(&"mine")), "your own chip is highlighted")
	var sb: StyleBoxFlat = mine.get_theme_stylebox(&"panel") as StyleBoxFlat
	assert_eq(sb.bg_color, Palette.player_color(0), "in your colour")
	assert_eq(sb.border_color, Palette.VIP_BURGUNDY, "rimmed in the 'that's you' wine")
	assert_almost_eq(sb.shadow_color.a, 0.9, 0.01, "and glowing gold")
	var plain: StyleBoxFlat = (_chips(2)[1]["chip"] as Control).get_theme_stylebox(&"panel") as StyleBoxFlat
	assert_ne(plain.border_color, Palette.VIP_BURGUNDY, "the others' chips are plain")
	var other: StyleBoxFlat = (_chips(2)[1]["chip"] as Control).get_theme_stylebox(&"panel") as StyleBoxFlat
	assert_eq(other.bg_color, Palette.player_color(2), "Cy's chip in Cy's colour")
	assert_eq(stage.display_steps[1], 0, "the step waits for the chips")
	stage.skip_reveal()
	assert_eq((stage.cards[2] as VoteRaceCard).tally, 3)
	assert_eq((stage.cards[2] as VoteRaceCard).tally_label.text, "3 VOTES")
	assert_eq((stage.cards[1] as VoteRaceCard).tally_label.text, "0 VOTES")
	for p: int in [1, 4]:
		assert_eq((stage.cards[p] as VoteRaceCard).stamp_text, "+1 STEP", "zero votes: %d steps" % p)
		assert_eq(stage.display_steps[p], 1)
	assert_eq((stage.cards[2] as VoteRaceCard).stamp_text, "")
	assert_eq(stage.status_label.text, "Nobody voted for you - you step forward!")


func test_chips_land_one_by_one() -> void:
	(stage.cards[2] as VoteRaceCard).pressed.emit()
	_others_vote({2: 3, 3: 2, 4: 5, 5: 2})
	await wait_process_frames(2)
	var landed: int = 0
	for c: Dictionary in _chips(2):
		landed += 1 if bool(c["landed"]) else 0
	assert_eq(landed, 0, "still flying")
	await wait_seconds(1.2)
	assert_eq((stage.cards[2] as VoteRaceCard).tally, 3, "all landed")
	assert_true(stage._reveal_paid, "and the zero-vote cards stepped")
	assert_eq(stage.display_steps[1], 1)


func test_next_round_clears_the_chips() -> void:
	(stage.cards[2] as VoteRaceCard).pressed.emit()
	_others_vote({2: 3, 3: 2, 4: 5, 5: 2})
	logic.tick(VoteRaceLogic.REVEAL_TIME + 0.01, 0.0)
	_pump()
	assert_true(stage.voting)
	assert_eq(stage.round_num, 1)
	assert_eq(_chips(2).size(), 0)
	assert_eq(stage.my_vote, -1)
	assert_true(stage.can_act(), "round 2 vote open")
	assert_eq(stage.display_steps[1], 1)


func test_late_join_mid_reveal_shows_the_chips_in_place() -> void:
	(stage.cards[2] as VoteRaceCard).pressed.emit()
	_others_vote({2: 3, 3: 2, 4: 5, 5: 2})
	var snap: Dictionary = logic.get_public_state()
	var late := VoteRaceStage.new()
	late.send_intent = func(_i: Dictionary) -> Dictionary: return {"ok": true}
	add_child_autofree(late)
	late.begin(st, 3, {"minigame": &"vote_race", "players": [1, 2, 3, 4, 5]}, snap)
	assert_false(late.voting)
	assert_eq((late.cards[2] as VoteRaceCard).chips.size(), 3)
	assert_true(bool((late.cards[2] as VoteRaceCard).chips[1]["chip"].get_meta(&"mine")), "Cy's own chip")
	assert_eq((late.cards[2] as VoteRaceCard).tally, 3)
	assert_eq(late.display_steps[1], 1)


# --- The result --------------------------------------------------------------------------------

func test_result_names_the_winner_and_ranks_every_card() -> void:
	_make(4, {})
	# Only Me gets zero votes for five rounds, then only Di: Me first, Di second.
	for i: int in VoteRaceLogic.TRACK_LENGTH:
		_others_vote({1: 2, 2: 4, 3: 2, 4: 3})
		logic.tick(VoteRaceLogic.REVEAL_TIME + 0.01, 0.0)
		_pump()
	for i: int in VoteRaceLogic.TRACK_LENGTH:
		_others_vote({2: 3, 3: 2, 4: 3})
		logic.tick(VoteRaceLogic.REVEAL_TIME + 0.01, 0.0)
		_pump()
	assert_true(logic.is_finished())
	assert_true(stage.over)
	assert_eq(stage.status_label.text, "YOU WIN!")
	assert_eq(stage.marquee.headline.text, "YOU WIN!")
	assert_eq((stage.cards[1] as VoteRaceCard).stamp_text, "WINNER")
	assert_eq((stage.cards[4] as VoteRaceCard).stamp_text, "#2")
	assert_eq((stage.cards[2] as VoteRaceCard).stamp_text, "#3")
	assert_false(stage.can_act())
	for p: int in stage.cards:
		assert_true((stage.cards[p] as VoteRaceCard).disabled)


func test_someone_else_winning() -> void:
	_make(4, {})
	for i: int in VoteRaceLogic.TRACK_LENGTH:
		_others_vote({1: 3, 2: 4, 3: 1, 4: 3})
		logic.tick(VoteRaceLogic.REVEAL_TIME + 0.01, 0.0)
		_pump()
	for i: int in VoteRaceLogic.TRACK_LENGTH:
		_others_vote({1: 3, 3: 1, 4: 3})
		logic.tick(VoteRaceLogic.REVEAL_TIME + 0.01, 0.0)
		_pump()
	assert_true(stage.over)
	assert_eq(stage.status_label.text, "Bo wins the race!")
	assert_eq(stage.marquee.headline.text, "BO WINS THE RACE!")


# --- Layout ------------------------------------------------------------------------------------

func test_eight_cards_fit_side_by_side() -> void:
	_make(8, {})
	await wait_process_frames(3)
	var rects: Array[Rect2] = []
	for p: int in stage.players_list:
		rects.append((stage.cards[p] as Control).get_global_rect())
	var screen: Rect2 = stage.root.get_global_rect()
	for i: int in rects.size():
		assert_true(screen.encloses(rects[i]), "card %d on screen" % i)
		assert_gt(rects[i].size.x, 150.0)
		for j: int in range(i + 1, rects.size()):
			assert_false(rects[i].intersects(rects[j]), "cards %d and %d overlap" % [i, j])
