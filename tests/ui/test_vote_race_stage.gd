extends GutTest
## Vote Race stage fed by the real logic's events and private state (the schema contract), built
## the way the match scene builds it: AFTER the opening events (`vote_race_started`, the first
## `vote_race_round`) already went out behind the curtain. The first vote must still count; the
## reveal shows every voter's name chip on the card they picked and a vote arc between the beans on
## the 3D track; zero-vote beans hop a plate forward; the result names the winner.

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
	assert_true((stage.cards[3] as VoteRaceCard).check_badge.visible, "a check on the card you picked")
	assert_false((stage.cards[2] as VoteRaceCard).check_badge.visible)
	assert_eq(stage.status_label.text, "", "no floating 'you voted for' line")


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


# --- The 3D track ------------------------------------------------------------------------------

func _bean_x(p: int) -> float:
	return (stage.track.beans[p]["root"] as Node3D).position.x


func _on_step(p: int, step: int) -> void:
	var tr: VoteRaceTrack = stage.track
	assert_eq(int(tr.beans[p]["step"]), step, "bean %d on step %d" % [p, step])
	var want: float = tr.step_x(step) - (0.55 if step == 0 else 0.0)
	assert_almost_eq(_bean_x(p), want, 0.01, "bean %d stands on plate %d" % [p, step])


func test_track_has_a_bean_per_racer_on_the_start() -> void:
	var tr: VoteRaceTrack = stage.track
	assert_eq(stage.camera, tr.camera, "the stage films the track")
	assert_eq(tr.lanes, [1, 2, 3, 4, 5] as Array[int])
	assert_true(tr.benched.is_empty())
	var zs: Array[float] = []
	for p: int in [1, 2, 3, 4, 5]:
		_on_step(p, 0)
		var bean: AvatarVisuals = tr.beans[p]["bean"]
		assert_not_null(bean.get_node_or_null("Puppet"), "a puppet bean")
		var z: float = (tr.beans[p]["root"] as Node3D).position.z
		assert_false(z in zs, "own lane")
		zs.append(z)
	assert_eq((tr.beans[1]["tag"] as Label3D).text, "YOU")
	assert_eq((tr.beans[2]["tag"] as Label3D).text, "BO")
	assert_false(tr.cashier_lit)


func test_step_forward_hops_the_zero_vote_beans() -> void:
	(stage.cards[2] as VoteRaceCard).pressed.emit()
	_others_vote({2: 3, 3: 2, 4: 5, 5: 2})
	for p: int in [1, 2, 3, 4, 5]:
		_on_step(p, 0)  # nothing moves before the chips land
	await wait_seconds(1.2 + VoteRaceTrack.HOP_TIME)
	for p: int in [1, 4]:
		_on_step(p, 1)
	for p: int in [2, 3, 5]:
		_on_step(p, 0)


func test_skipping_the_reveal_puts_beans_in_place() -> void:
	(stage.cards[2] as VoteRaceCard).pressed.emit()
	_others_vote({2: 3, 3: 2, 4: 5, 5: 2})
	stage.skip_reveal()
	stage.track.land_all()
	_on_step(1, 1)
	_on_step(4, 1)
	_on_step(2, 0)


func test_reveal_draws_who_voted_for_whom() -> void:
	(stage.cards[2] as VoteRaceCard).pressed.emit()
	_others_vote({2: 3, 3: 2, 4: 5, 5: 2})
	var pairs: Array = []
	for a: Dictionary in stage.track.vote_arcs:
		pairs.append([a["voter"], a["target"]])
		assert_true(is_instance_valid(a["node"]))
	assert_eq(pairs, [[1, 2], [2, 3], [3, 2], [4, 5], [5, 2]])
	logic.tick(VoteRaceLogic.REVEAL_TIME + 0.01, 0.0)
	_pump()
	assert_eq(stage.track.vote_arcs.size(), 0, "the next round clears the arcs")


func test_reaching_the_cashier_is_a_win_pose() -> void:
	_make(4, {})
	for i: int in VoteRaceLogic.TRACK_LENGTH:
		_others_vote({1: 2, 2: 4, 3: 2, 4: 3})
		logic.tick(VoteRaceLogic.REVEAL_TIME + 0.01, 0.0)
		_pump()
	var tr: VoteRaceTrack = stage.track
	tr.land_all()
	_on_step(1, VoteRaceLogic.TRACK_LENGTH)
	assert_eq((tr.beans[1]["puppet"] as BeanPuppet).mood, BeanPuppet.Mood.CHEER, "cheering at the cashier")
	assert_true(tr.cashier_lit, "the window lights up")
	assert_eq((tr.beans[2]["puppet"] as BeanPuppet).mood, BeanPuppet.Mood.IDLE)
	assert_true(1 in tr.lanes, "still in their lane, at the window")


func test_two_racers_get_two_lanes() -> void:
	_make(2, {})
	var tr: VoteRaceTrack = stage.track
	assert_eq(tr.lanes.size(), 2)
	assert_ne((tr.beans[1]["root"] as Node3D).position.z, (tr.beans[2]["root"] as Node3D).position.z)


func test_eight_racers_get_eight_lanes_on_the_carpet() -> void:
	_make(8, {})
	var tr: VoteRaceTrack = stage.track
	assert_eq(tr.lanes.size(), 8)
	var half: float = 8.0 * VoteRaceTrack.LANE_W * 0.5
	var zs: Dictionary = {}
	for p: int in tr.lanes:
		var z: float = (tr.beans[p]["root"] as Node3D).position.z
		assert_lt(absf(z), half, "lane %d on the carpet" % p)
		zs[snappedf(z, 0.01)] = true
	assert_eq(zs.size(), 8, "eight different lanes")


func test_players_out_of_the_race_sit_on_the_bench() -> void:
	st.players[6] = {"id": 6, "name": "Gus", "color": 6}  # at the table, not in this race
	logic.remove_player(5)
	logic.tick(VoteRaceLogic.VOTE_TIME + 0.01, 0.0)
	logic.tick(VoteRaceLogic.REVEAL_TIME + 0.01, 0.0)
	_pump()
	stage.skip_reveal()
	var tr: VoteRaceTrack = stage.track
	assert_false(5 in tr.lanes, "Ed left the race")
	assert_true(5 in tr.benched, "Ed is on the couch")
	assert_true(6 in tr.benched, "so is the spectator")
	var bench_root: Node = (tr.beans[5]["root"] as Node3D).get_parent()
	assert_eq(bench_root.name, "Bench")
	assert_true((bench_root as Node3D).visible)
	assert_eq(tr.lanes, [1, 2, 3, 4] as Array[int])
