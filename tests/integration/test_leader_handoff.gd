extends GutTest
## Patrick's playtest: when the party leader leaves, another connected human leads.

var fx: ServerFixture


func before_each() -> void:
	fx = ServerFixture.new(3, {"minigames": 2, "gamble_seconds": 100.0, "seed": 2})


func after_each() -> void:
	fx.server.free()


func test_leader_leaving_in_the_lobby_hands_over() -> void:
	fx.server.open_lobby()
	var host: int = fx.server.lobby.leader()
	assert_eq(host, fx.player_ids[0])
	fx.server.player_disconnected(host)
	assert_eq(fx.server.lobby.leader(), fx.player_ids[1])
	assert_eq(int(fx.of_type(&"leader_changed").back()["player"]), fx.player_ids[1])
	assert_eq(int(fx.server.get_snapshot()["lobby"]["leader"]), fx.player_ids[1])


func test_leader_leaving_mid_match_hands_over_and_new_leader_can_act() -> void:
	fx.server.start_match()
	fx.run(3.1)
	fx.server.player_disconnected(fx.player_ids[0])
	assert_eq(fx.server.lobby.leader(), fx.player_ids[1])
	fx.server.player_disconnected(fx.player_ids[1])
	assert_eq(fx.server.lobby.leader(), fx.player_ids[2])
	fx.server.player_reconnected(fx.player_ids[0])
	assert_eq(fx.server.lobby.leader(), fx.player_ids[2], "leadership sticks with the new leader")


## Old fix batch: "the new host's clicks are ignored after Play Again". The leader leaves, the new
## leader takes the room back to the lobby and runs it from there like the first one did.
func test_new_leader_runs_play_again_in_the_same_room() -> void:
	fx.server.open_lobby()
	var a: int = fx.player_ids[0]
	var b: int = fx.player_ids[1]
	fx.server.start_match()
	fx.run(3.1)
	fx.server.player_disconnected(a)
	fx.server.run_to_end()
	assert_eq(fx.server.phases.phase, Phase.Id.RESULTS)
	assert_eq(int(fx.server.get_snapshot()["lobby"]["leader"]), b, "the results screen shows the new leader")
	assert_eq(fx.intent(a, &"return_to_lobby")["error"], &"not_leader")
	assert_true(fx.intent(b, &"return_to_lobby")["ok"], "the new leader's Play Again is taken")
	assert_eq(fx.server.phases.phase, Phase.Id.LOBBY)
	assert_eq(int(fx.server.get_snapshot()["lobby"]["leader"]), b, "and stays the leader in the lobby")
	assert_true(fx.intent(b, &"lobby_setting", {"key": "minigames", "value": 3})["ok"], "the new leader's settings clicks count")
	assert_eq(int(fx.server.lobby.settings["minigames"]), 3)
	fx.server.player_reconnected(a)
	assert_eq(fx.intent(a, &"lobby_setting", {"key": "minigames", "value": 2})["error"], &"not_leader")
	assert_eq(fx.server.lobby.leader(), b)


## The lobby is not on the match clock: a leader trying settings for a while is never locked out.
func test_lobby_clicks_keep_counting_while_the_party_waits() -> void:
	fx.server.open_lobby()
	var a: int = fx.player_ids[0]
	for i: int in 60:
		fx.server.advance(0.5)
		assert_true(fx.intent(a, &"lobby_setting", {"key": "minigames", "value": 2 + i % 2})["ok"], "click %d counts" % i)
		assert_eq(int(fx.server.lobby.settings["minigames"]), 2 + i % 2)
