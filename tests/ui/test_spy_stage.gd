extends GutTest
## Spy stage fed by the real logic's events and private state (the schema contract), built the
## way the match scene builds it: AFTER `spy_started` already went out behind the curtain. The
## secret card shows the word to a civilian and only the category to a spy; the clue entry and
## the vote keys send their intents; the reveal flies the chips and stamps the verdict; the end
## screen shows the word and the winning side.

const WORDS: Array = [{"word": "Vault", "category": "Places", "hint": "A thick steel door"}]
const NAMES: Array[String] = ["Ann", "Bo", "Cy", "Di", "Ed", "Flo", "Gus", "Hal"]

var logic: SpyLogic
var stage: SpyStage
var st: ClientMatchState
var me: int = 1
var sent: Array[Dictionary] = []


func _make(n: int, as_spy: bool, start_extra: Dictionary = {}) -> void:
	sent.clear()
	if stage != null and is_instance_valid(stage):
		stage.free()
	st = ClientMatchState.new()
	var ids: Array[int] = []
	for i: int in n:
		st.players[i + 1] = {"id": i + 1, "name": NAMES[i], "color": i}
		ids.append(i + 1)
	logic = SpyLogic.new()
	logic.setup(ids, SeededRng.new(7), BalanceConfig.new(), {}, {"spy_words": WORDS})
	me = logic.spies[0] if as_spy else _civilian(0)
	logic.drain_events()
	stage = SpyStage.new()
	stage.send_intent = func(i: Dictionary) -> Dictionary:
		sent.append(i)
		return logic.submit(me, i, 0.0)
	add_child_autofree(stage)
	var start: Dictionary = {"minigame": &"spy", "players": ids}
	start.merge(start_extra)
	stage.begin(st, me, start, {})
	_pump()


func _civilian(skip: int) -> int:
	var left: int = skip
	for p: int in logic.seats:
		if not logic.is_spy(p):
			if left == 0:
				return p
			left -= 1
	return -1


func _pump() -> void:
	for ev: Dictionary in logic.drain_events():
		stage.on_event(ev)
	stage.on_private({"minigame": logic.private_state(me)})


func _key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	stage._unhandled_input(ev)


## Past the intro, then clues until it is the local player's turn.
func _to_my_turn() -> void:
	logic.tick(SpyLogic.INTRO_TIME + 0.01, 0.0)
	while logic.speaker != me:
		assert_true(logic.submit(logic.speaker, {"type": &"spy_clue", "text": "hmm"}, 0.0)["ok"])
	_pump()


# --- The secret card -----------------------------------------------------------------------------

func test_a_civilian_sees_the_word() -> void:
	_make(5, false)
	assert_eq(stage.cards.size(), 5, "a card per player")
	assert_eq(stage.secret_card.role, "civilian")
	assert_eq(stage.secret_card.big.text, "VAULT")
	assert_string_contains(stage.secret_card.line1.text, "PLACES")
	assert_eq(stage.marquee.headline.text, "WHO IS THE SPY?")


func test_a_spy_sees_only_the_category_then_the_hint() -> void:
	_make(5, true)
	assert_eq(stage.secret_card.role, "spy")
	assert_eq(stage.secret_card.big.text, "YOU ARE THE SPY")
	assert_string_contains(stage.secret_card.line1.text, "PLACES")
	for l: Label in [stage.secret_card.kicker, stage.secret_card.big, stage.secret_card.line1, stage.secret_card.line2]:
		assert_false(l.text.to_lower().contains("vault"), "no word for the spy")
	logic.tick(SpyLogic.INTRO_TIME + 0.01, 0.0)
	for i: int in 61:
		logic.tick(1.0, 0.0)
	_pump()
	assert_string_contains(stage.secret_card.line2.text, "A thick steel door")


# --- Clue turns ----------------------------------------------------------------------------------

func test_the_clue_entry_sends_the_intent() -> void:
	_make(4, false)
	_to_my_turn()
	assert_true(stage.entry.visible, "the entry shows on your turn")
	assert_true((stage.cards[me] as SpyCard).speaking)
	stage.entry.text = "  steel door "
	stage.entry.text_submitted.emit(stage.entry.text)
	assert_eq(sent.size(), 1)
	assert_eq(sent[0]["type"], &"spy_clue")
	assert_eq(sent[0]["text"], "steel door")
	_pump()
	assert_eq(stage.clues[me], ["steel door"])
	assert_false(stage.entry.visible, "hidden once the clue is in")
	assert_eq((stage.cards[me] as SpyCard).clue_texts, ["steel door"] as Array[String])


func test_the_word_itself_is_stopped_with_a_message() -> void:
	_make(4, false)
	_to_my_turn()
	stage.entry.text = "the vault"
	stage.send_clue()
	assert_eq(sent.size(), 0, "never leaves the client")
	assert_string_contains(stage.status_label.text, "secret word")
	assert_true(stage.entry.visible, "try again")


func test_other_players_clues_show_on_their_cards_in_order() -> void:
	_make(4, false)
	logic.tick(SpyLogic.INTRO_TIME + 0.01, 0.0)
	var first: int = logic.speaker
	logic.submit(first, {"type": &"spy_clue", "text": "metal"}, 0.0)
	_pump()
	assert_eq(stage.clues[first], ["metal"])
	assert_eq(stage.speaker, logic.speaker)
	assert_true((stage.cards[logic.speaker] as SpyCard).speaking)
	logic.tick(SpyLogic.CLUE_TIME + 0.01, 0.0)
	_pump()
	var card: SpyCard = stage.cards[first] as SpyCard
	assert_eq(card.clue_box.get_child_count(), 1)


# --- Votes ---------------------------------------------------------------------------------------

func test_v_calls_a_vote_and_number_keys_vote() -> void:
	_make(5, false)
	logic.tick(SpyLogic.INTRO_TIME + 0.01, 0.0)
	_pump()
	_key(KEY_V)
	assert_eq(sent.size(), 1)
	assert_eq(sent[0]["type"], &"spy_call_vote")
	_pump()
	assert_eq(stage.phase, "vote")
	assert_true(stage.can_vote_now())
	var targets: Array[int] = stage.vote_targets()
	assert_false(me in targets)
	_key(KEY_2)
	assert_eq(sent.size(), 2)
	assert_eq(sent[1]["type"], &"spy_vote")
	assert_eq(int(sent[1]["target"]), targets[1])
	assert_eq(logic.votes.get(me, -1), targets[1])
	_pump()
	assert_eq(stage.my_vote, targets[1])
	_key(KEY_1)
	assert_eq(sent.size(), 2, "one vote")


func test_clicking_a_card_votes() -> void:
	_make(5, false)
	logic.tick(SpyLogic.INTRO_TIME + 0.01, 0.0)
	logic.submit(_civilian(1), {"type": &"spy_call_vote"}, 0.0)
	_pump()
	var t: int = stage.vote_targets()[0]
	(stage.cards[t] as SpyCard).pressed.emit()
	assert_eq(logic.votes.get(me, -1), t)
	assert_true((stage.cards[me] as SpyCard).disabled, "no voting for yourself")


func test_briefing_holds_the_game_until_go() -> void:
	_make(4, false, {"briefing": 30.0})
	assert_true(stage.held)
	logic.tick(SpyLogic.INTRO_TIME + 0.01, 0.0)
	_pump()
	var c: float = stage.clock_left
	stage._process(3.0)
	assert_eq(stage.clock_left, c, "the clock waits for the start")
	stage.on_event({"type": &"minigame_go"})
	stage._process(1.0)
	assert_lt(stage.clock_left, c)


# --- Reveal and end ------------------------------------------------------------------------------

func test_the_reveal_flies_chips_and_stamps_the_spy() -> void:
	_make(4, false)
	logic.tick(SpyLogic.INTRO_TIME + 0.01, 0.0)
	var spy: int = logic.spies[0]
	logic.submit(me, {"type": &"spy_call_vote"}, 0.0)
	for p: int in logic.alive():
		logic.submit(p, {"type": &"spy_vote", "target": spy if p != spy else me}, 0.0)
	logic.tick(0.05, 0.0)
	_pump()
	assert_eq(stage.phase, "reveal")
	assert_eq((stage.cards[spy] as SpyCard).chips.size(), 3, "a chip per voter")
	stage.skip_reveal()
	assert_eq((stage.cards[spy] as SpyCard).tally, 3)
	assert_string_contains(stage.marquee.headline.text, "OUT: %s" % NAMES[spy - 1].to_upper())
	assert_string_contains(stage.marquee.subline.text, "SPY")
	assert_string_contains((stage.cards[spy] as SpyCard).stamp_text, "SPY")
	# The end screen.
	logic.tick(SpyLogic.REVEAL_TIME + 0.01, 0.0)
	_pump()
	assert_true(stage.over)
	assert_eq(stage.marquee.headline.text, "THE GROUP WINS!")
	assert_string_contains(stage.marquee.kicker.text, "VAULT")
	assert_string_contains(stage.status_label.text, "You win")
	assert_string_contains((stage.cards[me] as SpyCard).tag_label.text, "#1")


func test_a_wrong_vote_ends_with_the_spies_winning_and_the_word_for_the_spy() -> void:
	_make(4, true)
	logic.tick(SpyLogic.INTRO_TIME + 0.01, 0.0)
	var victim: int = _civilian(0)
	logic.submit(victim, {"type": &"spy_call_vote"}, 0.0)
	for p: int in logic.alive():
		logic.submit(p, {"type": &"spy_vote", "target": victim if p != victim else me}, 0.0)
	logic.tick(0.05, 0.0)
	_pump()
	stage.skip_reveal()
	assert_string_contains(stage.marquee.subline.text, "innocent")
	assert_string_contains((stage.cards[victim] as SpyCard).stamp_text, "INNOCENT")
	logic.tick(SpyLogic.REVEAL_TIME + 0.01, 0.0)
	_pump()
	assert_eq(stage.marquee.headline.text, "THE SPY WINS!")
	assert_eq(stage.secret_card.big.text, "VAULT", "the spy learns the word at the end")
	assert_eq((stage.cards[me] as SpyCard).stamp_text, "THE SPY")


func test_late_join_mid_vote_from_the_snapshot() -> void:
	_make(5, false)
	logic.tick(SpyLogic.INTRO_TIME + 0.01, 0.0)
	var first: int = logic.speaker
	logic.submit(first, {"type": &"spy_clue", "text": "steel"}, 0.0)
	logic.submit(_civilian(1), {"type": &"spy_call_vote"}, 0.0)
	logic.drain_events()
	st.minigame = logic.get_public_state()
	var late := SpyStage.new()
	late.send_intent = func(_i: Dictionary) -> Dictionary: return {"ok": true}
	add_child_autofree(late)
	late.begin(st, me, {"minigame": &"spy", "players": logic.players}, st.minigame)
	late.on_private({"minigame": logic.private_state(me)})
	assert_eq(late.phase, "vote")
	assert_eq(late.clues[first], ["steel"])
	assert_true(late.can_vote_now())
	assert_eq(late.secret_card.big.text, "VAULT")
