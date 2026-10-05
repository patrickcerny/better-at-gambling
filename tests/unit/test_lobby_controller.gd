extends GutTest
## Lobby rules (§2.2): leadership, ready (pad or panel), countdown, settings, colors.

var lobby: LobbyController


func before_each() -> void:
	lobby = LobbyController.new()


func test_leader_is_the_longest_connected_player_and_sticks() -> void:
	lobby.join(2, 1.0)
	lobby.join(3, 2.0)
	assert_eq(lobby.leader(), 2)
	lobby.set_connected(2, false, 3.0)
	assert_eq(lobby.leader(), 3, "leader left: next longest-connected player")
	lobby.set_connected(2, true, 4.0)
	assert_eq(lobby.leader(), 3, "leadership doesn't bounce back")
	lobby.remove(3)
	assert_eq(lobby.leader(), 2)


func test_ready_countdown_start_and_cancel() -> void:
	lobby.join(1, 0.0)
	lobby.min_participants = 2
	assert_eq(lobby.tick(0.1), &"", "one player is not enough")
	lobby.join(2, 0.5)
	lobby.set_panel_ready(2, true)
	assert_false(lobby.all_ready())
	assert_true(lobby.set_on_pad(1, true))
	assert_false(lobby.set_on_pad(1, true), "no change")
	assert_eq(lobby.tick(0.1), &"countdown_started")
	lobby.set_on_pad(1, false)
	assert_eq(lobby.tick(0.1), &"countdown_cancelled", "stepping off the pad cancels")
	lobby.set_panel_ready(1, true)
	assert_eq(lobby.tick(0.1), &"countdown_started", "the panel toggle counts too")
	var result: StringName = &""
	for i: int in 40:
		result = lobby.tick(0.1)
		if result != &"":
			break
	assert_eq(result, &"start")


func test_disconnected_players_never_block() -> void:
	lobby.join(1, 0.0)
	lobby.join(2, 1.0)
	lobby.join(3, 2.0)
	lobby.set_panel_ready(1, true)
	lobby.set_panel_ready(2, true)
	assert_false(lobby.all_ready())
	lobby.set_connected(3, false, 3.0)
	assert_true(lobby.all_ready())
	assert_eq(lobby.participant_count(), 2)


func test_settings_are_leader_only_and_validated() -> void:
	lobby.join(1, 0.0)
	lobby.join(2, 1.0)
	assert_eq(lobby.set_setting(2, "duration", 5), &"not_leader")
	assert_eq(lobby.set_setting(1, "duration", 7), &"bad_value")
	assert_eq(lobby.set_setting(1, "duration", 15), &"")
	assert_eq(lobby.settings["duration"], 15)
	assert_eq(lobby.set_setting(1, "bot_difficulty", &"hard"), &"bad_key", "the game has no bots")
	assert_eq(lobby.set_setting(1, "money", 1e9), &"bad_key")
	assert_eq(lobby.set_setting(1, "items_enabled", false), &"")
	assert_false(lobby.settings["items_enabled"])


func test_free_color_prefers_the_wish() -> void:
	var taken: Array[int] = [0, 2]
	assert_eq(lobby.free_color(taken, 5), 5)
	assert_eq(lobby.free_color(taken, 2), 1, "taken wish: first free")
	assert_eq(lobby.free_color(taken, 99), 1)
