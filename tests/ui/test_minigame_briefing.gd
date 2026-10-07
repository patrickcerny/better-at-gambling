extends GutTest
## The rules screen before a minigame (0.8.13): shows name, rules, who is ready and the countdown
## from the `minigame_started` event or a late-join snapshot, follows `minigame_ready` events and
## goes away on `minigame_go`.

var st: ClientMatchState
var briefing: MinigameBriefing


func before_each() -> void:
	st = ClientMatchState.new()
	st.players = {1: {"id": 1, "name": "Me", "color": 0}, 2: {"id": 2, "name": "Bo", "color": 1}}
	briefing = MinigameBriefing.new()
	add_child_autofree(briefing)


func test_shows_rules_ready_states_and_countdown_from_the_start_event() -> void:
	briefing.open({"minigame": &"lonely_number", "name": "Lonely Number", "rules": "Pick the highest number nobody else picks.", "players": [1, 2], "briefing": 30.0}, st, 1)
	assert_eq(briefing.title_label.text, "Lonely Number")
	assert_string_contains(briefing.rules_label.text, "highest number")
	assert_eq(briefing.rows.size(), 2)
	assert_string_contains((briefing.rows[1] as Label).text, "…  Me")
	assert_string_contains((briefing.rows[2] as Label).text, "…  Bo")
	assert_eq(briefing.countdown_label.text, "Starts in 30 s")
	assert_false(briefing.ready_button.disabled)
	briefing._process(2.5)
	assert_eq(briefing.countdown_label.text, "Starts in 28 s")
	briefing.on_event({"type": &"minigame_ready", "player": 2, "ready": [2]})
	assert_string_contains((briefing.rows[2] as Label).text, "✓  Bo")
	assert_string_contains((briefing.rows[1] as Label).text, "…  Me")
	assert_false(briefing.ready_button.disabled, "we have not clicked yet")
	# Without a connection the click sends nothing and the button stays live.
	briefing.press_ready()
	assert_false(briefing.sent)


func test_snapshot_form_and_go() -> void:
	briefing.open({"minigame": &"lonely_number", "players": [1, 2], "briefing": {"left": 12.4, "ready": [1]}}, st, 1)
	assert_eq(briefing.title_label.text, Registry.minigames[&"lonely_number"].display_name, "name from the definition")
	assert_eq(briefing.rules_label.text, Registry.minigames[&"lonely_number"].rules_text)
	assert_eq(briefing.countdown_label.text, "Starts in 13 s")
	assert_true(briefing.ready_button.disabled, "we were already ready before we rejoined")
	assert_string_contains(briefing.ready_button.text, "WAITING")
	briefing.on_event({"type": &"minigame_go"})
	assert_true(briefing.is_queued_for_deletion())
